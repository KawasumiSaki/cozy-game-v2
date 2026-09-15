class_name CozyRecipeDefs
extends RefCounted
## Recipes (V2.1 doc #45, and the "Recipe Definitions" row in the doc's data tree).
##
## A recipe is what turns "the resident finished working" into "something was
## produced". The doc's chain is:
##
##     Job → Need/Recipe → Find Input → Find Container → Navigate → Take
##         → Navigate to WorkPoint → Work → Produce Output → Store
##
## and the constraint that shapes this table is the line under it:
##
##     "NPC 不应该因为增加一个新工作台而增加一段特殊硬编码."
##
## So a recipe names a JOB, a POINT TYPE and ITEM IDS. It never names a
## workstation, a room, an object or a position. Adding an oven later is a row
## here; `CozyNpcAgent` does not change, exactly as adding a forge does not
## change it under `CozyObjectDefs`' own rule.
##
## INPUTS ARE A REQUIREMENT, NOT A DECORATION. A recipe whose inputs are not in
## the pack produces NOTHING — the same discipline as eating needing food. A
## production chain that can run from an empty pack is not a chain, it is a
## conjuring trick.

## Where each recipe is performed. `work` because that is what the world's
## workstations advertise today; a forge would be a different point type and this
## row would say so.
const POINT_WORK := "work"

## THE RECIPE IS KEYED BY POINT TYPE, NOT BY TRADE (2026-09-15).
##
## It used to be keyed by `job`, and `for_job()` returned the FIRST match — which
## meant a trade could only ever have one recipe, and that the farmer who reaped
## could not also sow. Looked up by the trade alone it was also simply WRONG: the
## resident produced their trade's goods at whatever point they happened to work,
## so a farmer standing at a research table produced wheat.
##
## Keying on the point type fixes both at once, and it is what "everyone can do
## every kind of work" needs: which goods come out of a job of work depends on the
## WORK, not on who is doing it. A trade is therefore a preference for where to
## start, not a licence — see `CozyJobDefs.point_types()`.
##
## `spawns` names a WORLD OBJECT the work leaves behind, and it is the first field
## in this table that is not an item id. The dungeon blueprint refuses a `spawns`
## field because nothing could resolve one; here something can —
## `CozyObjectDefs.exists()` and the ground rule it already owns — so the field
## arrives together with its validation (`test_resource_chain`), which is the rule
## that document set.

const RECIPES := {
	# ---- the crafting chain's two sources (2026-09-15) -----------------------
	#
	# Their own point types, and the header above says why: `for_point` answers by
	# point type and takes the first, so the verb a gatherable offers IS its recipe.
	"harvest_grass": {
		"job": "farmer",
		"point_type": "harvest",
		"inputs": {},
		"outputs": {"hay": 2.0},
	},
	"harvest_flax": {
		"job": "farmer",
		"point_type": "harvest",
		"inputs": {},
		"outputs": {"fibre": 2.0},
	},

	# ---- the gathering legs (2026-09-14) -------------------------------------
	#
	# Each names a point type that an object in `CozyObjectDefs` actually offers —
	# or, for `plant`, that the GROUND offers (see `CozyGroundPoints`). That is
	# asserted rather than assumed: a recipe whose point type nothing offers is a
	# resident that can never finish a task, which is exactly the failure this
	# project has paid for repeatedly.
	"chop_tree": {
		"job": "woodcutter",
		"point_type": "chop",
		"inputs": {},
		"outputs": {"wood": 4.0},
	},
	"mine_rock": {
		"job": "miner",
		"point_type": "mine",
		"inputs": {},
		"outputs": {"stone": 3.0},
	},
	# The PRIMARY producer of the food chain: the land does the work, so there
	# are no inputs. Without it `bake_bread` is waiting on wheat nothing can
	# create.
	#
	# It used to be `grow_crop` at a `work` point — the same type a research
	# table offers — so the resident farmed at a desk and wheat appeared next to
	# it. `harvest` is a point a crop actually has, and the name says what the
	# resident does rather than what happens to the field afterwards.
	#
	# AND IT YIELDS SEED, which is what `sow_crop` is worked from: keeping part of
	# the harvest back as next year's seed is what a farm actually does, and it
	# needs no second recipe, no second trade and no second point type.
	"harvest_crop": {
		"job": "farmer",
		"point_type": "harvest",
		"inputs": {},
		"outputs": {"wheat": 2.0, "seed": 1.0},
	},
	# SOWING — worked at a point the GROUND offers, because a tilled field is
	# terrain and not an object. One seed in, one crop standing where it was sown.
	#
	# NO `outputs`: the goods are the crop, which is a thing in the world with its
	# own growth cycle rather than an entry in the pack.
	"sow_crop": {
		"job": "farmer",
		"point_type": "plant",
		"inputs": {"seed": 1.0},
		"outputs": {},
		"spawns": "crop",
	},
	# The first recipe with a real input leg, so it is the one that exercises
	# "Find Input → Find Container → Take" rather than going straight to work.
	"bake_bread": {
		"job": "cook",
		"point_type": "work",
		"inputs": {"wheat": 2.0},
		"outputs": {"bread": 3.0},
	},
}

