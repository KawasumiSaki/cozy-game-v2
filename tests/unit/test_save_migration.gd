extends "res://tests/unit/unit_test.gd"
## Save versioning and the migration chain.
##
## The policy is frozen in `CozySaveManager`: a field ADDED with a safe default
## does not bump the version; a field whose MEANING changes, or one that is
## removed, does. A file that no chain reaches is REFUSED rather than half-read,
## because a partially-understood world is worse than no world — it looks like it
## loaded.
##
## `VERSION` is 2, and the step that got it there is REAL: v1 stored one
## top-level section per system and v2 stores one entity list (Core Architecture
## V1.0, item 1). The general machinery is still driven through explicit target
## versions as well, so its shape stays covered by something other than the one
## migration that happens to exist today.

const FIXTURE := "res://tests/fixtures/saves/v1_world.json"

## What the fixture holds, counted rather than assumed. A fixture that changed
## shape while the migration carried on quietly is the failure this suite exists
## to catch.
const FIXTURE_WALLS := 10
const FIXTURE_SLABS := 3
const FIXTURE_STAIRS := 1
const FIXTURE_OBJECTS := 6
const FIXTURE_NPCS := 1


func _init() -> void:
	suite("save migration")
	case("the v1 fixture is a real save", _fixture_is_real)
	case("a current-version document passes through", _passthrough)
	case("the real v1 step builds one entity list", _real_v1_step)
	case("a document with no version is refused", _no_version)
	case("a document from the future is refused", _from_the_future)
	case("a missing step refuses the whole chain", _missing_step)
	case("a registered step is applied, in order", _chain_applied)
	case("a step that gives back nonsense is refused", _bad_step)


## Real output from the game, not a hand-written stub: a fixture that was typed
## by hand tests what the author believed the format was.
func _fixture_is_real() -> void:
	var doc := _read_fixture()
	is_true("the fixture parsed", not doc.is_empty())
	eq("it carries version 1", int(doc.get("version", -1)), 1)
	var world: Dictionary = doc.get("world", {})
	for key in ["terrain", "building", "objects", "npcs", "clock"]:
		is_true("it has a '%s' section" % key, world.has(key))


func _passthrough() -> void:
	var doc := {"version": CozySaveManager.VERSION,
		"world": {"terrain": {}, "clock": {}}}
	var out := CozySaveManager.migrate(doc)
	eq("a file already at VERSION comes back at VERSION",
		int(out.get("version", -1)), CozySaveManager.VERSION)
	eq("and its world is untouched",
		str((out.get("world", {}) as Dictionary).keys()),
		str((doc.get("world", {}) as Dictionary).keys()))


## The migration that actually exists, driven by the real fixture.
func _real_v1_step() -> void:
	var out := CozySaveManager.migrate(_read_fixture())
	eq("the v1 fixture is brought up to VERSION",
		int(out.get("version", -1)), CozySaveManager.VERSION)

	var world: Dictionary = out.get("world", {})
	is_true("the per-system building section is gone", not world.has("building"))
	is_true("and so are the old objects and npcs sections",
		not world.has("objects") and not world.has("npcs"))
	is_true("the world comes back as ONE entity list", world.has("entities"))

	var by_kind := {}
	for e in world.get("entities", []):
		var k := String((e as Dictionary).get("kind", ""))
		by_kind[k] = int(by_kind.get(k, 0)) + 1

	eq("every wall arrived", int(by_kind.get("wall", 0)), FIXTURE_WALLS)
	eq("every slab arrived", int(by_kind.get("slab", 0)), FIXTURE_SLABS)
	eq("every stair arrived", int(by_kind.get("stair", 0)), FIXTURE_STAIRS)
	eq("every object arrived", int(by_kind.get("object", 0)), FIXTURE_OBJECTS)
	eq("every resident arrived", int(by_kind.get("npc", 0)), FIXTURE_NPCS)

	# The id stays INSIDE the payload, where every serializer in this project has
	# always written it — so the file never carries the same id twice.
	var walls := CozyEntityRegistry.payloads(world, CozyEntityRegistry.WALL)
	eq("a wall's id is still inside its payload",
		String((walls[0] as Dictionary).get("id", "")), "wall_001")

	# v1 furniture had no id at all — an object was identified by its index in a
	# list — so the step has to mint one per object, and leave the counter clear
	# of them. Without this, every object in an old save is anonymous.
	var objs := CozyEntityRegistry.payloads(world, CozyEntityRegistry.OBJECT)
	var obj_ids := PackedStringArray()
	for o in objs:
		obj_ids.append(String((o as Dictionary).get("id", "")))
	eq("every object got an id", obj_ids.size(), FIXTURE_OBJECTS)
	is_false("and no two are the same", _has_duplicates(obj_ids))
	eq("the object counter sits past them",
		int((world.get("next_ids", {}) as Dictionary).get("object", 0)),
		FIXTURE_OBJECTS + 1)

	# Terrain and the id counters are NOT entities and keep their own keys: one is
	# a field, the other has no id to be addressed by.
	is_true("terrain keeps its own key", world.has("terrain"))
	is_true("and so does the clock", world.has("clock"))
	eq("the wall counter came across",
		int((world.get("next_ids", {}) as Dictionary).get("wall", 0)), 11)
	eq("and the roof counter, which has no entity in the list",
		int((world.get("next_ids", {}) as Dictionary).get("roof", 0)), 4)


