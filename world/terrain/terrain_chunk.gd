class_name CozyTerrainChunk
extends RefCounted
## The memory / update / save unit (V2.1 doc #5.1).
##
##     "Chunk 是内存管理单位、更新单位、Dirty Region 的边界、
##      保存/加载单位、Terrain Mesh 重建单位。"
##
## STORAGE NOTE — why this does not hold CozyTerrainCell objects:
## the doc's cell size (#5.2) is a simulation unit around 0.25 m, so a modest
## 64x64 m area is 256x256 = 65,536 cells. One RefCounted per cell would mean
## 65k live objects for a small field, before any world expansion, and a chunk
## is supposed to be the cheap unit. Cells are therefore stored
## struct-of-arrays — the same data in three Packed arrays, a fraction of the
## footprint, and cheap to serialise wholesale.
##
## CozyTerrainCell remains the shape at the API boundary, so callers still see
## the doc's data model.

const CELLS := 64          ## Cells per side.
const CELL_SIZE := 0.25    ## Metres per cell (doc #5.2 — a simulation unit,
                           ## explicitly NOT a screen pixel).

var chunk_x := 0
var chunk_z := 0

## "Dirty" means the generated surface no longer matches the data (doc #33).
## Nothing rebuilds until a caller clears it — that is what keeps edits local.
var dirty := true

## Does this chunk contain any water? Maintained as cells change, because the
## shore test otherwise probes five neighbours per sample point and a world with
## no water in it pays that cost for nothing.
var has_water := false

var _material: PackedInt32Array
var _height: PackedFloat32Array
var _build: PackedByteArray


func _init(p_chunk_x := 0, p_chunk_z := 0) -> void:
	chunk_x = p_chunk_x
	chunk_z = p_chunk_z
	var n := CELLS * CELLS
	_material = PackedInt32Array()
	_material.resize(n)
	_material.fill(CozyTerrainMaterials.index_of(CozyTerrainMaterials.DEFAULT))
	_height = PackedFloat32Array()
	_height.resize(n)
	_height.fill(0.0)
	_build = PackedByteArray()
	_build.resize(n)
	for i in n:
		_build[i] = CozyTerrainMaterials.default_buildability(
			CozyTerrainMaterials.id_of(_material[i]))
	_recount_water()


# ---------------------------------------------------------------- geometry

func cell_count() -> int:
	return CELLS * CELLS


## World-space origin of this chunk's first cell.
func world_origin() -> Vector2:
	return Vector2(float(chunk_x) * CELLS * CELL_SIZE,
		float(chunk_z) * CELLS * CELL_SIZE)


func chunk_extent() -> float:
	return float(CELLS) * CELL_SIZE


static func _index(lx: int, lz: int) -> int:
	return lz * CELLS + lx


func in_bounds(lx: int, lz: int) -> bool:
	return lx >= 0 and lz >= 0 and lx < CELLS and lz < CELLS


# ---------------------------------------------------------------- accessors

func material_id_at(lx: int, lz: int) -> String:
	return CozyTerrainMaterials.id_of(_material[_index(lx, lz)])


func material_index_at(lx: int, lz: int) -> int:
	return _material[_index(lx, lz)]


func height_at(lx: int, lz: int) -> float:
	return _height[_index(lx, lz)]


func buildability_at(lx: int, lz: int) -> int:
	return _build[_index(lx, lz)]


func cell_at(lx: int, lz: int) -> CozyTerrainCell:
	return CozyTerrainCell.create(material_id_at(lx, lz), height_at(lx, lz))


# Index-based accessors for the hot path. The system's `locate_index()` hands
# back a flat index, and going back through (lx, lz) would just multiply out
# again — these skip the round trip.
func material_by_index(i: int) -> String:
	return CozyTerrainMaterials.id_of(_material[i])


func height_by_index(i: int) -> float:
	return _height[i]


func buildability_by_index(i: int) -> int:
	return _build[i]


# ---------------------------------------------------------------- mutation
# Every setter marks the chunk dirty. Rebuilding the surface is the caller's
# decision, made once per edit, not once per cell (doc #33).

func set_material(lx: int, lz: int, material_id: String) -> bool:
	if not in_bounds(lx, lz) or not CozyTerrainMaterials.exists(material_id):
		return false
	var i := _index(lx, lz)
	var new_index := CozyTerrainMaterials.index_of(material_id)
	if _material[i] == new_index:
		return false

	var was_water := _material[i] == _water_index
	var is_water := new_index == _water_index
	_material[i] = new_index
	# Default buildability follows the new material (doc #7 / #11).
	_build[i] = CozyTerrainMaterials.default_buildability(material_id)
	dirty = true

	if was_water != is_water:
		# A flip changes whether the shore test can short-circuit. Recounting
		# beats tracking a running total with two counters to keep in step.
		_recount_water()
	return true


static var _water_index := CozyTerrainMaterials.index_of("water")


func _recount_water() -> void:
	for i in _material.size():
		if _material[i] == _water_index:
			has_water = true
			return
	has_water = false


func set_height(lx: int, lz: int, h: float) -> bool:
	if not in_bounds(lx, lz):
		return false
	var i := _index(lx, lz)
	if is_equal_approx(_height[i], h):
		return false
	_height[i] = h
	dirty = true
	return true


func set_buildability(lx: int, lz: int, b: int) -> bool:
	if not in_bounds(lx, lz):
		return false
	var i := _index(lx, lz)
	if _build[i] == b:
		return false
	_build[i] = b
	dirty = true
	return true


# ---------------------------------------------------------------- serialise

## Facts only — material indices, heights, buildability (doc #63).
## The generated surface is never saved; it is rebuilt from this.
func to_dict() -> Dictionary:
	return {
		"chunk_x": chunk_x,
		"chunk_z": chunk_z,
		"cells": CELLS,
		"cell_size": CELL_SIZE,
		"material": _material,
		"height": _height,
		"buildability": _build,
	}


static func from_dict(d: Dictionary) -> CozyTerrainChunk:
	var c := CozyTerrainChunk.new(int(d.get("chunk_x", 0)), int(d.get("chunk_z", 0)))
	c._material = d.get("material", c._material)
	c._height = d.get("height", c._height)
	c._build = d.get("buildability", c._build)
	c.dirty = true
	return c


func describe() -> String:
	var counts := {}
	for i in _material:
		var id := CozyTerrainMaterials.id_of(i)
		counts[id] = counts.get(id, 0) + 1
	return "chunk(%d,%d) %s" % [chunk_x, chunk_z, counts]
