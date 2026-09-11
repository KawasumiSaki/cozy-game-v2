extends Node3D
## CozyVale V2 — Phase 0 technical spike (V2 tech doc #169).
##
## The doc scopes Phase 0 down to exactly four things, to prove four things:
##     ground / wall / two characters / one building
##   -> front-to-back relations, going up and down floors, occlusion, camera
##
## AXIS CONVENTION (important):
##   The design doc records height as Z, but Godot is Y-up.
##   This project maps the doc's Z (height) onto Godot's +Y —
##   identical semantics (a floor IS a real elevation), different axis label.
##       doc(x, y, z)  ->  godot(x, z, y)
##
## Controls:
##   WASD move | Q/E rotate camera | R/F pitch | mouse wheel zoom

## Floor height: a building-system parameter, not hard-coded around the codebase (#8.2).
const FLOOR_H := 3.0

## House footprint
const HOUSE_W := 8.0
const HOUSE_D := 6.0
const WALL_T := 0.25

## Stairwell: the upper slab leaves a hole here, otherwise nobody can get upstairs.
const WELL_X0 := 5.0
const WELL_Z0 := 3.0

## Flip on to print a per-frame physics probe (useful under --headless).
const DEBUG_PHYSICS_PROBE := false

var camera: CozyCameraRig = null
var player: CozyCharacter = null
var npc: CozyCharacter = null
var walls: Array[CozyWall] = []
var hud: Label = null
var floor_system: CozyFloorSystem = null
var room_graph: CozyRoomGraph = null

var _is_headless := false


func _ready() -> void:
	# Note: OS.has_feature("headless") is FALSE under --headless in Godot 4.7;
	# the display server name is the reliable check.
	_is_headless = DisplayServer.get_name() == "headless"
	if _is_headless:
		print("[cozyv2] headless self-check start")
	_build_environment()
	_build_ground()
	_build_house()
	_detect_rooms()
	_build_characters()
	_build_camera()
	_build_hud()
	_report_rooms()


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
	var house := Node3D.new()
	house.name = "House"
	add_child(house)

	var y0 := 0.0
	var y1 := FLOOR_H

	# ---- Floor 0: an 8x6 rectangle with a 1.5m doorway in the south wall ----
	# The doorway splits the south wall into two segments. This is exactly the
	# advantage of segment walls over tiles (doc #16 / #19): the opening can sit
	# anywhere, it does not have to snap to a grid cell.
	_add_wall(house, Vector3(0.0, y0, 0.0), Vector3(2.5, y0, 0.0))              # south, left of door
	_add_wall(house, Vector3(4.0, y0, 0.0), Vector3(HOUSE_W, y0, 0.0))          # south, right of door
	_add_wall(house, Vector3(HOUSE_W, y0, 0.0), Vector3(HOUSE_W, y0, HOUSE_D))  # east
	_add_wall(house, Vector3(HOUSE_W, y0, HOUSE_D), Vector3(0.0, y0, HOUSE_D))  # north
	_add_wall(house, Vector3(0.0, y0, HOUSE_D), Vector3(0.0, y0, 0.0))          # west

	# ---- Floor 1: a full ring of exterior walls ----
	_add_wall(house, Vector3(0.0, y1, 0.0), Vector3(HOUSE_W, y1, 0.0))
	_add_wall(house, Vector3(HOUSE_W, y1, 0.0), Vector3(HOUSE_W, y1, HOUSE_D))
	_add_wall(house, Vector3(HOUSE_W, y1, HOUSE_D), Vector3(0.0, y1, HOUSE_D))
	_add_wall(house, Vector3(0.0, y1, HOUSE_D), Vector3(0.0, y1, 0.0))

	# ---- Upper slab, with a hole left open for the stairwell ----
	_add_box(house, Vector3(WELL_X0 * 0.5, y1 - 0.1, HOUSE_D * 0.5),
		Vector3(WELL_X0, 0.2, HOUSE_D), "stone")
	_add_box(house, Vector3((WELL_X0 + HOUSE_W) * 0.5, y1 - 0.1, WELL_Z0 * 0.5),
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
		_add_box(house, Vector3(cx, top * 0.5, well_cz),
			Vector3(step_run, top, well_d), "wood")

	var ramp := StaticBody3D.new()
	var rcs := CollisionShape3D.new()
	var rbox := BoxShape3D.new()
	rbox.size = Vector3(sqrt(run_x * run_x + rise * rise), 0.2, well_d)
	rcs.shape = rbox
	ramp.add_child(rcs)
	ramp.position = Vector3(WELL_X0 + run_x * 0.5, rise * 0.5, well_cz)
	ramp.rotation.z = atan2(rise, run_x)
	house.add_child(ramp)


func _add_wall(parent: Node3D, a: Vector3, b: Vector3, mat_id := "wood") -> void:
	var w := CozyWall.new()
	parent.add_child(w)
	w.setup(a, b, FLOOR_H, WALL_T, mat_id)
	walls.append(w)


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


# ---------------------------------------------------------------- rooms (V2-06)

## Rooms are DERIVED, never authored (doc #26). Feed the wall graph for each
## floor through a planar face traversal and the enclosed regions fall out.
func _detect_rooms() -> void:
	floor_system = CozyFloorSystem.new()
	floor_system.floor_height = FLOOR_H

	# Group wall centre-lines by floor.
	var by_floor := {}
	for w in walls:
		var fi := floor_system.floor_index_at(w.midpoint().y)
		if not by_floor.has(fi):
			by_floor[fi] = []
		by_floor[fi].append([Vector2(w.start.x, w.start.z), Vector2(w.end.x, w.end.z)])

	var detector := CozyRoomDetector.new()
	for fi in by_floor.keys():
		var segs: Array = by_floor[fi]
		segs.append_array(_door_bridges(fi))
		var polys := detector.detect(segs)
		for i in polys.size():
			floor_system.add_room(CozyRoom.new("room_%d_%d" % [fi, i], fi, polys[i]))

	# ---- Portals (V2-07) ----
	# A door and a staircase are the SAME abstraction to the routing system:
	# something that joins space A to space B (doc #8.5). Registering them as
	# portals is what stops floor changes from needing bespoke NPC code (#112).
	floor_system.add_portal(CozyPortal.new("door_south", CozyPortal.Kind.DOOR,
		Vector3(3.25, 0.05, -1.0), Vector3(3.25, 0.05, 1.0)))
	floor_system.add_portal(CozyPortal.new("stair_main", CozyPortal.Kind.STAIR,
		Vector3(5.3, 0.05, 4.5), Vector3(7.6, FLOOR_H + 0.05, 4.5)))

	# Now that rooms exist, ask the spatial model which room each side lands in.
	floor_system.resolve_portals()

	# ---- Room graph (V2-08) ----
	# Rooms are nodes, portals are edges. This is the macro half of navigation
	# (doc #41): it answers "which rooms must I cross?" without any geometry.
	room_graph = CozyRoomGraph.new()
	room_graph.build(floor_system)


## Doorways are physically open, but topologically they CLOSE a room — a door
## separates two spaces while remaining passable (doc #29: a Door knows both
## room_a and room_b). So detection bridges the opening.
func _door_bridges(floor_index: int) -> Array:
	if floor_index != 0:
		return []
	# The 1.5m doorway cut into the south wall (x 2.5 .. 4.0 at z = 0).
	return [[Vector2(2.5, 0.0), Vector2(4.0, 0.0)]]


func _report_rooms() -> void:
	if not _is_headless or floor_system == null:
		return
	print("[cozyv2] detected rooms:")
	print(floor_system.describe())

	# Assert the full lookup chain: wall graph -> polygon -> floor -> world point.
	_check_room_at(Vector3(4.0, 0.1, 3.0), "room_0_0")            # inside, ground floor
	_check_room_at(Vector3(4.0, FLOOR_H + 0.1, 3.0), "room_1_0")  # same xz, upper floor
	_check_room_at(Vector3(4.0, 0.1, -6.0), "outdoors")           # outside the footprint

	# Portals must resolve to the rooms their endpoints land in (doc #29).
	_check_portal("door_south", "", "room_0_0")        # outside <-> ground floor
	_check_portal("stair_main", "room_0_0", "room_1_0")  # ground floor <-> upper floor

	# Room graph must produce cross-floor routes with no geometry involved.
	_check_route(CozyRoomGraph.OUTDOORS, "room_1_0",
		"door_south[door] -> stair_main[stair]")
	_check_route("room_0_0", "room_1_0", "stair_main[stair]")
	_check_route("room_1_0", "room_1_0", "(no route)")


func _check_route(from_id: String, to_id: String, expect: String) -> void:
	var got := room_graph.route_description(room_graph.find_route(from_id, to_id))
	print("[cozyv2] route %-10s -> %-10s : %s  [%s]" % [
		CozyRoomGraph.display_name(from_id), CozyRoomGraph.display_name(to_id), got,
		"OK" if got == expect else "FAIL, expected " + expect])


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


func _check_room_at(pos: Vector3, expected: String) -> void:
	var r := floor_system.room_at(pos)
	var got := r.id if r != null else "outdoors"
	print("[cozyv2] room_at(%s) -> %s  [%s]" % [
		pos, got, "OK" if got == expected else "FAIL, expected " + expected])


# ---------------------------------------------------------------- characters

func _build_characters() -> void:
	# Order matters: add_child() fires _ready() immediately, and the sprite is
	# built inside _ready() from the configured colors. So setup() must run
	# BEFORE add_child(), otherwise every character gets the default palette.

	# Player starts outside, facing the doorway — easy to verify "walk round the
	# back / walk inside / go upstairs".
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
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.0, 0.0, 0.0, 0.45)
	sb.set_content_margin_all(6)
	hud.add_theme_stylebox_override("normal", sb)
	layer.add_child(hud)


