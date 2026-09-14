class_name CozyTerrainRenderer
extends Node3D
## Draws the terrain field as pixel art (V2.1 doc #55).
##
## ONE TEXEL PER SIMULATION CELL. That is the project's whole idea applied to
## the ground: the cells are the truth, and the picture is a rendering of them
## — "3D solves space, pixel art solves looks".
##
## The alternative, one mesh quad per cell, would be 65,536 quads for a modest
## 64x64 m field. Doc #61 forbids exactly that:
##
##     "禁止 10000 Objects = 10000 expensive independent draw calls"
##
## so a chunk becomes ONE quad wearing ONE small texture. Rebuilding a chunk is
## then an image upload, which is cheap enough to do while the player drags.
##
## Height IS displaced now (debt 2). Each chunk is a grid of vertices — one per
## cell CORNER — pushed to `CozyTerrainChunk.corner_height`, which is what turns
## DIG and FILL from numbers in the field into ground you can see and stand in.
##
## Collision is a trimesh built from the very same triangles. Two meshes sampled
## separately would eventually disagree, and a disagreement here is a player
## standing inside a hill or floating over a hole.

const CELLS := CozyTerrainChunk.CELLS

const CELL_SIZE := CozyTerrainChunk.CELL_SIZE

## How many metres one material texture covers before repeating. At 16 texels and
## one metre that is a 16 px/m ground, which is the project's own pixel unit.
const TEXTURE_METRES := 1.0

## How much the per-cell grain moves the albedo. Narrow on purpose.
const GRAIN := 0.09

## How far a dual-grid region's corner is cut back where its boundary turns, as a
## fraction of a cell. Set from here rather than left to the shader, for the same
## reason every other uniform is: a value that lives only inside a shader is a
## value this side cannot assert about and cannot switch off in a hurry.
const ROUNDING := 0.28

## The chunk's placement height. Vertices are displaced around it, so flat
## terrain renders exactly at this y and dug terrain below it.
const SURFACE_Y := 0.0

var terrain: CozyTerrainSystem = null

var _meshes: Dictionary = {}   ## Vector2i chunk coord -> MeshInstance3D
var _bodies: Dictionary = {}   ## Vector2i chunk coord -> StaticBody3D


func setup(p_terrain: CozyTerrainSystem) -> void:
	terrain = p_terrain
	rebuild_all()


func rebuild_all() -> void:
	for coord in terrain.chunks:
		_rebuild_chunk(coord)


## Only the chunks the edit touched (doc #33: local edit, local rebuild).
func rebuild_dirty() -> void:
	var coords := terrain.dirty_chunks()
	for coord in coords:
		if terrain.chunks.has(coord):
			_rebuild_chunk(coord)
	terrain.clear_dirty()
	return


func chunk_mesh_count() -> int:
	return _meshes.size()


func _rebuild_chunk(coord: Vector2i) -> void:
	var chunk: CozyTerrainChunk = terrain.chunks[coord]
	var extent := terrain.chunk_extent()
	var origin := terrain.chunk_world_origin(coord)
	var centre := Vector3(origin.x + extent * 0.5, SURFACE_Y, origin.y + extent * 0.5)

	var mi: MeshInstance3D = _meshes.get(coord)
	if mi == null:
		mi = MeshInstance3D.new()
		add_child(mi)
		_meshes[coord] = mi
		# The control texture is replaced on every rebuild, so the material is
		# made once and only its `control` uniform is re-set.
		mi.material_override = _make_ground_material()
	mi.global_position = centre
	var am := _make_surface_mesh(chunk, extent)
	mi.mesh = am

	var mat: ShaderMaterial = mi.material_override
	mat.set_shader_parameter("control", _make_control_texture(chunk))

	# Collision from the SAME triangles, not a second sampling of the field.
	var body: StaticBody3D = _bodies.get(coord)
	if body == null:
		body = StaticBody3D.new()
		var cs := CollisionShape3D.new()
		body.add_child(cs)
		add_child(body)
		_bodies[coord] = body
	body.global_position = centre
	# A FLAT BOX, not a trimesh. The ground is a plane now, and a trimesh built
	# from 4096 triangles to describe a plane is 4096 triangles the physics
	# server has to consider for every step. One box says the same thing.
	var cs := body.get_child(0) as CollisionShape3D
	var box := BoxShape3D.new()
	box.size = Vector3(extent, 1.0, extent)
	cs.shape = box
	cs.position = Vector3(0.0, -0.5, 0.0)


## ONE QUAD per chunk. The whole ground is a plane, and every tile in it is
## decided per fragment by the shader.
##
## The version this replaced built a quad per display tile — 4096 of them per
## chunk — because that is what a tilemap does. It works, and it costs four
## thousand quads to draw a rectangle: the tile rule is arithmetic, and arithmetic
## does not need geometry.
##
## PlaneMesh lies in XZ centred on its origin, so the mesh spans the chunk exactly
## and `chunk_local.xz` in the shader IS a position within it.
func _make_surface_mesh(_chunk: CozyTerrainChunk, extent: float) -> ArrayMesh:
	var pm := PlaneMesh.new()
	pm.size = Vector2(extent, extent)
	var arrays := pm.get_mesh_arrays()
	var am := ArrayMesh.new()
	am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return am


