extends SceneTree
## MEASUREMENT, not an assertion.
##
##     godot --headless --path <repo> --script res://tests/probe/navmesh_bake_probe.gd
##
## ---------------------------------------------------------------------------
## `world/spatial/local_nav.gd` says, in its own header, why this project
## rasterises a grid instead of baking a navigation mesh:
##
##     "doc #86 makes dynamic updates a hard requirement — placing a table must
##      change NPC routing. Marking cells is synchronous and cheap; rebaking a
##      navmesh at runtime is neither."
##
## That sentence is the entire case against `NavigationServer3D`, and it is an
## ARGUMENT, not a number. Meanwhile the grid it defends has been measured to
## route agents through gaps narrower than the agent (`tests/unit/test_local_nav.gd`)
## and to extend half a wall-thickness past every wall, because the room polygons
## it rasterises are bounded by wall CENTRELINES (an 8 x 6 room measures 48.0 m2).
##
## So before choosing, measure the thing the sentence claims. Three numbers:
##
##   1. how long does ONE bake of this house take, from real geometry?
##   2. how long does RE-baking take when one table moves?
##   3. what does the grid actually cost, for comparison — the honest baseline,
##      because "cheap" is only meaningful next to "expensive".
##
## If (2) is a few milliseconds, the argument above is simply out of date and the
## mesh is affordable. If it is hundreds, the mesh still wins for the STATIC parts
## and the dynamic parts need `NavigationObstacle3D` avoidance instead of a rebake.
## Either way the decision stops being a matter of taste.

const FLOOR_H := 3.0
const WALL_T := 0.25
const HOUSE_W := 8.0
const HOUSE_D := 6.0
const WELL_X0 := 4.5
const WELL_X1 := 7.0
const WELL_Z0 := 3.0

## The agent that has to fit through whatever comes out.
const AGENT_RADIUS := 0.3

## A 60 Hz frame. A rebake that fits inside one of these can happen on the frame
## a table is placed; anything larger has to be threaded or avoided.
const FRAME_MS := 16.67


func _initialize() -> void:
	print("[probe] navmesh bake cost vs grid rebuild cost, on the project's own house")
	print("[probe] agent radius %.2f m, one frame = %.2f ms" % [AGENT_RADIUS, FRAME_MS])

	var house := _build_house_geometry()
	# The bake parses a node tree, so the tree has to BE in the SceneTree —
	# `parse_source_geometry_data` refuses a detached root, and refusing is the
	# good outcome: the alternative would be a bake that silently finds nothing
	# and reports a very fast zero.
	get_root().add_child(house)
	print("[probe] source geometry: %d node(s) under one root" % house.get_child_count())
	await process_frame

	await _time_bake("1. first bake, whole house", house, 1)
	await _time_bake("2. re-bake after a table moves", house, 20)

	await _report_clearance(house)

	_time_grid()

	house.queue_free()
	quit(0)


# ---------------------------------------------------------------- the bake

func _new_navmesh() -> NavigationMesh:
	var navmesh := NavigationMesh.new()
	navmesh.agent_radius = AGENT_RADIUS
	navmesh.agent_height = 1.2
	navmesh.cell_size = 0.25
	navmesh.cell_height = 0.25
	# Stated rather than defaulted: a bake that parses the wrong thing finds
	# nothing, and finding nothing looks exactly like a very fast bake.
	navmesh.geometry_parsed_geometry_type = NavigationMesh.PARSED_GEOMETRY_MESH_INSTANCES
	navmesh.geometry_source_geometry_mode = NavigationMesh.SOURCE_GEOMETRY_ROOT_NODE_CHILDREN
	navmesh.geometry_collision_mask = 0xFFFFFFFF
	return navmesh


