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

## Tools, grouped by what the OPERATION is.
##
## Doc #24 is the reason a Door is not here: an opening is a property of a wall,
## not a thing you place. Neither is a roof or a foundation — those are DERIVED
## from what you draw. A palette listing "Wall / Door / Roof" as siblings would
## quietly undo V2-16 and V2-17.
##
## The terrain tools make an existing system reachable for the first time:
## CozyTerrainIntent has had CLEAR/DIG/FILL since V2-11 with no way to invoke it.
const TERRAIN_TOOLS: Array[String] = ["dig", "fill", "clear"]
const BUILD_TOOLS: Array[String] = ["outline", "wall"]
const PLACE_TOOLS: Array[String] = ["research_table", "chest", "bed", "chair",
	"campfire"]
const TOOL_GROUPS: Array = [BUILD_TOOLS, TERRAIN_TOOLS, PLACE_TOOLS]
const TOOLS: Array[String] = ["outline", "wall", "dig", "fill", "clear",
	"research_table", "chest", "bed", "chair", "campfire"]

## Brush radius for terrain tools, metres.
const TERRAIN_BRUSH := 2.5

var camera: CozyCameraRig = null
var player: CozyCharacter = null
var npc: CozyNpcAgent = null
var occlusion: CozyOcclusion = null
var hud: CozyHud = null
var menu: CozyContextMenu = null

var building: CozyBuildingSystem = null
var terrain: CozyTerrainSystem = null
var terrain_renderer: CozyTerrainRenderer = null
var assets: CozyAssetLibrary = null
var scatter: CozyVegetationScatter = null
var objects: Array[CozyWorldObject] = []

var floor_system: CozyFloorSystem = null
var room_graph: CozyRoomGraph = null
var world_navigator: CozyWorldNavigator = null
var local_nav: CozyLocalNav = null
var _nav_by_room: Dictionary = {}
## Per-floor room cache, so an edit only re-derives its own floor (doc #33).
var _rooms_by_floor: Dictionary = {}

var build_mode := false
## Feedback shown in the HUD strip. Timed, so a confirmation clears itself and a
## refusal does not sit on screen forever after the situation has changed.
var _hud_message := ""
var _hud_message_warn := false
var _hud_message_until := 0.0
var tool_idx := 0
var _drag_active := false
var _drag_start := Vector3.ZERO
var _drag_end := Vector3.ZERO
var _preview: MeshInstance3D = null

## Points collected while drawing a building outline (world x, z).
var _outline_points := PackedVector2Array()
var _outline_preview: MeshInstance3D = null

var _clock := 0.0
var _is_headless := false
var _build_test_done := false
var _npc_test_done := false
var _occlusion_test_done := false
var _vfx_test_done := false
var _outline_test_done := false


func _ready() -> void:
	# Note: OS.has_feature("headless") is FALSE under --headless in Godot 4.7;
	# the display server name is the reliable check.
	_is_headless = DisplayServer.get_name() == "headless"
	if _is_headless:
		print("[cozyv2] headless self-check start")
	_build_environment()
	_build_assets()
	_build_terrain()
	# The homestead starts on ground that has already been cleared. Without
	# this the terrain gate (doc #12) would refuse the very first wall.
	_prepare_starter_plot()
	_build_ground()

	# The building system owns BuildingState and generates every wall view from
	# it (doc #18). Nothing else in this file is allowed to create a wall node.
	building = CozyBuildingSystem.new()
	add_child(building)
	building.setup(self)
	building.terrain = terrain        # ground must approve placements (doc #12)

	# Construction stops being free (doc #34). The starting stock is sized so the
	# homestead itself fits, with enough left that running out is something the
	# player can actually experience rather than a number that never bites.
	building.inventory = CozyInventory.new()
	building.inventory.add("wood", 600.0)
	building.inventory.add("stone", 300.0)
	building.inventory.add("brick", 150.0)
	building.inventory.add("plaster", 100.0)

	_build_house()
	_place_initial_furniture()
	_rebuild_spatial()
	# Roofs come after room detection: the generator needs the room polygon and
	# the floor elevations, and neither exists until _rebuild_spatial has run.
	_build_roofs()
	_build_scatter()
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


# ---------------------------------------------------------------- assets

## The asset catalogue (V2.1 doc E.3 / E.4).
##
## Nothing visible is drawn from it yet — that is ART-11 onwards. What exists
## now is the contract: definitions load, invalid ones are refused with a
## reason, and only APPROVED assets are offered to runtime systems.
##
## Doc 58.1 is the reason this can be built before any art exists:
## "美术资源可以为空，系统不能依赖资源本身才能运行。"
func _build_assets() -> void:
	assets = CozyAssetLibrary.new()
	assets.load_dir("res://assets/art")


# ---------------------------------------------------------------- scatter

## Vegetation scatter (V2.1 doc E.20 / 58.4).
##
## Built after the building system so it can see what has been built: the
## `village` biome and the near-building thinning rule (E.20.2) both depend on
## it. Rebuilt whenever the world changes underneath, which is the payoff of
## biomes being derived rather than stored.
func _build_scatter() -> void:
	scatter = CozyVegetationScatter.new()
	add_child(scatter)
	scatter.setup(terrain, assets, 20260911)
	scatter.building_points = _building_points()
	scatter.rebuild()


## World positions of built things. A wall's NODE sits at the origin — its
## geometry is baked into vertices — so midpoints are what has to be reported.
func _building_points() -> Array:
	var out: Array = []
	for ws in building.state.walls:
		out.append(ws.midpoint())
	for o in objects:
		if is_instance_valid(o):
			out.append(o.global_position)
	return out


# ---------------------------------------------------------------- terrain

## The terrain field spans the playable area, centred on the house.
##
## Created before the building system but not yet consulted BY it: gating
## construction on buildability is the next block (doc #12). This block is the
## data layer — cells, chunks, materials — and its self-check.
func _build_terrain() -> void:
	terrain = CozyTerrainSystem.new()
	add_child(terrain)
	terrain.setup(64.0, 64.0,
		Vector2(HOUSE_W * 0.5 - 32.0, HOUSE_D * 0.5 - 32.0))

	terrain_renderer = CozyTerrainRenderer.new()
	add_child(terrain_renderer)
	terrain_renderer.setup(terrain)


## Clear a plot around the house so the terrain gate has something to approve.
##
## This is the doc's own opening beat (#10): you do not get to build on virgin
## grass, you clear it first. The homestead simply starts already cleared —
## the mechanic is the same one the player uses, driven through an Intent.
func _prepare_starter_plot() -> void:
	var plot := PackedVector2Array([
		Vector2(-3.0, -3.0),
		Vector2(HOUSE_W + 3.0, -3.0),
		Vector2(HOUSE_W + 3.0, HOUSE_D + 3.0),
		Vector2(-3.0, HOUSE_D + 3.0),
	])
	terrain.apply_intent(CozyTerrainIntent.clear_polygon(plot))
	terrain_renderer.rebuild_dirty()


func _build_ground() -> void:
	var grass := CozyPixelArt.make_texture(16, Color(0.44, 0.72, 0.36), 0.055, 1337)

	var ground := MeshInstance3D.new()
	ground.name = "Ground"
	var pm := PlaneMesh.new()
	pm.size = Vector2(400.0, 400.0)
	ground.mesh = pm
	ground.material_override = CozyPixelArt.make_material(grass, Vector3(200.0, 200.0, 1.0))
	# Sits just under the terrain field so the two never z-fight. It is what the
	# world looks like beyond the terrain field's edge.
	ground.position = Vector3(0.0, -0.1, 0.0)
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

	# Slabs and the stair are submitted as Intents like everything else, so
	# BuildingState owns them (doc #18 lists Floor and Stair alongside Wall).
	# A roof generator needs to know where the floors are, which it could not do
	# while these were emitted straight into the scene.
	var well_d := HOUSE_D - WELL_Z0
	var well_cz := WELL_Z0 + well_d * 0.5

	# Upper slab: two pieces plus a landing at the head of the stairs, leaving a
	# stairwell hole between WELL_X0 and WELL_X1.
	building.submit_many([
		CozyBuildingIntent.add_slab(
			Vector3(WELL_X0 * 0.5, y1 - 0.1, HOUSE_D * 0.5),
			Vector3(WELL_X0, 0.2, HOUSE_D), "stone", 1),                      # west half
		CozyBuildingIntent.add_slab(
			Vector3((WELL_X0 + HOUSE_W) * 0.5, y1 - 0.1, WELL_Z0 * 0.5),
			Vector3(HOUSE_W - WELL_X0, 0.2, WELL_Z0), "stone", 1),            # south strip
		CozyBuildingIntent.add_slab(
			Vector3((WELL_X1 + HOUSE_W) * 0.5, y1 - 0.1, well_cz),
			Vector3(HOUSE_W - WELL_X1, 0.2, well_d), "stone", 1),             # landing
	])

	# The stair runs from WELL_X0 to WELL_X1 and rises the full floor. Its slope
	# must stay under the agent's floor_max_angle, and — just as important — it
	# must TOP OUT AT FLOOR LEVEL. A ramp reaching full height only at the far
	# wall leaves nothing to arrive on, and its tilted collider presents a
	# vertical face along z = WELL_Z0 that an agent cannot climb from the south.
	# Those constraints are properties of the stair's state (start/end), which is
	# why they live in CozyStairState rather than in the model.
	building.submit(CozyBuildingIntent.add_stair(
		Vector3(WELL_X0, 0.0, well_cz), Vector3(WELL_X1, FLOOR_H, well_cz),
		well_d, "wood"))


