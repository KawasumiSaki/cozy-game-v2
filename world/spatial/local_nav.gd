class_name CozyLocalNav
extends RefCounted
## Local navigation inside a single room (V2 doc #9, #41, #86).
##
## The doc splits navigation into two halves and is explicit about why (#41):
##
##     Room Graph  ->  macro route   ("which rooms must I cross?")
##     Navigation  ->  local route   ("how do I actually walk across this room?")
##
## This is the lower half. Given a room polygon it rasterises a walkable grid,
## blocks whatever the walls and furniture occupy, and runs A* across it.
##
## Why a grid and not a baked navmesh: doc #86 makes dynamic updates a hard
## requirement — placing a table must change NPC routing. Marking cells is
## synchronous and cheap; rebaking a navmesh at runtime is neither.

const CELL := 0.25   ## Default metres per cell.

## Actual cell size for this grid. A room is metre-scale so the default is
## right; the OUTDOOR grid covers the whole terrain and is built much coarser,
## because 0.25 m over 64 x 64 m is 65,536 cells — a startup cost paid for
## precision nobody can see at that scale.
var cell := CELL

## How far the agent's CENTRE must stay from anything solid, in metres.
##
## Obstacles are grown by this before they are rasterised. Without it the grid
## answers "can a POINT get from here to there" and happily routes an agent at a
## gap narrower than the agent — see `tests/unit/test_local_nav.gd`, which was
## written to pin exactly that and went red when this parameter arrived.
var clearance := 0.0

## Extra erosion applied to the ROOM POLYGON only, on top of `clearance`.
##
## A room's polygon runs through wall CENTRELINES — an 8 x 6 room measures 48.0
## m2, i.e. centreline to centreline — so the grid's edge is the middle of a wall
## rather than its face. Without this half a wall-thickness of every wall is
## walkable space, and the collider disagrees. It is separate from `clearance`
## because a table has no wall in it.
var wall_reach := 0.0

## 4 orthogonal + 4 diagonal neighbours.
const DIRS: Array[Vector2i] = [
	Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1),
	Vector2i(1, 1), Vector2i(1, -1), Vector2i(-1, 1), Vector2i(-1, -1),
]
const SQRT2 := 1.41421356

var room: CozyRoom = null

var _min := Vector2.ZERO          ## Grid origin in world (x, z).
var _size := Vector2i.ZERO
var _blocked := PackedByteArray()
var _obstacles: Array[Rect2] = []


# ---------------------------------------------------------------- build

## `p_clearance` has NO default, deliberately. A default would leave every
## existing call site rasterising obstacles with no room for the body, which is
## the bug — and it would do it silently, at the one moment nobody looks: the
## call that was already written.
func build(p_room: CozyRoom, p_clearance: float, obstacles: Array = [],
		p_cell := CELL, p_wall_reach := 0.0) -> void:
	room = p_room
	clearance = maxf(p_clearance, 0.0)
	wall_reach = maxf(p_wall_reach, 0.0)
	cell = maxf(p_cell, 0.01)
	_obstacles.clear()

	var bb := _bounds(p_room.polygon)
	_min = bb.position
	_size = Vector2i(int(ceil(bb.size.x / cell)) + 1, int(ceil(bb.size.y / cell)) + 1)

	_blocked = PackedByteArray()
	_blocked.resize(_size.x * _size.y)
	_blocked.fill(0)

	# Anything outside the room polygon is not walkable — and neither is anything
	# within reach of its EDGE.
	#
	# The edge is the interesting half. A room's polygon runs through wall
	# CENTRELINES (an 8 x 6 room measures 48.0 m2), so the polygon boundary is the
	# middle of a wall, and a cell tested only against "inside or outside" leaves
	# half a wall-thickness of wall as walkable space. `wall_reach` is that half;
	# `clearance` is the body that has to fit between the face and the agent's
	# centre.
	var reach := clearance + wall_reach
	for y in _size.y:
		for x in _size.x:
			var c := Vector2i(x, y)
			var p := cell_to_world(c)
			if not p_room.contains_point(p):
				_set_blocked(c, true)
			elif reach > 0.0 and _distance_to_edge(p_room.polygon, p) < reach:
				_set_blocked(c, true)

	for ob in obstacles:
		add_obstacle(ob)


