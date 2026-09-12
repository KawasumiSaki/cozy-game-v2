class_name CozyAppearanceDefs
extends RefCounted
## The character-factory vocabulary (ART-14, Hybrid Pixel Diorama pipeline).
##
## A resident's look is DATA. The factory — Blender, offline — turns one
## combination into one sprite sheet, and the game only ever loads the result.
## Nothing here knows how a character is drawn.
##
## WHY A TABLE AND NOT A CLASS PER LOOK: the doc's rule is that adding content is
## adding a row (#139). A new hairstyle must not need a new node, a new script or
## a new branch — it needs an id here, and a sheet from the factory.
##
## THE IDS ARE THE INTERFACE. Whatever the factory calls `hair_05`, this file
## calls `hair_05`. Renaming one without re-rendering the other produces a
## character that silently falls back to the placeholder — which is the failure
## the whole contract exists to make visible rather than to hide.
##
## The row counts match the target Willow gave 2026-09-12 (hair 5, face 3,
## clothes 8). NOTHING IS RENDERED YET, and that is fine: the system is required
## to run with the art empty (doc 58.1). `tint` is what makes the placeholder
## differ per choice, so a wrong id is visible before any art exists.

const HAIR := {
	"hair_01": {"name": "Short crop", "tint": Color(0.30, 0.21, 0.15)},
	"hair_02": {"name": "Long straight", "tint": Color(0.42, 0.28, 0.16)},
	"hair_03": {"name": "Bun", "tint": Color(0.18, 0.14, 0.12)},
	"hair_04": {"name": "Wavy", "tint": Color(0.58, 0.40, 0.20)},
	"hair_05": {"name": "Braided", "tint": Color(0.66, 0.52, 0.30)},
}

const FACE := {
	"face_01": {"name": "Round"},
	"face_02": {"name": "Oval"},
	"face_03": {"name": "Square"},
}

const CLOTHES := {
	"clothes_01": {"name": "Plain tunic", "tint": Color(0.55, 0.42, 0.72)},
	"clothes_02": {"name": "Wool shirt", "tint": Color(0.72, 0.46, 0.34)},
	"clothes_03": {"name": "Apron", "tint": Color(0.86, 0.82, 0.72)},
	"clothes_04": {"name": "Work coat", "tint": Color(0.38, 0.46, 0.56)},
	"clothes_05": {"name": "Dress", "tint": Color(0.74, 0.52, 0.60)},
	"clothes_06": {"name": "Vest", "tint": Color(0.46, 0.54, 0.38)},
	"clothes_07": {"name": "Cloak", "tint": Color(0.34, 0.30, 0.42)},
	"clothes_08": {"name": "Overall", "tint": Color(0.52, 0.44, 0.30)},
}

## Body build. NO scale multiplier, and that is deliberate: the factory controls
## size by how much of the canvas the figure fills, so a "small" resident is a
## smaller drawing on the same sheet and the game needs no number at all. A
## multiplier here would be a second source of truth for one fact.
const BODY := {
	"small": {"name": "Small"},
	"medium": {"name": "Medium"},
	"large": {"name": "Large"},
}

## Skin tone. Named by the shade, not by a person.
const COLOR := {
	"fair": {"name": "Fair", "skin": Color(0.96, 0.80, 0.66)},
	"warm": {"name": "Warm", "skin": Color(0.90, 0.72, 0.54)},
	"olive": {"name": "Olive", "skin": Color(0.80, 0.64, 0.44)},
	"tan": {"name": "Tan", "skin": Color(0.68, 0.50, 0.34)},
	"brown": {"name": "Brown", "skin": Color(0.50, 0.34, 0.22)},
	"deep": {"name": "Deep", "skin": Color(0.34, 0.22, 0.16)},
}

const DEFAULT := {
	"hair": "hair_01",
	"face": "face_01",
	"clothes": "clothes_01",
	"body": "medium",
	"color": "fair",
}

## Every slot, in a fixed order. Used to validate an appearance and to render it.
const SLOTS: Array[String] = ["hair", "face", "clothes", "body", "color"]


static func table_for(slot: String) -> Dictionary:
	match slot:
		"hair": return HAIR
		"face": return FACE
		"clothes": return CLOTHES
		"body": return BODY
		"color": return COLOR
	return {}


## A copy of DEFAULT, so a caller can mutate one without touching the constant.
static func make_default() -> Dictionary:
	return DEFAULT.duplicate()


## Is this id real for this slot?
static func has_id(slot: String, id: String) -> bool:
	return table_for(slot).has(id)


## Every id in a slot, sorted. Deterministic, so a randomiser over it is too.
static func ids_for(slot: String) -> Array:
	var keys: Array = table_for(slot).keys()
	keys.sort()
	return keys


## Which slots of this appearance are NOT real ids. A typo has to be reportable:
## silently falling back to the placeholder is exactly how an id and a rendered
## sheet drift apart unnoticed.
static func unknown_slots(appearance: Dictionary) -> Array[String]:
	var bad: Array[String] = []
	for slot in SLOTS:
		var id := String(appearance.get(slot, ""))
		if not has_id(slot, id):
			bad.append(slot)
	return bad


## Fill in anything missing, and return the result. An appearance is allowed to
## be partial — a resident created before a slot existed must still draw.
static func normalise(appearance: Dictionary) -> Dictionary:
	var out := make_default()
	for slot in SLOTS:
		var id := String(appearance.get(slot, ""))
		if has_id(slot, id):
			out[slot] = id
	return out


static func skin_of(appearance: Dictionary) -> Color:
	var row: Dictionary = COLOR.get(String(appearance.get("color", "")), {})
	return row.get("skin", COLOR[DEFAULT["color"]]["skin"])


static func hair_tint_of(appearance: Dictionary) -> Color:
	var row: Dictionary = HAIR.get(String(appearance.get("hair", "")), {})
	return row.get("tint", HAIR[DEFAULT["hair"]]["tint"])


static func cloth_tint_of(appearance: Dictionary) -> Color:
	var row: Dictionary = CLOTHES.get(String(appearance.get("clothes", "")), {})
	return row.get("tint", CLOTHES[DEFAULT["clothes"]]["tint"])


## One line for a panel or a log.
static func describe(appearance: Dictionary) -> String:
	var parts: Array[String] = []
	for slot in SLOTS:
		var id := String(appearance.get(slot, ""))
		var row: Dictionary = table_for(slot).get(id, {})
		parts.append(String(row.get("name", id)))
	return ", ".join(parts)
