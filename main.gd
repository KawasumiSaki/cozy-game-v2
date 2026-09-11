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

## Cell size for the OUTDOOR navigation grid, metres.
##
## Coarser than a room's 0.25 m on purpose: this grid spans the whole terrain,
## and 0.25 m over 64 x 64 m is 65,536 cells — a startup cost paid for precision
## nobody can see at that scale. Half a metre still routes around a house.
const OUTDOOR_CELL := 0.5

var camera: CozyCameraRig = null
var player: CozyCharacter = null
var npc: CozyNpcAgent = null
var occlusion: CozyOcclusion = null
var hud: CozyHud = null
var menu: CozyContextMenu = null
var npc_panel: CozyNpcPanel = null

## Who the resident panel is showing. Held as the node, not an index, so it stays
## correct the day residents can be added or removed.
var _npc_panel_target: CozyNpcAgent = null

var clock: CozyTimeSystem = null
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
	_build_clock()
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

	# Deliberately after _report(): pass 1 wants to write a world that has already
	# been through every check, and pass 2 wants its own checks printed first.
	if _is_headless:
		if _has_arg("--cozy-save-on-exit"):
			_cross_process_save()
		elif _has_arg("--cozy-load-first"):
			_cross_process_verify()


func _build_clock() -> void:
	clock = CozyTimeSystem.new()
	add_child(clock)


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
	_refresh_scatter()


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
	_rebuild_terrain_surface()


## The ground beyond the terrain field — the world does not stop at the field's
## edge.
##
## A FRAME, not one slab, and the reason is debt 2. The terrain field now carries
## its own collision, displaced to its own heights. A slab spanning the field
## would sit at y=0 as a LID over every hole dug into it: the player would see a
## pit and walk straight across the top of it. Four strips leave the field to its
## own surface.
##
## The visual sits a hair low so it never z-fights the field's edge.
func _build_ground() -> void:
	var grass := CozyPixelArt.make_texture(16, Color(0.44, 0.72, 0.36), 0.055, 1337)
	var o := terrain.origin
	var x0 := o.x
	var x1 := o.x + terrain.width_m
	var z0 := o.y
	var z1 := o.y + terrain.depth_m
	var out := 200.0

	# x0, z0, x1, z1 — the four bands around the field.
	var strips := [
		[-out, -out, out, z0],
		[-out, z1, out, out],
		[-out, z0, x0, z1],
		[x1, z0, out, z1],
	]
	for s in strips:
		var w: float = s[2] - s[0]
		var d: float = s[3] - s[1]
		if w <= 0.0 or d <= 0.0:
			continue
		var cx: float = (s[0] + s[2]) * 0.5
		var cz: float = (s[1] + s[3]) * 0.5

		var ground := MeshInstance3D.new()
		var pm := PlaneMesh.new()
		pm.size = Vector2(w, d)
		ground.mesh = pm
		# Half a texture repeat per metre, matching the old single slab.
		ground.material_override = CozyPixelArt.make_material(grass,
			Vector3(w * 0.5, d * 0.5, 1.0))
		ground.position = Vector3(cx, -0.1, cz)
		add_child(ground)

		var body := StaticBody3D.new()
		var cs := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = Vector3(w, 1.0, d)
		cs.shape = box
		body.add_child(cs)
		body.position = Vector3(cx, -0.5, cz)
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
## slopes and gables from those.
##
## This is what the slabs-and-stairs migration unblocked — before it, there was
## no way to ask where the floors were or how high the building went.
##
## But "move a wall and the roof follows" was not true until debt 8. The pass skipped
## any room that already had a roof, keyed on the room's ID — and an ID SURVIVES
## a wall moving. So a room could be reshaped and keep the roof it had before,
## floating over a footprint that no longer existed, while every count in the
## world stayed correct.
##
## Matching is by POLYGON now, and a roof that no longer matches is retired and
## rebuilt. A second pass still stacks nothing: an unchanged room still matches.
func _build_roofs() -> void:
	var intents: Array = []
	var retire: Array[String] = []
	for r in floor_system.all_rooms():
		var existing := _roof_for(r.id)
		if _has_cover_above(r):
			# Something covers this room now, so any roof it had is wrong.
			if existing != null:
				retire.append(existing.id)
			continue
		# The eave line sits on top of this room's own walls, one floor height
		# above its floor — not at the top of the building.
		var base_y := floor_system.elevation_of(r.floor_index + 1)
		if existing != null:
			if _roof_matches(existing, r, base_y):
				continue
			retire.append(existing.id)
		intents.append(CozyBuildingIntent.add_roof(r.id, r.polygon, base_y,
			CozyRoofState.Style.GABLE, "brick", r.floor_index + 1))

	for id in retire:
		building.state.remove_roof(id)
	if intents.is_empty():
		return
	building.submit_many(intents)


func _roof_for(room_id: String) -> CozyRoofState:
	for r in building.state.roofs:
		if r.room_id == room_id:
			return r
	return null


## Is this roof still the right roof for this room?
##
## Comparing the POLYGON is the point: a room's id is stable across an edit, so
## `room_id` matching says nothing about whether the shape is still the same.
func _roof_matches(roof: CozyRoofState, room: CozyRoom, base_y: float) -> bool:
	if absf(roof.base_y - base_y) > 0.001:
		return false
	if roof.polygon.size() != room.polygon.size():
		return false
	for i in roof.polygon.size():
		if roof.polygon[i].distance_to(room.polygon[i]) > 0.001:
			return false
	return true


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

	# A resident's day needs a bed and somewhere to sit, and both have to be
	# INSIDE: the schedule (V2-25) sends them to sleep, to eat and to rest, and
	# without these the day simply cannot happen. Furniture placement is by
	# hand for now — build-mode placement is how a player would do it.
	_place_object("bed", 1.5, 1.5, 0)
	_place_object("chair", 2.0, 5.0, 0)


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

	# The stair portal is still a fixture — a stair is a special component whose
	# two ends are not derivable from a wall opening. Doors are NOT: they come
	# out of the wall data below, which is why there is no hand-written door
	# portal here any more. Registering one by hand as well produced a duplicate
	# describing the same doorway.
	#
	# Both anchors sit OUTSIDE the ramp footprint: the foot just west of it (the
	# only side you can walk onto), the head on the landing at floor level.
	floor_system.add_portal(CozyPortal.new("stair_main", CozyPortal.Kind.STAIR,
		Vector3(WELL_X0 - 0.3, 0.05, 4.5),
		Vector3((WELL_X1 + HOUSE_W) * 0.5, FLOOR_H + 0.05, 4.5)))

	# Door openings become portals (doc #27 / #29).
	#
	# This was MISSING, and it bit: a wall carrying a door still left the rooms
	# on either side disconnected in the room graph, so a resident whose bedroom
	# ended up on the far side of a new wall could not reach the stairs — even
	# though the wall had a door in it. Openings carve geometry, and nothing had
	# told the graph that they are also passable.
	#
	# Doc #29 says a Door "knows room_a and room_b", so the pairing is derived
	# exactly the way everything else here is: place two probe points either
	# side of the wall and ask the spatial model which rooms they land in.
	for ws in building.state.walls:
		for o in ws.openings:
			if o.kind != CozyOpening.Kind.DOOR:
				continue
			var seg := ws.effective_segment()
			var a3: Vector3 = seg[0]
			var b3: Vector3 = seg[1]
			var flat := Vector3(b3.x - a3.x, 0.0, b3.z - a3.z)
			if flat.length() < 0.001:
				continue
			var dir := flat.normalized()
			# Openings are measured from the wall's original start.
			var at := ws.start + dir * o.offset
			var normal := Vector3(-dir.z, 0.0, dir.x)
			# Probe far enough out to clear the wall's own thickness.
			var reach := ws.thickness + 0.9
			floor_system.add_portal(CozyPortal.new(
				"%s_%s" % [ws.id, "door"], CozyPortal.Kind.DOOR,
				at + normal * reach, at - normal * reach))

	floor_system.resolve_portals()

	room_graph = CozyRoomGraph.new()
	room_graph.build(floor_system)

	# The outdoors gets a grid too, or the navigator falls back to a straight
	# line outside and walks through the house.
	_build_outdoor_nav()

	# Local navigation per room, with furniture registered as obstacles.
	# This is what makes moving a table change routing (doc #86).
	#
	# The nav grid is the expensive layer — one cell per 0.25 m — so this is
	# where "local edit, local rebuild" actually pays. Rooms on untouched floors
	# keep the grid they already have.
	# OUTDOORS is in `alive` even though it is not a room: the prune below
	# removes every grid whose id is not listed, and the outdoor grid is keyed by
	# a space no room has.
	var alive := {CozyRoomGraph.OUTDOORS: true}
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