## Lowest and highest points of a chunk## Lowest and highest points of a chunk## Lowest and highest points of a chunk's rendered surface. Used by the
## self-check to prove DIG moved the ground rather than only the field.
func chunk_surface_range(coord: Vector2i) -> Vector2:
	var mi: MeshInstance3D = _meshes.get(coord)
	if mi == null or mi.mesh == null:
		return Vector2.ZERO
	var aabb := mi.mesh.get_aabb()
	return Vector2(mi.global_position.y + aabb.position.y,
		mi.global_position.y + aabb.end.y)


func chunk_collision_count() -> int:
	return _bodies.size()


## Lowest point of a chunk's COLLISION. A check needs this separately from
## `chunk_surface_range`: displacing the picture without moving the collision
## gives a pit the player can see and walk across the top of, and the two numbers
## drifting apart is the only way to notice.
func chunk_collision_min_y(coord: Vector2i) -> float:
	var body: StaticBody3D = _bodies.get(coord)
	if body == null:
		return 0.0
	var cs := body.get_child(0) as CollisionShape3D
	if cs == null or not (cs.shape is ConcavePolygonShape3D):
		return 0.0
	var faces := (cs.shape as ConcavePolygonShape3D).get_faces()
	var lo := INF
	for i in faces.size():                  # `get_faces()` is raw vertices, 3 per triangle
		lo = minf(lo, faces[i].y)
	return (lo + body.global_position.y) if lo != INF else 0.0


## Where the ground shader lives.
const GROUND_SHADER := "res://shaders/ground.gdshader"

## One 16x16 pixel texture per material, in an array, built once and shared.
##
## AN ARRAY AND NOT AN ATLAS: a sub-region of an atlas cannot use hardware
## repeat, so everyone ends up doing `mod(UV, 1.0)` by hand and the sampler then
## bleeds the neighbouring cell's texels in at the region edge. Layers are
## independent, and `repeat_enable` is honoured on the array sampler where it is
## silently ignored on an array of `sampler2D`.
##
## Built lazily, because a headless run that never renders a chunk should not pay
## to generate six images it will not sample.
var _materials: Texture2DArray = null


func _materials_or_build() -> Texture2DArray:
	if _materials == null:
		var images: Array[Image] = []
		for id in CozyTerrainMaterials.ORDER:
			images.append(CozyTerrainTiles.material_image(id))
		_materials = Texture2DArray.new()
		_materials.create_from_images(images)
	return _materials


## The ground's material: the shader, told where its textures and its numbers are.
##
## Every uniform is SET here rather than left to the shader's own default, and
## the assertion that reads one back is why: `get_shader_parameter` answers null
## for a uniform nothing has set, so a check would report a feature off while the
## GPU drew it on. A value that lives only inside a shader is a value this side
## cannot assert about, and cannot switch off in a hurry.
func _make_ground_material() -> ShaderMaterial:
	var mat := ShaderMaterial.new()
	mat.shader = load(GROUND_SHADER)
	mat.set_shader_parameter("materials", _materials_or_build())
	mat.set_shader_parameter("material_count", CozyTerrainMaterials.ORDER.size())
	mat.set_shader_parameter("chunk_metres", float(CELLS) * CELL_SIZE)
	mat.set_shader_parameter("cell_metres", CELL_SIZE)
	mat.set_shader_parameter("texture_metres", TEXTURE_METRES)
	mat.set_shader_parameter("grain", GRAIN)
	mat.set_shader_parameter("rounding", ROUNDING)
	return mat


## One texel per cell: R is the material INDEX, G is the cell's grain.
##
## AN INDEX IS NOT A COLOUR. It is never filtered and never interpolated — the
## shader fetches it by integer coordinate — because averaging two material ids
## picks a third material nobody chose.
##
## The grain is deterministic, never Random (doc #53): the same world must
## regenerate identically after a save/load, and a touch of variation is what
## stops a large field reading as flat paint.
func _make_control_texture(chunk: CozyTerrainChunk) -> ImageTexture:
	var img := Image.create(CELLS, CELLS, false, Image.FORMAT_RGBA8)
	for lz in CELLS:
		for lx in CELLS:
			var index := CozyTerrainMaterials.index_of(chunk.material_id_at(lx, lz))
			var n := float(absi(hash(Vector3i(lx, lz,
				chunk.chunk_x * 73856093 + chunk.chunk_z * 19349663))) % 1000) / 1000.0
			img.set_pixel(lx, lz, Color(float(index) / 255.0, n, 0.0, 1.0))
	return ImageTexture.create_from_image(img)


## One chunk's control texture, read back as an Image.
##
## READING IT BACK IS THE POINT. The control texture is the ONLY link between
## what the terrain system knows and what the shader samples, and a wrong byte in
## it draws every cell as the same material — which looks like an art decision.
func control_image(coord: Vector2i) -> Image:
	if not _meshes.has(coord):
		return null
	var mat := (_meshes[coord] as MeshInstance3D).material_override as ShaderMaterial
	if mat == null:
		return null
	var tex: Texture2D = mat.get_shader_parameter("control")
	return tex.get_image() if tex != null else null


## How many material textures the ground can sample.
func material_layers() -> int:
	return 0 if _materials == null else _materials.get_layers()


## The chunks this renderer currently holds, sorted.
func chunk_coords() -> Array:
	var out: Array = _meshes.keys()
	out.sort()
	return out


## For the self-check: the material a chunk is drawn with, or null.
func material_of(coord: Vector2i) -> Material:
	if not _meshes.has(coord):
		return null
	return (_meshes[coord] as MeshInstance3D).material_override


func describe() -> String:
	return "terrain renderer, %d chunk mesh(es)" % _meshes.size()
