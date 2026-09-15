class_name CozyNpcAgent
extends CozyCharacter
## An NPC that genuinely works (V2 doc #164).
##
## The doc's hard requirement for the first version is: one NPC, but it must
## REALLY work — "warehouse -> fetch material -> walk to the research table ->
## research -> produce a result".
##
## Note what is absent from this file. There is no research-table code, no
## special case for floors, and no staircase logic. The agent asks the world
## for a WorkPoint of a type it cares about (#94), routes to it through the
## room graph and the local grid, works for the point's stated duration, and
## repeats. That is #112's "no hard-coded go_upstairs()" made real.

enum State { IDLE, GOING, WORKING }

## How close the agent must actually get before it may start working.
const ARRIVE_RADIUS := 1.5

## How much a resident moves in one hauling trip (V2-21). Not a game balance
## number — it exists so a withdrawal has a definite size, and can be replaced
## the day carrying capacity becomes a real attribute.
const HAUL_LOAD := 5.0

## The resident's data (V2-22, doc #43). STATE, not node — the agent reads it
## rather than keeping its own copy of anything, which is what makes a save file
## possible without serialising a scene tree.
var npc_state: CozyNpcState = null

## Fallbacks used only when no state is attached, so the agent still works
## standalone in a test.
var job_id := "researcher"
var job_point_type := "work"   ## What kind of interaction this agent seeks.

## The agent's own finite state machine — NOT the resident's data.
##
## Named `fsm_state` rather than `state` because `npc_state` sits three lines
## above it holding the resident, and `main.gd` legitimately reads `.state` off a
## WALL (`CozyWallState`). Copying that line for an NPC yields an int here: no
## error, no crash, just a blank panel (see INVARIANTS).
var fsm_state: State = State.IDLE

## The clock, so the agent knows what KIND of thing it should be doing (#115).
## Without one it falls back to its job, which keeps it usable in a test.
var clock: CozyTimeSystem = null

var navigator: CozyWorldNavigator = null
var objects: Array = []        ## CozyWorldObject list, refreshed by the caller.

## A SECOND point source, for work offered by the GROUND rather than by an object
## (`CozyGroundPoints`). Injected like everything else — no autoloads here.
##
## NOT folded into `objects`, and that is a rule rather than taste: `objects` is
## `Array[CozyWorldObject]`, so a point source in it is a runtime error, and the
## half-dozen readers that iterate it (`_larder_food`, `_outdoor_obstacles`,
## `_grow_the_world`, the save's entity list) all assume a world object.
var ground = null

## How to leave a world object behind at a point, for recipes that spawn one
## instead of producing items (`sow_crop`).
##
## A `Callable` rather than a reference to `main`, because the alternative is an
## agent that knows where the world lives — the same reason `navigator` and
## `clock` are injected. `main.gd` owns placement, ids, navigation and the save;
## the agent asks, and what happens is the world's business.
##
## Empty means "cannot spawn", and a recipe that wants one then refuses rather
## than eating its inputs for nothing.
var place_object := Callable()

var completions := 0

## In-game hours, handed over by whatever owns the clock.
##
## INJECTED rather than reached for: this project has no autoloads, and an agent
## that could ask the time by itself would be an agent that cannot be tested
## without a running world. `main.gd` sets it every hour, in the same pass that
## grows the world.
var now_hours := 0.0           ## Finished jobs — the visible payoff.

## Batches actually produced (doc #45's "Produce Output"). Counted separately from
## `completions` because they are different facts: a resident can finish a job and
## produce nothing, and "did the chain ever yield anything" is the question that
## a check on inputs alone cannot answer.
var produced := 0
var last_status := "spawning"

var _target_point: CozyInteractionPoint = null

## The thing that advertised `_target_point`. A point carries no back-reference
## to its owner, and hauling needs one — "the work finished" has to resolve to
## "the chest it finished at".
##
## `Node3D` RATHER THAN `CozyWorldObject` since 2026-09-15, because work can now
## be offered by the GROUND (`CozyGroundPoints`) as well as by a world object.
## Three sites below ask only world objects can answer — `container`, `def_id`,
## `take_one` — and each of them now says `is CozyWorldObject` out loud instead of
## relying on the type to have kept them honest.
var _target_object: Node3D = null
var _path := PackedVector3Array()
var _path_i := 0
var _work_left := 0.0
var _idle_timer := 0.6
var _stuck_time := 0.0
var _last_pos := Vector3.ZERO


