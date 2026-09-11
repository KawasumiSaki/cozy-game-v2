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

func _scan(path: String) -> void:
	var dir := DirAccess.open(path)
	if dir == null:
		return
	dir.list_dir_begin()
	var name := dir.get_next()
	while name != "":
		if name.begins_with("."):
			name = dir.get_next()
			continue
		var full := path.path_join(name)
		if dir.current_is_dir():
			_scan(full)
		elif name.to_lower().ends_with(".json"):
			_load_file(full)
		name = dir.get_next()
	dir.list_dir_end()


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
