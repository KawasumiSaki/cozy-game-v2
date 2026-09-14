class_name CozyItemInstance
extends RefCounted
## One particular item: the one in your hand, not the idea of it.
##
## Section 3.2 of the design document. An instance is a definition plus what was
## rolled onto it, and it is the only thing that owns a roll — the definition is
## shared by every copy and must not be able to differ between two of them.
##
## ---------------------------------------------------------------------------
## THE SOURCE OF ITS MODIFIERS IS THE INSTANCE ID, NOT THE DEFINITION ID.
##
## That one choice is what makes two iron swords two swords. Keyed by definition,
## equipping a second one would REPLACE the first's contribution rather than add
## to it — `CozyStats.put` replaces what a source says — and the player would
## watch a sword vanish from their numbers. Keyed by instance, taking one off
## removes exactly one.
##
## It is also why `CozyStats` is source-keyed at all: "take the sword off" has to
## be a subtraction that cannot go wrong, and the only way to make it one is for
## the sword to have a name of its own.

var instance_id := ""
var definition_id := ""
var rarity := "common"
var level := 1

## The rolled affixes: `[{"id": "strength", "value": 6.0}, ...]`.
##
## A LIST, not a dictionary keyed by affix id, because section 19 says a V1 item
## cannot roll the same affix twice but also says the data must not ASSUME that —
## a later version may allow a stackable affix, and a dictionary would have
## silently dropped the second roll rather than made it impossible.
var affixes: Array = []

var quantity := 1


static func make(p_instance_id: String, p_definition_id: String,
		p_rarity := "common", p_level := 1) -> CozyItemInstance:
	var it := CozyItemInstance.new()
	it.instance_id = p_instance_id
	it.definition_id = p_definition_id
	it.rarity = p_rarity
	it.level = p_level
	return it


# ---------------------------------------------------------------- identity

func definition() -> Dictionary:
	return CozyItemDefs.get_def(definition_id)


func display_name() -> String:
	return CozyItemDefs.display_name(definition_id)


func rarity_name() -> String:
	return CozyItemDefs.rarity_name(rarity)


func slot() -> String:
	return CozyItemDefs.slot_of(definition_id)


func item_type() -> String:
	return CozyItemDefs.type_of(definition_id)


## The name a source is known by. See the header: this is the instance, not the
## definition, and two of the same sword are two sources.
func source() -> String:
	return "item:%s" % instance_id


# ---------------------------------------------------------------- stats

## What this item is worth to whoever wears it, as `CozyStats` modifiers.
##
## The item's own `stats` go on first, then the rolled affixes on top. Both are
## the same kind of number and take the same four passes when the character's
## total is worked out — a sword's attack and a rolled `+4 Attack` are not two
## mechanisms, they are two rows that arrive at the same place.
func modifiers() -> Array:
	# MERGED FIRST, EMITTED ONCE, and that order is load-bearing. An item is ONE
	# source, so two contributions from it to the same stat and operation are the
	# same `(source, stat, op)` key — and `CozyStats.put` REPLACES what a key
	# already says. Writing the sword's own attack and then a rolled `+6 Attack`
	# straight into the list left the sword at 6: the affix erased the blade it
	# was rolled onto.
	#
	# So the item does its own arithmetic, which is its business, and hands the
	# resolver one number per stat and operation. Taking the sword off still
	# removes all of it in one call.
	var totals := {}      ## "stat|op" -> summed value
	for stat in CozyItemDefs.base_stats(definition_id):
		_add(totals, String(stat), CozyStats.Op.ADD,
			float(CozyItemDefs.base_stats(definition_id)[stat]))
	for a in affixes:
		var d: Dictionary = a
		var def := CozyAffixDefs.get_def(String(d["id"]))
		if def.is_empty():
			continue
		_add(totals, String(def["stat"]), int(def["op"]), float(d["value"]))

	var out: Array = []
	var keys: Array = totals.keys()
	keys.sort()   # A stable order, so a display does not reshuffle between frames.
	for k in keys:
		var parts := String(k).split("|")
		CozyStats.put(out, source(), parts[0], int(parts[1]), float(totals[k]))
	return out


static func _add(totals: Dictionary, stat: String, op: int, value: float) -> void:
	var key := "%s|%d" % [stat, op]
	totals[key] = float(totals.get(key, 0.0)) + value


## How well this affix rolled against its own range, 0.0 to 1.0 (section 17).
##
## DERIVED, never stored. Storing it would let the ratio disagree with the value
## it is a ratio of, and the value is the thing the character's stats are made
## from — so the value wins and this is computed from it on demand.
func roll_ratio(affix_id: String) -> float:
	var def := CozyAffixDefs.get_def(affix_id)
	if def.is_empty():
		return 0.0
	for a in affixes:
		if String((a as Dictionary)["id"]) != affix_id:
			continue
		var lo := float(def["min"])
		var hi := float(def["max"])
		if is_equal_approx(hi, lo):
			return 1.0
		return clampf((float((a as Dictionary)["value"]) - lo) / (hi - lo), 0.0, 1.0)
	return 0.0


# ---------------------------------------------------------------- serialise

## JSON's OWN TYPES ONLY.
##
## Section 47 says what to save and section 48 says why the final stats are not
## among it — they are recomputed, so a formula change does not leave a world of
## stale numbers behind. `docs/INVARIANTS.md` has the three bugs that hid behind
## a `to_dict()` which only ever made an in-memory round trip.
func to_dict() -> Dictionary:
	var rolled: Array = []
	for a in affixes:
		rolled.append({"id": String((a as Dictionary)["id"]),
			"value": float((a as Dictionary)["value"])})
	return {
		"instance_id": instance_id,
		"definition_id": definition_id,
		"rarity": rarity,
		"level": level,
		"affixes": rolled,
		"quantity": quantity,
	}


static func from_dict(d: Dictionary) -> CozyItemInstance:
	var it := CozyItemInstance.make(
		String(d.get("instance_id", "")),
		String(d.get("definition_id", "")),
		String(d.get("rarity", "common")),
		int(d.get("level", 1)))
	it.quantity = int(d.get("quantity", 1))
	for a in (d.get("affixes", []) as Array):
		it.affixes.append({"id": String((a as Dictionary).get("id", "")),
			"value": float((a as Dictionary).get("value", 0.0))})
	return it


func describe() -> String:
	var parts: Array[String] = []
	for a in affixes:
		parts.append("%s %+.2f" % [CozyAffixDefs.display_name(String((a as Dictionary)["id"])),
			float((a as Dictionary)["value"])])
	return "%s (%s, level %d)%s" % [
		display_name(), rarity_name(), level,
		"" if parts.is_empty() else " [" + ", ".join(parts) + "]"]