func _ready() -> void:
	super._ready()
	if npc_state != null:
		# Speed comes from the state, so a trait or an attribute change takes
		# effect without anything having to remember to push it here.
		move_speed = npc_state.effective_move_speed()
		job_id = npc_state.job_id


## Every kind of point this resident will accept right now, MOST WANTED FIRST.
##
## The single string this replaced could only say "what I would like"; it could
## not say "and if that is not there, this". So a resident whose one preference
## had no free point stood still and retried — which is how a trade with nothing
## ripe in front of it became a resident doing nothing at all.
##
## Decided in tiers, most urgent first:
##   1. a CRITICAL need, and it is the whole list (doc #116)
##   2. otherwise the SCHEDULE says what kind of hour this is (doc #115)
##   3. and the JOB says which interaction the resident prefers (doc #138)
##
## Note that none of these name an object. The schedule resolves to an activity,
## the activity to a point TYPE, and the world is searched for one of those. That
## is what keeps `if npc_is_textile_worker: go_upstairs()` from ever being
## necessary.
func want_point_types() -> Array[String]:
	var out: Array[String] = []
	if npc_state == null:
		out.append(job_point_type)
		return out

	var urgent := npc_state.critical_need()
	if urgent != "":
		# A CRITICAL need is not a PREFERENCE, so it leads the list and does not
		# queue behind the trade: a resident out of energy does not fell one more
		# tree because no bed is free, and one who is starving does not work
		# through it.
		#
		# The one case that falls through is a need whose own point type is empty
		# — there is then nowhere to send them, and standing still is not a
		# treatment.
		#
		# A hungry resident whose pack is empty but whose larder is not goes to
		# the larder FIRST. Eating needs food (debt 15), so sending them straight
		# to a seat would have them sit and starve beside a full chest.
		if urgent == "eat" and _pack_food() <= 0.0 and _larder_food() > 0.0:
			out.append(CozyObjectDefs.INTERACT_STORE)
		_add_point_type(out, CozySchedule.point_for(urgent))
		if not out.is_empty():
			return out

	# What the day says — when it says anything. A block may name no point type
	# at all, and the working block deliberately does not: `work` is the KIND of
	# hour, and the trade is what says where (see `ACTIVITY_POINTS`).
	var schedule_type := ""
	if clock != null:
		schedule_type = CozySchedule.point_for(CozySchedule.activity_at(clock.hour))

	if schedule_type != "":
		# Sleeping, eating, resting: the day names one place and that is the list.
		_add_point_type(out, schedule_type)
		return out

	# WORKING TIME. The §45 container legs come first — a resident holding a
	# finished batch stores it before fetching more — and then EVERY KIND OF WORK
	# this resident will take on, most wanted first.
	#
	# THE WHOLE LIST, NOT ONE TYPE, and that is the change Willow asked for:
	# "所有人都可以干所有事" — a trade decides where a resident STARTS, not what
	# they are allowed to do. So a farmer whose crops are all a day from ripe picks
	# up an axe instead of standing in the field, and a cook with a free oven
	# bakes. `CozyJobDefs.point_types()` builds the list; the only thing that ever
	# removes an entry is a rule about the resident, and the one that exists is
	# skill aversion (`is_assignable`, doc §10) — applied below, to the list.
	_add_point_type(out, _production_point_type())
	for t in _permitted(CozyJobDefs.point_types(npc_state.job_id)):
		_add_point_type(out, t)
	return out


## The list with the kinds of work this resident is not allowed to do taken out.
##
## Doc §10's "厌恶：无法主动安排" is the mechanism, and it is a SKILL rule rather
## than a trade rule — aversion to `farming` is how a resident refuses farm work.
## It arrives through the point, because the POINT carries the skill: that field
## was stored and never read from Phase 4 until 2026-09-15, the seventh
## "declared with no consumer" this project has paid for, and reading it is what
## makes "everyone can do every job except what they refuse" a rule instead of a
## slogan.
##
## A point type whose skill cannot be resolved (no object offers it yet) is kept:
## refusing work because the TABLE is incomplete would hide a missing row.
func _permitted(types: Array[String]) -> Array[String]:
	var out: Array[String] = []
	for t in types:
		var skill := _skill_of_point_type(t)
		if skill == "" or npc_state.can_be_assigned_to(skill):
			out.append(t)
	return out


