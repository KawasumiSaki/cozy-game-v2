class_name CozyJobDefs
extends RefCounted
## Job definitions (V2.1 doc #44 / #138).
##
## Doc #44 draws the distinction this table exists to serve:
##
##     Job  = 我负责什么     ("what am I responsible for")
##     Task = 我现在具体做什么 ("what am I doing right now")
##
## A job is a standing responsibility. It says which interactions the NPC
## prefers, which skills it leans on, and — since the doc's §45 production chain
## needs one — what it produces. It says nothing about a particular table or a
## particular staircase, which is exactly the point: the doc's worked example
## forbids `if npc_is_textile_worker: go_upstairs()`.
##
## So a job here is a filter over the world. Add a forge to the game and a
## blacksmith is a row in this table.

const JOBS := {
	"researcher": {
		"name": "Researcher",
		"point_type": "work",          ## Which InteractionPoints it looks for
		"preferred_skills": ["research"],
		"preferred_interactions": ["research"],
		"rest_point_type": "sit",
	},
	"builder": {
		"name": "Builder",
		"point_type": "work",
		"preferred_skills": ["building"],
		"preferred_interactions": ["build"],
		"rest_point_type": "sit",
	},
	"hauler": {
		"name": "Hauler",
		"point_type": "store",
		"preferred_skills": ["hauling"],
		"preferred_interactions": ["store"],
		"rest_point_type": "sit",
	},
	"cook": {
		"name": "Cook",
		"point_type": "work",
		"preferred_skills": ["cooking"],
		"preferred_interactions": ["cook"],
		"rest_point_type": "sit",
	},
	"farmer": {
		"name": "Farmer",
		"point_type": "work",
		"preferred_skills": ["farming"],
		"preferred_interactions": ["plant", "harvest"],
		"rest_point_type": "sit",
	},
}

const DEFAULT_JOB := "researcher"


static func get_def(id: String) -> Dictionary:
	return JOBS.get(id, JOBS[DEFAULT_JOB])


static func exists(id: String) -> bool:
	return JOBS.has(id)


static func display_name(id: String) -> String:
	return String(get_def(id).get("name", id))


## What kind of InteractionPoint this job seeks. The agent asks the world for
## this and never for a specific piece of furniture (doc #94).
static func point_type(id: String) -> String:
	return String(get_def(id).get("point_type", "work"))


static func preferred_skills(id: String) -> Array:
	return get_def(id).get("preferred_skills", [])


## The skill whose passion governs this job — the first preferred one, since a
## job with two preferences has to pick a primary to be assignable at all.
static func primary_skill(id: String) -> String:
	var s := preferred_skills(id)
	return String(s[0]) if not s.is_empty() else ""


static func ids() -> Array:
	var out: Array = JOBS.keys()
	out.sort()
	return out
