extends "res://tests/unit/unit_test.gd"
## The vocabulary has to close: every point something OFFERS is asked for, and
## every point something ASKS FOR is offered.
##
## This suite exists because "a declared capability with no consumer" is the
## mistake this project has paid for seven separate times — a `chest` advertising
## a `store` point nothing wanted, a `hauler` seeking a `store` point nothing
## offered, a `to_dict()` nothing called. Every one of them read as a working
## feature and had never once run.
##
## `grep` for the constant was the check. This makes it a check the machine runs,
## and it covers the whole table at once instead of one suspicion at a time.
##
## The two halves are each other's teeth, the same way the dungeon layout suite's
## are: if the demand side were empty, "everything offered is wanted" would be
## false rather than vacuous; if the offer side were empty, its twin would fail.
##
## Pure data throughout — no world, no nodes. The tables are the system.

const IGNORED := ""   ## An activity may deliberately seek nothing; see `wake`.


func _init() -> void:
	suite("resource chain")
	case("every point an object offers is wanted by something", _offers_are_wanted)
	case("every point a job or an activity wants is offered", _wants_are_offered)
	case("the offered set is not empty and names its trades", _offer_set_is_real)
	case("every recipe belongs to a job that exists", _recipes_have_jobs)
	case("a recipe is worked where its job works", _recipe_matches_job)
	case("every item a recipe names is a real item", _recipe_items_exist)
	case("every skill named anywhere is a real skill", _skills_exist)
	case("every job can be assigned and can rest", _jobs_are_usable)
	case("every placeable id is a real object", _placeables_exist)
	case("a crop is refused on grass and allowed on farmland", _ground_rule)
	case("a node gives its season, then waits", _yield_cycle)
	case("sowing is wired end to end", _sowing_is_wired)
	case("every job of work names the skill it trains", _work_skills_are_real)


# ---------------------------------------------------------------- the teeth

## An object that offers an interaction nothing seeks is furniture with a button
## that does nothing. `chop`, `mine` and `harvest` were in exactly this position
## before the jobs existed — the points would have been reachable and pointless.
func _offers_are_wanted() -> void:
	var wanted := _demanded_types()
	for t in _offered_types():
		is_true("'%s' is offered by an object and wanted by something" % t,
			wanted.has(t))
	# The ground is the second source and gets the same treatment. Without this
	# half, `plant` could be derived by `CozyGroundPoints` and sought by nobody —
	# which is the `chest`/`store` bug in a new place.
	for t in CozyGroundPoints.offers():
		is_true("'%s' is offered by the GROUND and wanted by something" % t,
			wanted.has(t))


## The other direction, and the more dangerous one: a job or an activity that
## seeks a point nothing offers can acquire a target it can never reach, so it
## can never finish a task. That is the `hauler`/`chest` bug exactly.
func _wants_are_offered() -> void:
	var offered := _offered_types()
	for t in CozyGroundPoints.offers():
		offered.append(t)
	for t in _demanded_types():
		is_true("'%s' is wanted and something offers it" % t, offered.has(t))


## Guards the pair above from passing because both sides are empty. Without this,
## deleting every interaction in the game would make this suite green.
func _offer_set_is_real() -> void:
	var offered := _offered_types()
	eq("nine kinds of interaction point exist", offered.size(), 9)
	for t in ["work", "sit", "sleep", "store", "chop", "mine", "harvest", "buy", "sell"]:
		is_true("'%s' is among them" % t, offered.has(t))
	is_true("gathering is a real trade to look for", offered.has("chop")
		or offered.has("mine") or offered.has("harvest"))


# ---------------------------------------------------------------- recipes

func _recipes_have_jobs() -> void:
	for id in CozyRecipeDefs.ids():
		var job := String(CozyRecipeDefs.RECIPES[id]["job"])
		is_true("recipe '%s' names a job that exists" % id, CozyJobDefs.exists(job))


## A recipe says where its work happens. That place has to be one the resident's
## own trade will reach for, and somewhere something actually offers.
##
## "IS A MEMBER OF", not "equals": a trade now has a whole ranked list of work it
## will take on (`CozyJobDefs.point_types`) and its specialty leads it. Comparing
## against the head alone would have said `sow_crop` is worked where the farmer
## does not work — which was true of a resident who could only ever do one thing,
## and is exactly what changed on 2026-09-15.
func _recipe_matches_job() -> void:
	for id in CozyRecipeDefs.ids():
		var job := String(CozyRecipeDefs.RECIPES[id]["job"])
		if not CozyJobDefs.exists(job):
			continue
		is_true("recipe '%s' is worked somewhere its trade will go" % id,
			CozyJobDefs.point_types(job).has(CozyRecipeDefs.point_type(id)))

	# And that place has to be somewhere a resident can actually reach — offered
	# by an object, or by the ground.
	var offered := _offered_types()
	for t in CozyGroundPoints.offers():
		offered.append(t)
	for id in CozyRecipeDefs.ids():
		is_true("recipe '%s' names a point something offers" % id,
			offered.has(CozyRecipeDefs.point_type(id)))


