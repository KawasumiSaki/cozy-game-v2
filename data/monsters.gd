class_name CozyMonsterDefs
extends RefCounted
## What a monster IS, and what it leaves behind.
##
## The same shape as `CozyObjectDefs` and `CozyScatterRule`: a row per kind, read
## by a node that does not care which one it is. Adding a second monster is a row
## here and a row in `CozyLootDefs` — the entity, the combat and the drop do not
## change.
##
## ---------------------------------------------------------------------------
## WHAT IS DELIBERATELY NOT HERE: ANYTHING ABOUT FIGHTING BACK.
##
## These monsters are TARGETS, not opponents. They have health and a loot table
## and they do not move, guard or swing. That is not a placeholder for a missing
## feature — it is the smallest thing that makes the equipment lane reachable:
## the player can kill one, and the sword it drops can be worn and can move a
## number. Every one of those steps was built, tested and unreachable.
##
## An aggression row (`aggro_range`, `attack_id`) arrives on the day there is a
## driver that reads one, and not before — this project has eight entries in
## `docs/INVARIANTS.md` about fields declared for a consumer that never came.

const MONSTERS := {
	# The one carrying the sword. Sixty health is a handful of light swings with a
	# bare fist and two or three with anything in hand, which is the difference
	# equipping something is supposed to make.
	"brigand": {
		"name": "Brigand",
		"hp": 60.0,
		"loot": "brigand",
		"colour": Color(0.52, 0.30, 0.34),
		"size": Vector2(0.9, 0.9),
		"height": 1.7,
	},
	"slime": {
		"name": "Slime",
		"hp": 24.0,
		"loot": "slime",
		"colour": Color(0.42, 0.60, 0.38),
		"size": Vector2(0.8, 0.8),
		"height": 0.7,
	},
}


static func exists(id: String) -> bool:
	return MONSTERS.has(id)


static func get_def(id: String) -> Dictionary:
	return MONSTERS.get(id, {})


static func ids() -> Array[String]:
	var out: Array[String] = []
	for id in MONSTERS:
		out.append(String(id))
	out.sort()
	return out


static func display_name(id: String) -> String:
	var d := get_def(id)
	return String(d.get("name", id))


static func hp(id: String) -> float:
	return float(get_def(id).get("hp", 0.0))


static func loot_table(id: String) -> String:
	return String(get_def(id).get("loot", ""))


static func height(id: String) -> float:
	return float(get_def(id).get("height", 1.0))


## Why a monster definition is not usable. Empty is healthy, and the self-check
## asserts that — every one of these is a way a monster can exist and be
## unkillable or drop nothing, which nothing else in the game would notice.
static func complaints() -> Array[String]:
	var out: Array[String] = []
	for id in ids():
		var d := get_def(id)
		if String(d.get("name", "")) == "":
			out.append("%s has no name" % id)
		if float(d.get("hp", 0.0)) <= 0.0:
			out.append("%s cannot be killed: hp is not positive" % id)
		var table := loot_table(id)
		if table == "":
			out.append("%s drops nothing at all" % id)
		elif not CozyLootDefs.exists(table):
			out.append("%s drops from '%s', which is no table" % [id, table])
		elif CozyLootDefs.kind(table) != "drop":
			out.append("%s drops from '%s', which is not a drop table" % [id, table])
	return out
