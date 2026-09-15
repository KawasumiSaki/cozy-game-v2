class_name CozyLootDefs
extends RefCounted
## What a monster leaves behind (design doc sections 22 and 23).
##
## A monster does not know what a sword is (section 53: its LootComponent "does
## not generate equipment"). It names a table, the table names things, and the
## generator turns a name into an instance — so a new drop is a row here and
## `CozyNpcAgent` and every enemy stay untouched, which is the same promise
## `CozyObjectDefs` and `CozyRecipeDefs` make.
##
## ---------------------------------------------------------------------------
## TWO KINDS OF TABLE, DELIBERATELY NOT ONE.
##
## A DROP table rolls every entry INDEPENDENTLY by its own `chance`, so two of
## them can both drop. That is what the document's Goblin example does — "Gold
## 100%, Potion 20%, Equipment 15%" — and it is why `chance` is per entry rather
## than a share of a single draw.
##
## A PICK table draws exactly `pick` things from its entries IN PROPORTION to
## their `weight`. Section 21's idea — a rare thing is rare because its number is
## small — applied to which slot a drop lands in.
##
## Mixing the two in one mechanism is how a table comes to mean two things at
## once, and the first symptom would be a drop rate nobody can explain. So they
## are separate kinds and the roller refuses a table that tries to be both.

## What an entry produces.
const KIND_ITEM := "item"        ## Something from the material vocabulary.
const KIND_GOLD := "gold"        ## Currency, which is not an item and has no row.
const KIND_EQUIPMENT := "equipment"   ## A rolled instance, by way of a pick table.

const TABLES := {
	"slime": {
		"kind": "drop",
		"entries": [
			{"kind": KIND_ITEM, "id": "wheat", "chance": 1.0, "min": 1, "max": 2},
			{"kind": KIND_ITEM, "id": "wood", "chance": 0.5, "min": 1, "max": 3},
		],
	},
	"goblin": {
		"kind": "drop",
		"entries": [
			{"kind": KIND_GOLD, "chance": 1.0, "min": 3, "max": 9},
			{"kind": KIND_ITEM, "id": "stone", "chance": 0.6, "min": 1, "max": 3},
			# The one that matters: the first thing in the game that can put a
			# rolled item with rolled affixes into a player's hands.
			{"kind": KIND_EQUIPMENT, "chance": 0.35, "pick": "goblin_gear"},
		],
	},
	"brigand": {
		"kind": "drop",
		"entries": [
			{"kind": KIND_GOLD, "chance": 1.0, "min": 5, "max": 12},
			{"kind": KIND_ITEM, "id": "stone", "chance": 0.4, "min": 1, "max": 2},
			# CERTAIN, and deliberately: this is the drop the whole equipment lane
			# exists to make possible, and a player who kills the one brigand in
			# the world and gets nothing has learned that loot is a lottery rather
			# than a reward.
			{"kind": KIND_EQUIPMENT, "chance": 1.0, "pick": "brigand_gear"},
		],
	},
	## Which SLOT the equipment lands in. Weights, not chances: exactly one of
	## these is drawn, and a weapon is four times as likely as a ring.
	##
	## NO AMULET, although the document lists the slot. `CozyItemDefs` has no
	## amulet, and a pick that can land on a type with no items in it is a drop
	## that silently does not happen — the failure this project has paid for seven
	## times, arriving through a table rather than a field. The slot joins the
	## table on the day an amulet exists, and `complaints()` will insist on it.
	## WHAT ONE PARTICULAR MONSTER IS CARRYING.
	##
	## The first table in the game that NAMES a definition rather than a type,
	## and the reason is the same one the pick table above is written the way it
	## is: "some weapon" is three swords and "the steel sword" is one of them, and
	## a designed reward is the second. A goblin drops whatever it drops; the
	## brigand is carrying the sword the player is meant to walk away with.
	"brigand_gear": {
		"kind": "pick",
		"pick": 1,
		"entries": [
			{"weight": 1.0, "item": "steel_sword"},
		],
	},
	"goblin_gear": {
		"kind": "pick",
		"pick": 1,
		"entries": [
			{"weight": 40.0, "type": "weapon"},
			{"weight": 40.0, "type": "armor"},
			{"weight": 10.0, "type": "ring"},
			{"weight": 10.0, "type": "boots"},
		],
	},
}


