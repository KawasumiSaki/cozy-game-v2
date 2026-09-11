extends Node3D
## CozyVale V2 — Phase 0/1 spike, plus live building.
##
## The doc scopes Phase 0 (#169) down to ground / wall / two characters / one
## building, to prove front-to-back relations, floors, occlusion and camera.
## Phase 1 adds the spatial core: floors, rooms, portals, macro + local routing.
##
## This scene also pulls the first slice of Phase 3 forward: the player can drag
## out a wall and every derived layer re-computes live — rooms, portals, the room
## graph and local navigation. That is doc #28's claim made visible:
##     "a building is not a static picture but a dynamic spatial structure"
##
## AXIS CONVENTION (important):
##   The design doc records height as Z, but Godot is Y-up.
##   This project maps the doc's Z (height) onto Godot's +Y —
##   identical semantics (a floor IS a real elevation), different axis label.
##       doc(x, y, z)  ->  godot(x, z, y)
##
## Controls:
##   WASD move | Q/E rotate | R/F pitch | wheel zoom | B toggle build mode
##   In build mode: left-drag on the ground to place a wall

## Floor height: a building-system parameter, not hard-coded around the codebase (#8.2).
const FLOOR_H := 3.0

## House footprint
const HOUSE_W := 8.0
const HOUSE_D := 6.0
const WALL_T := 0.25

## Stairwell: the upper slab leaves a hole here, otherwise nobody can get upstairs.
const WELL_X0 := 5.0
const WELL_Z0 := 3.0

## Wall endpoints snap to this grid while dragging. Doc #84 is explicit that
## snapping must be assistance, not a cage — so this is deliberately fine.
const SNAP_M := 0.25
const MIN_WALL_LEN := 0.5

## When the headless autopilot has finished its run, exercise live rebuilding.
const AUTOPILOT_DONE_FRAME := 420

## Flip on to print a per-frame physics probe outside headless too.
const DEBUG_PHYSICS_PROBE := false

var camera: CozyCameraRig = null
var player: CozyCharacter = null
var npc: CozyCharacter = null
var hud: Label = null

var walls: Array[CozyWall] = []
var floor_system: CozyFloorSystem = null
var room_graph: CozyRoomGraph = null
var local_nav: CozyLocalNav = null
var _nav_by_room: Dictionary = {}

var build_mode := false
var _drag_active := false
var _drag_start := Vector3.ZERO
var _drag_end := Vector3.ZERO
var _preview: MeshInstance3D = null

var _house: Node3D = null
var _is_headless := false
var _build_test_done := false


func _ready() -> void:
	# Note: OS.has_feature("headless") is FALSE under --headless in Godot 4.7;
	# the display server name is the reliable check.
	_is_headless = DisplayServer.get_name() == "headless"
	if _is_headless:
		print("[cozyv2] headless self-check start")
	_build_environment()
	_build_ground()
	_build_house()
	_rebuild_spatial()
	_build_characters()
	_build_camera()
	_build_hud()
	_report()


# ---------------------------------------------------------------- environment

func _build_environment() -> void:
	# "Home must make you want to live in it" (doc #34) — bright daylight, blue sky.
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.53, 0.74, 0.92)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.78, 0.82, 0.88)
	env.ambient_light_energy = 1.0
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)

	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-52.0, -38.0, 0.0)
	sun.light_energy = 1.15
	sun.light_color = Color(1.0, 0.97, 0.90)
	sun.shadow_enabled = true
	add_child(sun)


# ---------------------------------------------------------------- ground

func _build_ground() -> void:
	var grass := CozyPixelArt.make_texture(16, Color(0.44, 0.72, 0.36), 0.055, 1337)

	var ground := MeshInstance3D.new()
	ground.name = "Ground"
	var pm := PlaneMesh.new()
	pm.size = Vector2(400.0, 400.0)
	ground.mesh = pm
	ground.material_override = CozyPixelArt.make_material(grass, Vector3(200.0, 200.0, 1.0))
	add_child(ground)

	# Ground collision — without it the player falls forever.
	var body := StaticBody3D.new()
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(400.0, 1.0, 400.0)
	cs.shape = box
	cs.position = Vector3(0.0, -0.5, 0.0)
	body.add_child(cs)
	add_child(body)


# ---------------------------------------------------------------- building