func _time_bake(label: String, root: Node3D, runs: int) -> void:
	var navmesh := _new_navmesh()

	# One warm-up, so the first-call cost of the server's own setup is not
	# charged to the measurement.
	var src := _parse(navmesh, root)
	var parsed := src.get_vertices().size()
	await _bake(navmesh, src)

	var t0 := Time.get_ticks_usec()
	var verts := 0
	for i in runs:
		src = _parse(navmesh, root)
		NavigationServer3D.bake_from_source_geometry_data(navmesh, src)
		verts = navmesh.get_vertices().size()
	var total_ms := float(Time.get_ticks_usec() - t0) / 1000.0
	var per_ms := total_ms / float(runs)

	print("[probe] %-34s %7.2f ms each  (%d run(s))  src verts=%d  baked verts=%d  [%s]" % [
		label, per_ms, runs, parsed, verts,
		"within a frame" if per_ms < FRAME_MS else "OVER a frame"])


func _parse(navmesh: NavigationMesh, root: Node3D) -> NavigationMeshSourceGeometryData3D:
	var src := NavigationMeshSourceGeometryData3D.new()
	NavigationServer3D.parse_source_geometry_data(navmesh, src, root)
	return src


## Bake, then give the server a frame. Navigation baking in 4.7 can be handed to
## a worker, so a vertex count read on the same line as the call reports zero for
## a bake that worked — which is what the first version of this probe did.
func _bake(navmesh: NavigationMesh, src: NavigationMeshSourceGeometryData3D) -> void:
	NavigationServer3D.bake_from_source_geometry_data(navmesh, src)
	await process_frame
	await process_frame


## Where the mesh and the grid would disagree: the landing beside the stairwell,
## which the grid calls walkable, and the phantom column the grid has at the wall
## centreline, which the collider occupies.
func _report_clearance(root: Node3D) -> void:
	var navmesh := _new_navmesh()
	await _bake(navmesh, _parse(navmesh, root))
	print("[probe] baked %d vert(s), %d polygon(s)" % [
		navmesh.get_vertices().size(), navmesh.get_polygon_count()])

	var map := NavigationServer3D.map_create()
	NavigationServer3D.map_set_active(map, true)
	var region := NavigationServer3D.region_create()
	NavigationServer3D.region_set_map(region, map)
	NavigationServer3D.region_set_navigation_mesh(region, navmesh)
	NavigationServer3D.map_force_update(map)

	var probes := [
		["landing beside the stairwell", Vector3(7.30, FLOOR_H + 0.1, 4.50)],
		["wall-centreline phantom column", Vector3(7.95, FLOOR_H + 0.1, 3.20)],
		["open upper floor", Vector3(2.00, FLOOR_H + 0.1, 2.00)],
		["inside the stairwell hole", Vector3(5.50, FLOOR_H + 0.1, 4.50)],
	]
	for p in probes:
		var point: Vector3 = p[1]
		var closest := NavigationServer3D.map_get_closest_point(map, point)
		var off := closest.distance_to(point)
		print("[probe]   closest to %-32s -> (%.2f, %.2f, %.2f)  %s" % [
			p[0], closest.x, closest.y, closest.z,
			"ON the mesh" if off < 0.35 else "off it by %.2f m" % off])

	NavigationServer3D.free_rid(region)
	NavigationServer3D.free_rid(map)


# ---------------------------------------------------------------- the baseline

## What the grid costs for the same job, so "cheap" has something to be cheap
## relative to. `CozyLocalNav.build()` is the function that runs today.
func _time_grid() -> void:
	var poly := PackedVector2Array([
		Vector2(0, 0), Vector2(HOUSE_W, 0), Vector2(HOUSE_W, HOUSE_D), Vector2(0, HOUSE_D)])
	var room := CozyRoom.new("probe", 1, poly)
	var obstacles: Array = [
		Rect2(WELL_X0, WELL_Z0, WELL_X1 - WELL_X0, HOUSE_D - WELL_Z0),
		Rect2(2.0, 2.0, 1.0, 1.0),   # a table, the thing that forces a rebuild
	]

	var runs := 200
	var t0 := Time.get_ticks_usec()
	for i in runs:
		var nav := CozyLocalNav.new()
		# `clearance` has NO default on purpose (see local_nav.gd): an existing call
		# site must not be able to keep the old behaviour by saying nothing. This
		# probe said nothing and stopped parsing on 2026-09-14 — a probe that cannot
		# load reports exactly what a probe that does not exist reports: nothing.
		nav.build(room, AGENT_RADIUS, obstacles)
	var per_ms := float(Time.get_ticks_usec() - t0) / 1000.0 / float(runs)
	print("[probe] %-34s %7.3f ms each  (%d run(s))" % [
		"3. grid rebuild (today's cost)", per_ms, runs])