## Which skill a kind of work trains, taken from the RECIPE rather than from the
## station. The point's own `skill` field is doc #94's station property ("empty
## means anyone may use it") — reading it here would mean a cook baking bread at a
## research table trained research.
func _skill_of_point_type(t: String) -> String:
	return CozyRecipeDefs.skill_for_point(t)


## Append a point type to a ranked list, skipping "" and anything already there.
## Deduplicating matters because the tiers overlap: the container leg and the job
## are both `store` for a hauler, and asking the world for the same type twice
## would let the second pass pick a NEARER point of the same kind and quietly
## come back with a different answer.
func _add_point_type(into: Array[String], t: String) -> void:
	if t != "" and not into.has(t):
		into.append(t)


## There is deliberately NO single-string accessor any more. `want_point_type()`
## existed for a day alongside the list, and by the end of that day its only
## readers were the tests and a probe — the "declared with no consumer" shape this
## project has paid for seven times, kept alive by a doc comment claiming the HUD
## used it. A display that wants one word takes the first element of the list;
## a decision that wants one word is the bug the list exists to fix.


## §45's "Find Container" leg — why the chain wants the resident at a container.
##
## Two reasons, and they are the two ends of it:
##   - the pack holds finished goods   ("Store")
##   - the pack lacks inputs, and a larder could supply them
##                                     ("Find Input → Take")
##
## A larder that CANNOT supply them is not a reason to go: without that check the
## resident would walk to an empty chest, take nothing, and walk back forever.
func _production_point_type() -> String:
	# WHAT THE RESIDENT IS CARRYING is judged against everything their work can
	# produce — a reaped crop is a reason to go to the chest whoever reaped it.
	if _carrying_outputs(_work_bag()):
		return CozyObjectDefs.INTERACT_STORE
	# WHAT THEY NEED is judged against the work they would do FIRST, and it has to
	# be, because `_larder_has_inputs` asks whether ONE container can supply the
	# whole requirement in one trip. Merged across every kind of work, that
	# question becomes "does a chest hold wheat AND seed", which no chest ever
	# does — and the take-leg then never fires. Measured: the live chain went from
	# `chest wheat 8 -> 6` to `8 -> 8` with the merged view, because the resident
	# could no longer fetch the wheat it bakes with.
	#
	# The head is the trade's own specialty (`CozyJobDefs.point_types`), so this is
	# the behaviour the recipe-per-trade lookup had, kept deliberately.
	var head := _head_bag()
	if _missing_inputs(head) and _larder_has_inputs(head):
		return CozyObjectDefs.INTERACT_STORE
	return ""


## Everything the work this resident will take on consumes and produces, merged.
##
## It used to be the resident's single trade recipe. With work keyed by point type
## and every resident able to do every kind of work, the §45 legs have to reason
## about the whole set: a cook who can also reap needs the chest for wheat before
## baking and for storing the wheat they just reaped.
func _work_bag() -> Dictionary:
	return CozyRecipeDefs.for_works(CozyJobDefs.point_types(npc_state.job_id))


## The work this resident would do first — their trade's own kind — as a bag.
##
## Used for the TAKE leg only. See `_production_point_type` for why the two legs
## ask different questions.
func _head_bag() -> Dictionary:
	return CozyRecipeDefs.for_works([CozyJobDefs.point_type(npc_state.job_id)])


## Is the pack holding something FINISHED — a reason to go and put it away?
##
## ⚠️ AN ID THE SAME RESIDENT'S WORK ALSO CONSUMES IS NOT A FINISHED GOOD, and
## this line is load-bearing rather than a tidy-up. `seed` is produced by
## `harvest_crop` and consumed by `sow_crop`, so a resident holding one is holding
## both a product and the thing they are about to use. Read as a product, `store`
## outranks every kind of work every hour of the day: they walk to the chest,
## deposit the seed, withdraw it again, and never sow anything. Measured on paper
## before it was written — see `CozyRecipeDefs.for_works`.
func _carrying_outputs(r: Dictionary) -> bool:
	for id in r["outputs"]:
		if r["inputs"].has(id):
			continue
		if npc_state.inventory.count(String(id)) > 0.0:
			return true
	return false


