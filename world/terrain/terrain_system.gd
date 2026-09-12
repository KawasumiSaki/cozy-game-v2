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


## Allocation-free fast path for the hot queries.
##
## Returns Vector3i(chunk_x, chunk_z, local_index), or Vector3i(-1, -1, -1) when
## the point is outside. `locate()` above allocates an Array per call, which is
## fine occasionally but not here: the scatter walks ~4096 sample points and each
## one asks for its own material plus four neighbours for the shore test — over
## 20,000 calls, and an Array per call is pure garbage pressure. Measured before
## and after: the scatter rebuild went from 194 ms to single digits.
func locate_index(world_x: float, world_z: float) -> Vector3i:
	var gx := int(floor((world_x - origin.x) / CELL_SIZE))
	var gz := int(floor((world_z - origin.y) / CELL_SIZE))
	if gx < 0 or gz < 0:
		return Vector3i(-1, -1, -1)
	var cx := gx / CHUNK_CELLS
	var cz := gz / CHUNK_CELLS
	if not chunks.has(Vector2i(cx, cz)):
		return Vector3i(-1, -1, -1)
	return Vector3i(cx, cz, (gz % CHUNK_CELLS) * CHUNK_CELLS + (gx % CHUNK_CELLS))


func cell_center_world(coord: Vector2i, lx: int, lz: int) -> Vector2:
	var o := chunk_world_origin(coord)
	return o + Vector2((float(lx) + 0.5) * CELL_SIZE, (float(lz) + 0.5) * CELL_SIZE)


# ---------------------------------------------------------------- queries

func material_id_at(world_x: float, world_z: float) -> String:
	var loc := locate_index(world_x, world_z)
	if loc.x < 0:
		return CozyTerrainMaterials.DEFAULT
	return (chunks[Vector2i(loc.x, loc.y)] as CozyTerrainChunk).material_by_index(loc.z)


func height_at(world_x: float, world_z: float) -> float:
	var loc := locate_index(world_x, world_z)
	if loc.x < 0:
		return 0.0
	return (chunks[Vector2i(loc.x, loc.y)] as CozyTerrainChunk).height_by_index(loc.z)


func buildability_at(world_x: float, world_z: float) -> int:
	var loc := locate_index(world_x, world_z)
	if loc.x < 0:
		return CozyBuildability.RESTRICTED   # Outside the world is not buildable.
	return (chunks[Vector2i(loc.x, loc.y)] as CozyTerrainChunk).buildability_by_index(loc.z)


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


# ---------------------------------------------------------------- intent entry

## Apply a land edit. This is the ONLY way terrain changes (doc #1.4): the same
## rule the building system follows, applied to ground. Returns a summary.
func apply_intent(intent: CozyTerrainIntent) -> Dictionary:
	var cells := intent.cells(CELL_SIZE, origin)
	var touched := 0

	match intent.operation:
		CozyTerrainIntent.Op.CLEAR:
			for c in cells:
				if _clear_cell(c):
					touched += 1
		CozyTerrainIntent.Op.PAINT_MATERIAL:
			for c in cells:
				if set_material_at(c.x, c.y, intent.material_id):
					touched += 1
		CozyTerrainIntent.Op.DIG:
			for c in cells:
				if _offset_height(c, -intent.depth):
					touched += 1
		CozyTerrainIntent.Op.FILL:
			for c in cells:
				if _offset_height(c, intent.depth):
					touched += 1
		CozyTerrainIntent.Op.FLATTEN:
			touched = _flatten(cells)
		CozyTerrainIntent.Op.TILL:
			for c in cells:
				if _till_cell(c):
					touched += 1

	return {"cells": cells.size(), "touched": touched, "dirty": _dirty.size()}


## doc #10 — clearing vegetation turns Grass into Soil, and the ground becomes
## buildable.
##
## The doc's full chain is Grassland -> CLEARED -> PREPARED -> BUILDABLE. This
## collapses the two preparation steps into the single action the doc describes
## the PLAYER performing ("clean a patch of lawn"), and lands on the end state
## the doc states for it (Buildable = true). CLEARED and PREPARED stay in the
## enum for a later multi-step flow; nothing drives them yet.
func _clear_cell(c: Vector2) -> bool:
	var loc := locate(c.x, c.y)
	if loc.is_empty():
		return false
	var chunk: CozyTerrainChunk = chunks[loc[0]]
	var changed := false
	if chunk.material_id_at(loc[1], loc[2]) == "grass":
		changed = chunk.set_material(loc[1], loc[2], "soil") or changed
	# Soil's own default already resolves to BUILDABLE (doc #7), so this is a
	# no-op on a fresh conversion and only fires when re-clearing.
	changed = chunk.set_buildability(loc[1], loc[2], CozyBuildability.BUILDABLE) or changed
	if changed:
		_dirty[loc[0]] = true
	return changed


## Soil -> Farmland. The planting half of the chain.
##
## It REFUSES anything that is not already soil, and that refusal is the feature:
## the chain is Grass -> Soil -> Farmland, and tilling grass directly would make
## the clearing step optional. Two tools, two actions. A player who tills a lawn
## gets nothing and has to notice why.
##
## Note what is NOT here: no height change. Farmland is flat ground — elevation
## editing is deliberately out of scope for now, and this op must not sneak it in.
func _till_cell(c: Vector2) -> bool:
	var loc := locate(c.x, c.y)
	if loc.is_empty():
		return false
	var chunk: CozyTerrainChunk = chunks[loc[0]]
	if chunk.material_id_at(loc[1], loc[2]) != "soil":
		return false
	# `set_material` carries the new material's default buildability with it, so
	# farmland lands on NATURAL by itself — no buildability write needed here.
	if not chunk.set_material(loc[1], loc[2], "farmland"):
		return false
	_dirty[loc[0]] = true
	return true


func _offset_height(c: Vector2, delta: float) -> bool:
	var loc := locate(c.x, c.y)
	if loc.is_empty():
		return false
	var chunk: CozyTerrainChunk = chunks[loc[0]]
	var h := chunk.height_at(loc[1], loc[2]) + delta
	if not chunk.set_height(loc[1], loc[2], h):
		return false
	_dirty[loc[0]] = true
	return true


func _flatten(cells: Array) -> int:
	if cells.is_empty():
		return 0
	var sum := 0.0
	for c in cells:
		sum += height_at(c.x, c.y)
	var mean := sum / float(cells.size())
	var n := 0
	for c in cells:
		if set_height_at(c.x, c.y, mean):
			n += 1
	return n


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
