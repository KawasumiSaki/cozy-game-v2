extends "res://tests/unit/unit_test.gd"
## The terrain material table.
##
## THIS IS THE ONE THAT WAS MISSING. The APPEND-ONLY rule on `ORDER` guards every
## existing save file — chunk cell arrays store INDICES into that list, so
## inserting a material in the middle silently re-labels every cell of every
## world ever saved. Until now that rule rested on a single boolean inside an
## integration check that has to boot a world to run.

## The five that existed before `farmland`. Their ORDER must not change, ever.
const ORIGINAL_FIVE: Array[String] = ["grass", "soil", "sand", "stone", "water"]


func _init() -> void:
	suite("terrain materials")
	case("storage order is append only", _order_is_append_only)
	case("every id round-trips through its index", _round_trip)
	case("an unknown id falls back instead of failing", _fallback)
	case("every material is fully described", _every_material_complete)
	case("buildability follows the material", _buildability)
	case("every material names a real state", _states_are_real)


## The rule, stated as a test. A saved chunk holds indices, so slot 3 must mean
## stone forever.
func _order_is_append_only() -> void:
	var order: Array = CozyTerrainMaterials.ORDER
	is_true("order still holds at least the original five",
		order.size() >= ORIGINAL_FIVE.size())
	for i in ORIGINAL_FIVE.size():
		eq("slot %d is still %s" % [i, ORIGINAL_FIVE[i]],
			String(order[i]), ORIGINAL_FIVE[i])
	eq("stone resolves to index 3", CozyTerrainMaterials.index_of("stone"), 3)
	eq("water resolves to index 4", CozyTerrainMaterials.index_of("water"), 4)
	is_true("farmland was appended, not inserted",
		CozyTerrainMaterials.index_of("farmland") >= ORIGINAL_FIVE.size())


func _round_trip() -> void:
	for id in CozyTerrainMaterials.ORDER:
		is_true("'%s' exists" % id, CozyTerrainMaterials.exists(String(id)))
		eq("'%s' round-trips" % id,
			CozyTerrainMaterials.id_of(CozyTerrainMaterials.index_of(String(id))),
			String(id))


func _fallback() -> void:
	eq("an unknown id resolves to the default",
		CozyTerrainMaterials.index_of("unobtainium"),
		CozyTerrainMaterials.index_of(CozyTerrainMaterials.DEFAULT))
	eq("a negative index reads as the default",
		CozyTerrainMaterials.id_of(-1), CozyTerrainMaterials.DEFAULT)
	eq("an out-of-range index reads as the default",
		CozyTerrainMaterials.id_of(9999), CozyTerrainMaterials.DEFAULT)
	is_false("an unknown id does not exist",
		CozyTerrainMaterials.exists("unobtainium"))


## `color_of` returns MAGENTA for a material with no colour — the loud sentinel.
## A material that reaches the renderer magenta is a material someone forgot.
func _every_material_complete() -> void:
	for id in CozyTerrainMaterials.ORDER:
		ne("'%s' has a real colour" % id,
			CozyTerrainMaterials.color_of(String(id)), Color.MAGENTA)
		ne("'%s' has a display name" % id,
			String(CozyTerrainMaterials.def(String(id)).get("display_name", "")), "")


## `CozyBuildability.from_name` falls back to NATURAL for a name it does not
## know, and that fallback is SILENT — a typo in a `default_buildability` string
## would quietly make a material unbuildable with nothing to see. This is where
## the typo would actually be made, so this is where it is caught.
func _states_are_real() -> void:
	for id in CozyTerrainMaterials.ORDER:
		var name := String(CozyTerrainMaterials.def(String(id)).get("default_buildability", ""))
		ne("'%s' names a state" % id, name, "")
		eq("'%s' -> '%s' round-trips" % [id, name],
			CozyBuildability.name_of(CozyBuildability.from_name(name)), name)


func _buildability() -> void:
	eq("soil is buildable by default",
		CozyTerrainMaterials.default_buildability("soil"), CozyBuildability.BUILDABLE)
	eq("stone is buildable by default",
		CozyTerrainMaterials.default_buildability("stone"), CozyBuildability.BUILDABLE)
	eq("grass starts untouched",
		CozyTerrainMaterials.default_buildability("grass"), CozyBuildability.NATURAL)
	# Farmland is worked ground: you do not drop a wall onto a crop field.
	eq("farmland is NOT buildable",
		CozyTerrainMaterials.default_buildability("farmland"), CozyBuildability.NATURAL)
	is_false("farmland does not accept a building",
		CozyBuildability.accepts_building(
			CozyTerrainMaterials.default_buildability("farmland")))
