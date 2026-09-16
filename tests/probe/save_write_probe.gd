extends SceneTree
## MEASUREMENT, NOT AN ASSERTION.
##
##     godot --headless --path <repo> --script res://tests/probe/save_write_probe.gd
##
## ---------------------------------------------------------------------------
## What does THIS PLATFORM actually do about write safety, and what does the save
## layer do about the failures that leaves?
##
## The plan is the one every game converges on independently — Factorio,
## Minecraft (`level.dat_old`), Terraria (`.bak` / `.bak2`), and both Godot save
## addons: **write a temp file, flush, rename it over the target, keep a rotating
## backup.** The whole pattern rests on ONE platform fact:
##
##     renaming over an EXISTING file replaces it.
##
## POSIX guarantees that. **Windows may not**, and this project runs on Windows,
## for a player who will one day be killed mid-save. So it is measured here
## rather than assumed.
##
## ⚠️ THE FIRST RUN OF THIS PROBE LIED. It reported `rename_absolute` failing
## BOTH times, with the source AND the destination gone afterwards — a rename that
## deletes both files is not a thing a filesystem does. It was the probe: the
## paths it passed had already been globalised once and were globalised AGAIN on
## the way in. **A broken probe and broken code have the same symptom**, which is
## why this file now prints existence on both sides of every call and why the
## four spellings below are all measured instead of the one that seemed obvious.
##
## The unreadable-save cases come last. They are here and not in the unit suite on
## purpose: `load_world` pushing an error is CORRECT behaviour, and a unit test
## that provokes it would make the baseline's `0 ERROR` a lie.

const PREFIX := "[probe]"
const DIR := "user://save_probe"


func _initialize() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(DIR))
	print("%s dir=%s (absolute path contains a space=%s)" % [
		PREFIX, ProjectSettings.globalize_path(DIR),
		str(ProjectSettings.globalize_path(DIR).contains(" "))])
	_rename_spellings()
	_rename_onto_existing()
	_copy_aside_then_overwrite()
	_truncated_with_no_backup()
	_crash_mid_save_with_a_backup()
	_rotation_keeps_the_previous_generation()
	_cleanup()
	quit(0)


## Every spelling of the move, onto a MISSING destination. All four are expected
## to work; the point of measuring all four is that the first two runs of this
## probe each picked a spelling that came back wrong — both times because the
## probe had globalised a path twice, which created no file to move.
func _rename_spellings() -> void:
	var forms := [
		["forward slashes", false, false],
		["BACKslashes", true, false],
		["DirAccess.open(dir).rename(name, name)", false, true],
		["DirAccess.open(dir).rename_absolute(abs, abs)", true, true],
	]
	for form in forms:
		var label := String(form[0])
		var abs_src := _p("r_%d_src.json" % forms.find(form))
		var abs_dst := _p("r_%d_moved.json" % forms.find(form))
		_erase(abs_src)
		_erase(abs_dst)
		_write_at(abs_src, "SRC")
		var there := str(FileAccess.file_exists(abs_src))
		var err := FAILED
		if bool(form[2]):
			var d := DirAccess.open(DIR)
			if d == null:
				print("%s %s: DirAccess.open returned null" % [PREFIX, label])
				continue
			err = (d.rename_absolute(abs_src.replace("/", "\\"), abs_dst.replace("/", "\\"))
				if bool(form[1])
				else d.rename(abs_src.get_file(), abs_dst.get_file()))
		else:
			err = DirAccess.rename_absolute(
				abs_src.replace("/", "\\") if bool(form[1]) else abs_src,
				abs_dst.replace("/", "\\") if bool(form[1]) else abs_dst)
		print("%s rename[%-42s] src existed=%s err=%-2s dst=%s content='%s'" % [
			PREFIX, label, there, str(int(err)), str(FileAccess.file_exists(abs_dst)),
			_read(abs_dst)])
		_erase(abs_src)
		_erase(abs_dst)


## THE ONE THAT DECIDES THE DESIGN.
func _rename_onto_existing() -> void:
	var abs_src := _p("x_src.json")
	var abs_dst := _p("x_dst.json")
	_erase(abs_src)
	_erase(abs_dst)
	_write_at(abs_src, "NEW")
	_write_at(abs_dst, "OLD")
	var err := DirAccess.rename_absolute(abs_src, abs_dst)
	print("%s rename onto an EXISTING destination: err=%s (%s), dst OLD -> '%s'%s" % [
		PREFIX, error_string(err), str(int(err)), _read(abs_dst),
		"  [REPLACED]" if _read(abs_dst) == "NEW" else "  [NOT replaced]"])
	_erase(abs_src)
	_erase(abs_dst)


