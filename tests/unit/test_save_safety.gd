extends "res://tests/unit/unit_test.gd"
## Write safety: no crash can leave the player with nothing.
##
## `CozySaveManager.save_world` used to open the LIVE path with
## `FileAccess.WRITE`, which truncates the old world before a byte of the new one
## is written. A crash in that window leaves a file that is not a damaged world
## but NO world — `load_world` returns `{}` and the homestead is gone. Measured in
## `tests/probe/save_write_probe.gd`, which builds exactly that file.
##
## The order it uses now is chosen so that AT EVERY INSTANT AT LEAST ONE COMPLETE
## GENERATION EXISTS ON DISK: write `<path>.tmp`, rename the live file to
## `<path>.bak`, rename the temp into place. A crash between the two renames
## leaves no live file — which is why `load_world` tries the backup and says so.
##
## WHAT THIS SUITE DELIBERATELY DOES NOT DO: provoke the case where NEITHER file
## can be read. That path pushes an error, correctly, and a test that provoked it
## would make the baseline's `0 ERROR` a lie — this project has already paid for
## a "the probe worked" log line that looked like a broken build. That case is
## measured in the probe instead.

const DIR := "user://save_safety_test"
const LIVE := DIR + "/world.json"
const BAK := LIVE + CozySaveManager.BAK_SUFFIX
const TMP := LIVE + CozySaveManager.TMP_SUFFIX


func _init() -> void:
	suite("save safety")
	case("a save comes back", _round_trip)
	case("the previous generation is kept", _rotation)
	case("an unreadable world falls back to the backup", _falls_back)
	case("with no files at all there is no world", _nothing_at_all)
	case("a leftover temp file is never the world", _stale_temp)
	case("erasing takes the backup with it", _erase_takes_the_backup)
	case("a good save leaves no temp behind", _no_temp_left)


func _round_trip() -> void:
	_clean()
	CozySaveManager.save_world({"clock": {"day": 7}}, LIVE)
	var world := CozySaveManager.load_world(LIVE)
	eq("the day came back", int(world.get("clock", {}).get("day", -1)), 7)
	eq("and it came from the live file", CozySaveManager.last_source, "main")


## The rotation itself. Without it the backup would sit empty and the fallback
## below would have nothing to fall back TO — which is the shape of a safety
## feature that has never been asked to work.
func _rotation() -> void:
	_clean()
	CozySaveManager.save_world({"clock": {"day": 1}}, LIVE)
	CozySaveManager.save_world({"clock": {"day": 2}}, LIVE)
	var live := CozySaveManager.load_world(LIVE)
	var previous := CozySaveManager.load_world(BAK)
	eq("the live file is the newer world", int(live.get("clock", {}).get("day", -1)), 2)
	eq("and the one before it is beside it", int(previous.get("clock", {}).get("day", -1)), 1)


## THE CASE THE WHOLE CARD IS FOR: the live file was being written when the
## process died, and the world still comes back.
func _falls_back() -> void:
	_clean()
	CozySaveManager.save_world({"clock": {"day": 3}}, LIVE)
	CozySaveManager.save_world({"clock": {"day": 4}}, LIVE)
	# The crash: the live file is half of what it says it is.
	_overwrite(LIVE, "{\"version\": 2, \"world\": {\"clock\": {\"da")
	var world := CozySaveManager.load_world(LIVE)
	eq("the world came back anyway, one save old", int(world.get("clock", {}).get("day", -1)), 3)
	eq("and the load said where it came from", CozySaveManager.last_source, "backup")


## The other half of the fallback's teeth: it must not be true when there is
## nothing to fall back to. A check that always answers the same way is not a
## check — this project has paid for that lesson more than once.
func _nothing_at_all() -> void:
	_clean()
	var world := CozySaveManager.load_world(LIVE)
	is_true("there is no world", world.is_empty())
	eq("and no source is claimed", CozySaveManager.last_source, "")


## A `.tmp` is what an interrupted save leaves. It is a HALF-written world with a
## plausible name, so reading it would be the exact failure this file prevents —
## and it is discarded rather than left to be found again.
func _stale_temp() -> void:
	_clean()
	CozySaveManager.save_world({"clock": {"day": 9}}, LIVE)
	_overwrite(TMP, "{\"version\": 2, \"world\": {\"clock\": {\"da")
	var world := CozySaveManager.load_world(LIVE)
	eq("the world is the saved one, not the leftover", int(world.get("clock", {}).get("day", -1)), 9)
	is_false("and the leftover is gone", FileAccess.file_exists(TMP))


## Erasing a world must take the backup too. A leftover `.bak` would bring back a
## world the player asked to delete, on the next load, with nothing saying so.
func _erase_takes_the_backup() -> void:
	_clean()
	CozySaveManager.save_world({"clock": {"day": 1}}, LIVE)
	CozySaveManager.save_world({"clock": {"day": 2}}, LIVE)
	is_true("there is a backup to lose", FileAccess.file_exists(BAK))
	CozySaveManager.erase(LIVE)
	is_false("the live file is gone", FileAccess.file_exists(LIVE))
	is_false("the backup is gone with it", FileAccess.file_exists(BAK))
	is_true("and nothing loads", CozySaveManager.load_world(LIVE).is_empty())
	_clean()


func _no_temp_left() -> void:
	_clean()
	CozySaveManager.save_world({"clock": {"day": 1}}, LIVE)
	is_false("a completed save leaves no temp behind", FileAccess.file_exists(TMP))
	_clean()


# ---------------------------------------------------------------- helpers

func _clean() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(DIR))
	for p in [LIVE, BAK, TMP]:
		if FileAccess.file_exists(p):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(p))


## Write straight at a path, unglobalised, so this helper is not another place
## that turns a path into a different path. That mistake has already produced two
## false measurements in this project's probes.
func _overwrite(path: String, text: String) -> void:
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f != null:
		f.store_string(text)
		f.close()
