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
