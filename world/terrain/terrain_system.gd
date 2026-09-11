class_name CozyTerrainSystem
extends Node3D
## Owns every terrain chunk and answers world-space questions about the ground
## (V2.1 doc #4 / #5).
##
## The doc promotes Terrain from "diggable ground" to the PREREQUISITE JUDGEMENT
## system for building:
##
##     Natural Terrain -> Modification -> Buildable Mask -> Foundation Validation
##                     -> Building Intent -> Building
##
## So this is not just storage. It is what a building placement has to ask
## permission from, and what a save file stores instead of any generated mesh.

const CHUNK_CELLS := CozyTerrainChunk.CELLS
const CELL_SIZE := CozyTerrainChunk.CELL_SIZE

var chunks: Dictionary = {}       ## Vector2i -> CozyTerrainChunk

## World position of the terrain's (0,0) cell.
## NOTE: this is a Vector2, so `.x` is world X and `.y` is world Z — the ground
## plane is 2D and there is no third component. Reading `.z` here is a bug.
var origin := Vector2.ZERO
var width_m := 0.0
var depth_m := 0.0

var _chunks_x := 0
var _chunks_z := 0

## Chunk coords touched since the last clear — the dirty region (doc #33).
var _dirty := {}


func setup(p_width_m: float, p_depth_m: float, p_origin := Vector2.ZERO) -> void:
	origin = p_origin
	width_m = p_width_m
	depth_m = p_depth_m
	var extent := chunk_extent()
	_chunks_x = int(ceil(p_width_m / extent))
	_chunks_z = int(ceil(p_depth_m / extent))
	chunks.clear()
	_dirty.clear()
	for cz in _chunks_z:
		for cx in _chunks_x:
			chunks[Vector2i(cx, cz)] = CozyTerrainChunk.new(cx, cz)


func chunk_extent() -> float:
	return float(CHUNK_CELLS) * CELL_SIZE


func chunk_world_origin(coord: Vector2i) -> Vector2:
	return origin + Vector2(float(coord.x), float(coord.y)) * chunk_extent()


func chunk_count() -> int:
	return chunks.size()


# ---------------------------------------------------------------- addressing

## World (x, z) -> [chunk coord, local x, local z], or [] when outside.
func locate(world_x: float, world_z: float) -> Array:
	var gx := int(floor((world_x - origin.x) / CELL_SIZE))
	var gz := int(floor((world_z - origin.y) / CELL_SIZE))
	if gx < 0 or gz < 0:
		return []
	var coord := Vector2i(gx / CHUNK_CELLS, gz / CHUNK_CELLS)
	if not chunks.has(coord):
		return []
	return [coord, gx % CHUNK_CELLS, gz % CHUNK_CELLS]


func cell_center_world(coord: Vector2i, lx: int, lz: int) -> Vector2:
	var o := chunk_world_origin(coord)
	return o + Vector2((float(lx) + 0.5) * CELL_SIZE, (float(lz) + 0.5) * CELL_SIZE)


# ---------------------------------------------------------------- queries

func material_id_at(world_x: float, world_z: float) -> String:
	var loc := locate(world_x, world_z)
	if loc.is_empty():
		return CozyTerrainMaterials.DEFAULT
	return (chunks[loc[0]] as CozyTerrainChunk).material_id_at(loc[1], loc[2])


func height_at(world_x: float, world_z: float) -> float:
	var loc := locate(world_x, world_z)
	if loc.is_empty():
		return 0.0
	return (chunks[loc[0]] as CozyTerrainChunk).height_at(loc[1], loc[2])


func buildability_at(world_x: float, world_z: float) -> int:
	var loc := locate(world_x, world_z)
	if loc.is_empty():
		return CozyBuildability.RESTRICTED   # Outside the world is not buildable.
	return (chunks[loc[0]] as CozyTerrainChunk).buildability_at(loc[1], loc[2])


func cell_at(world_x: float, world_z: float) -> CozyTerrainCell:
	var loc := locate(world_x, world_z)
	if loc.is_empty():
		return null
	return (chunks[loc[0]] as CozyTerrainChunk).cell_at(loc[1], loc[2])


# ---------------------------------------------------------------- mutation

func set_material_at(world_x: float, world_z: float, material_id: String) -> bool:
	var loc := locate(world_x, world_z)
	if loc.is_empty():
		return false
	var c: CozyTerrainChunk = chunks[loc[0]]
	if not c.set_material(loc[1], loc[2], material_id):
		return false
	_dirty[loc[0]] = true
	return true


func set_height_at(world_x: float, world_z: float, h: float) -> bool:
	var loc := locate(world_x, world_z)
	if loc.is_empty():
		return false
	var c: CozyTerrainChunk = chunks[loc[0]]
	if not c.set_height(loc[1], loc[2], h):
		return false
	_dirty[loc[0]] = true
	return true


func set_buildability_at(world_x: float, world_z: float, b: int) -> bool:
	var loc := locate(world_x, world_z)
	if loc.is_empty():
		return false
	var c: CozyTerrainChunk = chunks[loc[0]]
	if not c.set_buildability(loc[1], loc[2], b):
		return false
	_dirty[loc[0]] = true
	return true


# ---------------------------------------------------------------- dirty region

## Chunk coords edited since the last clear (doc #33: local edit, local rebuild).
func dirty_chunks() -> Array:
	var out: Array = _dirty.keys()
	out.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
		return a.y < b.y if a.y != b.y else a.x < b.x)
	return out


func clear_dirty() -> void:
	for coord in _dirty:
		if chunks.has(coord):
			(chunks[coord] as CozyTerrainChunk).dirty = false
	_dirty.clear()


# ---------------------------------------------------------------- serialise

func to_dict() -> Dictionary:
	var out: Array = []
	for coord in chunks:
		out.append((chunks[coord] as CozyTerrainChunk).to_dict())
	return {
		"origin": [origin.x, origin.y],
		"width_m": width_m,
		"depth_m": depth_m,
		"chunks": out,
	}


## Rebuild purely from facts. No generated surface is involved (doc #63):
## the saved data is the material/height/buildability field, and everything
## visual is regenerated afterwards.
func from_dict(d: Dictionary) -> void:
	var o: Array = d.get("origin", [0.0, 0.0])
	origin = Vector2(o[0], o[1])
	width_m = float(d.get("width_m", 0.0))
	depth_m = float(d.get("depth_m", 0.0))
	chunks.clear()
	_dirty.clear()
	for cd in d.get("chunks", []):
		var c := CozyTerrainChunk.from_dict(cd)
		chunks[Vector2i(c.chunk_x, c.chunk_z)] = c
	var extent := chunk_extent()
	_chunks_x = int(ceil(width_m / extent))
	_chunks_z = int(ceil(depth_m / extent))


func describe() -> String:
	return "terrain %dx%d m, %d chunk(s), %d dirty" % [
		int(width_m), int(depth_m), chunks.size(), _dirty.size()]
