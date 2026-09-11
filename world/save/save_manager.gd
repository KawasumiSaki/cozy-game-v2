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

const VERSION := 1
const DEFAULT_PATH := "user://world.json"


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
		push_error("save: %s is version %s, expected %d — refusing rather than \
half-reading it" % [path, str(doc.get("version", "none")), VERSION])
		return {}
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
