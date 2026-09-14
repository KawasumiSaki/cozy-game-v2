extends "res://tests/unit/unit_test.gd"
## What the navigation grid calls walkable, measured without a world.
##
## `CozyLocalNav` rasterises obstacles into a grid and runs A* over it. What it
## rasterises is the thing these cases are about, because until 2026-09-14 it
## rasterised obstacles EXACTLY — no inflation by the agent's radius, no erosion
## of the room boundary — and so answered "can a POINT get from here to there"
## while the thing that has to get there is a capsule
## `CozyCharacter.CAPSULE_RADIUS` in radius.
##
## Two defects came out of that, and both are pinned below:
##
##   * a gap wider than a cell and narrower than the agent was a route to the
##     planner and a wall to the body. The agent walks at it, is stopped, waits,
##     abandons the job, replans, and is handed the same route again — which is
##     what a resident pinned at `wp=2/29 stuck=1.5` for hundreds of frames looks
##     like from outside.
##   * a room's polygon runs through wall CENTRELINES (an 8 x 6 room measures
##     48.0 m2, which is centreline to centreline), so the grid extended half a
##     wall-thickness into every wall — a phantom column the collider fills.
##
## THE CLEARANCE IS READ FROM `CozyCharacter`, not written down here, so the
## contradiction cannot be repaired by editing the test.
##
## Pure logic: a room polygon, obstacle rects, an A*. No world, no nodes, no
## physics — which is the point, because the body is what disagrees and the body
## is exactly what is not in this file.


func _init() -> void:
	suite("local nav")
	case("a gap the agent does not fit through is not a route", _narrow_gap_is_not_a_route)
	case("a gap the agent does fit through is a route", _wide_gap_is_a_route)
	case("the clearance is the body's own radius", _clearance_is_the_body)
	case("a sealed room has no route at all", _sealed_room_has_no_route)
	case("the room's own shape is a boundary", _room_shape_is_a_boundary)
	case("the wall is not walkable space", _the_wall_is_not_walkable)
	case("the snap has a budget, not a search", _the_snap_has_a_budget)


## The defect this whole suite was written for, now asserted the other way round.
##
## Two obstacle rects leave a 0.5 m doorway. A 0.6 m agent does not fit, so there
## must be NO route. Before the fix this returned a route, and the case that said
## so was the tooth: it was the only thing that would go red on the day the grid
## grew clearance. It did go red, and this is what replaced it.
func _narrow_gap_is_not_a_route() -> void:
	var gap := 0.5
	var nav := _nav_with_a_doorway(gap)
	var path := nav.find_path(Vector2(1.0, 2.0), Vector2(5.0, 2.0))

	near("the body is 0.6 m across", CozyCharacter.CAPSULE_RADIUS * 2.0, 0.6)
	is_true("and the doorway is narrower than that",
		CozyCharacter.CAPSULE_RADIUS * 2.0 > gap)
	is_true("so the grid must not offer a route through it", path.is_empty())


## The boundary the other way. A gap the agent fits through must still be a route
## — otherwise "add clearance" gets implemented as "refuse everything", and the
## case above would go green for a reason worse than the bug.
func _wide_gap_is_a_route() -> void:
	var gap := 2.0
	var nav := _nav_with_a_doorway(gap)
	var path := nav.find_path(Vector2(1.0, 2.0), Vector2(5.0, 2.0))

	is_true("a 2 m doorway is a route", not path.is_empty())
	is_true("and the agent fits through this one with room to spare",
		CozyCharacter.CAPSULE_RADIUS * 2.0 < gap)


