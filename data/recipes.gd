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

const RECIPES := {
	# The PRIMARY producer: the land does the work, so there are no inputs. This
	# is the bottom of the chain — without one of these, every other recipe is
	# waiting on materials nothing can create.
	"grow_crop": {
		"job": "farmer",
		"point_type": "work",
		"inputs": {},
		"outputs": {"wheat": 2.0},
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


static func for_job(job_id: String) -> Dictionary:
	for id in ids():
		if String(RECIPES[id]["job"]) == job_id:
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
