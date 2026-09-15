class_name CozyVegetationScatter
extends Node3D
## Vegetation scatter (V2.1 doc E.20 / 58.4 / 58.5 / 61).
##
## The doc's rule for ground plants is not to model every blade:
##
##     "地面植物不要制作成'每一根草的模型'"
##
## Instead a handful of atoms plus a rule decide what appears where. The rules
## live in `CozyScatterRule`, biomes come from `CozyBiome`, and the roll is
## deterministic through `CozyArtSeed` so the field survives a save and reload.
##
## INSTANCING. Every instance of one asset goes into a single MultiMesh, so a
## field of a few thousand tufts is ONE draw call rather than a few thousand.
## Doc #61 is explicit that this is not optional:
##
##     "禁止默认采用：10000 Objects = 10000 expensive independent draw calls"
##
## The sprites are procedural placeholders (doc 58.1). Replacing them with real
## art changes the texture map below and nothing else.
##
## INCREMENTAL REBUILD (debt 6). The field is sampled per CHUNK and the samples
## are kept, so a terrain edit resamples only the chunks it touched. Sampling is
## the expensive half — one candidate per metre over the whole field — and it was
## being redone in full for a brush stroke that moved a handful of cells.

## Metres between candidate points. Finer means denser and slower.
##
## Chunk sampling assumes this divides the chunk extent exactly; `_can_sample_per_chunk`
## checks it and `rebuild_dirty` falls back to a full pass rather than answer
## wrongly.
const SAMPLE_STEP := 1.0

## How far a plant may sit from its square's lattice point, in metres.
##
## STRICTLY LESS THAN `SAMPLE_STEP / 2`, and that is a correctness bound rather
## than a taste one: every plant grown by a square has to stay inside that
## square, or the per-chunk split puts the plant in one chunk while its square is
## in another — and the incremental rebuild, which re-samples only the dirty
## chunks, would then drop it or duplicate it. `_check_scatter`'s
## "incremental == full" assertion is what would catch that, but only by
## accident, so the bound is written here instead.
const JITTER := SAMPLE_STEP * 0.45

## World size of each GENERATED sprite, metres.
##
## THE HAND-PICKED NUMBERS ARE THE DEBT, and the header above has said the right
## thing since before there was a reason to act on it. An asset's world size
## follows from its own pixels (see `_world_size`), so every entry here describes
## a placeholder that is NOT yet drawn at the profile's density: 16 or 24 px
## stretched over 0.4 to 2.4 m. `_check_scatter` prints how far off each one is.
const PLACEHOLDER_SIZE := {
	"grass_tuft_01": 0.55,
	"flower_daisy_01": 0.45,
	"rock_small_01": 0.40,
	"tree_oak_01": 2.40,
}

## How much each kind of plant moves in the wind, 0..1.
##
## A ROCK DOES NOT SWAY. It is drawn by the same material as the grass, because
## one shader for the whole layer is what keeps the wind field shared between
## neighbours and the code short — but a rock that bends reads as a bug rather
## than as wind, so the strength is per-asset and the rock's is zero. A tree
## moves a little: enough that a gust crosses the forest, not enough to look like
## grass.
const WIND_STRENGTH := {
	"grass_tuft_01": 1.0,
	"flower_daisy_01": 1.0,
	"rock_small_01": 0.0,
	"tree_oak_01": 0.30,
}

## Draw vegetation with the moving-billboard shader
## (`shaders/vegetation.gdshader`) instead of Godot's built-in fixed-Y billboard.
##
## A CONSTANT RATHER THAN A DELETED BRANCH, the same shape as `HOUSE_ENABLED` in
## `main.gd`: the built-in path is what this one has to match on everything
## EXCEPT motion, and a comparison is how that gets checked. It is also the only
## way to tell which half of a wrong picture is the shader.
const USE_VEGETATION_SHADER := true

var terrain: CozyTerrainSystem = null
var assets: CozyAssetLibrary = null

## World positions of built things — see CozyBiome.classify for why this is a
## list of points rather than of nodes.
var building_points: Array = []
var world_seed := 20260911

var _meshes: Dictionary = {}       ## asset_id -> MultiMeshInstance3D
var _counts: Dictionary = {}       ## rule_id  -> instances placed
var _candidates := 0

## asset_id -> the world size its quad was built at, so the self-check can ask
## how far each sprite is from the profile's pixel density without rebuilding
## anything. What is DRAWN is the thing to measure, not what the table says.
var _world_sizes: Dictionary = {}