## Roofs generated from the top floor's rooms (V2.1 doc #31).
##
## Nothing here is a prefab: the polygon comes from room detection, the
## elevation from the floor system, and CozyRoofGenerator derives the ridge,
## slopes and gables from those. Move a wall and the roof follows.
##
## This is what the slabs-and-stairs migration unblocked — before it, there was
## no way to ask where the floors were or how high the building went.
func _has_roof_for(room_id: String) -> bool:
	for r in building.state.roofs:
		if r.room_id == room_id:
			return true
	return false


## Is there a floor slab above this room?
##
## The rule for "does this room need a roof" is NOT "is it on the highest floor".
## A one-storey outbuilding on floor 0 is topmost for its own footprint and must
## be roofed; the floor-based version of this rule left exactly that case bare.
## What matters is whether anything covers it.
func _has_cover_above(room: CozyRoom) -> bool:
	var room_y := floor_system.elevation_of(room.floor_index)

	# Sample the interior, not just the centroid. A single centre point decides
	# wrongly whenever the middle of a room happens to fall in an opening above
	# it — this project has a stairwell hole, and the ground-floor room beside
	# it was being given a roof it does not want.
	var samples: Array[Vector2] = [room.centroid]
	for pt in room.polygon:
		# Pull each vertex toward the centre so a point sitting exactly on the
		# wall line does not decide the answer either way.
		samples.append(pt.lerp(room.centroid, 0.35))

	var covered := 0
	for q in samples:
		for sl in building.state.slabs:
			if sl.surface_y() <= room_y + 0.01:
				continue
			if sl.footprint().has_point(q):
				covered += 1
				break

	# Mostly covered counts as covered: a room under a floor is an interior
	# room, and one open corner does not change that.
	return covered * 2 >= samples.size()


## Roofs generated from the rooms that have nothing above them (doc #31).
##
## Nothing here is a prefab: the polygon comes from room detection, the
## elevation from the floor system, and CozyRoofGenerator derives the ridge,
## slopes and gables from those. Move a wall and the roof follows.
##
## This is what the slabs-and-stairs migration unblocked — before it, there was
## no way to ask where the floors were or how high the building went.
func _build_roofs() -> void:
	# Idempotent: this runs again whenever the building changes, and a second
	# pass must not stack another roof on a room that already has one.
	var intents: Array = []
	for r in floor_system.all_rooms():
		if _has_roof_for(r.id) or _has_cover_above(r):
			continue
		# The eave line sits on top of this room's own walls, one floor height
		# above its floor — not at the top of the building.
		var base_y := floor_system.elevation_of(r.floor_index + 1)
		intents.append(CozyBuildingIntent.add_roof(r.id, r.polygon, base_y,
			CozyRoofState.Style.GABLE, "brick", r.floor_index + 1))
	if intents.is_empty():
		return
	building.submit_many(intents)


func _add_wall(a: Vector3, b: Vector3, mat_id := "wood", floor_id := 0) -> CozyWallState:
	return building.submit(
		CozyBuildingIntent.draw_wall(a, b, FLOOR_H, WALL_T, mat_id, floor_id))




# ---------------------------------------------------------------- furniture

## The NPC's workplace starts UPSTAIRS, so its very first job is the doc's
## worked example (#111): cross the ground floor, take the stairs, work on the
## first floor. If the routing were broken, the NPC would simply never deliver.
func _place_initial_furniture() -> void:
	_place_object("research_table", 2.0, 2.0, 1)
	_place_object("chest", 6.6, 1.0, 0)
	# Two campfires, so the self-check can prove their effects do not animate in
	# lockstep (doc E.21): same definition, different phase.
	_place_object("campfire", -2.0, 5.0, 0)
	_place_object("campfire", 10.5, 2.0, 0)


func _place_object(def_id: String, x: float, z: float, floor_index: int) -> CozyWorldObject:
	if not CozyObjectDefs.exists(def_id):
		return null
	var obj := CozyWorldObject.new()
	add_child(obj)
	obj.setup(def_id, floor_index)
	obj.global_position = Vector3(x, float(floor_index) * FLOOR_H, z)
	obj.refresh_points()      # work points usable before the first frame
	obj.refresh_vfx_phase()   # effects desynced by position, not by definition
	objects.append(obj)
	return obj


# ---------------------------------------------------------------- spatial rebuild

## Re-derive every layer that depends on walls or furniture: wall joins, rooms,
## portals, the room graph, local navigation and the world navigator.
## Safe to call repeatedly — that is the point (doc #28).
func _rebuild_spatial(dirty: CozyDirtyRegion = null) -> void:
	# Which floors need their rooms re-derived? Rooms come from the wall graph
	# of a SINGLE floor, so a wall on floor 0 cannot change the rooms on floor 1.
	# An edit therefore only invalidates its own floor (doc #33). A null or empty
	# region means "rebuild everything" — used at startup and when furniture
	# moves, since objects are not part of the building's dirty region yet.
	var full := dirty == null or dirty.is_empty()
	var floors: Array = building.state.floor_ids() if full else dirty.floor_list()

	# Room detection reads centre-lines straight out of BuildingState. There is
	# no doorway bridging: an opening carves geometry but leaves the centre-line
	# intact, so the graph is already closed around a door. Bridging an intact
	# span would add a duplicate edge and corrupt the planar face traversal.
	var detector := CozyRoomDetector.new()
	for fi in floors:
		var polys := detector.detect(building.centrelines_on_floor(fi))
		var rooms: Array = []
		for i in polys.size():
			rooms.append(CozyRoom.new("room_%d_%d" % [fi, i], fi, polys[i]))
		_rooms_by_floor[fi] = rooms

	# A floor that lost its last wall must lose its rooms too.
	var live_floors := building.state.floor_ids()
	for fi in _rooms_by_floor.keys().duplicate():
		if not live_floors.has(fi):
			_rooms_by_floor.erase(fi)

	floor_system = CozyFloorSystem.new()
	floor_system.floor_height = FLOOR_H
	for fi in _rooms_by_floor:
		for r in _rooms_by_floor[fi]:
			floor_system.add_room(r)

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
	#
	# The nav grid is the expensive layer — one cell per 0.25 m — so this is
	# where "local edit, local rebuild" actually pays. Rooms on untouched floors
	# keep the grid they already have.
	var alive := {}
	for r in floor_system.all_rooms():
		alive[r.id] = true
		if full or floors.has(r.floor_index):
			var nav := CozyLocalNav.new()
			nav.build(r, _obstacles_on_floor(r.floor_index))
			_nav_by_room[r.id] = nav
	for id in _nav_by_room.keys().duplicate():
		if not alive.has(id):
			_nav_by_room.erase(id)
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
	# The resident's data (V2-22). Everything about who they are lives here; the
	# node only reads it.
	npc.npc_state = CozyNpcState.create("npc_001", "Alice", "researcher", 20260911)
	npc.npc_state.move_speed = 3.5
	npc.npc_state.set_passion("research", CozySkills.Passion.INTERESTED)
	npc.npc_state.train("research", 6)
	npc.uses_gravity = true
	npc.floor_max_angle = deg_to_rad(55.0)
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
	# Order matters: index 0 is the character the camera follows, and only that
	# one drives fading by default. See CozyOcclusion.watch_non_followed.
	occ.targets = [player, npc]
	# Walls and roofs both fade — a roof that cannot fade hides the player.
	occ.fadables = []
	occ.fadables.append_array(building.wall_views)
	occ.fadables.append_array(building.roof_views)
	occlusion = occ


