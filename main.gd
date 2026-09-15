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

## What navigation keeps clear of everything solid: the agent's own radius.
##
## Read from the character rather than written down here, because the number that
## matters is the COLLIDER's. A nav grid that disagrees with the collider is a
## resident that walks at a gap and stops, which is what `test_local_nav.gd`
## measured and what this constant exists to prevent.
const NAV_CLEARANCE := CozyCharacter.CAPSULE_RADIUS

## Half a wall, added for the ROOM POLYGON only. Room polygons run through wall
## CENTRELINES (an 8 x 6 room measures 48.0 m2), so without it the grid's edge is
## the middle of a wall and the collider disagrees about the rest of it.
const NAV_WALL_REACH := WALL_T * 0.5

## Stairwell: the upper slab leaves a hole from WELL_X0 to WELL_X1 in x, and from
## WELL_Z0 to the south wall in z. The ramp tops out at WELL_X1 and the rest is a
## landing, so an agent arrives on level floor instead of stepping off into a wall.
##
## BOTH VALUES MOVED WEST BY 1.0 m ON 2026-09-14, and the RUN IS UNCHANGED
## (WELL_X1 - WELL_X0 is still 2.5 m, so the stair is still 50.2 degrees). What
## changed is the landing: it was `HOUSE_W - WELL_X1` = 1.0 m, and navigation had
## just learned to keep the agent's width clear. Half a wall (0.125) plus the
## agent's radius (0.3) plus the cell the grown stairwell obstacle claims left
## `walkable=false` — the stair topped out on floor nothing could stand on, and
## the ONLY thing that noticed was a new assertion written for it.
##
##     npc plan ground->upstairs: 33 waypoints, crosses floor=true  [OK]   <- green
##     landing beside the stairwell: 1.00 m of floor, walkable=false [FAIL]
##
## The old green was a straight-line fallback: `find_path` came back empty and
## `_local()` handed the agent a bee-line, which is a navigator that has stopped
## navigating while its assertion still says it crosses floors.
const WELL_X0 := 3.5
const WELL_X1 := 6.0
const WELL_Z0 := 3.0

## Is the house part of the world?
##
## ON, and it is a PREFAB. `_build_house()` is a hand-authored list of eight
## walls, three slabs and a stair — it never went through `CozyOutlineGenerator`,
## which is the "auto-generated" path Willow ruled out on 2026-09-14. What IS
## derived from it — the rooms, the portals, the room graph and the roof — is
## derived the way everything else here is, and none of those has a known bug:
##
##     outline guard: L-shape and square allowed=true       [OK]
##     door gap (walkable) open / door lintel (solid)       [OK]
##     roof over room_1_0: style=gable, 4 face(s), ridge=2  [OK]
##
## So the prefab is not a different mechanism, it is the same one with the input
## written down instead of drawn. What changed is the OTHER switch below: nothing
## draws walls while the game is running any more.
##
## OFF means the house is absent and the checks that measure it are parked. That
## state is worth keeping reachable — it is how the ground was cleared for the
## farming lane — and both directions are verified: false gives 89 OK, true gives
## 122 OK, both with 0 FAIL and 0 ERROR.
const HOUSE_ENABLED := true


## Can a wall be drawn while the game is RUNNING?
##
## OFF, and this single switch is the fix for debt 22 — not a workaround.
##
## Measured 2026-09-14 by differential experiment. A wall added AFTER the
## navigation was built, with a door cut into it, leaves the navigation grid
## routing through that door while the collider is solid at its centre:
##
##     cast through wall_010's door centre: SOLID
##     [FAIL, navigation has a hole the collider does not]
##
## A resident that paths through it walks into the wall, gets stuck, replans and
## never arrives — which is exactly the ten-hours-in-place this project has been
## describing as debt 22. Gating the live-rebuild test off took the resident's
## path from 2 crossings to 0, and nothing else about the run changed:
##
##     house ON, live-rebuild test running   -> path crosses geometry: 2 leg(s)
##     house ON, live-rebuild test gated off -> path crosses geometry: 0 leg(s)
##
## THE HOUSE DOES NOT TRIGGER IT, and that is the whole reason a prefab is the
## answer rather than a fix. Its door is cut at startup, before any navigation
## exists, and `door gap (walkable) open` has been green since V2-16. Only a wall
## that appears after the navigation does.
##
## Willow 2026-09-14: "别修了，我们直接换建筑逻辑，放一个预制房". Understood as:
## keep the house, stop generating buildings at runtime. So the two producers of
## runtime walls — the build palette and the live-rebuild test — are off, and the
## palette's two tools are parked rather than deleted.
##
## WHEN THIS GOES BACK ON, THE BUG IS BACK. Fixing the nav/collider disagreement
## for runtime-added openings is the price of player building, and it is recorded
## in `docs/INVARIANTS.md` so that turning this on is a decision rather than a
## rediscovery.
const BUILDING_ENABLED := false


## Where the game starts: in front of the door, on the south side of the house.
##
## The house's door is cut into the z = 0 wall, so the FRONT of the house faces
## -Z — and the locked camera has to be on that side, or the game opens on the
## back of the house with the whole building between the camera and the player.
## Measured 2026-09-12 (see `_check_opening_shot`).
##
## NOTE while `HOUSE_ENABLED` is false: the measurement above justifies yaw 180
## for a world that HAS that house. With no house there is no evidence for any
## particular yaw, so the camera is left exactly where it was rather than moved
## to a new guess — and changing the yaw would change `ground_forward()`, which
## is the controls. The reasoning is parked with the house; the value is not
## disturbed.
const SPAWN_POINT := Vector3(3.25, 0.2, -3.5)

## Where production art lives. EMPTY until real assets exist — that is the
## correct state (doc 58.1: "美术资源可以为空，系统不能依赖资源本身才能运行").
const ART_ROOT := "res://assets/art"

## Where the asset-library fixtures live. The loader takes a path rather than
## hard-coding one, so the test reads test data and production reads production.
const FIXTURE_ROOT := "res://tests/fixtures/art"

const SNAP_M := 0.25     ## Wall snapping — assistance, not a cage (#84).
const MIN_WALL_LEN := 0.5

## Physics-frame milestones. Note --quit-after counts *idle* frames, and under
## headless the physics tick advances at roughly half that rate, so the quit
## count is set well above these.
const AUTOPILOT_DONE_FRAME := 420
const NPC_CHECK_FRAME := 900

## When §45's live chain gets read.
##
## Later than `NPC_CHECK_FRAME` by design: the chain's first transfer was measured
## at frame 1372, so judging it at 900 read a chest the resident had not reached
## yet and called a working chain broken.
##
## ⚠️ AND THE CEILING IS NOT `--quit-after`. `--quit-after 4500` reaches physics
## frame **1883**, not 4500 — measured, and stable across runs on this machine.
## The two counters are not the same counter, and a stage numbered past the real
## ceiling never fires at all: the run reports `pending=production_chain` and the
## self-check's own schedule guard turns red. 1700 sits between the first transfer
## (1372) and that ceiling (1883) with room either side.
const PRODUCTION_CHAIN_FRAME := 1700

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
## The terrain tools, minus the two that edited HEIGHT.
##
## `dig` and `fill` are gone (Willow, 2026-09-14: heights can go). The ground is
## flat now, so a tool that raises or lowers it would change a number nothing
## draws — a dead button, which is a claim that something is there. The INTENTS
## are still in `CozyTerrainIntent` and the height field is still in the save;
## what is removed is the way to reach them, so nothing offers an edit that has
## no visible result.
##
## `clear` and `till` stay: both change the MATERIAL, which is what a tile is.
const TERRAIN_TOOLS: Array[String] = ["clear", "till"]
const BUILD_TOOLS: Array[String] = ["outline", "wall"]
const PLACE_TOOLS: Array[String] = ["research_table", "chest", "bed", "chair",
	"campfire"]

## The palette. `outline` and `wall` are the two tools that DRAW A WALL, which is
## the one act `BUILDING_ENABLED` exists to prevent — see above, and the bug is
## not in these buttons but in what they produce. The house is unaffected: it is
## authored at startup, not drawn.
const TOOL_GROUPS: Array = (
	[BUILD_TOOLS, TERRAIN_TOOLS, PLACE_TOOLS] if BUILDING_ENABLED
	else [TERRAIN_TOOLS, PLACE_TOOLS])

## The live resident's trade. §45's production chain runs on THIS one, so it is
## asserted against the real resident rather than a synthetic one — a chain that
## only ever runs inside an assertion is the "declared with no consumer" shape
## this project has already paid for three times.
const NPC_JOB := "cook"

## The three trades the world has resources for, in the order the checks walk
## them. One list, because two checks ask about the same three trades: whether
## each has somewhere to STAND (`_check_resource_chain`) and whether the resident
## would actually SEEK it (`_check_work_priority`). Two copies would drift, and
## the drift would look like one of the two passing.
const RESOURCE_TRADES: Array[String] = ["woodcutter", "miner", "farmer"]

## The starter sack in the chest, and the baseline the live chain is measured
## against. One constant, used both to fill the chest and to judge it — two
## numbers that have to agree are two numbers that will stop agreeing.
const STARTER_WHEAT := 8.0

## Seeds in the same chest, for the sowing leg. Kept apart from the wheat because
## they are different facts: wheat is what the oven eats, seed is what the FIELD
## eats, and a check that read one constant for both would hide a split.
const STARTER_SEED := 4.0

## The flat list the HOTKEYS index, and it MUST equal `TOOL_GROUPS` flattened.
##
## These are two hand-kept lists that have to agree, which is normally a bug
## waiting to happen: the HUD builds its buttons by flattening the groups, while
## the number keys index THIS list, so the day the two disagree a key press picks
## the wrong tool — silently. They cannot be one value, because the palette needs
## the group boundaries and the hotkeys need a flat index, so they are held
## together by the `hud tools` assertion, which flattens the groups and compares.
const TOOLS: Array[String] = (
	["outline", "wall", "clear", "till",
		"research_table", "chest", "bed", "chair", "campfire"] if BUILDING_ENABLED
	else ["clear", "till",
		"research_table", "chest", "bed", "chair", "campfire"])

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

## What the PLAYER owns: their own packing, separate from the village's.
##
## Two accounts on purpose (Willow 2026-09-15) — the resident economy runs
## itself, so a player whose money came out of the village's store would be
## watching a number go up rather than earning one. See `CozyPlayerState`.
var player_state: CozyPlayerState = null

## The player's pack, on screen. See `CozyPackPanel` for why it is only the pack.
var pack_panel: CozyPackPanel = null

## Everything alive that can be killed. A plain list rather than a group: there
## are a handful, the swing asks all of them once per active frame, and a group
## lookup would be a second way to ask the same question.
var monsters: Array[CozyMonster] = []

## Whether the attack button is down THIS frame. Set by the input handler and
## cleared after the tick, so a click that lands between two frames is still a
## click rather than a lost one.
var _attack_held := false
var npc: CozyNpcAgent = null

## Points that come from the GROUND rather than from an object (sowing).
##
## A second point source, NOT an entry in `objects`: that array is
## `Array[CozyWorldObject]` and six readers iterate it assuming a world object.
## Built once the terrain and the fields exist.
var ground_points: CozyGroundPoints = null
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

## Object ids are minted `obj_%03d`, the shape the building state already uses.
## The counter travels in the save (`next_ids`), because a load that reset it
## would immediately mint an id that already exists.
var _next_object_id := 1

## The entity index (Core Architecture V1.0, item 1). It answers the one question
## no single system could: "what is id X". Built once, after the systems it
## indexes exist; it PULLS from them on every query, so it cannot go stale.
var entities: CozyEntityRegistry = null

var floor_system: CozyFloorSystem = null
var room_graph: CozyRoomGraph = null
var world_navigator: CozyWorldNavigator = null
var local_nav: CozyLocalNav = null
var _nav_by_room: Dictionary = {}

## What the chest held when the world was built, so §45's live chain is judged
## against the world it actually got rather than against a constant.
var _starter_chest: Dictionary = {}
## Per-floor room cache, so an edit only re-derives its own floor (doc #33).
var _rooms_by_floor: Dictionary = {}

var build_mode := false
## Feedback shown in the HUD strip. Timed, so a confirmation clears itself and a
## refusal does not sit on screen forever after the situation has changed.
var _hud_message := ""
var _hud_message_warn := false
var _hud_message_until := 0.0
var tool_idx := 0

## Why the last placement was refused, or "" when it was not. The reason a
## refusal is a VALUE rather than a shrug: whoever asked can say what went wrong.
var last_placement_refusal := ""

## The last in-game hour growth was re-checked at. Growth is DERIVED from the
## clock, so nothing has to run per frame — only when the answer can have
## changed, which is at most once an hour.
var _last_growth_hour := -1

## The environment and the sun, kept so the clock can move them.
var world_env: Environment = null
var day_sun: DirectionalLight3D = null

## The day, in hours. Dawn and dusk are RAMPS rather than a switch: a world that
## goes from full sun to night between one hour and the next reads as a bug.
const DAWN := 5.0
const SUNRISE := 8.0
const SUNSET := 17.0
const DUSK := 20.0

## HOW DARK NIGHT GETS, and it is deliberately not very.
##
## Willow, 2026-09-14: "黑夜也不要太黑，有一点点月光就行了". So the floor is
## MOONLIGHT rather than black — the layout stays readable, colours stay
## distinguishable, and the lamps are warmth added on top of a scene you can
## already see rather than the only thing between you and a void. A survival game
## wants the dark to be a threat; a game about a village you are proud of does not.
const SKY_DAY := Color(0.53, 0.74, 0.92)
const SKY_NIGHT := Color(0.11, 0.13, 0.24)
const AMBIENT_DAY := Color(0.78, 0.82, 0.88)
const AMBIENT_NIGHT := Color(0.34, 0.37, 0.52)   ## Moonlight, cool and blue.
const SUN_ENERGY_DAY := 1.15
const SUN_ENERGY_NIGHT := 0.18
const SUN_COLOR_DAY := Color(1.0, 0.97, 0.90)
const SUN_COLOR_NIGHT := Color(0.62, 0.70, 0.95)


## How much daylight there is: 0 at night, 1 in the middle of the day.
##
## A PURE FUNCTION OF THE CLOCK, so it can be asked at any hour — which is how
## the assertion checks noon and midnight without waiting nine hours.
func _daylight() -> float:
	if clock == null:
		return 1.0
	var h := fmod(clock.hour, 24.0)
	if h <= DAWN or h >= DUSK:
		return 0.0
	if h < SUNRISE:
		return (h - DAWN) / (SUNRISE - DAWN)
	if h > SUNSET:
		return 1.0 - (h - SUNSET) / (DUSK - SUNSET)
	return 1.0


## Move the sky, the ambient and the sun with the clock, and tell every lamp how
## dark it is.
##
## RUNS EVERY FRAME, and that is affordable and honest: it is a pure function of
## the hour, so calling it sixty times a second and calling it once give the same
## answer — the property `INVARIANTS` demands of anything refreshed repeatedly.
## A per-hour version would make dusk arrive in steps.
func _light_the_world() -> void:
	if clock == null:
		return
	var light := _daylight()
	var dark := 1.0 - light

	if world_env != null:
		world_env.background_color = SKY_NIGHT.lerp(SKY_DAY, light)
		world_env.ambient_light_color = AMBIENT_NIGHT.lerp(AMBIENT_DAY, light)
		world_env.ambient_light_energy = lerpf(0.55, 1.0, light)
	if day_sun != null:
		day_sun.light_energy = lerpf(SUN_ENERGY_NIGHT, SUN_ENERGY_DAY, light)
		day_sun.light_color = SUN_COLOR_NIGHT.lerp(SUN_COLOR_DAY, light)

	for o in objects:
		if is_instance_valid(o):
			o.set_light_level(dark)
var _drag_active := false
var _drag_start := Vector3.ZERO
var _drag_end := Vector3.ZERO
var _preview: MeshInstance3D = null

## Points collected while drawing a building outline (world x, z).
var _outline_points := PackedVector2Array()
var _outline_preview: MeshInstance3D = null

var _clock := 0.0
var _is_headless := false
## The headless self-check's schedule (tests/self_check.gd). It owns WHICH stages
## exist and WHEN each is due; the checks themselves are still methods here.
## One stage used to need a boolean member AND an if-block below; now it needs a
## line in `_build_self_check()`.
var self_check: CozySelfCheck = null


func _ready() -> void:
	# Note: OS.has_feature("headless") is FALSE under --headless in Godot 4.7;
	# the display server name is the reliable check.
	_is_headless = DisplayServer.get_name() == "headless"
	if _is_headless:
		print("[cozyv2] headless self-check start")
	_build_environment()
	_build_clock()
	_build_self_check()
	_build_assets()
	_build_terrain()
	# The homestead starts on ground that has already been cleared. Without
	# this the terrain gate (doc #12) would refuse the very first wall.
	_prepare_starter_plot()
	_prepare_crop_ground()
	_paint_demo_path()
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

	# Parked, not removed — see HOUSE_ENABLED. The furniture below is NOT part of
	# the house: it is placed independently of it and every piece has a consumer.
	if HOUSE_ENABLED:
		_build_house()
	_place_initial_furniture()
	_place_resource_nodes()
	_place_monsters()
	_rebuild_spatial()
	# AFTER the crops are standing: the ground's points are derived from what is
	# already there, so a provider built before them would offer a sow point under
	# every crop. `_rebuild_spatial` above is also what makes the terrain they
	# stand on settled.
	_build_ground_points()
	# Roofs come after room detection: the generator needs the room polygon and
	# the floor elevations, and neither exists until _rebuild_spatial has run.
	_build_roofs()
	_build_scatter()
	_build_characters()
	# After every system that owns state, because it indexes all of them.
	_build_entity_registry()
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
	else:
		_maybe_arm_screenshot()


## `--cozy-shot <path>`: draw a few frames, save what the camera sees, quit.
##
## A MEASUREMENT, in the same spirit as the `--cozy-probe-*` flags: for anything
## about how the world LOOKS, the number to read is a picture. Everything the
## self-check asserts is about PLACEMENT — counts, fingerprints, standability —
## and none of it can tell the difference between a field of grass and a field of
## the same grass repeated until it reads as wallpaper. That distinction is the
## whole of what art is, and it was being argued about from memory.
##
## NOT headless: the dummy renderer draws nothing, so a screenshot needs a real
## device and a real window. That is why this is opt-in and why nothing arms it
## by default — see the GUI rule in CLAUDE.md.
##
## The delay is for the first frames, when shadows and the scatter are still
## settling; a picture of a half-built world is worse than no picture, because it
## looks like a bug in whatever was just changed.
const SHOT_FRAMES := 30

func _maybe_arm_screenshot() -> void:
	var args := OS.get_cmdline_user_args()
	var at := args.find("--cozy-shot")
	if at < 0 or at + 1 >= args.size():
		return
	var path := args[at + 1]
	_shot_frames_left = SHOT_FRAMES
	_shot_path = path
	print("[cozyv2] screenshot armed: %s after %d frame(s)" % [path, SHOT_FRAMES])

var _shot_frames_left := 0
var _shot_path := ""


## One frame of the screenshot countdown. True once the picture has been taken
## and the process is on its way out, so the normal update can be skipped.
func _tick_screenshot() -> bool:
	if _shot_frames_left <= 0:
		return false
	_shot_frames_left -= 1
	if _shot_frames_left > 0:
		return false
	var img := get_viewport().get_texture().get_image()
	var err := img.save_png(_shot_path)
	print("[cozyv2] screenshot %s: %s" % [
		"written" if err == OK else "FAILED (%d)" % err, _shot_path])
	get_tree().quit(0 if err == OK else 1)
	return true



func _build_clock() -> void:
	clock = CozyTimeSystem.new()
	add_child(clock)


# ---------------------------------------------------------------- self-check

## Register the self-check's stages. ONE LINE PER STAGE, and the order here is
## the order they are listed in, not the order they run — each fires on its own
## frame.
##
## Frames are PHYSICS frames. `--quit-after` counts idle frames, and the two
## diverge under a variable step, so a stage's frame is a measurement, not a
## round number someone liked.
##
## The frame each stage sits at is not arbitrary either:
##   * occlusion at 60 — the player is still outdoors with nothing in front of
##     them. It is the only moment that answer is unambiguous.
##   * the others wait for the systems they measure to have settled, which is
##     why the two autopilot-dependent ones sit far later.
func _build_self_check() -> void:
	self_check = CozySelfCheck.new()
	# Parked with the house, and gated rather than dropped so that the stage
	# comes back with it. Occlusion fades whatever stands between the camera and
	# the player, which here is always a wall or a slab; with no house there is
	# nothing to fade, and `opening shot at spawn: 0 opaque` is true for a reason
	# that has nothing to do with the camera being right.
	self_check.add("occlusion", 60, _check_occlusion,
		func() -> bool: return HOUSE_ENABLED)
	# Probe only. Gated on the flag so the baseline run never pays for it.
	self_check.add("occlusion_probe", 90, _probe_occlusion_sweep,
		func() -> bool: return _has_arg("--cozy-probe-occlusion"))
	self_check.add("vfx", 120, _check_vfx)
	self_check.add("character", 140, _check_character_visuals)
	# Probe only, and LATE: the thing it measures is a resident that has been
	# trying and failing for a while, which takes in-game minutes to produce.
	self_check.add("npc_pathing_probe", 1000, _probe_npc_pathing,
		func() -> bool: return _has_arg("--cozy-probe-npc-pathing"))
	# A STAGE, not a _report() check, and that is not a style choice: a physics
	# ray in _ready() sees bodies the physics server has not positioned yet. This
	# check first ran from _report() and reported a 0.5 m ray hitting a table at
	# (2, 3, 2) — the node's position, not the body's.
	self_check.add("outdoor_route", 180, _check_outdoor_route_is_walkable)
	self_check.add("landing", 190, _check_landing_is_walkable)
	self_check.add("entity_registry", 160, _check_entity_registry)
	self_check.add("outline", 1500, _check_outline_build)
	# Gated on BUILDING, not on the house. This test adds a dividing wall at
	# runtime with a door cut into it, which is the ONE thing measured to produce
	# the navigation hole the resident cannot path through. It is the test's own
	# wall that does it, not the house's — so it goes off with runtime building,
	# and the world stays one the resident can walk.
	self_check.add("live_rebuild", AUTOPILOT_DONE_FRAME, _run_live_rebuild_test,
		func() -> bool: return BUILDING_ENABLED)
	self_check.add("npc_work", NPC_CHECK_FRAME, _check_npc_work)
	# LATE, and later than `npc_work` on purpose. The chain needs the resident to
	# walk to the chest, come back, work, and walk there again; the FIRST transfer
	# measured on 2026-09-14 was at frame 1372, so a check at 900 read a chest the
	# resident had not touched yet and called a working chain broken. A stage that
	# fires before its subject exists is the same failure as a probe that fires at
	# the wrong moment, one level up.
	self_check.add("production_chain", PRODUCTION_CHAIN_FRAME,
		_check_production_chain_live)
	# Last, so it observes every stage above it. It is itself a stage, which is
	# what keeps a deliberately short run (`--quit-after 400`) honest: the report
	# simply never fires rather than failing on stages the run could not reach.
	# The schedule guard asserts that every registered stage RAN, so it cannot
	# fire before the latest of them. It sat at a hard 1600 and the moment a stage
	# was registered past that, the guard reported it pending and turned red on a
	# run where everything had in fact run — the check was measuring its own
	# position, not the schedule. Derived from the last stage now, so adding one
	# later cannot leave this behind again.
	self_check.add("schedule", PRODUCTION_CHAIN_FRAME + 60, _check_self_check)


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
	# Kept, because these three numbers are no longer a constant: `_light_the_world`
	# moves them with the clock.
	world_env = env

	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-52.0, -38.0, 0.0)
	sun.light_energy = 1.15
	sun.light_color = Color(1.0, 0.97, 0.90)
	sun.shadow_enabled = true
	add_child(sun)
	day_sun = sun


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
	assets.load_dir(ART_ROOT)


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
	# A starter sack of wheat, so §45's chain has its first link. `bake_bread`
	# needs wheat as an INPUT and nothing grows any yet — the farmer who would is
	# the next block, and until then a chain with no input source is a resident
	# standing at an empty chest.
	var chest := _place_object("chest", 6.6, 1.0, 0)
	if chest != null and chest.container != null:
		chest.container.inventory.add("wheat", STARTER_WHEAT)
		# AND A FEW SEEDS, for the same reason and one more. `sow_crop` consumes
		# one, and the only other source is a harvest — which needs a ripe crop,
		# which is 24 hours of world time away. A chain whose first link cannot be
		# supplied is a resident standing at an empty chest, and that is the exact
		# sentence the line above was written for.
		chest.container.inventory.add("seed", STARTER_SEED)
		# What the chain gets measured AGAINST — captured here, rather than
		# compared against the constant above. `STARTER_WHEAT` is what this line
		# puts in; the check has to know what actually ARRIVED, or a world that
		# starts empty reads as "8 - 0, so the resident took some".
		_starter_chest = chest.container.inventory.items.duplicate()
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