func _build_house() -> void:
	_house = Node3D.new()
	_house.name = "House"
	add_child(_house)

	var y0 := 0.0
	var y1 := FLOOR_H

	# ---- Floor 0: an 8x6 rectangle, south wall carrying a real doorway ----
	# The south wall is ONE segment with a Door opening cut into it (V2-16).
	# It used to be two hand-split segments with a gap between them; now the
	# wall generates its own geometry around the hole.
	var south := _add_wall(_house, Vector3(0.0, y0, 0.0), Vector3(HOUSE_W, y0, 0.0))
	south.add_opening(CozyOpening.door(3.25, 1.5))

	_add_wall(_house, Vector3(HOUSE_W, y0, 0.0), Vector3(HOUSE_W, y0, HOUSE_D))  # east
	_add_wall(_house, Vector3(HOUSE_W, y0, HOUSE_D), Vector3(0.0, y0, HOUSE_D))  # north
	_add_wall(_house, Vector3(0.0, y0, HOUSE_D), Vector3(0.0, y0, 0.0))          # west

	# ---- Floor 1: exterior ring with windows ----
	var up_south := _add_wall(_house, Vector3(0.0, y1, 0.0), Vector3(HOUSE_W, y1, 0.0))
	up_south.add_opening(CozyOpening.window(2.0, 1.2))
	up_south.add_opening(CozyOpening.window(6.0, 1.2))

	_add_wall(_house, Vector3(HOUSE_W, y1, 0.0), Vector3(HOUSE_W, y1, HOUSE_D))
	var up_north := _add_wall(_house, Vector3(HOUSE_W, y1, HOUSE_D), Vector3(0.0, y1, HOUSE_D))
	up_north.add_opening(CozyOpening.window(4.0, 1.6))
	_add_wall(_house, Vector3(0.0, y1, HOUSE_D), Vector3(0.0, y1, 0.0))

	# ---- Upper slab, with a hole left open for the stairwell ----
	_add_box(_house, Vector3(WELL_X0 * 0.5, y1 - 0.1, HOUSE_D * 0.5),
		Vector3(WELL_X0, 0.2, HOUSE_D), "stone")
	_add_box(_house, Vector3((WELL_X0 + HOUSE_W) * 0.5, y1 - 0.1, WELL_Z0 * 0.5),
		Vector3(HOUSE_W - WELL_X0, 0.2, WELL_Z0), "stone")

	# ---- Stairs: stepped visuals, but a single sloped collider ----
	# Colliding against the step boxes themselves makes CharacterBody3D catch on
	# every riser. Carrying the collision on one hidden slope keeps it walkable
	# while still looking like a staircase.
	var steps := 8
	var run_x := HOUSE_W - WELL_X0
	var rise := FLOOR_H
	var step_run := run_x / float(steps)
	var step_rise := rise / float(steps)
	var well_d := HOUSE_D - WELL_Z0
	var well_cz := WELL_Z0 + well_d * 0.5

	for i in steps:
		var top := float(i + 1) * step_rise
		var cx := WELL_X0 + (float(i) + 0.5) * step_run
		_add_box(_house, Vector3(cx, top * 0.5, well_cz),
			Vector3(step_run, top, well_d), "wood")

	var ramp := StaticBody3D.new()
	var rcs := CollisionShape3D.new()
	var rbox := BoxShape3D.new()
	rbox.size = Vector3(sqrt(run_x * run_x + rise * rise), 0.2, well_d)
	rcs.shape = rbox
	ramp.add_child(rcs)
	ramp.position = Vector3(WELL_X0 + run_x * 0.5, rise * 0.5, well_cz)
	ramp.rotation.z = atan2(rise, run_x)
	_house.add_child(ramp)


func _add_wall(parent: Node3D, a: Vector3, b: Vector3, mat_id := "wood") -> CozyWall:
	var w := CozyWall.new()
	parent.add_child(w)
	w.setup(a, b, FLOOR_H, WALL_T, mat_id)
	walls.append(w)
	return w


func _add_box(parent: Node3D, center: Vector3, box_size: Vector3, mat_id: String) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = box_size
	mi.mesh = bm
	mi.position = center
	mi.material_override = CozyMaterials.get_material(mat_id,
		Vector3(maxf(box_size.x / 2.0, 1.0), maxf(box_size.z / 2.0, 1.0), 1.0))
	parent.add_child(mi)
	return mi


# ---------------------------------------------------------------- spatial rebuild