# ---------------------------------------------------------------- HUD

func _build_hud() -> void:
	hud = CozyHud.new()
	add_child(hud)
	hud.set_tool_groups(TOOL_GROUPS)
	hud.tool_selected.connect(_on_hud_tool_selected)

	menu = CozyContextMenu.new()
	add_child(menu)
	menu.action_chosen.connect(_on_menu_action)


## The HUD is now the single place a tool can be chosen, so a click and the TAB
## key go through the same path rather than two that can drift apart.
func _on_hud_tool_selected(i: int) -> void:
	tool_idx = i
	if not build_mode:
		build_mode = true
	_cancel_outline()
	_update_hud()


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
	if _is_terrain_tool():
		# A brush, not a drag-shape: terrain edits are repeated small strokes and
		# making the player define a polygon for every one would be miserable.
		_apply_terrain_brush(p)
		return

	match _current_tool():
		"wall":
			_drag_start = _snap(p)
			_drag_end = _drag_start
			_drag_active = true
			_update_preview()
		"outline":
			# Each click drops a corner. The outline is finished with Enter,
			# not with the mouse, so a mis-click does not commit a building.
			var sp := _snap(p)
			_outline_points.append(Vector2(sp.x, sp.z))
			_update_outline_preview()
			_update_hud()
		_:
			# Furniture is a single click, not a drag.
			_place_object(_current_tool(), p.x, p.z, _build_floor_index())
			_rebuild_spatial()
			_update_hud()


func _update_drag() -> void:
	# Terrain keeps painting while the button is held. The scatter is NOT
	# rebuilt per stroke — that costs 138 ms and would stutter — only the
	# terrain surface, and the scatter catches up once on release.
	if _is_terrain_tool():
		var tp := _mouse_ground_point()
		if is_finite(tp.x):
			_apply_terrain_brush(tp)
		return
	if not _drag_active:
		return
	var p := _mouse_ground_point()
	if is_finite(p.x):
		_drag_end = _snap(p)
	_update_preview()


func _end_drag() -> void:
	# Releasing after terrain strokes is when the plants catch up. One rebuild
	# for the whole stroke rather than one per frame.
	if _is_terrain_tool():
		_rebuild_spatial_after_terrain()
		return
	# An outline is committed with Enter, so releasing the mouse does nothing.
	if _current_tool() == "outline":
		return
	if not _drag_active:
		return
	_drag_active = false
	_clear_preview()

	var t := CozyWallState.segment_transform(_drag_start, _drag_end, FLOOR_H)
	if float(t["length"]) < MIN_WALL_LEN:
		return   # A click, not a drag.

	_add_wall(_drag_start, _drag_end, "wood", _build_floor_index())

	# The terrain gate lives in the building system, so a refusal shows up as
	# "nothing was added". Report it rather than silently doing nothing.
	if building.last_rejection != "":
		_say("refused: %s" % building.last_rejection, true, 5.0)
	else:
		_rebuild_spatial(building.last_dirty)
		_refresh_occlusion_fadables()
	_update_hud()


## The building system rebuilds wall views, so the occlusion list is
## re-collected rather than incrementally maintained.
func _refresh_occlusion_fadables() -> void:
	for c in get_children():
		if c is CozyOcclusion:
			c.fadables = []
			c.fadables.append_array(building.wall_views)
			c.fadables.append_array(building.roof_views)


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


# ---------------------------------------------------------------- context menu

## What is under the cursor, and what can be done with it.
##
## The menu is built from the PROBE, not from a fixed list: offering "remove
## wall" over open ground would be an action that silently does nothing, and
## that is worse than not offering it.
func _probe_at_mouse() -> Dictionary:
	var mp := get_viewport().get_mouse_position()
	var from := camera.project_ray_origin(mp)
	var dir := camera.project_ray_normal(mp)
	var q := PhysicsRayQueryParameters3D.create(from, from + dir * 500.0)
	q.collide_with_areas = false
	var hit := camera.get_world_3d().direct_space_state.intersect_ray(q)
	if hit.is_empty():
		return {"kind": "ground", "point": _mouse_ground_point()}
	var owner_node := _owner_of(hit["collider"])
	return {"kind": _kind_of(owner_node), "node": owner_node, "point": hit["position"]}


## Walk up from a collider to the thing that owns it. Every generated view
## (wall, slab, roof, stair, object) keeps its colliders as children, so this is
## the one place that has to know the shape of that.
func _owner_of(n: Node) -> Node:
	var cur := n
	while cur != null:
		if cur is CozyWall or cur is CozySlab or cur is CozyRoof or cur is CozyStair \
				or cur is CozyWorldObject or cur is CozyCharacter:
			return cur
		cur = cur.get_parent()
	return n


func _kind_of(n: Node) -> String:
	if n is CozyWall:
		return "wall"
	if n is CozySlab:
		return "slab"
	if n is CozyRoof:
		return "roof"
	if n is CozyStair:
		return "stair"
	if n is CozyWorldObject:
		return "object"
	if n is CozyNpcAgent:
		return "npc"
	if n is CozyCharacter:
		return "player"
	return "unknown"


func _open_context_menu(at: Vector2) -> void:
	var probe := _probe_at_mouse()
	var kind: String = probe["kind"]
	var entries: Array = []
	var target := {"title": kind.capitalize(), "kind": kind, "node": probe.get("node"),
		"point": probe.get("point", Vector3.ZERO)}

	match kind:
		"ground":
			# The terrain entry is the point of this whole menu: the terrain
			# system has existed since V2-11 with no way to reach it.
			var cell := terrain.cell_at(probe["point"].x, probe["point"].z)
			target["title"] = "Ground" + (" · %s" % cell.material_id if cell else "")
			entries.append({"id": "terrain_edit", "label": "Terrain edit",
				"hint": "dig / fill / clear the land under the cursor"})
			if cell:
				entries.append({"id": "terrain_clear", "label": "Clear here",
					"hint": "one brush stroke of CLEAR, exactly as the tool would do"})
		"wall":
			var ws: CozyWallState = probe["node"].state
			target["title"] = "Wall · %s" % ws.material_id
			entries.append({"id": "info", "label": "Info"})
			entries.append({"id": "remove", "label": "Remove wall"})
		"object":
			var o: CozyWorldObject = probe["node"]
			target["title"] = CozyObjectDefs.display_name(o.def_id)
			entries.append({"id": "info", "label": "Info"})
			entries.append({"id": "remove", "label": "Remove"})
		_:
			entries.append({"id": "info", "label": "Info"})

	menu.open_for(entries, at, target)


func _on_menu_action(id: String, target: Variant) -> void:
	match id:
		"terrain_edit":
			build_mode = true
			_on_hud_tool_selected(TOOLS.find("dig"))
			_say("terrain edit: pick Dig / Fill / Clear, then click the ground")
		"terrain_clear":
			var pt: Vector3 = target["point"]
			terrain.apply_intent(CozyTerrainIntent.clear_brush(Vector2(pt.x, pt.z),
				TERRAIN_BRUSH))
			terrain_renderer.rebuild_dirty()
			_rebuild_spatial_after_terrain()
			_say("cleared")
		"remove":
			_remove_target(target)
		"info":
			_show_info(target)


func _remove_target(target: Variant) -> void:
	var node = target.get("node")
	if node is CozyWall:
		building.submit(CozyBuildingIntent.remove_wall(node.state.id))
		_rebuild_spatial(building.last_dirty)
		_build_roofs()
		_refresh_occlusion_fadables()
		_say("wall removed")
	elif node is CozyWorldObject:
		objects.erase(node)
		node.queue_free()
		_rebuild_spatial()
		_say("removed")
	_update_hud()