## The resource nodes the gathering trades work at (2026-09-14).
##
## These exist so that `chop`, `mine` and `harvest` are not just table rows: the
## jobs name a point type, an object has to OFFER one, and a resident has to be
## able to walk to it. Without a single tree in the world, `woodcutter` would be
## the eighth "declared capability with no consumer" this project has written.
##
## Placed by hand at fixed coordinates, the way the furniture is, and
## deliberately WEST and SOUTH of the door axis: the spawn-to-door line runs
## north along x = 3.25, and putting a grove across it would turn the walk every
## resident makes into a detour for no reason.
##
## NOT YET LINKED TO ANYTHING. A crop does not have to be on farmland, a tree is
## not one of `vegetation_scatter`'s 165 instanced trees, and nothing removes a
## node when it is worked. Those are the next steps; this one makes the
## vocabulary real, which has to happen first.
func _place_resource_nodes() -> void:
	# A small stand of trees, and a rock each side of it.
	_place_object("tree", -4.0, 1.0, 0)
	_place_object("tree", -6.0, 3.0, 0)
	_place_object("tree", -4.0, 5.5, 0)
	# Away from the crop row: a crop's interaction point sits 1.3 m in front of it,
	# and at (-8, -1.5) this rock's footprint swallowed the point of the westernmost
	# crop. The `standable` assertion is what noticed — a resource whose point is
	# inside something else is a resource nobody can work.
	_place_object("rock", -10.0, -4.0, 0)
	_place_object("rock", -7.0, 6.5, 0)
	# A row of crops, out where the ground is clear.
	_place_object("crop", -4.5, -3.0, 0)
	_place_object("crop", -6.0, -3.0, 0)
	_place_object("crop", -7.5, -3.0, 0)

	# A lamp post by the door and one inside, so the night has something to show.
	# The door is at x = 3.25 on the z = 0 wall, so the post stands just south of
	# it and lights the way in; the floor lamp sits where a person would put one.
	_place_object("lamp_post", 5.2, -1.6, 0)
	_place_object("floor_lamp", 1.2, 4.4, 0)

	# A stall, east of the door and clear of the crop row. A shop is a FIXTURE
	# rather than something the build tool offers: `market_stall` is deliberately
	# not in `PLACEABLE`, because a player who can put a shop anywhere is a
	# question about economy design and this is a question about whether buying a
	# seed works at all.
	_place_object("market_stall", 7.6, 2.2, 0)


## Break the ground the crops are going into: grass -> soil -> farmland.
##
## Two intents rather than one because the terrain system refuses to skip a step,
## which is the property `farming chain` asserts. A plot drawn as farmland over
## grass would till nothing at all, and the crops would then be refused by
## `ground_problem` — correctly, and with a reason that said why.
## A winding path, so the dual-grid corners have something to round.
##
## A RECTANGLE WOULD NOT SHOW THE TECHNIQUE, and that is why the field looked
## like it had none. Every corner of a rectangle is a right angle on a cell
## boundary, and the rounding only happens where a boundary TURNS — a straight
## run has a neighbour in the same material on both sides of the centre, so its
## corner test fails by design. A winding path turns constantly.
##
## Painted with CLEAR rather than a new material, because a path through grass is
## what a villager would wear into the ground and it needs no vocabulary of its
## own. Several overlapping brush strokes rather than one polygon: the shape
## should be lumpy, and a polygon would put back the straight runs this exists to
## avoid.
func _paint_demo_path() -> void:
	if terrain == null:
		return
	var route := [
		Vector2(6.2, -3.2), Vector2(8.4, -4.6), Vector2(10.8, -4.2),
		Vector2(12.6, -2.2), Vector2(12.2, 0.6), Vector2(13.4, 3.2),
		Vector2(11.6, 5.8), Vector2(9.0, 7.2), Vector2(6.2, 8.6),
		Vector2(3.0, 9.4), Vector2(-0.6, 8.2),
	]
	for p in route:
		terrain.apply_intent(CozyTerrainIntent.clear_brush(p, 0.85))
	_rebuild_terrain_surface()


## The world's monsters. A brigand carrying the steel sword, and two slimes.
##
## PLACED BY HAND for the same reason the resource nodes are: this is a test
## fixture with a shape, not a spawner. A spawner is a different question — where,
## how many, how often — and answering it before anything can be killed would be
## inventing a rule for a system with nothing in it.
func _place_monsters() -> void:
	for m in monsters:
		if is_instance_valid(m):
			m.queue_free()
	monsters.clear()
	for spec in [["brigand", -2.0, 9.5], ["slime", 10.5, 6.0], ["slime", 12.0, -3.0]]:
		var m := CozyMonster.new()
		m.setup(String(spec[0]))
		add_child(m)
		m.global_position = Vector3(float(spec[1]), 0.0, float(spec[2]))
		monsters.append(m)


func _prepare_crop_ground() -> void:
	if terrain == null:
		return
	# WIDENED 2026-09-15, and the crops did NOT move. The first field was
	# 5.0 x 2.4 m with three 1 x 1 m crops in a row across the middle — and a sow
	# point is one crop-sized square that must be clear of every crop standing
	# near it, because a new crop's own interaction point reaches out from its
	# body. Measured, with the check now in the self-check:
	#
	#     ground offers 0 sow point(s) on the starter field  [FAIL]
	#
	# Zero. A farmer could reap and never sow, which is the whole of what this
	# block was for. The field is the player's work rather than a demo prop, so it
	# grows and the three starter crops stay exactly where they were.
	var plot := PackedVector2Array([
		Vector2(-13.5, -7.5), Vector2(-3.5, -7.5),
		Vector2(-3.5, -1.8), Vector2(-13.5, -1.8)])
	terrain.apply_intent(CozyTerrainIntent.clear_polygon(plot))
	terrain.apply_intent(CozyTerrainIntent.till_polygon(plot))
	# THE SAME TAIL AS `_prepare_starter_plot`, for the same reason: `setup()`
	# already ran `rebuild_all()`, so an edit after it leaves the mesh stale and
	# the dirty marks pending. Pending marks are not harmless — `describe()`
	# reports them, and the save round-trip compares `describe()`.
	_rebuild_terrain_surface()


# ---------------------------------------------------------------- entities

## The entity index (Core Architecture V1.0, item 1).
##
## ONE registration per kind, each a pair of lambdas over the system that already
## owns that state. No system was rewritten to become indexable, and no list is
## duplicated here: the providers read MEMBERS rather than capturing an Array, so
## a list that is ever replaced wholesale is still seen.
##
## Roofs register WITHOUT an encoder. They are entities with ids and are
## deliberately never saved, because they are derived from the rooms (doc #63) —
## the exclusion lives in the registration rather than in a filter at the save
## site, so a future derived kind cannot be saved by forgetting to skip it.
func _build_entity_registry() -> void:
	entities = CozyEntityRegistry.new()

	entities.register_kind(CozyEntityRegistry.WALL,
		func() -> Array: return building.state.walls,
		func(w) -> Dictionary: return building.state.wall_dict(w))
	entities.register_kind(CozyEntityRegistry.SLAB,
		func() -> Array: return building.state.slabs,
		func(s) -> Dictionary: return building.state.slab_dict(s))
	entities.register_kind(CozyEntityRegistry.STAIR,
		func() -> Array: return building.state.stairs,
		func(s) -> Dictionary: return building.state.stair_dict(s))
	entities.register_kind(CozyEntityRegistry.ROOF,
		func() -> Array: return building.state.roofs)
	entities.register_kind(CozyEntityRegistry.OBJECT,
		func() -> Array: return objects,
		func(o) -> Dictionary: return o.to_dict())
	entities.register_kind(CozyEntityRegistry.NPC,
		_resident_states,
		func(n) -> Dictionary: return n.to_dict())
	# The player's ledger is saved like anything else that OWNS state. An
	# inventory that a reload empties is worse than no inventory: the player
	# watches their afternoon's work disappear and has no way to tell whether the
	# game did it or they did.
	entities.register_kind(CozyEntityRegistry.PLAYER,
		_player_states,
		func(s) -> Dictionary: return s.to_dict())


## The residents, as a list the registry can pull like any other kind. A method
## rather than a lambda because the two null checks are the whole content of it.
func _resident_states() -> Array:
	if npc == null or npc.npc_state == null:
		return []
	return [npc.npc_state]


## The player's state, as a one-element list, for the same reason the residents
## are: the registry pulls a LIST per kind and this kind has exactly one member.
func _player_states() -> Array:
	return [] if player_state == null else [player_state]


func _place_object(def_id: String, x: float, z: float, floor_index: int) -> CozyWorldObject:
	if not CozyObjectDefs.exists(def_id):
		return null

	# THE GROUND GETS A SAY, and it says why when it refuses — the same question
	# `CozyBuildingSystem` asks for a wall, asked of a thing instead. A crop on
	# virgin grass is the case this exists for: `Grass -> Soil -> Farmland` has
	# been a chain since V2-11, and a crop could be dropped anywhere regardless.
	#
	# The refusal is SILENT (INVARIANTS: "the refusal is silent on purpose").
	# `last_placement_refusal` is where a caller reads it, and an assertion is
	# what notices; a line printed here would make `0 ERROR` a lie the way
	# `JSON.parse_string` did.
	#
	# Only floor 0 stands on terrain. An upper floor is a slab, and what a thing
	# needs from a slab is a question nothing has asked yet.
	if floor_index == 0 and terrain != null:
		var problem := CozyObjectDefs.ground_problem(def_id, terrain.material_id_at(x, z))
		if problem != "":
			last_placement_refusal = problem
			return null
	last_placement_refusal = ""

	var obj := CozyWorldObject.new()
	# The id first, so `setup()` and everything after it can be addressed by it.
	obj.id = "obj_%03d" % _next_object_id
	_next_object_id += 1
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
			nav.build(r, NAV_CLEARANCE, _obstacles_on_floor(r.floor_index),
				CozyLocalNav.CELL, NAV_WALL_REACH)
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
	# No `wall_reach` outdoors: the house is already an obstacle rect out here, so
	# there is no centreline polygon standing in for a wall.
	nav.build(r, NAV_CLEARANCE, _outdoor_obstacles(), OUTDOOR_CELL)
	_nav_by_room[CozyRoomGraph.OUTDOORS] = nav


## Everything built, as axis-aligned footprints the outdoor grid must route
## around.
##
## A wall contributes its bounding box: exact for the axis-aligned walls this
## project builds, conservative for a diagonal one. Over-blocking is the safe
## direction — an agent walking a slightly longer way is a nuisance, an agent
## walking through a wall is a defect.
##
## THE PARTS ARE ADDED SEPARATELY, ON PURPOSE, and this is worth reading before
## changing: the call below deliberately uses the STATIC helper, which returns
## only the stairwell, and walls, slabs and objects are then appended by hand.
## A room's grid instead goes through `_obstacles_on_floor`, which folds the
## objects in for it.
##
##   `_static_obstacles_on_floor(f)`  -> stairwell only
##   `_obstacles_on_floor(f)`         -> the above, PLUS every object on floor f
##
## READ THE WHOLE FUNCTION BEFORE "FIXING" THAT. On 2026-09-14 the first line was
## read, the objects were declared missing, and switching the helper made them
## arrive twice — thirteen duplicate rects, an obstacle count that went 23 to 36,
## and no behaviour change at all, because the loop at the bottom had been adding
## them the whole time. Mutation testing is what exposed it: reverting the
## "fix" turned nothing red.
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
	player.global_position = SPAWN_POINT

	# THE PLAYER'S OWN LEDGER, and a DIFFERENT OBJECT from the village's
	# (`building.inventory`, built below and paying for walls). Two accounts is a
	# gameplay decision, not a data one — see `CozyPlayerState`. What keeps it
	# from silently becoming one account is `_check_player_ledger`, which chops a
	# tree and asserts the wood landed on exactly one side of the split.
	player_state = CozyPlayerState.new()

	# The NPC starts on the GROUND floor while its workstation is UPSTAIRS, so
	# its first job exercises the whole stack: local nav -> portal -> room graph
	# -> stairs -> local nav again (#111 / #112).
	npc = CozyNpcAgent.new()
	npc.setup("Researcher", Color(0.94, 0.76, 0.62), Color(0.78, 0.44, 0.42),
		Color(0.20, 0.14, 0.10), false)
	# The resident's data (V2-22). Everything about who they are lives here; the
	# node only reads it.
	# A COOK, so §45's production chain runs on the real resident rather than only
	# in an assertion. The trade decides the recipe (`CozyRecipeDefs.for_job`),
	# the recipe decides the goods, and `CozyJobDefs` decides which point type the
	# resident seeks — which is still `work`, so the doc #111 demo (cross the
	# ground floor, take the stairs, work upstairs) is unchanged.
	npc.npc_state = CozyNpcState.create("npc_001", "Alice", NPC_JOB, 20260911)
	npc.npc_state.move_speed = 3.5
	# Derived from the trade, never typed twice — so changing NPC_JOB cannot
	# leave the resident training a skill their job does not use.
	var trade_skill := CozyJobDefs.primary_skill(NPC_JOB)
	npc.npc_state.set_passion(trade_skill, CozySkills.Passion.INTERESTED)
	npc.npc_state.train(trade_skill, 6)
	# A starter larder and a starter sack of wheat. `bake_bread` needs wheat as an
	# INPUT, and nothing grows any yet — a chain whose first link cannot be
	# supplied would just be a resident standing at an empty chest.
	npc.npc_state.inventory.add("bread", 3.0)
	npc.uses_gravity = true
	npc.floor_max_angle = deg_to_rad(55.0)
	add_child(npc)
	npc.global_position = Vector3(6.0, 0.2, 1.5)
	npc.navigator = world_navigator
	npc.objects = objects
	npc.clock = clock
	# The second point source, and the way to leave something behind at a point.
	# Both INJECTED, like `navigator` and `clock`: the agent never reaches for the
	# world, which is what keeps it runnable in a test with no world at all.
	npc.ground = ground_points
	npc.place_object = _sow


## Build the ground's point source, once the terrain and the fields exist.
##
## ORDER MATTERS: `objects` is read on every query to find out what is already
## standing where, so the provider must exist after the crops are placed — and it
## is handed the SAME array `main` owns, by reference, so a crop placed later is
## seen without anything having to tell it.
func _build_ground_points() -> void:
	ground_points = CozyGroundPoints.new()
	ground_points.terrain = terrain
	ground_points.objects = objects
	add_child(ground_points)


## Leave a world object behind where work happened — the `spawns` half of a recipe.
##
## ONE PLACE, because three things have to happen together and forgetting the
## third is invisible: the object is placed (which mints its id, applies the
## ground rule and appends it to `objects`), navigation is rebuilt (an object
## blocks movement, and `_place_object` deliberately does not touch navigation —
## the furniture click path calls `_rebuild_spatial()` right after it for exactly
## this reason), and nothing else needs telling because the ground source reads
## `objects` live.
##
## Returns the new object, or null when the placement refused. The REFUSAL IS
## PROPAGATED rather than swallowed: `_produce` spends nothing unless this returns
## something, which is what keeps a failed planting from eating a seed.
func _sow(def_id: String, at: Vector3) -> Node3D:
	var o := _place_object(def_id, at.x, at.z, 0)
	if o == null:
		return null
	_rebuild_spatial()
	return o


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
	# Walls, roofs AND slabs fade. A roof that cannot fade hides the player, and
	# so does a slab: at a pitched camera a floor between the camera and anyone
	# under it hides them exactly the way a wall would (`slab.gd` says so, and
	# doc #57 is the reason). Slabs were left out of this list — see the note on
	# `CozyOcclusion.fadable_source`.
	#
	# The list is PULLED on every refresh rather than pushed here, because the
	# building system replaces views as the world changes and a push is a
	# snapshot: a roof that follows its room left a freed node in this list and
	# the live roof missing, so no roof ever faded.
	occ.fadable_source = _current_fadables
	occ.structural_source = _fade_structurally
	occlusion = occ


# ---------------------------------------------------------------- HUD

func _build_hud() -> void:
	hud = CozyHud.new()
	add_child(hud)
	hud.set_tool_groups(TOOL_GROUPS)
	hud.tool_selected.connect(_on_hud_tool_selected)
	# Opening a category is not always a HUD matter: the resident panel belongs to
	# the game. The bar says WHICH part of the game the player asked for; what that
	# part does is decided here.
	hud.category_selected.connect(_on_hud_category)

	menu = CozyContextMenu.new()
	add_child(menu)
	menu.action_chosen.connect(_on_menu_action)

	# The resident panel rides the HUD's CanvasLayer and is anchored to the right
	# edge, so it never covers the tool strip along the bottom. Offset bottom is
	# left equal to top: a PanelContainer grows to its content's minimum height,
	# and grow_vertical decides which way.
	pack_panel = CozyPackPanel.new()
	hud.add_child(pack_panel)
	pack_panel.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	pack_panel.offset_left = -CozyPackPanel.WIDTH - CozyUiTheme.GAP
	pack_panel.offset_right = -CozyUiTheme.GAP
	pack_panel.offset_top = CozyUiTheme.STRIP_H + CozyUiTheme.GAP
	pack_panel.visible = false

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
## A category was opened on the bottom bar.
##
## Only the ones with something behind them do anything, and the ones without say
## so on the bar itself — so this is a dispatch, not a place for rules.
func _on_hud_category(id: String) -> void:
	# The two categories with a panel. Each closes the other, because both are
	# anchored to the same corner and two panels in one corner is one panel with
	# its text on top of itself.
	if id == "people" and hud.category_open():
		_close_pack_panel()
		_open_npc_panel(npc)
	elif id == "inventory" and hud.category_open():
		_close_npc_panel()
		pack_panel.visible = true
	else:
		_close_npc_panel()
		_close_pack_panel()


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
	_update_hud()


## Everything that may fade when it blocks the followed character: the live wall,
## roof and slab views, and nothing else. `CozyOcclusion` asks for this on every
## refresh, so a rebuilt view is picked up the same frame and a replaced one
## cannot linger.
##
## Stairs are deliberately absent: `CozyStair.set_fade()` takes an alpha and
## ignores it, so listing them would add a "fadable" that never fades.
## The state behind a fadable, or null for one this rule has nothing to say
## about. Mirrors the type checks `_describe_fadable` makes, because the fade
## registry is deliberately generic and only these four kinds carry a floor.
func _fadable_state(f: Object) -> Object:
	if f is CozyWall:
		return (f as CozyWall).state
	if f is CozySlab:
		return (f as CozySlab).state
	if f is CozyStair:
		return (f as CozyStair).state
	if f is CozyRoof:
		return (f as CozyRoof).state
	return null


## The floor the followed character is standing on, or -1 when they are outdoors.
func _watched_floor() -> int:
	if player == null or floor_system == null:
		return -1
	var r := floor_system.room_at(player.global_position)
	return r.floor_index if r != null else -1


## Should this piece of the building be see-through because of where it is?
##
## Willow, 2026-09-14: on the ground floor, everything above should be
## transparent including the wall on this floor's camera side; on the first
## floor, the roof and the camera-side wall.
##
## THE RULE ONLY APPLIES INDOORS, and that is a decision rather than an
## oversight. Outside, "above my floor" is every wall of the house, and fading
## them all would make the building disappear whenever the player walks past it —
## which is a different request from seeing into the room you are standing in.
func _fade_structurally(f: Object) -> bool:
	var here := _watched_floor()
	if here < 0:
		return false
	var st := _fadable_state(f)
	if st == null:
		return false

	# Everything on a floor above the one the resident is standing on. This is
	# the ceiling, the upper walls and the roof at once, and it is what makes a
	# ground floor readable from a camera that is looking down at it.
	if int(st.floor_id) > here:
		return true

	# And the wall on the camera's side of the resident, on their own floor:
	# the one the camera is looking THROUGH to reach them.
	#
	# ONLY A WALL IS ASKED. A slab or a stair has no line to be on the wrong side
	# of. The first version instead asked whether the state HAD `start` and `end`
	# using GDScript's `in`, which does not answer that question for an Object —
	# so every wall was declined and the rule did nothing at all while looking
	# perfectly reasonable. Measured by running the probe: the fades were
	# byte-for-byte the same as before the rule existed.
	if int(st.floor_id) != here or not (f is CozyWall):
		return false
	return _camera_is_across(st)


## Is the camera on the far side of this wall from the resident?
##
## A wall in plan is a segment; the camera and the resident are each on one side
## of the line through it. Opposite sides means the wall is between them, and a
## wall between the camera and the resident is a wall the player cannot see past
## — whether or not the ray happens to find a piece of it.
func _camera_is_across(st: Object) -> bool:
	if camera == null or player == null:
		return false
	var a := Vector2(st.start.x, st.start.z)
	var b := Vector2(st.end.x, st.end.z)
	var mid := (a + b) * 0.5
	var d := b - a
	if d.length_squared() < 0.000001:
		return false
	var n := Vector2(-d.y, d.x)          # a normal to the wall, in plan
	var cam := Vector2(camera.global_position.x, camera.global_position.z)
	var who := Vector2(player.global_position.x, player.global_position.z)
	return signf((cam - mid).dot(n)) != signf((who - mid).dot(n))


