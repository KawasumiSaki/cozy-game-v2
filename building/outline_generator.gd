class_name CozyOutlineGenerator
extends RefCounted
## Turn a drawn outline into a building (V2.1 doc #17 / #86).
##
## The doc's point is that the player expresses INTENT — "I want a building this
## shape" — and the system works out the walls, the doorway and everything
## downstream. Drawing an outline is not placing walls one at a time:
##
##     "玩家表达建筑意图 → BuildingSystem → 结构解析 → 程序化生成 →
##      墙 / 地板 / 屋顶 / 门 / 窗 / 楼梯 → 真实 3D 建筑"
##
## So this emits INTENTS, not geometry. Rooms, portals and the roof all follow
## from the wall graph, which is why none of them appear here — they are already
## derived by systems that exist.

## Width of the doorway cut into the chosen edge, metres.
const DOOR_WIDTH := 1.5

## An edge shorter than this cannot carry a doorway without eating the corner.
const MIN_DOOR_EDGE := 2.5

## Shortest edge that is still a wall. Below this the two endpoints are the same
## point as far as the wall solver is concerned, and it produces a degenerate
## segment the planar subdivision cannot split.
const MIN_EDGE := 0.05


## Build the intents for an outline.
##
## `door_hint` is where the player is standing: the doorway goes on whichever
## edge is nearest, so a building is entered from the side you approached it
## from rather than from an arbitrary one.
## Why an outline cannot be built, or "" when it can (debt 8).
##
## The outline becomes a CLOSED LOOP of walls, so a self-intersecting polygon
## produces walls that cross each other and room detection is handed a non-planar
## graph. That is the same class of failure as the T-junction bug, and it fails
## the same way: quietly, by a room that does not appear.
##
## Concave outlines are deliberately NOT refused. An L-shaped building is
## legitimate, and the walls of a concave polygon are perfectly good walls. What
## a concave polygon breaks is the GABLE roof generator, which falls back to a
## flat roof — that is doc #31's stated simplification and a different thing
## from refusing to build at all. Refusing here would trade a known limitation
## for a missing feature.
static func reject_reason(polygon: PackedVector2Array) -> String:
	var n := polygon.size()
	if n < 3:
		return "needs at least 3 points"
	for i in n:
		if polygon[i].distance_to(polygon[(i + 1) % n]) < MIN_EDGE:
			return "two points are on top of each other (edge %d)" % i
	for i in n:
		var a1 := polygon[i]
		var a2 := polygon[(i + 1) % n]
		for j in range(i + 1, n):
			# Edges sharing a vertex always "meet"; only true crossings count.
			if (j + 1) % n == i or (i + 1) % n == j:
				continue
			if _segments_cross(a1, a2, polygon[j], polygon[(j + 1) % n]):
				return "the outline crosses itself (edges %d and %d)" % [i, j]
	return ""


## Proper (interior) crossing of two segments. Parallel and collinear pairs
## return false — overlapping collinear edges are a degenerate outline, not a
## crossing, and reporting them as one would give the player a wrong reason.
static func _segments_cross(a1: Vector2, a2: Vector2, b1: Vector2, b2: Vector2) -> bool:
	var d1 := a2 - a1
	var d2 := b2 - b1
	var den := d1.x * d2.y - d1.y * d2.x
	if absf(den) < 0.00001:
		return false
	var t := ((b1.x - a1.x) * d2.y - (b1.y - a1.y) * d2.x) / den
	var u := ((b1.x - a1.x) * d1.y - (b1.y - a1.y) * d1.x) / den
	return t > 0.0001 and t < 0.9999 and u > 0.0001 and u < 0.9999


static func plan(polygon: PackedVector2Array, base_y: float, height := 3.0,
		thickness := 0.25, material := "wood", floor_id := 0,
		door_hint := Vector2.ZERO) -> Array:
	var out: Array = []
	var n := polygon.size()
	if n < 3:
		return out

	# Walls run edge by edge. The outline is CLOSED: the last edge returns to
	# the first point, which is what makes the room detection find a room.
	var door_edge := _pick_door_edge(polygon, door_hint)

	for i in n:
		var a2 := polygon[i]
		var b2 := polygon[(i + 1) % n]
		var intent := CozyBuildingIntent.draw_wall(
			Vector3(a2.x, base_y, a2.y), Vector3(b2.x, base_y, b2.y),
			height, thickness, material, floor_id)

		if i == door_edge:
			var edge_len := a2.distance_to(b2)
			# Centred on the edge, so a doorway never lands in a corner.
			intent.with_opening(CozyOpening.door(edge_len * 0.5, DOOR_WIDTH))

		out.append(intent)

	return out


## Which edge should carry the doorway: the one nearest the hint, provided it is
## long enough to hold a door without weakening the corner.
static func _pick_door_edge(polygon: PackedVector2Array, hint: Vector2) -> int:
	var n := polygon.size()
	var best := -1
	var best_d := INF

	for i in n:
		var a := polygon[i]
		var b := polygon[(i + 1) % n]
		var len := a.distance_to(b)
		if len < MIN_DOOR_EDGE:
			continue
		var d := _point_segment_distance(hint, a, b)
		if d < best_d:
			best_d = d
			best = i

	# Every edge too short to hold a door (a tiny shed): fall back to the
	# longest, which is the least bad option and still produces a way in.
	if best < 0:
		var longest := 0.0
		for i in n:
			var len := polygon[i].distance_to(polygon[(i + 1) % n])
			if len > longest:
				longest = len
				best = i
	return best


static func _point_segment_distance(p: Vector2, a: Vector2, b: Vector2) -> float:
	var ab := b - a
	var len_sq := ab.length_squared()
	if len_sq < 0.000001:
		return p.distance_to(a)
	var t := clampf((p - a).dot(ab) / len_sq, 0.0, 1.0)
	return p.distance_to(a + ab * t)


## Total wall length an outline will produce — used for cost preview and by the
## self-check, without building anything.
static func perimeter(polygon: PackedVector2Array) -> float:
	var n := polygon.size()
	if n < 3:
		return 0.0
	var total := 0.0
	for i in n:
		total += polygon[i].distance_to(polygon[(i + 1) % n])
	return total