## `wheat` and `bread` are rows in the same table as `wood` and `stone`, because
## doc #35 forbids a separate food inventory. A recipe naming an item that table
## does not have would produce nothing, silently.
func _recipe_items_exist() -> void:
	for id in CozyRecipeDefs.ids():
		for want in [CozyRecipeDefs.inputs(id), CozyRecipeDefs.outputs(id)]:
			for item in want:
				is_true("recipe '%s' names a real item ('%s')" % [id, item],
					CozyMaterials.MATERIALS.has(item))

	# The food chain specifically: harvest makes wheat, baking eats it. If either
	# end drifted, the live production check in the world would be the first to
	# notice — and it would look like a production bug rather than a table one.
	eq("harvest produces wheat", CozyRecipeDefs.outputs("harvest_crop"),
		{"wheat": 2.0, "seed": 1.0})
	eq("baking consumes wheat", CozyRecipeDefs.inputs("bake_bread"), {"wheat": 2.0})


## SOWING — the leg that had nowhere to be offered from until the GROUND could
## offer a point, and the first recipe whose product is a THING IN THE WORLD
## rather than an entry in the pack.
##
## Both halves are asserted, because either one alone is useless: a `plant` point
## that spawns nothing is a resident waving at a field, and a `spawns` field
## naming an object nothing may plant is a row that reads as working.
func _sowing_is_wired() -> void:
	eq("sowing is worked on the ground", CozyGroundPoints.offers(), _want(["plant"]))
	eq("and the ground names the crop it plants", CozyGroundPoints.spawn_for("plant"), "crop")

	var r := CozyRecipeDefs.for_point("plant")
	is_true("sowing has a recipe", not r.is_empty())
	eq("it consumes a seed", CozyRecipeDefs.inputs("sow_crop"), {"seed": 1.0})
	eq("and produces the crop in the world, not in the pack",
		CozyRecipeDefs.outputs("sow_crop"), {})

	# The spawned object has to be REAL — `CozyObjectDefs.get_def()` falls back to
	# `wood` for an unknown id, so a typo here would plant timber silently.
	is_true("the crop it plants is a real object",
		CozyObjectDefs.exists(CozyRecipeDefs.spawns("sow_crop")))

	# And it has to be plantable SOMEWHERE, or the sow point is offered on ground
	# the placement rule refuses — the resident would walk out and be told no.
	var ground := "farmland"
	eq("a crop may stand on the ground the sow point is offered on",
		CozyObjectDefs.ground_problem(CozyRecipeDefs.spawns("sow_crop"), ground), "")
	# The other direction: the same call on ground it does NOT accept must refuse,
	# or the line above would pass for a rule that never refuses anything.
	is_true("and the rule still refuses other ground",
		CozyObjectDefs.ground_problem(CozyRecipeDefs.spawns("sow_crop"), "grass") != "")

	# A seed that comes from nowhere cannot be sown twice. `harvest_crop` yields
	# it, which is what a farm actually does with part of its grain.
	is_true("a seed can be obtained at all",
		float(CozyRecipeDefs.outputs("harvest_crop").get("seed", 0.0)) > 0.0)


## The skill a job of work trains. Kept beside the recipes rather than on each row
## (a smaller diff), so the two have to be held together by something.
func _work_skills_are_real() -> void:
	for id in CozyRecipeDefs.SKILLS:
		is_true("skill row '%s' is a real recipe" % id, CozyRecipeDefs.exists(id))
		is_true("and names a real skill ('%s')" % CozyRecipeDefs.SKILLS[id],
			CozySkills.exists(String(CozyRecipeDefs.SKILLS[id])))
	for id in CozyRecipeDefs.ids():
		is_true("recipe '%s' says what skill it trains" % id,
			CozyRecipeDefs.skill_for_point(CozyRecipeDefs.point_type(id)) != "")


# ---------------------------------------------------------------- the rest

