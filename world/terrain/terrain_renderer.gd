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

## Texels per side of one material texture. 16 is the project's own pixel unit
## (`CozyPixelArt` draws everything at 16), and at one texture per metre it lands
## near the 16 px/m the art profile assumes.
const MATERIAL_TEXELS := 16

## Where the ground shader lives.
const TERRAIN_SHADER := "res://shaders/terrain.gdshader"

## The six material textures, loaded once and shared by every chunk's material.
##
## Built lazily rather than in `setup()`, because a headless run that never
## renders a chunk should not pay for sixteen images it will not sample.
var _material_array: Texture2DArray = null
const CELL_SIZE := CozyTerrainChunk.CELL_SIZE

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
		mi.material_override = _make_shader_material()
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
	(body.get_child(0) as CollisionShape3D).shape = am.create_trimesh_shape()


## One mesh per chunk, still: a 65 x 65 vertex grid is 4096 triangles in ONE
## draw call, which is what doc #61's rule is actually about (it forbids 10,000
## independent draw calls, not triangle count). Sixteen chunks cost sixteen draw
## calls, and the per-cell texture and its UVs are untouched by the displacement.
func _make_surface_mesh(chunk: CozyTerrainChunk, extent: float) -> ArrayMesh:
	var pm := PlaneMesh.new()
	pm.size = Vector2(extent, extent)
	pm.subdivide_width = CELLS - 1
	pm.subdivide_depth = CELLS - 1
	var arrays := pm.get_mesh_arrays()

	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var half := extent * 0.5
	for i in verts.size():
		var v := verts[i]
		# PlaneMesh lies in XZ centred on its origin, so a vertex's own x/z IS its
		# position within the chunk. Reading it back beats index arithmetic, which
		# would depend on a vertex ordering the engine never promised.
		var gx := int(round((v.x + half) / CELL_SIZE))
		var gz := int(round((v.z + half) / CELL_SIZE))
		verts[i] = Vector3(v.x, chunk.corner_height(gx, gz), v.z)
	arrays[Mesh.ARRAY_VERTEX] = verts

	var am := ArrayMesh.new()
	am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return am


## Lowest and highest points of a chunk's rendered surface. Used by the
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


## One texel per cell: R is the material INDEX, G is the cell's grain.
##
## It used to be the cell's colour, which is why the ground read as flat paint:
## one texel per cell is one flat colour per cell, and a material boundary was a
## one-texel staircase by construction. The colour now comes from a repeating
## texture and this carries only what the shader cannot work out for itself.
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


## The six material textures as one array, built once and shared.
func _material_array_or_build() -> Texture2DArray:
	if _material_array != null:
		return _material_array
	var images: Array[Image] = []
	for id in CozyTerrainMaterials.ORDER:
		images.append(_material_image(id))
	_material_array = Texture2DArray.new()
	_material_array.create_from_images(images)
	return _material_array


## One material's repeating texture: its colour, grained by a hash of its id.
##
## Procedural, like everything else in the placeholder art pipeline, so a new
## terrain material is a row in `CozyTerrainMaterials` and needs no file.
func _material_image(id: String) -> Image:
	var img := Image.create(MATERIAL_TEXELS, MATERIAL_TEXELS, false, Image.FORMAT_RGBA8)
	var base := CozyTerrainMaterials.color_of(id)
	var h := hash(id)
	for y in MATERIAL_TEXELS:
		for x in MATERIAL_TEXELS:
			var n := float(absi(hash(Vector3i(x, y, h))) % 1000) / 1000.0
			var shade := 1.0 + (n - 0.5) * 0.18
			img.set_pixel(x, y, Color(
				clampf(base.r * shade, 0.0, 1.0),
				clampf(base.g * shade, 0.0, 1.0),
				clampf(base.b * shade, 0.0, 1.0),
				1.0))
	return img


func _make_shader_material() -> ShaderMaterial:
	var mat := ShaderMaterial.new()
	mat.shader = load(TERRAIN_SHADER)
	mat.set_shader_parameter("materials", _material_array_or_build())
	# The mesh spans the chunk exactly, and a cell is a quarter of a metre.
	mat.set_shader_parameter("chunk_metres", float(CELLS) * CELL_SIZE)
	return mat


## How many material textures the ground can sample.
##
## For the self-check, and it is asserted because the failure is SILENT: a layer
## count that falls behind `CozyTerrainMaterials` means every cell of the newer
## material draws as layer 0 — grass where there should be stone, and nothing
## anywhere says so.
func material_layers() -> int:
	if _material_array == null:
		return 0
	return _material_array.get_layers()


## One chunk's control texture, read back as an Image.
##
## READING IT BACK IS THE POINT. The control texture is the ONLY link between
## what the terrain system knows and what the fragment shader samples, and a
## wrong byte in it draws every cell as the same material — which looks like an
## art decision, not a bug. Mutation testing is what found that: writing a
## constant index into every cell turned nothing red.
func control_image(coord: Vector2i) -> Image:
	if not _meshes.has(coord):
		return null
	var mat := (_meshes[coord] as MeshInstance3D).material_override as ShaderMaterial
	if mat == null:
		return null
	var tex: Texture2D = mat.get_shader_parameter("control")
	return tex.get_image() if tex != null else null


## The chunks this renderer currently holds, sorted.
func chunk_coords() -> Array:
	var out: Array = _meshes.keys()
	out.sort()
	return out


## Is the ground drawn through the shader at all? A chunk that fell back to a
## plain material would render as untextured grey, which looks like an art
## problem rather than a wiring one.
func draws_through_shader() -> bool:
	for coord in _meshes:
		if (_meshes[coord] as MeshInstance3D).material_override is ShaderMaterial:
			return true
	return false


func describe() -> String:
	return "terrain renderer, %d chunk mesh(es)" % _meshes.size()