## Doc #86: when furniture is placed or moved, navigation must follow.
## Registering an obstacle only touches the cells it covers — no full rebuild.
func add_obstacle(rect: Rect2) -> void:
	_obstacles.append(rect)

	# GROWN by the agent's clearance, so that what walks this grid is a point.
	#
	# This is the Minkowski sum, and it is the textbook answer to exactly this
	# bug (Lozano-Perez & Wesley, CACM 22(10), 1979): if the obstacles are
	# enlarged by the agent's radius, planning for a point is planning for the
	# agent. Rasterising the rect exactly — which is what this did until
	# 2026-09-14 — makes the grid answer a question about a point while a capsule
	# 0.6 m across is what has to walk the answer.
	#
	# `grow` rather than a per-side constant, so the clearance is one number that
	# cannot drift between the four sides.
	var grown := rect.grow(clearance) if clearance > 0.0 else rect
	var c0 := world_to_cell(grown.position)
	var c1 := world_to_cell(grown.position + grown.size)
	for y in range(maxi(c0.y, 0), mini(c1.y, _size.y - 1) + 1):
		for x in range(maxi(c0.x, 0), mini(c1.x, _size.x - 1) + 1):
			_set_blocked(Vector2i(x, y), true)


func obstacle_count() -> int:
	return _obstacles.size()


func blocked_cell_count() -> int:
	var n := 0
	for v in _blocked:
		if v != 0:
			n += 1
	return n


# ---------------------------------------------------------------- grid access

func world_to_cell(p: Vector2) -> Vector2i:
	return Vector2i(int(floor((p.x - _min.x) / cell)), int(floor((p.y - _min.y) / cell)))


func cell_to_world(c: Vector2i) -> Vector2:
	return Vector2(_min.x + (float(c.x) + 0.5) * cell, _min.y + (float(c.y) + 0.5) * cell)


func _in_bounds(c: Vector2i) -> bool:
	return c.x >= 0 and c.y >= 0 and c.x < _size.x and c.y < _size.y


func _is_blocked(c: Vector2i) -> bool:
	return _blocked[c.y * _size.x + c.x] != 0


func _set_blocked(c: Vector2i, v: bool) -> void:
	if _in_bounds(c):
		_blocked[c.y * _size.x + c.x] = 1 if v else 0


func is_walkable(c: Vector2i) -> bool:
	return _in_bounds(c) and not _is_blocked(c)


## How far `_nearest_walkable` may look for something walkable, in cells.
##
## It used to be 12 — three metres at 0.25 m cells — and that was harmless while
## obstacles were rasterised exactly, because an agent was rarely far from a free
## cell. Once obstacles grow by the agent's clearance it stops being harmless: a
## resident standing somewhere that has just been closed off is not "half inside
## a wall" any more, it is a couple of centimetres inside a grown obstacle, and a
## spiral that reaches three metres turns that into a route to a DIFFERENT place.
##
## Snapping is for the half-step an agent is inside its own clearance, so the
## budget is that step and not a search.
const NEAREST_WALKABLE_CELLS := 4


## Spiral outwards for the closest walkable cell — an entity standing half
## inside a wall should still be able to path.
func _nearest_walkable(c: Vector2i) -> Vector2i:
	if is_walkable(c):
		return c
	for r in range(1, NEAREST_WALKABLE_CELLS + 1):
		for dy in range(-r, r + 1):
			for dx in range(-r, r + 1):
				if absi(dx) != r and absi(dy) != r:
					continue
				var t := Vector2i(c.x + dx, c.y + dy)
				if is_walkable(t):
					return t
	return Vector2i(-1, -1)


# ---------------------------------------------------------------- pathfinding