func _missing_inputs(r: Dictionary) -> bool:
	for id in r["inputs"]:
		if npc_state.inventory.count(String(id)) < float(r["inputs"][id]):
			return true
	return false


func _larder_has_inputs(r: Dictionary) -> bool:
	for o in objects:
		if not is_instance_valid(o) or o.container == null:
			continue
		var enough := true
		for id in r["inputs"]:
			if o.container.inventory.count(String(id)) < float(r["inputs"][id]):
				enough = false
				break
		if enough:
			return true
	return false


func _pack_food() -> float:
	var t := 0.0
	if npc_state == null or npc_state.inventory == null:
		return 0.0
	for id in CozyMaterials.food_ids():
		t += npc_state.inventory.count(String(id))
	return t


func _larder_food() -> float:
	var t := 0.0
	for o in objects:
		if not is_instance_valid(o) or o.container == null:
			continue
		for id in CozyMaterials.food_ids():
			t += o.container.inventory.count(String(id))
	return t


## What the resident believes they are doing right now — for the HUD and the
## info panel, not for any decision.
func current_activity() -> String:
	if npc_state != null:
		var urgent := npc_state.critical_need()
		if urgent != "":
			return urgent
	if clock != null:
		return CozySchedule.activity_at(clock.hour)
	return "work"


## Working is the only FSM state that has a task. IDLE has not acquired one and
## GOING is walking to it — and `CozyCharacterVisuals.select` checks locomotion
## first, so a resident on the way to bed walks rather than sleeps.
##
## Note what this does NOT decide: whether the task is work, eating or sleeping.
## All three run while `fsm_state == WORKING`, which is why the animation cannot
## be selected from the FSM alone.
func is_occupied() -> bool:
	return fsm_state == State.WORKING


func _physics_process(delta: float) -> void:
	match fsm_state:
		State.IDLE:
			_idle_timer -= delta
			if _idle_timer <= 0.0:
				_acquire_job()
		State.GOING:
			_follow_path(delta)
		State.WORKING:
			_work_left -= delta
			if _work_left <= 0.0:
				_finish_work()

	# Needs advance with the clock. `current_activity()` rather than the
	# schedule alone, so a resident who is up because a need woke them recovers
	# (or does not) according to what they are actually doing.
	if npc_state != null:
		var hours := delta / CozyTimeSystem.REAL_SECONDS_PER_GAME_HOUR
		npc_state.tick(hours, current_activity(),
			clock.is_night() if clock != null else false)

	# Let the base class apply gravity and move.
	super._physics_process(delta)


# ---------------------------------------------------------------- job loop

## Find the point to walk to for the ranked list `want`, from where the agent is
## standing.
##
## RANKED FIRST, DISTANCE SECOND, and the order is the whole of the work priority
## rule. A resident that took the nearest point of any acceptable kind would do
## its trade only when the trade happened to be closer than the alternative —
## which is not a priority, it is a coin toss with a tape measure.
##
## PURE, and it takes the origin as an ARGUMENT rather than reading
## `global_position`. A decision that cannot be asked a question outside a tree
## is a decision nobody can assert, and this one is the rule that broke: at 09:00
## the list had `work` at its head for every trade, so which point a resident
## walked to was decided entirely by this function.
##
## TWO SOURCES, ONE RANKING. `objects` and the ground are scanned per TYPE rather
## than one after the other, so a nearer point of a less-wanted kind does not win
## by being in the other list. That is the same rule the ranking already follows
## inside one source, and it would be a strange priority that depended on which
## table a point came from.
##
## Returns `[point, owner]`, or `[]` when no kind on the list has a free point.
## The OWNER comes back with the point because a point carries no back-reference
## (doc #87) and hauling needs one: "the work finished" has to resolve to "the
## chest it finished at" — or to the ground, for work that leaves something
## behind rather than producing items.
func _best_point(from: Vector3, want: Array[String]) -> Array:
	for t in want:
		var best: CozyInteractionPoint = null
		# UNTYPED ON PURPOSE, and it is not laziness: this function is duck-typed
		# by design (a source only has to answer `free_points_of_type`), and the
		# unit tests hand it stubs that are not `Node3D`s at all. A typed local
		# here aborts the whole call on the first stub, which reports as "nothing
		# was picked" — a wrong answer rather than an error.
		var best_obj = null
		var best_dist := INF
		for source in _sources():
			for p in source.free_points_of_type(t):
				var d := from.distance_to(p.world_position)
				if d < best_dist:
					best_dist = d
					best = p
					best_obj = source
		if best != null:
			return [best, best_obj]      # The best kind that exists wins outright.
	return []