## Jobs whose work produces nothing. Not an error — a researcher with no recipe
## still works and still trains; there is simply nothing to carry afterwards.
const NONE := {}


## The skill each job of work trains, by recipe.
##
## BY RECIPE AND NOT BY TRADE, and not by the point either. A resident used to
## train their trade's skill whatever they were doing; with work keyed by point
## type the trade no longer knows. The POINT's own `skill` field is a different
## thing — doc #94's "empty means anyone may use it" makes it a property of the
## STATION, and reading it here would mean a cook baking bread at a research table
## trained `research`. What skill a job of work trains is a property of the work,
## and the work is the recipe.
##
## ⚠️ Kept next to the recipes rather than as a field on each row only because
## that is a smaller diff; `test_resource_chain` asserts the keys and the recipes
## are the same set, so the two cannot drift apart unnoticed.
const SKILLS := {
	"chop_tree": "gathering",
	"mine_rock": "mining",
	"harvest_crop": "farming",
	"sow_crop": "farming",
	"bake_bread": "cooking",
}

## Skills for kinds of work that have NO RECIPE, by point type.
##
## Hauling is the one: its "output" is a transfer rather than a thing, so there is
## nothing for a recipe to name — and it is still a trade the doc's ten-skill
## table has (`hauling`, which `hauler` already leans on). Without this, a
## resident whose finished job was a container leg trained nothing at all, and the
## live assertion that work grows a skill went red on a resident that had only
## hauled so far — a real change in behaviour rather than a broken check.
const POINT_SKILLS := {
	"store": "hauling",
}


## The skill worked at this point type, or "" when nothing says.
static func skill_for_point(point_type: String) -> String:
	for id in ids():
		if point_type(id) == point_type:
			return String(SKILLS.get(String(id), ""))
	return String(POINT_SKILLS.get(point_type, ""))


## The recipe worked at this point type, or `NONE`.
##
## The second parameter used to be a trade, and dropping it is the point: two
## residents of different trades working the same point produce the same thing,
## and one resident working two points produces two different things.
##
## ONE RECIPE PER POINT TYPE is a limit rather than a rule: this returns the first
## match in id order, so a second recipe at one type would be unreachable.
## `test_resource_chain` refuses a second one rather than letting it sit in the
## table looking usable.
## The recipe a PARTICULAR OBJECT performs for a verb — the one that matters.
##
## `for_point` answers by the verb alone and takes the FIRST match in alphabetical
## order, so three plants that all offer `harvest` would resolve to one recipe and
## two of them would produce the wrong thing. THE OBJECT DECIDES: an interaction row
## may name its `recipe`, and this is what reads it.
##
## Falls back to `for_point` so every object that predates this keeps working, and
## `complaints()` names the ones that need a recipe rather than leaving it to be
## discovered as a plant that yields wheat.
static func for_object(def_id: String, point_type: String) -> Dictionary:
	for it in CozyObjectDefs.get_def(def_id).get("interactions", []):
		var row: Dictionary = it
		if String(row.get("type", "")) != point_type:
			continue
		var named := String(row.get("recipe", ""))
		if named != "" and RECIPES.has(named):
			return RECIPES[named]
		break
	return for_point(point_type)


