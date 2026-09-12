extends "res://tests/unit/unit_test.gd"
## The animation selector, exhaustively.
##
## The integration check drives eight hand-picked cases. This drives the WHOLE
## cross product of the game's own activity vocabulary, which is cheap here and
## is where the interesting one lives: sleeping and eating both run inside
## `fsm_state == WORKING`, so a selector that reads the FSM alone plays `work`
## through a resident's entire sleep.


func _init() -> void:
	suite("character visuals")
	case("locomotion outranks intent", _locomotion)
	case("standing with no task is idle", _idle)
	case("the activity decides only once there is a task", _activity)
	case("every result is a real animation", _results_are_real)
	case("the reachable set IS the animation set", _coverage)
	case("sit activities come from the schedule", _sit_derived)


func _vocabulary() -> Array:
	var v: Array = CozySchedule.ACTIVITY_POINTS.keys()
	v.append("")            # the player, and anyone with no schedule
	return v


func _locomotion() -> void:
	for a in _vocabulary():
		eq("moving during '%s' is walking" % a,
			CozyCharacterVisuals.select(String(a), true, true), "walk")
		eq("moving during '%s' (idle) is walking" % a,
			CozyCharacterVisuals.select(String(a), true, false), "walk")


func _idle() -> void:
	for a in _vocabulary():
		eq("'%s' with no task is idle" % a,
			CozyCharacterVisuals.select(String(a), false, false), "idle")


## The one that matters. `sleep` and the sit activities happen while the FSM says
## WORKING, so "busy" alone cannot tell them apart from work.
func _activity() -> void:
	eq("sleeping is sleep, NOT work",
		CozyCharacterVisuals.select("sleep", false, true), "sleep")
	for a in CozyCharacterVisuals.sit_activities():
		eq("'%s' is a sitting pose" % a,
			CozyCharacterVisuals.select(a, false, true), "sit")
	eq("working is work", CozyCharacterVisuals.select("work", false, true), "work")
	eq("waking with a task falls through to work",
		CozyCharacterVisuals.select("wake", false, true), "work")


func _results_are_real() -> void:
	for a in _vocabulary():
		for moving in [true, false]:
			for busy in [true, false]:
				var got := CozyCharacterVisuals.select(String(a), moving, busy)
				is_true("select(%s,%s,%s) = '%s' is a known animation" % [a, moving, busy, got],
					CozyCharacterVisuals.ANIMATIONS.has(got))


## Both directions at once, and no SpriteFrames needed.
##
## Forward: everything select() can return is a real animation, or the character
## goes blank at that moment.
## Backward: everything in ANIMATIONS can be reached, or the sheet contains
## something nobody will ever see — the "declared with no consumer" trap. A
## `carry` animation would fail here, because hauling runs inside WORKING and is
## indistinguishable from any other work.
func _coverage() -> void:
	var reachable := CozyCharacterVisuals.reachable_animations().duplicate()
	var declared := CozyCharacterVisuals.ANIMATIONS.duplicate()
	reachable.sort()
	declared.sort()
	eq("reachable == declared", str(reachable), str(declared))


## The sit set is DERIVED from the schedule's own bridge table rather than
## retyped. This pins that derivation: if the schedule gains a sit activity, the
## selector must pick it up without anyone remembering to edit it.
func _sit_derived() -> void:
	var from_schedule: Array[String] = []
	for a in CozySchedule.ACTIVITY_POINTS:
		if String(CozySchedule.ACTIVITY_POINTS[a]) == "sit":
			from_schedule.append(String(a))
	from_schedule.sort()
	var derived := CozyCharacterVisuals.sit_activities().duplicate()
	derived.sort()
	eq("sit activities match the schedule bridge", str(derived), str(from_schedule))
	is_true("there is more than one sit activity", derived.size() > 1)
