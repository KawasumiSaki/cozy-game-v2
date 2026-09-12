class_name CozyAssetLibrary
extends RefCounted
## The runtime asset catalogue (V2.1 doc E.3 / E.4).
##
## Reads `assets/art/**.json` Asset Definitions and answers the questions a
## generator actually asks: what can go in this biome, what belongs beside a
## road, which of these casts a shadow.
##
## Loading is deliberately STRICT. A definition missing required fields is
## rejected and recorded with its reason rather than silently skipped — doc
## E.4.2's whole point is that the runtime must be able to trust what it
## queries, so a half-specified asset is a bug to surface, not to tolerate.
##
## It also enforces doc E.3.1: `runtime_definitions()` returns only APPROVED
## assets. Raw generator output must never reach the running game.
##
## NOTE: this scans with DirAccess, which works in the editor and in headless
## runs. An exported build would need the definitions declared as resources or
## bundled into a manifest first — recorded here so it is not a surprise later.

var definitions: Dictionary = {}   ## id -> CozyAssetDefinition
var rejected: Array = []           ## {path, problems}

## Bumped when the manifest FORMAT changes, which is not the same thing as the
## asset set changing — that needs no bump at all, the file is a list.
const MANIFEST_VERSION := 1

var _files_seen := 0
var _roots: Array[String] = []


## Recursively load every `.json` under `root`. Returns a summary.
func load_dir(root: String) -> Dictionary:
	if not _roots.has(root):
		_roots.append(root)
	_scan(root)
	return summary()


## Re-read everything previously loaded. Used after an asset ingest so the
## running game picks up new definitions without a restart.
func reload() -> Dictionary:
	definitions.clear()
	rejected.clear()
	_files_seen = 0
	for r in _roots:
		_scan(r)
	return summary()


func summary() -> Dictionary:
	return {
		"files": _files_seen,
		"loaded": definitions.size(),
		"rejected": rejected.size(),
		"runtime": runtime_definitions().size(),
	}


# ---------------------------------------------------------------- loading

## The name a manifest has inside the tree it describes.
##
## It must be EXCLUDED from the walk, or a manifest would list itself and the
## drift check would compare a set with a superset of itself and never agree.
const MANIFEST_NAME := "manifest.json"


## Every asset definition under `root`, as paths relative to it, SORTED.
##
## SORTED is not cosmetic. `DirAccess` returns entries in whatever order the
## filesystem gives, so a manifest written from an unsorted walk would reorder
## for reasons that have nothing to do with the assets — and the drift check
## would then fail on a tree nobody had touched.
##
## This is the ONE place the tree is walked. Both `_scan` and the manifest
## generator go through it, so the two cannot disagree about what is there.
static func scan_paths(root: String) -> Array[String]:
	var out: Array[String] = []
	_walk(root, "", out)
	out.sort()
	return out


static func _walk(root: String, rel: String, out: Array[String]) -> void:
	var here := root if rel.is_empty() else root.path_join(rel)
	var dir := DirAccess.open(here)
	if dir == null:
		return
	dir.list_dir_begin()
	var name := dir.get_next()
	while name != "":
		if not name.begins_with("."):
			var child_rel := name if rel.is_empty() else rel.path_join(name)
			if dir.current_is_dir():
				_walk(root, child_rel, out)
			elif name.to_lower().ends_with(".json") and name != MANIFEST_NAME:
				out.append(child_rel)
		name = dir.get_next()
	dir.list_dir_end()


func _scan(path: String) -> void:
	for rel in scan_paths(path):
		_load_file(path.path_join(rel))


# ---------------------------------------------------------------- manifest

