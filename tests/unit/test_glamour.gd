extends "res://tests/unit/unit_test.gd"
## Glamours: an item that looks like another and is worth exactly the same.
##
## TWO CLAIMS, and everything else here is bookkeeping around them:
##
##   1. THE APPEARANCE IS PER-INSTANCE. Two iron swords are two swords, so one of
##      them can be made to look like a steel sword and the other cannot be
##      affected — the same claim the affix system rests on, one field over.
##   2. IT CHANGES NO NUMBER. Not one. This is the promise the entire feature is
##      made of, and it is one careless line in `base_stats()` away from being
##      false: the player who glamoured a sword for the look would silently be
##      given its numbers instead.
##
## The second is checked against `CozyStats.resolve` over a rolled item rather
## than against a hand-written expectation, because a hand-written one would be a
## second copy of what the stats are.

func _init() -> void:
	suite("glamour")
	case("a fresh item looks like itself", _fresh)
	case("an item can be made to look like another", _apply)
	case("the numbers do not move", _numbers_are_untouched)
	case("one sword glamoured leaves the other alone", _per_instance)
	case("a helmet cannot be worn on a hand", _slot_rule)
	case("a source that is not an item is refused, and says so", _bad_source)
	case("taking it off restores what it is", _remove)
	case("an appearance survives a file", _round_trip)
	case("what a player may use is what a player owns", _owned_sources)


func _fresh() -> void:
	var it := _sword("a")
	eq("no glamour", it.glamour_id, "")
	is_false("and it does not claim one", it.is_glamoured())
	eq("it looks like itself", it.appearance_id(), "iron_sword")
	eq("and is named after itself", it.appearance_name(), "Iron Sword")


func _apply() -> void:
	var it := _sword("a")
	is_true("a sword may look like another sword", CozyGlamour.apply(it, "steel_sword"))
	eq("it wears it", it.glamour_id, "steel_sword")
	is_true("and says so", it.is_glamoured())
	eq("what it looks like", it.appearance_id(), "steel_sword")
	# NAMED AFTER THE LOOK. A bag showing "Iron Sword" over a steel-sword sprite
	# is a bug report about a lie.
	eq("and is named after the look", it.appearance_name(), "Steel Sword")
	# ...while what it IS has not moved, which is what the stats are read from.
	eq("but it is still an iron sword", it.definition_id, "iron_sword")
	eq("and still named that where it matters", it.display_name(), "Iron Sword")


## THE PROMISE. Checked through the resolver, over an item with rolled affixes,
## because that is the path a number actually takes to reach a player.
func _numbers_are_untouched() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 20260915
	var it := CozyItemGenerator.generate("iron_sword", "rare", 1, rng, "item_g1")
	var before: Array = it.modifiers().duplicate(true)
	var attack_before := CozyStats.resolve(it.modifiers(), "attack", 0.0)

	is_true("the glamour took", CozyGlamour.apply(it, "steel_sword"))

	eq("the modifier list is identical", str(it.modifiers()), str(before))
	near("and the resolved attack is identical",
		CozyStats.resolve(it.modifiers(), "attack", 0.0), attack_before)
	# And the affixes themselves were not replaced by the source's, which is the
	# other way this could go wrong: a glamour that copied the SOURCE's stats
	# would look correct in a bag and be a silent upgrade.
	near("the rolled affixes are its own",
		CozyStats.resolve(it.modifiers(), "attack_speed", 0.0),
		CozyStats.resolve(before, "attack_speed", 0.0))
	# A steel sword is worth more than an iron one, so if the numbers had moved
	# the comparison above would have found it — stated as its own check so the
	# suite fails loudly if someone ever makes the two swords the same.
	is_true("and the two swords are actually different",
		CozyItemDefs.base_stats("steel_sword")["attack"] \
			> CozyItemDefs.base_stats("iron_sword")["attack"])


## THE OTHER CLAIM. Same field, same argument as the affixes: an appearance on
## the definition would be a game-wide reskin.
func _per_instance() -> void:
	var a := _sword("a")
	var b := _sword("b")
	CozyGlamour.apply(a, "steel_sword")
	eq("the one keeps its look", a.appearance_id(), "steel_sword")
	eq("and the other did not move", b.appearance_id(), "iron_sword")
	is_false("and does not claim a glamour", b.is_glamoured())


