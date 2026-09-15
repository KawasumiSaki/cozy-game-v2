class_name CozyLootRoller
extends RefCounted
## Turns a loot table into the things that fell out of it.
##
## The document's section 22 chain is Enemy -> LootTable -> LootRoller ->
## ItemGenerator -> ItemInstance, and this is the middle link: it knows what a
## table means and nothing about what dropped it. Given a table and a source of
## randomness it hands back drops, which is why a goblin does not need to exist
## for the drop rates to be asserted.
##
## ---------------------------------------------------------------------------
## THE CALLER OWNS THE SEED, as everywhere else procedural in this project. Two
## rolls from the same seed are the same drop, which is not a limitation to work
## around — it is what lets a bug report say which seed produced it, and what
## lets the rates be measured without a monster.

## A drop is one of these.
const DROP_GOLD := "gold"
const DROP_ITEM := "item"
const DROP_EQUIPMENT := "equipment"

## The level a dropped item is rolled at, for V1. There is no character level to
## read one from yet, and a number in the generator's signature that nobody
## supplies is a number that will quietly be zero.
const DROP_LEVEL := 1


## Why this table cannot be rolled, or "" when it can.
##
## A REASON rather than a null, the shape the rest of this project settled on: a
## caller that refuses has to be able to say why, and a test can assert on the
## words.
static func reject_reason(table_id: String) -> String:
	if not CozyLootDefs.exists(table_id):
		return "no loot table '%s'" % table_id
	if CozyLootDefs.kind(table_id) != "drop":
		return "'%s' is not a drop table" % table_id
	return ""


## Roll a table. Returns `{"drops": Array, "next_id": int}`.
##
## `first_id` is where the caller's item-id counter stands, and `next_id` is where
## it stands afterwards: ids belong to whoever owns the list they are unique
## within, which is the rule the entity registry already follows. Handing back the
## counter rather than a list of ids is what keeps that ownership in one place
## instead of two.
##
## A drop is `{kind, ...}`:
##
##     {"kind": "gold", "amount": 7}
##     {"kind": "item", "id": "wheat", "amount": 2}
##     {"kind": "equipment", "item": CozyItemInstance}
##
## EVERY ENTRY IS ROLLED, IN ORDER, EVEN THE ONES THAT DO NOT DROP. A roller that
## skipped the draw for a zero-chance entry would produce a different sequence
## from the same seed the moment a table was edited — so an unrelated row changing
## would reshuffle every drop after it, and a bug report's seed would stop meaning
## anything.
static func roll(table_id: String, rng: RandomNumberGenerator,
		first_id := 1) -> Dictionary:
	var drops: Array = []
	var next_id := first_id
	if reject_reason(table_id) != "":
		return {"drops": drops, "next_id": next_id}

	for e in CozyLootDefs.entries(table_id):
		var entry: Dictionary = e
		if rng.randf() > float(entry.get("chance", 0.0)):
			continue
		var amount := rng.randi_range(int(entry.get("min", 1)), int(entry.get("max", 1)))
		match String(entry.get("kind", "")):
			CozyLootDefs.KIND_GOLD:
				drops.append({"kind": DROP_GOLD, "amount": amount})
			CozyLootDefs.KIND_ITEM:
				drops.append({"kind": DROP_ITEM,
					"id": String(entry.get("id", "")), "amount": amount})
			CozyLootDefs.KIND_EQUIPMENT:
				var made := _roll_equipment(String(entry.get("pick", "")), rng, next_id)
				if made != null:
					next_id += 1
					drops.append({"kind": DROP_EQUIPMENT, "item": made})
	return {"drops": drops, "next_id": next_id}


## One rolled instance, from whichever slot the pick table chose.
##
## THE PICK NAMES A TYPE AND THE TYPE FINDS THE ITEM, so the table never names a
## sword — the same discipline `CozyRecipeDefs` keeps about workstations. A table
## that could name an item directly would be able to name one that does not exist,
## and the drop would silently not happen.
static func _roll_equipment(pick_id: String, rng: RandomNumberGenerator,
		instance_id: int) -> CozyItemInstance:
	if not CozyLootDefs.exists(pick_id) or CozyLootDefs.kind(pick_id) != "pick":
		return null

	var picked := _pick(pick_id, rng)
	if picked == "":
		return null

	# A PICK ENTRY NAMES EITHER A TYPE OR ONE DEFINITION. A type is "some weapon"
	# and one definition is "this sword" — and the second is not expressible
	# through the first, because `weapon` has three items in it and a designed
	# reward is a particular one of them.
	#
	# Checked before the type table, and the two cannot collide: an item id is
	# never a type name (`steel_sword` is not a type, `weapon` is not a
	# definition), and `complaints()` refuses an entry that names neither.
	var definition := ""
	if CozyItemDefs.exists(picked):
		definition = picked
	else:
		var choices := CozyLootDefs.items_of_type(picked)
		if choices.is_empty():
			return null
		# The item within the type is drawn too, rather than taken as the first,
		# so a type with two swords is two swords and not one sword and a dead row.
		definition = choices[rng.randi_range(0, choices.size() - 1)]
	var rarity := CozyItemGenerator.roll_rarity(rng)
	return CozyItemGenerator.generate(definition, rarity, DROP_LEVEL, rng,
		"item_%03d" % instance_id)


## Which entry a pick table draws, in proportion to its weights.
##
## One draw scaled by the total, walked in table order, so the outcome is fixed by
## one number from the seed. A per-entry dice would give the same distribution and
## would not be reproducible from a single value.
static func _pick(table_id: String, rng: RandomNumberGenerator) -> String:
	var list := CozyLootDefs.entries(table_id)
	var total := 0.0
	for e in list:
		total += float((e as Dictionary).get("weight", 0.0))
	if total <= 0.0:
		return ""
	var roll := rng.randf() * total
	var acc := 0.0
	for e in list:
		acc += float((e as Dictionary).get("weight", 0.0))
		if roll <= acc:
			return CozyLootDefs.entry_target(e)
	# Only reachable by floating-point error at the very top of the range, and
	# falling back to the LAST entry keeps it biased towards the rarest rather
	# than the commonest.
	return CozyLootDefs.entry_target(list[list.size() - 1])


## A table's drop rates, measured rather than stated.
##
## For the developer mode's loot simulator (document section 44) and for the
## assertion that a stated `chance` is the rate a player actually sees. Counts
## per kind, so a table can be checked without a monster and without waiting for
## a lucky roll.
static func simulate(table_id: String, count: int, seed_value := 1) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value

	var kinds := {}
	var equipment := 0
	var gold := 0
	for i in maxi(0, count):
		var r := roll(table_id, rng, 1)
		for d in (r["drops"] as Array):
			var drop: Dictionary = d
			var k := String(drop["kind"])
			kinds[k] = int(kinds.get(k, 0)) + 1
			if k == DROP_EQUIPMENT:
				equipment += 1
			elif k == DROP_GOLD:
				gold += int(drop["amount"])
	return {"rolls": count, "kinds": kinds, "gold": gold,
		"equipment_rate": float(equipment) / float(count) if count > 0 else 0.0}