## Everything that can advertise a point. A list rather than a union of two
## arrays because the ground may be absent (a test, a world with no terrain) and
## because `objects` must never be written to.
func _sources() -> Array:
	var out: Array = []
	if ground != null and is_instance_valid(ground):
		out.append(ground)
	for o in objects:
		if is_instance_valid(o):
			out.append(o)
	return out


## Take the best point on offer and start walking to it. It asks the world what it
## offers rather than knowing what any object is (#87 / #94).
func _acquire_job() -> void:
	var want := want_point_types()
	var picked := _best_point(global_position, want)
	var best: CozyInteractionPoint = null
	var best_obj: Node3D = null
	if not picked.is_empty():
		best = picked[0]
		best_obj = picked[1]

	if npc_state != null and not npc_state.is_assignable():
		last_status = "aversion: will not do %s" % npc_state.job_name()
		_idle_timer = 2.0
		return

	if best == null:
		# The whole list, not its head: "no free harvest point" was once printed
		# by a resident whose list also held `chop`, and that message is what made
		# a resident with a world full of trees look like a resident with nothing
		# to do.
		last_status = "nothing to seek" if want.is_empty() \
			else "no free %s point" % ", ".join(want)
		_idle_timer = 1.0
		return

	if navigator == null:
		last_status = "no navigator"
		_idle_timer = 1.0
		return

	var pts := navigator.plan(global_position, best.world_position)
	if pts.is_empty():
		last_status = "no route: %s" % navigator.last_failure
		_idle_timer = 1.0
		return

	_target_point = best
	_target_object = best_obj
	_path = pts
	_path_i = 0
	_stuck_time = 0.0
	_last_pos = global_position
	fsm_state = State.GOING
	last_status = "walking"


func _follow_path(delta: float) -> void:
	if _path_i >= _path.size():
		_arrive()
		return

	var wp := _path[_path_i]
	var flat := Vector3(wp.x - global_position.x, 0.0, wp.z - global_position.z)

	if flat.length() < 0.45:
		_path_i += 1
		_stuck_time = 0.0
		return

	# Stuck detection must only count time spent NOT moving. Accumulating
	# unconditionally would abandon any walk lasting longer than the timeout,
	# which looks exactly like being blocked.
	if global_position.distance_to(_last_pos) < 0.02:
		_stuck_time += delta
	else:
		_stuck_time = 0.0
	_last_pos = global_position

	# Give up on a point we cannot reach rather than grinding against a wall
	# forever — furniture may have moved since the route was planned (#120).
	if _stuck_time > 3.0:
		last_status = "blocked, replanning"
		_abandon_job()
		return

	set_move_dir(flat.normalized())


func _arrive() -> void:
	stop()

	if _target_point == null or not _target_point.is_free():
		# Somebody else took the spot while we walked (doc #109).
		last_status = "spot taken"
		_abandon_job()
		return

	# Running out of waypoints is NOT the same as being there. Without this the
	# agent happily "works" from the far side of a wall — or, as happened here,
	# from the ground floor directly beneath a first-floor table after walking
	# off a landing edge.
	var d := global_position.distance_to(_target_point.world_position)
	if d > ARRIVE_RADIUS:
		last_status = "stopped %.1fm short" % d
		_abandon_job()
		return

	_target_point.occupy(self)
	_work_left = _target_point.duration
	fsm_state = State.WORKING
	last_status = "working"