# ---------------------------------------------------------------- geometry
#
# A stand-in for the real house, built from the same constants `main.gd` uses:
# eight walls, three slabs leaving a stairwell hole, and a stair. Meshes AND
# colliders, because which one the bake parses is a setting and both have to be
# there for either answer to be measurable.

func _build_house_geometry() -> Node3D:
	var holder := Node3D.new()
	holder.name = "HouseProbe"

	# A ground slab, so floor 0 has something to walk on — the real house stands
	# on terrain, and a bake with no floor under it produces nothing to measure.
	_box(holder, Vector3(HOUSE_W, 0.2, HOUSE_D), Vector3(HOUSE_W * 0.5, -0.1, HOUSE_D * 0.5))

	for f in 2:
		var y := float(f) * FLOOR_H
		_wall(holder, Vector3(0, y, 0), Vector3(HOUSE_W, y, 0))
		_wall(holder, Vector3(HOUSE_W, y, 0), Vector3(HOUSE_W, y, HOUSE_D))
		_wall(holder, Vector3(HOUSE_W, y, HOUSE_D), Vector3(0, y, HOUSE_D))
		_wall(holder, Vector3(0, y, HOUSE_D), Vector3(0, y, 0))

	# The upper slab in three pieces, leaving the stairwell hole open.
	var well_d := HOUSE_D - WELL_Z0
	_box(holder, Vector3(WELL_X0, 0.2, HOUSE_D),
		Vector3(WELL_X0 * 0.5, FLOOR_H - 0.1, HOUSE_D * 0.5))
	_box(holder, Vector3(HOUSE_W - WELL_X0, 0.2, WELL_Z0),
		Vector3((WELL_X0 + HOUSE_W) * 0.5, FLOOR_H - 0.1, WELL_Z0 * 0.5))
	_box(holder, Vector3(HOUSE_W - WELL_X1, 0.2, well_d),
		Vector3((WELL_X1 + HOUSE_W) * 0.5, FLOOR_H - 0.1, WELL_Z0 + well_d * 0.5))

	# The ramp, as the tilted box the project builds.
	var stair := _box(holder, Vector3(WELL_X1 - WELL_X0, 0.3, well_d),
		Vector3((WELL_X0 + WELL_X1) * 0.5, FLOOR_H * 0.5, WELL_Z0 + well_d * 0.5))
	stair.rotation = Vector3(0, 0, atan2(FLOOR_H, WELL_X1 - WELL_X0))

	# The furniture that has to be able to move.
	_box(holder, Vector3(1.4, 0.8, 0.9), Vector3(2.0, FLOOR_H + 0.4, 2.0))
	_box(holder, Vector3(1.0, 0.6, 2.0), Vector3(1.5, 0.3, 1.5))
	_box(holder, Vector3(0.8, 0.8, 0.6), Vector3(6.6, 0.4, 1.0))

	return holder


func _wall(holder: Node3D, a: Vector3, b: Vector3) -> void:
	var d := b - a
	var length := Vector2(d.x, d.z).length()
	var centre := (a + b) * 0.5 + Vector3(0, FLOOR_H * 0.5, 0)
	var box := _box(holder, Vector3(length, FLOOR_H, WALL_T), centre)
	box.rotation = Vector3(0, atan2(-d.z, d.x), 0)


func _box(holder: Node3D, size: Vector3, centre: Vector3) -> Node3D:
	var body := StaticBody3D.new()
	body.position = centre

	var mesh := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mesh.mesh = bm
	body.add_child(mesh)

	var shape := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = size
	shape.shape = bs
	body.add_child(shape)

	holder.add_child(body)
	return body