## Re-derive every layer that depends on the walls: rooms, portals, the room
## graph and local navigation. Safe to call repeatedly — that is the whole point
## (doc #28: change a wall, the room polygon is recomputed).
func _rebuild_spatial() -> void:
	# Wall joins first: every wall that meets another runs half a thickness past
	# the joint, so corners read as solid (doc #24 / #25). Room detection below
	# uses centre-lines and is unaffected by the extension.
	CozyWallSolver.solve(walls)

	floor_system = CozyFloorSystem.new()
	floor_system.floor_height = FLOOR_H

	# Group wall centre-lines by floor.
	var by_floor := {}
	for w in walls:
		var fi := floor_system.floor_index_at(w.midpoint().y)
		if not by_floor.has(fi):
			by_floor[fi] = []
		by_floor[fi].append([Vector2(w.start.x, w.start.z), Vector2(w.end.x, w.end.z)])

	# Note: NO bridging of doorways here any more. An opening carves geometry but
	# leaves the wall's centre-line intact, so the wall graph is already closed
	# around a doorway and the room is detected without help. (Bridging used to
	# be required when a doorway was a physical gap between two wall segments;
	# it is now redundant, and a bridge over an intact span would add a duplicate
	# edge that corrupts the planar face traversal.)
	var detector := CozyRoomDetector.new()
	for fi in by_floor.keys():
		var polys := detector.detect(by_floor[fi])
		for i in polys.size():
			floor_system.add_room(CozyRoom.new("room_%d_%d" % [fi, i], fi, polys[i]))

	# Portals. These are fixtures for now — V2-16 (openings) will derive them
	# from the wall data itself, at which point walling up a door will
	# automatically remove its portal.
	floor_system.add_portal(CozyPortal.new("door_south", CozyPortal.Kind.DOOR,
		Vector3(3.25, 0.05, -1.0), Vector3(3.25, 0.05, 1.0)))
	floor_system.add_portal(CozyPortal.new("stair_main", CozyPortal.Kind.STAIR,
		Vector3(5.3, 0.05, 4.5), Vector3(7.6, FLOOR_H + 0.05, 4.5)))
	floor_system.resolve_portals()

	# Rooms are nodes, portals are edges (doc #41, macro half).
	room_graph = CozyRoomGraph.new()
	room_graph.build(floor_system)

	# Local navigation per room (doc #41, local half).
	_nav_by_room.clear()
	for r in floor_system.all_rooms():
		var nav := CozyLocalNav.new()
		nav.build(r)
		_nav_by_room[r.id] = nav
	local_nav = _nav_by_room.get("room_0_0", null)


# ---------------------------------------------------------------- characters

func _build_characters() -> void:
	# Order matters: add_child() fires _ready() immediately, and the sprite is
	# built inside _ready() from the configured colors. So setup() must run
	# BEFORE add_child(), otherwise every character gets the default palette.

	# Player starts outside, facing the doorway.
	player = CozyCharacter.new()
	player.setup("Player", Color(0.96, 0.80, 0.66), Color(0.36, 0.52, 0.78),
		Color(0.28, 0.18, 0.12), true)
	player.uses_gravity = true
	player.floor_max_angle = deg_to_rad(52.0)   # let the 45-degree staircase be walkable
	add_child(player)
	player.global_position = Vector3(3.25, 0.2, -3.5)

	# NPC stands on the upper floor — exercises multi-floor and occlusion.
	npc = CozyCharacter.new()
	npc.setup("NPC", Color(0.94, 0.76, 0.62), Color(0.78, 0.44, 0.42),
		Color(0.20, 0.14, 0.10), false)
	add_child(npc)
	npc.global_position = Vector3(2.5, FLOOR_H + 0.1, 3.0)


# ---------------------------------------------------------------- camera & occlusion

func _build_camera() -> void:
	camera = CozyCameraRig.new()
	add_child(camera)
	camera.target = player
	camera.snap_to_target()

	var occ := CozyOcclusion.new()
	add_child(occ)
	occ.camera = camera
	occ.targets = [player, npc]
	occ.walls = walls


# ---------------------------------------------------------------- HUD

func _build_hud() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)

	hud = Label.new()
	hud.position = Vector2(8, 6)
	hud.add_theme_font_size_override("font_size", 11)
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.0, 0.0, 0.0, 0.45)
	sb.set_content_margin_all(6)
	hud.add_theme_stylebox_override("normal", sb)
	layer.add_child(hud)


