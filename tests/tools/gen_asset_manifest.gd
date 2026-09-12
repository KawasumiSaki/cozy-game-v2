extends SceneTree
## Write the asset manifest for a tree.
##
##     godot --headless --path <repo> --script res://tests/tools/gen_asset_manifest.gd -- <root>
##
## A BUILD-TIME TOOL, not a runtime dependency. An exported project has no loose
## files to enumerate, so `DirAccess` cannot be used to find assets at runtime —
## the manifest is the answer to that, and this is what produces it.
##
## Run it after adding or removing a definition. Forgetting to is not silent:
## the self-check compares the manifest against a fresh walk and fails when the
## two disagree, so a stale manifest is caught rather than shipped.

const DEFAULT_ROOT := "res://tests/fixtures/art"


func _initialize() -> void:
	var root := DEFAULT_ROOT
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		root = String(args[0])

	var paths := CozyAssetLibrary.scan_paths(root)
	if paths.is_empty():
		print("[manifest] no definitions under %s  [FAIL, nothing to write]" % root)
		quit(1)
		return

	var out := root.path_join(CozyAssetLibrary.MANIFEST_NAME)
	var f := FileAccess.open(out, FileAccess.WRITE)
	if f == null:
		print("[manifest] cannot write %s  [FAIL]" % out)
		quit(1)
		return
	f.store_string(JSON.stringify(
		{"version": CozyAssetLibrary.MANIFEST_VERSION, "assets": paths},
		"  "))
	f.close()
	print("[manifest] %d asset(s) -> %s  [OK]" % [paths.size(), out])
	quit(0)
