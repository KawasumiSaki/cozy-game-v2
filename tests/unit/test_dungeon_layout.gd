extends "res://tests/unit/unit_test.gd"
## A dungeon's outlines, resolved into a wall graph that derives the RIGHT rooms.
##
## `tests/probe/dungeon_layout_probe.gd` measured that the naive reading of the
## blueprint's `outlines` merges rooms silently. These cases turn that
## measurement into assertions.
##
## The FIRST case is the tooth, and it is deliberately an assertion that the
## naive path FAILS: the same two outlines, through the raw outline generator,
## must come back as ONE room. Without that pair, "the layout gives 2 rooms"
## would pass just as well if nothing had been wrong in the first place.
##
## Pure logic throughout — outlines, intents, the detector. No world is booted.


func _init() -> void:
	suite("dungeon layout")
	case("the naive path merges two adjacent rooms", _naive_merges)
	case("a shared edge is one wall, and the rooms stay two", _keeps_them_apart)
	case("that shared wall carries exactly one door", _shared_door)
	case("a corridor joins both rooms", _corridor_joins_rooms)
	case("a corridor's end walls are doorways, not walls", _corridor_ends_dropped)
	case("a corner touch is not a doorway", _corner_touch)
	case("one outline is left alone", _single_outline)
	case("a concave outline is one room", _concave)
	case("the entrance defaults to the biggest space", _centre)


# ---------------------------------------------------------------- the tooth

## The failure `CozyDungeonLayout` exists to prevent, asserted directly.
##
## Two 8x6 rooms side by side, each outline closed by `plan()` exactly as a first
## implementation would close it. The shared edge is emitted twice, and the face
## traversal merges the two rooms into one 96 m2 space — with no error, and
## nothing in the pipeline that notices.
func _naive_merges() -> void:
	var naive := _segments_naive([_room_a(), _room_b()])
	eq("the raw outline path gives 8 segments", naive.size(), 8)
	eq("and they derive ONE room, not two", _rooms(naive), 1)


func _keeps_them_apart() -> void:
	var layout := _layout([_room_a(), _room_b()])
	eq("the layout derives two rooms", _rooms(_segments(layout)), 2)
	# 4 + 4 - 1: B's west edge is A's east edge, emitted once.
	eq("one wall per shared edge", layout.walls().size(), 7)


func _shared_door() -> void:
	var layout := _layout([_room_a(), _room_b()])
	eq("exactly one door, on the shared wall", _doors(layout), 1)

	# The door is ON the shared wall, not scattered onto some other one.
	var shared := _wall_at(layout, Vector2(8, 0), Vector2(8, 6))
	is_true("the shared wall is the one carrying it", not shared.is_empty())
	eq("and nothing else carries one", _door_count(shared), 1)


## The room the corridor connects to is 2 m away from the other one, and the
## corridor's ends butt INTO their walls rather than coinciding with them. That
## is the case the detector's planar subdivision already handles.
func _corridor_joins_rooms() -> void:
	var layout := _layout([_room_a(), _room_c(), _corridor()])
	eq("three rooms", _rooms(_segments(layout)), 3)


func _corridor_ends_dropped() -> void:
	var layout := _layout([_room_a(), _room_c(), _corridor()])
	# 4 + 4 + 2: the corridor's two LONG sides are walls, and its two END edges
	# lie along the rooms' walls, so they are doorways. Emitting them would put a
	# second wall on a segment that already has one.
	eq("the corridor's end walls are dropped", layout.walls().size(), 10)
	eq("and each end became a door", _doors(layout), 2)

	var west := _wall_at(layout, Vector2(8, 0), Vector2(8, 6))
	eq("the west room's wall has a door where the corridor meets it",
		_door_count(west), 1)


## Collinear edges that share an endpoint but do not overlap are a shared CORNER.
## A doorway there would be a door in a wall nobody can walk through.
func _corner_touch() -> void:
	var layout := _layout([_room_a(), _room_d()])
	eq("two rooms", _rooms(_segments(layout)), 2)
	eq("two walls meeting at a point is not a connection", _doors(layout), 0)


