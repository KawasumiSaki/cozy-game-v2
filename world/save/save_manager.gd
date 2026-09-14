class_name CozySaveManager
extends RefCounted
## Save and load (V2.1 doc #63–#68).
##
## The doc's rule is that a save file holds FACTS and never anything derived from
## them (#63 / #68): no meshes, no room polygons, no navigation grids, no paths.
## Load restores the facts and lets every generator rebuild its own derived layer
## — through the same code that builds the world the first time, so there is no
## second implementation to drift out of step with the first.
##
## `user://` is the right path on every target. On desktop it is a real
## directory; in a web build Godot backs it with IndexedDB. A browser-specific
## branch would buy nothing and would be one more path to keep correct.
##
## The file carries a version, and a file from another version is REFUSED rather
## than half-read. A partially-understood world is worse than no world, because
## it looks like it loaded.
##
## Note what JSON does to numbers: every int comes back a float. That is why
## every reader below wraps its values in `int()` / `float()` rather than
## trusting the type it wrote.

const VERSION := 2
const DEFAULT_PATH := "user://world.json"

## --- version policy (frozen 2026-09-12, Core Architecture V1.0) --------------
##
## WHEN TO BUMP `VERSION`:
##
##   adding a field that has a safe default   -> DO NOT bump. An old file still
##                                               reads; the reader supplies the
##                                               default. Bumping here would
##                                               strand every existing world for
##                                               no reason.
##   changing what an existing field MEANS    -> bump, and register a step.
##   removing a field                         -> bump, and register a step.
##
## A bump with no registered step is a fault, not a policy: the file becomes
## unreadable and no migration can ever be written for it. `_migrations` is
## walked from the file's version UP to `VERSION`, one step at a time, so a v1
## file reaching v3 runs v1->v2 and then v2->v3 and each step is testable alone.

## from_version -> Callable(world: Dictionary) -> Dictionary
##
## Holds one real step: v1 -> v2, the entity list (Core Architecture V1.0, item
## 1). The mechanism and the policy were built and driven through a fake target
## version first (②-1), so the first real bump was a registration rather than a
## redesign of something unverified — which is exactly what it turned out to be.
static var _migrations: Dictionary = {}


## The real chain, registered when the class is first touched.
static func _static_init() -> void:
	register_builtin_migrations()


## Re-register the built-in steps. Called once from `_static_init`, and again by
## any test that clears the registry: a test which leaves the chain empty would
## make every later LOAD in that process refuse a v1 file, and the failure would
## land in whatever ran next rather than in the test that caused it.
static func register_builtin_migrations() -> void:
	_migrations.clear()
	register_migration(1, _migrate_v1_to_v2)


## Register the step that turns a `from_version` world into a `from_version + 1`
## world. Registering twice for the same version replaces the step.
static func register_migration(from_version: int, step: Callable) -> void:
	_migrations[from_version] = step


## Test-only. The real chain comes back with `register_builtin_migrations()`.
static func clear_migrations() -> void:
	_migrations.clear()


## v1 -> v2 (Core Architecture V1.0, item 1): the world's top-level keys became
## ONE entity list.
##
## v1 stored one section per system — `building` (walls / slabs / stairs),
## `objects`, `npcs` — so "everything in this world" had as many answers as there
## were systems, and an id could only be resolved by a reader who already knew
## which system minted it. v2 stores an entity as `{"kind", "state"}`, with the id
## inside the state where every serializer already wrote it.
##
## Two things do NOT become entities and keep a home of their own: terrain (a
## field, not a thing with an id) and the id counters (`next_ids` — a counter has
## no id to be addressed by). Roofs are absent from both versions, because they
## are derived from the rooms.
##
## v1 furniture had no id at all — an object was identified by its INDEX in the
## list — so this step MINTS one per object, in list order, and leaves the counter
## past them.
static func _migrate_v1_to_v2(w: Dictionary) -> Dictionary:
	var b: Dictionary = w.get("building", {})
	var ents: Array = []

	# The singular of each v1 section name is the kind. This one table is the
	# whole mapping, so it is written once rather than matched on four times.
	for pair in [["walls", "wall"], ["slabs", "slab"], ["stairs", "stair"]]:
		for s in b.get(pair[0], []):
			ents.append({"kind": pair[1], "state": s})

	var next_object := 1
	for o in w.get("objects", []):
		var od: Dictionary = (o as Dictionary).duplicate(true)
		if String(od.get("id", "")) == "":
			od["id"] = "obj_%03d" % next_object
			next_object += 1
		ents.append({"kind": "object", "state": od})

	for n in w.get("npcs", []):
		ents.append({"kind": "npc", "state": n})

	return {
		"entities": ents,
		"next_ids": {
			"wall": int(b.get("next_wall_id", 1)),
			"slab": int(b.get("next_slab_id", 1)),
			"stair": int(b.get("next_stair_id", 1)),
			"roof": int(b.get("next_roof_id", 1)),
			"object": next_object,
		},
		"terrain": w.get("terrain", {}),
		"clock": w.get("clock", {}),
	}


