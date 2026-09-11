extends Node3D
## CozyVale V2 — a small but complete playable slice.
##
## What this scene is: a real 3D world (X/Y/Z, floors, collision, line of sight)
## presented as pixel art, where you can walk, drag out walls, drop furniture,
## and watch an NPC route upstairs on its own and get to work.
##
## Deliberately simple in places. The roof is a slab, not the doc's roof
## generator (#34–#37); furniture is a box, not a model. Those are art and
## polish problems. What is NOT simplified is the machinery underneath:
## rooms derived from geometry, portals, the room graph, and local navigation —
## because that is the part that is expensive to get wrong later.
##
## AXIS CONVENTION (important):
##   The design doc records height as Z, but Godot is Y-up.
##   This project maps the doc's Z (height) onto Godot's +Y —
##   identical semantics (a floor IS a real elevation), different axis label.
##       doc(x, y, z)  ->  godot(x, z, y)
##
## Controls:
##   WASD move | Q/E rotate | R/F pitch | wheel zoom
##   B toggle build mode | TAB cycle tool | left-drag wall / left-click furniture

## Floor height: a building-system parameter, not hard-coded around the codebase (#8.2).
const FLOOR_H := 3.0

const HOUSE_W := 8.0
const HOUSE_D := 6.0
const WALL_T := 0.25

const WELL_X0 := 4.5     ## Stairwell: the upper slab leaves a hole from here...
const WELL_X1 := 7.0     ## ...to here. The ramp tops out at WELL_X1 and the
                         ## remaining strip is a landing, so an agent arrives on
                         ## level floor instead of stepping off into a wall.
const WELL_Z0 := 3.0

const SNAP_M := 0.25     ## Wall snapping — assistance, not a cage (#84).
const MIN_WALL_LEN := 0.5

## Physics-frame milestones. Note --quit-after counts *idle* frames, and under
## headless the physics tick advances at roughly half that rate, so the quit
## count is set well above these.
const AUTOPILOT_DONE_FRAME := 420
const NPC_CHECK_FRAME := 900

const DEBUG_PHYSICS_PROBE := false

## Build tools: "wall" drags a segment, everything else places furniture.
const TOOLS: Array[String] = ["wall", "research_table", "chest", "bed", "chair"]

var camera: CozyCameraRig = null
var player: CozyCharacter = null
var npc: CozyNpcAgent = null
var hud: Label = null

var building: CozyBuildingSystem = null
var roofs: Array[CozyRoof] = []
var objects: Array[CozyWorldObject] = []

var floor_system: CozyFloorSystem = null
var room_graph: CozyRoomGraph = null
var world_navigator: CozyWorldNavigator = null
var local_nav: CozyLocalNav = null
var _nav_by_room: Dictionary = {}

var build_mode := false
var tool_idx := 0
var _drag_active := false
var _drag_start := Vector3.ZERO
var _drag_end := Vector3.ZERO
var _preview: MeshInstance3D = null

var _house: Node3D = null
var _is_headless := false
var _build_test_done := false
var _npc_test_done := false


func _ready() -> void:
	# Note: OS.has_feature("headless") is FALSE under --headless in Godot 4.7;
	# the display server name is the reliable check.
	_is_headless = DisplayServer.get_name() == "headless"
	if _is_headless:
		print("[cozyv2] headless self-check start")
	_build_environment()
	_build_ground()
	# The building system owns BuildingState and generates every wall view from
	# it (doc #18). Nothing else in this file is allowed to create a wall node.
	building = CozyBuildingSystem.new()
	add_child(building)
	building.setup(self)
	_build_house()
	_build_roof()
	_place_initial_furniture()
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


