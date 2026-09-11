class_name CozyObjectDefs
extends RefCounted
## Data-driven furniture definitions (V2 doc #134 / #135 / #136).
##
## Adding a forge or an alchemy table later means adding a row here — the object
## system, the interaction system and the NPC system do not change (#139).
## That is the entire point of the data-driven rule.
##
## KEEP IT SIMPLE FOR NOW. Each object is a box with a footprint and some
## interaction points. Real models replace the mesh later; nothing else moves.

## Interaction kinds an NPC or the player can use (doc #95).
const INTERACT_WORK := "work"
const INTERACT_SIT := "sit"
const INTERACT_SLEEP := "sleep"
const INTERACT_STORE := "store"

const OBJECTS := {
	"research_table": {
		"name": "Research Table",
		"kind": "workstation",
		"size": Vector2(1.8, 1.0),      # footprint, X x Z metres
		"height": 0.9,
		"color": Color(0.66, 0.50, 0.34),
		"interactions": [
			{"type": "work", "skill": "research", "duration": 6.0, "reach": 0.9},
		],
	},
	"chest": {
		"name": "Chest",
		"kind": "container",
		"size": Vector2(1.0, 0.7),
		"height": 0.7,
		"color": Color(0.52, 0.36, 0.24),
		# How much it holds, in the SAME units the inventory counts — doc #35's
		# "one store, many callers" means this is not "20 wood", just 20.
		"capacity": 20.0,
		"interactions": [
			{"type": "store", "skill": "", "duration": 2.0, "reach": 0.7},
		],
	},
	"bed": {
		"name": "Bed",
		"kind": "furniture",
		"size": Vector2(0.9, 2.0),
		"height": 0.5,
		"color": Color(0.62, 0.44, 0.58),
		"interactions": [
			{"type": "sleep", "skill": "", "duration": 8.0, "reach": 1.2},
		],
	},
	"campfire": {
		"name": "Campfire",
		"kind": "decoration",
		"size": Vector2(0.9, 0.9),
		"height": 0.3,
		"color": Color(0.38, 0.30, 0.24),
		# Effects this object emits (doc E.18). Declared as data so adding a
		# lantern or a forge chimney later needs no object-system change.
		"vfx": ["fire", "smoke"],
		"interactions": [
			{"type": "sit", "skill": "", "duration": 4.0, "reach": 1.0},
		],
	},
	"chair": {
		"name": "Chair",
		"kind": "furniture",
		"size": Vector2(0.6, 0.6),
		"height": 0.5,
		"color": Color(0.70, 0.56, 0.40),
		"interactions": [
			{"type": "sit", "skill": "", "duration": 4.0, "reach": 0.5},
		],
	},
}

## Order used when cycling build choices in-game.
const PLACEABLE: Array[String] = ["research_table", "chest", "bed", "chair", "campfire"]


static func get_def(id: String) -> Dictionary:
	return OBJECTS.get(id, {})


static func exists(id: String) -> bool:
	return OBJECTS.has(id)


static func display_name(id: String) -> String:
	var d := get_def(id)
	return d.get("name", id)