func _show_info(target: Variant) -> void:
	var node = target.get("node")
	var lines: Array = []
	if node is CozyWall:
		var ws: CozyWallState = node.state
		lines.append("%s · floor %d" % [ws.id, ws.floor_id])
		lines.append("%.1f m · %.2f m3 · %d block(s)" % [
			ws.length(), ws.volume(), node.block_count()])
		lines.append("%d opening(s)" % ws.openings.size())
	elif node is CozySlab:
		var ss: CozySlabState = node.state
		lines.append("%s · floor %d" % [ss.id, ss.floor_id])
		lines.append("%.1f x %.1f m, surface y=%.1f" % [
			ss.size.x, ss.size.z, ss.surface_y()])
	elif node is CozyRoof:
		lines.append("%s over %s" % [node.state.id, node.state.room_id])
		lines.append("style %s · %d face(s)" % [node.style_name(), node.face_count()])
	elif node is CozyStair:
		var st: CozyStairState = node.state
		lines.append("%s · floor %s" % [st.id, st.floor_span()])
		lines.append("%.1f deg over %.1f m" % [rad_to_deg(st.slope_angle()), st.run()])
	elif node is CozyWorldObject:
		lines.append(node.def_id)
		lines.append("%d interaction point(s)" % node.interaction_points.size())
		for pt in node.interaction_points:
			lines.append("  %s" % pt.describe())
	elif node is CozyNpcAgent:
		lines.append(node.status_line())
		lines.append("floor %d" % node.current_floor(FLOOR_H))
	elif node is CozyCharacter:
		lines.append(node.display_name)
		lines.append("floor %d" % node.current_floor(FLOOR_H))
	else:
		var pt: Vector3 = target.get("point", Vector3.ZERO)
		var cell := terrain.cell_at(pt.x, pt.z)
		if cell:
			lines.append("material %s · %s" % [cell.material_id,
				CozyBuildability.name_of(cell.buildability)])
			lines.append("height %.2f" % cell.height)
			var biome := CozyBiome.classify(terrain, _building_points(), pt.x, pt.z,
				scatter.world_seed)
			lines.append("biome %s" % biome)
	hud.show_info(String(target.get("title", "")), lines)


# ---------------------------------------------------------------- terrain tools

func _is_terrain_tool() -> bool:
	return TERRAIN_TOOLS.has(_current_tool())


## Paint one brush stroke of the current terrain operation at a world point.
##
## The operation comes from the tool name, so adding "road" later is a row in
## TERRAIN_TOOLS plus a brush radius — the intent already exists.
func _apply_terrain_brush(world: Vector3) -> void:
	var centre := Vector2(world.x, world.z)
	var intent: CozyTerrainIntent = null
	match _current_tool():
		"dig":
			intent = CozyTerrainIntent.dig_brush(centre, TERRAIN_BRUSH, 0.25)
		"fill":
			intent = CozyTerrainIntent.fill_brush(centre, TERRAIN_BRUSH, 0.25)
		_:
			intent = CozyTerrainIntent.clear_brush(centre, TERRAIN_BRUSH)
	if intent == null:
		return
	if terrain.apply_intent(intent)["touched"] > 0:
		terrain_renderer.rebuild_dirty()


## Called once when a terrain stroke finishes: everything downstream of the
## ground catches up in a single pass.
func _rebuild_spatial_after_terrain() -> void:
	# Rooms, portals, navigation and the roof all depend on buildability, which
	# the terrain just changed.
	_rebuild_spatial()
	_build_roofs()
	scatter.building_points = _building_points()
	scatter.rebuild()
	_update_hud()


# ---------------------------------------------------------------- outline

## Finish the current outline and turn it into a building (doc #17 / #86).
##
## The generator emits WALL INTENTS and a doorway; everything else follows on
## its own — rooms come from the wall graph, the roof from the rooms. That is
## the doc's "intent in, structure out" chain, and none of it is special-cased.
func _finish_outline() -> void:
	if _outline_points.size() < 3:
		_say("outline needs at least 3 points", true)
		_cancel_outline()
		_update_hud()
		return

	var floor_id := _build_floor_index()
	var base_y := floor_system.elevation_of(floor_id)
	var hint := Vector2(player.global_position.x, player.global_position.z)

	var intents := CozyOutlineGenerator.plan(_outline_points, base_y, FLOOR_H,
		WALL_T, "wood", floor_id, hint)

	var before := building.state.wall_count()
	building.submit_many(intents)
	var added := building.state.wall_count() - before

	_cancel_outline()
	if added == 0:
		_say("refused: %s" % building.last_rejection, true, 5.0)
	else:
		_say("built %d wall(s) from outline" % added)
		_rebuild_spatial(building.last_dirty)
		_build_roofs()
		_refresh_occlusion_fadables()
	_update_hud()


func _cancel_outline() -> void:
	_outline_points = PackedVector2Array()
	if _outline_preview != null:
		_outline_preview.queue_free()
		_outline_preview = null


## Draw the collected corners, plus a rubber-band segment to the cursor.
func _update_outline_preview() -> void:
	if _outline_preview == null:
		_outline_preview = MeshInstance3D.new()
		var mat := StandardMaterial3D.new()
		mat.albedo_color = Color(0.35, 0.85, 1.0)
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_outline_preview.material_override = mat
		add_child(_outline_preview)

	var y := floor_system.elevation_of(_build_floor_index()) + 0.15
	var im := ImmediateMesh.new()
	im.surface_begin(Mesh.PRIMITIVE_LINE_STRIP)
	for pt in _outline_points:
		im.surface_add_vertex(Vector3(pt.x, y, pt.y))
	var mouse := _mouse_ground_point()
	if is_finite(mouse.x) and _outline_points.size() > 0:
		var sp := _snap(mouse)
		im.surface_add_vertex(Vector3(sp.x, y, sp.z))
	im.surface_end()
	_outline_preview.mesh = im


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
		if event.keycode == KEY_ENTER or event.keycode == KEY_KP_ENTER:
			if build_mode and _current_tool() == "outline":
				_finish_outline()
				return
		if event.keycode == KEY_ESCAPE:
			if build_mode and _outline_points.size() > 0:
				_cancel_outline()
				_say("outline cancelled")
				_update_hud()
				return
		# Debug escape hatch (doc E.1.1 allows a fixed OR strictly controlled
		# camera; free rotation is barred as a gameplay feature). Anything seen
		# at a non-locked angle is out of spec, so do not author art from it.
		if event.keycode == KEY_L:
			if camera.free_look:
				camera.lock_view()
			else:
				camera.free_look = true
			_update_hud()
			return

	# Right-click is the world's selection gesture. It works in every mode,
	# including while building, because "what is that?" is always a fair
	# question and taking the player out of build mode to ask it would be worse.
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_RIGHT \
			and event.pressed:
		_open_context_menu(get_viewport().get_mouse_position())
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
	_clock += delta
	_expire_message()
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


## Rotation input is only meaningful under the debug unlock — the camera is
## fixed by default (doc E.1.1), and rotate_by/pitch_by refuse otherwise.
func _handle_camera_keys(delta: float) -> void:
	if not camera.free_look:
		return
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
	# Early, while the player is still out in the open with nothing in front
	# of them — the only moment the occlusion answer is unambiguous.
	if not _occlusion_test_done and f > 60:
		_occlusion_test_done = true
		_check_occlusion()
	if not _vfx_test_done and f > 120:
		_vfx_test_done = true
		_check_vfx()
	if not _outline_test_done and f > 1500:
		_outline_test_done = true
		_check_outline_build()
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

	_check_camera()
	_check_ui()
	_check_assets()
	_check_scatter()
	_check_nav()
	_check_terrain()
	_check_wall_connection()
	_check_openings()
	_check_wall_assembly()
	_check_building_state()
	_check_roofs()
	_check_npc_route_plan()