func _finish_work() -> void:
	# Capture before releasing: the transfer below has to know WHAT was worked at
	# and WHERE, and every reference is cleared on the next lines.
	#
	# THE POSITION IS CAPTURED FOR THE SAME REASON, and it is easy to miss: a
	# recipe that leaves something behind (`sow_crop`) has to put it where the work
	# happened, and by the time anything knows that, the point is gone. Reading
	# `_target_point` after the release below is a null dereference.
	var finished_type := _target_point.type if _target_point != null else ""
	var finished_at := _target_point.world_position if _target_point != null else global_position
	var finished_obj := _target_object

	if _target_point != null:
		_target_point.release()
	_target_point = null
	_target_object = null
	completions += 1

	# Hauling is the one job whose work is a TRANSFER rather than a skill roll
	# (doc §45). It resolves here because "the work completed" is exactly the
	# moment at which the load is understood to have moved.
	#
	# `is CozyWorldObject` is now said OUT LOUD rather than guaranteed by the type:
	# work can be offered by the ground, and the ground has no container.
	var haul := ""
	if finished_type == CozyObjectDefs.INTERACT_STORE \
			and finished_obj is CozyWorldObject:
		haul = _haul(finished_obj)
	elif npc_state != null:
		# §45's "Produce Output". Inputs are a REQUIREMENT, not a decoration: a
		# batch with nothing to work from produces nothing, on the same rule as
		# eating needing food. A chain that can run from an empty pack is not a
		# chain, it is a conjuring trick.
		#
		# THE RECIPE FOR THE WORK JUST DONE, not for the resident's trade. Looked
		# up by trade it produced that trade's goods at whatever point the resident
		# happened to work — wheat from a farmer standing at a research table.
		# BY THE OBJECT IT FINISHED AT — `finished_obj` is right there, and the verb
		# alone cannot tell a crop from a flax plant.
		var worked := ""
		if finished_obj is CozyWorldObject:
			worked = (finished_obj as CozyWorldObject).def_id
		haul = _produce(CozyRecipeDefs.for_object(worked, finished_type), finished_at)
		# AND THE NODE IS THE POORER FOR IT. Only when something was actually
		# made — a batch that produced nothing because the pack was empty did not
		# take anything out of the ground either. Guarded on the type because the
		# ground has no `taken` to spend: it is not a node that is worked out, it
		# is a place where something is planted.
		if haul != "" and finished_obj is CozyWorldObject \
				and CozyObjectDefs.is_gathered(finished_obj.def_id):
			finished_obj.take_one(now_hours)
			finished_obj.refresh_availability(now_hours)

	# Working trains the skill of the WORK, scaled by passion (愿景 §10: ×1/×2/×4).
	# This is what makes a resident grow into their role rather than staying a
	# fixed production number.
	if npc_state != null:
		var skill_id := CozyRecipeDefs.skill_for_point(finished_type)
		if skill_id != "":
			npc_state.train(skill_id,
				maxi(1, int(round(npc_state.passion_multiplier(skill_id)))))

	fsm_state = State.IDLE
	_idle_timer = 0.8
	if haul != "":
		last_status = "%s | completed %d" % [haul, completions]
	else:
		last_status = "completed %d" % completions


