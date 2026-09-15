class_name CozyItemDefs
extends RefCounted
## What an item IS, and how rare things are.
##
## Section 2.1 of the design document calls the split between a definition and an
## instance "the most important design in the whole equipment system", and it is
## the same split the rest of this project already makes: a campfire definition
## is not a campfire, and a wall's state is not the wall solver. What this table
## holds is the part that is SHARED by every copy — an iron sword's name, its
## slot, and what it is worth before any affix is rolled.
##
## ---------------------------------------------------------------------------
## WHAT IS DELIBERATELY NOT HERE YET.
##
## `hands` and `range` are in the document's weapon definition (section 11), and
## nothing reads them: the shield rule they exist for — right click guards with a
## shield and shoves without one — is answered from `type` and `slot`, and the
## combat driver that would use a reach is not written. They arrive on the day
## something reads them. A field nothing consumes is this project's most
## expensive habit and it has seven entries in `docs/INVARIANTS.md`.

## What a character can wear, in the order a panel draws it.
##
## Willow, 2026-09-15, gave this list: helmet / chest / legs / arms / boots /
## backpack / three charms / two rings / weapon / off hand (which holds the
## shield).
const SLOTS: Array[String] = ["helmet", "armor", "legs", "arms", "boots",
	"backpack", "charm", "ring", "weapon", "offhand"]

## How many of each a character wears at once.
##
## A SLOT IS A KIND WITH A CAPACITY, NOT ONE PLACE. "Three charms and two rings"
## is the whole reason: with one place per kind, a second ring would have to
## displace the first, and `ring_1` / `ring_2` as separate ids would make the
## ring a definition names a different thing from the ring it is worn in.
##
## The order of `SLOTS` is the PANEL's order, not this table's — this one is a
## lookup, and a Dictionary's order is an implementation detail.
const SLOT_CAPACITY := {
	"helmet": 1, "armor": 1, "legs": 1, "arms": 1, "boots": 1, "backpack": 1,
	"charm": 3, "ring": 2, "weapon": 1, "offhand": 1,
}

## What to call each one on screen. ASCII, because game text has to be.
const SLOT_NAMES := {
	"helmet": "Helmet", "armor": "Chest", "legs": "Legs", "arms": "Arms",
	"boots": "Boots", "backpack": "Backpack", "charm": "Charm", "ring": "Ring",
	"weapon": "Weapon", "offhand": "Off Hand",
}

## How rare a drop is, and what rarity is WORTH.
##
## Section 13 is explicit that rarity must not decide everything: it controls the
## NUMBER of affixes, the quality of their rolls and how often it drops, and
## nothing else. So that is all this table says. A legendary is not "a better
## sword" — it is the same sword with four rolls and a smaller chance of being
## seen at all.
##
## The weights are the drop weights, so the gap between Common (100) and
## Legendary (1) IS the rarity curve, readable in one place rather than spread
## across whatever rolls it.
const RARITY := {
	"common": {"name": "Common", "affixes": 0, "weight": 100.0},
	"uncommon": {"name": "Uncommon", "affixes": 1, "weight": 45.0},
	"rare": {"name": "Rare", "affixes": 2, "weight": 18.0},
	"epic": {"name": "Epic", "affixes": 3, "weight": 5.0},
	"legendary": {"name": "Legendary", "affixes": 4, "weight": 1.0},
}

const RARITY_ORDER: Array[String] = ["common", "uncommon", "rare", "epic", "legendary"]