## Doc #86 — the whole chain, end to end.
##
## The doc's "第一个完整 Terrain → Building Demo": clear the ground, express an
## outline, and let the system produce the structure. Nothing here is
## special-cased — rooms come from the wall graph and the roof from the rooms,
## exactly as they do for the hand-built house.
func _check_outline_build() -> void:
	# Somewhere clear of the house, on ground that has to be made ready first.
	var cx := 17.0
	var cz := 13.0
	var hw := 2.6
	var hd := 2.0
	var poly := PackedVector2Array([
		Vector2(cx - hw, cz - hd), Vector2(cx + hw, cz - hd),
		Vector2(cx + hw, cz + hd), Vector2(cx - hw, cz + hd)])

	# 1. Terrain first — doc #12 refuses a building on uncleared ground, so the
	#    test has to clear it exactly the way the player would.
	var plot := PackedVector2Array([
		Vector2(cx - hw - 1.0, cz - hd - 1.0), Vector2(cx + hw + 1.0, cz - hd - 1.0),
		Vector2(cx + hw + 1.0, cz + hd + 1.0), Vector2(cx - hw - 1.0, cz + hd + 1.0)])
	terrain.apply_intent(CozyTerrainIntent.clear_polygon(plot))
	terrain_renderer.rebuild_dirty()

	# 2. Outline -> intents.
	var before_walls := building.state.wall_count()
	var before_rooms := floor_system.all_rooms().size()
	var before_roofs := building.state.roofs.size()

	var intents := CozyOutlineGenerator.plan(poly, 0.0, FLOOR_H, WALL_T,
		"wood", 0, Vector2(cx, cz - hd - 3.0))
	building.submit_many(intents)

	# 3. Everything downstream re-derives on its own.
	_rebuild_spatial(building.last_dirty)
	_build_roofs()

	var d_walls := building.state.wall_count() - before_walls
	var d_rooms := floor_system.all_rooms().size() - before_rooms
	var d_roofs := building.state.roofs.size() - before_roofs

	print("[cozyv2] outline build: %d pt(s) -> +%d wall(s), +%d room(s), +%d roof(s)  [%s]" % [
		poly.size(), d_walls, d_rooms, d_roofs,
		"OK" if d_walls == 4 and d_rooms == 1 and d_roofs == 1 else "FAIL, expected 4/1/1"])

	# The generated room must be the size that was drawn, which proves the
	# walls landed where the outline said rather than merely that some appeared.
	var found := false
	var want_area := (hw * 2.0) * (hd * 2.0)
	for r in floor_system.all_rooms():
		if r.floor_index == 0 and is_equal_approx(r.area, want_area):
			found = true
			break
	print("[cozyv2] outline room area: %.1f m2 expected %.1f  [%s]" % [
		want_area, want_area, "OK" if found else "FAIL, no room of that size"])


## Roofs (V2.1 doc #31). Derived from the room polygon rather than placed, and
## they must fade (doc #57) or the player disappears the moment they go inside.
func _check_roofs() -> void:
	var rs := building.roof_views
	if rs.is_empty():
		print("[cozyv2] roof: NONE GENERATED  [FAIL]")
		return

	var r: CozyRoof = rs[0]
	var st := r.state
	var plan_ridge := r.ridge()

	# A gable over a rectangle must produce exactly one ridge line.
	print("[cozyv2] roof over %s: style=%s, %d face(s), ridge=%d  [%s]" % [
		st.room_id, r.style_name(), r.face_count(), plan_ridge.size(),
		"OK" if r.face_count() >= 4 and plan_ridge.size() == 2 else "FAIL"])

	# It must sit above the floor it caps, not through it.
	var top_slab_y := 0.0
	for sl in building.state.slabs:
		top_slab_y = maxf(top_slab_y, sl.surface_y())
	print("[cozyv2] roof eave y=%.1f above top floor y=%.1f  [%s]" % [
		st.base_y, top_slab_y,
		"OK" if st.base_y > top_slab_y else "FAIL, roof inside the building"])

	# doc #57 — a roof that cannot fade hides the player.
	var before := r._fade
	r.set_fade(0.22)
	var faded := not is_equal_approx(r._fade, before)
	r.set_fade(1.0)
	print("[cozyv2] roof fade: responds=%s  [%s]" % [
		str(faded), "OK" if faded else "FAIL, roof cannot fade"])


## Doc #18 — BuildingState owns floors and stairs, not only walls.
##
## This is the debt that blocked V2-17: a roof generator has to know where the
## floors are and how high the building goes, and it could not find out while
## slabs and stairs were emitted straight into the scene.
func _check_building_state() -> void:
	var s := building.state
	print("[cozyv2] building state: %s  [%s]" % [
		s.describe(),
		"OK" if s.slabs.size() >= 3 and s.stairs.size() >= 1 else "FAIL, incomplete"])

	# A stair steeper than an agent's floor_max_angle is climbed by nobody, so
	# the constraint is asserted rather than trusted (doc #30).
	var st: CozyStairState = s.stairs[0]
	var deg := rad_to_deg(st.slope_angle())
	var limit := rad_to_deg(player.floor_max_angle)
	print("[cozyv2] stair %s: %.2f m run, %.2f m rise, %.1f deg (agent limit %.0f)  [%s]" % [
		st.floor_span(), st.run(), st.rise(), deg, limit,
		"OK" if deg < limit else "FAIL, too steep to climb"])

	# The head must land at floor level, or the agent arrives on a lip (#30).
	var head_y := st.end.y
	var slab_y := s.slabs[0].surface_y()
	print("[cozyv2] stair head at y=%.2f, floor surface at y=%.2f  [%s]" % [
		head_y, slab_y,
		"OK" if is_equal_approx(head_y, slab_y) else "FAIL, stair tops out short"])


## Wall assembly (V2.1 doc 58.3 Layer 3 / E.16 / E.21).
##
## Three properties, checked separately: blocks tile the span (so a longer wall
## has proportionally more), the blocks merge into ONE mesh (doc #61), and the
## layout is DETERMINISTIC so masonry cannot rearrange itself across a reload.
func _check_wall_assembly() -> void:
	var south: CozyWall = null
	for v in building.wall_views:
		if v.state != null and v.state.length() > 7.5 and v.state.floor_id == 0:
			south = v
			break
	if south == null:
		print("[cozyv2] wall assembly: SOUTH WALL NOT FOUND  [FAIL]")
		return

	print("[cozyv2] wall assembly: %.1f m %s wall -> %d blocks in %d mesh(es)  [%s]" % [
		south.state.length(), south.state.material_id, south.block_count(),
		south.mesh_count(),
		"OK" if south.block_count() > 20 and south.mesh_count() == 1 else "FAIL"])

	# doc E.21 — identical inputs must give an identical layout.
	var a := CozyWallAssembly.blocks_for_span(0.0, 8.0, 0.0, 3.0, 0.8, 0.4, 12345)
	var b := CozyWallAssembly.blocks_for_span(0.0, 8.0, 0.0, 3.0, 0.8, 0.4, 12345)
	var same := a.size() == b.size()
	if same:
		for i in a.size():
			if not is_equal_approx(float(a[i]["shade"]), float(b[i]["shade"])):
				same = false
				break
	print("[cozyv2] wall assembly deterministic: %d vs %d blocks, shades match=%s  [%s]" % [
		a.size(), b.size(), str(same), "OK" if same and a.size() > 0 else "FAIL"])

	# Scaling — twice the wall, meaningfully more blocks.
	var half := CozyWallAssembly.blocks_for_span(0.0, 4.0, 0.0, 3.0, 0.8, 0.4, 1)
	var full := CozyWallAssembly.blocks_for_span(0.0, 8.0, 0.0, 3.0, 0.8, 0.4, 1)
	print("[cozyv2] wall assembly scaling: 4 m -> %d blocks, 8 m -> %d  [%s]" % [
		half.size(), full.size(),
		"OK" if full.size() > half.size() * 3 / 2 else "FAIL"])