## The outdoors has no room polygon — it is everything that is NOT a room — so
## one is synthesised from the terrain bounds.
##
## Without this the navigator fell back to a straight line outside, and a
## straight line from the front door to a campfire behind the house walked
## through the west wall. That is not theoretical: it is what the schedule dose
## (V2-25) exposed as `blocked, replanning`, and it is asserted below.
func _build_outdoor_nav() -> void:
	if terrain == null:
		return
	var poly := PackedVector2Array([
		Vector2(terrain.origin.x, terrain.origin.y),
		Vector2(terrain.origin.x + terrain.width_m, terrain.origin.y),
		Vector2(terrain.origin.x + terrain.width_m, terrain.origin.y + terrain.depth_m),
		Vector2(terrain.origin.x, terrain.origin.y + terrain.depth_m)])
	var r := CozyRoom.new(CozyRoomGraph.OUTDOORS, 0, poly)
	var nav := CozyLocalNav.new()
	nav.build(r, _outdoor_obstacles(), OUTDOOR_CELL)
	_nav_by_room[CozyRoomGraph.OUTDOORS] = nav


## Everything built, as axis-aligned footprints the outdoor grid must route
## around.
##
## A wall contributes its bounding box: exact for the axis-aligned walls this
## project builds, conservative for a diagonal one. Over-blocking is the safe
## direction — an agent walking a slightly longer way is a nuisance, an agent
## walking through a wall is a defect.
func _outdoor_obstacles() -> Array:
	var out: Array = _static_obstacles_on_floor(0)

	for ws in building.state.walls:
		var a := ws.start
		var b := ws.end
		var pad := ws.thickness * 0.5
		out.append(Rect2(
			Vector2(minf(a.x, b.x) - pad, minf(a.z, b.z) - pad),
			Vector2(absf(b.x - a.x) + pad * 2.0, absf(b.z - a.z) + pad * 2.0)))

	for sl in building.state.slabs:
		# Only ground-level slabs obstruct someone walking outside; an upper
		# floor with open air under it does not.
		if sl.surface_y() > FLOOR_H * 0.5:
			continue
		out.append(sl.footprint())

	for o in objects:
		if is_instance_valid(o) and o.floor_index == 0:
			out.append(o.footprint_rect())

	return out


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
	# A starter larder. Eating needs food to exist (debt 15), and until §45's
	# production chain lands there is nothing that produces any — a resident with
	# an empty pack simply starves, which is the honest behaviour and a poor
	# first impression. Six loaves is a few days at the doc's own meal times.
	npc.npc_state.inventory.add("bread", 6.0)
	npc.uses_gravity = true
	npc.floor_max_angle = deg_to_rad(55.0)
	add_child(npc)
	npc.global_position = Vector3(6.0, 0.2, 1.5)
	npc.navigator = world_navigator
	npc.objects = objects
	npc.clock = clock


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

	# The resident panel rides the HUD's CanvasLayer and is anchored to the right
	# edge, so it never covers the tool strip along the bottom. Offset bottom is
	# left equal to top: a PanelContainer grows to its content's minimum height,
	# and grow_vertical decides which way.
	npc_panel = CozyNpcPanel.new()
	hud.add_child(npc_panel)
	npc_panel.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	npc_panel.offset_left = -CozyNpcPanel.WIDTH - CozyUiTheme.GAP
	npc_panel.offset_right = -CozyUiTheme.GAP
	npc_panel.offset_top = CozyUiTheme.STRIP_H + CozyUiTheme.GAP
	npc_panel.offset_bottom = CozyUiTheme.STRIP_H + CozyUiTheme.GAP
	npc_panel.grow_vertical = Control.GROW_DIRECTION_END
	npc_panel.visible = false


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
		"npc":
			# The resident panel is where V2-22 and V2-25 stop being stored values.
			#
			# `npc_state`, NOT `state`: an agent's `state` is its FSM enum
			# (IDLE/GOING/WORKING), and reading that instead would hand the panel an
			# int — no error, no crash, just a blank resident.
			var a: CozyNpcAgent = probe["node"]
			target["title"] = a.npc_state.display_name if a.npc_state != null else "Resident"
			entries.append({"id": "npc_panel", "label": "Resident",
				"hint": "attributes, skills, needs and today's schedule"})
			entries.append({"id": "info", "label": "Info"})
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
			_rebuild_terrain_surface()
			_rebuild_spatial_after_terrain()
			_say("cleared")
		"remove":
			_remove_target(target)
		"npc_panel":
			_open_npc_panel(target["node"])
		"info":
			_show_info(target)


# ---------------------------------------------------------------- resident panel

func _open_npc_panel(agent: CozyNpcAgent) -> void:
	if agent == null or agent.npc_state == null:
		_say("that resident has no state attached", true)
		return
	_npc_panel_target = agent
	npc_panel.visible = true
	_refresh_npc_panel()


func _close_npc_panel() -> void:
	npc_panel.visible = false
	_npc_panel_target = null


## Called every frame the panel is open. Needs MOVE — hunger climbs and energy
## falls while you read, and a panel frozen at the value it opened with would
## teach the player the numbers are decorative.
func _refresh_npc_panel() -> void:
	if npc_panel == null or not npc_panel.visible:
		return
	if not is_instance_valid(_npc_panel_target):
		_close_npc_panel()
		return
	var st: CozyNpcState = _npc_panel_target.npc_state
	if st == null:
		return
	# current_activity() rather than the raw schedule: a critical need overrides
	# the timetable (doc #116), and the panel should agree with the agent.
	npc_panel.refresh(st, clock.hour, _npc_panel_target.current_activity())


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
		_rebuild_terrain_surface()


## Called once when a terrain stroke finishes: everything downstream of the
## ground catches up in a single pass.
func _rebuild_spatial_after_terrain() -> void:
	# Rooms, portals, navigation and the roof all depend on buildability, which
	# the terrain just changed.
	_rebuild_spatial()
	_build_roofs()
	_refresh_scatter()
	_update_hud()


## Chunks the terrain has touched since the last scatter rebuild.
##
## `terrain_renderer.rebuild_dirty()` calls `terrain.clear_dirty()`, and the
## scatter runs after it — so without this ledger the scatter can never learn
## what an edit touched and has to resample the whole field. That was debt 6's
## performance half: one candidate per metre over 64 x 64 m, redone for a brush
## stroke that moved a handful of cells.
var _terrain_dirty_accum: Dictionary = {}


## Take the dirty chunks BEFORE the renderer consumes them, then let it consume
## them. Every terrain edit goes through here, so no caller can clear the set
## behind the ledger's back.
func _rebuild_terrain_surface() -> void:
	for c in terrain.dirty_chunks():
		_terrain_dirty_accum[c] = true
	terrain_renderer.rebuild_dirty()


