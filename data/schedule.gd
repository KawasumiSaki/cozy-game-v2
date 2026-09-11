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
const ACTIVITY_POINTS := {
	"work": "work",
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


## Which interaction point type an activity wants. Empty means "nothing to
## seek" — the agent should fall through to its needs instead.
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