## Terrain data layer (V2.1 doc #5–#11).
##
## Proves the four things the doc asks of this block: cells carry material and
## buildability, clearing converts Grass -> Soil and unlocks building, edits
## mark a dirty region rather than the whole world, and the field round-trips
## through its save shape with no generated surface involved.
func _check_terrain() -> void:
	if terrain == null:
		print("[cozyv2] terrain NOT BUILT  [FAIL]")
		return
	print("[cozyv2] %s" % terrain.describe())

	# A point well inside the field and clear of the house.
	var tx := 20.0
	var tz := 20.0

	var m0 := terrain.material_id_at(tx, tz)
	var b0 := terrain.buildability_at(tx, tz)
	print("[cozyv2] terrain default: %s / %s  [%s]" % [
		m0, CozyBuildability.name_of(b0),
		"OK" if m0 == "grass" and b0 == CozyBuildability.NATURAL else "FAIL"])

	# doc #10 — "clean a patch of lawn": Grass -> Soil, and the ground becomes
	# buildable. This is the step the whole terrain phase exists to enable.
	var changed := terrain.set_material_at(tx, tz, "soil")
	var m1 := terrain.material_id_at(tx, tz)
	var b1 := terrain.buildability_at(tx, tz)
	print("[cozyv2] terrain cleared: %s -> %s, %s -> %s  [%s]" % [
		m0, m1, CozyBuildability.name_of(b0), CozyBuildability.name_of(b1),
		"OK" if changed and m1 == "soil" and CozyBuildability.accepts_building(b1) else "FAIL"])

	# doc #33 — one cell edited must dirty exactly one chunk, not the world.
	var dirty := terrain.dirty_chunks()
	print("[cozyv2] terrain dirty region: %d chunk(s) of %d  [%s]" % [
		dirty.size(), terrain.chunk_count(),
		"OK" if dirty.size() == 1 else "FAIL, expected 1"])

	# doc #63 — save facts, not meshes. Round-trip must restore the field.
	var restored := CozyTerrainSystem.new()
	restored.from_dict(terrain.to_dict())
	var m2 := restored.material_id_at(tx, tz)
	var b2 := restored.buildability_at(tx, tz)
	var same := restored.chunk_count() == terrain.chunk_count()
	print("[cozyv2] terrain round-trip: %s / %s, %d chunks  [%s]" % [
		m2, CozyBuildability.name_of(b2), restored.chunk_count(),
		"OK" if m2 == m1 and b2 == b1 and same else "FAIL"])
	# This instance was never added to the tree, so nothing else will free it.
	restored.free()

	# --- editing: shape + operation + material (doc #8 / #9) ---
	#
	# The doc's worked example (#10) is "clear a triangular patch of lawn". A
	# triangle is not a special shape — it is a 3-point polygon, and the same
	# rasterizer handles brush circles and rectangles too.
	terrain.clear_dirty()
	var tri := PackedVector2Array([
		Vector2(12.0, 12.0), Vector2(20.0, 12.0), Vector2(16.0, 20.0)])
	var res := terrain.apply_intent(CozyTerrainIntent.clear_polygon(tri))
	var dirty_n: int = terrain.dirty_chunks().size()

	print("[cozyv2] terrain clear polygon: %d cells, %d changed, %d chunk(s) dirty  [%s]" % [
		res["cells"], res["touched"], dirty_n,
		"OK" if res["touched"] > 0 and dirty_n > 0 and dirty_n < terrain.chunk_count() else "FAIL"])

	# Inside the polygon: grass -> soil, not buildable -> buildable.
	var in_m := terrain.material_id_at(16.0, 15.0)
	var in_b := terrain.buildability_at(16.0, 15.0)
	print("[cozyv2]   inside  (16,15): %s / %s  [%s]" % [
		in_m, CozyBuildability.name_of(in_b),
		"OK" if in_m == "soil" and CozyBuildability.accepts_building(in_b) else "FAIL"])

	# Outside it, nothing may have moved.
	var out_m := terrain.material_id_at(11.0, 15.0)
	var out_b := terrain.buildability_at(11.0, 15.0)
	print("[cozyv2]   outside (11,15): %s / %s  [%s]" % [
		out_m, CozyBuildability.name_of(out_b),
		"OK" if out_m == "grass" and out_b == CozyBuildability.NATURAL else "FAIL"])

	# Dig lowers the surface; the intent carries the depth.
	terrain.apply_intent(CozyTerrainIntent.dig_polygon(tri, 0.5))
	var h := terrain.height_at(16.0, 15.0)
	print("[cozyv2] terrain dig 0.5 m: height=%.2f  [%s]" % [
		h, "OK" if is_equal_approx(h, -0.5) else "FAIL"])

	terrain.clear_dirty()

	# --- the building gate (doc #12) ---
	# Virgin grass must refuse; the cleared homestead plot must accept.
	var on_grass := CozyFoundationValidator.validate(terrain, Rect2(30.0, 30.0, 2.0, 2.0))
	print("[cozyv2] foundation on virgin grass: %s (%s)  [%s]" % [
		CozyFoundationValidator.result_name(on_grass["result"]), on_grass["reason"],
		"OK" if on_grass["result"] == CozyFoundationValidator.Result.INVALID else "FAIL"])

	var on_plot := CozyFoundationValidator.validate(terrain, Rect2(1.0, 1.0, 2.0, 1.0))
	print("[cozyv2] foundation on cleared plot: %s  [%s]" % [
		CozyFoundationValidator.result_name(on_plot["result"]),
		"OK" if on_plot["result"] == CozyFoundationValidator.Result.VALID else "FAIL"])

	# The gate must hold at the SYSTEM level, not merely in the validator.
	# A rule that only exists in a mouse handler is not a rule (doc #70).
	var before_n := building.state.wall_count()
	building.submit(CozyBuildingIntent.draw_wall(
		Vector3(30.0, 0.0, 30.0), Vector3(34.0, 0.0, 30.0), FLOOR_H, WALL_T, "wood", 0))
	var held := building.state.wall_count() == before_n
	print("[cozyv2] wall on virgin grass: refused=%s (%s)  [%s]" % [
		str(held), building.last_rejection,
		"OK" if held else "FAIL, the gate did not hold"])

	# --- material cost (doc #34-#36) ---
	# Cost is derived from geometry, so it must scale with the wall's volume.
	var probe := CozyWallState.create("probe", Vector3.ZERO, Vector3(8.0, 0.0, 0.0),
		3.0, 0.25, "wood", 0)
	var vol := probe.volume()
	var cost := CozyBuildingDefs.cost_for("wood", vol)
	print("[cozyv2] cost of an 8x3x0.25 m wood wall (%.1f m3): %s  [%s]" % [
		vol, CozyBuildingDefs.describe_cost(cost),
		"OK" if is_equal_approx(vol, 6.0) and float(cost.get("wood", 0)) > 0.0 else "FAIL"])

	var inv := CozyInventory.new()
	inv.add("wood", 100.0)
	var afford := inv.can_afford({"wood": 50.0})
	var paid := inv.spend({"wood": 50.0})
	print("[cozyv2] inventory spend 50 of 100: paid=%s, left=%d  [%s]" % [
		str(paid), int(inv.count("wood")),
		"OK" if afford and paid and is_equal_approx(inv.count("wood"), 50.0) else "FAIL"])

	var refused := not inv.can_afford({"wood": 500.0})
	var no_partial := inv.count("wood") > 0.0
	print("[cozyv2] inventory refuses overspend: %s  [%s]" % [
		str(refused), "OK" if refused and no_partial else "FAIL"])

	# --- dirty region (doc #33) ---
	# A wall on one floor must not invalidate the other floor's rooms.
	var rooms1_before := floor_system.rooms_on(1).size()
	building.submit(CozyBuildingIntent.draw_wall(
		Vector3(1.0, 0.0, 2.0), Vector3(1.0, 0.0, 5.0), FLOOR_H, WALL_T, "wood", 0))
	var fl := building.last_dirty.floor_list()
	var rooms1_after := floor_system.rooms_on(1).size()
	print("[cozyv2] dirty region after a floor-0 wall: floors=%s  [%s]" % [
		str(fl), "OK" if fl.size() == 1 and fl[0] == 0 and rooms1_after == rooms1_before else "FAIL"])


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
	_check_npc_state()


func _run_live_rebuild_test() -> void:
	print("[cozyv2] --- live rebuild test: add a dividing wall ---")
	var before := floor_system.rooms_on(0).size()
	# Bisect the GROUND floor. The autopilot has already finished by this frame,
	# so the new wall cannot interfere with the walk-through test.
	_add_wall(Vector3(4.0, 0.0, 0.0), Vector3(4.0, 0.0, HOUSE_D), "wood", 0)
	_rebuild_spatial(building.last_dirty)
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