## Lowest ground height any sampled point had. Exposed so a check can prove the
## field follows the terrain's HEIGHT and not just its material — plants are
## placed at the sample point's own height (debt 6).
var lowest_y := 0.0

## Phase timings from the last rebuild, milliseconds. Split because the two
## halves have completely different fixes — sampling is arithmetic, mesh
## building is GPU buffer upload — and guessing which one dominates is how
## optimisation turns into superstition.
var sample_ms := 0.0
var build_ms := 0.0

## Per-chunk samples, keyed by chunk coord. Each entry is
## `{assets: {asset_id -> items}, counts: {rule_id -> n}, cand: int, low: float}`.
##
## Everything derived — `_counts`, `_candidates`, `lowest_y`, the meshes — is
## recomputed from THIS by `_finish()`. Keeping one source of truth is what makes
## an incremental rebuild provably identical to a full one instead of merely
## intended to be.
var _by_chunk: Dictionary = {}

## Resolved once per pass. The inner loop runs per candidate per rule, and
## re-doing the dictionary lookups there is pure waste.
var _rules: Array = []
var _any_water := false


func setup(p_terrain: CozyTerrainSystem, p_assets: CozyAssetLibrary,
		p_seed := 20260911) -> void:
	terrain = p_terrain
	assets = p_assets
	world_seed = p_seed


## Rebuild the whole field. Returns per-rule instance counts.
func rebuild() -> Dictionary:
	var t0 := float(Time.get_ticks_usec()) / 1000.0
	_by_chunk.clear()
	_prepare()
	if terrain != null:
		for coord in _sorted_coords():
			_by_chunk[coord] = _sample_chunk(coord)
	sample_ms = float(Time.get_ticks_usec()) / 1000.0 - t0
	return _finish()


## Resample only the chunks an edit touched (doc #33), then rebuild the meshes.
##
## Rebuilding EVERY mesh afterwards rather than tracking which asset each chunk
## fed is deliberate: mesh building is a few milliseconds against sampling's
## hundred-plus, so the whole saving is in resampling, and a chunk-to-asset index
## would be one more thing to keep correct for the remainder.
##
## Chunks already in `_by_chunk` keep their POSITION in it when replaced, so the
## instance order — and therefore `fingerprint()` — is the same as a full
## rebuild's. That equality is asserted rather than assumed.
func rebuild_dirty(coords: Array) -> Dictionary:
	if not _can_sample_per_chunk():
		return rebuild()

	var t0 := float(Time.get_ticks_usec()) / 1000.0
	_prepare()
	for coord in coords:
		if terrain.chunks.has(coord):
			_by_chunk[coord] = _sample_chunk(coord)
	sample_ms = float(Time.get_ticks_usec()) / 1000.0 - t0
	return _finish()


## A fixed order, so the mesh instance order is reproducible run to run.
func _sorted_coords() -> Array:
	var coords: Array = terrain.chunks.keys()
	coords.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
		return a.x < b.x if a.x != b.x else a.y < b.y)
	return coords


func _prepare() -> void:
	_any_water = false
	if terrain != null:
		for coord in terrain.chunks:
			if (terrain.chunks[coord] as CozyTerrainChunk).has_water:
				_any_water = true
				break
	_rules.clear()
	for rule_id in CozyScatterRule.ids():
		var res := CozyScatterRule.resolve(rule_id)
		if not res.is_empty():
			_rules.append(res)


func _steps_per_chunk() -> int:
	return maxi(1, int(round(terrain.chunk_extent() / SAMPLE_STEP)))


## Chunk sampling reproduces the global grid only when a chunk holds a whole
## number of sample steps. It does at 16 m / 1 m, and if that ever stops being
## true the incremental path must not quietly place a different field.
func _can_sample_per_chunk() -> bool:
	if terrain == null or _rules.is_empty():
		return false
	var extent := terrain.chunk_extent()
	return absf(float(_steps_per_chunk()) * SAMPLE_STEP - extent) < 0.0001


