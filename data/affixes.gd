class_name CozyAffixDefs
extends RefCounted
## What an affix IS: a stat, an operation, a range, and how likely it is.
##
## An affix DEF is not an affix. The def for `strength` says "+2 to +8 Attack";
## the affix on a particular sword says "+6". The design document's section 16
## puts it as Definition -> Roll -> Instance, which is the same split the item
## itself uses one level up, and it is the same reason: a def is shared by every
## copy of a thing and an instance belongs to one of them.
##
## ---------------------------------------------------------------------------
## `types` IS THE ONLY PLACE THE POOL IS DECLARED.
##
## The document states the relation twice — `allowed_item_types` on the affix
## (sections 14 and 18) and `allowed_affixes` on the item (section 25). Two copies
## of one fact are two answers the first time one of them is edited, which is the
## shape this project keeps paying for. Section 18 says the control is
## `allowed_item_types`, so that is the one that exists and an item's pool is
## DERIVED from it. A sword that should not roll life steal says so by life steal
## not naming weapons.
##
## ---------------------------------------------------------------------------
## THE OPERATIONS ARE `CozyStats`' OWN. The document calls them FLAT and PERCENT;
## the resolver calls them ADD and MULTIPLY. Those are two vocabularies for one
## thing, so the table uses the resolver's — a second set of names would have to
## be translated at exactly one place and would therefore be translated wrongly
## at the second.

## The roll is a FLOAT even for a flat stat. "+6.0 Attack" is a number the
## resolver adds; whether it prints as an integer is a display question, and
## making it an int here would make a 0.03 attack-speed roll impossible.
const AFFIXES := {
	"strength": {
		"name": "Strength",
		"stat": "attack", "op": CozyStats.Op.ADD,
		"min": 2.0, "max": 8.0, "weight": 100.0,
		"types": ["weapon", "armor", "gloves", "ring", "amulet"],
	},
	"defense": {
		"name": "Defense",
		"stat": "defense", "op": CozyStats.Op.ADD,
		"min": 2.0, "max": 10.0, "weight": 90.0,
		"types": ["armor", "helmet", "shield", "gloves", "boots", "ring"],
	},
	"max_hp": {
		"name": "Maximum Life",
		"stat": "max_hp", "op": CozyStats.Op.ADD,
		"min": 10.0, "max": 50.0, "weight": 80.0,
		"types": ["armor", "helmet", "shield", "boots", "ring", "amulet"],
	},
	"attack_speed": {
		"name": "Attack Speed",
		"stat": "attack_speed", "op": CozyStats.Op.MULTIPLY,
		"min": 0.03, "max": 0.08, "weight": 60.0,
		"types": ["weapon", "gloves", "ring"],
	},
	"fire_resistance": {
		"name": "Fire Resistance",
		"stat": "fire_resistance", "op": CozyStats.Op.ADD,
		"min": 2.0, "max": 10.0, "weight": 50.0,
		"types": ["armor", "helmet", "shield", "boots", "ring", "amulet"],
	},
	"ice_resistance": {
		"name": "Ice Resistance",
		"stat": "ice_resistance", "op": CozyStats.Op.ADD,
		"min": 2.0, "max": 10.0, "weight": 50.0,
		"types": ["armor", "helmet", "shield", "boots", "ring", "amulet"],
	},
	"crit_chance": {
		"name": "Critical Chance",
		"stat": "crit_chance", "op": CozyStats.Op.ADD,
		"min": 0.02, "max": 0.06, "weight": 40.0,
		"types": ["weapon", "ring", "amulet"],
	},
	"move_speed": {
		"name": "Move Speed",
		"stat": "move_speed", "op": CozyStats.Op.MULTIPLY,
		"min": 0.02, "max": 0.06, "weight": 30.0,
		"types": ["boots", "ring"],
	},
	# Weight 10 against Strength's 100, which is the whole of section 21: a rare
	# affix is rare because its number is small, not because a special case says
	# so. Making it ten times less common is a one-character edit here.
	"life_steal": {
		"name": "Life Steal",
		"stat": "life_steal", "op": CozyStats.Op.ADD,
		"min": 0.01, "max": 0.03, "weight": 10.0,
		"types": ["weapon", "ring"],
	},
}


static func get_def(id: String) -> Dictionary:
	return AFFIXES.get(id, {})


static func exists(id: String) -> bool:
	return AFFIXES.has(id)


static func display_name(id: String) -> String:
	return String(get_def(id).get("name", id))


static func ids() -> Array[String]:
	var out: Array[String] = []
	for k in AFFIXES:
		out.append(String(k))
	out.sort()
	return out


## Every affix that may appear on this kind of item.
##
## DERIVED, not stored on the item — see the header. Sorted, so the pool a
## generator walks is the same order on every machine and a seeded roll is
## reproducible.
static func pool_for(item_type: String) -> Array[String]:
	var out: Array[String] = []
	for id in ids():
		if (get_def(id)["types"] as Array).has(item_type):
			out.append(id)
	return out


## Why this affix table is not usable, as a list of complaints. Empty is healthy.
##
## The self-check asserts it empty, because every entry is a way for a roll to go
## wrong silently: a stat the resolver does not know reads as zero, a range with
## its ends the wrong way round produces a value outside the range, and a pool
## that nothing can roll is an affix that will never be seen.
static func complaints() -> Array[String]:
	var out: Array[String] = []
	for id in ids():
		var d := get_def(id)
		if not CozyStats.is_stat(String(d.get("stat", ""))):
			out.append("%s names a stat the resolver does not know: %s" % [id, d.get("stat", "none")])
		if float(d.get("min", 0.0)) > float(d.get("max", 0.0)):
			out.append("%s has its range the wrong way round" % id)
		if float(d.get("weight", 0.0)) <= 0.0:
			out.append("%s can never be rolled" % id)
		if (d.get("types", []) as Array).is_empty():
			out.append("%s fits no item type, so no pool contains it" % id)
	return out