func _single_outline() -> void:
	var layout := _layout([_room_a()])
	eq("one outline is four walls", layout.walls().size(), 4)
	eq("with no doors — a doorway needs somewhere to lead", _doors(layout), 0)
	eq("and one room", _rooms(_segments(layout)), 1)


## Concave on purpose: the outline guard refuses only self-intersection, because
## an L-shaped building is legitimate.
func _concave() -> void:
	var layout := _layout([_ell()])
	eq("an L is six walls", layout.walls().size(), 6)
	eq("and one room, not two", _rooms(_segments(layout)), 1)


func _centre() -> void:
	var layout := _layout([_room_a(), _room_big()])
	var c := layout.centre()
	is_true("the biggest space wins, not the first one",
		c.distance_to(Vector2(19, 4)) < 0.001)


# ---------------------------------------------------------------- outlines
#
# Plan coordinates (x, z). A and B share the edge x = 8. A and C are 4 m apart
# with a corridor between them. D meets A at the single point (8, 6).

func _room_a() -> PackedVector2Array:
	return PackedVector2Array([Vector2(0, 0), Vector2(8, 0), Vector2(8, 6), Vector2(0, 6)])


func _room_b() -> PackedVector2Array:
	return PackedVector2Array([Vector2(8, 0), Vector2(16, 0), Vector2(16, 6), Vector2(8, 6)])


func _room_c() -> PackedVector2Array:
	return PackedVector2Array([Vector2(12, 0), Vector2(20, 0), Vector2(20, 6), Vector2(12, 6)])


func _room_d() -> PackedVector2Array:
	return PackedVector2Array([Vector2(8, 6), Vector2(16, 6), Vector2(16, 12), Vector2(8, 12)])


func _room_big() -> PackedVector2Array:
	return PackedVector2Array([Vector2(12, 0), Vector2(26, 0), Vector2(26, 8), Vector2(12, 8)])


func _corridor() -> PackedVector2Array:
	return PackedVector2Array([Vector2(8, 2), Vector2(12, 2), Vector2(12, 4), Vector2(8, 4)])


func _ell() -> PackedVector2Array:
	return PackedVector2Array([Vector2(0, 0), Vector2(12, 0), Vector2(12, 4),
		Vector2(6, 4), Vector2(6, 10), Vector2(0, 10)])


# ---------------------------------------------------------------- helpers

func _layout(outlines: Array) -> CozyDungeonLayout:
	var l := CozyDungeonLayout.new()
	l.set_outlines(outlines)
	return l


## The layout's walls in the shape the detector wants: [Vector2, Vector2] pairs
## in the (x, z) plane.
func _segments(layout: CozyDungeonLayout) -> Array:
	var out: Array = []
	for w in layout.walls():
		out.append([w["a"], w["b"]])
	return out


## The NAIVE path — every outline through `CozyOutlineGenerator.plan()` and
## nothing else. This is what the first implementation would have done.
func _segments_naive(outlines: Array) -> Array:
	var out: Array = []
	for poly in outlines:
		var intents := CozyOutlineGenerator.plan(poly, 0.0, 3.0, 0.25, "stone", 0,
			Vector2(999.0, 999.0))
		for it in intents:
			out.append([Vector2(it.a.x, it.a.z), Vector2(it.b.x, it.b.z)])
	return out


func _rooms(segments: Array) -> int:
	return CozyRoomDetector.new().detect(segments).size()


func _doors(layout: CozyDungeonLayout) -> int:
	var n := 0
	for w in layout.walls():
		n += (w["doors"] as Array).size()
	return n


## The wall between two points, either way round. Empty when there is none —
## which is itself a thing worth being able to assert.
func _wall_at(layout: CozyDungeonLayout, a: Vector2, b: Vector2) -> Dictionary:
	for w in layout.walls():
		var wa: Vector2 = w["a"]
		var wb: Vector2 = w["b"]
		if (wa.distance_to(a) < 0.001 and wb.distance_to(b) < 0.001) \
				or (wa.distance_to(b) < 0.001 and wb.distance_to(a) < 0.001):
			return w
	return {}


func _door_count(wall: Dictionary) -> int:
	return (wall.get("doors", []) as Array).size()