## Every gatherable that offers a verb more than one recipe claims, and does not
## say which one it is.
##
## THE TRAP THIS EXISTS FOR: `for_point` is first-match, so the day a second plant
## offers `harvest` one of them silently produces the other's goods. Named here
## rather than discovered as "my flax gave me wheat".
static func ambiguous_offers() -> Array[String]:
	var by_point := {}
	for id in ids():
		var pt := String(RECIPES[id]["point_type"])
		if not by_point.has(pt):
			by_point[pt] = 0
		by_point[pt] = int(by_point[pt]) + 1
	var out: Array[String] = []
	for def_id in CozyObjectDefs.OBJECTS:
		for it in CozyObjectDefs.get_def(String(def_id)).get("interactions", []):
			var row: Dictionary = it
			var pt := String(row.get("type", ""))
			if int(by_point.get(pt, 0)) < 2:
				continue
			if String(row.get("recipe", "")) == "":
				out.append("%s offers '%s', which %d recipes claim" % [
					def_id, pt, int(by_point[pt])])
	out.sort()
	return out


static func for_point(point_type: String) -> Dictionary:
	for id in ids():
		if String(RECIPES[id]["point_type"]) == point_type:
			return RECIPES[id]
	return NONE


static func ids() -> Array:
	var out: Array = RECIPES.keys()
	out.sort()
	return out


static func exists(id: String) -> bool:
	return RECIPES.has(id)


static func point_type(id: String) -> String:
	return String(RECIPES[id].get("point_type", POINT_WORK))


static func inputs(id: String) -> Dictionary:
	return RECIPES[id].get("inputs", {})


static func outputs(id: String) -> Dictionary:
	return RECIPES[id].get("outputs", {})


## Which world object this recipe leaves behind, or "" when it leaves none.
static func spawns(id: String) -> String:
	return String(RECIPES[id].get("spawns", ""))


## Every point type that is worked on the GROUND rather than at an object: the
## point types of the recipes that spawn something.
##
## This is how `CozyGroundPoints` knows what it may be asked for, instead of the
## string "plant" being written down in two places.
static func ground_point_types() -> Array[String]:
	var out: Array[String] = []
	for id in ids():
		var s := spawns(id)
		if s != "" and not out.has(point_type(id)):
			out.append(point_type(id))
	out.sort()
	return out


## The object a point of this type produces, or "" when the type is worked at an
## object that is already there.
static func spawn_for_point(point_type: String) -> String:
	for id in ids():
		if RECIPES[id]["point_type"] == point_type:
			return spawns(String(id))
	return ""


## Every point type any recipe is worked at, in a fixed order. The "work" half of
## the world's vocabulary, as opposed to the resting and eating halves.
static func work_point_types() -> Array[String]:
	var out: Array[String] = []
	for id in ids():
		var t := point_type(id)
		if not out.has(t):
			out.append(t)
	out.sort()
	return out


## Everything a resident who does all of `point_types` consumes and produces,
## merged into one pair of dictionaries.
##
## The §45 container legs ask "am I carrying finished goods?" and "do I lack
## inputs a larder could supply?", and with work keyed by point type those
## questions are about the WHOLE set of work a resident will do rather than about
## one trade's single recipe.
##
## ⚠️ THE MERGE DELIBERATELY KEEPS AN ID ON BOTH SIDES, and the caller has to
## handle it — see `CozyNpcAgent._carrying_outputs`. `seed` is produced by
## `harvest_crop` and consumed by `sow_crop`, so a resident holding one is holding
## both a finished good and the thing they are about to use. Read as a finished
## good, `store` outranks every kind of work every hour of the day: the resident
## walks to the chest, deposits the seed, withdraws it again, and never sows.
## Dropping the id here instead would lose the input leg, which is why the rule
## lives at the read site and is named there.
static func for_works(point_types: Array[String]) -> Dictionary:
	var ins := {}
	var outs := {}
	for id in ids():
		if not point_types.has(point_type(id)):
			continue
		for k in inputs(id):
			ins[k] = float(ins.get(k, 0.0)) + float(inputs(id)[k])
		for k in outputs(id):
			outs[k] = float(outs.get(k, 0.0)) + float(outputs(id)[k])
	return {"inputs": ins, "outputs": outs}


## The recipe id a job runs, or "" when it has none.
static func id_for_job(job_id: String) -> String:
	for id in ids():
		if String(RECIPES[id]["job"]) == job_id:
			return id
	return ""


## What one run of this recipe is worth in goods, inputs and outputs together.
## Used to decide whether a batch is worth starting, not for balance.
static func total_output(id: String) -> float:
	var t := 0.0
	for k in outputs(id):
		t += float(outputs(id)[k])
	return t

