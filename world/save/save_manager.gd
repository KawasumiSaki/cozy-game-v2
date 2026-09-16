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

## --- write safety -----------------------------------------------------------
##
## A SAVE IS WRITTEN TO A TEMP FILE, AND ONLY THEN DOES IT TAKE THE REAL NAME.
##
## The old version opened the live path with `FileAccess.WRITE`, which TRUNCATES
## it before a byte of the new world is written. A crash, a power cut or a full
## disk in that window leaves a truncated file, and a truncated file is not a
## damaged world — it is NO world: `load_world` returns `{}` and the homestead is
## gone. Measured, not assumed: `tests/probe/save_write_probe.gd` builds exactly
## that file and prints `load_world -> {} (the world is GONE)`.
##
## The order below is chosen so that AT EVERY INSTANT AT LEAST ONE COMPLETE
## GENERATION EXISTS ON DISK:
##
##   1. write the new world to `<path>.tmp`, flush, close
##   2. rename the live file to `<path>.bak`      (the previous generation)
##   3. rename `<path>.tmp` to the live path
##
## A crash before (2) leaves the old world live and a stray `.tmp`. A crash
## between (2) and (3) leaves NO live file and a complete `.bak` — which is why
## `load_world` tries the backup and says that it did. A crash after (3) leaves a
## new live world and the previous one beside it.
##
## The pattern is the one Factorio, Minecraft (`level.dat_old`), Terraria
## (`.bak`/`.bak2`) and both Godot save addons arrived at independently. Two
## caveats measured or read rather than assumed:
##
##   * `rename` onto an EXISTING destination both works here and replaces it —
##     measured on this project's own `user://` path (which contains a space, and
##     which four spellings of the call all handle). On Windows that is not
##     guaranteed the way POSIX guarantees it, **which is exactly why the backup
##     is the real net: it does not depend on the rename being atomic.**
##   * `FileAccess.flush()` is the closest primitive Godot exposes to fsync;
##     there is no directory fsync. So a power cut can still lose a save that
##     reported success. The `.bak` is what covers that too.
##
## This is NOT the version policy below — that one is about the FORMAT of the
## document, and it is already in place (`VERSION` + a registered chain).
const BAK_SUFFIX := ".bak"
const TMP_SUFFIX := ".tmp"

## Which file the LAST `load_world` got its world from: "main", "backup", or "".
##
## A fallback that nobody is told about is not a safety feature. A player whose
## main file was unreadable would keep playing a world one save behind and never
## learn why their last hour is gone — so the answer is recorded here AND pushed
## as a warning, and an assertion can read it.
static var last_source := ""

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


## Write the world so that no crash can leave the player with nothing.
##
## See the block comment above for the order and why each step is where it is.
## Returns false when the world did NOT reach the live path, which is the only
## question a caller can act on.
static func save_world(world: Dictionary, path := DEFAULT_PATH) -> bool:
	var text := JSON.stringify({"version": VERSION, "world": world})

	# (1) The new world goes somewhere harmless first.
	var tmp := path + TMP_SUFFIX
	var f := FileAccess.open(tmp, FileAccess.WRITE)
	if f == null:
		push_error("save: cannot open %s for writing (error %d)" % [
			tmp, FileAccess.get_open_error()])
		return false
	f.store_string(text)
	f.flush()
	f.close()

	# (2) The previous generation takes the backup name. A RENAME, not a copy:
	# one operation, no window where the backup is half of two files.
	var bak := path + BAK_SUFFIX
	if FileAccess.file_exists(path):
		_erase_file(bak)
		if _rename_file(path, bak) != OK:
			# DO NOT ABORT. The invariant above still holds — the live file is
			# complete, and the next step replaces it with another complete one —
			# so the cost of carrying on is one missing backup, while the cost of
			# aborting is refusing to save a player's work because a housekeeping
			# step failed. Loud, then, rather than fatal.
			push_error("save: could not move %s aside to %s — saving anyway, but \
this save will have no backup" % [path, bak])

	# (3) And only now does the new world take the name players load from.
	if _rename_file(tmp, path) != OK:
		push_error("save: could not put %s in place (error %d); the previous \
world is still in %s and nothing was lost" % [
			tmp, FileAccess.get_open_error(), bak])
		return false
	return true