func _build_ground() -> void:
	var grass := CozyPixelArt.make_texture(16, Color(0.44, 0.72, 0.36), 0.055, 1337)

	var ground := MeshInstance3D.new()
	ground.name = "Ground"
	var pm := PlaneMesh.new()
	pm.size = Vector2(400.0, 400.0)
	ground.mesh = pm
	ground.material_override = CozyPixelArt.make_material(grass, Vector3(200.0, 200.0, 1.0))
	add_child(ground)

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

	# Every wall below is submitted as an Intent (doc #1.4). This function never
	# creates a node: the walls are generated from the resulting BuildingState.
	#
	# The south wall of floor 0 is ONE segment with a Door opening cut into it
	# (doc #24) — no hand-splitting, and no topology patching downstream.
	var intents: Array = [
		CozyBuildingIntent.draw_wall(Vector3(0.0, y0, 0.0), Vector3(HOUSE_W, y0, 0.0),
			FLOOR_H, WALL_T, "wood", 0).with_opening(CozyOpening.door(3.25, 1.5)),
		CozyBuildingIntent.draw_wall(Vector3(HOUSE_W, y0, 0.0), Vector3(HOUSE_W, y0, HOUSE_D),
			FLOOR_H, WALL_T, "wood", 0),
		CozyBuildingIntent.draw_wall(Vector3(HOUSE_W, y0, HOUSE_D), Vector3(0.0, y0, HOUSE_D),
			FLOOR_H, WALL_T, "wood", 0),
		CozyBuildingIntent.draw_wall(Vector3(0.0, y0, HOUSE_D), Vector3(0.0, y0, 0.0),
			FLOOR_H, WALL_T, "wood", 0),

		# Floor 1: exterior ring with windows.
		CozyBuildingIntent.draw_wall(Vector3(0.0, y1, 0.0), Vector3(HOUSE_W, y1, 0.0),
			FLOOR_H, WALL_T, "wood", 1)
			.with_opening(CozyOpening.window(2.0, 1.2))
			.with_opening(CozyOpening.window(6.0, 1.2)),
		CozyBuildingIntent.draw_wall(Vector3(HOUSE_W, y1, 0.0), Vector3(HOUSE_W, y1, HOUSE_D),
			FLOOR_H, WALL_T, "wood", 1),
		CozyBuildingIntent.draw_wall(Vector3(HOUSE_W, y1, HOUSE_D), Vector3(0.0, y1, HOUSE_D),
			FLOOR_H, WALL_T, "wood", 1).with_opening(CozyOpening.window(4.0, 1.6)),
		CozyBuildingIntent.draw_wall(Vector3(0.0, y1, HOUSE_D), Vector3(0.0, y1, 0.0),
			FLOOR_H, WALL_T, "wood", 1),
	]
	building.submit_many(intents)

	# NOTE: slabs and stairs are still emitted directly here. They belong in
	# BuildingState too (doc #18 lists Floor / Stair alongside Wall), but they
	# are not what the State refactor was about, and converting them now would
	# mix two changes. Tracked as remaining debt.

	# Upper slab: two pieces plus a landing at the head of the stairs, leaving
	# a stairwell hole between WELL_X0 and WELL_X1.
	_add_box(_house, Vector3(WELL_X0 * 0.5, y1 - 0.1, HOUSE_D * 0.5),
		Vector3(WELL_X0, 0.2, HOUSE_D), "stone", true)            # west half
	_add_box(_house, Vector3((WELL_X0 + HOUSE_W) * 0.5, y1 - 0.1, WELL_Z0 * 0.5),
		Vector3(HOUSE_W - WELL_X0, 0.2, WELL_Z0), "stone", true)  # south strip
	_add_box(_house, Vector3((WELL_X1 + HOUSE_W) * 0.5, y1 - 0.1,
		WELL_Z0 + (HOUSE_D - WELL_Z0) * 0.5),
		Vector3(HOUSE_W - WELL_X1, 0.2, HOUSE_D - WELL_Z0), "stone", true)  # landing

	# Stairs: stepped visuals, one hidden sloped collider. Colliding against the
	# step boxes themselves makes CharacterBody3D catch on every riser.
	#
	# The ramp runs from WELL_X0 to WELL_X1 and rises the full floor. Its slope
	# must stay under the agent's floor_max_angle, and — just as important — it
	# must TOP OUT AT FLOOR LEVEL. A ramp that reaches full height only at the
	# far wall leaves nothing to arrive on, and its tilted collider presents a
	# vertical face along z = WELL_Z0 that an agent cannot climb from the south.
	var steps := 8
	var run_x := WELL_X1 - WELL_X0
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


## A flat roof slab. Simple on purpose — see the class note. Its job right now
## is to occlude and fade, not to look like a real roof.
func _build_roof() -> void:
	var roof := CozyRoof.new()
	add_child(roof)
	roof.setup(Vector3(HOUSE_W + 0.8, 0.2, HOUSE_D + 0.8))
	roof.global_position = Vector3(HOUSE_W * 0.5, FLOOR_H * 2.0 + 0.1, HOUSE_D * 0.5)
	roofs.append(roof)