## The clearance is the BODY's, and the grid is COARSE.
##
## Both halves matter. A cell is 0.25 m and rasterising blocks every cell a grown
## obstacle touches at all, so the grid's real threshold is the agent's width plus
## about a cell on each side. Stating only the first half would give a case that
## fails for a reason nobody wrote down the day the cell size changes; stating
## both is what makes this a measurement of the clearance rather than of the
## rounding.
func _clearance_is_the_body() -> void:
	var wide := CozyCharacter.CAPSULE_RADIUS * 2.0 + CozyLocalNav.CELL * 2.0
	var narrow := CozyCharacter.CAPSULE_RADIUS * 2.0 - 0.1

	is_true("a doorway narrower than the agent is not a route",
		_nav_with_a_doorway(narrow).find_path(
			Vector2(1.0, 2.0), Vector2(5.0, 2.0)).is_empty())
	is_true("and the agent's width plus a cell of slack each side is",
		not _nav_with_a_doorway(wide).find_path(
			Vector2(1.0, 2.0), Vector2(5.0, 2.0)).is_empty())


## The tooth for the two cases above. Without it, "no route" would pass just as
## well on an A* that returns nothing for everything. A sealed room must come
## back empty AND the same room with a doorway must not.
func _sealed_room_has_no_route() -> void:
	var room := CozyRoom.new("test", 0, _rect(0.0, 0.0, 6.0, 4.0))
	var nav := CozyLocalNav.new()
	nav.build(room, CozyCharacter.CAPSULE_RADIUS, [Rect2(3.0, 0.0, 0.2, 4.0)])

	is_true("a wall across the whole room is not a route",
		nav.find_path(Vector2(1.0, 2.0), Vector2(5.0, 2.0)).is_empty())
	is_true("while the same room with a doorway does route",
		not _nav_with_a_doorway(2.0).find_path(
			Vector2(1.0, 2.0), Vector2(5.0, 2.0)).is_empty())


## The grid is bounded by the room's POLYGON, not by its bounding box, and the
## difference is the whole reason an L-shaped building works.
##
## THIS CASE EXISTS BECAUSE A MUTATION FOUND IT MISSING. Deleting the bounds check
## in `build()` — the one that blocks every cell whose centre is outside the room
## — changed nothing in this suite, because every other room here is a rectangle
## and no other path goes near an edge. A branch nothing walks is a branch nobody
## is watching, and it took deliberately breaking the file to see it.
func _room_shape_is_a_boundary() -> void:
	var nav := CozyLocalNav.new()
	nav.build(CozyRoom.new("ell", 0, PackedVector2Array([
		Vector2(0, 0), Vector2(6, 0), Vector2(6, 3),
		Vector2(3, 3), Vector2(3, 6), Vector2(0, 6)])),
		CozyCharacter.CAPSULE_RADIUS, [])

	is_false("the notch outside the L is not walkable",
		nav.is_walkable(nav.world_to_cell(Vector2(4.5, 4.5))))
	is_true("and the inside of the L is",
		nav.is_walkable(nav.world_to_cell(Vector2(1.5, 1.5))))

	# Both ends are inside the L, so the route has to go round the corner rather
	# than cut across the notch.
	var path := nav.find_path(Vector2(1.5, 1.5), Vector2(1.5, 4.5))
	is_true("a route exists inside the L", not path.is_empty())
	var in_notch := 0
	for p in path:
		if p.x > 3.0 and p.y > 3.0:
			in_notch += 1
	eq("and no waypoint of it is in the notch", in_notch, 0)