# ---------------------------------------------------------------- build interaction

## Where the mouse points on the build floor's plane.
## The camera is orthographic, so the ray is still well-defined.
func _mouse_ground_point() -> Vector3:
	var mp := get_viewport().get_mouse_position()
	var from := camera.project_ray_origin(mp)
	var dir := camera.project_ray_normal(mp)
	var plane_y := floor_system.elevation_of(_build_floor_index())
	if absf(dir.y) < 0.0001:
		return Vector3(INF, INF, INF)
	var t := (plane_y - from.y) / dir.y
	if t < 0.0:
		return Vector3(INF, INF, INF)
	return from + dir * t


## Build on the floor the player is standing on — so you can wall in an upstairs
## room without touching the ground floor.
func _build_floor_index() -> int:
	return player.current_floor(FLOOR_H)


func _snap(v: Vector3) -> Vector3:
	return Vector3(snappedf(v.x, SNAP_M), v.y, snappedf(v.z, SNAP_M))


func _begin_drag() -> void:
	var p := _mouse_ground_point()
	if not is_finite(p.x):
		return
	_drag_start = _snap(p)
	_drag_end = _drag_start
	_drag_active = true
	_update_preview()


func _update_drag() -> void:
	if not _drag_active:
		return
	var p := _mouse_ground_point()
	if is_finite(p.x):
		_drag_end = _snap(p)
	_update_preview()


func _end_drag() -> void:
	if not _drag_active:
		return
	_drag_active = false
	_clear_preview()

	var t := CozyWall.segment_transform(_drag_start, _drag_end, FLOOR_H)
	if float(t["length"]) < MIN_WALL_LEN:
		return   # A click, not a drag — nothing to build.

	_add_wall(_house, _drag_start, _drag_end)
	# Everything downstream re-derives from the wall list, so one call is enough.
	_rebuild_spatial()
	_update_hud()


func _update_preview() -> void:
	if _preview == null:
		_preview = MeshInstance3D.new()
		var mat := StandardMaterial3D.new()
		mat.albedo_color = Color(0.35, 0.80, 1.0, 0.45)
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_preview.material_override = mat
		add_child(_preview)

	var t := CozyWall.segment_transform(_drag_start, _drag_end, FLOOR_H)
	var bm := BoxMesh.new()
	bm.size = Vector3(float(t["length"]), FLOOR_H, WALL_T)
	_preview.mesh = bm
	_preview.position = t["center"]
	_preview.rotation.y = t["angle"]


func _clear_preview() -> void:
	if _preview != null:
		_preview.queue_free()
		_preview = null


# ---------------------------------------------------------------- input

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_B:
			build_mode = not build_mode
			if not build_mode:
				_drag_active = false
				_clear_preview()
			_update_hud()
			return

	if build_mode:
		if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
			if event.pressed:
				_begin_drag()
			else:
				_end_drag()
			return

	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			camera.zoom_in()
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			camera.zoom_out()


func _process(delta: float) -> void:
	_handle_camera_keys(delta)

	if _is_headless:
		player.set_move_dir(_autopilot_dir())
		if not _build_test_done and Engine.get_physics_frames() > AUTOPILOT_DONE_FRAME:
			_build_test_done = true
			_run_live_rebuild_test()
	else:
		if build_mode:
			_update_drag()
			player.stop()
		else:
			_handle_move_keys()

	if DEBUG_PHYSICS_PROBE or _is_headless:
		print("frame=%d pos=(%.2f, %.2f, %.2f) floor=%d on_floor=%s" % [
			Engine.get_physics_frames(), player.global_position.x,
			player.global_position.y, player.global_position.z,
			player.current_floor(FLOOR_H), str(player.is_on_floor())])

	_update_hud()


func _handle_camera_keys(delta: float) -> void:
	if Input.is_key_pressed(KEY_Q):
		camera.rotate_by(-100.0 * delta)
	if Input.is_key_pressed(KEY_E):
		camera.rotate_by(100.0 * delta)
	if Input.is_key_pressed(KEY_R):
		camera.pitch_by(45.0 * delta)
	if Input.is_key_pressed(KEY_F):
		camera.pitch_by(-45.0 * delta)