## The non-atomic alternative, for comparison: copy the good file aside, then
## overwrite in place. It leaves a recoverable previous generation, and it is
## available even where a replace-by-rename is not.
func _copy_aside_then_overwrite() -> void:
	var live := _p("c_live.json")
	var bak := _p("c_live.json.bak")
	_erase(live)
	_erase(bak)
	_write_at(live, "GOOD")
	var err := DirAccess.copy_absolute(live, bak)
	_write_at(live, "HALFWAY")
	print("%s copy aside then overwrite in place: copy err=%s (%s), bak='%s', live='%s'" % [
		PREFIX, error_string(err), str(int(err)), _read(bak), _read(live)])


## What a crash mid-write used to leave, WITH NOTHING BESIDE IT.
##
## This is the case the old `save_world` produced: it opened the live path with
## `FileAccess.WRITE`, which truncates before a byte of the new world is written.
## There is no recovery here, and the error it pushes is the truth.
func _truncated_with_no_backup() -> void:
	var p := _p("d_trunc.json")
	var full := JSON.stringify({
		"version": CozySaveManager.VERSION, "world": {"clock": {"day": 4}}})
	_erase(p)
	_erase(p + CozySaveManager.BAK_SUFFIX)
	_write_at(p, full.substr(0, int(full.length() * 0.6)))
	var world := CozySaveManager.load_world(p)
	print("%s a truncated save with NO backup: load_world -> %s, last_source='%s'" % [
		PREFIX, "{} (the world is GONE)" if world.is_empty() else "loaded",
		CozySaveManager.last_source])


## The same crash WITH the backup the new `save_world` keeps: recoverable, and
## the recovery is announced rather than silent.
func _crash_mid_save_with_a_backup() -> void:
	var live := _p("e_live.json")
	var bak := live + CozySaveManager.BAK_SUFFIX
	_erase(live)
	_erase(bak)
	# Generation -1, complete, sitting where a previous save leaves it.
	_write_at(live, JSON.stringify({
		"version": CozySaveManager.VERSION, "world": {"clock": {"day": 4}}}))
	DirAccess.copy_absolute(live, bak)
	# Then the crash: the live file is half-written.
	_write_at(live, "{\"version\": 2, \"world\": {\"clock\": {\"da")
	var world := CozySaveManager.load_world(live)
	print("%s the same crash WITH a backup: day=%d, last_source='%s'" % [
		PREFIX, int(world.get("clock", {}).get("day", -1)),
		CozySaveManager.last_source])


## And what the real `save_world` leaves behind after two saves: the previous
## generation under `.bak`, and no `.tmp` still lying around.
func _rotation_keeps_the_previous_generation() -> void:
	var p := _p("f_live.json")
	_erase(p)
	_erase(p + CozySaveManager.BAK_SUFFIX)
	_erase(p + CozySaveManager.TMP_SUFFIX)
	CozySaveManager.save_world({"clock": {"day": 1}}, p)
	CozySaveManager.save_world({"clock": {"day": 2}}, p)
	var live := CozySaveManager.load_world(p)
	var prev := CozySaveManager.load_world(p + CozySaveManager.BAK_SUFFIX)
	print("%s two saves: live day=%d, .bak day=%d, .tmp exists=%s" % [
		PREFIX, int(live.get("clock", {}).get("day", -1)),
		int(prev.get("clock", {}).get("day", -1)),
		str(FileAccess.file_exists(p + CozySaveManager.TMP_SUFFIX))])


# ---------------------------------------------------------------- helpers
#
# EXACTLY ONE PLACE TURNS A NAME INTO A PATH. Every other helper takes an
# absolute path and touches nothing. The two runs of this probe that came back
# with "rename is broken on Windows" were both the same mistake: a helper that
# globalised, handed a path that had already been globalised.

func _p(name: String) -> String:
	return ProjectSettings.globalize_path("%s/%s" % [DIR, name])


func _write_at(abs_path: String, text: String) -> void:
	var f := FileAccess.open(abs_path, FileAccess.WRITE)
	if f != null:
		f.store_string(text)
		f.close()


func _read(abs_path: String) -> String:
	if not FileAccess.file_exists(abs_path):
		return "<missing>"
	return FileAccess.get_file_as_string(abs_path)


func _erase(abs_path: String) -> void:
	if FileAccess.file_exists(abs_path):
		DirAccess.remove_absolute(abs_path)


func _cleanup() -> void:
	var d := DirAccess.open(DIR)
	if d != null:
		for f in d.get_files():
			DirAccess.remove_absolute(_p(f))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(DIR))