## Bring the scatter level with the terrain: incrementally when the ledger knows
## what changed, in full when it does not.
##
## The ledger is cleared HERE, beside the rebuild that consumes it. A ledger that
## outlived its rebuild would point the NEXT edit at the wrong chunks, and the
## result would look like ordinary vegetation that is subtly not the same field.
func _refresh_scatter() -> void:
	scatter.building_points = _building_points()
	if _terrain_dirty_accum.is_empty():
		scatter.rebuild()
	else:
		scatter.rebuild_dirty(_terrain_dirty_accum.keys())
	_terrain_dirty_accum.clear()


# ---------------------------------------------------------------- outline

## Finish the current outline and turn it into a building (doc #17 / #86).
##
## The generator emits WALL INTENTS and a doorway; everything else follows on
## its own — rooms come from the wall graph, the roof from the rooms. That is
## the doc's "intent in, structure out" chain, and none of it is special-cased.
func _finish_outline() -> void:
	# A bad outline is refused with a REASON rather than built into a broken
	# graph. A crossed outline produces walls that intersect mid-span, and room
	# detection then walks a non-planar graph — the T-junction failure again,
	# which showed up only as a room that quietly did not appear.
	var reason := CozyOutlineGenerator.reject_reason(_outline_points)
	if reason != "":
		_say("outline refused: %s" % reason, true, 5.0)
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
		# Tool hotkeys — the same ones the palette prints on its buttons. They go
		# through the HUD's own selection path, so a key and a click cannot drift.
		if event.keycode >= KEY_0 and event.keycode <= KEY_9:
			var i := CozyHud.index_for_hotkey(event.keycode - KEY_0)
			if i >= 0 and i < TOOLS.size():
				_on_hud_tool_selected(i)
				return
		if event.keycode == KEY_ENTER or event.keycode == KEY_KP_ENTER:
			if build_mode and _current_tool() == "outline":
				_finish_outline()
				return
		if event.keycode == KEY_ESCAPE:
			# Esc closes whatever is on top: the resident panel first, then an
			# unfinished outline. Dismissing a read-only panel must never discard
			# work the player has not finished.
			if npc_panel != null and npc_panel.visible:
				_close_npc_panel()
				return
			if build_mode and _outline_points.size() > 0:
				_cancel_outline()
				_say("outline cancelled")
				_update_hud()
				return
		# Save / load. Godot's own editor uses F5/F9 for run and stop, so the
		# muscle memory is already there; these are the obvious keys, and a save
		# system with no way to invoke it would be one more capability with no
		# consumer.
		if event.keycode == KEY_F5:
			save_game()
			return
		if event.keycode == KEY_F9:
			load_game()
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

	_refresh_npc_panel()
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

	# Doors are derived from wall openings now, so the check looks for the
	# connection rather than for a hand-chosen id.
	_check_door_between("", "room_0_0")
	_check_portal("stair_main", "room_0_0", "room_1_0")

	# Asserted by the KIND of connector crossed, not by id: a door's portal id is
	# generated from the wall that carries the opening, so a named expectation
	# would break every time the walls are renumbered — and "through a door,
	# then up a stair" is what this test actually means.
	_check_route_kinds(CozyRoomGraph.OUTDOORS, "room_1_0", ["door", "stair"])
	_check_route_kinds("room_0_0", "room_1_0", ["stair"])
	_check_route_kinds("room_1_0", "room_1_0", [])

	_check_camera()
	_check_ui()
	_check_container()
	_check_eating()
	_check_save_load()
	_check_assets()
	_check_scatter()
	_check_nav()
	_check_terrain()
	_check_terrain_surface()
	_check_wall_connection()
	_check_openings()
	_check_wall_assembly()
	_check_building_state()
	_check_roofs()
	_check_scatter_incremental()
	_check_outline_guard()
	_check_roof_follows_room()
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
	_rebuild_terrain_surface()

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
## Scatter resamples only what changed (debt 6's performance half).
##
## The correctness half — plants following the terrain's height — is asserted in
## `_check_terrain_surface`. This is the other half: an edit re-sampled the whole
## 64 x 64 m field, one candidate per metre, to move a handful of cells.
##
## The check that matters is EQUIVALENCE, not speed. An incremental rebuild that
## produces a different field from a full one is a worse bug than the slowness it
## replaced, and it would look completely ordinary: the same kinds of plant in
## slightly different places.
func _check_scatter_incremental() -> void:
	var snapshot := terrain.to_dict()
	_refresh_scatter()
	var full_fp := scatter.fingerprint()
	var full_total := scatter.total_instances()

	# One edit, the way a brush makes one. Clearing rather than digging on
	# purpose: digging changes only the height, and the plants in that patch may
	# not move enough for the fingerprint to notice — the check would then be
	# comparing two identical fields and proving nothing. A material change
	# alters which rules spawn, so the edit is guaranteed to be visible.
	var px := terrain.origin.x + 8.0
	var pz := terrain.origin.y + 8.0
	terrain.apply_intent(CozyTerrainIntent.clear_brush(Vector2(px, pz), 3.0))
	var touched := terrain.dirty_chunks().size()
	_rebuild_terrain_surface()
	_refresh_scatter()
	var inc_fp := scatter.fingerprint()
	var inc_total := scatter.total_instances()

	# The same edit done the expensive way, as the reference.
	scatter.rebuild()
	var ref_fp := scatter.fingerprint()

	var moved := inc_fp != full_fp
	var same := inc_fp == ref_fp and inc_total == scatter.total_instances()
	print("[cozyv2] scatter incremental rebuild: %d chunk(s) dirty, %d -> %d instance(s), moved=%s, matches a full rebuild=%s  [%s]" % [
		touched, full_total, inc_total, str(moved), str(same),
		"OK" if same and moved and touched > 0
			else "FAIL, incremental differs from a full rebuild"])

	# Put the field back, and prove the restore took too.
	terrain.from_dict(snapshot)
	_rebuild_terrain_surface()
	_refresh_scatter()
	_rebuild_spatial()


## The outline guard (debt 8). A crossed outline becomes walls that intersect
## mid-span, and room detection is then handed a non-planar graph — the
## T-junction failure again, which shows up only as a room that quietly does not
## appear.
##
## Asserted in BOTH directions, because a guard that refuses too much is its own
## bug: it would silently make L-shaped buildings unbuildable.
func _check_outline_guard() -> void:
	var bowtie := PackedVector2Array([Vector2(0.0, 0.0), Vector2(4.0, 4.0),
		Vector2(4.0, 0.0), Vector2(0.0, 4.0)])
	var repeated := PackedVector2Array([Vector2(0.0, 0.0), Vector2(0.0, 0.0),
		Vector2(4.0, 0.0), Vector2(4.0, 4.0)])
	# Concave, and perfectly legitimate. The roof generator degrades to a flat
	# roof for it, which is doc #31's stated simplification — not a reason to
	# refuse the walls.
	var ell := PackedVector2Array([Vector2(0.0, 0.0), Vector2(6.0, 0.0),
		Vector2(6.0, 3.0), Vector2(3.0, 3.0), Vector2(3.0, 6.0), Vector2(0.0, 6.0)])
	var square := PackedVector2Array([Vector2(0.0, 0.0), Vector2(4.0, 0.0),
		Vector2(4.0, 4.0), Vector2(0.0, 4.0)])

	var bowtie_r := CozyOutlineGenerator.reject_reason(bowtie)
	var repeat_r := CozyOutlineGenerator.reject_reason(repeated)
	var ell_r := CozyOutlineGenerator.reject_reason(ell)
	var square_r := CozyOutlineGenerator.reject_reason(square)

	# The bowtie must be refused BY THE GUARD and not by something else further
	# down. `plan()` produces its walls quite happily, so the guard is the only
	# thing standing between this polygon and a non-planar graph — without this
	# line the check would still pass if the guard were removed and the terrain
	# gate happened to refuse the walls instead.
	var would_build := CozyOutlineGenerator.plan(bowtie, 0.0, FLOOR_H, WALL_T,
		"wood", 0, Vector2(2.0, 2.0)).size()

	var refuses_bad := bowtie_r != "" and repeat_r != "" and would_build == 4
	var allows_good := ell_r == "" and square_r == ""
	print("[cozyv2] outline guard: bowtie=\"%s\" (%d wall(s) planned, refused by the guard), repeated=\"%s\"; L-shape and square allowed=%s  [%s]" % [
		bowtie_r, would_build, repeat_r, str(allows_good),
		"OK" if refuses_bad and allows_good else "FAIL"])