## Sample one chunk onto the same grid the whole-field pass used to walk.
##
## Local indices are computed by COUNTING, not by dividing world coordinates:
## `origin.x + 16.0 + 1.0` and `origin.x + 17.0` can differ in the last bit, and
## a sample point that lands in the neighbouring cell would roll a different seed
## and grow a different plant.
func _sample_chunk(coord: Vector2i) -> Dictionary:
	var entry := {"assets": {}, "counts": {}, "cand": 0, "low": 0.0}
	if not _can_sample_per_chunk():
		return entry

	var assets_by_id: Dictionary = entry["assets"]
	var counts: Dictionary = entry["counts"]
	var extent := terrain.chunk_extent()
	var steps := _steps_per_chunk()
	var x0 := terrain.origin.x + float(coord.x) * extent
	var z0 := terrain.origin.y + float(coord.y) * extent

	for ix in steps:
		var x := x0 + float(ix) * SAMPLE_STEP
		for iz in steps:
			var z := z0 + float(iz) * SAMPLE_STEP
			entry["cand"] = int(entry["cand"]) + 1
			var material := terrain.material_id_at(x, z)
			if material == "water":
				continue
			var biome := CozyBiome.classify(terrain, building_points, x, z,
				world_seed, _any_water)
			var near_building := biome == CozyBiome.VILLAGE
			# Global sample index, per doc E.21's seed hierarchy.
			var lx := int(coord.x) * steps + ix
			var lz := int(coord.y) * steps + iz

			for res in _rules:
				var rule_id: String = res["id"]
				var seed_val := CozyArtSeed.for_cell(world_seed, coord, lx, lz, rule_id)
				if not CozyScatterRule.spawns_resolved(res, biome, material,
						near_building, seed_val):
					continue
				var asset_id: String = res["asset_id"]
				if not assets_by_id.has(asset_id):
					assets_by_id[asset_id] = []
				# HOW MANY of it this square grows (see `CozyScatterRule`). The
				# roll is derived from the SAME seed the spawn test used, so a
				# square that passes still passes after a reload and the cluster
				# is the same size every time.
				var lo: int = res["cluster_lo"]
				var span: int = maxi(1, int(res["cluster_hi"]) - lo + 1)
				var n := lo + CozyArtSeed.pick_index(seed_val ^ 0x2545f491, span)
				for k in n:
					# A fresh stream per plant, from the square's own seed.
					var s := seed_val ^ (k * 0x9e3779b9)
					# JITTERED INSIDE ITS OWN SQUARE, not dropped on the lattice
					# point. This is most of what turns "a grid of plants" into
					# "a patch of grass", and it is why density is bought with
					# clusters rather than with a finer lattice — a finer lattice
					# is still a lattice. `JITTER < SAMPLE_STEP / 2` keeps every
					# plant inside the square that grew it, so the per-chunk split
					# and the incremental rebuild stay correct.
					var bx := x + CozyArtSeed.range_f(s ^ 0x1b873593, -JITTER, JITTER)
					var bz := z + CozyArtSeed.range_f(s ^ 0xcc9e2d51, -JITTER, JITTER)
					var sc := CozyArtSeed.range_f(s ^ 0x5bf03635,
						res["scale_lo"], res["scale_hi"])
					# On the ground, not at y=0 (debt 6). The field carries a
					# height and DIG/FILL move it, so a fixed y would leave plants
					# hanging over a hole or sunk in a mound — and it was the
					# HEIGHT half of that debt, not the material half, that was
					# ever wrong: this loop already re-read the terrain on every
					# rebuild. Read PER PLANT, because a jittered plant is not
					# standing where the square's own sample was taken.
					var gy := terrain.height_at(bx, bz)
					entry["low"] = minf(float(entry["low"]), gy)
					assets_by_id[asset_id].append({"pos": Vector3(bx, gy, bz), "scale": sc})
				counts[rule_id] = int(counts.get(rule_id, 0)) + n
	return entry


## Roll the per-chunk samples up into counts and meshes. Everything the rest of
## the system reads is produced here, from `_by_chunk` alone.
func _finish() -> Dictionary:
	_counts.clear()
	_candidates = 0
	lowest_y = 0.0

	var t_build := Time.get_ticks_usec()
	var by_asset := {}     ## asset_id -> Array of {pos, scale}
	for coord in _by_chunk:
		var e: Dictionary = _by_chunk[coord]
		_candidates += int(e["cand"])
		lowest_y = minf(lowest_y, float(e["low"]))
		var counts: Dictionary = e["counts"]
		for rule_id in counts:
			_counts[rule_id] = int(_counts.get(rule_id, 0)) + int(counts[rule_id])
		var assets_by_id: Dictionary = e["assets"]
		for asset_id in assets_by_id:
			if not by_asset.has(asset_id):
				by_asset[asset_id] = []
			by_asset[asset_id].append_array(assets_by_id[asset_id])

	for c in get_children():
		c.queue_free()
	_meshes.clear()
	for asset_id in by_asset:
		_build_multimesh(asset_id, by_asset[asset_id])

	build_ms = float(Time.get_ticks_usec() - t_build) / 1000.0
	return _counts


