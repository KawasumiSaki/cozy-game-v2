extends SceneTree
## Unit-test entry point.
##
##     godot --headless --path <repo> --script res://tests/unit/run.gd
##
## A SEPARATE ENTRY POINT, and that is the point: unit tests must be runnable
## without booting the world, and the game's own self-check must not grow a
## second mode or a second way to be invoked. `main.gd` does not know this file
## exists.
##
## Exit code is 0 when everything passed and 1 otherwise, so CI can use it
## without parsing the log.
##
## Every suite prints one `[OK]` or `[FAIL, reason]` line per CASE, in the same
## shape as the game's own assertions, so one grep counts both:
##
##     grep -c '\[FAIL'      # correct
##     grep -c '\[FAIL\]'    # WRONG — misses every [FAIL, reason]

const UNIT_DIR := "res://tests/unit"
const PREFIX := "[cozyunit]"


func _initialize() -> void:
	var paths := _suite_files()
	if paths.is_empty():
		print("%s no test files found in %s  [FAIL, nothing to run]" % [PREFIX, UNIT_DIR])
		quit(1)
		return

	var total_cases := 0
	var total_checks := 0
	var failed := 0

	for path in paths:
		var script: GDScript = load(path)
		if script == null:
			print("%s %s could not be loaded  [FAIL]" % [PREFIX, path])
			failed += 1
			continue
		var t = script.new()
		t.run()
		total_cases += t.case_count()
		total_checks += t.checks()
		var bad: Array = t.failures()
		if bad.is_empty():
			print("%s %-28s %2d case(s), %3d check(s)  [OK]" % [
				PREFIX, t.suite_name(), t.case_count(), t.checks()])
		else:
			failed += bad.size()
			print("%s %-28s %2d case(s), %3d check(s)  [FAIL, %d problem(s)]" % [
				PREFIX, t.suite_name(), t.case_count(), t.checks(), bad.size()])
			for b in bad:
				print("%s   - %s" % [PREFIX, b])

	print("%s %d suite(s), %d case(s), %d check(s), %d failure(s)  [%s]" % [
		PREFIX, paths.size(), total_cases, total_checks, failed,
		"OK" if failed == 0 else "FAIL"])
	quit(1 if failed > 0 else 0)


## Every `test_*.gd` in this directory. `run.gd` and `unit_test.gd` are excluded
## by the prefix, which is why the convention is worth keeping.
##
## DirAccess is editor/headless only — an exported build would need a manifest.
## That is already true of the asset library and is recorded in
## docs/PROJECT_LAYOUT.md; unit tests are not meant to ship anyway.
func _suite_files() -> Array[String]:
	var out: Array[String] = []
	var dir := DirAccess.open(UNIT_DIR)
	if dir == null:
		return out
	for f in dir.get_files():
		# Godot appends `.remap`/`.uid` alongside scripts; match the script only.
		if f.begins_with("test_") and f.ends_with(".gd"):
			out.append("%s/%s" % [UNIT_DIR, f])
	out.sort()
	return out
