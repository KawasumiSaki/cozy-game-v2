extends "res://tests/unit/unit_test.gd"
## The player's own ledger, and the two accessors the gather verb reads.
##
## The ledger is thin — an id and a bag of materials — so the cases that matter
## are the ones about it being a SEPARATE account and about the definition being
## readable from a node that is spent. The first is the whole of the two-ledger
## decision; the second is the difference between a menu that loses a verb and a
## menu that says why the verb will not work.

func _init() -> void:
	suite("player ledger")
	case("two players do not share one bag", _separate_bags)
	case("it has an entity id, or the registry cannot index it", _has_id)
	case("what was carried survives a file", _round_trip)
	case("an old file with no pack loads as an empty pack", _old_file)
	case("a node says what can be done to it, spent or not", _interaction_types)
	case("the reach is the object's own number", _reach)


## THE DECISION, IN ONE ASSERTION. `CozyPlayerState` is a separate object from
## every other, and `main.gd`'s `_check_player_ledger` is what asserts it against
## the VILLAGE's account — this case is the cheaper half, that two players do not
## accidentally share one store the way a `static var` would make them.
func _separate_bags() -> void:
	var a := CozyPlayerState.new()
	var b := CozyPlayerState.new()
	a.pack.add("wood", 5.0)
	eq("the second player did not receive it", b.pack.count("wood"), 0.0)
	ne("and the bags are not the same object", a.pack, b.pack)


## `CozyEntityRegistry` looks every state up by `id`. A state without one cannot
## be indexed and — because `entities()` walks every kind — takes the whole
## registry down with it rather than failing alone. That is how this was found.
func _has_id() -> void:
	var s := CozyPlayerState.new()
	ne("it has an id", s.id, "")
	eq("and it is the constant", s.id, CozyPlayerState.PLAYER_ID)


func _round_trip() -> void:
	var s := CozyPlayerState.new()
	s.pack.add("wood", 12.0)
	s.pack.add("copper", 3.0)
	# Through a real serialiser: an in-memory round trip cannot see a payload
	# `JSON.stringify` writes as a string, which is how the chunk save was broken.
	var back := CozyPlayerState.from_dict(
		JSON.parse_string(JSON.stringify(s.to_dict())))
	eq("the id came back", back.id, s.id)
	eq("wood came back", back.pack.count("wood"), 12.0)
	eq("copper came back", back.pack.count("copper"), 3.0)
	eq("and the description matches", back.describe(), s.describe())


func _old_file() -> void:
	var s := CozyPlayerState.from_dict({})
	eq("an absent pack is an empty pack, not a failure", s.pack.total(), 0.0)
	eq("and it still has its id", s.id, CozyPlayerState.PLAYER_ID)


## READ FROM THE DEFINITION, NOT FROM THE LIVE POINTS — which is the whole reason
## the accessor exists. A spent tree has no points left, so a menu built from the
## tree's points would drop `Chop` entirely, and the player would be told nothing
## about a verb that is about to come back.
func _interaction_types() -> void:
	eq("a tree can be chopped", CozyObjectDefs.interaction_types("tree"),
		[CozyObjectDefs.INTERACT_CHOP] as Array[String])
	eq("a rock can be mined", CozyObjectDefs.interaction_types("rock"),
		[CozyObjectDefs.INTERACT_MINE] as Array[String])
	eq("a crop can be harvested", CozyObjectDefs.interaction_types("crop"),
		[CozyObjectDefs.INTERACT_HARVEST] as Array[String])
	# A thing that is not gathered from the world still describes itself, and a
	# check that only looked at resource nodes would not notice the difference.
	for id in CozyObjectDefs.OBJECTS:
		if CozyObjectDefs.is_gathered(String(id)):
			is_true("'%s' says how it is worked" % id,
				CozyObjectDefs.interaction_types(String(id)).size() > 0)


func _reach() -> void:
	is_true("a tree has a reach", CozyObjectDefs.reach_of("tree") > 0.0)
	eq("and it is the row's number",
		CozyObjectDefs.reach_of("tree"),
		float(CozyObjectDefs.get_def("tree")["interactions"][0]["reach"]))
	# Something with no interactions reaches nowhere, and that is an answer
	# rather than an error. FOUND rather than named: `chest` looks like the
	# obvious choice and has a `store` point with a reach, and naming it here
	# would have been a test of this line rather than of the rule.
	var bare := ""
	for id in CozyObjectDefs.OBJECTS:
		if (CozyObjectDefs.get_def(String(id)).get("interactions", []) as Array).is_empty():
			bare = String(id)
			break
	is_true("the table has a thing that is not worked by hand", bare != "")
	if bare != "":
		eq("and it reaches nowhere ('%s')" % bare, CozyObjectDefs.reach_of(bare), 0.0)