func _build_multimesh(asset_id: String, items: Array) -> void:
	if items.is_empty():
		return

	var tex := _texture_for(asset_id)
	var world_size := _world_size(asset_id, tex)

	var quad := QuadMesh.new()
	quad.size = Vector2(world_size, world_size)

	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = quad
	mm.instance_count = items.size()

	for i in items.size():
		var p: Vector3 = items[i]["pos"]
		var s: float = items[i]["scale"]
		# The quad is centred; lift by half its height so the sprite STANDS on
		# the ground rather than sinking through it (anchor rule, ART_PROFILE).
		var h := world_size * s * 0.5
		mm.set_instance_transform(i, Transform3D(
			Basis().scaled(Vector3(s, s, s)), p + Vector3(0.0, h, 0.0)))

	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	_world_sizes[asset_id] = world_size
	mmi.material_override = _material_for(asset_id, world_size, tex)
	add_child(mmi)
	_meshes[asset_id] = mmi


## How big this sprite is in the world.
##
## A REAL asset is sized by its own pixels at the profile's density, because that
## is what the density IS — 24 px at 60 px/m is 0.40 m, and drawing it over 0.55 m
## magnifies every pixel by 1.38 and turns a blade of grass into a bush.
##
## A PLACEHOLDER keeps its hand-picked `PLACEHOLDER_SIZE`, and that is a debt
## rather than a design: the generated sprites are 16 or 24 px, so sizing THEM by
## density would make a 0.27 m tree. `_check_scatter` prints how far each one is
## from the profile, so the list is a measured number rather than a complaint.
func _world_size(asset_id: String, tex: Texture2D) -> float:
	var real_path := String(REAL_TEXTURES.get(asset_id, ""))
	if real_path != "" and tex != null and ResourceLoader.exists(real_path):
		return CozyPixelArt.metres_for_pixels(float(tex.get_width()))
	return float(PLACEHOLDER_SIZE.get(asset_id, 0.5))


## The material a kind of plant is drawn with.
##
## The half-height handed to the shader is EXACTLY the lift applied above
## (`world_size * s * 0.5` at scale 1) — the shader rotates each quad about that
## point, so if the two numbers disagree the plant spins about something that is
## not where it meets the ground, and it does so by an amount that grows with the
## distance from the wrong pivot. One number, read twice, in this file.
func _material_for(asset_id: String, world_size: float, tex: Texture2D) -> Material:
	if not USE_VEGETATION_SHADER:
		return CozyPixelArt.make_billboard_material(tex)
	var silhouette := bool(SILHOUETTE.get(asset_id, false))
	var size: Vector2 = SPRITE_SIZE.get(asset_id, Vector2.ONE)
	return CozyPixelArt.make_vegetation_material(
		tex, world_size * 0.5,
		float(WIND_STRENGTH.get(asset_id, 1.0)),
		silhouette,
		Vector2(1.0 / size.x, 1.0 / size.y),
		# The tint IS the plant's colour for a silhouette, and is unused for a
		# painted sprite — the shader returns the texture's own colour there.
		CozyPixelArt.GREEN_BASE if silhouette else Color.WHITE)


## Real sprites, by asset id, as EXPLICIT PATHS.
##
## Not a directory walk, and the reason is written down in
## `tests/unit/test_asset_manifest.gd`: `DirAccess` does not work in an exported
## build, which is why `CozyAssetLibrary` has a manifest at all. A scatter that
## scanned `assets/art` at runtime would work in the editor and ship empty.
##
## A path here is a PROMISE THAT CAN BE BROKEN, so `_texture_for` checks
## `ResourceLoader.exists` and falls back to the generated sprite. Deleting a
## file then costs a placeholder rather than a crash — and never a silently
## invisible field, because the fallback is a visible tuft.
const REAL_TEXTURES := {
	"grass_tuft_01": "res://assets/art/pixel/environment/grassleaf.png",
}