## A* across the walkable grid. Returns world-space (x, z) points, or an empty
## array when no route exists — which is a legitimate answer, not an error.
func find_path(from_world: Vector2, to_world: Vector2) -> PackedVector2Array:
	var empty := PackedVector2Array()
	var start := _nearest_walkable(world_to_cell(from_world))
	var goal := _nearest_walkable(world_to_cell(to_world))
	if start.x < 0 or goal.x < 0:
		return empty
	if start == goal:
		empty.append(cell_to_world(start))
		return empty

	var open: Array[Vector2i] = [start]
	var came: Dictionary = {}
	var g: Dictionary = {start: 0.0}
	var f: Dictionary = {start: _heuristic(start, goal)}
	var closed: Dictionary = {}

	while not open.is_empty():
		# Pop the lowest f. Linear scan is fine at this grid size; swap in a
		# binary heap if rooms ever get large.
		var best := 0
		for i in open.size():
			if f.get(open[i], INF) < f.get(open[best], INF):
				best = i
		var cur: Vector2i = open[best]
		open.remove_at(best)

		if cur == goal:
			return _reconstruct(came, cur)

		closed[cur] = true
		for d in DIRS:
			var nb := cur + d
			if not is_walkable(nb) or closed.has(nb):
				continue
			# No corner cutting: a diagonal move needs both orthogonal
			# neighbours open, or agents clip through wall corners.
			if d.x != 0 and d.y != 0:
				if not is_walkable(cur + Vector2i(d.x, 0)) \
						or not is_walkable(cur + Vector2i(0, d.y)):
					continue
			var step := SQRT2 if (d.x != 0 and d.y != 0) else 1.0
			var tentative: float = g[cur] + step
			if tentative < g.get(nb, INF):
				came[nb] = cur
				g[nb] = tentative
				f[nb] = tentative + _heuristic(nb, goal)
				if not open.has(nb):
					open.append(nb)
	return empty


func _reconstruct(came: Dictionary, goal: Vector2i) -> PackedVector2Array:
	var cells: Array[Vector2i] = [goal]
	var cur := goal
	while came.has(cur):
		cur = came[cur]
		cells.append(cur)
	cells.reverse()
	var out := PackedVector2Array()
	for c in cells:
		out.append(cell_to_world(c))
	return out


## Octile distance — admissible for 8-connected grids. In cell units, so
## the cell size cancels out and a coarse grid still measures correctly.
func _heuristic(a: Vector2i, b: Vector2i) -> float:
	var dx := absi(a.x - b.x)
	var dy := absi(a.y - b.y)
	return (float(maxi(dx, dy)) + (SQRT2 - 1.0) * float(mini(dx, dy))) * cell


## Total walked distance of a path, for comparing routes.
static func path_length(path: PackedVector2Array) -> float:
	var total := 0.0
	for i in range(1, path.size()):
		total += path[i - 1].distance_to(path[i])
	return total


## Perpendicular distance from `p` to the nearest edge of `poly`, in metres.
##
## This is what keeps the agent's centre clear of the wall the polygon runs
## through. It measures to the EDGES and not to the vertices, so a long straight
## wall is one distance and not a scalloped one.
static func _distance_to_edge(poly: PackedVector2Array, p: Vector2) -> float:
	var n := poly.size()
	if n < 2:
		return INF
	var best := INF
	for i in n:
		best = minf(best, _point_segment_distance(p, poly[i], poly[(i + 1) % n]))
	return best


static func _point_segment_distance(p: Vector2, a: Vector2, b: Vector2) -> float:
	var ab := b - a
	var len_sq := ab.length_squared()
	if len_sq < 0.000001:
		return p.distance_to(a)
	var t := clampf((p - a).dot(ab) / len_sq, 0.0, 1.0)
	return p.distance_to(a + ab * t)


static func _bounds(poly: PackedVector2Array) -> Rect2:
	if poly.is_empty():
		return Rect2()
	var lo := poly[0]
	var hi := poly[0]
	for p in poly:
		lo = Vector2(minf(lo.x, p.x), minf(lo.y, p.y))
		hi = Vector2(maxf(hi.x, p.x), maxf(hi.y, p.y))
	return Rect2(lo, hi - lo)
