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

## Metres between candidate points. Finer means denser and slower.
const SAMPLE_STEP := 1.0

## World size of each placeholder sprite, metres. Real definitions will carry
## this, derived from resolution and the profile's pixel density.
const PLACEHOLDER_SIZE := {
	"grass_tuft_01": 0.55,
	"flower_daisy_01": 0.45,
	"rock_small_01": 0.40,
}

var terrain: CozyTerrainSystem = null
var assets: CozyAssetLibrary = null

## World positions of built things — see CozyBiome.classify for why this is a
## list of points rather than of nodes.
var building_points: Array = []
var world_seed := 20260911

var _meshes: Dictionary = {}       ## asset_id -> MultiMeshInstance3D
var _counts: Dictionary = {}       ## rule_id  -> instances placed
var _candidates := 0


func setup(p_terrain: CozyTerrainSystem, p_assets: CozyAssetLibrary,
		p_seed := 20260911) -> void:
	terrain = p_terrain
	assets = p_assets
	world_seed = p_seed


## Rebuild the whole field. Returns per-rule instance counts.
##
## Full rebuild rather than incremental: the field is one pass over the terrain
## grid, and unlike rooms or nav grids it has no cheap way to know which cells
## an edit affected. Chunk-level dirtiness would be the refinement; noted as
## debt rather than pretended.
func rebuild() -> Dictionary:
	for c in get_children():
		c.queue_free()
	_meshes.clear()
	_counts.clear()
	_candidates = 0

	if terrain == null:
		return _counts

	var by_asset := {}     ## asset_id -> Array of {pos, scale}
	var rule_ids := CozyScatterRule.ids()

	var extent := terrain.chunk_extent()
	var origin := terrain.origin
	var x := origin.x
	while x < origin.x + terrain.width_m:
		var z := origin.y
		while z < origin.y + terrain.depth_m:
			_candidates += 1
			var material := terrain.material_id_at(x, z)
			if material != "water":
				var biome := CozyBiome.classify(terrain, building_points, x, z)
				var near_building := biome == CozyBiome.VILLAGE

				# ChunkCoord + local cell, per doc E.21's seed hierarchy.
				var ccoord := Vector2i(int(floor((x - origin.x) / extent)),
					int(floor((z - origin.y) / extent)))
				var lx := int(floor((x - origin.x) / SAMPLE_STEP))
				var lz := int(floor((z - origin.y) / SAMPLE_STEP))

				for rule_id in rule_ids:
					var seed_val := CozyArtSeed.for_cell(world_seed, ccoord, lx, lz, rule_id)
					if not CozyScatterRule.spawns(rule_id, biome, material,
							near_building, seed_val):
						continue
					var r := CozyScatterRule.get_rule(rule_id)
					var asset_id: String = r["asset_id"]
					var sc := CozyArtSeed.range_f(seed_val ^ 0x5bf03635,
						float(r["scale"][0]), float(r["scale"][1]))
					if not by_asset.has(asset_id):
						by_asset[asset_id] = []
					by_asset[asset_id].append({"pos": Vector3(x, 0.0, z), "scale": sc})
					_counts[rule_id] = int(_counts.get(rule_id, 0)) + 1
			z += SAMPLE_STEP
		x += SAMPLE_STEP

	for asset_id in by_asset:
		_build_multimesh(asset_id, by_asset[asset_id])

	return _counts


func _build_multimesh(asset_id: String, items: Array) -> void:
	if items.is_empty():
		return

	var world_size := float(PLACEHOLDER_SIZE.get(asset_id, 0.5))

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
	mmi.material_override = CozyPixelArt.make_billboard_material(
		_texture_for(asset_id))
	add_child(mmi)
	_meshes[asset_id] = mmi


## Placeholder textures, keyed by asset id. When real art arrives this becomes a
## lookup into the asset library and nothing else in the system changes.
func _texture_for(asset_id: String) -> Texture2D:
	match asset_id:
		"flower_daisy_01":
			return CozyPixelArt.make_flower_texture()
		"rock_small_01":
			return CozyPixelArt.make_pebble_texture()
		_:
			return CozyPixelArt.make_grass_tuft_texture()


# ---------------------------------------------------------------- queries

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


## A stable fingerprint of every instance position, for the determinism check.
##
## Counts alone are NOT enough. The wall assembler taught that lesson: a layout
## can be reordered while keeping the same total, and a count comparison would
## wave it through.
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