func _handle_move_keys() -> void:
	var dir := Vector3.ZERO
	if Input.is_key_pressed(KEY_W):
		dir += camera.ground_forward()
	if Input.is_key_pressed(KEY_S):
		dir -= camera.ground_forward()
	if Input.is_key_pressed(KEY_A):
		dir -= camera.ground_right()
	if Input.is_key_pressed(KEY_D):
		dir += camera.ground_right()

	if dir.length_squared() > 0.0:
		player.set_move_dir(dir.normalized())
	else:
		player.stop()


## Headless autopilot: drives the player through the Phase 0 acceptance path
## (outside -> through the doorway -> up the staircase -> onto floor 1).
##
## Without this, the self-check only proves "it did not crash". With it, the
## multi-floor traversal that doc #169 actually asks for gets exercised.
func _autopilot_dir() -> Vector3:
	var p := player.global_position
	if Engine.get_physics_frames() < 30:
		return Vector3.ZERO                 # let gravity settle first
	if p.z < 4.0:
		return Vector3(0.0, 0.0, 1.0)       # walk north, straight through the doorway
	if p.x < 7.5:
		return Vector3(1.0, 0.0, 0.0)       # walk east, up the staircase
	return Vector3.ZERO                     # arrived


# ---------------------------------------------------------------- self-check

func _report() -> void:
	if not _is_headless or floor_system == null:
		return
	print("[cozyv2] detected rooms:")
	print(floor_system.describe())

	# Assert the full lookup chain: wall graph -> polygon -> floor -> world point.
	_check_room_at(Vector3(4.0, 0.1, 3.0), "room_0_0")            # inside, ground floor
	_check_room_at(Vector3(4.0, FLOOR_H + 0.1, 3.0), "room_1_0")  # same xz, upper floor
	_check_room_at(Vector3(4.0, 0.1, -6.0), "outdoors")           # outside the footprint

	# Portals must resolve to the rooms their endpoints land in (doc #29).
	_check_portal("door_south", "", "room_0_0")          # outside <-> ground floor
	_check_portal("stair_main", "room_0_0", "room_1_0")  # ground floor <-> upper floor

	# Room graph must produce cross-floor routes with no geometry involved.
	_check_route(CozyRoomGraph.OUTDOORS, "room_1_0",
		"door_south[door] -> stair_main[stair]")
	_check_route("room_0_0", "room_1_0", "stair_main[stair]")
	_check_route("room_1_0", "room_1_0", "(no route)")

	_check_nav()
	_check_wall_connection()
	_check_openings()


## Openings (V2-16, doc #29 / #30). A wall carves its own geometry around a hole:
## a doorway reaches the floor and leaves a gap an agent walks through, while a
## window leaves a solid sill below it — which is what stops the agent, with no
## special-casing anywhere.
func _check_openings() -> void:
	var cases := [
		["door gap (walkable)", Vector3(3.25, 1.0, 0.0), false],
		["door lintel (solid)", Vector3(3.25, 2.6, 0.0), true],
		["window gap (open)", Vector3(2.0, 4.5, 0.0), false],
		["window sill (solid)", Vector3(2.0, 3.4, 0.0), true],
	]
	var all_ok := true
	for c in cases:
		var label: String = c[0]
		var p: Vector3 = c[1]
		var want_solid: bool = c[2]
		var is_solid := CozyWallSolver.any_wall_contains(walls, p)
		var ok := is_solid == want_solid
		all_ok = all_ok and ok
		print("[cozyv2]   %-22s %-5s  [%s]" % [
			label, "solid" if is_solid else "open", "OK" if ok else "FAIL"])
	print("[cozyv2] openings  [%s]" % ("OK" if all_ok else "FAIL"))


## Wall connection solving (V2-15, doc #24 / #25).
## Measure the outer corner before and after solving, rather than assuming the
## solver is what fills it — unsolving first proves causation.
func _check_wall_connection() -> void:
	var corner := Vector3(HOUSE_W + 0.1, 1.5, -0.1)   # just outside the SE corner

	for w in walls:
		w.extend_start = 0.0
		w.extend_end = 0.0
		w.refresh()
	var before := CozyWallSolver.any_wall_contains(walls, corner)

	CozyWallSolver.solve(walls)
	var after := CozyWallSolver.any_wall_contains(walls, corner)

	var joined := 0
	for w in walls:
		if w.extend_start > 0.0:
			joined += 1
		if w.extend_end > 0.0:
			joined += 1

	print("[cozyv2] corner(%.1f,%.1f) solid: %s -> %s  [%s]  (%d joined ends)" % [
		corner.x, corner.z, str(before), str(after),
		"OK" if (not before and after) else "FAIL", joined])