## The ONLY route by which this scene adds a wall. It returns the STATE, not a
## node — callers read facts, they never reach into generated geometry.
func _add_wall(a: Vector3, b: Vector3, mat_id := "wood", floor_id := 0) -> CozyWallState:
	return building.submit(
		CozyBuildingIntent.draw_wall(a, b, FLOOR_H, WALL_T, mat_id, floor_id))


## `collide` matters: floor slabs MUST be solid, or agents walk off the edge and
## drop to the floor below. Stair step boxes deliberately do NOT collide — the
## hidden ramp carries that, otherwise the capsule catches on every riser.
func _add_box(parent: Node3D, center: Vector3, box_size: Vector3, mat_id: String,
		collide := false) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = box_size
	mi.mesh = bm
	mi.position = center
	mi.material_override = CozyMaterials.get_material(mat_id,
		Vector3(maxf(box_size.x / 2.0, 1.0), maxf(box_size.z / 2.0, 1.0), 1.0))
	parent.add_child(mi)

	if collide:
		var body := StaticBody3D.new()
		body.position = center
		var cs := CollisionShape3D.new()
		var bs := BoxShape3D.new()
		bs.size = box_size
		cs.shape = bs
		body.add_child(cs)
		parent.add_child(body)

	return mi


# ---------------------------------------------------------------- furniture

## The NPC's workplace starts UPSTAIRS, so its very first job is the doc's
## worked example (#111): cross the ground floor, take the stairs, work on the
## first floor. If the routing were broken, the NPC would simply never deliver.
func _place_initial_furniture() -> void:
	_place_object("research_table", 2.0, 2.0, 1)
	_place_object("chest", 6.6, 1.0, 0)


func _place_object(def_id: String, x: float, z: float, floor_index: int) -> CozyWorldObject:
	if not CozyObjectDefs.exists(def_id):
		return null
	var obj := CozyWorldObject.new()
	add_child(obj)
	obj.setup(def_id, floor_index)
	obj.global_position = Vector3(x, float(floor_index) * FLOOR_H, z)
	obj.refresh_points()   # make its work points usable before the first frame
	objects.append(obj)
	return obj


# ---------------------------------------------------------------- spatial rebuild

## Re-derive every layer that depends on walls or furniture: wall joins, rooms,
## portals, the room graph, local navigation and the world navigator.
## Safe to call repeatedly — that is the point (doc #28).
func _rebuild_spatial() -> void:
	floor_system = CozyFloorSystem.new()
	floor_system.floor_height = FLOOR_H

	# Room detection reads centre-lines straight out of BuildingState. There is
	# no doorway bridging: an opening carves geometry but leaves the centre-line
	# intact, so the graph is already closed around a door. Bridging an intact
	# span would add a duplicate edge and corrupt the planar face traversal.
	var detector := CozyRoomDetector.new()
	for fi in building.state.floor_ids():
		var polys := detector.detect(building.centrelines_on_floor(fi))
		for i in polys.size():
			floor_system.add_room(CozyRoom.new("room_%d_%d" % [fi, i], fi, polys[i]))

	# Portals. Fixtures for now — V2-16 style derivation would bind these to
	# actual openings once openings carry a portal flag.
	floor_system.add_portal(CozyPortal.new("door_south", CozyPortal.Kind.DOOR,
		Vector3(3.25, 0.05, -1.0), Vector3(3.25, 0.05, 1.0)))
	# Both anchors sit OUTSIDE the ramp footprint: the foot just west of it (the
	# only side you can walk onto), the head on the landing at floor level.
	floor_system.add_portal(CozyPortal.new("stair_main", CozyPortal.Kind.STAIR,
		Vector3(WELL_X0 - 0.3, 0.05, 4.5),
		Vector3((WELL_X1 + HOUSE_W) * 0.5, FLOOR_H + 0.05, 4.5)))
	floor_system.resolve_portals()

	room_graph = CozyRoomGraph.new()
	room_graph.build(floor_system)

	# Local navigation per room, with furniture registered as obstacles.
	# This is what makes moving a table change routing (doc #86).
	_nav_by_room.clear()
	for r in floor_system.all_rooms():
		var nav := CozyLocalNav.new()
		nav.build(r, _obstacles_on_floor(r.floor_index))
		_nav_by_room[r.id] = nav
	local_nav = _nav_by_room.get("room_0_0", null)

	world_navigator = CozyWorldNavigator.new(floor_system, room_graph, _nav_by_room)
	if npc != null and is_instance_valid(npc):
		npc.navigator = world_navigator
		npc.objects = objects