## The second defect: a room polygon runs through the WALL CENTRELINES, so the
## grid's edge is the middle of the wall and not its face.
##
## Eroding by the agent's radius alone would not be enough — the agent's centre
## also has to clear the half wall-thickness between the centreline and the face.
## `wall_reach` is that half, and it is a separate number from `clearance`
## because furniture has no wall in it.
func _the_wall_is_not_walkable() -> void:
	const WALL_T := 0.25
	var room := CozyRoom.new("test", 0, _rect(0.0, 0.0, 6.0, 4.0))

	# x = 0 is the wall's CENTRELINE, which is what the polygon boundary is. The
	# agent's centre has to clear the wall's face (half a wall, 0.125) by its own
	# radius (0.3), so the first legal distance is 0.425 — and the cell centre at
	# 0.375 is inside that band.
	var band := Vector2(WALL_T * 0.5 + CozyCharacter.CAPSULE_RADIUS - 0.05, 2.0)
	var clear := Vector2(WALL_T * 0.5 + CozyCharacter.CAPSULE_RADIUS
		+ CozyLocalNav.CELL, 2.0)

	var nav := CozyLocalNav.new()
	nav.build(room, CozyCharacter.CAPSULE_RADIUS, [], CozyLocalNav.CELL, WALL_T * 0.5)
	is_false("a cell inside the face-plus-body band is not walkable",
		nav.is_walkable(nav.world_to_cell(band)))
	# Without this half the pair below would pass on a grid that simply refuses
	# everything near an edge, which is a different and worse bug.
	is_true("and clear of that band it is walkable",
		nav.is_walkable(nav.world_to_cell(clear)))

	# Without `wall_reach` the grid stops at the clearance instead of at the
	# wall's face, and the same cell becomes walkable space the collider fills —
	# the phantom column. Both grids are asked about the SAME cell, so the only
	# difference between the two answers is the number under test.
	var naive := CozyLocalNav.new()
	naive.build(room, CozyCharacter.CAPSULE_RADIUS, [], CozyLocalNav.CELL, 0.0)
	is_true("without the wall's half, that very cell IS walkable — the defect",
		naive.is_walkable(naive.world_to_cell(band)))


## How far `_nearest_walkable` may reach, which had NO assertion on it until a
## mutation said so: putting the spiral back to its old 12 cells changed nothing
## in this suite.
##
## Snapping exists for the half-step an agent is inside its own clearance. Past
## that it is not recovery, it is a different destination — and a resident handed
## a route that begins three metres from where it is standing has been told a
## story about where it is.
func _the_snap_has_a_budget() -> void:
	# A 6 x 4 room whose western half is walled off, band and wall together, so the
	# ONLY floor is a single run of columns on the east. Grown by the agent's
	# clearance the band covers x in [0, 3.25), and the sliver west of it is gone
	# rather than merely sealed — a sealed sliver is still somewhere the spiral can
	# reach, and reaching it would make this case pass for the wrong reason.
	var room := CozyRoom.new("test", 0, _rect(0.0, 0.0, 6.0, 4.0))
	var nav := CozyLocalNav.new()
	nav.build(room, CozyCharacter.CAPSULE_RADIUS, [Rect2(0.0, 0.0, 2.7, 4.0)])

	var near := nav.find_path(Vector2(3.0, 2.0), Vector2(5.0, 2.0))
	is_true("an agent one cell inside the grown wall is snapped out",
		not near.is_empty())
	if not near.is_empty():
		is_true("and lands on real floor, not on itself", near[0].x > 2.7)

	# Five cells inside it, the only floor is on the far side of the budget. The
	# grid must refuse rather than reach that far for one — which is exactly what
	# the old 12-cell spiral did, and why nothing caught it: no case had a start
	# far enough from anything walkable for the difference to show.
	is_true("but one further in than the budget reaches is refused, not teleported",
		nav.find_path(Vector2(1.6, 2.0), Vector2(5.0, 2.0)).is_empty())


# ---------------------------------------------------------------- helpers

## A 6 x 4 room with a 0.2 m thick wall across it at x = 3, broken by a doorway
## `gap` metres wide, centred at z = 2.
func _nav_with_a_doorway(gap: float) -> CozyLocalNav:
	var room := CozyRoom.new("test", 0, _rect(0.0, 0.0, 6.0, 4.0))
	var z0 := 2.0 - gap * 0.5
	var z1 := 2.0 + gap * 0.5
	var nav := CozyLocalNav.new()
	nav.build(room, CozyCharacter.CAPSULE_RADIUS, [
		Rect2(3.0, 0.0, 0.2, z0),          # north of the doorway
		Rect2(3.0, z1, 0.2, 4.0 - z1),     # south of it
	])
	return nav


func _rect(x: float, z: float, w: float, d: float) -> PackedVector2Array:
	return PackedVector2Array([
		Vector2(x, z), Vector2(x + w, z), Vector2(x + w, z + d), Vector2(x, z + d)])
