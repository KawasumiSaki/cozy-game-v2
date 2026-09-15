extends "res://tests/unit/unit_test.gd"
## The day, and the bridge from "what should I be doing" to "what do I want".
##
## The bridge is documented as the only place that mapping exists. These cases
## hold it to that.


func _init() -> void:
	suite("schedule")
	case("every scheduled activity can be looked up", _bridge_complete)
	case("every bridge entry is reachable from the day", _bridge_has_no_orphan)
	case("the clock picks the right block", _activity_at)
	case("every block names an activity", _blocks_well_formed)
	case("the working block leaves the point type to the trade", _work_names_no_point)


## A "declared capability with no consumer" guard, as a pure test. An activity
## the day asks for but the bridge does not know about means the resident seeks
## nothing and stands still — silently.
func _bridge_complete() -> void:
	var seen := {}
	for block in CozySchedule.DEFAULT_DAY:
		seen[String(block["activity"])] = true
	for a in seen:
		is_true("activity '%s' has a bridge entry" % a,
			CozySchedule.ACTIVITY_POINTS.has(a))


## And the other direction: a bridge entry nothing schedules is dead data.
func _bridge_has_no_orphan() -> void:
	var scheduled := {}
	for block in CozySchedule.DEFAULT_DAY:
		scheduled[String(block["activity"])] = true
	for a in CozySchedule.ACTIVITY_POINTS:
		is_true("bridge entry '%s' is scheduled somewhere" % a, scheduled.has(a))


func _activity_at() -> void:
	eq("00:00 is sleep", CozySchedule.activity_at(0.0), "sleep")
	eq("08:00 is eat", CozySchedule.activity_at(8.0), "eat")
	eq("09:00 is work", CozySchedule.activity_at(9.0), "work")
	eq("12:00 is eat", CozySchedule.activity_at(12.0), "eat")
	eq("13:00 is work", CozySchedule.activity_at(13.0), "work")
	eq("19:00 is social", CozySchedule.activity_at(19.0), "social")
	eq("22:00 is sleep", CozySchedule.activity_at(22.0), "sleep")
	# The last block of the day must hold until midnight, not fall off the end.
	eq("23:59 is still sleep", CozySchedule.activity_at(23.99), "sleep")
	eq("06:59 is still sleep", CozySchedule.activity_at(6.99), "sleep")


func _blocks_well_formed() -> void:
	var last_hour := -1.0
	for block in CozySchedule.DEFAULT_DAY:
		var h := float(block["hour"])
		is_true("block at %s is in order" % h, h > last_hour)
		last_hour = h
		is_true("hour %s is inside a day" % h, h >= 0.0 and h < 24.0)
		is_true("block at %s names an activity" % h,
			not String(block["activity"]).is_empty())


## THE WORKING BLOCK NAMES NO POINT TYPE, and it is load-bearing rather than
## missing data. doc #115: "Schedule 只决定现在应该做什么类型的事情" — the schedule
## picks the KIND of hour, the Task System picks the place. `work` as a POINT
## type is what a research table offers, and mapping the category onto it made
## the schedule override every trade that is not `work`:
##
##     09:00  a woodcutter sought `work`, a miner `work`, a farmer `work`
##
## so the three gathering trades added on 09-14 could not do their own work in
## the game, and neither could a hauler (whose trade point is `store`). It stayed
## invisible because every job in the table had `point_type: "work"` when this
## bridge was written — the rule was only ever exercised by the one case it was
## written for. Measured with `tests/probe/work_priority_probe.gd`.
##
## The other blocks are asserted to still name theirs, so this case cannot pass
## by the whole bridge having quietly gone empty.
func _work_names_no_point() -> void:
	eq("the working block names no point type", CozySchedule.point_for("work"), "")
	is_true("so the trade decides; see `want_point_types()`",
		CozyJobDefs.point_type("woodcutter") == "chop")

	eq("sleeping still names a bed", CozySchedule.point_for("sleep"), "sleep")
	eq("eating still names a seat", CozySchedule.point_for("eat"), "sit")
	eq("leisure still names a seat", CozySchedule.point_for("leisure"), "sit")
