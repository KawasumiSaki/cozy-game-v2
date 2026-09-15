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

## A TRADE IS A PREFERENCE FOR WHERE TO START, NOT A LICENCE (2026-09-15).
##
## Willow, on how work is assigned: "没有工种这个概念，我们参考 rimworld，所有人都
## 可以干所有事，除非有那种特殊特质禁止了做什么事情."
##
## So `job_id` no longer decides what a resident is ALLOWED to do. It decides what
## they will reach for first — their specialty — and everything else follows
## behind it in one fixed order. A cook bakes bread because cooking is what they
## do best, not because the other work is closed to them, and a farmer with
## nothing ripe in front of them picks up an axe rather than standing still.
##
## What a resident is actually forbidden from doing already exists and is a
## SKILL rule, not a trade rule: `CozyNpcState.is_assignable()` and
## `CozySkills.Passion.AVERSION` — doc §10's "厌恶：无法主动安排". Aversion to
## `farming` is how a resident refuses farm work, and it needs no new mechanism.
## Nothing here had to be loosened for this: the trade was already only ever read
## through `point_type()`.

const JOBS := {
	"researcher": {
		"name": "Researcher",
		"point_type": "work",          ## Where this trade starts; see the note above
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
		"point_type": "harvest",
		"preferred_skills": ["farming"],
		"preferred_interactions": ["harvest"],
		"rest_point_type": "sit",
	},
	# The three gathering trades (2026-09-14). They are rows rather than a
	# system: each names the point TYPE its work happens at, and the agent
	# already knows how to find one of those on any object.
	#
	# `farmer` used to sit at a `work` point — the same type a research table
	# offers — which meant the resident farmed at a desk and wheat appeared. It
	# now names `harvest`, which is a point a crop actually offers. The old
	# `preferred_interactions: ["plant", "harvest"]` has lost "plant" for the
	# same reason: no object offers one, and a declared interaction with no
	# consumer is the shape this project has paid for seven times. As of
	# 2026-09-15 the GROUND offers one (`CozyGroundPoints`), so `plant` is back —
	# see `CozyWorkDefs`.
	"woodcutter": {
		"name": "Woodcutter",
		"point_type": "chop",
		"preferred_skills": ["gathering"],
		"preferred_interactions": ["chop"],
		"rest_point_type": "sit",
	},
	"miner": {
		"name": "Miner",
		"point_type": "mine",
		"preferred_skills": ["mining"],
		"preferred_interactions": ["mine"],
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


## Where this trade STARTS. Kept as a single value because seven call sites read
## it and because "which one first" is a fair question to ask of a trade; the full
## list is `point_types()`.
static func point_type(id: String) -> String:
	return String(get_def(id).get("point_type", "work"))


## Every kind of work this trade will take on, most wanted first: its own
## specialty, then the rest of the world's work in one fixed order.
##
## THIS IS WHAT "EVERYONE CAN DO EVERYTHING" MEANS IN CODE. The list is the same
## for every trade except for which entry leads it, so no trade is a licence and
## no kind of work is unreachable — which is what makes a resident whose own work
## is not available do something else instead of standing still.
##
## The tail order is `CozyWorkDefs.ORDER` rather than the recipe table's key order,
## because a resident's second choice is a design decision and should be readable
## as one.
static func point_types(id: String) -> Array[String]:
	return CozyWorkDefs.ranked_for(point_type(id))


static func preferred_skills(id: String) -> Array:
	return get_def(id).get("preferred_skills", [])


## The skill whose passion governs this job — the first preferred one, since a
## job with two preferences has to pick a primary to be assignable at all.
##
## ⚠️ NO LONGER WHAT WORK TRAINS. A resident used to train this skill whatever
## they were doing; with work keyed by point type they train the skill the POINT
## names (`CozyInteractionPoint.skill`, which had been stored and never read since
## Phase 4 — the seventh "declared with no consumer"). This stays because
## `is_assignable()` uses it and because a trade still has a defining skill.
static func primary_skill(id: String) -> String:
	var s := preferred_skills(id)
	return String(s[0]) if not s.is_empty() else ""


static func ids() -> Array:
	var out: Array = JOBS.keys()
	out.sort()
	return out
