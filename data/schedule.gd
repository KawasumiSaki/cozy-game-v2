class_name CozySchedule
extends RefCounted
## Daily routines (V2.1 doc #114 / #115).
##
## The doc gives a concrete day and, importantly, says what a schedule is NOT:
##
##     "Schedule 不直接决定 NPC 去哪里。它只决定现在应该做什么类型的事情。
##      具体去哪儿：Task System 决定。"
##
## So a block resolves to an ACTIVITY, and the activity becomes an interaction
## point type the agent goes looking for. The schedule never names a bed or a
## chair — the same discipline doc #112 demands of the job system.
##
## The default day is the doc's own (#114):
##
##     07:00 起床   08:00 吃饭   09:00 工作   12:00 午餐
##     13:00 工作   18:00 回家   19:00 娱乐   22:00 睡觉

## Hour the block starts -> activity id. Read in order; the last block whose
## start hour has passed is the current one.
const DEFAULT_DAY := [
	{"hour": 0, "activity": "sleep"},
	{"hour": 7, "activity": "wake"},
	{"hour": 8, "activity": "eat"},
	{"hour": 9, "activity": "work"},
	{"hour": 12, "activity": "eat"},
	{"hour": 13, "activity": "work"},
	{"hour": 18, "activity": "leisure"},
	{"hour": 19, "activity": "social"},
	{"hour": 22, "activity": "sleep"},
]

## What each activity makes the agent look for. This is the bridge from "what
## kind of thing should I be doing" to "which interaction point do I want" —
## and the only place that bridge exists.
##
## Note what is absent: no furniture, no room, no specific object.
##
## TWO OF THESE ARE EMPTY, and they are empty for the same reason with two
## different consequences. "" means "this block names no point type — the
## resident's own tiers decide", which is the only honest answer for a block that
## picks the KIND of hour rather than the place:
##
##   - `wake`  : there is nothing to seek; the need system decides.
##   - `work`  : the doc's "work" is a CATEGORY, not a point type (doc #115:
##               "Schedule 只决定现在应该做什么类型的事情"). `work` as a point type
##               is what a research table offers, and mapping the category onto
##               it made the schedule override every trade that is not `work`.
##
## THE SECOND ONE WAS A BUG FOR A DAY (found 2026-09-15, measured with
## `tests/probe/work_priority_probe.gd`). At 09:00 a woodcutter sought `work`,
## a miner sought `work`, a farmer sought `work` — so the three gathering trades
## added on 09-14 were reachable in the tables and unreachable in the game, and
## so was `hauler` (whose trade point is `store`). It was invisible while every
## job in the table happened to have `point_type: "work"`, which is exactly the
## shape this project keeps paying for: a rule that is only ever exercised by the
## one case it was written for.
const ACTIVITY_POINTS := {
	"work": "",          ## The trade decides; see above
	"eat": "sit",        ## Eating happens at a seat until food items exist
	"leisure": "sit",
	"social": "sit",
	"sleep": "sleep",
	"wake": "",          ## Nothing to seek; the need system decides
}


static func activity_at(hour: float) -> String:
	var current := "sleep"
	for block in DEFAULT_DAY:
		if hour >= float(block["hour"]):
			current = String(block["activity"])
		else:
			break
	return current


## Which interaction point type an activity wants. Empty means the schedule
## names none: either there is nothing to seek (`wake`) or the KIND of hour is
## all it is saying and the resident's own trade says where (`work`). Both fall
## through to the agent's own tiers, which is what `want_point_types()` is for.
static func point_for(activity: String) -> String:
	return String(ACTIVITY_POINTS.get(activity, ""))


static func activity_name(a: String) -> String:
	match a:
		"work": return "Working"
		"eat": return "Eating"
		"leisure": return "Resting"
		"social": return "Socialising"
		"sleep": return "Sleeping"
		"wake": return "Waking"
		_: return a