## The skill on an interaction point is currently stored and never read —
## `free_points_of_type()` matches on `type` alone. Asserting they resolve does
## not give them a consumer, but it does mean a typo cannot sit in the table
## looking like a mechanic.
func _skills_exist() -> void:
	for id in CozyObjectDefs.OBJECTS:
		for it in CozyObjectDefs.OBJECTS[id]["interactions"]:
			var s := String(it.get("skill", ""))
			if s == "":
				continue   ## Empty means anyone may use it (doc #94).
			is_true("object '%s' names a real skill ('%s')" % [id, s],
				CozySkills.exists(s))

	for job in CozyJobDefs.JOBS:
		for s in CozyJobDefs.preferred_skills(job):
			is_true("job '%s' prefers a real skill ('%s')" % [job, s],
				CozySkills.exists(String(s)))


## A job with no usable primary skill cannot be assigned at all, and a job whose
## rest point nothing offers can never let its resident rest — it would work
## until the need system forced it to stand somewhere it cannot sit.
func _jobs_are_usable() -> void:
	var offered := _offered_types()
	for job in CozyJobDefs.JOBS:
		var primary := CozyJobDefs.primary_skill(job)
		is_true("job '%s' has a primary skill" % job, primary != "")
		is_true("job '%s' can be assigned" % job,
			CozySkills.can_be_assigned(CozySkills.Passion.NEUTRAL))

		var rest := String(CozyJobDefs.JOBS[job].get("rest_point_type", ""))
		is_true("job '%s' rests somewhere an object offers" % job,
			offered.has(rest))
		is_true("job '%s' seeks a point an object offers" % job,
			offered.has(CozyJobDefs.point_type(job)))

	# The three gathering trades specifically, since they are the ones this
	# suite was written alongside.
	eq("woodcutting is gathering, not a new skill", CozyJobDefs.primary_skill("woodcutter"), "gathering")
	eq("the miner mines", CozyJobDefs.primary_skill("miner"), "mining")
	eq("the farmer farms", CozyJobDefs.primary_skill("farmer"), "farming")


## `PLACEABLE` is a second copy of what the palette offers — the HUD reads
## `main.gd`'s `PLACE_TOOLS` — so the two are free to drift. This does not make
## them one list, but it does stop the copy naming something that is not there.
func _placeables_exist() -> void:
	for id in CozyObjectDefs.PLACEABLE:
		is_true("placeable '%s' is a real object" % id, CozyObjectDefs.exists(id))
	is_true("the resource nodes are placeable",
		CozyObjectDefs.PLACEABLE.has("tree")
		and CozyObjectDefs.PLACEABLE.has("rock")
		and CozyObjectDefs.PLACEABLE.has("crop"))


## What a thing needs from the ground it stands on. The farming chain
## `Grass -> Soil -> Farmland` has existed since V2-11 and refuses to skip a step,
## and a crop could still be dropped on virgin grass — this is the link, and it is
## a row in `CozyObjectDefs` rather than a rule in whatever code places things.
##
## THE TWO DIRECTIONS ARE EACH OTHER'S TEETH. A `ground_problem` that always
## refused would fail the allowed case; one that never refused would fail the
## refused case. The third line is the control: an object that asks for nothing
## must still be placeable anywhere, or "refuses" would just mean "broken".
func _ground_rule() -> void:
	var on_grass := CozyObjectDefs.ground_problem("crop", "grass")
	var on_soil := CozyObjectDefs.ground_problem("crop", "soil")
	var on_field := CozyObjectDefs.ground_problem("crop", "farmland")

	is_true("a crop on grass is refused", on_grass != "")
	is_true("and so is one on soil — the chain has a last step", on_soil != "")
	is_true("the reason names what it wanted", on_grass.contains("farmland"))
	is_true("and what it got", on_grass.contains("grass"))
	is_true("and it says which thing was refused", on_grass.contains("Crop"))
	eq("but on farmland it is allowed", on_field, "")

	eq("an object that asks for no ground goes anywhere",
		CozyObjectDefs.ground_problem("chest", "grass"), "")
	eq("and the same for a tree", CozyObjectDefs.ground_problem("tree", "sand"), "")

	# So the rule is not vacuous: something has to actually be constrained, or
	# every line above would pass on a table that constrains nothing.
	var constrained := CozyObjectDefs.constrained_ids()
	is_true("something is constrained", constrained.size() > 0)
	is_true("and the crop is one of them", constrained.has("crop"))