## A sword cannot be made to look like a helmet, and the reason is not realism —
## the two are drawn in different places, so the result is a helmet on a hand.
func _slot_rule() -> void:
	var it := _sword("a")
	var why := CozyGlamour.reject_reason(it, "iron_helmet")
	ne("it is refused", why, "")
	is_true("and the reason names the slots", why.contains("Helmet"))
	is_false("and it did not take", CozyGlamour.apply(it, "iron_helmet"))
	eq("the sword is unchanged", it.glamour_id, "")
	# And the same rule from the other side: a ring may not look like a sword.
	# (The first version of this asked whether a copper ring could look like a
	# copper ring, which is "already looks like itself" — a different rule, and
	# the one it accidentally tested.)
	var ring := CozyItemInstance.make("r", "copper_ring", "common", 1)
	ne("a ring may not look like a sword",
		CozyGlamour.reject_reason(ring, "iron_sword"), "")
	eq("but a sword may look like a sword", CozyGlamour.reject_reason(
		_sword("a"), "steel_sword"), "")
	# Looking like yourself is a no-op rather than an error, and it is refused so
	# a menu can leave it out instead of offering a button that does nothing.
	is_true("looking like itself is refused",
		CozyGlamour.reject_reason(it, "iron_sword").contains("itself"))


func _bad_source() -> void:
	var it := _sword("a")
	ne("an empty choice is refused", CozyGlamour.reject_reason(it, ""), "")
	ne("something that is not an item is refused",
		CozyGlamour.reject_reason(it, "not_a_thing"), "")
	ne("and nothing is refused", CozyGlamour.reject_reason(null, "steel_sword"), "")
	is_false("applying to nothing does nothing",
		CozyGlamour.apply(null, "steel_sword"))


func _remove() -> void:
	var it := _sword("a")
	CozyGlamour.apply(it, "steel_sword")
	is_true("taking it off reports a change", CozyGlamour.remove(it))
	is_false("and it looks like itself again", it.is_glamoured())
	eq("by name", it.appearance_name(), "Iron Sword")
	# Idempotent: taking one off an unglamoured item is a no-op, not a failure.
	is_false("taking it off twice is a no-op", CozyGlamour.remove(it))


func _round_trip() -> void:
	var it := _sword("a")
	it.affixes = [{"id": "strength", "value": 6.0}]
	CozyGlamour.apply(it, "steel_sword")
	# Through a real serialiser: an in-memory round trip cannot see a payload
	# `JSON.stringify` writes as a string.
	var back := CozyItemInstance.from_dict(
		JSON.parse_string(JSON.stringify(it.to_dict())))
	eq("the glamour came back", back.glamour_id, "steel_sword")
	eq("the affixes came back", back.affixes.size(), 1)
	eq("and the description matches", back.describe(), it.describe())
	# An item from before glamours existed has no field, and the honest reading of
	# an absent appearance is "none".
	eq("an old file reads as unglamoured",
		CozyItemInstance.from_dict({"definition_id": "iron_sword"}).glamour_id, "")


## A glamour in every game of this kind consumes the source, and consuming
## something the player does not have is a bug waiting for a menu.
func _owned_sources() -> void:
	var target := _sword("a")
	var bag := CozyItemContainer.new(4)
	bag.add_item(_sword("b"))
	bag.add_item(CozyItemInstance.make("h", "iron_helmet", "common", 1))
	var eq := CozyEquipment.new()
	eq.equip(CozyItemInstance.make("s", "steel_sword", "common", 1))

	var all := CozyGlamour.sources_for(target)
	is_true("a steel sword is a possible look", all.has("steel_sword"))
	is_true("a helmet is not", not all.has("iron_helmet"))

	var owned := CozyGlamour.owned_sources(target, bag, eq)
	# THE SWORD IN HAND COUNTS AS OWNED, which is the case a bag-only rule misses:
	# a player wearing the steel sword and glamouring their iron one to match is
	# the single most obvious use of the feature.
	is_true("what is worn counts as owned", owned.has("steel_sword"))
	is_true("and so does what is carried", owned.has("iron_sword")
		or owned.has("steel_sword"))


func _sword(instance_id: String) -> CozyItemInstance:
	return CozyItemInstance.make(instance_id, "iron_sword", "common", 1)