## Load from a MANIFEST instead of by walking the tree.
##
## `load_dir` enumerates with `DirAccess`, which works in the editor and in
## headless runs and DOES NOT WORK IN AN EXPORTED BUILD: an exported project has
## no loose files to enumerate, only packed resources. The manifest is the list
## of what is there, produced at build time by `tests/tools/gen_asset_manifest.gd`.
##
## Paths in the manifest are relative to the manifest's OWN directory, so the
## file travels with the tree it describes.
##
## The two must not drift, and that is asserted rather than trusted — see
## `_check_asset_manifest` in the self-check. A manifest that disagrees with the
## tree is a build that ships the wrong assets, and it would ship them silently.
func load_manifest(manifest_path: String) -> Dictionary:
	var f := FileAccess.open(manifest_path, FileAccess.READ)
	if f == null:
		rejected.append({"path": manifest_path, "problems": ["manifest cannot open"]})
		return summary()
	var text := f.get_as_text()
	f.close()

	var parsed: Variant = JSON.parse_string(text)
	if typeof(parsed) != TYPE_DICTIONARY:
		rejected.append({"path": manifest_path, "problems": ["manifest is not a JSON object"]})
		return summary()
	var doc: Dictionary = parsed
	if int(doc.get("version", -1)) != MANIFEST_VERSION:
		rejected.append({"path": manifest_path,
			"problems": ["manifest version %s, expected %d" % [
				str(doc.get("version", "none")), MANIFEST_VERSION]]})
		return summary()
	var listed: Variant = doc.get("assets", [])
	if typeof(listed) != TYPE_ARRAY:
		rejected.append({"path": manifest_path, "problems": ["manifest has no asset list"]})
		return summary()

	var base := manifest_path.get_base_dir()
	for rel in listed:
		_load_file(base.path_join(String(rel)))
	return summary()


func _load_file(path: String) -> void:
	_files_seen += 1

	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		rejected.append({"path": path, "problems": ["cannot open"]})
		return
	var text := f.get_as_text()
	f.close()

	var parsed = JSON.parse_string(text)
	if not (parsed is Dictionary):
		rejected.append({"path": path, "problems": ["not a JSON object"]})
		return

	var def := CozyAssetDefinition.from_dict(parsed, path)
	var problems := def.validate()
	if not problems.is_empty():
		rejected.append({"path": path, "problems": problems})
		return

	if definitions.has(def.id):
		rejected.append({"path": path,
			"problems": ["duplicate id '%s'" % def.id]})
		return

	definitions[def.id] = def


# ---------------------------------------------------------------- queries

func get_def(id: String) -> CozyAssetDefinition:
	return definitions.get(id, null)


func has(id: String) -> bool:
	return definitions.has(id)


func count() -> int:
	return definitions.size()


## Only APPROVED assets (doc E.3.1). This is what runtime systems may use.
func runtime_definitions() -> Array[CozyAssetDefinition]:
	var out: Array[CozyAssetDefinition] = []
	for id in definitions:
		var d: CozyAssetDefinition = definitions[id]
		if d.is_runtime_ready():
			out.append(d)
	return out


func by_category(cat: String) -> Array[CozyAssetDefinition]:
	return _filter(func(d: CozyAssetDefinition) -> bool: return d.category == cat)


func by_biome(biome: String) -> Array[CozyAssetDefinition]:
	return _filter(func(d: CozyAssetDefinition) -> bool: return d.has_biome(biome))


func by_tag(tag: String) -> Array[CozyAssetDefinition]:
	return _filter(func(d: CozyAssetDefinition) -> bool: return d.has_tag(tag))


## Idiomatic shorthand for the question a scatter system actually asks.
func by_biome_and_category(biome: String, cat: String) -> Array[CozyAssetDefinition]:
	return _filter(func(d: CozyAssetDefinition) -> bool:
		return d.has_biome(biome) and d.category == cat)


func _filter(pred: Callable) -> Array[CozyAssetDefinition]:
	var out: Array[CozyAssetDefinition] = []
	var ids: Array = definitions.keys()
	ids.sort()
	for id in ids:
		var d: CozyAssetDefinition = definitions[id]
		if pred.call(d):
			out.append(d)
	return out


func rejection_report() -> String:
	if rejected.is_empty():
		return "0 rejected"
	var parts: Array[String] = []
	for r in rejected:
		parts.append("%s: %s" % [r["path"].get_file(), ", ".join(r["problems"])])
	return "; ".join(parts)


func describe() -> String:
	var s := summary()
	return "%d definition(s) from %d file(s), %d runtime-ready, %d rejected" % [
		s["loaded"], s["files"], s["runtime"], s["rejected"]]
