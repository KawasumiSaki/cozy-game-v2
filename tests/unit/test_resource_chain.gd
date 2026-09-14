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


# ---------------------------------------------------------------- the teeth

## An object that offers an interaction nothing seeks is furniture with a button
## that does nothing. `chop`, `mine` and `harvest` were in exactly this position
## before the jobs existed — the points would have been reachable and pointless.
func _offers_are_wanted() -> void:
	var wanted := _demanded_types()
	for t in _offered_types():
		is_true("'%s' is offered by an object and wanted by something" % t,
			wanted.has(t))


## The other direction, and the more dangerous one: a job or an activity that
## seeks a point nothing offers can acquire a target it can never reach, so it
## can never finish a task. That is the `hauler`/`chest` bug exactly.
func _wants_are_offered() -> void:
	var offered := _offered_types()
	for t in _demanded_types():
		is_true("'%s' is wanted and some object offers it" % t, offered.has(t))


## Guards the pair above from passing because both sides are empty. Without this,
## deleting every interaction in the game would make this suite green.
func _offer_set_is_real() -> void:
	var offered := _offered_types()
	eq("seven kinds of interaction point exist", offered.size(), 7)
	for t in ["work", "sit", "sleep", "store", "chop", "mine", "harvest"]:
		is_true("'%s' is among them" % t, offered.has(t))
	is_true("gathering is a real trade to look for", offered.has("chop")
		or offered.has("mine") or offered.has("harvest"))


# ---------------------------------------------------------------- recipes

func _recipes_have_jobs() -> void:
	for id in CozyRecipeDefs.ids():
		var job := String(CozyRecipeDefs.RECIPES[id]["job"])
		is_true("recipe '%s' names a job that exists" % id, CozyJobDefs.exists(job))


## A recipe says where its work happens. If that disagrees with the job's own
## point type, the resident walks to one kind of place and the recipe claims
## another — the work would happen somewhere the agent never went.
func _recipe_matches_job() -> void:
	for id in CozyRecipeDefs.ids():
		var job := String(CozyRecipeDefs.RECIPES[id]["job"])
		if not CozyJobDefs.exists(job):
			continue
		eq("recipe '%s' is worked where its job works" % id,
			CozyRecipeDefs.point_type(id), CozyJobDefs.point_type(job))

	# And that place has to be somewhere a resident can actually stand.
	var offered := _offered_types()
	for id in CozyRecipeDefs.ids():
		is_true("recipe '%s' names a point an object offers" % id,
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
	eq("harvest produces wheat", CozyRecipeDefs.outputs("harvest_crop"), {"wheat": 2.0})
	eq("baking consumes wheat", CozyRecipeDefs.inputs("bake_bread"), {"wheat": 2.0})


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
func _demanded_types() -> Array[String]:
	var out: Array[String] = []
	for job in CozyJobDefs.JOBS:
		var d: Dictionary = CozyJobDefs.JOBS[job]
		_push(out, String(d.get("point_type", "")))
		_push(out, String(d.get("rest_point_type", "")))
	for a in CozySchedule.ACTIVITY_POINTS:
		_push(out, String(CozySchedule.ACTIVITY_POINTS[a]))
	return out


## Sorted and deduplicated, so a failure message lists the set rather than the
## order the tables happened to be declared in.
func _push(into: Array[String], t: String) -> void:
	if t == IGNORED or into.has(t):
		return
	into.append(t)
	into.sort()