func _obstacles_on_floor(floor_index: int) -> Array:
	var out := _static_obstacles_on_floor(floor_index)
	for o in objects:
		if is_instance_valid(o) and o.floor_index == floor_index:
			out.append(o.footprint_rect())
	return out


## Static geometry that navigation must route around but that is neither a wall
## nor a placed object.
##
## The staircase ramp is the case that matters. Its collider is a tilted slab,
## so along z = WELL_Z0 it presents a VERTICAL face — an agent approaching from
## the south walks into a wall it cannot climb. Blocking the steep part of the
## ramp leaves its low western end as the only approach, which is how a person
## climbs a staircase anyway.
func _static_obstacles_on_floor(floor_index: int) -> Array:
	if floor_index != 0 and floor_index != 1:
		return []
	# The stairwell occupies this footprint on BOTH floors, for two different
	# reasons, and navigation has to be told about each:
	#   floor 0 — the ramp is solid, and its low edge is only approachable from
	#             the west, so agents must be sent round rather than straight at
	#             the side of the slope.
	#   floor 1 — the same footprint is an OPEN HOLE. Without this an agent
	#             walks off the landing's edge and falls to the ground floor.
	return [Rect2(WELL_X0, WELL_Z0, WELL_X1 - WELL_X0, HOUSE_D - WELL_Z0)]


# ---------------------------------------------------------------- characters

func _build_characters() -> void:
	# Order matters: add_child() fires _ready() immediately, and the sprite is
	# built inside _ready() from the configured colors. So setup() must run
	# BEFORE add_child().

	player = CozyCharacter.new()
	player.setup("Player", Color(0.96, 0.80, 0.66), Color(0.36, 0.52, 0.78),
		Color(0.28, 0.18, 0.12), true)
	player.uses_gravity = true
	player.floor_max_angle = deg_to_rad(55.0)
	add_child(player)
	player.global_position = Vector3(3.25, 0.2, -3.5)

	# The NPC starts on the GROUND floor while its workstation is UPSTAIRS, so
	# its first job exercises the whole stack: local nav -> portal -> room graph
	# -> stairs -> local nav again (#111 / #112).
	npc = CozyNpcAgent.new()
	npc.setup("Researcher", Color(0.94, 0.76, 0.62), Color(0.78, 0.44, 0.42),
		Color(0.20, 0.14, 0.10), false)
	npc.uses_gravity = true
	npc.floor_max_angle = deg_to_rad(55.0)
	npc.move_speed = 3.5
	add_child(npc)
	npc.global_position = Vector3(6.0, 0.2, 1.5)
	npc.navigator = world_navigator
	npc.objects = objects


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
	# Walls and roofs both fade — a roof that cannot fade hides the player.
	occ.fadables = []
	occ.fadables.append_array(building.wall_views)
	occ.fadables.append_array(roofs)


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


func _build_floor_index() -> int:
	return player.current_floor(FLOOR_H)


func _snap(v: Vector3) -> Vector3:
	return Vector3(snappedf(v.x, SNAP_M), v.y, snappedf(v.z, SNAP_M))


func _current_tool() -> String:
	return TOOLS[tool_idx]


func _is_wall_tool() -> bool:
	return _current_tool() == "wall"


func _begin_drag() -> void:
	var p := _mouse_ground_point()
	if not is_finite(p.x):
		return
	if _is_wall_tool():
		_drag_start = _snap(p)
		_drag_end = _drag_start
		_drag_active = true
		_update_preview()
	else:
		# Furniture is a single click, not a drag.
		_place_object(_current_tool(), p.x, p.z, _build_floor_index())
		_rebuild_spatial()
		_update_hud()


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

	var t := CozyWallState.segment_transform(_drag_start, _drag_end, FLOOR_H)
	if float(t["length"]) < MIN_WALL_LEN:
		return   # A click, not a drag.

	_add_wall(_drag_start, _drag_end, "wood", _build_floor_index())
	_rebuild_spatial()
	_refresh_occlusion_fadables()
	_update_hud()


