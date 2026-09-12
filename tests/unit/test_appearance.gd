extends "res://tests/unit/unit_test.gd"
## The character-factory vocabulary (ART-14).
##
## The IDs here ARE the interface with the offline renderer: whatever Blender
## calls `hair_05`, this table calls `hair_05`. These cases keep the table
## self-consistent, which is the half that can be checked without a renderer.


func _init() -> void:
	suite("appearance")
	case("the default is valid in every slot", _default_valid)
	case("every row is fully described", _rows_complete)
	case("ids_for agrees with its table", _ids_match)
	case("a partial appearance is filled in", _normalise)
	case("a typo is reported, not absorbed", _unknown_reported)
	case("colour helpers resolve a real row", _tints)


func _default_valid() -> void:
	for slot in CozyAppearanceDefs.SLOTS:
		var id := String(CozyAppearanceDefs.DEFAULT[slot])
		is_true("default %s '%s' is a real id" % [slot, id],
			CozyAppearanceDefs.has_id(slot, id))
	is_true("normalise leaves the default alone",
		str(CozyAppearanceDefs.normalise({})) == str(CozyAppearanceDefs.DEFAULT))


func _rows_complete() -> void:
	for slot in CozyAppearanceDefs.SLOTS:
		var table := CozyAppearanceDefs.table_for(slot)
		is_true("slot '%s' is not empty" % slot, not table.is_empty())
		for id in table:
			ne("'%s' has a display name" % id, String(table[id].get("name", "")), "")


func _ids_match() -> void:
	for slot in CozyAppearanceDefs.SLOTS:
		eq("ids_for('%s') matches the table size" % slot,
			CozyAppearanceDefs.ids_for(slot).size(),
			CozyAppearanceDefs.table_for(slot).size())
	# Sorted, so anything that randomises over it is deterministic.
	for slot in CozyAppearanceDefs.SLOTS:
		var ids := CozyAppearanceDefs.ids_for(slot)
		var sorted_ids := ids.duplicate()
		sorted_ids.sort()
		eq("ids_for('%s') is sorted" % slot, str(ids), str(sorted_ids))


func _normalise() -> void:
	var partial := CozyAppearanceDefs.normalise({"clothes": "clothes_04"})
	eq("the given slot survives", String(partial["clothes"]), "clothes_04")
	eq("a missing slot falls back to the default",
		String(partial["hair"]), String(CozyAppearanceDefs.DEFAULT["hair"]))
	eq("normalise returns every slot",
		CozyAppearanceDefs.SLOTS.size(), partial.size())
	# A default must not be handed out by reference: mutating one caller's
	# appearance must not edit the constant.
	var a := CozyAppearanceDefs.make_default()
	a["hair"] = "hair_05"
	ne("make_default() copies", String(CozyAppearanceDefs.DEFAULT["hair"]), "hair_05")


## Silently falling back is how an id and a rendered sheet drift apart with
## nothing to see: the character still draws, it just draws the wrong one.
func _unknown_reported() -> void:
	var typo := CozyAppearanceDefs.make_default()
	typo["hair"] = "hair_99"
	var bad := CozyAppearanceDefs.unknown_slots(typo)
	eq("exactly one slot is reported", bad.size(), 1)
	eq("and it is the right one", String(bad[0]), "hair")
	eq("a clean appearance reports nothing",
		CozyAppearanceDefs.unknown_slots(CozyAppearanceDefs.make_default()).size(), 0)


func _tints() -> void:
	var fair := CozyAppearanceDefs.make_default()
	var brown := CozyAppearanceDefs.make_default()
	brown["color"] = "brown"
	ne("two skin tones differ",
		CozyAppearanceDefs.skin_of(fair), CozyAppearanceDefs.skin_of(brown))
	var short_hair := CozyAppearanceDefs.make_default()
	var braided := CozyAppearanceDefs.make_default()
	braided["hair"] = "hair_05"
	ne("two hair colours differ",
		CozyAppearanceDefs.hair_tint_of(short_hair),
		CozyAppearanceDefs.hair_tint_of(braided))
	ne("describe() says something",
		CozyAppearanceDefs.describe(fair), "")