## Roofs follow their room (debt 8).
##
## The bug was never "a roof is missing". It was that a roof could OUTLIVE the
## room it was built for: `_build_roofs` skipped any room that already had a
## roof, keyed on the room's ID, and an ID survives a wall moving. The shape
## changed under a fixed roof while every count in the world stayed correct.
##
## This drives the decision directly — it makes a roof disagree with its room the
## way a moved wall would, and requires the next pass to notice. Reaching the
## same state by moving walls would be three coordinated edits for the same code
## path.
func _check_roof_follows_room() -> void:
	var room: CozyRoom = null
	var roof: CozyRoofState = null
	for r in floor_system.all_rooms():
		var cand := _roof_for(r.id)
		if cand != null:
			room = r
			roof = cand
			break
	if room == null or roof == null:
		print("[cozyv2] roof follows its room: no roofed room in the scene  [FAIL]")
		return

	var before_id := roof.id
	var poly := roof.polygon
	if poly.is_empty():
		print("[cozyv2] roof follows its room: roof has no polygon  [FAIL]")
		return
	poly[0] = poly[0] + Vector2(1.5, 1.5)
	roof.polygon = poly

	var noticed := not _roof_matches(roof, room, roof.base_y)
	_build_roofs()

	var after := _roof_for(room.id)
	var base_y := floor_system.elevation_of(room.floor_index + 1)
	var repaired := after != null and _roof_matches(after, room, base_y)
	print("[cozyv2] roof follows its room: noticed=%s, rebuilt=%s (roof %s -> %s)  [%s]" % [
		str(noticed), str(repaired), before_id, after.id if after != null else "-",
		"OK" if noticed and repaired else "FAIL, a stale roof survived"])


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
	_check_schedule_and_needs()
	_check_outdoor_nav()


func _run_live_rebuild_test() -> void:
	print("[cozyv2] --- live rebuild test: add a dividing wall ---")
	var before := floor_system.rooms_on(0).size()
	# Bisect the GROUND floor. The autopilot has already finished by this frame,
	# so the new wall cannot interfere with the walk-through test.
	var divider := _add_wall(Vector3(4.0, 0.0, 0.0), Vector3(4.0, 0.0, HOUSE_D),
		"wood", 0)
	divider.add_opening(CozyOpening.door(HOUSE_D * 0.5, 1.2))
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


## Terrain HEIGHT, displaced into the ground (debt 2), and the plants that sit on
## it (debt 6).
##
## Before this the field carried a height DIG changed and the renderer ignored:
## the ground was one flat plane at y=0, so a dug cell looked exactly like an
## undug one. The number moved and nothing else did.
##
## Surface and collision are asserted SEPARATELY because they fail independently,
## and the failure between them is the worst of the three: displacing the picture
## without moving the collision gives a pit the player can see and walk straight
## across the top of. That is worse than no pit, because it is a lie.
func _check_terrain_surface() -> void:
	# Inside the field and clear of the homestead.
	var px := terrain.origin.x + 48.0
	var pz := terrain.origin.y + 48.0
	var extent := terrain.chunk_extent()
	var coord := Vector2i(int(floor((px - terrain.origin.x) / extent)),
		int(floor((pz - terrain.origin.y) / extent)))

	var flat := terrain_renderer.chunk_surface_range(coord)
	var flat_ok := absf(flat.x) < 0.001 and absf(flat.y) < 0.001
	print("[cozyv2] terrain surface before digging: y %.2f..%.2f (flat)  [%s]" % [
		flat.x, flat.y, "OK" if flat_ok else "FAIL"])

	var snapshot := terrain.to_dict()          # restored at the end

	var touched: int = terrain.apply_intent(
		CozyTerrainIntent.dig_brush(Vector2(px, pz), 2.5, 0.5))["touched"]
	_rebuild_terrain_surface()
	_refresh_scatter()

	var dug := terrain_renderer.chunk_surface_range(coord)
	var col := terrain_renderer.chunk_collision_min_y(coord)
	print("[cozyv2] terrain after DIG 0.5 m: %d cell(s), surface y %.2f..%.2f, collision min y %.2f  [%s]" % [
		touched, dug.x, dug.y, col,
		"OK" if touched > 0 and dug.x < -0.1 and col < -0.1
			else "FAIL, the ground did not follow the field"])

	print("[cozyv2] scatter sits on the surface: lowest sampled y %.2f  [%s]" % [
		scatter.lowest_y,
		"OK" if scatter.lowest_y < -0.1 else "FAIL, plants are still placed at y=0"])

	# Put the ground back, so every check after this sees the world it expects.
	# The restore goes through the save/load serialiser, which exercises it too.
	terrain.from_dict(snapshot)
	terrain_renderer.rebuild_all()
	_rebuild_spatial_after_terrain()


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
	_refresh_scatter()
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

	_check_npc_panel()

	# The clock and the tool hotkeys — both "declared but never shown". The clock
	# has had hh_mm()/season() since Phase 0 with nothing displaying them, and
	# `set_tools` carried a comment claiming the hotkey was printed while nothing
	# printed it.
	_update_hud()
	var clock_ok := hud.clock_text().begins_with("Day ")
	print("[cozyv2] hud clock: \"%s\"  [%s]" % [
		hud.clock_text(), "OK" if clock_ok else "FAIL, nothing is showing the time"])

	var keys_ok := true
	var distinct := {}
	for i in TOOLS.size():
		var k := hud.tool_hotkey_text(i)
		if k == "" or CozyHud.index_for_hotkey(int(k)) != i:
			keys_ok = false
		distinct[k] = true
	print("[cozyv2] hud tool hotkeys: %d tool(s), %d distinct key(s) shown  [%s]" % [
		TOOLS.size(), distinct.size(),
		"OK" if keys_ok and distinct.size() == TOOLS.size() else "FAIL"])

	# Leave the scene on the wall tool so the demo opens in a neutral state.
	hud.select_tool(TOOLS.find("outline"))


