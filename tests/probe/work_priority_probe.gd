extends SceneTree
## MEASUREMENT, NOT AN ASSERTION. What does a resident actually want, hour by
## hour, per trade?
##
## This exists because the answer was surprising and had to be written down
## before anything was changed: `CozySchedule.ACTIVITY_POINTS` maps the activity
## `work` to the point type `work`, and `work` is what a research table offers.
## So during the two working blocks of the day EVERY trade is overridden by the
## generic point type — a woodcutter seeks a desk.
##
## Run:
##     godot --headless --path <repo> --script res://tests/probe/work_priority_probe.gd

const PREFIX := "[probe]"

const HOURS := [3.0, 8.0, 9.0, 13.0, 19.0, 23.0]
const JOBS := ["researcher", "builder", "hauler", "cook", "farmer", "woodcutter", "miner"]


func _initialize() -> void:
	print("%s what each trade seeks, by hour" % PREFIX)
	print("%s %-12s %-8s %-10s %s" % [PREFIX, "trade", "hour", "activity", "want"])
	for job in JOBS:
		for h in HOURS:
			var clock := CozyTimeSystem.new()
			clock.hour = h
			var agent := CozyNpcAgent.new()
			agent.npc_state = CozyNpcState.create("probe", "Probe", job, 7)
			agent.clock = clock
			print("%s %-12s %-8.0f %-10s [%s]   (job's own point type: '%s')" % [
				PREFIX, job, h, CozySchedule.activity_at(h),
				", ".join(agent.want_point_types()),
				CozyJobDefs.point_type(job)])
			agent.free()
			clock.free()

	# And the same question for the trades the world actually contains.
	print("%s ---- the trades the world has resources for ----" % PREFIX)
	var trade_wants := {"woodcutter": "chop", "miner": "mine", "farmer": "harvest"}
	var clock2 := CozyTimeSystem.new()
	clock2.hour = 9.0
	for job in trade_wants:
		var agent2 := CozyNpcAgent.new()
		agent2.npc_state = CozyNpcState.create("probe", "Probe", job, 7)
		agent2.clock = clock2
		var ranked := agent2.want_point_types()
		var want := ranked[0] if not ranked.is_empty() else ""
		print("%s at 09:00 a %s seeks '%s', and the world's '%s' points are therefore %s" % [
			PREFIX, job, want, trade_wants[job],
			"UNREACHABLE" if want != trade_wants[job] else "reachable"])
		agent2.free()
	clock2.free()
	quit(0)