## Growth is a FUNCTION of the clock, not a timer per object, and that is what
## makes this suite possible at all: a day of growth is asserted here without
## waiting a day, and two reads at the same hour cannot disagree.
##
## Every number below is the definition's, so changing `regrow_hours` moves the
## expectations with it rather than leaving a test that passes for the wrong
## reason.
func _yield_cycle() -> void:
	# A crop: one harvest, back the next day.
	is_true("a fresh crop can be taken", CozyObjectDefs.available("crop", 0, -1.0, 100.0))
	is_true("a crop just taken cannot", not CozyObjectDefs.available("crop", 1, 100.0, 100.0))
	is_true("nor an hour later", not CozyObjectDefs.available("crop", 1, 100.0, 101.0))
	is_true("but it can the next day", CozyObjectDefs.available("crop", 1, 100.0, 124.0))

	# A rock: two loads, and then it is worked out for good.
	is_true("a rock gives twice", CozyObjectDefs.available("rock", 1, 0.0, 5.0))
	is_true("and then not", not CozyObjectDefs.available("rock", 2, 0.0, 5.0))
	is_true("and never again, however long the world runs",
		not CozyObjectDefs.available("rock", 2, 0.0, 999999.0))

	# A tree: three chops, then three days of standing there.
	is_true("a tree gives three", CozyObjectDefs.available("tree", 2, 0.0, 1.0))
	is_true("then waits", not CozyObjectDefs.available("tree", 3, 10.0, 81.0))
	is_true("and comes back after its own regrow time",
		CozyObjectDefs.available("tree", 3, 10.0, 82.0))

	# An object that is not gathered at all is never spent. Without this the
	# rule above could be "everything is eventually spent" and every line would
	# still pass.
	is_true("a chest is never worked out", CozyObjectDefs.available("chest", 99, 0.0, 0.0))
	is_true("nor is a bed", CozyObjectDefs.available("bed", 99, 0.0, 0.0))
	is_true("and the three gathered kinds are the ones that are",
		CozyObjectDefs.is_gathered("tree") and CozyObjectDefs.is_gathered("rock")
		and CozyObjectDefs.is_gathered("crop"))
	is_true("while furniture is not", not CozyObjectDefs.is_gathered("chair"))


# ---------------------------------------------------------------- helpers

func _offered_types() -> Array[String]:
	var out: Array[String] = []
	for id in CozyObjectDefs.OBJECTS:
		for it in CozyObjectDefs.OBJECTS[id]["interactions"]:
			_push(out, String(it["type"]))
	return out


## Three tables demand a point: a job's work, a job's rest, and the schedule's
## activity. A check that read only the jobs would call `sleep` unclaimed.
##
## A JOB DEMANDS ITS WHOLE RANKED LIST, not just its head: since 2026-09-15 every
## trade will take on every kind of work, with its specialty first
## (`CozyJobDefs.point_types`). Reading `point_type()` alone would call `plant`
## unclaimed while the farmer's own want-list is handing it out — and this check
## exists precisely to catch a point nothing wants.
func _demanded_types() -> Array[String]:
	var out: Array[String] = []
	for job in CozyJobDefs.JOBS:
		var d: Dictionary = CozyJobDefs.JOBS[job]
		_push(out, String(d.get("rest_point_type", "")))
		for t in CozyJobDefs.point_types(job):
			_push(out, t)
	for a in CozySchedule.ACTIVITY_POINTS:
		_push(out, String(CozySchedule.ACTIVITY_POINTS[a]))
	# AND THE PLAYER IS A CONSUMER TOO. A shop's `buy`/`sell` are worked by a
	# person, not by a trade, and a check that only knew about jobs would call
	# them unclaimed — which is what it did the moment the stall was added, and it
	# was right to.
	#
	# Read from `CozyObjectDefs.PLAYER_VERBS`, the SAME list `main.gd`'s context
	# menu iterates to decide what to offer. A copy kept here would let the two
	# drift, and the drift would look exactly like this check passing.
	for t in CozyObjectDefs.PLAYER_VERBS:
		_push(out, t)
	return out


## Sorted and deduplicated, so a failure message lists the set rather than the
## order the tables happened to be declared in.
func _push(into: Array[String], t: String) -> void:
	if t == IGNORED or into.has(t):
		return
	into.append(t)
	into.sort()


## Expected lists, typed, so a case that quietly returned an untyped array is
## still compared by value.
func _want(a: Array) -> Array[String]:
	var out: Array[String] = []
	for x in a:
		out.append(String(x))
	return out