## The resident panel — where V2-22 and V2-25 finally become visible.
##
## The assertion that earns its keep is the idempotence one. The panel redraws
## every frame, and the version this was written against rebuilt each schedule
## row's text from that same row's PREVIOUS text, stripping a fixed-width prefix
## that matched neither format. It accrued garbage sixty times a second.
##
## Every other check below passes with that bug present: the panel exists, it is
## wired, it draws the right number of rows, and a SINGLE refresh produces
## correct output. Only refreshing twice catches it — which is the whole reason
## the assertion is written as "one refresh vs six hundred" rather than "does it
## draw the right thing".
func _check_npc_panel() -> void:
	if npc_panel == null:
		print("[cozyv2] npc panel: NOT BUILT  [FAIL]")
		return

	var hidden_at_start := not npc_panel.visible
	print("[cozyv2] npc panel: built on the HUD, hidden until asked  [%s]" % [
		"OK" if hidden_at_start else "FAIL, visible before anything was selected"])

	# Row counts come from the DATA, never from a list retyped here.
	var skills_ok := npc_panel.skill_row_count() == CozySkills.ORDER.size()
	var sched_ok := npc_panel.schedule_row_count() == CozySchedule.DEFAULT_DAY.size()
	print("[cozyv2] npc panel rows: %d/%d skill(s), %d/%d schedule row(s)  [%s]" % [
		npc_panel.skill_row_count(), CozySkills.ORDER.size(),
		npc_panel.schedule_row_count(), CozySchedule.DEFAULT_DAY.size(),
		"OK" if skills_ok and sched_ok else "FAIL, a row list is out of step with its data"])

	# Content, read back off the widgets after a known state is pushed in.
	var st := CozyNpcState.create("panel_probe", "Probe Resident", "researcher", 7)
	st.traits = []
	st.hunger = 40.0
	st.energy = 90.0
	st.mood = 50.0
	npc_panel.refresh(st, 9.0, "work")
	var titled := npc_panel.title_text() == "Probe Resident"
	var hunger_ok := npc_panel.meter_value("hunger") == 40
	var frac_ok := absf(npc_panel.meter_fraction("hunger") - 0.40) < 0.01
	var marked_ok := npc_panel.highlighted_schedule_hour() == 9
	print("[cozyv2] npc panel content: \"%s\" hunger=%d frac=%.2f marked=%02d:00  [%s]" % [
		npc_panel.title_text(), npc_panel.meter_value("hunger"),
		npc_panel.meter_fraction("hunger"), npc_panel.highlighted_schedule_hour(),
		"OK" if titled and hunger_ok and frac_ok and marked_ok else "FAIL"])

	# Idempotence — see the note above. 600 refreshes is ten seconds of frames.
	var once := npc_panel.schedule_line(9)
	for i in 600:
		npc_panel.refresh(st, 9.0, "work")
	var many := npc_panel.schedule_line(9)
	print("[cozyv2] npc panel refresh idempotent over 600 frames: %s  [%s]" % [
		"unchanged" if once == many else "\"%s\" -> \"%s\"" % [once, many],
		"OK" if once == many else "FAIL, refresh is feeding on its own output"])

	# The menu -> panel path, end to end, on the resident that actually exists.
	if npc != null and npc.npc_state != null:
		_on_menu_action("npc_panel", {"node": npc})
		var opened := npc_panel.visible \
			and npc_panel.title_text() == npc.npc_state.display_name
		print("[cozyv2] menu opens the resident panel: %s -> \"%s\"  [%s]" % [
			npc.npc_state.id, npc_panel.title_text(), "OK" if opened else "FAIL"])
		_close_npc_panel()
		print("[cozyv2] resident panel closes again: %s  [%s]" % [
			str(not npc_panel.visible), "OK" if not npc_panel.visible else "FAIL"])
	else:
		print("[cozyv2] menu opens the resident panel: no resident in the scene  [SKIP]")


## Containers, and the `hauler` job that has never been able to work (V2-21).
##
## The chest has been in this scene since Phase 4 advertising a `store`
## interaction point, and `CozyJobDefs` has carried a `hauler` whose point_type
## is `store` for just as long. Neither meant anything: nothing consumed either
## one. A point nothing answers and a job that can never complete are both
## invisible on screen — they look exactly like features.
##
## The check that earns its keep is CONSERVATION. A transfer system's
## characteristic failure is not a crash; it is goods that quietly doubled or
## vanished, and that is invisible in any single frame.
func _check_container() -> void:
	var chest := _first_object("chest")
	if chest == null or chest.container == null:
		print("[cozyv2] container: the chest has no container behind its store point  [FAIL]")
		return

	var c := chest.container

	# (1) The point the hauler job has always pointed at is finally answered.
	var pts := chest.free_points_of_type(CozyObjectDefs.INTERACT_STORE)
	var hauler_wants := CozyJobDefs.point_type("hauler")
	var answered := not pts.is_empty() and hauler_wants == CozyObjectDefs.INTERACT_STORE
	print("[cozyv2] container: hauler wants \"%s\", chest offers %d point(s)  [%s]" % [
		hauler_wants, pts.size(),
		"OK" if answered else "FAIL, the store point is still unanswered"])

	if npc == null or npc.npc_state == null or npc.npc_state.inventory == null:
		print("[cozyv2] container transfers: no resident with a pack  [SKIP]")
		return
	var pack := npc.npc_state.inventory

	# (2) Deposit, through the same function the agent runs when work completes.
	c.inventory.items.clear()
	pack.items.clear()
	pack.add("wood", 8.0)
	pack.add("stone", 3.0)
	var before := pack.total() + c.stored()
	var msg_out := npc._haul(chest)
	var after := pack.total() + c.stored()
	var conserved := absf(before - after) < 0.0001 and c.stored() > 0.0 \
		and pack.total() <= 0.0
	print("[cozyv2] container deposit: %s, conserved=%s (%.0f -> %.0f)  [%s]" % [
		msg_out, str(conserved), before, after,
		"OK" if conserved else "FAIL, goods were created or destroyed"])

	# (3) And back out again — the other half of the chain.
	var before2 := pack.total() + c.stored()
	var msg_in := npc._haul(chest)
	var after2 := pack.total() + c.stored()
	var conserved2 := absf(before2 - after2) < 0.0001 and pack.total() > 0.0
	print("[cozyv2] container withdraw: %s, conserved=%s (%.0f -> %.0f)  [%s]" % [
		msg_in, str(conserved2), before2, after2,
		"OK" if conserved2 else "FAIL"])

	# (4) Capacity is a real limit, and a refusal moves NOTHING.
	c.inventory.items.clear()
	c.inventory.add("stone", c.capacity - 1.0)      # exactly one unit of room
	pack.items.clear()
	pack.add("wood", 5.0)
	var refused_msg := npc._haul(chest)
	var refused := absf(pack.total() - 5.0) < 0.0001 \
		and absf(c.stored() - (c.capacity - 1.0)) < 0.0001
	print("[cozyv2] container refuses an over-capacity load whole: carrying=%.0f -> %s  [%s]" % [
		pack.total(), refused_msg, "OK" if refused else "FAIL, a partial load moved"])

	# Leave the world as it was found.
	c.inventory.items.clear()
	pack.items.clear()


