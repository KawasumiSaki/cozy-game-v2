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
##
## AND IT IS A DERIVED FACT, WHICH IS WHAT MAKES IT DANGEROUS. It is not part of
## the save; it is recomputed from the cells. Every route that writes cells has to
## either keep it in step or recount, and the one route that did neither went
## unnoticed for as long as the world happened to hold no water: see
## `from_dict`. `chunk_flag_probe.gd` measures it.
var has_water := false

## Does this chunk contain any farmland? Same shape and same reason as
## `has_water`, for a heavier consumer: a sow point exists only on farmland, and
## a search that walks the whole 64 x 64 m field for one spends 40 ms on chunks
## that cannot possibly hold it. Measured in `CozyGroundPoints`.
var has_farmland := false

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
	_recount_flags()


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


## Height at a GRID CORNER. Corners run 0..CELLS inclusive, so a chunk has one
## more corner than cell in each direction — 65 x 65 of them.
##
## Averaged over the up-to-four cells that share the corner. Both the surface
## mesh and the collision mesh read THIS, so the ground you look at and the
## ground you stand on cannot disagree; a mismatch between them is a player
## standing inside a hillside. Averaging also keeps the surface from depending on
## which side of a boundary `locate_index` happens to pick.
func corner_height(gx: int, gz: int) -> float:
	var sum := 0.0
	var n := 0
	for oz: int in [-1, 0]:
		for ox: int in [-1, 0]:
			var cx: int = gx + ox
			var cz: int = gz + oz
			if cx < 0 or cz < 0 or cx >= CELLS or cz >= CELLS:
				continue
			sum += height_at(cx, cz)
			n += 1
	return sum / float(n) if n > 0 else 0.0


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
	var was_farmland := _material[i] == _farmland_index
	var is_farmland := new_index == _farmland_index
	_material[i] = new_index
	# Default buildability follows the new material (doc #7 / #11).
	_build[i] = CozyTerrainMaterials.default_buildability(material_id)
	dirty = true

	# A cell that has JUST become water/farmland is itself proof that the chunk
	# holds some, so the cheap direction is a plain set. Only LOSING the last one
	# needs a recount — and that is the rare direction: a field is tilled once and
	# then left, and a chunk is 4096 cells, so recounting on every till would cost
	# more than the walk the flag exists to avoid.
	if is_water:
		has_water = true
	elif was_water:
		has_water = _any_cell_is(_water_index)
	if is_farmland:
		has_farmland = true
	elif was_farmland:
		has_farmland = _any_cell_is(_farmland_index)
	return true


static var _water_index := CozyTerrainMaterials.index_of("water")
static var _farmland_index := CozyTerrainMaterials.index_of("farmland")


func _any_cell_is(material_index: int) -> bool:
	for i in _material.size():
		if _material[i] == material_index:
			return true
	return false


## Recompute both flags from the cells. For the routes that install cells
## WHOLESALE rather than one at a time, where there is no "which cell changed" to
## reason from — currently `from_dict`.
func _recount_flags() -> void:
	has_water = _any_cell_is(_water_index)
	has_farmland = _any_cell_is(_farmland_index)


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
##
## The packed arrays are converted to PLAIN arrays on purpose. `JSON.stringify`
## does not understand `PackedInt32Array` / `PackedFloat32Array` /
## `PackedByteArray` and silently writes each as a STRING — which then reads back
## as a string and cannot be assigned to the field it came from.
##
## An in-memory round trip cannot see that: `to_dict()` hands back the live
## packed array, the assignment succeeds, and the assertion goes green while the
## file on disk is unreadable. That is exactly how this went unnoticed until
## V2-26 put the dict through a real serializer.
func to_dict() -> Dictionary:
	return {
		"chunk_x": chunk_x,
		"chunk_z": chunk_z,
		"cells": CELLS,
		"cell_size": CELL_SIZE,
		"material": Array(_material),
		"height": Array(_height),
		"buildability": Array(_build),
	}


## Sizes are checked before copying. A truncated or corrupt file must not leave a
## half-filled chunk — that would be a chunk that looks loaded and is wrong.
static func from_dict(d: Dictionary) -> CozyTerrainChunk:
	var c := CozyTerrainChunk.new(int(d.get("chunk_x", 0)), int(d.get("chunk_z", 0)))
	var m: Array = d.get("material", [])
	var h: Array = d.get("height", [])
	var b: Array = d.get("buildability", [])
	if m.size() == c._material.size():
		for i in m.size():
			c._material[i] = int(m[i])
	if h.size() == c._height.size():
		for i in h.size():
			c._height[i] = float(h[i])
	if b.size() == c._build.size():
		for i in b.size():
			c._build[i] = int(b[i])
	# THE FLAGS ARE NOT IN THE FILE, so nothing above has maintained them: this
	# function assigns `_material` cell by cell and never goes through
	# `set_material`. Without this line a loaded chunk claims to hold no water and
	# no farmland while its cells say otherwise, and the reader is a classifier
	# that then decides the world is dry. Measured in `chunk_flag_probe.gd`:
	#
	#     after set_material_at:   has_water=true   material=water
	#     after to_dict/from_dict: has_water=false  material=water
	#
	# It went unnoticed because a world with no water in it reads false either
	# way — and because the ONE caller that runs on the live terrain is
	# `_check_scatter_incremental` (main.gd), which reloads the field mid-check.
	c._recount_flags()
	c.dirty = true
	return c


func describe() -> String:
	var counts := {}
	for i in _material:
		var id := CozyTerrainMaterials.id_of(i)
		counts[id] = counts.get(id, 0) + 1
	return "chunk(%d,%d) %s" % [chunk_x, chunk_z, counts]