## Which sprites are SILHOUETTES — white, one colour, tinted by the shader — and
## which carry their own colours. See `shaders/vegetation.gdshader`.
##
## A tree is painted: it has a brown trunk and a green canopy and no single tint
## makes both. The grass is a silhouette, which is what lets the shader decide
## what colour this hillside is (see `docs/CREDITS.md`).
const SILHOUETTE := {
	"grass_tuft_01": true,
	"flower_daisy_01": false,
	"rock_small_01": false,
	"tree_oak_01": false,
}

## Sprite pixel dimensions, for the shader's one-texel outline pass. Only
## silhouette sprites need it — a painted sprite has its outline baked in.
const SPRITE_SIZE := {
	"grass_tuft_01": Vector2(24, 24),
}


## Placeholder sprites, keyed by asset id, for anything with no real file yet.
func _placeholder_texture(asset_id: String) -> Texture2D:
	match asset_id:
		"flower_daisy_01":
			return CozyPixelArt.make_flower_texture()
		"rock_small_01":
			return CozyPixelArt.make_pebble_texture()
		"tree_oak_01":
			return CozyPixelArt.make_tree_texture()
		_:
			return CozyPixelArt.make_grass_tuft_texture()


## The real sprite if there is one, the generated one otherwise.
func _texture_for(asset_id: String) -> Texture2D:
	var path := String(REAL_TEXTURES.get(asset_id, ""))
	if path != "" and ResourceLoader.exists(path):
		return load(path)
	return _placeholder_texture(asset_id)


# ---------------------------------------------------------------- queries

## The world size a kind of plant was actually built at, metres.
func world_size_of(asset_id: String) -> float:
	return float(_world_sizes.get(asset_id, 0.0))


## The sprite a kind of plant is drawn with.
func texture_of(asset_id: String) -> Texture2D:
	var mmi: MultiMeshInstance3D = _meshes.get(asset_id)
	if mmi == null:
		return null
	var mat := mmi.material_override
	if mat is ShaderMaterial:
		return (mat as ShaderMaterial).get_shader_parameter("albedo_texture")
	if mat is StandardMaterial3D:
		return (mat as StandardMaterial3D).albedo_texture
	return null


## The material a kind of plant is actually drawn with, or null if that kind is
## not in this field. For the self-check: a material is the one part of the
## scatter that renders rather than places, and until this existed nothing
## asserted anything about it.
func material_of(asset_id: String) -> Material:
	var mmi: MultiMeshInstance3D = _meshes.get(asset_id)
	return mmi.material_override if mmi != null else null


## The kinds of plant this field actually built, sorted.
func asset_ids() -> Array:
	var out: Array = _meshes.keys()
	out.sort()
	return out


func instance_count(rule_id: String) -> int:
	return int(_counts.get(rule_id, 0))


func total_instances() -> int:
	var n := 0
	for k in _counts:
		n += int(_counts[k])
	return n


## How many draw calls the field costs. Must stay small — this is the number
## doc #61 is about.
func mesh_count() -> int:
	return _meshes.size()


func sample_candidates() -> int:
	return _candidates


func cached_chunk_count() -> int:
	return _by_chunk.size()


## A stable fingerprint of every instance position, for the determinism check.
##
## Counts alone are NOT enough. The wall assembler taught that lesson: a layout
## can be reordered while keeping the same total, and a count comparison would
## wave it through.
##
## It hashes POSITIONS, which is what makes it the right check for the incremental
## rebuild as well: an incremental pass that placed the same plants in the same
## places gives the same number, and one that quietly dropped or moved any gives a
## different one.
func fingerprint() -> int:
	var h := 0
	var ids: Array = _meshes.keys()
	ids.sort()
	for id in ids:
		h = (h * 31 + hash(id)) & 0x7FFFFFFF
		var mmi: MultiMeshInstance3D = _meshes[id]
		var mm := mmi.multimesh
		for i in mm.instance_count:
			var t := mm.get_instance_transform(i)
			h = (h * 31 + hash(t.origin)) & 0x7FFFFFFF
	return h


func describe() -> String:
	var parts: Array[String] = []
	var keys: Array = _counts.keys()
	keys.sort()
	for k in keys:
		parts.append("%s=%d" % [k, int(_counts[k])])
	return "%d instance(s) in %d mesh(es) from %d candidate(s): %s" % [
		total_instances(), mesh_count(), _candidates,
		", ".join(parts) if not parts.is_empty() else "none"]