## Eating (debt 15, and doc #35's item vocabulary).
##
## `tick` had no `eat` branch at all: hunger only ever climbed, so a resident
## reached "critical: eat", walked to a seat, and starved there for the rest of
## the save. Worth recording that the debt note said "`eat` only restores hunger"
## — it did not even do that. A debt list can be wrong in the DIRECTION of the
## problem, not merely stale, and this is the second time today that checking the
## claim was worth more than acting on it.
##
## Three assertions, and the first two are the ones that matter:
##   1. eating needs FOOD — the pack must shrink
##   2. an empty pack does NOT feed anyone
##   3. the larder drains at a sane rate
func _check_eating() -> void:
	# (1) and (2): the same meal, with and without a larder.
	var fed := CozyNpcState.create("fed", "Fed", "researcher", 3)
	fed.traits = []
	fed.hunger = 80.0
	fed.inventory.add("bread", 2.0)
	var bread_before := fed.inventory.count("bread")
	fed.tick(1.0, "eat")

	var empty := CozyNpcState.create("empty", "Empty", "researcher", 4)
	empty.traits = []
	empty.hunger = 80.0
	empty.tick(1.0, "eat")

	var fed_ok := fed.hunger < 80.0 and fed.inventory.count("bread") < bread_before
	var empty_ok := empty.hunger >= 80.0
	print("[cozyv2] eating: with bread hunger 80->%.0f (bread %.0f->%.0f); empty pack 80->%.0f  [%s]" % [
		fed.hunger, bread_before, fed.inventory.count("bread"), empty.hunger,
		"OK" if fed_ok and empty_ok else "FAIL, eating is free food or no food"])

	# (3) The per-frame trap. `tick` runs about 60 times a second with a
	# `game_hours` of ~0.003, so a naive "still hungry? eat a loaf" consumes the
	# whole larder in one second. One second of eating is 0.2 game hours, which is
	# 12 hunger points — well under one 45-point loaf.
	var nib := CozyNpcState.create("nib", "Nib", "researcher", 5)
	nib.traits = []
	nib.hunger = 80.0
	nib.inventory.add("bread", 10.0)
	for i in 60:
		nib.tick(1.0 / 300.0, "eat")
	var drained := 10.0 - nib.inventory.count("bread")
	var nib_ok := nib.hunger < 79.0 and drained <= 1.0
	print("[cozyv2] eating a second of frames: hunger 80->%.0f, loaves eaten %.0f  [%s]" % [
		nib.hunger, drained,
		"OK" if nib_ok else "FAIL, servings are not being banked across frames"])

	# (4) The vocabulary itself (doc #35): food is a CATEGORY in the item table,
	# not a second table, and an inedible item reports no nourishment rather than
	# a default a caller could read.
	var foods := CozyMaterials.food_ids()
	var vocab_ok := foods.has("bread") and CozyMaterials.nourishment("bread") > 0.0 \
		and CozyMaterials.nourishment("wood") == 0.0 \
		and not CozyMaterials.is_food("wood")
	print("[cozyv2] item vocabulary: foods=%s, wood is food=%s nourishment=%.0f  [%s]" % [
		str(foods), str(CozyMaterials.is_food("wood")),
		CozyMaterials.nourishment("wood"),
		"OK" if vocab_ok else "FAIL"])


# ---------------------------------------------------------------- save / load

## The whole world, as facts (doc #63). Everything derived is excluded on
## purpose: meshes, room polygons, portals, navigation grids and paths are all
## rebuilt on load by the generators that built them the first time.
func _world_to_dict() -> Dictionary:
	var objs: Array = []
	for o in objects:
		if is_instance_valid(o):
			objs.append(o.to_dict())
	var npcs: Array = []
	if npc != null and npc.npc_state != null:
		npcs.append(npc.npc_state.to_dict())
	return {
		"terrain": terrain.to_dict(),
		"building": building.state.to_dict(),
		"objects": objs,
		"npcs": npcs,
		"clock": {"day": clock.day, "hour": clock.hour},
	}


## Rebuild the world from facts. The order below is the order the world is built
## in the first place (see `_ready`), which is the only reason it works: terrain
## before building, building before rooms, rooms before roofs.
func _apply_world(d: Dictionary) -> void:
	if d.is_empty():
		return

	terrain.from_dict(d.get("terrain", {}))
	terrain_renderer.rebuild_all()

	# Roofs are cleared by `from_dict` rather than restored — `_build_roofs`
	# refills them below from the rooms it just re-derived.
	building.state.from_dict(d.get("building", {}))

	for o in objects:
		if is_instance_valid(o):
			o.queue_free()
	objects.clear()
	for od in d.get("objects", []):
		# Add first, exactly as `_place_object` does: setup() phases VFX from the
		# world position, which does not exist until the node is parented.
		var o := CozyWorldObject.new()
		add_child(o)
		o.apply_dict(od)
		objects.append(o)

	var npcs: Array = d.get("npcs", [])
	if npc != null and not npcs.is_empty():
		npc.npc_state = CozyNpcState.from_dict(npcs[0])

	var c: Dictionary = d.get("clock", {})
	if not c.is_empty():
		clock.day = int(c.get("day", 1))
		clock.hour = float(c.get("hour", CozyTimeSystem.START_HOUR))

	building.regenerate()
	# This re-derives rooms, portals, the room graph and BOTH navigation layers,
	# and re-links the agent's navigator and object list at the end of it.
	_rebuild_spatial()
	_build_roofs()
	# Walls and roofs are new nodes now, so the occlusion lists still point at
	# the ones that were freed.
	_refresh_occlusion_fadables()
	_update_hud()


## Cross-process save check (V2-26 debt 21).
##
## Everything in `_check_save_load` happens inside ONE process, and that cannot
## answer the question that actually matters: does the game come back after being
## CLOSED and reopened? So this runs in two passes, driven from the shell:
##
##     godot --headless ... --quit-after 2 -- --cozy-save-on-exit
##     godot --headless ... --quit-after 2 -- --cozy-load-first
##
## Pass 2 starts from a freshly built default world — the state a real launch is
## in — so it tests the real path and not a warm one. That is the part a
## single-process check structurally cannot reach: whether `_ready()`'s default
## build can be displaced by a load.
const XPROC_PATH := "user://crossprocess.json"

## What pass 1 writes and pass 2 looks for. Deliberately not round numbers, so a
## default world that coincidentally matches cannot pass.
const XPROC_HUNGER := 37.0
const XPROC_ENERGY := 61.0
const XPROC_DAY := 4
const XPROC_WOOD := 9.0

## Where pass 1 puts its marker wall. Checked by position rather than by counting
## walls: the assertion suite runs before this and mutates the default world (a
## T-junction check adds a divider), so a wall COUNT is not a stable baseline.
const XPROC_MARK_A := Vector3(11.0, 0.0, 11.0)
const XPROC_MARK_B := Vector3(13.0, 0.0, 11.0)


func _has_arg(flag: String) -> bool:
	return OS.get_cmdline_user_args().has(flag)


## Pass 1: build something a default world does not have, then write it.
func _cross_process_save() -> void:
	if npc != null and npc.npc_state != null:
		npc.npc_state.hunger = XPROC_HUNGER
		npc.npc_state.energy = XPROC_ENERGY
	clock.day = XPROC_DAY
	var chest := _first_object("chest")
	if chest != null and chest.container != null:
		chest.container.inventory.items.clear()
		chest.container.inventory.add("wood", XPROC_WOOD)
	# A wall somewhere the homestead does not build one, so the building facts
	# have to have survived too — not just the numbers.
	#
	# The terrain gate (doc #12) refuses to build on uncleared ground and says so:
	# "11,11 is natural (grass)". Clearing it first is what the terrain tool would
	# do, and it means this check now carries a TERRAIN edit across the process
	# boundary as well as a building one.
	terrain.apply_intent(CozyTerrainIntent.clear_brush(
		Vector2(XPROC_MARK_A.x, XPROC_MARK_A.z), TERRAIN_BRUSH))
	_rebuild_terrain_surface()
	_rebuild_spatial_after_terrain()
	var marker := _add_wall(XPROC_MARK_A, XPROC_MARK_B, "wood", 0)
	if marker == null:
		print("[cozyv2] cross-process: marker wall REFUSED at %s -> %s  [FAIL]" % [
			XPROC_MARK_A, building.last_rejection])
	_rebuild_spatial()
	_build_roofs()
	var wrote := save_game(XPROC_PATH)
	print("[cozyv2] cross-process PASS 1 wrote: %d wall(s), npc %d/%d, day %d, wood %.0f  [%s]" % [
		building.state.wall_count(), int(XPROC_HUNGER), int(XPROC_ENERGY),
		XPROC_DAY, XPROC_WOOD, "OK" if wrote else "FAIL, could not write"])