## §45's "Take" and "Store" — both happen here, at a container.
##
## Which one it is follows from WHAT THE RESIDENT'S WORK CONSUMES AND PRODUCES,
## never from a per-workstation rule: put down what the work makes, pick up what
## the work needs. When neither explains the visit, they are at a chest to move
## goods, which is what hauling is.
##
## Every transfer is all-or-nothing. Depositing id by id would let a nearly-full
## chest absorb half a pack and refuse the rest, which is precisely the "goods
## quietly vanished" failure the conservation assertion exists to catch.
func _haul(obj: Node3D) -> String:
	# The ground offers `plant` and has no container, so the type is checked
	# rather than assumed. Nothing reaches here for a ground point — a `plant`
	# point is not a `store` point — and a guard that is never taken is still
	# cheaper than an invalid-property error the day something changes.
	if not (obj is CozyWorldObject):
		return "no container"
	# A cast rather than the `is` above alone: GDScript does not narrow a
	# variable's static type through `is`, so `obj.container` stays an
	# unresolvable property on Node3D.
	var wo := obj as CozyWorldObject
	var c := wo.container
	if c == null:
		return "no container"
	if npc_state == null or npc_state.inventory == null:
		return "no pack"
	var pack := npc_state.inventory

	# ONE thing per visit, in the order the chain needs it.
	#
	# Doing both at once reads as efficient and is not: a resident that deposits
	# its output and immediately draws fresh input walks away carrying two
	# different things, and every later step then has to cope with a pack that is
	# two things at once. §45 lists Take and Store as separate steps for the same
	# reason.
	#
	# Store first: a resident still holding a finished batch is not going to go
	# and fetch more materials on top of it.
	#
	# PUT DOWN EVERYTHING THE WORK MAKES, PICK UP ONLY WHAT THE NEXT WORK NEEDS —
	# the same split `_production_point_type` explains: deposits are judged against
	# all of the resident's work, withdrawals against the trade's own recipe,
	# because a chest that must hold every input at once holds none of them.
	var put := _deposit_ids(c, pack, _work_bag()["outputs"])
	if put != "":
		return put
	var got := _withdraw_for(c, pack, _head_bag()["inputs"])
	if got != "":
		return got
	if _pack_food() <= 0.0:
		var food := _withdraw_food(c, pack)
		if food != "":
			return food
	# NOTHING IN THE BAG EXPLAINS THE VISIT, so they are here to move goods. This
	# is the branch the `hauler` trade used to get for free by having no recipe;
	# with work keyed by point type there is no recipe-less trade, so the
	# fallback is written down instead of being implied by an empty table.
	return _withdraw_any(c, pack)


## §45's "Produce Output", all-or-nothing. A batch that ate its inputs and
## produced nothing is worse than one that never started.
##
## `at` is where the resident is standing when the work finishes, and it is only
## read by recipes that LEAVE SOMETHING BEHIND (`spawns`) rather than filling the
## pack. Defaulted so the existing direct callers keep compiling — `_check_production`
## drives this function on purpose, and it has no world position to give.
##
##⚠️ AND IT IS STILL ALL-OR-NOTHING WHEN THE OUTPUT IS A WORLD OBJECT, which is
## the case that is easy to get wrong. `_place_object` REFUSES SILENTLY — a crop
## needs farmland and `ground_problem` says no to anything else — so spending the
## seed first and spawning second would destroy a seed with nothing planted. The
## placement therefore happens BEFORE `pack.spend`, and a refusal returns a reason
## with the pack untouched.
func _produce(r: Dictionary, at := Vector3.ZERO) -> String:
	if r.is_empty():
		return ""
	var ins: Dictionary = r["inputs"]
	var outs: Dictionary = r["outputs"]
	var spawn := String(r.get("spawns", ""))
	var pack := npc_state.inventory

	if spawn != "":
		if not place_object.is_valid():
			return "cannot plant here"          # No world to plant into.
		if not _can_stand_at(at):
			return "nowhere to plant"
	for id in ins:
		if pack.count(String(id)) < float(ins[id]):
			return "no %s to work with" % id

	# The spawn comes second (all the inputs are known to be in hand) and before
	# anything is spent. A refusal here costs nothing and says why.
	var spawned: Node3D = null
	if spawn != "":
		spawned = place_object.call(spawn, at)
		if spawned == null:
			return "the ground refused a %s" % CozyObjectDefs.display_name(spawn)

	for id in ins:
		pack.spend({String(id): float(ins[id])})
	var made := 0.0
	var named := ""
	for id in outs:
		pack.add(String(id), float(outs[id]))
		made += float(outs[id])
		named = String(id)
	produced += 1
	if spawn != "":
		# Named rather than counted: "made 0 " with an empty name is what a
		# spawn-only recipe reports otherwise, and it reads like a bug.
		return "planted a %s" % CozyObjectDefs.display_name(spawn)
	return "made %.0f %s" % [made, named]


