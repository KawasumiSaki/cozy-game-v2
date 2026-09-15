extends "res://tests/unit/unit_test.gd"
## What a resident will ACCEPT right now, in order.
##
## `want_point_type()` returned one string, and a string cannot say "and if that
## is not there, this". So a resident whose single preference had no free point
## stood still and retried — a trade with nothing ripe in front of it became a
## resident doing nothing at all. `want_point_types()` returns a ranked list, and
## this suite is about the ranking: which tier leads, what sits behind it, and
## that nothing on the list is a kind of point the world does not have.
##
## It also holds the hour the ranking went wrong. For a day, at 09:00, EVERY
## trade wanted `work` — because `CozySchedule` mapped the activity `work` onto
## the point type `work`, which is what a research table offers. A woodcutter
## sought a desk, and a miner and a farmer did too. The three gathering trades
## were reachable in the tables and unreachable in the game. Measured with
## `tests/probe/work_priority_probe.gd` before anything was changed; the cases
## below are that measurement, as assertions.
##
## The agent is built DETACHED — never added to a tree — so no frames run and no
## world is needed. That is why the two container cases use a stub rather than a
## real `CozyWorldObject`: instantiating one outside the tree calls `to_global()`
## on a parentless node, which logs an engine error, and this project counts
## errors. The ranking is the subject here; the chest itself is asserted against
## the real world in `main.gd`'s `_check_work_priority`.


func _init() -> void:
	suite("work priority")
	case("the trade leads the want-list at a working hour", _trade_leads_at_work)
	case("the schedule still owns the hours it names", _schedule_owns_its_hours)
	case("a critical need is the whole list", _need_is_not_a_preference)
	case("a hungry resident with no larder wants a seat, not the chest",
		_eat_without_a_larder)
	case("a hungry resident with a larder goes to it first", _eat_with_a_larder)
	case("the container leg ranks ahead of the trade", _container_leg_comes_first)
	case("every kind named is a kind the world offers", _kinds_are_real)
	case("no job in the table stands still", _lists_are_never_empty)
	case("an agent with no resident still wants something", _stateless_agent)
	case("the trade wins even when the alternative is nearer", _rank_beats_distance)
	case("and the nearer point wins within a kind", _distance_decides_inside_a_kind)
	case("a kind with nothing free is skipped", _a_spent_kind_falls_through)
	case("a list with nothing behind it picks nothing", _nothing_available)


# ---------------------------------------------------------------- the tiers

## The one that was broken. Not "the trade is on the list" — the trade LEADS it,
## which is a different and stronger claim, and the one the fix is.
func _trade_leads_at_work() -> void:
	var clock := _clock_at(9.0)
	for job in CozyJobDefs.JOBS:
		var agent := _agent(job, clock)
		var ranked := agent.want_point_types()
		is_true("'%s' wants something at 09:00" % job, not ranked.is_empty())
		eq("'%s' leads with its own trade" % job, ranked[0], CozyJobDefs.point_type(job))
		agent.free()
	clock.free()

	# And the tooth: a trade whose point type is not `work` must not be answered
	# with `work`. Without this the case above would pass on a table where every
	# job happened to work at the same kind of point — which is exactly how the
	# bug hid for a day.
	var w := _agent("woodcutter", _clock_at(9.0))
	eq("a woodcutter at 09:00 wants 'chop'", _head(w), "chop")
	is_true("and not the generic work point", not w.want_point_types().has("work"))
	w.clock.free()
	w.free()


## A ranked list must not have flattened the schedule into it: at the hours the
## day names, the day still wins. Same agent, different hour, different answer.
func _schedule_owns_its_hours() -> void:
	for job in CozyJobDefs.JOBS:
		var night := _clock_at(3.0)
		var sleeper := _agent(job, night)
		eq("'%s' sleeps at 03:00" % job, sleeper.want_point_types(), _want(["sleep"]))
		sleeper.free()
		night.free()

		var morning := _clock_at(8.0)
		var eater := _agent(job, morning)
		eq("'%s' eats at 08:00" % job, eater.want_point_types(), _want(["sit"]))
		eater.free()
		morning.free()


## A critical need is not a preference, so it does not queue behind the trade: a
## resident out of energy does not fell one more tree because no bed is free.
func _need_is_not_a_preference() -> void:
	var clock := _clock_at(9.0)
	var agent := _agent("woodcutter", clock)
	agent.npc_state.energy = CozyNpcState.ENERGY_CRITICAL - 1.0
	eq("an exhausted woodcutter wants a bed",
		agent.want_point_types(), _want(["sleep"]))
	is_true("and not a tree", not agent.want_point_types().has("chop"))

	# The same resident, rested, goes back to work — so the case above is about
	# the need and not about the agent being stuck on `sleep`.
	agent.npc_state.energy = 100.0
	eq("and back to the trade once rested", _head(agent), "chop")
	agent.free()
	clock.free()


