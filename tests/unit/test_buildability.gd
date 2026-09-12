extends "res://tests/unit/unit_test.gd"
## The buildability vocabulary. Six states, and one question that matters:
## may a building stand here?

const ALL: Array[int] = [
	CozyBuildability.NATURAL, CozyBuildability.CLEARED, CozyBuildability.PREPARED,
	CozyBuildability.BUILDABLE, CozyBuildability.RESTRICTED, CozyBuildability.OCCUPIED,
]


func _init() -> void:
	suite("buildability")
	case("names round-trip", _names)
	case("only BUILDABLE accepts a building", _accepts)
	case("an unknown name is refused loudly", _unknown)


func _names() -> void:
	for v in ALL:
		var n := CozyBuildability.name_of(v)
		ne("state %d has a name" % v, n, "")
		eq("'%s' maps back to %d" % [n, v], CozyBuildability.from_name(n), v)


## The decision this enum exists to answer.
##
## PREPARED accepts too — "levelled and consolidated" is good enough for a
## foundation, and the code says so deliberately. The first draft of this test
## asserted otherwise and FAILED, which is the useful outcome: the test was
## wrong, not the code.
func _accepts() -> void:
	var accepts: Array[int] = [CozyBuildability.BUILDABLE, CozyBuildability.PREPARED]
	for v in accepts:
		is_true("%s accepts" % CozyBuildability.name_of(v),
			CozyBuildability.accepts_building(v))
	is_true("OCCUPIED does not accept — clear it first",
		not CozyBuildability.accepts_building(CozyBuildability.OCCUPIED))
	for v in [CozyBuildability.NATURAL, CozyBuildability.CLEARED, CozyBuildability.RESTRICTED]:
		is_false("%s does not accept" % CozyBuildability.name_of(v),
			CozyBuildability.accepts_building(v))


## An unknown VALUE is reported loudly: `name_of` returns "unknown" rather than
## a real state, so a bad integer cannot masquerade as valid ground.
##
## An unknown NAME falls back to NATURAL, which is silent — but the direction is
## the safe one (refusing to build beats allowing it). The risk it leaves is a
## typo in a data table reading as "untouched ground", and that is caught at the
## source instead: see `test_terrain_materials.every material names a real state`.
func _unknown() -> void:
	eq("an unknown value reads as 'unknown'", CozyBuildability.name_of(999), "unknown")
	eq("a typo falls back to NATURAL (safe direction)",
		CozyBuildability.from_name("banana"), CozyBuildability.NATURAL)