## The V1 item list (section 55): two weapons, a shield, two pieces of armour and
## a ring — enough for every slot rule and every affix pool to have something in
## it, and no more.
##
## `stats` is what the item is worth before affixes, in the resolver's own
## vocabulary, so a sword's damage and a ring's attack bonus are the same kind of
## number and go through the same four passes.
const ITEMS := {
	# THE STEEL SWORD IS THE ONE THE PLAYER IS MEANT TO WALK AWAY WITH, and it is
	# an iron sword with better numbers rather than a new KIND of thing: the loot
	# table hands out instances, the bag holds them and the equipment resolves
	# them, and none of those three needs to know this row exists.
	"steel_sword": {
		"name": "Steel Sword", "type": "weapon", "slot": "weapon",
		"stats": {"attack": 18.0, "attack_speed": 1.1},
	},
	"iron_sword": {
		"name": "Iron Sword", "type": "weapon", "slot": "weapon",
		"stats": {"attack": 10.0, "attack_speed": 1.0},
	},
	"wooden_axe": {
		"name": "Wooden Axe", "type": "weapon", "slot": "weapon",
		"stats": {"attack": 8.0, "attack_speed": 0.85},
	},
	"wooden_shield": {
		"name": "Wooden Shield", "type": "shield", "slot": "offhand",
		"stats": {"defense": 3.0, "physical_resistance": 0.05},
	},
	"cloth_armor": {
		"name": "Cloth Armor", "type": "armor", "slot": "armor",
		"stats": {"defense": 4.0, "max_hp": 10.0},
	},
	"leather_boots": {
		"name": "Leather Boots", "type": "boots", "slot": "boots",
		"stats": {"defense": 2.0},
	},
	"copper_ring": {
		"name": "Copper Ring", "type": "ring", "slot": "ring",
		"stats": {"max_hp": 5.0},
	},
	# ---- the slots that had nothing to go in them ---------------------------
	#
	# Every one of these exists because a slot with no item is a slot the panel
	# draws empty forever, and a player who sees four empty squares concludes the
	# game is unfinished rather than that they have not found them yet.
	"iron_helmet": {
		"name": "Iron Helmet", "type": "armor", "slot": "helmet",
		"stats": {"defense": 3.0, "max_hp": 4.0},
	},
	"leather_legs": {
		"name": "Leather Legs", "type": "armor", "slot": "legs",
		"stats": {"defense": 2.0},
	},
	"leather_arms": {
		"name": "Leather Arms", "type": "armor", "slot": "arms",
		"stats": {"defense": 1.5},
	},
	# A PACK YOU WEAR, and it does not enlarge the bag YET. The slot is here
	# because the layout calls for it; the effect arrives with the item grid that
	# would have something to put in the extra room.
	"leather_backpack": {
		"name": "Leather Backpack", "type": "armor", "slot": "backpack",
		"stats": {"max_hp": 6.0},
	},
	"jade_charm": {
		"name": "Jade Charm", "type": "trinket", "slot": "charm",
		# `luck` is a RESIDENT attribute and NOT a stat — writing it here would
		# have been a row the resolver silently ignores, which `test_loot` refused
		# by name on the first run.
		"stats": {"crit_chance": 0.03, "max_hp": 3.0},
	},
}


static func get_def(id: String) -> Dictionary:
	return ITEMS.get(id, {})


static func exists(id: String) -> bool:
	return ITEMS.has(id)


static func display_name(id: String) -> String:
	return String(get_def(id).get("name", id))


static func type_of(id: String) -> String:
	return String(get_def(id).get("type", ""))


## How many of this kind a character wears at once. 0 for a kind that is not
## one — which is how `CozyEquipment` refuses a definition rather than growing a
## slot for it.
static func capacity_of(slot_kind: String) -> int:
	return int(SLOT_CAPACITY.get(slot_kind, 0))


static func slot_name(slot_kind: String) -> String:
	return String(SLOT_NAMES.get(slot_kind, slot_kind.capitalize()))


static func is_slot(slot_kind: String) -> bool:
	return SLOTS.has(slot_kind)


static func slot_of(id: String) -> String:
	return String(get_def(id).get("slot", ""))


## What the item is worth with nothing rolled on it, in the resolver's vocabulary.
static func base_stats(id: String) -> Dictionary:
	return get_def(id).get("stats", {})


static func ids() -> Array[String]:
	var out: Array[String] = []
	for k in ITEMS:
		out.append(String(k))
	out.sort()
	return out


# ---------------------------------------------------------------- rarity

static func rarity(id: String) -> Dictionary:
	return RARITY.get(id, {})


static func is_rarity(id: String) -> bool:
	return RARITY.has(id)


static func rarity_name(id: String) -> String:
	return String(rarity(id).get("name", id))


## How many affixes this rarity rolls. Zero is a legitimate answer: a Common
## sword is a sword with nothing rolled on it, not a bug.
static func affix_count(id: String) -> int:
	return int(rarity(id).get("affixes", 0))


## Why this pair of tables is not usable, as a list of complaints. Empty is
## healthy, and the self-check asserts it — because every entry is a way for a
## drop to go wrong without anything saying so.
static func complaints() -> Array[String]:
	var out: Array[String] = []
	for id in ids():
		var d := get_def(id)
		if not SLOTS.has(String(d.get("slot", ""))):
			out.append("%s is worn in a slot nothing knows: %s" % [id, d.get("slot", "none")])
		if String(d.get("type", "")) == "":
			out.append("%s has no type, so no affix pool can contain it" % id)
		for stat in (d.get("stats", {}) as Dictionary):
			if not CozyStats.is_stat(String(stat)):
				out.append("%s is worth a stat the resolver does not know: %s" % [id, stat])
	return out