## The other half of eating: with nothing edible anywhere, sending the resident to
## the chest first would have them walk to a container that cannot feed them and
## walk back — forever.
func _eat_without_a_larder() -> void:
	var clock := _clock_at(9.0)
	var agent := _agent("woodcutter", clock)
	agent.npc_state.hunger = CozyNpcState.HUNGER_CRITICAL
	eq("a starving resident with an empty pack wants a seat",
		agent.want_point_types(), _want(["sit"]))
	is_true("and not the chest it knows nothing about",
		not agent.want_point_types().has("store"))
	agent.free()
	clock.free()


## And its twin. The pack is empty, so eating needs food; the LARDER has some, so
## the chest is worth walking to — and it comes before the seat, because sitting
## down first means sitting down hungry.
func _eat_with_a_larder() -> void:
	var clock := _clock_at(9.0)
	var agent := _agent("woodcutter", clock)
	agent.npc_state.hunger = CozyNpcState.HUNGER_CRITICAL
	agent.objects = [_larder_with("bread", 4.0)]
	eq("a starving resident with a full larder wants the chest first",
		agent.want_point_types(), _want(["store", "sit"]))
	agent.free()

	# The same world with the larder EMPTY, so this case and the one above differ
	# by the chest's contents and nothing else — otherwise they would be each
	# other's teeth by accident, across two different worlds.
	var empty := _agent("woodcutter", clock)
	empty.npc_state.hunger = CozyNpcState.HUNGER_CRITICAL
	empty.objects = [_larder_with("", 0.0)]
	eq("and an empty one is not worth the walk",
		empty.want_point_types(), _want(["sit"]))
	empty.free()
	clock.free()


## §45's Take and Store are separate steps, so a resident holding a finished batch
## stores it before fetching more. Behind the container leg is the TRADE, which is
## what makes a full or unreachable chest cost a detour rather than the whole job.
func _container_leg_comes_first() -> void:
	var clock := _clock_at(9.0)
	var agent := _agent("woodcutter", clock)
	eq("a woodcutter with an empty pack just wants to chop",
		agent.want_point_types(), _want(["chop"]))

	agent.npc_state.inventory.add("wood", 4.0)
	eq("carrying a load, it stores first and chops after",
		agent.want_point_types(), _want(["store", "chop"]))
	agent.free()
	clock.free()


# ---------------------------------------------------------------- the guards

## The list is a promise about the world. A kind on it that nothing offers is a
## resident planning to walk to a point that does not exist — the `hauler`/`chest`
## bug, which the table-level suite catches on the TABLE and this one catches on
## the DECISION. Every job, every hour the day has.
func _kinds_are_real() -> void:
	var offered := {}
	for id in CozyObjectDefs.OBJECTS:
		for it in CozyObjectDefs.OBJECTS[id]["interactions"]:
			offered[String(it["type"])] = true
	is_true("something is offered at all", offered.size() > 0)

	var seen := 0
	for job in CozyJobDefs.JOBS:
		for hour in [3.0, 8.0, 9.0, 13.0, 19.0, 23.0]:
			var clock := _clock_at(hour)
			var agent := _agent(job, clock)
			for t in agent.want_point_types():
				seen += 1
				is_true("the %s at %02d:00 wants '%s', which something offers" % [
					job, int(hour), t], offered.has(t))
			agent.free()
			clock.free()
	# Not vacuous: an empty loop would make every line above true and prove
	# nothing, which is the failure mode this project keeps finding.
	is_true("and the walk found something to check", seen > 0)


## A job the table says exists must never leave its resident with nothing to seek.
## Teeth for a future row that names a trade with no point type.
func _lists_are_never_empty() -> void:
	var clock := _clock_at(9.0)
	for job in CozyJobDefs.JOBS:
		var agent := _agent(job, clock)
		is_true("'%s' has somewhere to go" % job, not agent.want_point_types().is_empty())
		agent.free()
	clock.free()


## The fallback path: an agent with no state at all still answers, which is what
## keeps it usable in a test.
func _stateless_agent() -> void:
	var agent := CozyNpcAgent.new()
	agent.job_point_type = "haul"
	eq("an agent with no resident wants its fallback type",
		agent.want_point_types(), _want(["haul"]))
	agent.free()


# ---------------------------------------------------------------- picking one

## RANKED FIRST, DISTANCE SECOND — the rule that decides where a resident
## actually walks. Only a world can break a tie, but this is not a tie: the
## alternative is five times nearer and must still lose.
func _rank_beats_distance() -> void:
	var agent := CozyNpcAgent.new()
	agent.objects = [
		_prop([_point("chop", Vector3(10.0, 0.0, 0.0))]),
		_prop([_point("work", Vector3(1.0, 0.0, 0.0))]),
	]
	var picked := agent._best_point(Vector3.ZERO, _want(["chop", "work"]))
	is_true("something was picked", not picked.is_empty())
	if not picked.is_empty():
		eq("the trade wins over the nearer work point",
			(picked[0] as CozyInteractionPoint).type, "chop")
	agent.free()


