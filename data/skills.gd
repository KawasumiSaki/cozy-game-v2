class_name CozySkills
extends RefCounted
## The ten skills and the passion system (愿景 §9 / §10).
##
## Data, so a new skill is a row rather than a change to the NPC system — the
## same rule the rest of the project follows.
##
## The doc fixes both the list and the passion multipliers, so they are
## constants here rather than something an NPC happens to have.

const SKILLS := {
	"combat": {"name": "Combat"},
	"melee": {"name": "Melee"},
	"farming": {"name": "Farming"},
	"cooking": {"name": "Cooking"},
	"research": {"name": "Research"},
	"building": {"name": "Building"},
	"hauling": {"name": "Hauling"},
	"mining": {"name": "Mining"},
	"gathering": {"name": "Gathering"},
	"medical": {"name": "Medical"},
}

## Fixed order, so iteration and displays are stable.
const ORDER: Array[String] = ["combat", "melee", "farming", "cooking", "research",
	"building", "hauling", "mining", "gathering", "medical"]

const MIN_LEVEL := 0
const MAX_LEVEL := 20

## Passion tiers, with the experience multipliers the doc specifies (愿景 §10).
##
##   "厌恶：无法主动安排 ｜ 无感：×1 ｜ 感兴趣：×2 ｜ 热爱：×4"
##
## HATE is not a small multiplier — it is a refusal, which is why it is a
## separate case in the code rather than a 0.0 in the table. A zero that
## multiplies still lets the work happen at no gain; the doc says the work does
## not happen at all.
enum Passion { HATE, NEUTRAL, INTERESTED, PASSIONATE }

const PASSION_NAMES := {
	Passion.HATE: "aversion",
	Passion.NEUTRAL: "neutral",
	Passion.INTERESTED: "interested",
	Passion.PASSIONATE: "passionate",
}

const PASSION_MULTIPLIER := {
	Passion.HATE: 0.0,
	Passion.NEUTRAL: 1.0,
	Passion.INTERESTED: 2.0,
	Passion.PASSIONATE: 4.0,
}


static func exists(id: String) -> bool:
	return SKILLS.has(id)


static func display_name(id: String) -> String:
	return SKILLS.get(id, {}).get("name", id)


## Levels are clamped rather than trusted. A skill is written to from several
## places and an out-of-range value would silently skew every check downstream.
static func clamp_level(v: int) -> int:
	return clampi(v, MIN_LEVEL, MAX_LEVEL)


static func passion_name(p: int) -> String:
	return PASSION_NAMES.get(p, "neutral")


static func passion_multiplier(p: int) -> float:
	return float(PASSION_MULTIPLIER.get(p, 1.0))


## The doc's rule, in one place: an aversion means the work is not assignable.
static func can_be_assigned(p: int) -> bool:
	return p != Passion.HATE


static func passion_from_name(n: String) -> Passion:
	for k in PASSION_NAMES:
		if PASSION_NAMES[k] == n.to_lower():
			return k
	return Passion.NEUTRAL


## A fresh skill table: every skill at zero, every passion neutral.
static func blank_skills() -> Dictionary:
	var out := {}
	for id in ORDER:
		out[id] = 0
	return out


static func blank_passions() -> Dictionary:
	var out := {}
	for id in ORDER:
		out[id] = Passion.NEUTRAL
	return out