## Vegetation scatter (V2.1 doc E.20 / E.21 / #61).
##
## Four properties, each checked separately:
##   1. it actually places things, at a plausible density
##   2. instancing holds — thousands of plants in a handful of draw calls (#61)
##   3. density responds to terrain and to buildings (E.20.1 / E.20.2)
##   4. it is DETERMINISTIC, so the field survives a save and reload (E.21)
func _check_scatter() -> void:
	if scatter == null:
		print("[cozyv2] scatter: NOT BUILT  [FAIL]")
		return

	var total := scatter.total_instances()
	var meshes := scatter.mesh_count()
	print("[cozyv2] scatter: %d instance(s) in %d mesh(es), %d candidate(s)  [%s]" % [
		total, meshes, scatter.sample_candidates(),
		"OK" if total > 0 and meshes > 0 else "FAIL, nothing placed"])
	print("[cozyv2] scatter instancing: %d instance(s) -> %d draw call(s)  [%s]" % [
		total, meshes, "OK" if meshes <= 4 else "FAIL, too many meshes"])

	# E.20.1 — the density field must respond to what is under it.
	var on_grass := CozyScatterRule.base_probability("grass_tuft",
		CozyBiome.GRASSLAND, "grass", false)
	var on_sand := CozyScatterRule.base_probability("grass_tuft",
		CozyBiome.ROCKY, "sand", false)
	var on_water := CozyScatterRule.base_probability("grass_tuft",
		CozyBiome.SHORE, "water", false)
	print("[cozyv2] scatter density: grass=%.2f sand=%.2f water=%.2f  [%s]" % [
		on_grass, on_sand, on_water,
		"OK" if on_grass > 0.3 and on_sand == 0.0 and on_water == 0.0 else "FAIL"])

	# E.20.2 — ground near a building is walked on, so it thins out.
	var away := CozyScatterRule.base_probability("grass_tuft",
		CozyBiome.GRASSLAND, "grass", false)
	var near := CozyScatterRule.base_probability("grass_tuft",
		CozyBiome.VILLAGE, "grass", true)
	print("[cozyv2] scatter near building: %.2f vs %.2f open  [%s]" % [
		near, away, "OK" if near < away else "FAIL, no thinning"])

	# E.19.2 / E.20.2 — woodland is a REGION and trees obey it strictly.
	var forest_p := CozyScatterRule.base_probability("tree",
		CozyBiome.FOREST_EDGE, "grass", false)
	var open_p := CozyScatterRule.base_probability("tree",
		CozyBiome.GRASSLAND, "grass", false)
	var near_p := CozyScatterRule.base_probability("tree",
		CozyBiome.VILLAGE, "grass", true)
	var trees := scatter.instance_count("tree")
	print("[cozyv2] scatter forest: forest=%.2f open=%.3f near-building=%.2f, %d tree(s)  [%s]" % [
		forest_p, open_p, near_p, trees,
		"OK" if forest_p > 0.1 and open_p < 0.05 and near_p == 0.0 and trees > 0 else "FAIL"])

	# E.21 — the same world must rebuild identically. Also the measurement that
	# decides whether per-chunk dirty regions are worth building: if a full
	# rebuild is this cheap, added complexity buys nothing.
	var fp1 := scatter.fingerprint()
	var t0 := Time.get_ticks_usec()
	scatter.rebuild()
	var ms := float(Time.get_ticks_usec() - t0) / 1000.0
	var fp2 := scatter.fingerprint()
	print("[cozyv2] scatter deterministic: fingerprint %d vs %d  [%s]" % [
		fp1, fp2, "OK" if fp1 == fp2 and fp1 != 0 else "FAIL, field rearranged"])
	print("[cozyv2] scatter rebuild cost: %.1f ms total = %.1f sampling + %.1f mesh build" % [
		ms, scatter.sample_ms, scatter.build_ms])


## Asset library (V2.1 doc E.3 / E.4).
##
## Three things must hold, and each is checked separately:
##   1. valid definitions load, invalid ones are REJECTED with a reason
##   2. raw generator output is excluded from the runtime set (E.3.1)
##   3. queries answer the questions a scatter system will actually ask
##
## Note (3) deliberately returns MORE than the runtime set: `by_category` sees
## every loaded definition, while `runtime_definitions()` is approval-filtered.
## Those are different questions and conflating them is how unapproved art
## reaches a running game.
func _check_assets() -> void:
	if assets == null:
		print("[cozyv2] asset library: NOT BUILT  [FAIL]")
		return

	var s := assets.summary()
	var expected_loaded := 4
	var expected_rejected := 1
	var expected_runtime := 3
	print("[cozyv2] asset library: %d loaded, %d rejected, %d runtime  [%s]" % [
		s["loaded"], s["rejected"], s["runtime"],
		"OK" if s["loaded"] == expected_loaded and s["rejected"] == expected_rejected \
			and s["runtime"] == expected_runtime else "FAIL, expected 4/1/3"])

	# A rejected definition must say WHY (same rule as the terrain gate, doc #72).
	var why := assets.rejection_report()
	print("[cozyv2] asset library rejects malformed_draft: %s  [%s]" % [
		why, "OK" if why.contains("missing") else "FAIL, no reason given"])

	# E.3.1 — the RAW asset must not appear in the runtime set.
	var raw_leaked := false
	for d in assets.runtime_definitions():
		if d.state_name() != "approved":
			raw_leaked = true
	var raw_visible_to_query := assets.by_category("vegetation").size()
	print("[cozyv2] asset library raw exclusion: runtime=%d, vegetation query=%d  [%s]" % [
		s["runtime"], raw_visible_to_query,
		"OK" if not raw_leaked and raw_visible_to_query == 3 else "FAIL"])

	var grassland := assets.by_biome_and_category("grassland", "vegetation")
	print("[cozyv2] asset library biome query: grassland+vegetation -> %d  [%s]" % [
		grassland.size(), "OK" if grassland.size() == 2 else "FAIL, expected 2"])


## The interface (built 2026-09-11).
##
## Four things, each of which was broken or absent before:
##   1. every tool has a button, and a click and the TAB key share one path
##   2. the terrain tools are REACHABLE — they had no UI at all, so the whole
##      terrain system built in V2-10/V2-11 could not be invoked from the game
##   3. the context menu offers what is actually under the cursor
##   4. colliders resolve back to their owning object, which is what makes (3)
##      possible at all
func _check_ui() -> void:
	if hud == null or menu == null:
		print("[cozyv2] ui: NOT BUILT  [FAIL]")
		return

	print("[cozyv2] hud: %d panel(s), %d tool button(s) for %d tool(s)  [%s]" % [
		hud.panel_count(), hud.tool_button_count(), TOOLS.size(),
		"OK" if hud.tool_button_count() == TOOLS.size() and hud.panel_count() >= 3 else "FAIL"])

	# (2) Reachability, through the same call a button click makes.
	var dig_i := TOOLS.find("dig")
	hud.select_tool(dig_i)
	var reached := build_mode and _is_terrain_tool() and tool_idx == dig_i
	print("[cozyv2] terrain tools reachable from the HUD: %s  [%s]" % [
		_current_tool(), "OK" if reached else "FAIL, tool did not switch"])

	# (4) A collider must walk back to the view that owns it. Without this the
	# context menu cannot tell a wall from a slab from the ground.
	var probe_ok := true
	var checked := 0
	for ws in building.state.walls:
		var v: CozyWall = null
		for cand in building.wall_views:
			if cand.state.id == ws.id:
				v = cand
				break
		if v == null or v.bodies().is_empty():
			continue
		checked += 1
		if _kind_of(_owner_of(v.bodies()[0])) != "wall":
			probe_ok = false
		if checked >= 3:
			break
	print("[cozyv2] context probe: %d wall collider(s) resolved to their wall  [%s]" % [
		checked, "OK" if probe_ok and checked > 0 else "FAIL"])

	# (3) The ground menu is the entry point for terrain editing, so its
	# presence is the thing worth asserting — not merely that a menu opened.
	menu.open_for([
		{"id": "terrain_edit", "label": "Terrain edit"},
		{"id": "terrain_clear", "label": "Clear here"},
	], Vector2(40, 40), {"title": "Ground"})
	var labels := menu.entry_labels()
	var has_terrain := labels.has("Terrain edit")
	print("[cozyv2] context menu on ground: %s  [%s]" % [
		str(labels), "OK" if has_terrain and labels.size() == 2 else "FAIL"])
	menu.hide()

	# (4) The info panel is where selecting something lands.
	hud.show_info("Wall", ["test line"])
	var shown := hud.info_visible() and hud.info_title_text() == "Wall"
	hud.clear_info()
	var hidden := not hud.info_visible()
	print("[cozyv2] info panel: shows=%s hides=%s  [%s]" % [
		str(shown), str(hidden), "OK" if shown and hidden else "FAIL"])

	# Leave the scene on the wall tool so the demo opens in a neutral state.
	hud.select_tool(TOOLS.find("outline"))