# ---------------------------------------------------------------- input

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			camera.zoom_in()
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			camera.zoom_out()


func _process(delta: float) -> void:
	if Input.is_key_pressed(KEY_Q):
		camera.rotate_by(-100.0 * delta)
	if Input.is_key_pressed(KEY_E):
		camera.rotate_by(100.0 * delta)
	if Input.is_key_pressed(KEY_R):
		camera.pitch_by(45.0 * delta)
	if Input.is_key_pressed(KEY_F):
		camera.pitch_by(-45.0 * delta)

	var dir := Vector3.ZERO
	if _is_headless:
		dir = _autopilot_dir()
	else:
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

	# Auto-on under --headless so CI/self-checks always report physics state.
	if DEBUG_PHYSICS_PROBE or _is_headless:
		print("frame=%d pos=(%.2f, %.2f, %.2f) floor=%d on_floor=%s" % [
			Engine.get_physics_frames(), player.global_position.x,
			player.global_position.y, player.global_position.z,
			player.current_floor(FLOOR_H), str(player.is_on_floor())])

	_update_hud()


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


func _update_hud() -> void:
	var p := player.global_position
	var room := floor_system.room_at(p) if floor_system != null else null
	hud.text = "CozyVale V2  Phase 0\nWASD move | Q/E rotate | R/F pitch | wheel zoom\npos   %.1f, %.1f, %.1f\nfloor %d\nroom  %s\nwalls %d" % [
		p.x, p.y, p.z, player.current_floor(FLOOR_H),
		(room.id if room != null else "outdoors"), walls.size()]