## Is there anywhere for a spawned thing to stand at `at`?
##
## The world owns the real answer (`_place_object` asks `ground_problem` and
## refuses), and this is not a second copy of that rule — it is the cheap check
## that keeps a resident from being sent to plant in a spot the placement will
## reject. A refusal from the real call is still handled, because a rule with two
## callers has to hold for both.
func _can_stand_at(at: Vector3) -> bool:
	return is_finite(at.x) and is_finite(at.z)


func _deposit_ids(c: CozyContainerState, pack: CozyInventory, ids: Dictionary) -> String:
	var total := 0.0
	for id in ids:
		total += pack.count(String(id))
	if total <= 0.0:
		return ""
	if not c.has_room_for(total):
		return "store full (%.0f/%.0f, carrying %.0f)" % [c.stored(), c.capacity, total]
	for id in ids:
		var n := pack.count(String(id))
		if n > 0.0:
			c.deposit(String(id), n)
			pack.spend({String(id): n})
	return "stored %.0f" % total


## Draw up to `want` of one id. `want` is a Dictionary so callers can pass either
## a recipe's inputs or a single wanted food.
func _withdraw_for(c: CozyContainerState, pack: CozyInventory, want: Dictionary) -> String:
	# Fixed order, so the same chest always yields the same draw — everything
	# procedural in this project is deterministic.
	var ids: Array = want.keys()
	ids.sort()
	for id in ids:
		var need := float(want[id]) - pack.count(String(id))
		if need <= 0.0:
			continue
		var n := minf(need, c.inventory.count(String(id)))
		if n > 0.0 and c.withdraw(String(id), n):
			pack.add(String(id), n)
			return "took %.0f %s" % [n, id]
	return ""


func _withdraw_food(c: CozyContainerState, pack: CozyInventory) -> String:
	for id in CozyMaterials.food_ids():
		var n := minf(HAUL_LOAD, c.inventory.count(String(id)))
		if n > 0.0 and c.withdraw(String(id), n):
			pack.add(String(id), n)
			return "took %.0f %s" % [n, id]
	return ""


func _withdraw_any(c: CozyContainerState, pack: CozyInventory) -> String:
	var have := c.sorted_ids()
	if have.is_empty():
		return ""
	var id := String(have[0])
	var n := minf(HAUL_LOAD, c.inventory.count(id))
	if not c.withdraw(id, n):
		return ""
	pack.add(id, n)
	return "took %.0f %s" % [n, id]


## Read-only accessors (2026-09-12) so the pathing probe can see what the agent
## chose without the probe having to guess. They ADD nothing to the agent's
## behaviour — `_acquire_job` is deliberately untouched while debt 22 is being
## measured rather than assumed.
func target_point() -> CozyInteractionPoint:
	return _target_point


## The thing the current work is being done at: a world object, or the ground.
##
## `Node3D` rather than `CozyWorldObject` since 2026-09-15 — work can be offered
## by the ground, which is not an object. The only readers are probes, and
## `_object_label` already answers for anything.
func target_object() -> Node3D:
	return _target_object


func current_path() -> PackedVector3Array:
	return _path


func path_index() -> int:
	return _path_i


func _abandon_job() -> void:
	if _target_point != null:
		_target_point.release()
	_target_point = null
	_target_object = null
	_path = PackedVector3Array()
	fsm_state = State.IDLE
	_idle_timer = 0.5


func status_line() -> String:
	if npc_state != null:
		return "%s | %s | %s | done %d" % [
			npc_state.describe(), current_activity(), last_status, completions]
	return "%s | %s | done %d" % [job_id, last_status, completions]


## Verbose state for the headless probe.
##
## `want=` prints the WHOLE ranked list rather than its head, because the list is
## the thing a probe about priorities is asking about: a resident that chose
## `chop` while the list also held `store` is a different fact from one whose list
## was `chop` alone.
func debug_line() -> String:
	var wp := Vector3.ZERO
	if _path_i < _path.size():
		wp = _path[_path_i]
	return "npc %s pos=(%.2f,%.2f,%.2f) wp=%d/%d -> (%.2f,%.2f,%.2f) stuck=%.1f want=[%s] act=%s why=%s" % [
		State.keys()[fsm_state], global_position.x, global_position.y, global_position.z,
		_path_i, _path.size(), wp.x, wp.y, wp.z, _stuck_time,
		", ".join(want_point_types()), current_activity(), last_status]