## What a pick entry names: ONE DEFINITION (`item`) or a TYPE (`type`).
##
## One helper rather than two keys read in three places, so the roller and the
## validator cannot disagree about which one an entry means.
static func entry_target(entry: Dictionary) -> String:
	var one := String(entry.get("item", ""))
	return one if one != "" else String(entry.get("type", ""))


static func get_def(id: String) -> Dictionary:
	return TABLES.get(id, {})


static func exists(id: String) -> bool:
	return TABLES.has(id)


static func kind(id: String) -> String:
	return String(get_def(id).get("kind", ""))


static func entries(id: String) -> Array:
	return get_def(id).get("entries", [])


static func ids() -> Array[String]:
	var out: Array[String] = []
	for k in TABLES:
		out.append(String(k))
	out.sort()
	return out


## Every item of this type, sorted. The pick table names a TYPE and this is what
## turns it into a definition, so the table never names a sword directly — the
## same discipline `CozyRecipeDefs` follows about workstations.
static func items_of_type(item_type: String) -> Array[String]:
	var out: Array[String] = []
	for id in CozyItemDefs.ids():
		if CozyItemDefs.type_of(id) == item_type:
			out.append(id)
	return out


## Why this table is not usable, as a list of complaints. Empty is healthy.
##
## The self-check asserts it empty, because every entry is a way for a drop to go
## wrong without anything saying so — and a drop that does not happen is the
## hardest kind of bug to notice, since nothing is the normal outcome of most
## rolls.
static func complaints() -> Array[String]:
	var out: Array[String] = []
	for id in ids():
		var d := get_def(id)
		var k := String(d.get("kind", ""))
		if k != "drop" and k != "pick":
			out.append("%s is neither a drop nor a pick table" % id)
			continue
		var list := entries(id)
		if list.is_empty():
			out.append("%s has no entries" % id)
			continue
		if k == "pick" and int(d.get("pick", 0)) < 1:
			out.append("%s picks nothing" % id)

		for e in list:
			var entry: Dictionary = e
			var amount := _amount_complaint(id, entry, k)
			if amount != "":
				out.append(amount)
			if k == "pick":
				var t := entry_target(entry)
				var by_type := String(entry.get("type", "")) != ""
				if t == "":
					out.append("%s has a pick entry naming nothing" % id)
				elif by_type and items_of_type(t).is_empty():
					out.append("%s can pick '%s', which no item has" % [id, t])
				elif not by_type and not CozyItemDefs.exists(t):
					out.append("%s can pick '%s', which is no item" % [id, t])
				continue
			match String(entry.get("kind", "")):
				KIND_ITEM:
					if not CozyMaterials.MATERIALS.has(String(entry.get("id", ""))):
						out.append("%s drops '%s', which is not an item" % [id, entry.get("id", "")])
				KIND_GOLD:
					pass          # Currency has no row to check against.
				KIND_EQUIPMENT:
					var pick := String(entry.get("pick", ""))
					if not exists(pick):
						out.append("%s drops equipment from '%s', which is no table" % [id, pick])
					elif kind(pick) != "pick":
						out.append("%s drops equipment from '%s', which is not a pick table" % [id, pick])
				_:
					out.append("%s has an entry of unknown kind '%s'" % [id, entry.get("kind", "")])
	return out


static func _amount_complaint(table_id: String, entry: Dictionary, table_kind: String) -> String:
	if table_kind == "pick":
		if float(entry.get("weight", 0.0)) <= 0.0:
			return "%s has a pick entry that can never be drawn" % table_id
		return ""
	var c := float(entry.get("chance", -1.0))
	if c < 0.0 or c > 1.0:
		return "%s has an entry with a chance outside 0..1" % table_id
	if int(entry.get("min", 0)) > int(entry.get("max", 0)):
		return "%s has an entry whose amount range is the wrong way round" % table_id
	return ""