## Proves doc #28 — "a building is not a static picture but a dynamic spatial
## structure". Add a dividing wall at runtime; every derived layer must follow.
## Runs only after the autopilot has arrived, because a bisecting wall would
## otherwise block the walk-through path.
func _run_live_rebuild_test() -> void:
	print("[cozyv2] --- live rebuild test: add a dividing wall ---")
	var before := floor_system.rooms_on(0).size()
	_add_wall(_house, Vector3(4.0, 0.0, 0.0), Vector3(4.0, 0.0, HOUSE_D))
	_rebuild_spatial()
	var after := floor_system.rooms_on(0).size()
	print("[cozyv2] floor-0 rooms %d -> %d  [%s]" % [
		before, after,
		"OK" if after == before + 1 else "FAIL, expected %d" % (before + 1)])
	print(floor_system.describe())


## Local navigation, and the dynamic-update requirement from doc #86:
## put a piece of furniture in the way and routing must react to it.
func _check_nav() -> void:
	if local_nav == null:
		print("[cozyv2] local nav NOT BUILT  [FAIL]")
		return

	var from := Vector2(3.25, 1.0)   # just inside the doorway
	var to := Vector2(5.3, 4.5)      # foot of the staircase

	var p1 := local_nav.find_path(from, to)
	var l1 := CozyLocalNav.path_length(p1)
	print("[cozyv2] nav door->stair:      %3d pts, %5.2f m  [%s]" % [
		p1.size(), l1, "OK" if p1.size() > 0 else "FAIL, no path"])
	if p1.is_empty():
		return

	# Block the direct line with a 0.6 x 4.0 m obstacle, as a table would.
	local_nav.add_obstacle(Rect2(4.0, 1.2, 0.6, 4.0))
	var p2 := local_nav.find_path(from, to)
	var l2 := CozyLocalNav.path_length(p2)
	var detoured := p2.size() > 0 and l2 > l1
	print("[cozyv2] nav after obstacle:   %3d pts, %5.2f m  [%s]" % [
		p2.size(), l2,
		"OK, detour +%.2f m" % (l2 - l1) if detoured else "FAIL, route did not change"])


func _check_room_at(pos: Vector3, expected: String) -> void:
	var r := floor_system.room_at(pos)
	var got := r.id if r != null else "outdoors"
	print("[cozyv2] room_at(%s) -> %s  [%s]" % [
		pos, got, "OK" if got == expected else "FAIL, expected " + expected])


func _check_portal(pid: String, expect_a: String, expect_b: String) -> void:
	for p in floor_system.all_portals():
		if p.id != pid:
			continue
		var got_a := p.a_room if p.a_room != "" else "outdoors"
		var got_b := p.b_room if p.b_room != "" else "outdoors"
		var ok := got_a == (expect_a if expect_a != "" else "outdoors") \
			and got_b == (expect_b if expect_b != "" else "outdoors")
		print("[cozyv2] portal %-12s %s <-> %s  [%s]" % [
			pid, got_a, got_b,
			"OK" if ok else "FAIL, expected %s/%s" % [expect_a, expect_b]])
		return
	print("[cozyv2] portal %s NOT FOUND  [FAIL]" % pid)


func _check_route(from_id: String, to_id: String, expect: String) -> void:
	var got := room_graph.route_description(room_graph.find_route(from_id, to_id))
	print("[cozyv2] route %-10s -> %-10s : %s  [%s]" % [
		CozyRoomGraph.display_name(from_id), CozyRoomGraph.display_name(to_id), got,
		"OK" if got == expect else "FAIL, expected " + expect])


# ---------------------------------------------------------------- HUD text

func _update_hud() -> void:
	var p := player.global_position
	var room := floor_system.room_at(p) if floor_system != null else null
	var mode := "BUILD (drag to place a wall)" if build_mode else "MOVE"
	hud.text = "CozyVale V2\n%s\nWASD move | Q/E rotate | R/F pitch | wheel zoom | B build\npos   %.1f, %.1f, %.1f\nfloor %d   room %s\nwalls %d   rooms %d" % [
		mode, p.x, p.y, p.z, player.current_floor(FLOOR_H),
		(room.id if room != null else "outdoors"),
		walls.size(), floor_system.all_rooms().size() if floor_system != null else 0]