## Distance still decides — but only between points of the SAME kind, which is
## what makes the two rules one rule instead of a rule and a guess.
func _distance_decides_inside_a_kind() -> void:
	var agent := CozyNpcAgent.new()
	agent.objects = [
		_prop([_point("chop", Vector3(9.0, 0.0, 0.0))]),
		_prop([_point("chop", Vector3(3.0, 0.0, 0.0))]),
	]
	var picked := agent._best_point(Vector3.ZERO, _want(["chop"]))
	is_true("something was picked", not picked.is_empty())
	if not picked.is_empty():
		eq("the nearer of two trees",
			(picked[0] as CozyInteractionPoint).world_position.x, 3.0)
	agent.free()


## The fall-through, on a real decision: a kind that exists but has nothing free
## is not an answer, and the next kind down is. This is the whole reason the list
## is a list — a resident whose one preference was spent stood still and retried,
## which is how a trade with nothing ripe in front of it became a resident doing
## nothing at all.
func _a_spent_kind_falls_through() -> void:
	var agent := CozyNpcAgent.new()
	var taken := _point("chop", Vector3(1.0, 0.0, 0.0))
	taken.occupy(null)          # released again, so nothing is occupied yet
	taken.occupy(agent)         # ... and now somebody else has it
	agent.objects = [_prop([taken]), _prop([_point("work", Vector3(8.0, 0.0, 0.0))])]
	var picked := agent._best_point(Vector3.ZERO, _want(["chop", "work"]))
	is_true("something was picked", not picked.is_empty())
	if not picked.is_empty():
		eq("the occupied kind is passed over for the next one",
			(picked[0] as CozyInteractionPoint).type, "work")
	agent.free()


## And when nothing on the list is free the answer is nothing — not the nearest
## anything. `_acquire_job` reads this as "no free ... point" and idles.
func _nothing_available() -> void:
	var agent := CozyNpcAgent.new()
	agent.objects = []
	eq("an empty world offers nothing",
		agent._best_point(Vector3.ZERO, _want(["chop", "work"])).size(), 0)

	agent.objects = [_prop([_point("chop", Vector3(1.0, 0.0, 0.0))])]
	eq("and a kind nobody offers is not a fallback either",
		agent._best_point(Vector3.ZERO, _want(["mine", "harvest"])).size(), 0)
	agent.free()


# ---------------------------------------------------------------- helpers

## A point on a prop, at a place. Real `CozyInteractionPoint`s, because they are
## pure and there is no reason to fake the thing the agent hands around.
func _point(type: String, at: Vector3) -> CozyInteractionPoint:
	return CozyInteractionPoint.new(type, at, "", 1.0)


## A prop offering the given points, and nothing else — `free_points_of_type` is
## the only thing the selection asks a world object for.
func _prop(points: Array) -> _Prop:
	var p := _Prop.new()
	for pt in points:
		p.points.append(pt)
	return p


## A detached agent for `job`, on the given clock. NEVER added to a tree: no
## frames run, so nothing here can move or be moved.
func _agent(job: String, clock: CozyTimeSystem) -> CozyNpcAgent:
	var agent := CozyNpcAgent.new()
	agent.npc_state = CozyNpcState.create("probe_%s" % job, "Probe", job, 7)
	agent.clock = clock
	return agent


## What the resident most wants — the head of the list, which is all a display
## needs and all these cases are ever about.
func _head(agent: CozyNpcAgent) -> String:
	var ranked := agent.want_point_types()
	return ranked[0] if not ranked.is_empty() else ""


func _clock_at(hour: float) -> CozyTimeSystem:
	var clock := CozyTimeSystem.new()
	clock.hour = hour
	return clock


## A chest stub holding `n` of `id`. An empty `id` makes an empty container, which
## is a different case and has to be built the same way.
func _larder_with(id: String, n: float) -> _Larder:
	var l := _Larder.new()
	l.container = CozyContainerState.new()
	if id != "" and n > 0.0:
		l.container.deposit(id, n)
	return l


## Expected lists, typed. `eq` compares a ranked list against one of these, so a
## case that quietly returned an untyped array would still be compared by value.
func _want(a: Array) -> Array[String]:
	var out: Array[String] = []
	for x in a:
		out.append(String(x))
	return out


## Stands in for a chest. It carries a `container` and nothing else, because
## `container` is the only thing the ranking asks a world object for.
class _Larder extends RefCounted:
	var container: CozyContainerState = null


## Stands in for a piece of furniture: a bag of points and the one method the
## selection reads. A real `CozyWorldObject` cannot be built outside a tree — its
## `_make_points()` calls `to_global()` on a parentless node and logs an engine
## error — and this project counts errors, so the stub is the honest way to ask
## the selection a question without a world.
class _Prop extends RefCounted:
	var points: Array[CozyInteractionPoint] = []

	func free_points_of_type(t: String) -> Array[CozyInteractionPoint]:
		var out: Array[CozyInteractionPoint] = []
		for p in points:
			if p.type == t and p.is_free():
				out.append(p)
		return out