## The building system rebuilds wall views, so the occlusion list is
## re-collected rather than incrementally maintained.
func _refresh_occlusion_fadables() -> void:
	for c in get_children():
		if c is CozyOcclusion:
			c.fadables = []
			c.fadables.append_array(building.wall_views)
			c.fadables.append_array(roofs)


func _update_preview() -> void:
	if _preview == null:
		_preview = MeshInstance3D.new()
		var mat := StandardMaterial3D.new()
		mat.albedo_color = Color(0.35, 0.80, 1.0, 0.45)
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_preview.material_override = mat
		add_child(_preview)

	var t := CozyWallState.segment_transform(_drag_start, _drag_end, FLOOR_H)
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
		if build_mode and event.keycode == KEY_TAB:
			tool_idx = (tool_idx + 1) % TOOLS.size()
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
		_run_headless_stages()
	else:
		if build_mode:
			_update_drag()
			player.stop()
		else:
			_handle_move_keys()

	if DEBUG_PHYSICS_PROBE or _is_headless:
		print("frame=%d pos=(%.2f, %.2f, %.2f) floor=%d on_floor=%s | %s" % [
			Engine.get_physics_frames(), player.global_position.x,
			player.global_position.y, player.global_position.z,
			player.current_floor(FLOOR_H), str(player.is_on_floor()),
			npc.debug_line() if npc != null else "-"])

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


## Headless staged tests, run once each at fixed frames.
func _run_headless_stages() -> void:
	var f := Engine.get_physics_frames()
	if not _build_test_done and f > AUTOPILOT_DONE_FRAME:
		_build_test_done = true
		_run_live_rebuild_test()
	if not _npc_test_done and f > NPC_CHECK_FRAME:
		_npc_test_done = true
		_check_npc_work()


## Headless autopilot: outside -> through the doorway -> up the stairs (#169).
func _autopilot_dir() -> Vector3:
	var p := player.global_position
	if Engine.get_physics_frames() < 30:
		return Vector3.ZERO
	if p.z < 4.0:
		return Vector3(0.0, 0.0, 1.0)
	if p.x < 7.5:
		return Vector3(1.0, 0.0, 0.0)
	return Vector3.ZERO


# ---------------------------------------------------------------- self-check

func _report() -> void:
	if not _is_headless or floor_system == null:
		return
	print("[cozyv2] detected rooms:")
	print(floor_system.describe())

	_check_room_at(Vector3(4.0, 0.1, 3.0), "room_0_0")
	_check_room_at(Vector3(4.0, FLOOR_H + 0.1, 3.0), "room_1_0")
	_check_room_at(Vector3(4.0, 0.1, -6.0), "outdoors")

	_check_portal("door_south", "", "room_0_0")
	_check_portal("stair_main", "room_0_0", "room_1_0")

	_check_route(CozyRoomGraph.OUTDOORS, "room_1_0",
		"door_south[door] -> stair_main[stair]")
	_check_route("room_0_0", "room_1_0", "stair_main[stair]")
	_check_route("room_1_0", "room_1_0", "(no route)")

	_check_nav()
	_check_wall_connection()
	_check_openings()
	_check_npc_route_plan()


## Can an agent standing on the ground floor obtain a route to a work point on
## the first floor? That is the whole stack in one query (#41 / #112).
func _check_npc_route_plan() -> void:
	var table := _first_object("research_table")
	if table == null or table.interaction_points.is_empty():
		print("[cozyv2] npc route plan: NO WORK POINT  [FAIL]")
		return
	var target: Vector3 = table.interaction_points[0].world_position
	var from := Vector3(6.0, 0.1, 1.5)
	var pts := world_navigator.plan(from, target)
	var crosses_floor := false
	for p in pts:
		if p.y > FLOOR_H * 0.5:
			crosses_floor = true
			break
	print("[cozyv2] npc plan ground->upstairs: %d waypoints, crosses floor=%s  [%s]" % [
		pts.size(), str(crosses_floor),
		"OK" if pts.size() > 0 and crosses_floor else "FAIL"])


