extends "res://tests/unit/unit_test.gd"
## The chunk's DERIVED FLAGS: `has_water` and `has_farmland`.
##
## Neither is saved. Both are answers about the cells, recomputed from them, and
## both have a consumer that will believe whatever they say — a shore test that
## short-circuits, and the ground's search for somewhere to sow.
##
## That combination is the dangerous one, and it is this project's recurring
## shape: a derived fact with a real consumer, no assertion, and a WRONG ANSWER
## THAT LOOKS LIKE A CORRECT ONE. "This chunk holds no water" is what a world
## with no water in it says, so a flag that is silently false everywhere is
## indistinguishable from a flag that works — right up until someone builds on
## it.
##
## Someone did. `from_dict` installed cells directly and never recounted, so a
## loaded chunk claimed to hold none of either, and the live terrain is reloaded
## mid-check by `_check_scatter_incremental`. Every case below is one route into
## the cells, because "there is one funnel" is a claim and this suite is where it
## gets to be wrong out loud.

const FARMLAND := "farmland"
const WATER := "water"


func _init() -> void:
	suite("terrain chunk")
	case("a fresh chunk holds neither", _fresh)
	case("an edit sets the flag it belongs to", _edit_sets)
	case("the other flag is not disturbed", _edit_is_specific)
	case("losing the last cell clears the flag", _last_cell_clears)
	case("a chunk keeps its flags through a save", _chunk_round_trip)
	case("the system keeps them through a load", _system_round_trip)
	case("a chunk reloaded with cells keeps the flags", _load_with_material)
	case("an empty chunk stays empty through a load", _load_empty_stays_empty)


func _fresh() -> void:
	var c := CozyTerrainChunk.new(0, 0)
	is_false("a new chunk has no water", c.has_water)
	is_false("a new chunk has no farmland", c.has_farmland)


func _edit_sets() -> void:
	var c := CozyTerrainChunk.new(0, 0)
	is_true("the edit landed", c.set_material(4, 4, FARMLAND))
	is_true("tilling sets has_farmland", c.has_farmland)
	is_false("and does not set has_water", c.has_water)

	is_true("the water edit landed", c.set_material(5, 5, WATER))
	is_true("painting water sets has_water", c.has_water)
	is_true("and farmland is still there", c.has_farmland)


## The flag is per-chunk and per-material. A single `has_something` bit would
## pass every case above and be useless to both consumers.
func _edit_is_specific() -> void:
	var c := CozyTerrainChunk.new(0, 0)
	c.set_material(1, 1, "stone")
	is_false("stone sets neither flag", c.has_water or c.has_farmland)
	c.set_material(1, 1, "grass")
	is_false("and neither does grass", c.has_water or c.has_farmland)


## The expensive direction, and the one the cheap shortcut got wrong in the
## other file: a plain `has_farmland = true` on every set is correct forever
## except here, where the last cell leaves and the flag has to be withdrawn.
func _last_cell_clears() -> void:
	var c := CozyTerrainChunk.new(0, 0)
	c.set_material(2, 2, FARMLAND)
	c.set_material(7, 9, FARMLAND)
	is_true("two cells, still farmland", c.has_farmland)

	c.set_material(2, 2, "grass")
	is_true("one left, still farmland", c.has_farmland)

	c.set_material(7, 9, "grass")
	is_false("none left, the flag is withdrawn", c.has_farmland)


## THE BUG THIS SUITE WAS WRITTEN FOR. The flag is not in the file, so a load has
## to ask the cells rather than expect an answer to arrive with them.
func _chunk_round_trip() -> void:
	var c := CozyTerrainChunk.new(0, 0)
	c.set_material(3, 3, WATER)
	c.set_material(6, 6, FARMLAND)

	var back := CozyTerrainChunk.from_dict(c.to_dict())
	eq("the water arrived", back.material_id_at(3, 3), WATER)
	eq("the farmland arrived", back.material_id_at(6, 6), FARMLAND)
	is_true("and so did has_water", back.has_water)
	is_true("and so did has_farmland", back.has_farmland)


## The route the live world actually takes (`main.gd`, `_check_scatter_incremental`
## and every F9), so it is asserted at the level the bug was found at rather than
## one below it.
func _system_round_trip() -> void:
	var sys := CozyTerrainSystem.new()
	sys.setup(32.0, 32.0, Vector2.ZERO)
	sys.set_material_at(2.0, 2.0, FARMLAND)

	var back := CozyTerrainSystem.new()
	back.from_dict(sys.to_dict())
	var c: CozyTerrainChunk = back.chunks[Vector2i(0, 0)]
	eq("the cell survived", back.material_id_at(2.0, 2.0), FARMLAND)
	is_true("and the flag survived with it", c.has_farmland)

	sys.free()
	back.free()


## A file can carry whatever a previous version of the game wrote, so the flags
## have to be DERIVED on load rather than restored from a key that may be absent,
## stale, or hand-edited.
func _load_with_material() -> void:
	var d := CozyTerrainChunk.new(0, 0).to_dict()
	var cells: Array = d["material"]
	# Local cell (1, 1) is row-major: z * CELLS + x.
	cells[1 * CozyTerrainChunk.CELLS + 1] = CozyTerrainMaterials.index_of(FARMLAND)
	var loaded := CozyTerrainChunk.from_dict(d)
	is_true("a chunk loaded with farmland knows it", loaded.has_farmland)


func _load_empty_stays_empty() -> void:
	var loaded := CozyTerrainChunk.from_dict(CozyTerrainChunk.new(0, 0).to_dict())
	is_false("and one loaded with none says none", loaded.has_farmland)
	is_false("water included", loaded.has_water)