func _current_fadables() -> Array:
	var out: Array = []
	out.append_array(building.wall_views)
	out.append_array(building.roof_views)
	out.append_array(building.slab_views)
	return out


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
			target["title"] = "Ground" + (" - %s" % cell.material_id if cell else "")
			entries.append({"id": "terrain_edit", "label": "Terrain edit",
				"hint": "dig / fill / clear the land under the cursor"})
			if cell:
				entries.append({"id": "terrain_clear", "label": "Clear here",
					"hint": "one brush stroke of CLEAR, exactly as the tool would do"})
		"wall":
			var ws: CozyWallState = probe["node"].state
			target["title"] = "Wall - %s" % ws.material_id
			entries.append({"id": "info", "label": "Info"})
			entries.append({"id": "remove", "label": "Remove wall"})
		"object":
			var o: CozyWorldObject = probe["node"]
			target["title"] = CozyObjectDefs.display_name(o.def_id)
			# WHAT THE PLAYER CAN DO HERE, read from the object's definition and
			# filtered by `CozyObjectDefs.PLAYER_VERBS` — the same list the
			# resource-chain check reads, so a verb offered here and wanted by
			# nobody cannot happen quietly.
			#
			# Right-click is already the world's selection gesture and this does
			# not take it away: the verb lives IN the menu, so "what is that?"
			# still works on a tree.
			#
			# THE ENTRIES COME FROM THE DEFINITION, NOT FROM THE LIVE POINTS, so a
			# spent node still says what could be done to it and the menu says WHY
			# it will not.
			var near := _within_reach(o)
			for verb in CozyObjectDefs.interaction_types(o.def_id):
				if not CozyObjectDefs.PLAYER_VERBS.has(verb):
					continue
				if CozyObjectDefs.is_stall(o.def_id):
					_trade_entries(entries, o, verb, near)
				elif not CozyRecipeDefs.for_point(verb).is_empty():
					entries.append({"id": "gather:%s" % verb,
						"label": _verb_label(verb),
						"hint": _gather_hint(o, verb, near),
						"disabled": not (near and o.is_available(_game_hours()))})
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
		_:
			if id.begins_with("gather:"):
				_gather_from(target["node"], id.trim_prefix("gather:"))
			elif id.begins_with("trade:"):
				_trade_with(target["node"], id.trim_prefix("trade:"))


# ---------------------------------------------------------------- fighting

const PLAYER_REACH := 1.6

## One tick of the player's swing, and whatever it touched.
##
## THE SOLVER OWNS THE TIMING. `CozyCombatSolver.step` IS the frame-data state
## machine — windup, active window, recovery, hitstop, combo — and this
## function's only job is to feed it a button and then ask whether the swing is
## in its active frames and has not already hit this target. Doing the timing here
## instead would be a second implementation of a thing that has its own tests.
func _tick_combat() -> void:
	if player_state == null or player == null:
		return
	var state: Dictionary = player_state.combat
	state["has_shield"] = player_state.has_shield()
	CozyCombatSolver.step(state, {"light": _attack_held})
	_attack_held = false
	if not CozyCombatSolver.wants_query(state):
		return
	_resolve_swing(state)


## Everything the active frames reach, hit ONCE.
##
## `has_hit` is the guard that keeps one swing from hitting the same target on
## every active frame — without it a six-frame window is six hits, and the damage
## a player sees would be six times what the frame data says.
func _resolve_swing(state: Dictionary) -> void:
	var damage := player_state.attack()
	for m in monsters:
		if not is_instance_valid(m) or m.is_dead():
			continue
		if CozyCombatSolver.has_hit(state, _monster_id(m)):
			continue
		if _flat_distance(player.global_position, m.global_position) > PLAYER_REACH:
			continue
		if not CozyCombatSolver.note_swing_landed(state, _monster_id(m)):
			continue
		var killed := m.take_damage(damage, player)
		_say("%s takes %d" % [CozyMonsterDefs.display_name(m.def_id), int(damage)])
		if killed:
			_kill_monster(m)


## A monster's identity to the solver. Its instance id is stable for the life of
## the object, and "already hit" is exactly a statement about that object.
func _monster_id(m: CozyMonster) -> String:
	return "monster:%d" % m.get_instance_id()


