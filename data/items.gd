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

## What an item can be worn in (section 10). The slot is also what an
## `EquipmentManager` will key on, so two rings are two slots rather than one.
const SLOTS: Array[String] = ["weapon", "shield", "helmet", "armor", "gloves",
	"boots", "ring", "amulet"]

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
	"iron_sword": {
		"name": "Iron Sword", "type": "weapon", "slot": "weapon",
		"stats": {"attack": 10.0, "attack_speed": 1.0},
	},
	"wooden_axe": {
		"name": "Wooden Axe", "type": "weapon", "slot": "weapon",
		"stats": {"attack": 8.0, "attack_speed": 0.85},
	},
	"wooden_shield": {
		"name": "Wooden Shield", "type": "shield", "slot": "shield",
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
}


static func get_def(id: String) -> Dictionary:
	return ITEMS.get(id, {})


static func exists(id: String) -> bool:
	return ITEMS.has(id)


static func display_name(id: String) -> String:
	return String(get_def(id).get("name", id))


static func type_of(id: String) -> String:
	return String(get_def(id).get("type", ""))


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
