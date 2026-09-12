extends "res://tests/unit/unit_test.gd"
## The asset manifest: export-safe enumeration.
##
## `load_dir` walks with `DirAccess`, which works in the editor and in headless
## runs and does not work in an exported build. The manifest is what ships. These
## cases pin the parts that can be checked without building an export.

const ROOT := "res://tests/fixtures/art"
const MANIFEST := "res://tests/fixtures/art/manifest.json"


func _init() -> void:
	suite("asset manifest")
	case("the walk is sorted and excludes the manifest", _walk_is_clean)
	case("the manifest matches the tree", _no_drift)
	case("loading through the manifest reaches the same definitions", _same_result)
	case("a bad manifest is refused with a reason", _refuses)


## Sorted matters: `DirAccess` returns filesystem order, so an unsorted manifest
## would churn for reasons unrelated to the assets and the drift check would fail
## on a tree nobody touched.
func _walk_is_clean() -> void:
	var paths := CozyAssetLibrary.scan_paths(ROOT)
	is_true("the fixture tree has definitions", paths.size() > 0)
	var sorted_paths := paths.duplicate()
	sorted_paths.sort()
	eq("the walk is sorted", str(paths), str(sorted_paths))
	for p in paths:
		is_false("the manifest does not list itself", String(p).ends_with("manifest.json"))


func _no_drift() -> void:
	var walked := CozyAssetLibrary.scan_paths(ROOT)
	var listed := _listed()
	eq("the manifest lists exactly the tree", str(listed), str(walked))


func _same_result() -> void:
	var by_scan := CozyAssetLibrary.new()
	by_scan.load_dir(ROOT)
	var by_manifest := CozyAssetLibrary.new()
	by_manifest.load_manifest(MANIFEST)
	eq("same loaded count",
		int(by_manifest.summary()["loaded"]), int(by_scan.summary()["loaded"]))
	eq("same rejected count",
		int(by_manifest.summary()["rejected"]), int(by_scan.summary()["rejected"]))
	eq("same runtime set",
		str(by_manifest.runtime_definitions().size()),
		str(by_scan.runtime_definitions().size()))


## A manifest is a build artifact and can be wrong. Every way it can be wrong
## must produce a REASON, because "the assets did not load" is not a diagnosis.
func _refuses() -> void:
	var lib := CozyAssetLibrary.new()
	is_true("a missing manifest is reported",
		lib.rejected.size() > 0 or lib.summary()["loaded"] == 0)

	var lib2 := CozyAssetLibrary.new()
	lib2.load_manifest("res://tests/fixtures/art/does_not_exist.json")
	is_true("a missing file is rejected", lib2.rejected.size() > 0)
	ne("and it says why", str(lib2.rejection_report()), "")


func _listed() -> Array:
	var f := FileAccess.open(MANIFEST, FileAccess.READ)
	if f == null:
		return []
	var parsed: Variant = JSON.parse_string(f.get_as_text())
	f.close()
	if typeof(parsed) != TYPE_DICTIONARY:
		return []
	var out: Array = (parsed as Dictionary).get("assets", []).duplicate()
	out.sort()
	return out