## Pass 2: fresh process, fresh default world, then load over it.
func _cross_process_verify() -> void:
	var fresh_walls := building.state.wall_count()
	var fresh_hunger := npc.npc_state.hunger if npc != null and npc.npc_state != null else -1.0
	var d := CozySaveManager.load_world(XPROC_PATH)
	if d.is_empty():
		print("[cozyv2] cross-process PASS 2: nothing readable at %s  [FAIL]" % XPROC_PATH)
		return
	_apply_world(d)

	var st: CozyNpcState = npc.npc_state
	var chest := _first_object("chest")
	var wood := -1.0
	if chest != null and chest.container != null:
		wood = chest.container.inventory.count("wood")

	# Found by position, not by count — see XPROC_MARK_A.
	var marker := false
	for ws in building.state.walls:
		if ws.start.distance_to(XPROC_MARK_A) < 0.01 \
				and ws.end.distance_to(XPROC_MARK_B) < 0.01:
			marker = true

	var ok := st != null \
		and absf(st.hunger - XPROC_HUNGER) < 0.001 \
		and absf(st.energy - XPROC_ENERGY) < 0.001 \
		and clock.day == XPROC_DAY \
		and absf(wood - XPROC_WOOD) < 0.001 \
		and marker
	print("[cozyv2] cross-process PASS 2 loaded over a fresh world (fresh: %d wall(s), hunger %d): npc %d/%d, day %d, wood %.0f, marker wall=%s  [%s]" % [
		fresh_walls, int(fresh_hunger),
		int(st.hunger) if st != null else -1, int(st.energy) if st != null else -1,
		clock.day, wood, str(marker),
		"OK" if ok else "FAIL, the reopened game did not match"])


func save_game(path := CozySaveManager.DEFAULT_PATH) -> bool:
	var ok := CozySaveManager.save_world(_world_to_dict(), path)
	_say("saved" if ok else "save FAILED (see the log)", not ok)
	return ok


func load_game(path := CozySaveManager.DEFAULT_PATH) -> bool:
	var d := CozySaveManager.load_world(path)
	if d.is_empty():
		_say("no readable save at %s" % path, true)
		return false
	_apply_world(d)
	_say("loaded")
	return true


## Save / load (V2-26).
##
## Two separate claims need proving, and they fail independently:
##   1. the FACTS survive the round trip (serialisation)
##   2. the DERIVED layers come back from those facts (regeneration)
## A save system can pass the first and fail the second, which is precisely what
## doc #63's "store facts, not results" rule exists to avoid.
##
## It also EXECUTES the load path on the live world and then puts the world back.
## A load that is written but never run is the "declared capability with no
## consumer" shape this project has now paid for twice — the chest's unanswered
## `store` point (V2-21) and the orphaned resident panel (UI-02).
func _check_save_load() -> void:
	# Seed the chest first. A round trip that only ever carries an EMPTY container
	# proves nothing about contents: the check has to have something to lose.
	var chest := _first_object("chest")
	if chest != null and chest.container != null:
		chest.container.inventory.items.clear()
		chest.container.inventory.add("wood", 12.0)
		chest.container.inventory.add("stone", 4.0)

	var before := _world_to_dict()
	var path := "user://selfcheck.json"

	# (0) It has to actually reach the disk. A serialiser that only ever runs in
	# memory would pass every check below while writing a file nothing can read.
	var wrote := CozySaveManager.save_world(before, path)
	if not wrote:
		print("[cozyv2] save/load: could not write %s  [FAIL]" % path)
		return
	var loaded := CozySaveManager.load_world(path)
	if loaded.is_empty():
		print("[cozyv2] save/load: wrote %s but could not read it back  [FAIL]" % path)
		return
	print("[cozyv2] save/load: %d byte(s) survived the disk  [OK]" % [
		FileAccess.get_file_as_string(path).length()])

	# (1) Terrain.
	var t := CozyTerrainSystem.new()
	t.from_dict(loaded.get("terrain", {}))
	var terrain_ok := t.describe() == terrain.describe()
	print("[cozyv2] save/load terrain: %s  [%s]" % [
		t.describe(), "OK" if terrain_ok else "FAIL"])

	# (2) Building — the reason this block exists.
	# Walls, SLABS and STAIRS are all authored state. Until this block to_dict
	# stored only walls, so a load silently dropped the floors and the staircase,
	# and nothing caught it because nothing consumed the function.
	var b := CozyBuildingState.new()
	b.from_dict(loaded.get("building", {}))
	var openings := 0
	for w in b.walls:
		openings += w.openings.size()
	var live_openings := 0
	for w in building.state.walls:
		live_openings += w.openings.size()
	var building_ok := b.walls.size() == building.state.walls.size() \
		and b.slabs.size() == building.state.slabs.size() \
		and b.stairs.size() == building.state.stairs.size() \
		and openings == live_openings
	print("[cozyv2] save/load building: %d wall(s) / %d slab(s) / %d stair(s) / %d opening(s)  [%s]" % [
		b.walls.size(), b.slabs.size(), b.stairs.size(), openings,
		"OK" if building_ok else "FAIL"])

	# (3) Objects, and the contents of the container inside one.
	var live_objs: Array = before.get("objects", [])
	var back_objs: Array = loaded.get("objects", [])
	var object_ok := back_objs.size() == live_objs.size() and not back_objs.is_empty()
	var container_note := "no container"
	if object_ok:
		for i in back_objs.size():
			var a: Dictionary = live_objs[i]
			var z: Dictionary = back_objs[i]
			if String(a.get("def_id", "")) != String(z.get("def_id", "")):
				object_ok = false
			if a.has("container") != z.has("container"):
				object_ok = false
			elif a.has("container"):
				var ca: Dictionary = a["container"]
				var cz: Dictionary = z["container"]
				container_note = "%s/%.0f" % [
					JSON.stringify(cz.get("items", {})), float(cz.get("capacity", 0.0))]
				if absf(float(ca.get("capacity", 0.0))
						- float(cz.get("capacity", 0.0))) > 0.001:
					object_ok = false
				if JSON.stringify(ca.get("items", {})) \
						!= JSON.stringify(cz.get("items", {})):
					object_ok = false
	print("[cozyv2] save/load objects: %d object(s), container %s  [%s]" % [
		back_objs.size(), container_note, "OK" if object_ok else "FAIL"])

	# (4) The resident.
	var live_npc: CozyNpcState = npc.npc_state
	var npcs: Array = loaded.get("npcs", [])
	var npc_ok := false
	var npc_note := "no resident in the file"
	if not npcs.is_empty() and live_npc != null:
		var n := CozyNpcState.from_dict(npcs[0])
		npc_ok = n.id == live_npc.id and n.display_name == live_npc.display_name \
			and n.job_id == live_npc.job_id \
			and absf(n.hunger - live_npc.hunger) < 0.001 \
			and absf(n.energy - live_npc.energy) < 0.001 \
			and n.skill("research") == live_npc.skill("research")
		npc_note = "%s \"%s\" %s" % [n.id, n.display_name, n.job_id]
	print("[cozyv2] save/load resident: %s  [%s]" % [
		npc_note, "OK" if npc_ok else "FAIL"])

	print("[cozyv2] save/load round-trip: terrain=%s building=%s object=%s npc=%s  [%s]" % [
		str(terrain_ok), str(building_ok), str(object_ok), str(npc_ok),
		"OK" if terrain_ok and building_ok and object_ok and npc_ok else "FAIL"])

	# The terrain system is a Node3D and nothing else will free it. The building
	# state is RefCounted — calling free() on it is an engine error, so it is
	# released simply by going out of scope.
	t.free()

	# (5) Now run the real load path against the live world. Everything above
	# proves the serialisers; only this proves the generators rebuild from facts.
	var walls_before := building.state.wall_count()
	var objs_before := objects.size()
	var rooms_before := floor_system.all_rooms().size()

	_apply_world(loaded)
	var applied := building.state.wall_count() == walls_before \
		and objects.size() == objs_before \
		and floor_system.all_rooms().size() == rooms_before \
		and npc.npc_state != null and npc.npc_state.id == live_npc.id \
		and building.state.stairs.size() > 0
	print("[cozyv2] save/load applied live: %d wall(s), %d slab(s), %d stair(s), %d room(s), %d object(s)  [%s]" % [
		building.state.wall_count(), building.state.slabs.size(),
		building.state.stairs.size(), floor_system.all_rooms().size(), objects.size(),
		"OK" if applied else "FAIL"])

	# (6) Put the world back and prove THAT round trip too — a check that leaves
	# the scene different from how it found it corrupts every check after it.
	_apply_world(before)
	var restored := building.state.wall_count() == walls_before \
		and objects.size() == objs_before \
		and floor_system.all_rooms().size() == rooms_before
	print("[cozyv2] save/load restores the world it found: %d wall(s), %d object(s)  [%s]" % [
		building.state.wall_count(), objects.size(),
		"OK" if restored else "FAIL"])

	CozySaveManager.erase(path)
	var chest2 := _first_object("chest")
	if chest2 != null and chest2.container != null:
		chest2.container.inventory.items.clear()


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