func _first_object(def_id: String) -> CozyWorldObject:
	for o in objects:
		if is_instance_valid(o) and o.def_id == def_id:
			return o
	return null


## The payoff assertion: the NPC must actually finish a job, not just exist.
func _check_npc_work() -> void:
	var ok := npc.completions > 0
	print("[cozyv2] npc completed %d job(s), state=%s  [%s]" % [
		npc.completions, npc.last_status, "OK" if ok else "FAIL, never finished work"])


func _run_live_rebuild_test() -> void:
	print("[cozyv2] --- live rebuild test: add a dividing wall ---")
	var before := floor_system.rooms_on(0).size()
	# Bisect the GROUND floor. The autopilot has already finished by this frame,
	# so the new wall cannot interfere with the walk-through test.
	_add_wall(Vector3(4.0, 0.0, 0.0), Vector3(4.0, 0.0, HOUSE_D), "wood", 0)
	_rebuild_spatial()
	_refresh_occlusion_fadables()
	var after := floor_system.rooms_on(0).size()
	print("[cozyv2] floor-0 rooms %d -> %d  [%s]" % [
		before, after,
		"OK" if after == before + 1 else "FAIL, expected %d" % (before + 1)])


func _check_nav() -> void:
	if local_nav == null:
		print("[cozyv2] local nav NOT BUILT  [FAIL]")
		return
	var from := Vector2(3.25, 1.0)          # just inside the doorway
	var to := Vector2(WELL_X0 - 0.3, 4.5)   # the foot of the stairs

	var p1 := local_nav.find_path(from, to)
	var l1 := CozyLocalNav.path_length(p1)
	print("[cozyv2] nav door->stair:      %3d pts, %5.2f m  [%s]" % [
		p1.size(), l1, "OK" if p1.size() > 0 else "FAIL, no path"])
	if p1.is_empty():
		return

	# Block the direct line with a table-sized obstacle, clear of the target.
	local_nav.add_obstacle(Rect2(3.7, 1.5, 0.5, 2.5))
	var p2 := local_nav.find_path(from, to)
	var l2 := CozyLocalNav.path_length(p2)
	var detoured := p2.size() > 0 and l2 > l1
	print("[cozyv2] nav after obstacle:   %3d pts, %5.2f m  [%s]" % [
		p2.size(), l2,
		"OK, detour +%.2f m" % (l2 - l1) if detoured else "FAIL, route did not change"])


func _check_wall_connection() -> void:
	var corner := Vector3(HOUSE_W + 0.1, 1.5, -0.1)

	# Un-solve, regenerate WITHOUT solving, measure, then solve and measure
	# again — so the result proves the solver fills the corner rather than
	# assuming it.
	for ws in building.state.walls:
		ws.extend_start = 0.0
		ws.extend_end = 0.0
	building.regenerate([], true)
	var before := CozyWallSolver.any_view_contains(building.wall_views, corner)

	building.regenerate()
	var after := CozyWallSolver.any_view_contains(building.wall_views, corner)

	print("[cozyv2] corner(%.1f,%.1f) solid: %s -> %s  [%s]" % [
		corner.x, corner.z, str(before), str(after),
		"OK" if (not before and after) else "FAIL"])


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
		var is_solid := CozyWallSolver.any_view_contains(building.wall_views, p)
		var ok := is_solid == want_solid
		all_ok = all_ok and ok
		print("[cozyv2]   %-22s %-5s  [%s]" % [
			label, "solid" if is_solid else "open", "OK" if ok else "FAIL"])
	print("[cozyv2] openings  [%s]" % ("OK" if all_ok else "FAIL"))


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
	var mode := "MOVE"
	if build_mode:
		mode = "BUILD [%s]  TAB cycles" % _current_tool()
	hud.text = "CozyVale V2\n%s\nWASD move | Q/E rotate | R/F pitch | wheel zoom | B build\npos %.1f,%.1f,%.1f  floor %d  room %s\nwalls %d  objects %d  rooms %d\nNPC: %s" % [
		mode, p.x, p.y, p.z, player.current_floor(FLOOR_H),
		(room.id if room != null else "outdoors"),
		building.state.wall_count(), objects.size(),
		floor_system.all_rooms().size() if floor_system != null else 0,
		npc.status_line() if npc != null else "-"]