## Returns {} for a missing, unreadable, malformed or wrong-version file.
##
## Callers check for empty rather than for an error code: there is exactly one
## way to fail here, and it is "no world came back". The reason is pushed as an
## error so it is not silent.
##
## AND IT FALLS BACK TO THE BACKUP. `save_world` can be interrupted between the
## two renames, which leaves no live file at all — a case that is RECOVERABLE and
## would otherwise read as "no save". `last_source` says which file answered.
static func load_world(path := DEFAULT_PATH) -> Dictionary:
	last_source = ""
	_clear_stale_temp(path)

	var main_try := _read_doc(path)
	if bool(main_try["ok"]):
		last_source = "main"
		return main_try["world"]

	# The live file is missing, unreadable, malformed, or from a version no chain
	# reaches. Try the previous generation BEFORE giving up — and say so, because
	# a world that silently comes back one save old is worse than a refusal.
	var bak := path + BAK_SUFFIX
	var bak_try := _read_doc(bak)
	if bool(bak_try["ok"]):
		last_source = "backup"
		# A WARNING and not an error: the world came back. The distinction is the
		# whole reason `_read_doc` reports nothing itself.
		push_warning("save: %s could not be read (%s); the world came from %s" % [
			path, String(main_try["why"]), bak])
		return bak_try["world"]

	# NOTHING TO LOAD AT ALL IS NOT AN ERROR. A fresh install has no save, and the
	# contract for that case is `{}` — the old code returned it quietly and this
	# keeps doing that, because a first run that logs an error is a first run that
	# teaches its reader to ignore errors. A file that is THERE and unreadable is a
	# different thing, and that one is reported.
	if FileAccess.file_exists(path) or FileAccess.file_exists(bak):
		push_error("save: no world at %s (%s) and none at %s either (%s)" % [
			path, String(main_try["why"]), bak, String(bak_try["why"])])
	return {}


## One file, read and brought up to `VERSION`.
##
## Returns `{"ok": bool, "world": Dictionary, "why": String}`, and REPORTS
## NOTHING ITSELF. Whether an unreadable file is an error or just a reason to
## try the backup is the caller's question — and a refusal that prints looks
## exactly like a broken build, which is a mistake this project has already paid
## for once (`state_of`'s `push_error` versus the probe that had to provoke it).
static func _read_doc(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {"ok": false, "world": {}, "why": "nothing there"}
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return {"ok": false, "world": {},
			"why": "cannot open it (error %d)" % FileAccess.get_open_error()}
	var text := f.get_as_text()
	f.close()

	# `JSON.new().parse()` AND NOT `JSON.parse_string()`, for the reason
	# `docs/INVARIANTS.md` already records as bug 23: `parse_string` PRINTS on a
	# malformed document, so refusing a corrupt save looks exactly like a broken
	# build. That fix was applied to the dungeon blueprint and to nothing else —
	# this file kept the printing call for two days, invisible, because no test had
	# ever fed it a file it could not read. `parse()` returns an error code, and
	# the reason it gives back is better than the old one: it has a line number.
	var json := JSON.new()
	var err := json.parse(text)
	if err != OK:
		return {"ok": false, "world": {},
			"why": "not JSON (line %d: %s)" % [json.get_error_line(), json.get_error_message()]}
	var doc: Dictionary = json.data
	if int(doc.get("version", -1)) != VERSION:
		# An older file gets a chance to be brought forward. A missing step is
		# still a refusal — see `migrate`.
		var migrated := migrate(doc)
		if migrated.is_empty():
			return {"ok": false, "world": {},
				"why": "version %s and no migration reaches version %d" % [
					str(doc.get("version", "none")), VERSION]}
		doc = migrated
	var world: Variant = doc.get("world", {})
	if typeof(world) != TYPE_DICTIONARY:
		return {"ok": false, "world": {}, "why": "no world object"}
	return {"ok": true, "world": world, "why": ""}


## A `.tmp` left behind means a save was interrupted. It is never read (a
## half-written world with a plausible name is the exact thing this file exists
## to prevent) and it is not deleted quietly either.
static func _clear_stale_temp(path: String) -> void:
	var tmp := path + TMP_SUFFIX
	if not FileAccess.file_exists(tmp):
		return
	push_warning("save: %s is left over from an interrupted save; discarding it, \
the world came from somewhere else" % tmp)
	_erase_file(tmp)


static func _rename_file(from: String, to: String) -> Error:
	return DirAccess.rename_absolute(
		ProjectSettings.globalize_path(from), ProjectSettings.globalize_path(to))


static func _erase_file(path: String) -> bool:
	if not FileAccess.file_exists(path):
		return true
	return DirAccess.remove_absolute(ProjectSettings.globalize_path(path)) == OK


## Delete a world: the live file AND the generations beside it. Returns true if
## nothing is left afterwards, which includes the case where nothing was there —
## the caller's question is "is it clear now".
##
## The backup goes too, on purpose. A caller asking for a world to be erased is
## not asking for it to come back on the next load, and a leftover `.bak` would
## do exactly that.
static func erase(path := DEFAULT_PATH) -> bool:
	var ok := _erase_file(path) and _erase_file(path + BAK_SUFFIX)
	_erase_file(path + TMP_SUFFIX)
	return ok
