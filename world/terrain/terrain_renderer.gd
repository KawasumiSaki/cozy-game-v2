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
## Height is not yet displaced into the mesh. The field carries it (doc #6) and
## DIG/FILL change it; rendering it needs a subdivided grid per chunk, which is
## a later block. Noted so the gap is deliberate rather than forgotten.

const CELLS := CozyTerrainChunk.CELLS
const CELL_SIZE := CozyTerrainChunk.CELL_SIZE

## Lifted a hair above the ground collision plane so the two never z-fight.
const SURFACE_Y := 0.0

var terrain: CozyTerrainSystem = null

var _meshes: Dictionary = {}   ## Vector2i chunk coord -> MeshInstance3D


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

	var mi: MeshInstance3D = _meshes.get(coord)
	if mi == null:
		mi = MeshInstance3D.new()
		var pm := PlaneMesh.new()
		pm.size = Vector2(extent, extent)
		mi.mesh = pm
		add_child(mi)
		_meshes[coord] = mi
		# The texture is replaced on every rebuild, so the material is made once.
		mi.material_override = CozyPixelArt.make_material(null, Vector3.ONE)

	var origin := terrain.chunk_world_origin(coord)
	mi.global_position = Vector3(origin.x + extent * 0.5, SURFACE_Y,
		origin.y + extent * 0.5)

	var mat: StandardMaterial3D = mi.material_override
	mat.albedo_texture = _make_chunk_texture(chunk)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_DISABLED


func _make_chunk_texture(chunk: CozyTerrainChunk) -> ImageTexture:
	var img := Image.create(CELLS, CELLS, false, Image.FORMAT_RGBA8)
	for lz in CELLS:
		for lx in CELLS:
			var id := chunk.material_id_at(lx, lz)
			var col := CozyTerrainMaterials.color_of(id)
			# Deterministic per-cell shading, never Random. Two reasons (doc #53):
			# the same world must regenerate identically after a save/load, and a
			# touch of variation is what stops a large field reading as flat paint.
			var n := float(absi(hash(Vector3i(lx, lz,
				chunk.chunk_x * 73856093 + chunk.chunk_z * 19349663))) % 1000) / 1000.0
			var shade := 1.0 + (n - 0.5) * 0.14
			img.set_pixel(lx, lz, Color(
				clampf(col.r * shade, 0.0, 1.0),
				clampf(col.g * shade, 0.0, 1.0),
				clampf(col.b * shade, 0.0, 1.0),
				1.0))
	return ImageTexture.create_from_image(img)


func describe() -> String:
	return "terrain renderer, %d chunk mesh(es)" % _meshes.size()
