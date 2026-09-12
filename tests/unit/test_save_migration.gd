extends "res://tests/unit/unit_test.gd"
## Save versioning and the migration chain.
##
## The policy is frozen in `CozySaveManager`: a field ADDED with a safe default
## does not bump the version; a field whose MEANING changes, or one that is
## removed, does. A file that no chain reaches is REFUSED rather than half-read,
## because a partially-understood world is worse than no world — it looks like it
## loaded.
##
## `VERSION` is still 1, so no real migration exists yet. These cases drive the
## MACHINERY through an explicit target version, so the first real bump is a
## one-line registration rather than a redesign of something unverified.

const FIXTURE := "res://tests/fixtures/saves/v1_world.json"


func _init() -> void:
	suite("save migration")
	case("the v1 fixture is a real save", _fixture_is_real)
	case("a current-version document passes through", _passthrough)
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
	var doc := _read_fixture()
	var out := CozySaveManager.migrate(doc)
	eq("a v1 file at VERSION 1 comes back at version 1", int(out.get("version", -1)), 1)
	eq("and its world is the same one",
		str((out.get("world", {}) as Dictionary).keys()),
		str((doc.get("world", {}) as Dictionary).keys()))


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

	# Leaving a registration behind would leak into every later test in the run.
	CozySaveManager.clear_migrations()


## A step that returns a String, or one that forgets to advance, must not produce
## a world.
func _bad_step() -> void:
	CozySaveManager.clear_migrations()
	CozySaveManager.register_migration(1, func(_w: Dictionary) -> Variant: return "nonsense")
	is_true("a step returning a non-dictionary is refused",
		CozySaveManager.migrate({"version": 1, "world": {}}, 2).is_empty())
	CozySaveManager.clear_migrations()


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
