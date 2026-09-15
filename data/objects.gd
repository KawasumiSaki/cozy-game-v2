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
## Gathered FROM the world rather than worked at (2026-09-14). An NPC with the
## matching job finds one of these the same way it finds a workstation: the point
## TYPE is the whole contract (doc #94), so a tree is not a thing the agent knows
## about — "a `chop` point is here" is.
##
## This is why the resource line needed no new system. `_acquire_job()` already
## scans every object for the point types `want_point_types()` ranks, and a job's
## point type is data. Adding these three rows and three jobs feeds a consumer
## that was written for furniture and does not care what it is looking at.
const INTERACT_CHOP := "chop"
const INTERACT_MINE := "mine"
const INTERACT_HARVEST := "harvest"
## SOWING — and the first point type in the project that NO OBJECT offers.
##
## A tilled field is terrain: no node, no id, nothing to initialise. So the point
## comes from `CozyGroundPoints`, which derives it from the ground and answers the
## same `free_points_of_type()` a world object does. It is declared here because
## this is the interaction vocabulary, but **an assert that every offered type is
## wanted and every wanted type is offered has to look in two places now**, and
## `test_resource_chain` names which side each type came from rather than quietly
## merging them.
const INTERACT_PLANT := "plant"

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
		# A fire is a light, and it always was. Before this the campfire glowed
		# in a world with no night to glow against.
		"light": {"color": Color(1.0, 0.72, 0.36), "energy": 3.2, "range": 7.0},
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
	# ---- resource nodes (2026-09-14) ----------------------------------------
	#
	# `kind: resource` marks the three that are gathered rather than used. The
	# skill is the one the doc's ten-skill table already has: chopping a tree is
	# GATHERING, not a new eleventh skill — "砍树" is where wood comes from, and
	# adding a skill would be a change to the doc's list rather than a row here.
	#
	# NOTE: `skill` on an interaction is currently STORED AND NEVER READ —
	# `free_points_of_type()` matches on `type` alone. It is filled in truthfully
	# because every existing row does and because the matcher should use it one
	# day, and `test_resource_chain.gd` asserts every skill named here exists, so
	# at least a typo cannot hide in it.
	"tree": {
		"name": "Tree",
		"kind": "resource",
		"size": Vector2(0.8, 0.8),
		"height": 4.0,
		"color": Color(0.30, 0.46, 0.24),
		# Three chops before it is a stump, and three days before it is a tree
		# again. A yield count is what makes chopping feel like felling rather
		# than plucking.
		"yields": 3,
		"regrow_hours": 72.0,
		"interactions": [
			{"type": "chop", "skill": "gathering", "duration": 5.0, "reach": 1.3},
		],
	},
	"rock": {
		"name": "Rock",
		"kind": "resource",
		"size": Vector2(1.2, 1.2),
		"height": 0.9,
		"color": Color(0.55, 0.55, 0.57),
		# Two loads, and then it is worked out for good: `regrow_hours` 0 means
		# the ground does not put it back. Stone has to be found, not waited for.
		"yields": 2,
		"regrow_hours": 0.0,
		"interactions": [
			{"type": "mine", "skill": "mining", "duration": 6.0, "reach": 1.3},
		],
	},
	# A crop is HARVESTED by a farmer. Planting it is placement, not an NPC
	# action, and the half of that limit which was about the AGENT is gone as of
	# 2026-09-15: `want_point_types()` returns a ranked list, so a resident holds
	# two kinds of work at once (it stores a finished load before fetching more)
	# and a job could name `plant` as well as `harvest` on the day something
	# offers one.
	#
	# What is still missing is the other half, and it is not in this file: no
	# object offers a `plant` point, and `test_resource_chain.gd` refuses a point
	# type nothing offers — deliberately, because a declared interaction with no
	# consumer is the shape this project has paid for seven times. Sowing has to
	# be worked at the GROUND, which is terrain rather than an object, so adding
	# it is a design step rather than a row. Until then the farmer harvests and
	# the player sows.
	"crop": {
		"name": "Crop",
		"kind": "resource",
		"size": Vector2(1.0, 1.0),
		"height": 0.6,
		"color": Color(0.78, 0.70, 0.36),
		# The ground it has to stand on. This is the link the farming chain was
		# missing: `Grass -> Soil -> Farmland` has existed since V2-11 and refuses
		# to skip a step, and a crop could be dropped on virgin grass anyway.
		# Empty means "anywhere", which is what every other object says.
		"requires_ground": ["farmland"],
		# One harvest, then a day before the field is worth walking back to. The
		# crop stays where it is — a stump that grows again is reversible and
		# survives a save; deleting the object is neither.
		"yields": 1,
		"regrow_hours": 24.0,
		"interactions": [
			{"type": "harvest", "skill": "farming", "duration": 3.0, "reach": 0.8},
		],
	},
	# ---- lights (2026-09-14) --------------------------------------------------
	#
	# THE SAME ROW SHAPE AS EVERYTHING ELSE. A lamp is an object with a footprint,
	# a colour and an interaction list that happens to be empty — so it is placed,
	# saved, indexed and faded by code that already existed, and the only new
	# thing in the whole system is the `light` row below.
	#
	# `energy` is what the lamp is worth at FULL dark. The world multiplies it by
	# how dark it actually is, so a lamp needs no clock of its own and turns
	# itself on at dusk without anything deciding that it should.
	"lamp_post": {
		"name": "Lamp Post",
		"kind": "light",
		"size": Vector2(0.3, 0.3),
		"height": 3.2,
		"color": Color(0.32, 0.30, 0.28),
		"light": {"color": Color(1.0, 0.88, 0.66), "energy": 5.0, "range": 9.0},
		"interactions": [],
	},
	"floor_lamp": {
		"name": "Floor Lamp",
		"kind": "light",
		"size": Vector2(0.4, 0.4),
		"height": 1.4,
		"color": Color(0.44, 0.36, 0.28),
		"light": {"color": Color(1.0, 0.82, 0.58), "energy": 2.6, "range": 6.0},
		"interactions": [],
	},
}