## Schedule and needs (V2-25, doc #114-#116, 愿景 §10).
##
## The point of this block was to make V2-22's data MOVE, and to give the ten
## traits something to actually affect — until now they were stored numbers
## nothing read. Both are asserted here rather than assumed.
func _check_schedule_and_needs() -> void:
	# doc #114's own day: the schedule must resolve differently at different hours.
	var slots: Array[String] = [
		CozySchedule.activity_at(3.0), CozySchedule.activity_at(9.0),
		CozySchedule.activity_at(12.0), CozySchedule.activity_at(23.0)]
	var varied: bool = slots[0] != slots[1] and slots[1] != slots[2] and slots[2] != slots[3]
	print("[cozyv2] schedule: 03:00=%s 09:00=%s 12:00=%s 23:00=%s  [%s]" % [
		slots[0], slots[1], slots[2], slots[3],
		"OK" if varied and slots[0] == "sleep" and slots[1] == "work" else "FAIL"])

	# The schedule resolves to a POINT TYPE, never to an object (doc #115).
	var work_point := CozySchedule.point_for("work")
	var sleep_point := CozySchedule.point_for("sleep")
	print("[cozyv2] schedule resolves to point types: work->%s sleep->%s  [%s]" % [
		work_point, sleep_point,
		"OK" if work_point == "work" and sleep_point == "sleep" else "FAIL"])

	# Needs decay, and sleep is the only thing that restores energy.
	var s1 := CozyNpcState.create("n1", "N", "researcher", 7)
	s1.traits = []
	s1.hunger = 0.0
	s1.energy = 100.0
	s1.tick(4.0, "work")
	var decayed := s1.hunger > 0.0 and s1.energy < 100.0
	var before_sleep := s1.energy
	s1.tick(4.0, "sleep")
	print("[cozyv2] needs: hunger 0->%d, energy 100->%d->%d(sleep)  [%s]" % [
		int(s1.hunger), int(before_sleep), int(s1.energy),
		"OK" if decayed and s1.energy > before_sleep else "FAIL"])

	# A critical need overrides the schedule (doc #116).
	s1.energy = 5.0
	var urgent := s1.critical_need()
	print("[cozyv2] critical need at energy 5: %s  [%s]" % [
		urgent if urgent != "" else "(none)", "OK" if urgent == "sleep" else "FAIL"])

	# THE PAYOFF FOR THE TRAITS: until this block they were stored values that
	# nothing consumed. Two residents, same hour, one of them Gourmet.
	var plain := CozyNpcState.create("p", "Plain", "researcher", 11)
	plain.traits = []
	var gourmet := CozyNpcState.create("g", "Gourmet", "researcher", 12)
	gourmet.traits = ["gourmet"]          # hunger_rate 1.2
	plain.hunger = 0.0
	gourmet.hunger = 0.0
	plain.tick(3.0, "work")
	gourmet.tick(3.0, "work")
	print("[cozyv2] trait effect is live: hunger plain=%d gourmet=%d  [%s]" % [
		int(plain.hunger), int(gourmet.hunger),
		"OK" if gourmet.hunger > plain.hunger else "FAIL, trait is inert"])


## Outdoor navigation (the gap V2-25 exposed).
##
## Before this the navigator fell back to a straight line outdoors, so a route
## from the front of the house to a point behind it walked THROUGH the house.
## The schedule hit it and the NPC sat at `blocked, replanning`.
##
## Asserted three ways, because "a path exists" is the weakest of them and would
## have passed even with the bug present.
func _check_outdoor_nav() -> void:
	var nav: CozyLocalNav = _nav_by_room.get(CozyRoomGraph.OUTDOORS)
	if nav == null:
		print("[cozyv2] outdoor nav: NOT BUILT  [FAIL]")
		return

	# In front of the door, to a point behind and west of the house. The straight
	# line between them crosses the building.
	var from := Vector2(3.25, -3.0)
	var to := Vector2(-3.0, 8.0)
	var path := nav.find_path(from, to)
	var walked := CozyLocalNav.path_length(path)
	var straight := from.distance_to(to)

	# The decisive check: no waypoint may sit INSIDE the house. "A path exists"
	# would have passed with the straight-line fallback still in place.
	var inside := 0
	for p in path:
		if p.x > 0.5 and p.x < 7.5 and p.y > 0.5 and p.y < 5.5:
			inside += 1

	print("[cozyv2] outdoor route front->back: %.1f m walked vs %.1f m straight, %d pt(s) inside the house  [%s]" % [
		walked, straight, inside,
		"OK" if path.size() > 0 and inside == 0 and walked > straight * 1.15 else "FAIL"])
	print("[cozyv2] outdoor grid: %d cell(s) at %.2f m, %d obstacle(s)" % [
		nav.blocked_cell_count(), OUTDOOR_CELL, nav.obstacle_count()])


func _check_room_at(pos: Vector3, expected: String) -> void:
	var r := floor_system.room_at(pos)
	var got := r.id if r != null else "outdoors"
	print("[cozyv2] room_at(%s) -> %s  [%s]" % [
		pos, got, "OK" if got == expected else "FAIL, expected " + expected])


## Is there a door portal joining these two spaces? Ids are generated from the
## wall that carries the opening, so matching on the connection is both more
## meaningful and less brittle than naming one.
func _check_door_between(expect_a: String, expect_b: String) -> void:
	var want_a := expect_a if expect_a != "" else "outdoors"
	var want_b := expect_b if expect_b != "" else "outdoors"
	for p in floor_system.all_portals():
		if p.kind != CozyPortal.Kind.DOOR:
			continue
		var a := p.a_room if p.a_room != "" else "outdoors"
		var b := p.b_room if p.b_room != "" else "outdoors"
		if (a == want_a and b == want_b) or (a == want_b and b == want_a):
			print("[cozyv2] door portal %-14s %s <-> %s  [OK]" % [p.id, a, b])
			return
	print("[cozyv2] door portal %s <-> %s: NONE FOUND  [FAIL]" % [want_a, want_b])


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


func _check_route_kinds(from_id: String, to_id: String, expect: Array) -> void:
	var route := room_graph.find_route(from_id, to_id)
	var got: Array = []
	for p in route:
		got.append(p.kind_name())
	var label := "(no route)" if got.is_empty() else " -> ".join(got)
	print("[cozyv2] route %-10s -> %-10s : %s  [%s]" % [
		CozyRoomGraph.display_name(from_id), CozyRoomGraph.display_name(to_id), label,
		"OK" if got == expect else "FAIL, expected %s" % str(expect)])


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

	# The clock, finally visible. The resident's entire day is scheduled off it —
	# they sleep at 22:00 and eat at 12:00 — and the player had no way to tell
	# what time it was.
	hud.set_clock("Day %d  %s  %s" % [
		clock.day, clock.hh_mm(), clock.season().capitalize()])

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
