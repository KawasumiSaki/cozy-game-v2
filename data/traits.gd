class_name CozyTraitDefs
extends RefCounted
## Resident traits (愿景 §8: "每个人拥有…性格…喜好…厌恶").
##
## A trait is a small, permanent modifier that makes two residents with the same
## skills behave differently. The doc's point is that the player manages PEOPLE
## rather than production numbers, and a trait is the cheapest thing that does
## that: one number, applied everywhere it matters, never changed.
##
## Modifiers go in a dictionary rather than as named fields, so a new trait needs
## no new code — the same data-driven rule the rest of the project follows.
## Recognised keys are applied in CozyNpcState; an unrecognised one is inert but
## harmless, which is deliberate so a trait can be authored before its effect
## exists.

const TRAITS := {
	"hard_worker": {
		"name": "Hard Worker",
		"desc": "Works a little faster at anything.",
		"modifiers": {"work_speed": 1.15},
	},
	"night_owl": {
		"name": "Night Owl",
		"desc": "Happier after dark, slower at dawn.",
		"modifiers": {"mood_night": 8.0, "mood_day": -3.0},
	},
	"green_thumb": {
		"name": "Green Thumb",
		"desc": "Plants and harvests better than the skill suggests.",
		"modifiers": {"farming_bonus": 3},
	},
	"optimist": {
		"name": "Optimist",
		"desc": "Mood recovers quickly and falls slowly.",
		"modifiers": {"mood_resilience": 1.5},
	},
	"gourmet": {
		"name": "Gourmet",
		"desc": "Cooks better food, and minds a bad meal more.",
		"modifiers": {"cooking_bonus": 3, "hunger_rate": 1.2},
	},
	"nimble": {
		"name": "Nimble",
		"desc": "Moves faster than most.",
		"modifiers": {"move_speed": 1.2},
	},
	"iron_will": {
		"name": "Iron Will",
		"desc": "Rarely rattled by anything.",
		"modifiers": {"mood_resilience": 2.0},
	},
	"lucky": {
		"name": "Lucky",
		"desc": "Fortune favours them, in loot and in mishaps.",
		"modifiers": {"luck": 5.0},
	},
	"solitary": {
		"name": "Solitary",
		"desc": "Prefers to work alone.",
		"modifiers": {"mood_crowd": -5.0},
	},
	"cheerful": {
		"name": "Cheerful",
		"desc": "Lifts the mood of everyone nearby.",
		"modifiers": {"mood_aura": 3.0},
	},
}

const ORDER: Array[String] = ["hard_worker", "night_owl", "green_thumb",
	"optimist", "gourmet", "nimble", "iron_will", "lucky", "solitary", "cheerful"]


static func exists(id: String) -> bool:
	return TRAITS.has(id)


static func get_def(id: String) -> Dictionary:
	return TRAITS.get(id, {})


static func display_name(id: String) -> String:
	return String(get_def(id).get("name", id))


static func modifiers(id: String) -> Dictionary:
	return get_def(id).get("modifiers", {})


## Deterministic trait draw from a seed (doc E.21), so a resident keeps the same
## character across a save and reload.
##
## "Optimist" turning into "Solitary" overnight is exactly the class of bug the
## deterministic-seed rule exists to prevent.
static func roll(seed_val: int, count := 3) -> Array[String]:
	var out: Array[String] = []
	var pool := ORDER.duplicate()
	var h := seed_val
	while out.size() < count and not pool.is_empty():
		h = CozyArtSeed.mix4(h, out.size(), pool.size(), 0x7A17)
		var i := h % pool.size()
		out.append(pool[i])
		pool.remove_at(i)
	return out