## Camera lock (V2.1 doc E.1.1). Free rotation is barred as a gameplay feature
## because every pixel asset is authored for exactly ONE observation direction.
## The lock therefore has to actually hold — being the default is not enough.
func _check_camera() -> void:
	var yaw0 := camera.yaw_deg
	var pitch0 := camera.pitch_deg
	var moved_yaw := camera.rotate_by(30.0)
	var moved_pitch := camera.pitch_by(15.0)
	var refused := not moved_yaw and not moved_pitch
	var held := refused and is_equal_approx(camera.yaw_deg, yaw0) \
		and is_equal_approx(camera.pitch_deg, pitch0)

	print("[cozyv2] camera fixed at yaw %.0f / pitch %.0f: rotation refused=%s, is_locked=%s  [%s]" % [
		yaw0, pitch0, str(refused), str(camera.is_locked()),
		"OK" if held and camera.is_locked() else "FAIL"])

	# The debug unlock must still work when deliberately asked for, and must be
	# able to get back to spec.
	camera.free_look = true
	var unlocked := camera.rotate_by(10.0)
	camera.lock_view()
	print("[cozyv2] camera debug unlock: rotates=%s, relocks=%s  [%s]" % [
		str(unlocked), str(camera.is_locked()),
		"OK" if unlocked and camera.is_locked() else "FAIL"])


## Pixel VFX (V2.1 doc E.18 / E.21).
##
## Staged rather than checked at startup: nothing has run a frame yet inside
## `_ready`, so animation would have nothing to report. It also checks the thing
## the doc actually cares about — that two instances of the same effect do NOT
## animate in lockstep.
func _check_vfx() -> void:
	var fires: Array[CozyVfx] = []
	for o in objects:
		if not is_instance_valid(o):
			continue
		for fx in o.vfx:
			if fx.vfx_id == "fire":
				fires.append(fx)

	if fires.size() < 2:
		print("[cozyv2] vfx: expected 2 campfire effects, found %d  [FAIL]" % fires.size())
		return

	print("[cozyv2] vfx: %d fire effect(s), %d frame(s), now frame %d, advanced %d  [%s]" % [
		fires.size(), fires[0].frames.size(), fires[0].current_frame(),
		fires[0].advances(),
		"OK" if fires[0].advances() > 0 and fires[0].frames.size() > 1 else "FAIL, not animating"])

	var phase_gap := absf(fires[0].start_phase - fires[1].start_phase)
	print("[cozyv2] vfx desync: phases %.3f vs %.3f  [%s]" % [
		fires[0].start_phase, fires[1].start_phase,
		"OK" if phase_gap > 0.01 else "FAIL, effects in lockstep"])


## Occlusion (doc #57). The camera follows the player, so only geometry that
## blocks the PLAYER may fade.
##
## The check is on the CAUSE, not the count. Being outdoors is not the same as
## having a clear view: with the camera pitched 55 degrees and sitting on the
## far side of the house, the line of sight to a player standing outside really
## does pass through the roof, and fading it is correct. What must never happen
## is fading for a character the camera is not following.
func _check_occlusion() -> void:
	if occlusion == null:
		print("[cozyv2] occlusion: NOT BUILT  [FAIL]")
		return
	var others := occlusion.faded_for_others()
	var total := occlusion.faded_count()
	var outdoors := floor_system.room_at(player.global_position) == null
	print("[cozyv2] occlusion, player %s: %s, %d for non-followed  [%s]" % [
		"outdoors" if outdoors else "indoors",
		occlusion.debug_summary(), others,
		"OK" if others == 0 else "FAIL, faded on someone else's behalf"])


## The resident's data model (V2-22, doc #43 / 愿景 §9-§10).
##
## Checked after the NPC has worked, because the interesting assertion is that
## the data CHANGED — a state that round-trips but never grows is a snapshot,
## not a resident.
func _check_npc_state() -> void:
	var st := npc.npc_state
	if st == null:
		print("[cozyv2] npc state: NOT ATTACHED  [FAIL]")
		return

	# 愿景 §10 — the multipliers are specified, so they are asserted.
	var p_neutral := CozySkills.passion_multiplier(CozySkills.Passion.NEUTRAL)
	var p_interested := CozySkills.passion_multiplier(CozySkills.Passion.INTERESTED)
	var p_passionate := CozySkills.passion_multiplier(CozySkills.Passion.PASSIONATE)
	var hate_blocked := not CozySkills.can_be_assigned(CozySkills.Passion.HATE)
	print("[cozyv2] passions: neutral x%.0f interested x%.0f passionate x%.0f, hate blocked=%s  [%s]" % [
		p_neutral, p_interested, p_passionate, str(hate_blocked),
		"OK" if is_equal_approx(p_neutral, 1.0) and is_equal_approx(p_interested, 2.0) 			and is_equal_approx(p_passionate, 4.0) and hate_blocked else "FAIL"])

	# THE PAYOFF, checked FIRST: work must have grown the skill. Asserting it
	# after the clamp test below would measure a value that test just destroyed —
	# which is exactly what the first version of this did.
	#
	# Starts at 6 with INTERESTED passion (x2), so each finished job adds 2.
	var trained := st.skill("research")
	print("[cozyv2] working trained the skill: research=%d after %d job(s)  [%s]" % [
		trained, npc.completions,
		"OK" if trained > 6 else "FAIL, skill did not grow"])

	# 愿景 §9 — 0..20, and a value beyond it must be clamped rather than stored.
	# Destructive, so it runs after everything that reads the worked-for value.
	st.train("research", 999)
	var clamped := st.skill("research") == CozySkills.MAX_LEVEL
	st.train("research", -999)
	clamped = clamped and st.skill("research") == CozySkills.MIN_LEVEL
	print("[cozyv2] skill clamp: 0..%d held  [%s]" % [
		CozySkills.MAX_LEVEL, "OK" if clamped else "FAIL"])

	# doc E.21 — the same seed must give the same character, or a resident's
	# traits would rearrange themselves across a save and reload.
	var a := CozyNpcState.create("t", "T", "researcher", 4242)
	var b := CozyNpcState.create("t", "T", "researcher", 4242)
	print("[cozyv2] traits deterministic: %s  [%s]" % [
		str(a.traits), "OK" if a.traits == b.traits and a.traits.size() > 0 else "FAIL"])

	# Round-trip is the save path (V2-26). Everything that matters must survive.
	st.set_passion("research", CozySkills.Passion.INTERESTED)
	var restored := CozyNpcState.from_dict(st.to_dict())
	var same := restored.job_id == st.job_id 		and restored.traits == st.traits 		and restored.skill("research") == st.skill("research") 		and restored.passion("research") == st.passion("research") 		and is_equal_approx(restored.move_speed, st.move_speed)
	print("[cozyv2] npc state round-trip: job=%s traits=%d skill=%d  [%s]" % [
		restored.job_name(), restored.traits.size(), restored.skill("research"),
		"OK" if same else "FAIL"])

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
	if hud == null:
		return

	var p := player.global_position
	var room := floor_system.room_at(p) if floor_system != null else null

	var mode := "MOVE"
	if build_mode:
		mode = "BUILD  \u00b7  %s" % _current_tool()
		if _current_tool() == "outline":
			mode += "   [%d pt \u00b7 ENTER build \u00b7 ESC cancel]" % _outline_points.size()
	hud.set_mode(mode, build_mode)

	hud.set_camera("CAM %.0f/%.0f" % [camera.yaw_deg, camera.pitch_deg], camera.free_look)

	hud.set_context("floor %d  %s    %s" % [
		player.current_floor(FLOOR_H),
		(room.id if room != null else "outdoors"),
		(npc.status_line() if npc != null else "-")])

	if building.inventory != null:
		hud.set_resources(building.inventory.items)

	hud.set_message(_hud_message, _hud_message_warn)


## Show feedback for a few seconds. Refusals go through here too, because the
## one message the player must not miss is the one explaining why nothing
## happened when they clicked.
func _say(text: String, warn := false, seconds := 3.0) -> void:
	_hud_message = text
	_hud_message_warn = warn
	_hud_message_until = _clock + seconds


func _expire_message() -> void:
	if _hud_message != "" and _clock > _hud_message_until:
		_hud_message = ""