## Order used when cycling build choices in-game.
##
## NOTE: nothing reads this yet — the HUD's palette comes from `main.gd`'s
## `PLACE_TOOLS`, so this list is a second copy that has already been free to
## drift. It is kept in step by `test_resource_chain.gd`, which asserts every id
## here is a real object; making it the single source is a separate tidy-up.
const PLACEABLE: Array[String] = ["research_table", "chest", "bed", "chair", "campfire",
	"tree", "rock", "crop", "lamp_post", "floor_lamp"]


static func get_def(id: String) -> Dictionary:
	return OBJECTS.get(id, {})


static func exists(id: String) -> bool:
	return OBJECTS.has(id)


## How many times this can be worked before it is spent, and how long the world
## takes to put it back. Both zero for anything that is not gathered.
##
## READ THIS AS A CYCLE, NOT A COUNTER. `yields` is what one growing season is
## worth and `regrow_hours` is how long the season is; 0 hours means it never
## comes back. A forge is not "gathered", so it has neither.
const NO_YIELDS := 0


## Can this node still be worked, given what has been taken and when?
##
## PURE, and derived from the clock rather than from a timer per object. The same
## question asked twice at the same hour gives the same answer, which is the
## property `INVARIANTS` demands of anything refreshed per frame — and it is why
## nothing here holds a `Timer` node or accumulates `delta`.
##
## `worked_at` is a game-hour timestamp (`CozyTimeSystem`), not a wall clock, so
## a save and a reload land in the same season they were left in.
static func available(def_id: String, taken: int, worked_at: float, now: float) -> bool:
	var d := get_def(def_id)
	var yields := int(d.get("yields", NO_YIELDS))
	if yields <= 0:
		return true                      # Not gathered; nothing to exhaust.
	if taken < yields:
		return true
	var regrow := float(d.get("regrow_hours", 0.0))
	if regrow <= 0.0:
		return false                     # Spent for good.
	return now - worked_at >= regrow


## Is this node gathered from the world at all? Used by the self-check so a table
## that quietly stopped having any yields cannot pass.
static func is_gathered(def_id: String) -> bool:
	return int(get_def(def_id).get("yields", NO_YIELDS)) > 0


## Why this object may not stand on this ground, or "" when it may.
##
## A REASON rather than a bool, the shape `CozyOutlineGenerator.reject_reason`
## and `CozyDungeonBlueprint.reject_reason` settled on: whatever refuses a
## placement has to be able to say why, and a test can then assert on the words
## instead of on a false.
##
## It lives here, with the data, rather than in whatever code happens to place
## the object. INVARIANTS: "A rule that lives only in a mouse handler is not a
## rule" — a second caller would otherwise be free to bypass it.
static func ground_problem(def_id: String, material_id: String) -> String:
	var allowed: Array = get_def(def_id).get("requires_ground", [])
	if allowed.is_empty() or allowed.has(material_id):
		return ""
	return "%s has to stand on %s, and this ground is %s" % [
		display_name(def_id), ", ".join(allowed), material_id]


## Does any object constrain its ground? Used by the self-check, so a table that
## silently stopped constraining anything cannot pass for a table that does.
static func constrained_ids() -> Array[String]:
	var out: Array[String] = []
	for id in OBJECTS:
		if not (OBJECTS[id].get("requires_ground", []) as Array).is_empty():
			out.append(String(id))
	out.sort()
	return out


static func display_name(id: String) -> String:
	var d := get_def(id)
	return d.get("name", id)