func _no_version() -> void:
	is_true("a document with no version field is refused",
		CozySaveManager.migrate({"world": {"terrain": {}}}).is_empty())
	is_true("version 0 is refused",
		CozySaveManager.migrate({"version": 0, "world": {}}).is_empty())


## Files from a newer build cannot be brought backwards, and pretending otherwise
## would silently drop whatever the newer version added.
func _from_the_future() -> void:
	is_true("a version above VERSION is refused",
		CozySaveManager.migrate({"version": CozySaveManager.VERSION + 1, "world": {}}).is_empty())


## The refusal that matters. A v1 file cannot reach v3 if the v2 step was never
## written — and the answer must be "no world", not "a world with v2's changes
## missing".
func _missing_step() -> void:
	CozySaveManager.clear_migrations()
	is_false("v1 -> v3 with no steps is not migratable",
		CozySaveManager.can_migrate(1, 3))
	is_true("and the walk gives back nothing",
		CozySaveManager.migrate({"version": 1, "world": {}}, 3).is_empty())
	CozySaveManager.register_builtin_migrations()


## The machinery itself: two steps, applied in order, each seeing the previous
## step's output.
func _chain_applied() -> void:
	CozySaveManager.clear_migrations()
	CozySaveManager.register_migration(1, func(w: Dictionary) -> Dictionary:
		w["seen_by_v2"] = true
		return w)
	CozySaveManager.register_migration(2, func(w: Dictionary) -> Dictionary:
		# Sees v2's edit, which is what proves the steps ran IN ORDER rather than
		# both being handed the original.
		w["v2_ran_first"] = w.get("seen_by_v2", false)
		return w)

	is_true("v1 can reach v3 once both steps exist",
		CozySaveManager.can_migrate(1, 3))
	var out := CozySaveManager.migrate({"version": 1, "world": {}}, 3)
	eq("the result is stamped 3", int(out.get("version", -1)), 3)
	var world: Dictionary = out.get("world", {})
	is_true("step 1 ran", world.get("seen_by_v2", false))
	is_true("step 2 ran after it", world.get("v2_ran_first", false))

	# Leaving the chain empty would leak into every later test in the run, and
	# into any LOAD the same process does afterwards.
	CozySaveManager.register_builtin_migrations()


## A step that returns a String, or one that forgets to advance, must not produce
## a world.
func _bad_step() -> void:
	CozySaveManager.clear_migrations()
	CozySaveManager.register_migration(1, func(_w: Dictionary) -> Variant: return "nonsense")
	is_true("a step returning a non-dictionary is refused",
		CozySaveManager.migrate({"version": 1, "world": {}}, 2).is_empty())
	CozySaveManager.register_builtin_migrations()


func _read_fixture() -> Dictionary:
	if not FileAccess.file_exists(FIXTURE):
		return {}
	var f := FileAccess.open(FIXTURE, FileAccess.READ)
	if f == null:
		return {}
	var text := f.get_as_text()
	f.close()
	var parsed: Variant = JSON.parse_string(text)
	return parsed if typeof(parsed) == TYPE_DICTIONARY else {}


func _has_duplicates(ids: PackedStringArray) -> bool:
	var seen := {}
	for id in ids:
		if seen.has(id):
			return true
		seen[id] = true
	return false