## Distance ON THE GROUND PLANE. A monster on a slope is not further away because
## of the slope, and a swing measured in 3D would miss anything standing at a
## different height.
func _flat_distance(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()


## Instance ids for dropped items, so two swords from two kills are two swords.
## A counter rather than a random suffix, because a file has to be able to name
## one and `CozyItemInstance` ids travel in the save.
var _next_item_id := 1


## Roll the table and hand the drops to whoever killed it.
##
## THE DROP GOES TO THE PLAYER'S OWN ACCOUNT, which is the two-ledger decision
## arriving at its point: a monster the player killed pays the player. Routing
## this into `building.inventory` would make the sword the village's.
##
## Three kinds, three destinations, and they are the three the roller produces:
## equipment becomes an INSTANCE and goes in the bag, materials go in the pack,
## and gold becomes the currency — `KIND_GOLD` has said "currency, which is not
## an item and has no row" since the table was written, and copper is now the only
## thing that sentence can mean.
func _kill_monster(m: CozyMonster) -> void:
	_say("%s falls" % CozyMonsterDefs.display_name(m.def_id))
	var table := CozyMonsterDefs.loot_table(m.def_id)
	if table != "":
		var rng := RandomNumberGenerator.new()
		rng.randomize()
		var rolled := CozyLootRoller.roll(table, rng, _next_item_id)
		_next_item_id = int(rolled["next_id"])
		_hand_out(rolled["drops"])
	if is_instance_valid(m):
		m.queue_free()


## Put a rolled drop list into the player's things, and say what was picked up.
##
## Split from the kill so the self-check can hand it a roll it made itself: the
## distribution is the roller's business and the destination is this one's, and a
## check that had to kill something to test the destination would be testing both
## at once.
func _hand_out(drops: Array) -> void:
	var got: Array[String] = []
	for drop in drops:
		var d: Dictionary = drop
		match String(d["kind"]):
			CozyLootRoller.DROP_EQUIPMENT:
				var item: CozyItemInstance = d["item"]
				if player_state.bag.add_item(item) < 0:
					_say("the bag is full, %s is left behind" % item.display_name(), true)
					continue
				got.append(item.display_name())
			CozyLootRoller.DROP_ITEM:
				player_state.pack.add(String(d["id"]), float(d["amount"]))
				got.append("%s x%d" % [String(d["id"]), int(d["amount"])])
			CozyLootRoller.DROP_GOLD:
				player_state.pack.add(CozyPrices.CURRENCY, float(d["amount"]))
				got.append("%d %s" % [int(d["amount"]),
					CozyMaterials.display_name(CozyPrices.CURRENCY)])
	if not got.is_empty():
		_say("picked up %s" % ", ".join(got))


# ------------------------------------------------- the player's work and trade

## The player works a resource node by hand.
##
## IT PAYS INTO `player_state.pack`, NOT INTO THE VILLAGE. That is the whole of
## the two-ledger decision (Willow 2026-09-15): the residents farm, cook and
## store on their own schedule without anyone watching, so the only goods the
## player can call their own are the ones they went and got. Routing this into
## `building.inventory` instead would be a one-word change that quietly turns the
## player into a spectator of their own economy — which is why the self-check
## chops one tree and asserts which side the wood landed on.
##
## The OUTPUT comes from `CozyRecipeDefs.for_point`, the same table the residents
## work from, so a tree that yields 3 wood yields 3 wood whoever fells it.
func _gather_from(o: CozyWorldObject, verb: String) -> void:
	if o == null or not is_instance_valid(o) or player_state == null:
		return
	var now := _game_hours()
	if not _within_reach(o):
		_say("too far away", true)
		return
	if not o.is_available(now):
		_say("%s is worked out" % CozyObjectDefs.display_name(o.def_id), true)
		return
	var recipe := CozyRecipeDefs.for_point(verb)
	if recipe.is_empty():
		return
	o.take_one(now)
	var outs: Dictionary = recipe.get("outputs", {})
	var got: Array[String] = []
	for id in outs:
		var n := float(outs[id])
		player_state.pack.add(String(id), n)
		got.append("%s x%d" % [String(id), int(n)])
	# The node goes back through the same refresh the residents' loop uses, so a
	# felled tree becomes a stump for the PLAYER by exactly the path it does for
	# an agent — one rule, two callers.
	if o.refresh_availability(now):
		_rebuild_spatial()
	_say("%s: %s" % [CozyObjectDefs.display_name(o.def_id), ", ".join(got)])


## One row per thing on the shelf: a `Buy` line and a `Sell` line for each.
##
## PAIRS RATHER THAN TWO SUBMENUS. The menu is a flat list of buttons and giving
## it a hierarchy to hold four rows would be a new widget for four rows. What the
## player reads is "Seed: buy 4, sell 1", which is the price table's own line.
##
## `disabled` carries the reason — too far, or not enough copper, or none to sell
## — and the hint says which, because a greyed button with no explanation reads
## as broken.
func _trade_entries(entries: Array, o: CozyWorldObject, verb: String, near: bool) -> void:
	for id in CozyPrices.SHELF:
		if not CozyPrices.has_price(String(id)):
			continue
		var buying := verb == CozyObjectDefs.INTERACT_BUY
		var price := CozyPrices.buy(String(id)) if buying else CozyPrices.sell(String(id))
		if price <= 0.0:
			continue
		var afford := CozyPrices.can_afford(player_state.pack, String(id), 1) if buying 			else player_state.pack.count(String(id)) >= 1.0
		entries.append({
			"id": "trade:%s:%s" % ["buy" if buying else "sell", String(id)],
			"label": "%s %s — %d %s" % [
				"Buy" if buying else "Sell", CozyMaterials.display_name(String(id)),
				int(price), CozyMaterials.display_name(CozyPrices.CURRENCY)],
			"hint": _trade_hint(o, String(id), buying, near, afford),
			"disabled": not (near and afford),
		})


func _trade_hint(o: CozyWorldObject, id: String, buying: bool, near: bool, afford: bool) -> String:
	if not near:
		return "stand closer to the %s" % CozyObjectDefs.display_name(o.def_id).to_lower()
	if not afford:
		return "not enough %s" % CozyMaterials.display_name(CozyPrices.CURRENCY).to_lower() 			if buying else "none to sell"
	var have := player_state.pack.count(CozyPrices.CURRENCY)
	return "you have %d %s" % [int(have), CozyMaterials.display_name(CozyPrices.CURRENCY)]


## Buy or sell one of something, at a stall.
##
## THE PURSE IS THE PLAYER'S, and the same argument as `_gather_from`: the
## village's account pays for walls, and a stall that took from it would let the
## player spend goods they never earned. `CozyPrices` takes the purse as an
## ARGUMENT rather than reaching for one, which is what makes that checkable
## instead of a convention.
func _trade_with(o: CozyWorldObject, spec: String) -> void:
	if o == null or not is_instance_valid(o) or player_state == null:
		return
	var parts := spec.split(":")
	if parts.size() != 2:
		return
	if not _within_reach(o):
		_say("too far away", true)
		return
	var buying := String(parts[0]) == "buy"
	var id := String(parts[1])
	var ok := CozyPrices.buy_from(player_state.pack, id, 1) if buying 		else CozyPrices.sell_to(player_state.pack, id, 1)
	if not ok:
		_say("that trade did not go through", true)
		return
	_say("%s %s x1 — %d %s" % [
		"bought" if buying else "sold", CozyMaterials.display_name(id),
		int(CozyPrices.buy(id) if buying else CozyPrices.sell(id)),
		CozyMaterials.display_name(CozyPrices.CURRENCY)])
	_update_hud()


## Is the player close enough to work this object by hand?
##
## Measured from the PLAYER, not from the mouse: the cursor can point at a tree
## on the far side of the field, and a rule that only checked the cursor would
## let a player fell the forest from their doorstep.
func _within_reach(o: CozyWorldObject) -> bool:
	if player == null or o == null or not is_instance_valid(o):
		return false
	var reach := CozyObjectDefs.reach_of(o.def_id)
	# The object's own SIZE counts: its centre can be a metre away while its body
	# is at your feet. Half the larger side, which is the same box the navigation
	# obstacle uses.
	var size: Vector2 = CozyObjectDefs.get_def(o.def_id).get("size", Vector2.ZERO)
	var a := player.global_position
	var b := o.global_position
	return Vector2(a.x - b.x, a.z - b.z).length() <= reach + size.length() * 0.5


func _verb_label(verb: String) -> String:
	match verb:
		CozyObjectDefs.INTERACT_CHOP:
			return "Chop"
		CozyObjectDefs.INTERACT_MINE:
			return "Mine"
		CozyObjectDefs.INTERACT_HARVEST:
			return "Harvest"
		_:
			return verb.capitalize()


## Why the verb is greyed out, or what it will produce. A disabled button with no
## tooltip is a button that looks broken.
func _gather_hint(o: CozyWorldObject, verb: String, near: bool) -> String:
	if not near:
		return "stand closer to the %s" % CozyObjectDefs.display_name(o.def_id).to_lower()
	if not o.is_available(_game_hours()):
		return "worked out for now"
	var recipe := CozyRecipeDefs.for_point(verb)
	if recipe.is_empty():
		return ""
	var parts: Array[String] = []
	var outs: Dictionary = recipe.get("outputs", {})
	for id in outs:
		parts.append("%s x%d" % [String(id), int(float(outs[id]))])
	return "yields %s" % ", ".join(parts)


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


func _close_pack_panel() -> void:
	if pack_panel != null:
		pack_panel.visible = false


## Called every frame the panel is open, for the same reason the resident
## panel is: a count that changed because something was bought is a count the
## player is looking at. There are a handful of rows, so this is a few label
## writes rather than a rebuild.
func _refresh_pack_panel() -> void:
	if pack_panel == null or not pack_panel.visible:
		return
	pack_panel.refresh(player_state)


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
		lines.append("%s - floor %d" % [ws.id, ws.floor_id])
		lines.append("%.1f m - %.2f m3 - %d block(s)" % [
			ws.length(), ws.volume(), node.block_count()])
		lines.append("%d opening(s)" % ws.openings.size())
	elif node is CozySlab:
		var ss: CozySlabState = node.state
		lines.append("%s - floor %d" % [ss.id, ss.floor_id])
		lines.append("%.1f x %.1f m, surface y=%.1f" % [
			ss.size.x, ss.size.z, ss.surface_y()])
	elif node is CozyRoof:
		lines.append("%s over %s" % [node.state.id, node.state.room_id])
		lines.append("style %s - %d face(s)" % [node.style_name(), node.face_count()])
	elif node is CozyStair:
		var st: CozyStairState = node.state
		lines.append("%s - floor %s" % [st.id, st.floor_span()])
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
			lines.append("material %s - %s" % [cell.material_id,
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
		"till":
			# No depth: farmland is flat ground. Tilling is a MATERIAL edit, not a
			# height edit, which is why it shares the tool row with clear/dig.
			intent = CozyTerrainIntent.till_brush(centre, TERRAIN_BRUSH)
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
		# PHYSICAL key, not logical: Godot reports Shift+1 as KEY_EXCLAMATION, so
		# matching on `keycode` silently loses every shifted hotkey.
		var digit_key: int = event.physical_keycode
		if digit_key == 0:
			digit_key = event.keycode
		if digit_key >= KEY_0 and digit_key <= KEY_9:
			var i := CozyHud.index_for_hotkey(digit_key - KEY_0, event.shift_pressed)
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

	if event is InputEventMouseButton:
		# LEFT IS THE SWING, and only outside build mode — in build mode it draws
		# the outline, and a click that both attacks and starts a wall does the
		# wrong one half the time.
		if event.button_index == MOUSE_BUTTON_LEFT and not build_mode:
			_attack_held = event.pressed
			return
		if event.pressed:
			if event.button_index == MOUSE_BUTTON_WHEEL_UP:
				camera.zoom_in()
			elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
				camera.zoom_out()


## Game hours since the world began, as one monotonically rising number.
##
## `hour` alone wraps every day, and a tree that takes 72 hours to come back would
## regrow every midnight. Growth cycles are lengths of time, so they need a clock
## that only goes forward.
func _game_hours() -> float:
	if clock == null:
		return 0.0
	return float((clock.day - 1) * CozyTimeSystem.HOURS_PER_DAY) + clock.hour


## Let the world grow, once an hour.
##
## ONCE AN HOUR, NOT ONCE A FRAME, and the reason is the same one that makes the
## growth itself derived: re-asking a question whose answer cannot have changed is
## work for nothing, and a refresh that runs at frame rate is the shape
## `INVARIANTS` warns about ("a per-frame refresh must be idempotent"). This one
## is idempotent AND rare.
##
## A save and a reload need nothing extra: the stage is a function of `worked_at`
## and the clock, both of which are saved.
func _grow_the_world() -> void:
	if clock == null:
		return
	var h := clock.hour_index()
	if h == _last_growth_hour:
		return
	_last_growth_hour = h
	var now := _game_hours()
	for o in objects:
		if is_instance_valid(o):
			o.refresh_availability(now)
	# The resident is told the hour too, because the node it works is taken from
	# at the moment the work finishes — and that moment is not an hour boundary.
	if npc != null and is_instance_valid(npc):
		npc.now_hours = now


func _process(delta: float) -> void:
	if _tick_screenshot():
		return
	_clock += delta
	_expire_message()
	_grow_the_world()
	_light_the_world()
	_handle_camera_keys(delta)

	if _is_headless:
		player.set_move_dir(_autopilot_dir())
		_run_headless_stages()
		if _has_arg("--cozy-probe-npc-pathing"):
			_watch_for_a_stuck_resident(delta)
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
	_refresh_pack_panel()
	_tick_combat()
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
## Run every stage that has come due. The schedule itself is data — see
## `_build_self_check()` for the table and `tests/self_check.gd` for the runner.
## Always fires, however the run ends.
##
## The assertion above can only report on a run that was long enough to reach it.
## This is what makes an over-budget stage VISIBLE instead of silent — which is
## the entire failure mode being guarded, so a report that shares the same blind
## spot would be decoration.
func _exit_tree() -> void:
	if not _is_headless or self_check == null:
		return
	var pending: Array[String] = []
	for name in self_check.required_names():
		if not self_check.has_run(name):
			pending.append(name)
	print("[cozyv2] self-check at exit: %s, never ran=%s" % [
		self_check.describe(),
		"none" if pending.is_empty() else ",".join(pending)])


func _run_headless_stages() -> void:
	self_check.run_due(Engine.get_physics_frames())


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

	_check_camera()
	_check_ui()
	_check_container()
	_check_eating()
	_check_production()
	_check_save_load()
	_check_assets()
	_check_scatter()
	_check_lights()
	_check_ground_tiles()
	_check_terrain()
	_check_farming_chain()
	_check_scatter_incremental()
	_check_resource_chain()
	_check_player_ledger()
	_check_trade()
	_check_pack_panel()
	_check_fight()

	_report_house()
	_report_runtime_building()


## What is off because a wall cannot be drawn while the game is running.
##
## Reported for the same reason the house checks are: two runs that differ only by
## a number are indistinguishable in a log, and the thing that must never happen is
## a run that measures less without saying so.
func _report_runtime_building() -> void:
	if BUILDING_ENABLED:
		return
	var parked: Array[String] = [
		"the build palette's %d tool(s) (%s)" % [BUILD_TOOLS.size(), ", ".join(BUILD_TOOLS)],
		"the live-rebuild stage, which adds a dividing wall at runtime",
	]
	print("[cozyv2] runtime building: PARKED, %d thing(s) NOT DONE (BUILDING_ENABLED=false): %s" % [
		parked.size(), ", ".join(parked)])


## Every gathering trade has somewhere to work, and a resident can walk there.
##
## This is the half of the resource vocabulary that a pure-logic suite cannot
## see. `tests/unit/test_resource_chain.gd` proves the three tables agree — every
## point offered is wanted and every point wanted is offered — but a table that
## agrees with itself still describes a world with no tree in it.
##
## "A declared capability with no consumer" is this project's most expensive
## mistake, and it has two halves: nobody reading the row, and nothing in the
## world to read. So this checks the second one.
##
## ASK THE GRID, NOT THE NAVIGATOR, and that is not a shortcut — it was found by
## mutation testing. `world_navigator.plan()` returns `[to]` for ANY outdoor
## target without consulting the outdoor grid at all (see `_local` in
## world_navigator.gd), so "a path exists" is true for a tree placed at
## (500, 500). The first version of this check did exactly that and a mutation
## that put a tree outside the world went green.
##
## The point an object offers is deliberately OUTSIDE its own footprint
## (`inside_own_footprint=false`), because it is where the resident stands — so
## the honest question is whether the grid says a body can stand there.
## The player's work pays into the player's account — and into nothing else.
##
## THE TWO-LEDGER DECISION IS ONLY REAL IF SOMETHING GUARDS IT. It is one word in
## `_gather_from` — `player_state.pack.add(...)` against `building.inventory.add`
## — and the two containers have the same shape, the same method names and the
## same units, so a wrong call is invisible: the wood appears, the count goes up,
## and the player's goods have silently become the village's. Nothing else in the
## game can tell those two worlds apart.
##
## So the check CHOPS A REAL TREE with the real player and asserts which side the
## wood landed on, and then asserts the OTHER side did not move.
##
## It also gives the reach rule teeth, by standing out of range FIRST. A check
## that only ever stands in the right place has said nothing about the places the
## game refuses — the same reason `_check_resource_chain` measures reachability
## from a tree someone actually placed.
func _check_player_ledger() -> void:
	if player_state == null or player == null or building == null:
		print("[cozyv2] player ledger: no player state to check  [FAIL]")
		return

	# (1) Two accounts, two objects. The cheapest half of the decision and the
	#     one that a future "let us just share the village store" refactor would
	#     break first.
	var distinct := player_state.pack != building.inventory
	print("[cozyv2] player ledger is its own account, not the village's: %s  [%s]" % [
		str(distinct), "OK" if distinct else "FAIL, the player's goods ARE the village's"])

	var tree := _first_object("tree")
	if tree == null:
		print("[cozyv2] player ledger: no tree in the world to chop  [FAIL]")
		return

	# Everything below MUTATES the world, so everything is put back at the end.
	var village_before: Dictionary = building.inventory.items.duplicate()
	var pack_before: Dictionary = player_state.pack.items.duplicate()
	var tree_taken := tree.taken
	var tree_worked := tree.worked_at
	var here := player.global_position
	# `for_point` hands back the RECIPE ROW, which does not carry its own id --
	# `CozyRecipeDefs.outputs(id)` takes an id, so the row's own `outputs` is
	# what to read. Reaching for `row["id"]` is an error rather than a null.
	var want: Dictionary = CozyRecipeDefs.for_point(
		CozyObjectDefs.INTERACT_CHOP).get("outputs", {})

	# (2) Out of range first: the reach is measured from the PLAYER, not from the
	#     mouse, so pointing at a distant tree must not fell it.
	player.global_position = tree.global_position + Vector3(0.0, 0.0, 25.0)
	_gather_from(tree, CozyObjectDefs.INTERACT_CHOP)
	var refused_far := tree.taken == tree_taken

	# (3) In range.
	player.global_position = tree.global_position
	_gather_from(tree, CozyObjectDefs.INTERACT_CHOP)
	var took := tree.taken == tree_taken + 1

	var got := 0.0
	for id in want:
		got += player_state.pack.count(String(id))
	var expected := 0.0
	for id in want:
		expected += float(want[id])

	var village_still := true
	for id in village_before:
		if not is_equal_approx(building.inventory.count(String(id)),
				float(village_before[id])):
			village_still = false
	# And it did not merely take from one and give to the other under the same
	# names: the village must have GAINED nothing either.
	var village_total_before := 0.0
	for id in village_before:
		village_total_before += float(village_before[id])
	var village_total_after := building.inventory.total()

	print("[cozyv2] player chopped a tree: refused out of range=%s, took=%s, pack +%.0f (wanted %.0f), village %s (%.0f -> %.0f)  [%s]" % [
		str(refused_far), str(took), got, expected,
		"untouched" if village_still and is_equal_approx(
			village_total_after, village_total_before) else "MOVED",
		village_total_before, village_total_after,
		"OK" if refused_far and took and is_equal_approx(got, expected)
			and village_still and player_state.pack.count(
				String(want.keys()[0])) > 0.0
			else "FAIL, the player's work did not land on exactly one side of the split"])

	# (4) Put the world back. The tree, the pack, the player, and the navigation
	#     the gather refreshed.
	tree.taken = tree_taken
	tree.worked_at = tree_worked
	tree.refresh_availability(_game_hours())
	player_state.pack.items = pack_before
	player.global_position = here
	_rebuild_spatial()


## Buying and selling move the player's purse and the shelf — and nothing else.
##
## The price table is pure and its one hard rule (buy > sell) is a unit test, so
## what is left for the world to prove is the two things pure code cannot: that
## the stall is somewhere the player can actually stand, and that a trade touches
## the PLAYER'S account rather than the village's. `CozyPrices` takes the purse as
## an argument, which is what makes that a fact rather than a convention.
##
## The fiction is arranged rather than stumbled into: the player is handed copper
## and wheat, trades, and is put back exactly as they were. A trade test that
## needed the player to go and earn something first would depend on where the
## trees are.
func _check_trade() -> void:
	if player_state == null or player == null:
		print("[cozyv2] trade: no player state to check  [FAIL]")
		return
	var stall := _first_object("market_stall")
	if stall == null:
		print("[cozyv2] trade: no stall in the world to trade at  [FAIL]")
		return

	var pack_before: Dictionary = player_state.pack.items.duplicate()
	var village_before := building.inventory.total()
	var here := player.global_position

	player_state.pack.items.clear()
	player_state.pack.add(CozyPrices.CURRENCY, 100.0)
	player_state.pack.add("wheat", 2.0)
	var purse := player_state.pack.count(CozyPrices.CURRENCY)

	# Out of range first, so the reach rule has teeth here too.
	player.global_position = stall.global_position + Vector3(0.0, 0.0, 25.0)
	_trade_with(stall, "buy:seed")
	var refused_far := is_equal_approx(
		player_state.pack.count(CozyPrices.CURRENCY), purse)

	player.global_position = stall.global_position
	_trade_with(stall, "buy:seed")
	var bought := is_equal_approx(player_state.pack.count("seed"), 1.0) 		and is_equal_approx(player_state.pack.count(CozyPrices.CURRENCY),
			purse - CozyPrices.buy("seed"))

	_trade_with(stall, "sell:wheat")
	var sold := is_equal_approx(player_state.pack.count("wheat"), 1.0) 		and is_equal_approx(player_state.pack.count(CozyPrices.CURRENCY),
			purse - CozyPrices.buy("seed") + CozyPrices.sell("wheat"))

	# Money cannot be bought or sold, which is the rule that keeps a stall from
	# turning copper into more copper for anyone standing in front of it.
	var minted := not CozyPrices.buy_from(player_state.pack, CozyPrices.CURRENCY, 1) 		and not CozyPrices.sell_to(player_state.pack, CozyPrices.CURRENCY, 1)

	# And an unaffordable purchase is refused whole rather than partly paid.
	player_state.pack.items.clear()
	player_state.pack.add(CozyPrices.CURRENCY, 1.0)
	var poor := not CozyPrices.buy_from(player_state.pack, "bread", 1) 		and is_equal_approx(player_state.pack.count(CozyPrices.CURRENCY), 1.0)

	var village_still := is_equal_approx(building.inventory.total(), village_before)

	print("[cozyv2] trade: at the stall, refused out of range=%s, bought=%s, sold=%s, currency not tradable=%s, cannot overspend=%s, village %s  [%s]" % [
		str(refused_far), str(bought), str(sold), str(minted), str(poor),
		"untouched" if village_still else "MOVED",
		"OK" if refused_far and bought and sold and minted and poor and village_still
			else "FAIL, a trade moved something it should not have"])

	player_state.pack.items = pack_before
	player.global_position = here


## The pack panel shows the PLAYER'S pack, and it shows what is in it.
##
## Three things a panel can get wrong that no assertion about state can see:
##
##   1. IT DRAWS THE WRONG LEDGER. The village has an account too, the HUD
##      already draws that one, and the two numbers look the same on screen. So
##      the check gives the player a distinctive amount and asserts the panel
##      says THAT — a panel reading `building.inventory` would show something
##      else and pass every other check in the game.
##   2. IT ACCUMULATES ROWS. A material that has been spent to zero must lose its
##      row; a panel that only ever adds turns into a list of everything the
##      player has ever touched.
##   3. IT FEEDS ON ITS OWN OUTPUT. The resident panel was born with that bug and
##      the refresh here writes into labels it already holds, so the failure mode
##      is available. 600 refreshes is ten seconds of frames.
func _check_pack_panel() -> void:
	if pack_panel == null or player_state == null:
		print("[cozyv2] pack panel: NOT BUILT  [FAIL]")
		return

	var pack_before: Dictionary = player_state.pack.items.duplicate()
	var village_copper := building.inventory.count(CozyPrices.CURRENCY)

	# A pack nothing else in the world has, so "the panel read the right ledger"
	# is a claim with a wrong answer available to it.
	player_state.pack.items.clear()
	player_state.pack.add(CozyPrices.CURRENCY, 41.0)
	player_state.pack.add("wheat", 7.0)
	player_state.pack.add("wood", 3.0)
	pack_panel.visible = true
	_refresh_pack_panel()

	# THROUGH `_refresh_pack_panel`, NOT `pack_panel.refresh` — the frame path is
	# what the game uses, and a check that called the panel directly would pass
	# against a wiring bug that hands the panel the wrong ledger entirely. The
	# first version of this did exactly that, and its teeth stayed green.
	var ids := pack_panel.row_ids()
	var wheat_ok := pack_panel.shown_count("wheat") == 7
	var wood_ok := pack_panel.shown_count("wood") == 3
	# Money is in the header and NOT in the list: a row for it would be found by
	# scanning, and the header is where it is read.
	var money_in_list := ids.has(CozyPrices.CURRENCY)
	var purse_ok := pack_panel.purse_text().begins_with("41")
	var hiding_empty := not pack_panel.empty_shown()
	var showing := wheat_ok and wood_ok and purse_ok and not money_in_list \
		and hiding_empty and not is_equal_approx(village_copper, 41.0)
	print("[cozyv2] pack panel: rows=%s, wheat=%d wood=%d, purse='%s', village copper %d  [%s]" % [
		str(ids), pack_panel.shown_count("wheat"), pack_panel.shown_count("wood"),
		pack_panel.purse_text(), int(village_copper),
		"OK" if showing else "FAIL, the panel is not showing the player's own pack"])

	# (2) Spending a material to nothing takes its row away.
	player_state.pack.spend({"wood": 3.0})
	_refresh_pack_panel()
	var gone := pack_panel.shown_count("wood") == -1
	var kept := pack_panel.shown_count("wheat") == 7
	print("[cozyv2] pack panel drops a spent row: wood gone=%s, wheat kept=%s  [%s]" % [
		str(gone), str(kept),
		"OK" if gone and kept else "FAIL, a spent material kept its row"])

	# (3) Idempotent. 600 refreshes is ten seconds of frames.
	var once := "%s|%s" % [str(pack_panel.row_ids()), pack_panel.purse_text()]
	var once_count := pack_panel.shown_count("wheat")
	for i in 600:
		_refresh_pack_panel()
	var many := "%s|%s" % [str(pack_panel.row_ids()), pack_panel.purse_text()]
	var stable := once == many and pack_panel.shown_count("wheat") == once_count
	print("[cozyv2] pack panel refresh idempotent over 600 frames: %s  [%s]" % [
		"unchanged" if stable else "'%s' -> '%s'" % [once, many],
		"OK" if stable else "FAIL, refresh is feeding on its own output"])

	# (4) And an empty pack says so rather than showing an empty list.
	player_state.pack.items.clear()
	_refresh_pack_panel()
	var blank := pack_panel.row_count() == 0 and pack_panel.empty_shown()
	print("[cozyv2] pack panel on an empty pack: %d row(s), says so=%s  [%s]" % [
		pack_panel.row_count(), str(pack_panel.empty_shown()),
		"OK" if blank else "FAIL, an empty pack drew rows or said nothing"])

	# Put it all back: the pack, and the panel the way it was found.
	player_state.pack.items = pack_before
	_refresh_pack_panel()
	pack_panel.visible = false


## THE LOOP, END TO END, ON REAL OBJECTS.
##
## Every part of the equipment lane was finished and unreachable before today:
## `CozyStats` resolved, the generator rolled, the roller dropped, the container
## held and the equipment wore — and NOTHING IN THE WORLD PRODUCED AN ITEM. So
## the check that matters is not any one of those. It is that a player can walk
## up to something, hit it until it dies, and end up better equipped.
##
## Three things it holds down that nothing else can:
##
##   1. ONE SWING HITS ONCE. The active window is six frames; without the
##      `has_hit` guard a swing would land six times and the damage numbers would
##      be six times the frame data. Measured by counting hits, not by trusting
##      the guard.
##   2. THE DROP IS THE PLAYER'S. The village has an account too and the two look
##      identical on screen. The brigand's steel sword must end up in
##      `player_state.bag` and NOT in `building.inventory`.
##   3. RANGE MEANS SOMETHING. A swing from across the field must miss — the
##      reach is the one number that stops the game being a click anywhere.
##
## It MUTATES the world (a monster dies) and puts it back: monsters are re-placed
## and the player's things are restored.
func _check_fight() -> void:
	if player_state == null or player == null or monsters.is_empty():
		print("[cozyv2] fight: no monsters to fight  [FAIL]")
		return
	var brigand: CozyMonster = null
	for m in monsters:
		if m.def_id == "brigand":
			brigand = m
			break
	if brigand == null:
		print("[cozyv2] fight: no brigand in the world  [FAIL]")
		return

	var here := player.global_position
	var pack_before: Dictionary = player_state.pack.items.duplicate()
	var bag_before := player_state.bag.to_dict()
	var village_before := building.inventory.total()

	# (1) Out of range: 25 m away, a full swing must do nothing at all.
	player.global_position = brigand.global_position + Vector3(0.0, 0.0, 25.0)
	for i in 30:
		_attack_held = true
		_tick_combat()
	var missed := is_equal_approx(brigand.hp, brigand.hp_max)

	# (2) Up close: ONE press, and count the hits until the swing is over.
	#
	# THE FIRST VERSION OF THIS HELD THE BUTTON FORTY FRAMES AND COUNTED TWO
	# HITS, and called it a guard failure. It was not: light_1 is twenty-two
	# ticks from press to recovery, so forty frames is TWO SWINGS, and two hits
	# is exactly right. A measurement that does not know what it is measuring
	# reports a working system as broken — so the window is one swing, entered by
	# one press and left when the solver says it is idle.
	player.global_position = brigand.global_position + Vector3(0.0, 0.0, 1.0)
	# SETTLE FIRST. Section (1) ended mid-swing, and a press during a recovery is
	# swallowed by design — so the "one press" below would be no press at all and
	# the measurement would read zero. Empty input until the solver says idle.
	for i in 200:
		_attack_held = false
		_tick_combat()
		if not CozyCombatSolver.is_attacking(player_state.combat):
			break
	var hp_before := brigand.hp
	_attack_held = true
	_tick_combat()
	var hits := 0
	for i in 60:
		_attack_held = false
		var before := brigand.hp
		_tick_combat()
		if brigand.hp < before:
			hits += 1
		if not CozyCombatSolver.is_attacking(player_state.combat):
			break
	var one_hit := hits == 1
	var hurt := brigand.hp < hp_before

	# (3) Kill it, and see where the sword went.
	var guard := 0
	while not brigand.is_dead() and guard < 900:
		_attack_held = true
		_tick_combat()
		guard += 1
	var dead := brigand.is_dead()

	var sword := ""
	for it in player_state.bag.get_items():
		if it.definition_id == "steel_sword":
			sword = it.display_name()
	var copper := player_state.pack.count(CozyPrices.CURRENCY)
	var village_still := is_equal_approx(building.inventory.total(), village_before)

	print("[cozyv2] fight: a swing from 25 m missed=%s; up close one swing landed %d hit(s)=%s, hurt=%s; killed=%s, bag=%d item(s) incl. '%s', copper %d, village %s  [%s]" % [
		str(missed), hits, str(one_hit), str(hurt), str(dead),
		player_state.bag.count(), sword, int(copper),
		"untouched" if village_still else "MOVED",
		"OK" if missed and one_hit and hurt and dead and sword != "" \
			and copper > 0.0 and village_still
			else "FAIL, the fight did not put the drop in the player's own hands"])

	# Put the world back: the player's things, the player, and the monsters.
	player_state.pack.items = pack_before
	player_state.bag = CozyItemContainer.from_dict(bag_before)
	player.global_position = here
	_place_monsters()


func _check_resource_chain() -> void:
	var outdoor: CozyLocalNav = _nav_by_room.get(CozyRoomGraph.OUTDOORS)
	if outdoor == null:
		print("[cozyv2] resource chain: no outdoor grid to stand on  [FAIL]")
		return

	for trade in RESOURCE_TRADES:
		var job := String(trade)
		# The point type comes from the JOB TABLE, not from a copy typed here. A
		# second copy would agree with itself forever: the question is whether the
		# trade the table declares has somewhere to stand, and a hardcoded string
		# makes it "these three words have somewhere to stand".
		var want := CozyJobDefs.point_type(job)
		var found := 0
		var standable := 0
		for o in objects:
			if not is_instance_valid(o):
				continue
			for p in o.free_points_of_type(want):
				found += 1
				var cell := outdoor.world_to_cell(Vector2(p.world_position.x, p.world_position.z))
				if outdoor.is_walkable(cell):
					standable += 1
		# EVERY point, not merely one of them. A node whose point cannot be
		# stood at is a node nobody can work, however many others there are —
		# and "more than zero" was the second thing mutation testing caught
		# here: putting one tree out of the world left the count at 2 and the
		# check green.

		print("[cozyv2] resource '%s' for the %s: %d point(s) in the world, %d standable  [%s]" % [
			want, job, found, standable,
			"OK" if found > 0 and standable == found
			else "FAIL, %d of %d point(s) have nowhere to stand" % [found - standable, found]])

	# AND THE WORLD OBEYS THE GROUND RULE. `_place_object` refuses a crop on
	# anything but farmland, so this looks like it cannot fail — except that a
	# LOAD does not go through `_place_object`. `_apply_world` builds objects
	# straight from the save, so a file written before the rule existed, or one
	# edited by hand, can put a field on grass, and nothing would say so.
	var crops := 0
	var on_field := 0
	for o in objects:
		if not is_instance_valid(o) or o.def_id != "crop":
			continue
		crops += 1
		if terrain != null and terrain.material_id_at(o.global_position.x,
				o.global_position.z) == "farmland":
			on_field += 1
	print("[cozyv2] crops standing on farmland: %d of %d  [%s]" % [
		on_field, crops,
		"OK" if crops > 0 and on_field == crops
		else "FAIL, a crop is growing on ground nobody tilled"])

	# AND THE PLACEMENT PATH ACTUALLY CONSULTS THE RULE. The rule itself is a pure
	# function asserted in `test_resource_chain.gd`; this is the other half —
	# a placement made through the real path, on ground that must refuse it.
	#
	# It is also what READS `last_placement_refusal`. Without it that member would
	# have been set and never looked at, which is the shape this project has paid
	# for seven times. An unused reason is worse than no reason: it looks like the
	# caller was informed.
	var objs_before := objects.size()
	var refused := _place_object("crop", 20.0, 20.0, 0)
	var reason := last_placement_refusal
	# The ground is named rather than assumed. It was first written as "grass" and
	# reported soil — `_check_terrain` clears a plot of its own a few checks
	# earlier, and this spot is inside it. An assertion that hardcodes what it
	# expects to find stops being about the rule and starts being about the world.
	var ground_there := terrain.material_id_at(20.0, 20.0) if terrain != null else "?"
	print("[cozyv2] placement teeth: a crop on '%s' -> refused=%s, nothing added=%s, reason=\"%s\"  [%s]" % [
		ground_there, refused == null, objects.size() == objs_before, reason,
		"OK" if refused == null and objects.size() == objs_before
			and reason.contains("farmland") and reason.contains(ground_there)
		else "FAIL, the ground rule is not enforced by the placer"])

	# THE CYCLE, ON A REAL OBJECT, without waiting for one. The clock is ASKED
	# rather than advanced — that is what derived growth buys — so a day of it is
	# asserted in the first frame of the run.
	#
	# It works on a real crop and puts it back, because the alternative is a
	# synthetic object that shares none of the code being tested.
	var probe: CozyWorldObject = null
	for o in objects:
		if is_instance_valid(o) and o.def_id == "crop":
			probe = o
			break
	if probe == null:
		print("[cozyv2] growth cycle: no crop to measure  [FAIL]")
	else:
		var hour := _game_hours()
		var kept_taken := probe.taken
		var kept_at := probe.worked_at
		var fresh := probe.is_available(hour)
		probe.take_one(hour)
		probe.refresh_availability(hour)
		var spent := probe.is_available(hour)
		var spent_has := not probe.free_points_of_type("harvest").is_empty()
		probe.refresh_availability(hour + 24.0)
		var back := probe.is_available(hour + 24.0)
		var back_has := not probe.free_points_of_type("harvest").is_empty()
		probe.taken = kept_taken
		probe.worked_at = kept_at
		probe.refresh_availability(hour)

		print("[cozyv2] growth cycle: fresh=%s, just taken=%s (point still offered=%s), next day=%s (point back=%s)  [%s]" % [
			fresh, spent, spent_has, back, back_has,
			"OK" if fresh and not spent and not spent_has and back and back_has
			else "FAIL, a crop does not live through the day"])

	# AND AN OBJECT MUST BLOCK ITS OWN CELL. This is what proves the outdoor grid
	# has been told placed objects are there at all.
	#
	# The route-based version of this could not tell: A* produced IDENTICAL
	# waypoints whether or not a tree was an obstacle, so a mutation that put the
	# grid back to walls-only turned nothing red. Naming the collider a route hit
	# was what made the other bug findable; asking the grid directly is what makes
	# this one.
	#
	# The room grids have always been told (`_obstacles_on_floor` adds objects);
	# the outdoor grid went through `_static_obstacles_on_floor`, which does not.
	var solid := 0
	var on_floor := 0
	for o in objects:
		if not is_instance_valid(o) or o.floor_index != 0:
			continue
		on_floor += 1
		var oc := outdoor.world_to_cell(Vector2(o.global_position.x, o.global_position.z))
		if not outdoor.is_walkable(oc):
			solid += 1
	print("[cozyv2] objects block their own cells: %d of %d on floor 0  [%s]" % [
		solid, on_floor,
		"OK" if on_floor > 0 and solid == on_floor
		else "FAIL, an object is see-through to navigation"])

	# And the job that does the work must name a point the world actually has —
	# the table check cannot tell a name from a place.
	for job in RESOURCE_TRADES:
		var want := CozyJobDefs.point_type(job)
		var offered := 0
		for o in objects:
			if is_instance_valid(o):
				offered += o.free_points_of_type(want).size()
		print("[cozyv2] resource job '%s' seeks '%s': %d in the world  [%s]" % [
			job, want, offered,
			"OK" if offered > 0 else "FAIL, a job that can never finish"])

	_check_work_priority()
	_check_ground_points()


## The GROUND as a point source: does the field offer anywhere to sow, and can a
## resident stand there?
##
## The measurement this exists for is the FIRST number: the starter field is
## 5.0 x 2.5 m of farmland with three 1 x 1 m crops already standing in it, and
## whether that leaves room to sow at all is not something to reason about. A
## provider that offers nothing is a farmer who can still only reap, and every
## assertion below would pass over a world with no sow point in it.
##
## A CHECK THAT PASSES FOR THE WRONG REASON IS WORSE THAN A SKIP (INVARIANTS):
## "every offered point is standable" is vacuously true when none are offered, so
## the count is asserted to be positive BEFORE standability means anything.
func _check_ground_points() -> void:
	if ground_points == null:
		print("[cozyv2] ground points: no provider (no terrain?)  [SKIP]")
		return

	var outdoor: CozyLocalNav = _nav_by_room.get(CozyRoomGraph.OUTDOORS)
	var t0 := Time.get_ticks_usec()
	var found := ground_points.free_points_of_type(CozyObjectDefs.INTERACT_PLANT)
	var rebuild_us := Time.get_ticks_usec() - t0
	# AND A SECOND TIME. The first call of the run also pays for every table it
	# touches being built for the first time, so the cold number is not the one a
	# resident feels — a resident asks on every scan for work. Reporting only the
	# cold one would overstate what the chunk shortcut bought.
	var t_warm := Time.get_ticks_usec()
	ground_points.free_points_of_type(CozyObjectDefs.INTERACT_PLANT)
	var warm_us := Time.get_ticks_usec() - t_warm
	var standable := 0
	var on_farmland := 0
	var spots: Array[String] = []
	for p in found:
		spots.append("(%.1f,%.1f)" % [p.world_position.x, p.world_position.z])
		if terrain != null and terrain.material_id_at(
				p.world_position.x, p.world_position.z) == "farmland":
			on_farmland += 1
		if outdoor != null:
			var cell := outdoor.world_to_cell(
				Vector2(p.world_position.x, p.world_position.z))
			if outdoor.is_walkable(cell):
				standable += 1
	print("[cozyv2] ground offers %d sow point(s) on the starter field, %d on farmland, %d standable, derived in %.2f ms (%.2f ms warm): %s  [%s]" % [
		found.size(), on_farmland, standable, float(rebuild_us) / 1000.0,
		float(warm_us) / 1000.0,
		", ".join(spots) if not spots.is_empty() else "(none)",
		"OK" if found.size() > 0 and standable == found.size()
			and on_farmland == found.size()
		else "FAIL, the field offers nowhere to sow, or a point nobody can stand at"])

	# AND THE SHORTCUT ANSWERS EXACTLY WHAT A FULL WALK ANSWERS.
	#
	# The walk above only visits chunks whose `has_farmland` flag is set, which is
	# 40 ms of work avoided. That shortcut is sound only while farmland is the
	# only ground a sow point may stand on — a fact about `CozyObjectDefs`, not
	# about the point source, and one a later author can change in a file that
	# does not know this check exists.
	#
	# SO IT IS CHECKED, NOT ASSUMED, AND COMPARED AS A SET RATHER THAN A COUNT.
	# Two walks that agree on how many points they found can disagree about which
	# ones, and the difference would be a crop in the wrong place rather than a
	# missing one. Duplicates are checked too: a chunk rectangle that does not
	# line up with the tile lattice can offer the same square twice, and two crops
	# in one square is a defect rather than a nuisance.
	var t1 := Time.get_ticks_usec()
	var reference := ground_points.full_free_points_of_type(CozyObjectDefs.INTERACT_PLANT)
	var full_us := Time.get_ticks_usec() - t1
	var fast_spots: Array[String] = []
	var full_spots: Array[String] = []
	for p in found:
		fast_spots.append(_spot_key(p))
	for p in reference:
		full_spots.append(_spot_key(p))
	var unique := {}
	for s in fast_spots:
		unique[s] = true
	fast_spots.sort()
	full_spots.sort()
	print("[cozyv2] ground chunk shortcut: %d point(s) vs %d from a full walk, %d distinct, %d ms saved  [%s]" % [
		fast_spots.size(), full_spots.size(), unique.size(),
		int((full_us - rebuild_us) / 1000.0),
		"OK" if fast_spots == full_spots and unique.size() == fast_spots.size()
			else "FAIL, the shortcut does not answer what a full walk answers"])

	# AND THE KIND IT OFFERS IS ONE A RECIPE IS WORKED AT. A point type the ground
	# derives but no recipe consumes is a resident walking out to a field for
	# nothing — the `chest`/`store` shape, in a new place.
	var unmatched: Array[String] = []
	for t in CozyGroundPoints.offers():
		if CozyRecipeDefs.for_point(t).is_empty():
			unmatched.append(t)
	print("[cozyv2] every kind the ground offers is worked by a recipe: %s  [%s]" % [
		", ".join(CozyGroundPoints.offers()),
		"OK" if unmatched.is_empty()
		else "FAIL, the ground offers %s and nothing consumes it" % ", ".join(unmatched)])


## A ground point's identity, for comparing two derivations of the same field.
##
## `CozyInteractionPoint` has no id, and a derived one is deliberately thrown
## away when the call returns — so POSITION IS THE IDENTITY here, which is also
## the right one: two sow points in the same square are the same square.
func _spot_key(p: CozyInteractionPoint) -> String:
	return "%.3f,%.3f" % [p.world_position.x, p.world_position.z]


## Would the resident actually SEEK those points, at the hour it would do the
## work? Everything above proves the world has `chop`, `mine` and `harvest`
## points in it; none of it proves the agent ever asks for one.
##
## IT DID NOT, UNTIL 2026-09-15, and the reason is the shape this project has
## paid for repeatedly: `CozySchedule.ACTIVITY_POINTS` mapped the activity `work`
## onto the point type `work`, which is what a research table offers — so at 09:00
## the schedule overrode the trade and a woodcutter sought a desk. It was
## invisible while every job in the table happened to have `point_type: "work"`,
## which was true when the schedule was written and stopped being true the day
## the three gathering trades were added.
##
## Measured, not reasoned about: `tests/probe/work_priority_probe.gd` prints what
## each trade wants at each hour of the day, and every one of the three read
## `work` at 09:00 and 13:00.
##
## THE PROBE AGENT IS DETACHED — never added to the tree — so this cannot move
## the resident, change its job, or run one frame of its script. A check that
## borrows the live resident to answer a question about a woodcutter has to put
## them back, and "putting it back" is another thing that can be forgotten.
func _check_work_priority() -> void:
	# A working hour, because that is the hour the bug lived in: this runs in the
	# first frames, when the real clock still reads 06:00 and every trade is
	# legitimately asleep.
	var clock := CozyTimeSystem.new()
	clock.hour = 9.0

	var wrong: Array[String] = []
	var line: Array[String] = []
	for job in RESOURCE_TRADES:
		var agent := CozyNpcAgent.new()
		agent.npc_state = CozyNpcState.create("probe", "Probe", job, 7)
		agent.clock = clock
		var ranked := agent.want_point_types()
		var head := ranked[0] if not ranked.is_empty() else ""
		# The whole list, because "the trade is on it" and "the trade leads it" are
		# different claims and only the second one is the fix.
		line.append("%s->[%s]" % [job, ", ".join(ranked)])
		if head != CozyJobDefs.point_type(job):
			wrong.append(job)
		agent.free()
	clock.free()

	print("[cozyv2] at 09:00 the trade leads the want-list: %s  [%s]" % [
		"  ".join(line),
		"OK" if wrong.is_empty()
		else "FAIL, %s sought something other than their trade" % ", ".join(wrong)])

	# AND THE TRADE IS A FALLBACK RATHER THAN THE ONLY ANSWER — the other half of
	# a ranked list. A woodcutter carrying a finished load stores it first (§45's
	# Take and Store are separate steps) and still chops behind it, so a chest
	# that is full or unreachable costs a detour rather than the whole job.
	var carrier := CozyNpcAgent.new()
	var state := CozyNpcState.create("probe2", "Probe", "woodcutter", 7)
	state.inventory.add("wood", 4.0)
	carrier.npc_state = state
	var clock2 := CozyTimeSystem.new()
	clock2.hour = 9.0
	carrier.clock = clock2
	# The rank is what matters and the tail is every kind of work the resident will
	# take on, so the head is asserted rather than the whole list — comparing the
	# list would be a second copy of `CozyWorkDefs.ORDER`.
	var carrying := carrier.want_point_types()
	var head := carrying[0] if not carrying.is_empty() else ""
	print("[cozyv2] a woodcutter carrying wood leads with '%s' (the container leg), and 'chop' is still on the list=%s)  [%s]" % [
		head, str(carrying.has("chop")),
		"OK" if head == "store" and carrying.has("chop")
		else "FAIL, the container leg is not ranked ahead of the trade"])
	carrier.free()
	clock2.free()


## Everything that measures the house, and the systems derived from its walls.
##
## A LIST, not a run of calls, and that is the whole design. When
## `HOUSE_ENABLED` is false the names are printed as NOT RUN — so a run that
## measures less than it used to says so, in the log, where the numbers are.
## A count kept by hand would drift the first time someone adds a check here.
##
## Each entry is `[what it measures, the callable]`. Grouping several calls under
## one name (rooms, routes) keeps the report readable without dropping the calls.
##
## Three of these passed VACUOUSLY with no house, which is why they are parked
## rather than left running: `npc route plan` planned "upstairs" in 1 waypoint and
## still reported `crosses floor=true`; `routes` expected no route between two
## rooms and got one because neither room exists; and the opening shot found
## nothing opaque because there is nothing to be opaque. A green that holds for
## the wrong reason is worse than a skip, because it reads as coverage.
func _report_house() -> void:
	var checks: Array = [
		["rooms", func() -> void:
			_check_room_at(Vector3(4.0, 0.1, 3.0), "room_0_0")
			_check_room_at(Vector3(4.0, FLOOR_H + 0.1, 3.0), "room_1_0")
			_check_room_at(Vector3(4.0, 0.1, -6.0), "outdoors")],
		# Doors are derived from wall openings now, so the check looks for the
		# connection rather than for a hand-chosen id.
		["door + stair portals", func() -> void:
			_check_door_between("", "room_0_0")
			_check_portal("stair_main", "room_0_0", "room_1_0")],
		# Asserted by the KIND of connector crossed, not by id: a door's portal id
		# is generated from the wall that carries the opening, so a named
		# expectation would break every time the walls are renumbered — and
		# "through a door, then up a stair" is what this test actually means.
		["routes", func() -> void:
			_check_route_kinds(CozyRoomGraph.OUTDOORS, "room_1_0", ["door", "stair"])
			_check_route_kinds("room_0_0", "room_1_0", ["stair"])
			_check_route_kinds("room_1_0", "room_1_0", [])],
		["local navigation + outdoor detour", _check_nav],
		["wall connection + context", _check_wall_connection],
		["openings", _check_openings],
		["wall assembly", _check_wall_assembly],
		["building state", _check_building_state],
		["roofs", _check_roofs],
		["roof follows its room", _check_roof_follows_room],
		["outline guard", _check_outline_guard],
		["npc route plan (upstairs)", _check_npc_route_plan],
		["occlusion structure", _check_occlusion_structure],
	]

	if HOUSE_ENABLED:
		for c in checks:
			(c[1] as Callable).call()
		return

	var names: Array[String] = []
	for c in checks:
		names.append(String(c[0]))
	# "group(s)", not "check(s)": several assertions hide behind one name
	# (`rooms` is three), so a count of names is not a count of assertions and
	# saying otherwise would understate what stopped being measured. The two
	# totals — 122 assertions with the house, 88 without — are in the project
	# notes, where a number that must be kept in step with the code belongs next
	# to the reason it changes.
	print("[cozyv2] house: PARKED, %d check group(s) NOT RUN (HOUSE_ENABLED=false): %s" % [
		names.size(), ", ".join(names)])


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
	# Read BEFORE the incremental pass below, which overwrites them.
	var full_ms := scatter.sample_ms + scatter.build_ms
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
	# TIMED, because this is the number a player feels and the full rebuild is
	# not. A stroke re-samples the chunks it touched and leaves the rest of the
	# field alone (`_refresh_scatter`), so this is the cost that lands between a
	# player's mouse button and the plants appearing — and until now nothing
	# printed it, which made "the scatter is slow" impossible to answer.
	var t_inc := Time.get_ticks_usec()
	_refresh_scatter()
	var inc_ms := float(Time.get_ticks_usec() - t_inc) / 1000.0
	var inc_fp := scatter.fingerprint()
	var inc_total := scatter.total_instances()

	# The same edit done the expensive way, as the reference.
	scatter.rebuild()
	var ref_fp := scatter.fingerprint()

	var moved := inc_fp != full_fp
	var same := inc_fp == ref_fp and inc_total == scatter.total_instances()
	# PER KIND, because "15367 instance(s) in 4 mesh(es)" cannot answer the
	# question a player actually asks, which is "where did the flowers go". Total
	# counts move with the grass and hide everything under it.
	var per_kind: Array[String] = []
	for rule_id in CozyScatterRule.ids():
		per_kind.append("%s=%d" % [String(rule_id), scatter.instance_count(String(rule_id))])
	print("[cozyv2] scatter by kind: %s" % ", ".join(per_kind))
	print("[cozyv2] scatter incremental rebuild: %d chunk(s) dirty of %d, %d -> %d instance(s) in %.1f ms (a full rebuild is %.1f ms), moved=%s, matches a full rebuild=%s  [%s]" % [
		touched, terrain.chunk_count(), full_total, inc_total, inc_ms, full_ms, str(moved), str(same),
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
	#
	# The two measurements below INDEX the world, so they have to say what they
	# do when there is nothing there to index. They used to take `[0]` outright,
	# which did not fail — it CRASHED, with a `SCRIPT ERROR: Out of bounds`, and
	# took both measurements down with it. A checker that dies instead of
	# reporting is worse than a missing one, because the crash reads as "the
	# build is broken" rather than "this check had nothing to measure".
	if s.stairs.is_empty() or s.slabs.is_empty():
		print("[cozyv2] stair: nothing to measure (%d stair(s), %d slab(s))  [%s]" % [
			s.stairs.size(), s.slabs.size(),
			"FAIL, none built" if HOUSE_ENABLED else "SKIPPED, no house"])
		return

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
## The planting half of the terrain chain (Willow 2026-09-12):
## Grass -> Soil -> Farmland, and tilling cannot skip a step.
##
## Driven through INTENTS rather than `set_material_at`, because the rule that
## matters lives in the OPERATION. Writing the material directly would step over
## the guard, and this check would then pass on a chain that does not hold.
func _check_farming_chain() -> void:
	if terrain == null:
		print("[cozyv2] farming chain: terrain NOT BUILT  [FAIL]")
		return

	# A plot clear of the house and of the other terrain checks' scratch corner.
	var tx := 26.0
	var tz := 26.0
	var at := Vector2(tx, tz)

	# (1) Tilling RAW GRASS must do nothing. This refusal IS the feature: without
	# it the clearing step would be optional and the chain would be one action
	# wearing two names.
	var start := terrain.material_id_at(tx, tz)
	var refused: int = terrain.apply_intent(
		CozyTerrainIntent.till_brush(at, 1.0))["touched"]
	var after_refusal := terrain.material_id_at(tx, tz)

	# (2) Clear it, then till it — the chain, one intent per step. Soil's
	# buildability is sampled BETWEEN the two, while the ground really is soil;
	# reading it after the till would silently measure farmland under a variable
	# named for soil.
	terrain.apply_intent(CozyTerrainIntent.clear_brush(at, 1.0))
	var cleared := terrain.material_id_at(tx, tz)
	var soil_b := terrain.buildability_at(tx, tz)
	terrain.apply_intent(CozyTerrainIntent.till_brush(at, 1.0))
	var tilled := terrain.material_id_at(tx, tz)
	var farm_b := terrain.buildability_at(tx, tz)

	var chain_ok := (start == "grass" and refused == 0 and after_refusal == "grass"
		and cleared == "soil" and tilled == "farmland")
	print("[cozyv2] farming chain: %s -till-> %s (%d touched), -clear-> %s, -till-> %s  [%s]" % [
		start, after_refusal, refused, cleared, tilled,
		"OK" if chain_ok else "FAIL, the chain does not hold"])

	# (3) Farmland is NOT buildable, and soil was. Both halves are needed: an
	# assertion that only checked "farmland is not buildable" would pass just as
	# well if buildability were broken for everything.
	var rule_ok := CozyBuildability.accepts_building(soil_b) 		and not CozyBuildability.accepts_building(farm_b)

	# (4) The storage order is APPEND ONLY. A saved chunk holds INDICES, so a
	# material inserted in the middle silently re-labels every existing cell.
	var round_trip := CozyTerrainMaterials.id_of(
		CozyTerrainMaterials.index_of("farmland")) == "farmland"
	var stone_kept := CozyTerrainMaterials.index_of("stone") == 3
	print("[cozyv2] farming rule: soil build=%s, farmland build=%s, index round-trip=%s, stone still 3=%s  [%s]" % [
		str(CozyBuildability.accepts_building(soil_b)),
		str(CozyBuildability.accepts_building(farm_b)),
		str(round_trip), str(stone_kept),
		"OK" if rule_ok and round_trip and stone_kept
			else "FAIL, farmland's build rule or the storage order is wrong"])


## The ground draws through a shader now, and every way the pieces can fail to
## meet is SILENT. A material array with too few layers samples layer 0 for the
## material that is missing; a control texture of the wrong size has the index
## fetched from a cell that is not the fragment's. Neither throws, neither
## warns, and both look like an art decision.
##
## So the two numbers that have to agree are asserted against each other rather
## than trusted to stay in step.
## The ground: dual-grid tiles, decided per fragment by the shader.
##
## THREE THINGS CAN GO WRONG HERE AND NONE OF THEM THROWS.
##
##   * The shader's material count falls behind `CozyTerrainMaterials`, and every
##     cell of the newer material draws as layer 0 — grass where there should be
##     stone. The count is a uniform, set from the table, so it CAN be compared.
##   * A control texel disagrees with the cell it describes. That texture is the
##     only link between what the terrain knows and what the shader samples, and
##     a wrong byte draws every cell as one material — which looks like an art
##     decision rather than a bug.
##   * The world is all one material, so the corner rule has nothing to do and
##     the check passes on a field with no boundaries in it at all. That is the
##     trap an earlier version of this check fell into, by reading the first
##     chunk — a corner of the field that is entirely grass.
##
## IT ALSO ASSERTS THAT THE SHADER IS ACTUALLY DRIVEN. Every uniform is set from
## GDScript rather than left to the shader's own default, because a uniform
## nothing has set answers `null` to `get_shader_parameter` — so an earlier check
## reported the feature OFF while the GPU was drawing it ON. A value that lives
## only inside a shader is a value this side cannot assert about.
func _check_ground_tiles() -> void:
	if terrain_renderer == null or terrain == null:
		print("[cozyv2] ground tiles: NOT BUILT  [FAIL]")
		return

	var want := CozyTerrainMaterials.ORDER.size()
	var have := terrain_renderer.material_layers()

	var coords: Array = terrain_renderer.chunk_coords()
	if coords.is_empty():
		print("[cozyv2] ground tiles: no chunk to read  [FAIL]")
		return

	var cells := CozyTerrainChunk.CELLS
	var read := 0
	var wrong := 0
	var kinds := {}
	for coord in coords:
		var img := terrain_renderer.control_image(coord)
		var chunk: CozyTerrainChunk = terrain.chunks.get(coord, null)
		if img == null or chunk == null:
			print("[cozyv2] ground tiles: chunk %s unreadable  [FAIL]" % coord)
			return
		for lz in cells:
			for lx in cells:
				var expect := CozyTerrainMaterials.index_of(chunk.material_id_at(lx, lz))
				var got := int(round(img.get_pixel(lx, lz).r * 255.0))
				read += 1
				kinds[expect] = true
				if got != expect:
					wrong += 1

	var mat := terrain_renderer.material_of(coords[0])
	var driven: bool = mat is ShaderMaterial 		and (mat as ShaderMaterial).get_shader_parameter("chunk_metres") != null

	print("[cozyv2] ground tiles: %d of %d material(s) in the array, %d cell(s) read back across %d chunk(s) in %d kind(s), %d disagreeing; shader-driven=%s  [%s]" % [
		have, want, read, coords.size(), kinds.size(), wrong, driven,
		"OK" if have == want and driven and wrong == 0 and read > 0 and kinds.size() >= 2
		else "FAIL, the ground the shader samples is not the ground the terrain knows"])


func _check_lights() -> void:
	if clock == null or world_env == null or day_sun == null:
		print("[cozyv2] lights: NOT BUILT  [FAIL]")
		return

	var kept := clock.hour

	clock.hour = 12.0
	_light_the_world()
	var noon := _daylight()
	var noon_sun := day_sun.light_energy
	var noon_ambient := world_env.ambient_light_energy

	clock.hour = 0.0
	_light_the_world()
	var midnight := _daylight()
	var night_sun := day_sun.light_energy
	var night_ambient := world_env.ambient_light_energy

	# Dawn is a RAMP: an hour after it starts it is neither day nor night.
	clock.hour = DAWN + 1.0
	_light_the_world()
	var dawn := _daylight()

	var lamps := 0
	var lit := 0
	for o in objects:
		if is_instance_valid(o) and o.has_light():
			lamps += 1
			if o.light_energy() > 0.0:
				lit += 1

	clock.hour = kept
	_light_the_world()

	print("[cozyv2] lights: noon daylight=%.2f sun=%.2f amb=%.2f | midnight daylight=%.2f sun=%.2f amb=%.2f | dawn=%0.2f | %d of %d lamp(s) lit at midnight  [%s]" % [
		noon, noon_sun, noon_ambient, midnight, night_sun, night_ambient, dawn, lit, lamps,
		"OK" if noon > 0.99 and midnight == 0.0 and dawn > 0.0 and dawn < 1.0
			and night_sun < noon_sun and night_sun > 0.0
			and night_ambient > 0.0 and lamps > 0 and lit == lamps
		else "FAIL, the night is not what it should be"])


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
	# Parked with the house. This one is about walking AROUND a building: the
	# navigation grid has to route the resident past an obstacle rather than
	# through it. With no building the walk is a straight line, so the check
	# would pass while measuring nothing — it failed instead, reporting
	# `1 pt(s) inside the house` for a house that is not there.
	if HOUSE_ENABLED:
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
## PARKED 2026-09-14 with the height field.
##
## Every number in here measures whether the RENDERED ground follows the CELL
## heights, and the ground deliberately no longer does — it is flat, so DIG moves
## a number and nothing else. The assertion below was still green-by-accident for
## one run and then said `[FAIL, the ground did not follow the field]`, which is
## exactly right: the ground did not, and should not.
##
## Kept rather than deleted because the height field is still in the data and
## still saved; if heights ever come back, so does this.
func _check_terrain_surface_parked() -> void:
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

	# AND THE PLANTS ARE DRAWN BY SOMETHING THAT COMPILED.
	#
	# Everything above counts instances and proves where they are; none of it
	# touches the one thing that renders. A shader that fails to compile leaves
	# every count, every fingerprint and every placement assertion exactly as it
	# was, and the field comes out INVISIBLE — the "green and proving nothing"
	# shape, with a picture attached.
	#
	# A uniform list is not a compile report, but it is the closest thing to one:
	# Godot hands back an empty list for a shader it could not build, so an empty
	# list here means the material is not drawing. The actual errors are in the
	# log as `SHADER ERROR`, which `grep -c "ERROR"` counts.
	var unlit: Array[String] = []
	var shader_kinds := 0
	for asset_id in scatter.asset_ids():
		var mat := scatter.material_of(String(asset_id))
		var ok := false
		if mat is ShaderMaterial:
			var sh: Shader = (mat as ShaderMaterial).shader
			ok = sh != null and not sh.get_shader_uniform_list().is_empty()
		elif not CozyVegetationScatter.USE_VEGETATION_SHADER:
			ok = mat != null
		if ok:
			shader_kinds += 1
		else:
			unlit.append(String(asset_id))
	# AND EVERY SPRITE IS DRAWN AT THE DENSITY THE PROFILE ASKS FOR.
	#
	# `ART_PROFILE.md` §2 fixes it: 12 m of visible height over 720 px is 60
	# screen px per world metre, so a 24 px sprite is 0.40 m and one drawn over
	# 0.55 m has every pixel stretched 1.38 times. That is not a small difference
	# in size — it is what makes a blade of grass read as a bush, and it was
	# invisible until there was a screenshot to look at.
	#
	# THIS PRINTS RATHER THAN FAILS, for now: the placeholders are 16 and 24 px
	# and sizing THEM by density would make a 0.27 m tree, so the number is the
	# work list rather than a regression. The grass is the one asset that is
	# already right, and it is named first so the line reads as a target.
	var density: Array[String] = []
	var off := 0
	for asset_id in scatter.asset_ids():
		var mag := CozyPixelArt.magnification(scatter.texture_of(String(asset_id)),
			scatter.world_size_of(String(asset_id)))
		var tex := scatter.texture_of(String(asset_id))
		var px := int(tex.get_width()) if tex != null else 0
		if absf(mag - 1.0) > 0.06:
			off += 1
		density.append("%s %dpx over %.2fm = x%.2f" % [
			String(asset_id), px, scatter.world_size_of(String(asset_id)), mag])
	print("[cozyv2] sprite density (native is x1.00): %s -- %d of %d off  [%s]" % [
		" | ".join(density), off, scatter.asset_ids().size(),
		"OK" if off == 0 else "NOTE"])

	print("[cozyv2] vegetation material: %d of %d kind(s) drawing, %s  [%s]" % [
		shader_kinds, scatter.asset_ids().size(),
		"all compiled" if unlit.is_empty() else "NOT DRAWING: %s" % ", ".join(unlit),
		"OK" if unlit.is_empty() else "FAIL, a plant material is missing or did not compile"])


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

	# The check reads a library pointed at the FIXTURE tree, not at the
	# production one, and the path is a parameter rather than a constant buried
	# in the loader. Two reasons, and the second is the real one:
	#
	#   * the fixtures are test data and belong in tests/ (see
	#     docs/PROJECT_LAYOUT.md), and
	#   * an assertion that counts what happens to be sitting in the production
	#     asset folder is measuring the FOLDER, not the loader. Emptying
	#     `res://assets/art` — which is the correct state until real art exists,
	#     doc 58.1 — would otherwise turn this into a failing test.
	#
	# Nothing in production reads `assets` today: the library is built, and the
	# scatter takes one in `setup()` and never looks at it. So this split changes
	# what is TESTED, not what RUNS.
	var fixtures := CozyAssetLibrary.new()
	fixtures.load_dir(FIXTURE_ROOT)
	var s := fixtures.summary()
	var expected_loaded := 4
	var expected_rejected := 1
	var expected_runtime := 3
	print("[cozyv2] asset library: %d loaded, %d rejected, %d runtime  [%s]" % [
		s["loaded"], s["rejected"], s["runtime"],
		"OK" if s["loaded"] == expected_loaded and s["rejected"] == expected_rejected \
			and s["runtime"] == expected_runtime else "FAIL, expected 4/1/3"])

	# A rejected definition must say WHY (same rule as the terrain gate, doc #72).
	var why := fixtures.rejection_report()
	print("[cozyv2] asset library rejects malformed_draft: %s  [%s]" % [
		why, "OK" if why.contains("missing") else "FAIL, no reason given"])

	# E.3.1 — the RAW asset must not appear in the runtime set.
	var raw_leaked := false
	for d in fixtures.runtime_definitions():
		if d.state_name() != "approved":
			raw_leaked = true
	var raw_visible_to_query := fixtures.by_category("vegetation").size()
	print("[cozyv2] asset library raw exclusion: runtime=%d, vegetation query=%d  [%s]" % [
		s["runtime"], raw_visible_to_query,
		"OK" if not raw_leaked and raw_visible_to_query == 3 else "FAIL"])

	var grassland := fixtures.by_biome_and_category("grassland", "vegetation")
	print("[cozyv2] asset library biome query: grassland+vegetation -> %d  [%s]" % [
		grassland.size(), "OK" if grassland.size() == 2 else "FAIL, expected 2"])

	_check_asset_manifest()


## The manifest is what an EXPORTED build reads: there are no loose files to
## enumerate, so `DirAccess` cannot find assets at runtime and the manifest is
## the list instead. Which means a manifest that disagrees with the tree ships
## the WRONG ASSETS, silently — the build succeeds, it just contains the wrong
## thing.
##
## So the two are compared, every run, in both directions.
func _check_asset_manifest() -> void:
	var manifest_path := FIXTURE_ROOT.path_join(CozyAssetLibrary.MANIFEST_NAME)
	var listed: Array = []
	var f := FileAccess.open(manifest_path, FileAccess.READ)
	if f != null:
		var parsed: Variant = JSON.parse_string(f.get_as_text())
		f.close()
		if typeof(parsed) == TYPE_DICTIONARY:
			listed = (parsed as Dictionary).get("assets", [])

	var walked := CozyAssetLibrary.scan_paths(FIXTURE_ROOT)
	var in_manifest := {}
	for entry in listed:
		in_manifest[String(entry)] = true
	var missing: Array[String] = []          # on disk, absent from the manifest
	for entry in walked:
		if not in_manifest.has(entry):
			missing.append(entry)
	var extra: Array[String] = []            # in the manifest, absent from disk
	for entry in listed:
		if not walked.has(String(entry)):
			extra.append(String(entry))

	# And loading THROUGH the manifest must reach the same definitions as
	# scanning, or the manifest names files the loader cannot use.
	var via := CozyAssetLibrary.new()
	var sum := via.load_manifest(manifest_path)

	# Every listed file must produce EITHER a definition or a rejection. A file
	# that produces neither vanished inside the loader, which is the one failure
	# the counts above cannot see.
	var accounted := int(sum["loaded"]) + int(sum["rejected"]) == listed.size()
	var ok := missing.is_empty() and extra.is_empty() and accounted
	print("[cozyv2] asset manifest: %d listed, %d walked, loaded=%d refused=%d, stale(missing=%s extra=%s)  [%s]" % [
		listed.size(), walked.size(), int(sum["loaded"]), int(sum["rejected"]),
		"none" if missing.is_empty() else ",".join(missing),
		"none" if extra.is_empty() else ",".join(extra),
		"OK" if ok else "FAIL, the manifest disagrees with the tree"])


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

	# (1b) The palette's list and the hotkeys' list are two hand-kept values that
	# must agree. If they drift, the buttons and the number keys address different
	# tools and a key press silently picks the wrong one — so the agreement is
	# asserted rather than trusted, by flattening the groups the way the HUD does.
	var flattened: Array[String] = []
	for g in TOOL_GROUPS:
		for t in g:
			flattened.append(String(t))
	var order_ok := flattened == TOOLS
	print("[cozyv2] hud tool order: %d group(s) flatten to %d tool(s), matches the hotkey list: %s  [%s]" % [
		TOOL_GROUPS.size(), flattened.size(), order_ok,
		"OK" if order_ok else "FAIL, the palette and the hotkeys disagree"])

	# (2) Reachability, through the same call a button click makes.
	# `clear` rather than `dig`: the reachability check is about the palette
	# wiring, and it has to name a tool that is still on the palette.
	var dig_i := TOOLS.find("clear")
	hud.select_tool(dig_i)
	var reached := build_mode and _is_terrain_tool() and tool_idx == dig_i
	# And the newest terrain tool, so adding one to TERRAIN_TOOLS without a button
	# or without a hotkey cannot pass.
	var till_i := TOOLS.find("till")
	hud.select_tool(till_i)
	var till_reached := build_mode and _is_terrain_tool() and tool_idx == till_i
	hud.select_tool(dig_i)
	print("[cozyv2] terrain tools reachable from the HUD: %s, %s  [%s]" % [
		_current_tool(), hud.tool_hotkey_text(till_i),
		"OK" if reached and till_reached else "FAIL, tool did not switch"])

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
	# "Nothing to resolve" is not a failure of the context menu, it is a fact
	# about the world. The demand for a wall came from the demo house: with none,
	# `checked` is 0 and the menu this check exists for is still perfectly wired.
	print("[cozyv2] context probe: %d wall collider(s) resolved to their wall  [%s]" % [
		checked,
		"OK" if probe_ok and checked > 0 else (
			"SKIPPED, no wall in the world" if checked == 0 and not HOUSE_ENABLED
			else "FAIL")])

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
		if k == "" or CozyHud.index_for_hotkey_text(k) != i:
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

	# (1b) OFFERING a point is not the same as REACHING it, and only one of those
	# was ever checked. A container nothing can walk to is a container that does
	# not exist as far as §45's chain is concerned — and that failure is invisible
	# in every count, because the point is still advertised and still free.
	var reachable := false
	var route_len := 0
	if npc != null and npc.navigator != null and not pts.is_empty():
		var route := npc.navigator.plan(npc.global_position, pts[0].world_position)
		reachable = not route.is_empty()
		route_len = route.size()
	print("[cozyv2] container store point is reachable: %s (%d waypoint(s) from the resident)  [%s]" % [
		str(reachable), route_len,
		"OK" if reachable else "FAIL, the chest is advertised but unreachable"])

	if npc == null or npc.npc_state == null or npc.npc_state.inventory == null:
		print("[cozyv2] container transfers: no resident with a pack  [SKIP]")
		return
	var pack := npc.npc_state.inventory

	# The GENERIC transfer is what a job with no recipe does, and that is the
	# `hauler` — moving goods is the whole trade. A cook's transfer is
	# recipe-directed (it puts down bread, not lumber) and is asserted in
	# `_check_production` instead. Testing both through one job would mean
	# testing neither.
	var job_before := npc.npc_state.job_id
	npc.npc_state.job_id = "hauler"
	# Snapshot of the LIVE chest and pack. This check moves goods around in both,
	# and it runs before the resident has done any work — so leaving them empty
	# would gut the world the production chain is supposed to run in. An assertion
	# that corrupts what it measures corrupts every check after it too.
	var chest_before := c.inventory.items.duplicate()
	var pack_before := pack.items.duplicate()

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

	# Leave the world exactly as it was found.
	npc.npc_state.job_id = job_before
	c.inventory.items = chest_before
	pack.items = pack_before


## §45's live chain, end to end — the one question `_check_production` cannot
## answer: did the goods actually MOVE?
##
## That check swaps in a probe state and calls `_produce()` directly, so it would
## pass in a world with no resident, no chest and no navigation. This one asks the
## world.
##
## IT WAS DELIBERATELY NOT WRITTEN ON 2026-09-14, and the note it left behind in
## `_check_npc_work` is the reason this project writes notes: an assertion written
## to pass on that evidence would have been measuring the wrong thing. The chain
## was stuck — a resident leaving for a 13-waypoint route to a chest three
## waypoints away, spending ten game hours with `stuck` climbing to 3.0 and never
## arriving — and `_check_production` was green throughout, because the arithmetic
## was never what was broken.
##
## The cause was the navigation grid routing the resident as a POINT (see
## `docs/INVARIANTS.md`). With that fixed the honest assertion is available, and it
## is a different animal from the mechanical one: bread in the chest can only have
## got there by a resident withdrawing wheat, baking it, and carrying it back.
##
## Reading the chest is safe because `_check_container` puts back exactly what it
## found — "Leave the world exactly as it was found" — so anything different is
## the chain's doing and not a check's. That was one of the two ways this
## assertion was got wrong before, so it is written down rather than trusted.
func _check_production_chain_live() -> void:
	var chest := _first_object("chest")
	if chest == null or chest.container == null:
		print("[cozyv2] production chain ran live: no chest to read  [FAIL]")
		return

	var wheat := chest.container.inventory.count("wheat")
	var bread := chest.container.inventory.count("bread")
	var wheat_start := float(_starter_chest.get("wheat", 0.0))
	var bread_start := float(_starter_chest.get("bread", 0.0))
	var carried := 0.0
	if npc != null and npc.npc_state != null:
		carried = npc.npc_state.inventory.count("wheat") \
			+ npc.npc_state.inventory.count("bread")

	# BOTH legs, and the wheat leg is the one that cannot be faked.
	#
	# `bread > 0` alone is NOT evidence, and this was measured rather than
	# assumed: the resident spawns with a starter larder of three loaves
	# (`_build_characters`), `_haul` deposits what it carries before it withdraws
	# anything, so a world whose chest starts EMPTY still ends with bread in it.
	# The first version of this check asserted `bread > 0` and passed on exactly
	# that world — a check that agreed with a chain which had never run.
	#
	# Wheat leaving the chest cannot be produced that way: an empty chest has no
	# wheat to leave, and the comparison is against what the chest actually held
	# rather than against the constant that was supposed to fill it.
	var withdrew := wheat < wheat_start - 0.0001
	var delivered := bread > bread_start + 0.0001
	print("[cozyv2] production chain ran live: chest wheat %.0f -> %.0f, bread %.0f -> %.0f, carrying %.0f, %d job(s)  [%s]" % [
		wheat_start, wheat, bread_start, bread, carried, npc.completions,
		"OK" if withdrew and delivered else
		"FAIL, the chain did not run: took materials=%s brought goods back=%s" % [
			str(withdrew), str(delivered)]])


## §45's production chain, mechanically.
##
## The live half — that the chain actually RUNS on the real resident — is asserted
## in `_check_npc_work`, once the resident has had time to work. This half proves
## the pieces: that the trade resolves to a recipe, that a recipe names no
## workstation, and that inputs are a requirement rather than a decoration.
func _check_production() -> void:
	# (1) The live trade resolves to a recipe, and the recipe names a JOB and item
	#     ids — never an object, a room or a position. That is doc #45's own
	#     constraint: "NPC 不应该因为增加一个新工作台而增加一段特殊硬编码."
	var rid := CozyRecipeDefs.id_for_job(NPC_JOB)
	# BY POINT TYPE, not by trade: `for_point` replaced `for_job` on 2026-09-15,
	# and a recipe is now what a KIND OF WORK makes rather than what a trade makes.
	var r := CozyRecipeDefs.for_point(CozyJobDefs.point_type(NPC_JOB))
	# Typed by hand: `r["inputs"]` is a Variant, so `and` cannot infer a bool.
	var ins: Dictionary = r.get("inputs", {})
	var outs: Dictionary = r.get("outputs", {})
	var wired: bool = rid != "" and not r.is_empty() and String(r["job"]) == NPC_JOB \
		and ins.has("wheat") and outs.has("bread")
	print("[cozyv2] recipe for the live trade: %s (%s)  [%s]" % [
		rid, r.get("point_type", "-"), "OK" if wired else "FAIL, the live resident has no recipe"])
	if not wired:
		return

	# Swapped in so the production path can be driven directly, then put back.
	# `produced` is snapshotted too: the probe's batches are not the resident's,
	# and a check that increments the counter it later reads is measuring itself.
	var live := npc.npc_state
	var produced_before := npc.produced
	var st := CozyNpcState.create("production_probe", "Probe", NPC_JOB, 11)
	st.traits = []
	npc.npc_state = st

	# (2) No inputs, no outputs. A chain that can run from an empty pack is not a
	#     chain, it is a conjuring trick — the same rule as eating needing food.
	var failed := npc._produce(r)
	var refused := failed != "" and st.inventory.total() == 0.0
	print("[cozyv2] production with no inputs: \"%s\", produced %.0f  [%s]" % [
		failed, st.inventory.total(),
		"OK" if refused else "FAIL, production is free"])

	# (3) With inputs, it consumes them and yields exactly the recipe's outputs.
	st.inventory.add("wheat", 4.0)
	var made := npc._produce(r)
	var consumed := st.inventory.count("wheat") == 2.0
	var yielded := st.inventory.count("bread") == 3.0
	print("[cozyv2] production: %s -> wheat %.0f left, bread %.0f  [%s]" % [
		made, st.inventory.count("wheat"), st.inventory.count("bread"),
		"OK" if consumed and yielded else "FAIL, the batch did not balance"])

	npc.npc_state = live
	npc.produced = produced_before


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


# ---------------------------------------------------------------- entity registry

## A kind name that exists only inside the registry's tooth test below.
const ENTITY_PROBE_KIND := "duplicate_probe"


## The entity index (Core Architecture V1.0, item 1).
##
## Three claims, and the third is the one with teeth:
##   1. every entity resolves by its own id, back to the very object that owns it
##   2. no two entities offer the same id — which no single system could notice,
##      because each one only ever saw its own list
##   3. the registry CATCHES a duplicate when there is one. Claim 2 alone passes
##      just as well when the detector is broken and there is nothing to find,
##      which is the shape this project has paid for repeatedly.
func _check_entity_registry() -> void:
	if entities == null:
		print("[cozyv2] entity registry: not built  [FAIL]")
		return

	# Counted against the lists the owners actually hold, not against another
	# number from the registry: a provider that silently stopped returning a kind
	# would agree with itself and go green.
	var per_kind := {
		CozyEntityRegistry.WALL: building.state.walls.size(),
		CozyEntityRegistry.SLAB: building.state.slabs.size(),
		CozyEntityRegistry.STAIR: building.state.stairs.size(),
		CozyEntityRegistry.ROOF: building.state.roofs.size(),
		CozyEntityRegistry.OBJECT: objects.size(),
		CozyEntityRegistry.NPC: 1 if npc != null and npc.npc_state != null else 0,
		CozyEntityRegistry.PLAYER: 1 if player_state != null else 0,
	}
	var complete := true
	for kind in per_kind:
		if entities.all_of(kind).size() != int(per_kind[kind]):
			complete = false
	# AND THE LIST ABOVE HAS TO BE THE WHOLE LIST. It is hand-written, so a kind
	# registered in `_build_entity_registry` and forgotten here would never be
	# counted — the check would agree with itself about a provider that returns
	# nothing at all, which is the shape this file exists to refuse.
	for kind in entities.kinds():
		if not per_kind.has(String(kind)):
			complete = false

	# A lookup that returns *something* is not the claim; returning THIS is.
	var resolves := true
	for e in entities.entities():
		if entities.state_of(String(e["id"])) != e["state"]:
			resolves = false
			break

	var dupes := entities.duplicate_ids()
	print("[cozyv2] entity registry: %s; per-kind matches owners=%s, ids resolve=%s, duplicates=%s  [%s]" % [
		entities.describe(), str(complete), str(resolves), str(dupes),
		"OK" if complete and resolves and dupes.is_empty() else "FAIL"])

	_check_entity_registry_teeth()


## The detector, driven through a case it has to catch.
##
## A second kind is registered that offers an id the wall kind already has. The
## duplicate must be REPORTED, and an unqualified lookup must REFUSE rather than
## pick one — while a kind-scoped lookup still resolves, which is the escape
## hatch that keeps `state_of` usable in a world that has gone wrong.
func _check_entity_registry_teeth() -> void:
	if building.state.walls.is_empty():
		print("[cozyv2] entity registry teeth: no wall to duplicate  [FAIL]")
		return
	var victim: CozyWallState = building.state.walls[0]

	entities.register_kind(ENTITY_PROBE_KIND, func() -> Array: return [victim])

	var found := entities.duplicate_ids()
	var refused := entities.state_of(victim.id) == null
	var scoped: Object = entities.state_of(victim.id, CozyEntityRegistry.WALL)

	# Removed whatever happened, so a failure here cannot poison the save that
	# runs later in the same process.
	entities.unregister_kind(ENTITY_PROBE_KIND)

	var ok := found.has(victim.id) and refused and scoped == victim
	print("[cozyv2] entity registry teeth: injected a second %s - reported=%s, unscoped lookup refused=%s, scoped found it=%s  [%s]" % [
		victim.id, str(found), str(refused), str(scoped == victim),
		"OK" if ok else "FAIL, the registry did not catch its own duplicate"])


# ---------------------------------------------------------------- save / load

## The whole world, as facts (doc #63). Everything derived is excluded on
## purpose: meshes, room polygons, portals, navigation grids and paths are all
## rebuilt on load by the generators that built them the first time.
##
## ONE entity list, not one top-level key per system (Core Architecture V1.0,
## item 1). The list comes from the registry, and which kinds are persisted is
## decided at REGISTRATION rather than here — so a new derived kind cannot leak
## into the file by being forgotten at this one call site.
##
## Terrain and the id counters keep their own keys because neither is an entity:
## terrain is a field, and a counter has no id to be addressed by.
func _world_to_dict() -> Dictionary:
	var ents: Array = []
	for e in entities.persisted_entities():
		ents.append(entities.encode_entity(e))
	return {
		"entities": ents,
		"next_ids": _next_ids_to_dict(),
		"terrain": terrain.to_dict(),
		"clock": {"day": clock.day, "hour": clock.hour},
	}


func _next_ids_to_dict() -> Dictionary:
	var ids := building.state.counters_to_dict()
	ids["object"] = _next_object_id
	return ids


## Rebuild the world from facts. The order below is the order the world is built
## in the first place (see `_ready`), which is the only reason it works: terrain
## before building, building before rooms, rooms before roofs.
##
## The one entity list is regrouped by kind and handed to the system that owns
## each kind. The registry can INDEX any state but it cannot INSTALL one — a
## decoded wall has to be appended to `building.state.walls` by the thing that
## owns that list — so the load path is where the split shows, and it is why the
## registry carries encoders but not decoders.
func _apply_world(d: Dictionary) -> void:
	if d.is_empty():
		return

	terrain.from_dict(d.get("terrain", {}))
	terrain_renderer.rebuild_all()

	# Roofs are cleared by `from_dict` rather than restored — `_build_roofs`
	# refills them below from the rooms it just re-derived.
	building.state.from_dict({
		"walls": CozyEntityRegistry.payloads(d, CozyEntityRegistry.WALL),
		"slabs": CozyEntityRegistry.payloads(d, CozyEntityRegistry.SLAB),
		"stairs": CozyEntityRegistry.payloads(d, CozyEntityRegistry.STAIR),
	})
	# After `from_dict`, so a missing counter falls back to one past the entities
	# that are actually here rather than to one past nothing.
	building.state.counters_from_dict(d.get("next_ids", {}))

	for o in objects:
		if is_instance_valid(o):
			o.queue_free()
	objects.clear()
	for od in CozyEntityRegistry.payloads(d, CozyEntityRegistry.OBJECT):
		# Add first, exactly as `_place_object` does: setup() phases VFX from the
		# world position, which does not exist until the node is parented.
		var o := CozyWorldObject.new()
		add_child(o)
		o.apply_dict(od)          # carries its own id back in
		objects.append(o)
	_next_object_id = int((d.get("next_ids", {}) as Dictionary).get(
		"object", objects.size() + 1))

	var npcs := CozyEntityRegistry.payloads(d, CozyEntityRegistry.NPC)
	if npc != null and not npcs.is_empty():
		npc.npc_state = CozyNpcState.from_dict(npcs[0])

	# The player's ledger. An old save has no such entry and that is not an
	# error: it means the pack was empty, which is what a new one is.
	var players := CozyEntityRegistry.payloads(d, CozyEntityRegistry.PLAYER)
	if player_state != null and not players.is_empty():
		player_state = CozyPlayerState.from_dict(players[0])

	var c: Dictionary = d.get("clock", {})
	if not c.is_empty():
		clock.day = int(c.get("day", 1))
		clock.hour = float(c.get("hour", CozyTimeSystem.START_HOUR))

	building.regenerate()
	# This re-derives rooms, portals, the room graph and BOTH navigation layers,
	# and re-links the agent's navigator and object list at the end of it.
	_rebuild_spatial()
	_build_roofs()
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

## A material the DEFAULT world does not start with, put in the PLAYER's pack
## before the file is written. If the pack is not saved, pass 2 finds nothing and
## says so — which an in-memory round trip cannot, because it never goes near a
## file. `copper` rather than wood on purpose: the player starts with none, and a
## marker that is also a default cannot tell "saved" from "never changed".
const XPROC_COPPER := 7.0

## A real v1 save, kept in the repo so the migration is driven by output the game
## actually produced rather than by a hand-written idea of the format.
const V1_FIXTURE := "res://tests/fixtures/saves/v1_world.json"

## What that file holds. Counted once, here, so a fixture that changes shape
## cannot quietly stop being the thing this check is about.
const V1_WALLS := 10
const V1_SLABS := 3
const V1_STAIRS := 1
const V1_OBJECTS := 6

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
	if player_state != null:
		player_state.pack.add("copper", XPROC_COPPER)
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
	var carried := player_state.pack.count("copper") if player_state != null else -1.0
	print("[cozyv2] cross-process player pack: copper %.0f of %.0f  [%s]" % [
		carried, XPROC_COPPER,
		"OK" if is_equal_approx(carried, XPROC_COPPER)
			else "FAIL, the player's pack did not survive the file"])
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
	# Snapshot first: this seeds the LIVE chest to give the round trip something to
	# lose, and has to put back what it found. It runs before the resident works.
	var chest_before := {}
	if chest != null and chest.container != null:
		chest_before = chest.container.inventory.items.duplicate()
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
	b.from_dict({
		"walls": CozyEntityRegistry.payloads(loaded, CozyEntityRegistry.WALL),
		"slabs": CozyEntityRegistry.payloads(loaded, CozyEntityRegistry.SLAB),
		"stairs": CozyEntityRegistry.payloads(loaded, CozyEntityRegistry.STAIR),
	})
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
	var live_objs: Array = CozyEntityRegistry.payloads(before, CozyEntityRegistry.OBJECT)
	var back_objs: Array = CozyEntityRegistry.payloads(loaded, CozyEntityRegistry.OBJECT)
	var object_ok := back_objs.size() == live_objs.size() and not back_objs.is_empty()
	var container_note := "no container"
	if object_ok:
		for i in back_objs.size():
			var a: Dictionary = live_objs[i]
			var z: Dictionary = back_objs[i]
			# Identity as well as shape: an object that came back as a different
			# object with the right definition is the failure this id was added for.
			if String(a.get("id", "")) != String(z.get("id", "")) \
					or String(a.get("def_id", "")) != String(z.get("def_id", "")):
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
	var npcs: Array = CozyEntityRegistry.payloads(loaded, CozyEntityRegistry.NPC)
	var npc_ok := false
	var npc_note := "no resident in the file"
	if not npcs.is_empty() and live_npc != null:
		var n := CozyNpcState.from_dict(npcs[0])
		# Derived from the trade, so this follows the resident's job instead of
		# naming a skill the job may no longer use.
		var trade := CozyJobDefs.primary_skill(live_npc.job_id)
		npc_ok = n.id == live_npc.id and n.display_name == live_npc.display_name \
			and n.job_id == live_npc.job_id \
			and absf(n.hunger - live_npc.hunger) < 0.001 \
			and absf(n.energy - live_npc.energy) < 0.001 \
			and n.skill(trade) == live_npc.skill(trade)
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
	var stairs_before := building.state.stairs.size()

	_apply_world(loaded)
	# A ROUND TRIP, not an absolute count. This used to end with
	# `and building.state.stairs.size() > 0` — which asserts that a stair EXISTS,
	# a fact about the demo house and not about saving at all. Every other clause
	# here compares what went in with what came out; that one clause demanded a
	# particular world. With the house parked the save was still a faithful round
	# trip and this check failed anyway, which is how it was found.
	var applied := building.state.wall_count() == walls_before \
		and objects.size() == objs_before \
		and floor_system.all_rooms().size() == rooms_before \
		and building.state.stairs.size() == stairs_before \
		and npc.npc_state != null and npc.npc_state.id == live_npc.id
	print("[cozyv2] save/load applied live: %d wall(s), %d slab(s), %d stair(s), %d room(s), %d object(s)  [%s]" % [
		building.state.wall_count(), building.state.slabs.size(),
		building.state.stairs.size(), floor_system.all_rooms().size(), objects.size(),
		"OK" if applied else "FAIL"])

	# (6) An OLD file, through the real load path.
	#
	# The migration has its own unit tests, but they prove the SHAPE it produces
	# and nothing more. This is the part they structurally cannot reach: that a
	# v1 file goes through `load_world` -> `migrate` -> `_apply_world` and lands
	# as a world. A migration nothing consumes is the "declared capability with
	# no consumer" shape one layer down, and this project has paid for that shape
	# seven times.
	#
	# The fixture is real output from the game (10 walls, 3 slabs, 1 stair, 6
	# objects, 1 resident), so the counts below are the file's, not a guess.
	var v1_ok := false
	var v1_note := "fixture unreadable"
	var v1_path := "user://selfcheck_v1.json"
	var fixture := FileAccess.get_file_as_string(V1_FIXTURE)
	if not fixture.is_empty():
		var vf := FileAccess.open(v1_path, FileAccess.WRITE)
		vf.store_string(fixture)
		vf.close()
		var old := CozySaveManager.load_world(v1_path)
		if old.is_empty():
			v1_note = "refused by load_world"
		else:
			_apply_world(old)
			v1_ok = building.state.walls.size() == V1_WALLS \
				and building.state.slabs.size() == V1_SLABS \
				and building.state.stairs.size() == V1_STAIRS \
				and objects.size() == V1_OBJECTS \
				and npc.npc_state != null and npc.npc_state.id == "npc_001"
			v1_note = "%d wall(s), %d slab(s), %d stair(s), %d object(s), resident %s" % [
				building.state.walls.size(), building.state.slabs.size(),
				building.state.stairs.size(), objects.size(),
				npc.npc_state.id if npc.npc_state != null else "none"]
		CozySaveManager.erase(v1_path)
	print("[cozyv2] save/load a v1 file through the real path: %s  [%s]" % [
		v1_note, "OK" if v1_ok else "FAIL"])

	# (7) Put the world back and prove THAT round trip too — a check that leaves
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
		chest2.container.inventory.items = chest_before


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
## The structural fade rule, measured where it applies.
##
## WHY THIS ASKS FOR THE TOTAL AND NOT FOR THE RAY. `_probe_occlusion_at` reports
## "of the colliders on the camera-to-player ray, how many are faded" — and a
## structural rule is invisible to that BY CONSTRUCTION, because the whole point
## is to fade the pieces that are NOT on the ray. It was chased for several
## rounds on that number: the renderer was fading nine fadables while the probe
## said two, and the rule looked broken the whole time. A measurement has to be
## of the thing the rule changes.
##
## It moves the player twice and puts them back, because the rule is about where
## the resident is standing and there is no other way to ask.
## `_probe_occlusion_sweep` already does the same thing for the same reason.
func _check_occlusion_structure() -> void:
	if occlusion == null or player == null or camera == null:
		print("[cozyv2] occlusion structure: NOT BUILT  [FAIL]")
		return

	var kept := player.global_position

	# Outdoors the rule is deliberately OFF: "above my floor" would be the whole
	# house, and fading it every time the player walks past is a different
	# request from seeing into the room they are standing in.
	player.global_position = SPAWN_POINT
	camera.snap_to_target()
	occlusion.refresh()
	var outside := occlusion.faded_count()

	# COUNTED AFTER THE FIRST REFRESH, because `occlusion.fadables` is filled BY
	# a refresh and is empty before one. The first version counted first and
	# reported zero pieces above floor 0 while the very next line faded nine.
	var above := 0
	for w in occlusion.fadables:
		var st := _fadable_state(w)
		if st != null and int(st.floor_id) > 0:
			above += 1

	# Inside, everything above the resident is see-through, plus the wall on the
	# camera's side of them.
	player.global_position = Vector3(4.0, 0.2, 3.0)
	camera.snap_to_target()
	occlusion.refresh()
	var inside := occlusion.faded_count()

	player.global_position = kept
	camera.snap_to_target()
	occlusion.refresh()

	print("[cozyv2] occlusion structure: %d fadable(s) above floor 0; outdoors=%d faded, indoors on floor 0=%d faded  [%s]" % [
		above, outside, inside,
		"OK" if above > 0 and outside == 0 and inside >= above
		else "FAIL, what is above the resident is not being cleared"])


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

	# The fade set must be exactly the LIVE views.
	#
	# "0 faded" cannot say whether that holds: it is equally what a list full of
	# freed nodes produces and what a ray reaching the character unobstructed
	# produces. Measured 2026-09-12 with the occlusion probe — the list held a
	# freed roof, the live roof was missing, and all three slabs were missing,
	# while the line above printed OK.
	occlusion.refresh()
	var live := _current_fadables()
	var freed := 0
	for f in occlusion.fadables:
		if not is_instance_valid(f):
			freed += 1
	var missing := 0
	for v in live:
		if not occlusion.fadables.has(v):
			missing += 1
	print("[cozyv2] occlusion fade set: %d listed, %d live, %d freed, %d missing  [%s]" % [
		occlusion.fadables.size(), live.size(), freed, missing,
		"OK" if freed == 0 and missing == 0 else "FAIL, the fade set is not the live views"])

	_check_opening_shot()


## The self-check's own bookkeeping: every UNGATED stage must have RUN.
##
## The failure this exists for is silent by construction. A stage scheduled at a
## frame the run never reaches simply never fires — no error, no warning — and
## the suite looks exactly as green as it does when the stage passed. Scheduling
## one at 9000 against a 4500-frame baseline would quietly retire a check, and
## nothing else in this file would notice.
##
## Gated stages are excluded: a probe behind a command-line flag not running is
## the normal case, not a failure.
##
## ⚠️ THE FRAME BUDGET. `--quit-after` counts IDLE frames and the headless physics
## tick advances at roughly 0.42 of that, so the 4500-frame baseline reaches only
## about physics frame 1880. A stage scheduled past that NEVER FIRES, silently.
## This check is scheduled at 1600 for exactly that reason, and `_exit_tree()`
## reports the same thing even when the run was too short to reach here.
func _check_self_check() -> void:
	var pending: Array[String] = []
	for name in self_check.required_names():
		if not self_check.has_run(name):
			pending.append(name)
	print("[cozyv2] self-check schedule: %s, pending=%s  [%s]" % [
		self_check.describe(),
		"none" if pending.is_empty() else ",".join(pending),
		"OK" if pending.is_empty() else "FAIL, a scheduled stage never ran"])


## PROBE, not an assertion. Where does the hauling resident actually get stuck?
##
## Added 2026-09-12 on debt 22. The evidence is `why=blocked, replanning`, which
## says the agent is NOT MOVING — and rules nothing else out: an interaction point
## on the wrong side of a wall, a path that crosses geometry, and a body pinned
## against it all end in that same line.
##
## So it measures all four candidates the design names, instead of picking one
## and looking for proof of it:
##
##   A  the interaction point's world position is wrong, or inside its own object
##   B  the path the navigator returned crosses something it should not
##   C  the path is fine and the BODY cannot follow it
##   D  the point was chosen by straight-line distance and is not reachable
##
## Run:  godot --headless --path <repo> --quit-after 1500 -- --cozy-probe-npc-pathing
##
## WHEN IT RUNS. It used to fire at a fixed frame, and a fixed frame is a coin
## toss: the resident is only ever pressed against the thing that is stopping it
## some of the time. The 2026-09-14 run reported `blocking cast: nothing between
## the agent and waypoint N` while the same build, at the same time, had a
## resident stuck for hundreds of frames at `wp=2/29 stuck=1.5` — the probe had
## sampled a moment when nothing was wrong, and a clean probe read as a clean
## system.
##
## So it now fires on the FIRST moment the resident has stood still long enough
## WHILE WALKING that standing still is the only explanation. That is the moment
## the question is about, and it is not one a frame number can be picked to hit.
##
## `_stuck_time` lives in `CozyNpcAgent` and is deliberately not read here: this
## is a measurement of the AGENT's body, and taking it from the agent's own
## bookkeeping would make the probe agree with the thing it is checking.
const STUCK_WATCH_SECONDS := 3.5   ## Longer than the agent's own 3 s replan, so
                                   ## the report lands after a replan attempt.
const STUCK_WATCH_METRES := 0.05   ## Below this it is not walking, it is jitter.

var _stuck_watch_last := Vector3.ZERO
var _stuck_watch_has_last := false
var _stuck_watch_time := 0.0
var _stuck_watch_fired := false


func _watch_for_a_stuck_resident(delta: float) -> void:
	if _stuck_watch_fired or npc == null or not is_instance_valid(npc):
		return

	# ONLY while it is walking. A resident standing at a workbench has not moved
	# either, and the first version of this watcher fired at frame 319 on exactly
	# that: `npc WORKING ... wp=20/20 stuck=0.0`, a resident doing its job. The
	# symptom is not "not moving", it is "not moving WHILE TRYING TO".
	#
	# This is the third time in this one probe that the measurement was correct
	# and its timing was not — the fixed frame sampled a calm moment, and now the
	# motion test sampled a stationary one. A probe that fires at the wrong
	# moment does not report "unknown", it reports "fine".
	if npc.fsm_state != CozyNpcAgent.State.GOING:
		_stuck_watch_time = 0.0
		_stuck_watch_has_last = false
		return

	var here := npc.global_position
	if _stuck_watch_has_last and here.distance_to(_stuck_watch_last) < STUCK_WATCH_METRES:
		_stuck_watch_time += delta
	else:
		_stuck_watch_time = 0.0
	_stuck_watch_last = here
	_stuck_watch_has_last = true

	if _stuck_watch_time < STUCK_WATCH_SECONDS:
		return
	_stuck_watch_fired = true
	print("[cozyv2] probe npc pathing: TRIGGERED at frame %d — the resident moved less than %.2f m in %.1f s" % [
		Engine.get_physics_frames(), STUCK_WATCH_METRES, _stuck_watch_time])
	_probe_npc_pathing()


func _probe_npc_pathing() -> void:
	if npc == null or npc.navigator == null:
		print("[cozyv2] probe npc pathing: NOT BUILT")
		return

	print("[cozyv2] probe npc pathing | %s" % npc.debug_line())

	# ---- D: what it CHOSE, and what else was on offer -----------------------
	#
	# The whole ranked list, not just its head: `chose: chop` means one thing from
	# a resident whose list was `chop` alone and another from one that passed over
	# `store` to get there. Reading only the head is how "the trade was overridden
	# by the schedule's work block" stayed invisible for a day.
	var want := npc.want_point_types()
	var chosen: CozyInteractionPoint = npc.target_point()
	print("[cozyv2]   wants (ranked): %s" % (
		"(%s)" % "nothing" if want.is_empty() else ", ".join(want)))
	if chosen == null:
		print("[cozyv2]   chose: nothing (no target point)")
	else:
		print("[cozyv2]   chose: %s  point=%s  straight=%.2f m" % [
			_object_label(npc.target_object()), chosen.type,
			npc.global_position.distance_to(chosen.world_position)])

	# Every candidate, straight-line distance against reachability. This is the
	# measurement that separates "nearest" from "reachable" — the two are the same
	# number only when nothing is in the way.
	print("[cozyv2]   candidates (straight-line vs reachable):")
	for o in objects:
		if not is_instance_valid(o):
			continue
		for pt in o.free_points_of_type(chosen.type if chosen != null else ""):
			var straight := npc.global_position.distance_to(pt.world_position)
			var route: Array = npc.navigator.plan(npc.global_position, pt.world_position)
			print("[cozyv2]     %-14s %-8s straight=%5.2f m  path=%s" % [
				_object_label(o), pt.type, straight,
				("%d wp" % route.size()) if not route.is_empty() else "NO ROUTE"])

	# ---- B: the path itself -------------------------------------------------
	var path: PackedVector3Array = npc.current_path()
	print("[cozyv2]   path: %d waypoint(s)" % path.size())
	for i in mini(path.size(), 24):
		print("[cozyv2]     %2d (%.2f, %.2f, %.2f)" % [i, path[i].x, path[i].y, path[i].z])

	# Does any leg of the path pass through geometry? A path that does is a
	# navigator fault, and the body cannot follow it no matter how good it is.
	var crossings := 0
	var first_crossing := ""
	var space := npc.get_world_3d().direct_space_state
	for i in range(1, path.size()):
		var q := PhysicsRayQueryParameters3D.create(
			path[i - 1] + Vector3(0.0, 0.9, 0.0), path[i] + Vector3(0.0, 0.9, 0.0))
		q.collide_with_areas = false
		q.exclude = [npc.get_rid()]
		var h := space.intersect_ray(q)
		if not h.is_empty():
			crossings += 1
			if first_crossing == "":
				first_crossing = "leg %d-%d hits %s" % [i - 1, i, _describe_collider(h["collider"])]
	print("[cozyv2]   path crosses geometry: %d leg(s)%s" % [
		crossings, "" if crossings == 0 else "  first: " + first_crossing])

	# ---- C: what stops the BODY --------------------------------------------
	# Cast from the agent toward its next waypoint. Whatever it hits is the thing
	# the body is pressed against — named, not guessed.
	if path.size() > 0:
		var wp_i: int = npc.path_index()
		var target_wp: Vector3 = path[mini(wp_i, path.size() - 1)]
		var from := npc.global_position + Vector3(0.0, 0.9, 0.0)
		var to := Vector3(target_wp.x, from.y, target_wp.z)
		var q2 := PhysicsRayQueryParameters3D.create(from, to)
		q2.collide_with_areas = false
		q2.exclude = [npc.get_rid()]
		var h2 := space.intersect_ray(q2)
		if h2.is_empty():
			print("[cozyv2]   blocking cast: nothing between the agent and waypoint %d" % wp_i)
		else:
			print("[cozyv2]   blocking cast: %s at %.2f m" % [
				_describe_collider(h2["collider"]), from.distance_to(h2["position"])])
			_probe_wall_openings(h2["collider"])

	# ---- A: is the point where it claims to be? ----------------------------
	#
	# ONLY FOR WORK AT A WORLD OBJECT. The target can now be the GROUND
	# (`CozyGroundPoints`), which has no footprint and no origin — and "is the
	# point inside the object it belongs to" is not a question about a patch of
	# field. The guard is written rather than the type relied on, because this is
	# a probe: a probe that crashes reports nothing about the thing it was pointed
	# at, and the pathing probe is the instrument this project uses for exactly
	# the faults that are hardest to see (`--cozy-probe-npc-pathing`).
	if chosen != null:
		var obj: Node3D = npc.target_object()
		# A CAST, not an `is` guard: GDScript does not narrow a variable's static
		# type through `is`, so `obj.footprint_rect()` stays an unresolvable call
		# on Node3D and the whole of main.gd fails to parse.
		var wo := obj as CozyWorldObject
		if wo != null:
			var inside := wo.footprint_rect().has_point(
				Vector2(chosen.world_position.x, chosen.world_position.z))
			var off := chosen.world_position.distance_to(
				wo.to_global(Vector3.ZERO))
			print("[cozyv2]   point geometry: %.2f m from the object's origin, inside_own_footprint=%s  [%s]" % [
				off, str(inside),
				"FAIL, the point is inside the object it belongs to" if inside else "OK"])
		elif obj != null:
			print("[cozyv2]   point geometry: offered by the GROUND at (%.2f, %.2f) — no object to measure against" % [
				chosen.world_position.x, chosen.world_position.z])


## DECISIVE MEASUREMENT for the wall that is blocking.
##
## The hypothesis it tests: the wall's STATE carries a door opening while its
## GENERATED GEOMETRY does not — because `WallState.add_opening()` only appends to
## a list and `_rebuild_spatial()` rebuilds rooms, portals and navigation, not
## wall meshes. Navigation reads the state and routes through the door; physics
## reads the collider and stops at a solid wall.
##
## So: count the openings the state claims, then cast a ray straight through the
## middle of the first one. A wall whose state says "door here" and whose
## collider says "solid" is the whole bug, and it is measurable in one line.
func _probe_wall_openings(collider: Object) -> void:
	var parent: Node = collider.get_parent()
	if not (parent is CozyWall):
		return
	var state: CozyWallState = parent.state
	if state == null:
		return
	print("[cozyv2]   blocker %s claims %d opening(s)" % [state.id, state.openings.size()])
	if state.openings.is_empty():
		return
	# Walk through the door's own centre, at chest height, along the wall's normal.
	var o: CozyOpening = state.openings[0]
	var along := (state.end - state.start).normalized()
	var across := Vector3(-along.z, 0.0, along.x)
	var centre: Vector3 = state.start + along * o.offset + Vector3(0.0, 0.9, 0.0)
	var q := PhysicsRayQueryParameters3D.create(centre - across * 1.6, centre + across * 1.6)
	q.collide_with_areas = false
	var hit := npc.get_world_3d().direct_space_state.intersect_ray(q)
	print("[cozyv2]   cast through %s's door centre: %s  [%s]" % [
		state.id,
		"SOLID" if not hit.is_empty() else "open",
		"FAIL, navigation has a hole the collider does not" if not hit.is_empty() else "OK"])


## A one-word label for an object, for probe output. Node names are
## engine-generated (`@Node3D@88`) and identify nothing.
func _object_label(o: Object) -> String:
	if o == null or not is_instance_valid(o):
		return "(none)"
	if o is CozyWorldObject:
		return String(o.def_id)
	return o.get_class().to_lower()


## The view the game OPENS ON, measured rather than assumed.
##
## The spawn point is the first place the player sees their own character, so the
## camera must have a clear line to it — nothing between the two, and therefore
## nothing that has to fade to make the player visible.
##
## BOTH NUMBERS ARE ASSERTED, and the second one is the one with teeth. An opaque
## count of zero alone passes at any angle where the fade rule happens to rescue
## the shot; requiring that NOTHING faded says the framing itself is right, and it
## is what separates a camera on the front of the house from one on the back.
##
## Measured 2026-09-12 with the yaw sweep in `--cozy-probe-occlusion`: at yaw 0 the
## spawn needs the roof and the upper south wall faded before the player is
## visible, because the door is cut into the z = 0 wall and yaw 0 puts the camera
## on the far side of the house. That was the whole "front yard is hidden" bug.
func _check_opening_shot() -> void:
	var keep := player.global_position
	player.global_position = SPAWN_POINT
	camera.snap_to_target()
	occlusion.refresh()
	var opaque := _count_opaque_blockers()
	var faded := occlusion.faded_count()
	# Hand the world back before anything downstream reads it.
	player.global_position = keep
	camera.snap_to_target()
	occlusion.refresh()
	print("[cozyv2] opening shot at spawn: %d opaque, %d faded  [%s]" % [
		opaque, faded,
		"OK" if opaque == 0 and faded == 0 else "FAIL, the opening view is not clear"])


## ART-14: the character sheet contract (Hybrid Pixel Diorama pipeline).
##
## Four things that fail separately, so they are asserted separately:
##
##   1. the SELECTION is right — a resident asleep must not play `work`
##   2. the sheet COVERS what selection can ask for, and nothing it cannot
##   3. the NODE is wired, and its per-frame update is idempotent
##   4. an appearance ID that does not exist is REPORTED, not silently absorbed
func _check_character_visuals() -> void:
	_check_character_selection()
	_check_character_sheet()
	_check_character_node()
	_check_character_appearance()


## Every case here is a fact about the game, not a restatement of the code.
##
## The first row is the whole reason this assertion exists. A resident's sleep
## runs with `fsm_state == WORKING`, so selecting on the FSM alone plays `work`
## for eight straight in-game hours — and the character just looks busy.
func _check_character_selection() -> void:
	var cases: Array = [
		# activity, moving, busy, expected
		["sleep",   false, true,  "sleep"],
		["sleep",   true,  false, "walk"],     # walking to bed is WALKING
		["eat",     false, true,  "sit"],
		["leisure", false, true,  "sit"],      # third sit activity, from the table
		["social",  false, true,  "sit"],
		["work",    false, true,  "work"],
		["work",    false, false, "idle"],
		["wake",    false, false, "idle"],     # nothing to seek, so nothing to do
	]
	var bad: Array[String] = []
	for c in cases:
		var got := CozyCharacterVisuals.select(String(c[0]), bool(c[1]), bool(c[2]))
		if got != String(c[3]):
			bad.append("%s/moving=%s/busy=%s gave %s, wanted %s" % [c[0], c[1], c[2], got, c[3]])
	print("[cozyv2] character anim select: %d case(s), sit=%s  [%s]" % [
		cases.size(), ",".join(CozyCharacterVisuals.sit_activities()),
		"OK" if bad.is_empty() else "FAIL, " + "; ".join(bad)])


## Both directions, and the second is the one this project keeps needing.
##
## Forward: something the selector can return must exist, or the character goes
## blank at that moment. Backward: an animation in the sheet that NO input can
## reach is a sheet nobody will ever see — the "declared capability with no
## consumer" trap, which this project has paid for five times. A `carry`
## animation would land here today: hauling runs inside `fsm_state == WORKING`
## and is indistinguishable from any other work.
func _check_character_sheet() -> void:
	var frames := CozyCharacterVisuals.frames_for(player.appearance)
	var reachable := CozyCharacterVisuals.reachable_animations()
	var missing: Array[String] = []
	var orphans: Array[String] = []
	var wrong: Array[String] = []
	var names := frames.get_animation_names()
	for anim in CozyCharacterVisuals.ANIMATIONS:
		if not frames.has_animation(anim):
			missing.append(anim)
			continue
		var want_frames := int(CozyCharacterVisuals.FRAMES[anim])
		if frames.get_frame_count(anim) != want_frames:
			wrong.append("%s has %d of %d" % [anim, frames.get_frame_count(anim), want_frames])
	for i in names.size():
		if not reachable.has(String(names[i])):
			orphans.append(String(names[i]))
	var ok := missing.is_empty() and orphans.is_empty() and wrong.is_empty()
	print("[cozyv2] character sheet: %d animation(s), reachable=%s, orphan=%s%s  [%s]" % [
		names.size(), ",".join(reachable),
		"none" if orphans.is_empty() else ",".join(orphans),
		"" if wrong.is_empty() else ", wrong frame count: " + "; ".join(wrong),
		"OK" if ok else "FAIL, missing=%s" % ",".join(missing)])


## The node itself. `AnimatedSprite3D` and not `AnimatedSprite2D` — a 2D one is a
## CanvasItem and cannot render in a 3D world at all, which is a mistake that
## shows up as an empty screen rather than as an error.
##
## The idempotence half is not decoration: `_update_animation()` runs every
## physics frame, and this project has already paid three times for a per-frame
## routine that only ever passed single-frame tests.
func _check_character_node() -> void:
	var s := player.sprite
	if s == null or not is_instance_valid(s):
		print("[cozyv2] character anim node: NOT BUILT  [FAIL]")
		return
	var wanted_pixel := CozyCharacter.SPRITE_WORLD_W / float(CozyCharacter.SPRITE_TEX_W)
	var wired: Array[String] = []
	if not (s is AnimatedSprite3D):
		wired.append("node is %s, not AnimatedSprite3D" % s.get_class())
	if s.sprite_frames == null:
		wired.append("no sprite_frames")
	if s.billboard != BaseMaterial3D.BILLBOARD_FIXED_Y:
		wired.append("billboard is not FIXED_Y")
	if not is_equal_approx(s.pixel_size, wanted_pixel):
		wired.append("pixel_size %.4f, wanted %.4f" % [s.pixel_size, wanted_pixel])
	if s.alpha_cut != SpriteBase3D.ALPHA_CUT_DISCARD:
		wired.append("alpha_cut is not DISCARD")

	# Idempotence: 240 per-frame updates must leave the same animation playing.
	var before := s.animation
	var before_playing := s.is_playing()
	for _i in 240:
		player._update_animation()
	if s.animation != before or s.is_playing() != before_playing:
		wired.append("animation drifted over 240 updates (%s -> %s)" % [before, s.animation])

	# And the live NPC's answer must be the pure function of its own inputs —
	# the wiring, not just the logic, has to be connected.
	var npc_want := CozyCharacterVisuals.select(
		npc.current_activity(),
		Vector2(npc.velocity.x, npc.velocity.z).length_squared() > 0.01,
		npc.is_occupied())
	if npc.current_animation() != npc_want:
		wired.append("npc current_animation disagrees with select()")

	print("[cozyv2] character anim node: AnimatedSprite3D playing \"%s\", %d update(s) stable, npc=%s/%s  [%s]" % [
		before, 240, npc.current_activity(), npc_want,
		"OK" if wired.is_empty() else "FAIL, " + "; ".join(wired)])


## A typo in an appearance id has to be REPORTED. Silently falling back to the
## placeholder is how an id and a rendered sheet drift apart with nothing to see:
## the character still draws, it just draws the wrong one.
func _check_character_appearance() -> void:
	var typo := CozyAppearanceDefs.make_default()
	typo["hair"] = "hair_99"
	var bad := CozyAppearanceDefs.unknown_slots(typo)
	var repaired := CozyAppearanceDefs.normalise(typo)
	var partial := CozyAppearanceDefs.normalise({"clothes": "clothes_04"})
	var problems: Array[String] = []
	if bad != ["hair"]:
		problems.append("hair_99 reported as %s" % str(bad))
	if String(repaired["hair"]) != String(CozyAppearanceDefs.DEFAULT["hair"]):
		problems.append("normalise kept the bad id")
	if String(partial["clothes"]) != "clothes_04" or String(partial["hair"]) != String(CozyAppearanceDefs.DEFAULT["hair"]):
		problems.append("a partial appearance was not filled in")
	if CozyAppearanceDefs.ids_for("hair").size() != CozyAppearanceDefs.HAIR.size():
		problems.append("ids_for disagrees with the table")
	print("[cozyv2] character appearance: %d slot(s), %d hair / %d face / %d clothes / %d body / %d color, typo caught=%s  [%s]" % [
		CozyAppearanceDefs.SLOTS.size(),
		CozyAppearanceDefs.HAIR.size(), CozyAppearanceDefs.FACE.size(),
		CozyAppearanceDefs.CLOTHES.size(), CozyAppearanceDefs.BODY.size(),
		CozyAppearanceDefs.COLOR.size(), str(bad == ["hair"]),
		"OK" if problems.is_empty() else "FAIL, " + "; ".join(problems)])


## PROBE, not an assertion. Walk the followed character around the homestead and
## report what the occlusion ray actually does from each spot.
##
## Added 2026-09-12, the day the camera moved to yaw 0 / pitch 40. The fade set is
## a property of the VIEWING ANGLE — the rule in `occlusion.gd` was written
## against a 45/52 oblique that looks down INTO a room, and a front-on camera
## meets the near wall first instead. Which piece of geometry ends up between the
## camera and the player is a fact about the scene, not about the source, so it
## gets measured rather than reasoned about.
##
## THE NUMBER THAT MATTERS is the OPAQUE BLOCKER COUNT: geometry sitting on the
## camera->player ray that did NOT fade. Above zero means the player is genuinely
## hidden and the fade set is wrong for this angle. `faded=` alone cannot tell a
## correct fade from a missing one — which is exactly why the existing check's
## "0 faded" reads as green whatever the camera does.
##
## Run:  godot --headless --path <repo> --quit-after 400 -- --cozy-probe-occlusion
func _probe_occlusion_sweep() -> void:
	if occlusion == null or camera == null:
		print("[cozyv2] probe occlusion: NOT BUILT")
		return

	var keep := player.global_position
	var spots: Array = [
		["front yard (spawn)", SPAWN_POINT],
		["at the door", Vector3(3.25, 0.2, -1.0)],
		["inside floor 0 mid", Vector3(4.0, 0.2, 3.0)],
		["inside floor 0 north", Vector3(4.0, 0.2, 5.0)],
		["inside floor 1", Vector3(2.0, 3.2, 3.0)],
		["north yard", Vector3(4.0, 0.2, 9.0)],
		["east yard", Vector3(11.0, 0.2, 3.0)],
		["west yard", Vector3(-3.0, 0.2, 3.0)],
	]

	print("[cozyv2] probe occlusion sweep: yaw %.0f pitch %.0f %s, %d fadable(s)" % [
		camera.yaw_deg, camera.pitch_deg,
		"perspective" if camera.projection == Camera3D.PROJECTION_PERSPECTIVE else "orthographic",
		occlusion.fadables.size()])
	for f in occlusion.fadables:
		if not is_instance_valid(f):
			print("[cozyv2]   fadable: FREED NODE STILL IN THE LIST")
			continue
		print("[cozyv2]   fadable: %s (bodies=%d)" % [_describe_fadable(f), f.bodies().size()])
	print("[cozyv2]   roof_views=%d slab_views=%d stair_views=%d" % [
		building.roof_views.size(), building.slab_views.size(), building.stair_views.size()])

	for spot in spots:
		player.global_position = spot[1]
		camera.snap_to_target()
		occlusion.refresh()
		_probe_occlusion_at(spot[0])

	_probe_yaw_sweep()

	# A probe reads the world; it must hand it back the way it found it.
	player.global_position = keep
	camera.snap_to_target()
	occlusion.refresh()


## Hold the SPOTS fixed and move the CAMERA ANGLE.
##
## The sweep above answers "where is the player hidden" for one angle. That is not
## enough to act on, because the same spot is clear or occluded depending on where
## the camera stands — and the angle is exactly what is under discussion.
##
## The angle is the thing being measured, so it is varied here on purpose. That
## needs the debug unlock; `lock_view()` puts it back before this returns, so the
## camera-lock assertion still sees a locked camera.
func _probe_yaw_sweep() -> void:
	var spots: Array = [
		["spawn", SPAWN_POINT],
		["door", Vector3(3.25, 0.2, -1.0)],
		["f0 mid", Vector3(4.0, 0.2, 3.0)],
		["north yard", Vector3(4.0, 0.2, 9.0)],
	]
	print("[cozyv2] probe yaw sweep: pitch %.0f, opaque blockers per spot (0 = player visible)" % [
		camera.pitch_deg])
	for y in [0.0, 90.0, 180.0, 270.0]:
		camera.free_look = true
		camera.yaw_deg = y
		camera._apply_angles()
		var line: Array[String] = []
		for s in spots:
			player.global_position = s[1]
			camera.snap_to_target()
			occlusion.refresh()
			line.append("%s=%d/%d" % [s[0], _count_opaque_blockers(), occlusion.faded_count()])
		print("[cozyv2]   yaw %3.0f | cam_z=%7.1f | opaque/faded of %d: %s" % [
			y, camera.global_position.z, occlusion.fadables.size(), "  ".join(line)])
		for s in spots:
			player.global_position = s[1]
			camera.snap_to_target()
			occlusion.refresh()
			var who := _probe_opaque_names()
			if who != "":
				print("[cozyv2]     yaw %3.0f | %-11s blocked by: %s" % [y, s[0], who])
	camera.lock_view()


## Every collider along the camera->player ray, in order, nearest first.
##
## `intersect_ray` returns only the FIRST hit, so the rest are found by re-casting
## with everything already found excluded. That march is the whole point of this
## probe: the occlusion rule itself takes only the first hit, and the question is
## what it is leaving behind.
func _probe_ray_hits() -> Array:
	var from: Vector3 = camera.global_position
	var to: Vector3 = player.global_position + Vector3(0.0, CozyOcclusion.AIM_HEIGHT, 0.0)

	var hits: Array = []
	var exclude: Array[RID] = [player.get_rid()]
	var space := camera.get_world_3d().direct_space_state
	for _i in 24:
		var q := PhysicsRayQueryParameters3D.create(from, to)
		q.collide_with_areas = false
		q.exclude = exclude
		var h := space.intersect_ray(q)
		if h.is_empty():
			break
		hits.append(h)
		exclude.append(h["rid"])
	return hits


## How many colliders on the current camera->player ray did NOT fade.
##
## The number that matters for occlusion: above zero means the player is genuinely
## hidden, whatever the "faded" count says.
func _count_opaque_blockers() -> int:
	var n := 0
	for h in _probe_ray_hits():
		var f: Object = _fadable_owning(h["collider"])
		if f == null or not occlusion.is_faded(f):
			n += 1
	return n


## The names of the blockers that did NOT fade, so a count of 1 says WHICH one.
##
## Without this, "f0 mid = 1 at every yaw" is only a number. The name says whether
## the angle or the fade rule put it there.
func _probe_opaque_names() -> String:
	var names: Array[String] = []
	for h in _probe_ray_hits():
		var f: Object = _fadable_owning(h["collider"])
		if f == null:
			names.append("%s (not fadable)" % _describe_collider(h["collider"]))
		elif not occlusion.is_faded(f):
			names.append(_describe_fadable(f))
	return ", ".join(names)


## One spot: every collider along the camera->player ray, in order, each labelled
## with whether it faded.
func _probe_occlusion_at(label: String) -> void:
	var from: Vector3 = camera.global_position
	var to: Vector3 = player.global_position + Vector3(0.0, CozyOcclusion.AIM_HEIGHT, 0.0)

	var hits := _probe_ray_hits()

	var faded_n := 0
	var opaque_n := 0
	var parts: Array[String] = []
	for h in hits:
		var f: Object = _fadable_owning(h["collider"])
		var what := _describe_collider(h["collider"])
		if f == null:
			opaque_n += 1
			parts.append("%s -> OPAQUE, not in `fadables`" % what)
		elif occlusion.is_faded(f):
			faded_n += 1
			parts.append("%s -> faded" % what)
		else:
			opaque_n += 1
			parts.append("%s -> OPAQUE, in `fadables` but did not fade" % what)

	print("[cozyv2] probe %s | TOTAL faded=%d of %d | player=(%.1f,%.1f,%.1f) ray=%d faded=%d opaque=%d  [%s]" % [
		label, occlusion.faded_count(), occlusion.fadables.size(),
		player.global_position.x, player.global_position.y, player.global_position.z,
		hits.size(), faded_n, opaque_n,
		"CLEAR" if opaque_n == 0 else "HIDDEN"])
	if not parts.is_empty():
		print("[cozyv2]   on the ray: %s" % ", ".join(parts))


## Name a hit collider by the generated view that owns it. Node names in this
## project are engine-generated (`@Node3D@88`), so `name` identifies nothing —
## the class of the PARENT is what says whether this was a wall, a slab or a roof.
func _describe_collider(c: Object) -> String:
	var p: Node = c.get_parent()
	# Placed objects are not "fadables" — occlusion has no business fading a
	# tree — so they are named here rather than in `_describe_fadable`. Without
	# this a hit object reported as `@Node3D@601`, which is a node's auto-name and
	# says nothing; naming it is what turned "3 legs through something" into a
	# one-word difference between two obstacle helpers.
	if p is CozyWorldObject:
		return "object %s (%s)" % [p.id, p.def_id]
	var d := _describe_fadable(p)
	return d if d != "?" else "unidentified collider at %s" % c.get_path()


func _describe_fadable(f: Object) -> String:
	if not is_instance_valid(f):
		return "FREED (still in the list!)"
	if f is CozyWall:
		return "wall %s" % _state_id(f.state)
	if f is CozyRoof:
		return "roof %s" % _state_id(f.state)
	if f is CozySlab:
		return "slab %s" % _state_id(f.state)
	if f is CozyStair:
		return "stair %s" % _state_id(f.state)
	return "?"


func _state_id(s: Object) -> String:
	return "?" if s == null else str(s.id)


## Which fadable, if any, owns this collider. Walls are several bodies, so a hit
## body has to be traced back to the wall that fades as a whole.
func _fadable_owning(collider: Object) -> Object:
	for w in occlusion.fadables:
		if not is_instance_valid(w):
			continue
		if w.bodies().has(collider):
			return w
	return null


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

	# THE PAYOFF: work must grow the skill OF THE WORK THAT WAS DONE.
	#
	# This used to read the trade's primary skill, and that stopped being the same
	# question on 2026-09-15: a resident now trains what the finished POINT says
	# (`CozyRecipeDefs.skill_for_point`), so a container leg trains `hauling` and a
	# stint at the oven trains `cooking`. Reading `cooking` at frame 900 measured a
	# resident who had so far only hauled — a real behaviour change, reported by a
	# check that had been asking the wrong question.
	#
	# SO IT IS DRIVEN RATHER THAN WAITED FOR. The project has paid twice for an
	# assertion that fired before its subject existed ("A check that fires before
	# its subject exists does not report 'not yet', it reports 'broken'"), and
	# "has the resident baked yet by frame N" is exactly that kind of bet. One
	# synthetic work point through the REAL `_finish_work` is deterministic: it
	# exercises the recipe lookup, the training and the passion multiplier without
	# a frame budget.
	var skill_id := CozyJobDefs.primary_skill(st.job_id)
	var before := st.skill(skill_id)
	var saved_point := npc._target_point
	var saved_obj := npc._target_object
	npc._target_point = CozyInteractionPoint.new(
		CozyJobDefs.point_type(st.job_id), npc.global_position, "", 0.0)
	npc._target_object = null
	npc._finish_work()
	npc._target_point = saved_point
	npc._target_object = saved_obj
	var trained := st.skill(skill_id)
	print("[cozyv2] working trained the skill of the work: %s %d -> %d, passion x%.0f  [%s]" % [
		skill_id, before, trained, st.passion_multiplier(skill_id),
		"OK" if trained > before else "FAIL, skill did not grow"])

	# 愿景 §9 — 0..20, and a value beyond it must be clamped rather than stored.
	# Destructive, so it runs after everything that reads the worked-for value.
	st.train(skill_id, 999)
	var clamped := st.skill(skill_id) == CozySkills.MAX_LEVEL
	st.train(skill_id, -999)
	clamped = clamped and st.skill(skill_id) == CozySkills.MIN_LEVEL
	print("[cozyv2] skill clamp: 0..%d held  [%s]" % [
		CozySkills.MAX_LEVEL, "OK" if clamped else "FAIL"])

	# doc E.21 — the same seed must give the same character, or a resident's
	# traits would rearrange themselves across a save and reload.
	var a := CozyNpcState.create("t", "T", "researcher", 4242)
	var b := CozyNpcState.create("t", "T", "researcher", 4242)
	print("[cozyv2] traits deterministic: %s  [%s]" % [
		str(a.traits), "OK" if a.traits == b.traits and a.traits.size() > 0 else "FAIL"])

	# Round-trip is the save path (V2-26). Everything that matters must survive.
	st.set_passion(skill_id, CozySkills.Passion.INTERESTED)
	var restored := CozyNpcState.from_dict(st.to_dict())
	var same := restored.job_id == st.job_id 		and restored.traits == st.traits 		and restored.skill(skill_id) == st.skill(skill_id) 		and restored.passion(skill_id) == st.passion(skill_id) 		and is_equal_approx(restored.move_speed, st.move_speed)
	print("[cozyv2] npc state round-trip: job=%s traits=%d skill=%d  [%s]" % [
		restored.job_name(), restored.traits.size(), restored.skill(skill_id),
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

	# The schedule resolves to a POINT TYPE, never to an object (doc #115) — and
	# the working block resolves to NOTHING ON PURPOSE. This line used to assert
	# `work->work`, which was the bug: `work` is a point type a research table
	# offers, so mapping the doc's work CATEGORY onto it overrode every trade that
	# is not `work`. A woodcutter sought a desk. The trade decides now, and
	# `_check_resource_chain` is where that is measured on the real world.
	var work_point := CozySchedule.point_for("work")
	var sleep_point := CozySchedule.point_for("sleep")
	print("[cozyv2] schedule resolves to point types: work->%s (the trade decides) sleep->%s  [%s]" % [
		work_point if work_point != "" else "(none)", sleep_point,
		"OK" if work_point == "" and sleep_point == "sleep" else "FAIL"])

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


## The landing the stair tops out on, asserted because it is exactly the space a
## navigation grid with clearance silently deletes.
##
## The strip is `HOUSE_W - WELL_X1` = 1.0 m by construction, and three things come
## out of it: half a wall's thickness, the agent's own width, and the cell the
## grown stairwell obstacle claims. On 2026-09-14 those came to nothing at all —
## and NOTHING SAID SO. `npc plan ground->upstairs` still reported
## `crosses floor=true`, because the upstairs leg fell back to a straight line the
## moment `find_path` came back empty: a green assertion and a navigator that had
## stopped navigating.
##
## So this asks the grid the one question with no fallback under it — can an agent
## stand here at all?
func _check_landing_is_walkable() -> void:
	var nav: CozyLocalNav = _nav_by_room.get("room_1_0", null)
	if nav == null:
		print("[cozyv2] landing beside the stairwell: no grid for room_1_0  [FAIL]")
		return
	var landing := Vector2((WELL_X1 + HOUSE_W) * 0.5, WELL_Z0 + (HOUSE_D - WELL_Z0) * 0.5)
	var ok := nav.is_walkable(nav.world_to_cell(landing))
	print("[cozyv2] landing beside the stairwell: %.2f m of floor, walkable=%s  [%s]" % [
		HOUSE_W - WELL_X1, str(ok),
		"OK" if ok else "FAIL, the stair tops out on floor no agent can stand on"])


## The same question, asked of the NAVIGATOR rather than of the grid.
##
## `_check_outdoor_nav` above proves the outdoor grid routes around the house.
## Until 2026-09-14 that proof was worth nothing: `_local()` returned a straight
## line for EVERY outdoor target and never consulted the grid, so the check was
## green while the behaviour it describes never happened. Every reader of that
## grid was a check.
##
## So this asks what a resident asks — plan me a route from here to there — and
## then looks for geometry along it, the way the pathing probe does. A leg that
## hits something is a leg the body cannot follow.
func _check_outdoor_route_is_walkable() -> void:
	if world_navigator == null:
		print("[cozyv2] outdoor navigator: NOT BUILT  [FAIL]")
		return

	# Each pair has the house between its ends, so a path that ignores the
	# building is a path through it.
	var pairs := [
		["front -> back", Vector3(3.25, 0.0, -3.0), Vector3(-3.0, 0.0, 8.0)],
		["west  -> east", Vector3(-3.0, 0.0, 3.0), Vector3(11.0, 0.0, 3.0)],
		["south -> north", Vector3(4.0, 0.0, -3.5), Vector3(4.0, 0.0, 9.0)],
	]
	var space := get_world_3d().direct_space_state

	# THE CANARY. A cast that provably crosses a solid wall, so that "no leg hit
	# anything" can be told apart from "the casts saw nothing at all". Without it
	# this check reported 0 crossings for a route that plainly walks through the
	# house — the third assertion today that could not fail, and the reason the
	# canary is here rather than in a comment.
	var probe := PhysicsRayQueryParameters3D.create(
		Vector3(1.5, 0.9, -1.5), Vector3(1.5, 0.9, 1.5))
	probe.collide_with_areas = false
	var canary := not space.intersect_ray(probe).is_empty()
	print("[cozyv2] outdoor navigator canary (must hit the south wall): %s  [%s]" % [
		canary, "OK" if canary else "FAIL, casts see no geometry — this check proves nothing"])

	for pair in pairs:
		var from: Vector3 = pair[1]
		var to: Vector3 = pair[2]
		var path := world_navigator.plan(from, to)
		# THE FIRST LEG IS NOT IN THE PATH. `plan()` returns the waypoints the
		# agent has yet to reach and does NOT include where it already is, so a
		# path of one waypoint has ONE leg, not zero. Counting only between
		# consecutive waypoints is how this check first reported "0 leg(s) through
		# geometry" for a route that walks straight through the house — the
		# canary above is what made the difference visible.
		var prev := from
		var crossings := 0
		var first_hit := ""
		for i in path.size():
			var q := PhysicsRayQueryParameters3D.create(
				prev + Vector3(0.0, 0.9, 0.0), path[i] + Vector3(0.0, 0.9, 0.0))
			q.collide_with_areas = false
			if npc != null:
				q.exclude = [npc.get_rid()]
			var hit := space.intersect_ray(q)
			if not hit.is_empty():
				crossings += 1
				if first_hit == "":
					first_hit = "%s at leg %d (%s -> %s)" % [
						_describe_collider(hit["collider"]), i,
						Vector2(prev.x, prev.z), Vector2(path[i].x, path[i].z)]
			prev = path[i]
		if pair[0] == "through the grove":
			print("[cozyv2] grove waypoints: ", path)
		print("[cozyv2] outdoor navigator %s: %d waypoint(s), %d leg(s) through geometry%s  [%s]" % [
			pair[0], path.size(), crossings,
			("" if first_hit == "" else ", first: " + first_hit),
			"OK" if not path.is_empty() and crossings == 0
			else "FAIL, the route walks through something"])


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