## Can a file at this version reach the current one?
## `target` exists so the chain is TESTABLE while `VERSION` is still 1 and there
## is nothing real to migrate. Without it the walk below could never execute and
## the mechanism would be unverified code — which is the shape this project has
## paid for repeatedly.
static func can_migrate(from_version: int, target := VERSION) -> bool:
	var v := from_version
	while v < target:
		if not _migrations.has(v):
			return false
		v += 1
	return v == target


## Walk a document up to `VERSION`, one registered step at a time.
##
## Returns {} when any step is missing, and that refusal is kept deliberately:
## a partially-understood world is worse than no world, because it LOOKS like it
## loaded. Same rule as the version check it replaces, applied per step.
static func migrate(doc: Dictionary, target := VERSION) -> Dictionary:
	var version := int(doc.get("version", -1))
	if version < 1:
		return {}                       # no usable version field: not our file
	if version > target:
		return {}                       # from the future: not migratable back
	var current := {"version": version, "world": doc.get("world", {})}
	var steps := 0
	while version < target:
		if not _migrations.has(version):
			return {}
		var world: Variant = (_migrations[version] as Callable).call(current["world"])
		if typeof(world) != TYPE_DICTIONARY:
			return {}
		version += 1
		steps += 1
		current = {"version": version, "world": world}
		# A step that forgets to advance the version would spin forever. Bound it
		# by the number of versions there are, not by a number that looks big.
		if steps > target + 1:
			push_error("save: migration did not advance past version %d" % version)
			return {}
	return current


static func save_world(world: Dictionary, path := DEFAULT_PATH) -> bool:
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		push_error("save: cannot open %s for writing (error %d)" % [
			path, FileAccess.get_open_error()])
		return false
	f.store_string(JSON.stringify({"version": VERSION, "world": world}))
	f.close()
	return true


## Returns {} for a missing, unreadable, malformed or wrong-version file.
##
## Callers check for empty rather than for an error code: there is exactly one
## way to fail here, and it is "no world came back". The reason is pushed as an
## error so it is not silent.
static func load_world(path := DEFAULT_PATH) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		push_error("save: cannot open %s for reading (error %d)" % [
			path, FileAccess.get_open_error()])
		return {}
	var text := f.get_as_text()
	f.close()

	var parsed: Variant = JSON.parse_string(text)
	if typeof(parsed) != TYPE_DICTIONARY:
		push_error("save: %s is not a JSON object" % path)
		return {}
	var doc: Dictionary = parsed
	if int(doc.get("version", -1)) != VERSION:
		# An older file gets a chance to be brought forward. A missing step is
		# still a refusal — see `migrate`.
		var migrated := migrate(doc)
		if migrated.is_empty():
			push_error("save: %s is version %s, expected %d, and no migration \
reaches it — refusing rather than half-reading it" % [
				path, str(doc.get("version", "none")), VERSION])
			return {}
		doc = migrated
	var world: Variant = doc.get("world", {})
	if typeof(world) != TYPE_DICTIONARY:
		push_error("save: %s has no world object" % path)
		return {}
	return world


static func exists(path := DEFAULT_PATH) -> bool:
	return FileAccess.file_exists(path)


## Delete a save. Returns true if it is gone afterwards, which includes the case
## where it was never there — the caller's question is "is it clear now".
static func erase(path := DEFAULT_PATH) -> bool:
	if not FileAccess.file_exists(path):
		return true
	return DirAccess.remove_absolute(ProjectSettings.globalize_path(path)) == OK
