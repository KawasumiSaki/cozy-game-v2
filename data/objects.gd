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

## NOTHING HERE FOR THE NEW PLANTS, and that is the fix rather than an omission.
##
## The first version gave grass and flax verbs of their own, because
## `CozyRecipeDefs.for_point()` returns the FIRST recipe naming a point type —
## iterating ids ALPHABETICALLY — so a second recipe sharing `harvest` is never
## found and a flax plant offering `harvest` would quietly yield WHEAT.
##
## Willow, 2026-09-15: "不同的植物harvest会产生不同的产物，你逻辑先做好." Inventing a
## verb per plant is not that logic; it is the same trap with more vocabulary. THE
## OBJECT NOW NAMES ITS RECIPE — see `CozyRecipeDefs.for_object` — so every plant
## offers `harvest` and what comes out of it is a fact about the plant.

## A SHOP'S VERBS, which are not worked on the world at all — see `is_stall`.
## They are interaction rows so that a stall answers `interaction_types` like
## anything else, and a menu can find them the same way it finds `chop`.
const INTERACT_BUY := "buy"
const INTERACT_SELL := "sell"

## The verbs the PLAYER performs, as opposed to the ones a resident's job does.
##
## A SECOND KIND OF CONSUMER, AND THE VOCABULARY HAS TO SAY SO. `test_resource_chain`
## refuses a point type that an object offers and nothing wants — a rule this
## project paid for with the `chest`/`store` bug — and the player is something
## that wants. Without this list the check would have exactly two options: treat
## a shop's verbs as unclaimed, or be taught in the test file about a menu it
## cannot see.
##
## SO THIS IS THE LIST THE MENU ITERATES, not a copy kept beside it. A verb added
## here is offered by the player's menu the same day; one removed here stops being
## offered AND stops being expected, because both sides read this.
const PLAYER_VERBS: Array[String] = [
	INTERACT_CHOP, INTERACT_MINE, INTERACT_HARVEST, INTERACT_BUY, INTERACT_SELL,
]

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
	# A shop is a place, not a menu. It has no yields and no recipe: nothing is
	# produced from the world here, which is why `CozyRecipeDefs` has nothing to
	# say about its verbs and `is_stall` exists instead.
	"market_stall": {
		"name": "Market Stall",
		"kind": "station",
		"size": Vector2(1.8, 1.0),
		"height": 1.4,
		"color": Color(0.72, 0.58, 0.34),
		"trades": true,
		# Reach is longer than a tree's: you talk across a counter rather than
		# standing in the goods.
		"interactions": [
			{"type": "buy", "skill": "", "duration": 1.0, "reach": 2.0},
			{"type": "sell", "skill": "", "duration": 1.0, "reach": 2.0},
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
			{"type": "harvest", "recipe": "harvest_crop", "skill": "farming",
				"duration": 3.0, "reach": 0.8},
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
	# ---- the crafting chain's two sources (2026-09-15) ------------------------
	#
	# OBJECTS rather than scattered plants, and that is the answer to a question
	# this project has been carrying: the 2011 scattered tufts are a MultiMesh with
	# no identity, so "cut that one patch" has nothing to name. A resource node has
	# an id, a `taken` count and a regrow — everything gathering already needs.
	#
	# THEY REGROW FAST (4 h against the tree's 72): hay and flax are the bottom of a
	# chain the player will walk many times, and a three-day wait at the bottom of a
	# chain is a chain nobody climbs.
	"grass_patch": {
		"name": "Grass",
		"kind": "resource",
		"size": Vector2(0.9, 0.9),
		"height": 0.5,
		"color": Color(0.42, 0.62, 0.30),
		"yields": 3,
		"regrow_hours": 4.0,
		"interactions": [
			{"type": "harvest", "recipe": "harvest_grass", "skill": "gathering",
				"duration": 2.0, "reach": 1.1},
		],
	},
	"flax": {
		"name": "Flax",
		"kind": "resource",
		"size": Vector2(0.7, 0.7),
		"height": 0.9,
		"color": Color(0.55, 0.66, 0.78),
		"yields": 2,
		"regrow_hours": 8.0,
		"interactions": [
			{"type": "harvest", "recipe": "harvest_flax", "skill": "gathering",
				"duration": 3.0, "reach": 1.1},
		],
	},
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


## The point types this object can be worked at, in the order they are declared.
##
## The ORDER is the definition's, so a tree that could one day be climbed as well
## as felled lists `chop` first because that is what the row says.
##
## READ FROM THE DEFINITION, NOT FROM THE LIVE POINTS, and that is the whole
## point of the accessor: a spent node has no points left, so asking a stump what
## it can be used for through its points answers "nothing" — and a menu built
## that way loses the VERB rather than the availability, which is a different
## thing and a confusing one. Being worked out is a fact about whether the work
## succeeds, not about whether the verb exists.
static func interaction_types(def_id: String) -> Array[String]:
	var out: Array[String] = []
	for row in get_def(def_id).get("interactions", []):
		var t := String((row as Dictionary).get("type", ""))
		if t != "" and not out.has(t):
			out.append(t)
	return out


## How close a person has to be to work this object, in metres.
##
## The PLAYER walks up to the object rather than to an interaction point: there
## is one player, nothing path-finds for them, and a point would only be a place
## to stand. The number is still the object's own — its interaction row already
## says how near the work has to be done, and a second number here would be a
## second answer.
## Does this object trade rather than produce?
##
## A FLAG RATHER THAN A PILE OF TYPES. The verbs live in `CozyPrices` and the
## shelf lives there too, so an object that merely HAS a `buy` interaction would
## still need the price table to exist — this says the object is a shop and lets
## the two tables meet in one place instead of in the menu.
static func is_stall(def_id: String) -> bool:
	return bool(get_def(def_id).get("trades", false))


static func reach_of(def_id: String) -> float:
	var best := 0.0
	for row in get_def(def_id).get("interactions", []):
		best = maxf(best, float((row as Dictionary).get("reach", 0.0)))
	return best


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
