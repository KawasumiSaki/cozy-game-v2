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
	case("the conversion loses no wall and no door", _intents_are_total)
	case("plan axes become Godot axes, at the floor asked for", _axes_and_elevation)
	case("a door lands in the middle of its wall", _door_lands_centred)
	case("the intents derive the same two rooms the walls did", _intents_derive_rooms)


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


# ------------------------------------------------- the last link: intents
#
# `to_intents()` is where this lane stops being able to check itself. Up to here
# every number is a wall or a door; after it, the wall graph is handed to systems
# that already exist. So the cases below check the two things that conversion can
# get wrong and nothing downstream could notice: an axis, and half a door.

## Total or nothing. A conversion that quietly drops a wall still produces a
## dungeon — a smaller one — and every assertion downstream would agree with it.
func _intents_are_total() -> void:
	var layout := _layout([_room_a(), _room_b()])
	var walls := layout.walls()
	var intents := layout.to_intents()

	eq("one intent per wall", intents.size(), walls.size())
	eq("all of them walls to draw", _draw_walls(intents), intents.size())

	var wanted := 0
	for w in walls:
		wanted += (w["doors"] as Array).size()
	eq("every door survived as an opening", _openings(intents), wanted)
	# The canary. Without it "0 openings, 0 wanted" passes just as well as a
	# conversion that works — and it is the layout that would have gone quiet.
	eq("and there were doors to survive", wanted, 1)


## The conversion has to speak two coordinate systems, and nothing downstream can
## tell whether it did: a dungeon drawn in the wrong plane is still a dungeon.
func _axes_and_elevation() -> void:
	var layout := _layout([_room_a()])
	var intents := layout.to_intents(3.0)

	eq("four walls, four intents", intents.size(), 4)
	var north := _intent_at(intents, Vector2(0, 0), Vector2(8, 0))
	is_true("the north wall is there", north != null)
	if north == null:
		return
	near("plan x -> godot x", north.a.x, 0.0)
	near("plan z -> godot z", north.b.z, 0.0)
	near("the far end keeps its x", north.b.x, 8.0)
	near("and the floor's elevation is threaded through", north.a.y, 3.0)
	near("on both ends of the wall", north.b.y, 3.0)
	eq("nothing else was promoted to a wall kind", _draw_walls(intents), 4)


## The tooth for the one arithmetic this file could plausibly get wrong.
##
## The shared wall is 6 m and both outlines cover all of it, so the doorway
## belongs at 3.0 m. `walls()` used to report the door's NEAR EDGE (`3.0 - 1.5/2`
## = 2.25) and `CozyOpening.offset` means the CENTRE — `CozyOutlineGenerator`
## cuts its own doorway at `edge_len * 0.5`. Passing one through as the other
## moves every door in the dungeon 0.75 m sideways: far enough to matter, near
## enough to look right.
func _door_lands_centred() -> void:
	var layout := _layout([_room_a(), _room_b()])
	var shared := _intent_at(layout.to_intents(), Vector2(8, 0), Vector2(8, 6))

	is_true("the shared wall survives the conversion", shared != null)
	if shared == null:
		return
	eq("carrying exactly one opening", shared.openings.size(), 1)
	if shared.openings.is_empty():
		return
	near("centred on the wall, not at its near edge", shared.openings[0].offset, 3.0)
	near("and it is the same size door the rest of the game cuts",
		shared.openings[0].width, 1.5)
	eq("as a door, not a window", shared.openings[0].kind, CozyOpening.Kind.DOOR)


## End to end, through the REAL state: intents -> `CozyBuildingState` -> the room
## detector. This is the assertion that says the conversion is complete, because
## a lost wall, a lost door or a flipped axis all change the room count — and
## `CozyBuildingState` is what the game actually feeds.
func _intents_derive_rooms() -> void:
	var layout := _layout([_room_a(), _room_b()])
	var state := CozyBuildingState.new()
	for it in layout.to_intents():
		var w := state.add_wall(it.a, it.b, it.height, it.thickness,
			it.material_id, it.floor_id)
		for o in it.openings:
			w.add_opening(o)

	eq("seven walls in the state", state.wall_count(), 7)
	eq("one opening, on the wall that earned it", _state_openings(state), 1)
	eq("and still two rooms, not the merged one", _rooms(_centrelines(state)), 2)
	# The nail that the first case in this file drives from the other side: same
	# outlines through the RAW generator give one room. Both halves are needed.
	eq("the naive path still merges them, as it always did",
		_rooms(_segments_naive([_room_a(), _room_b()])), 1)


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


## The wall between two PLAN points, either way round, among the layout's intents.
## Empty when there is none — which is itself a thing worth being able to assert.
func _intent_at(intents: Array, a: Vector2, b: Vector2) -> CozyBuildingIntent:
	for it in intents:
		var ia := Vector2(it.a.x, it.a.z)
		var ib := Vector2(it.b.x, it.b.z)
		if (ia.distance_to(a) < 0.001 and ib.distance_to(b) < 0.001) \
				or (ia.distance_to(b) < 0.001 and ib.distance_to(a) < 0.001):
			return it
	return null


func _draw_walls(intents: Array) -> int:
	var n := 0
	for it in intents:
		if it.kind == CozyBuildingIntent.Kind.DRAW_WALL:
			n += 1
	return n


func _openings(intents: Array) -> int:
	var n := 0
	for it in intents:
		n += it.openings.size()
	return n


## The state's walls in the shape the detector wants, straight off the state —
## not re-derived from the intents, so a wall the state refused would show up.
func _centrelines(state: CozyBuildingState) -> Array:
	var out: Array = []
	for w in state.walls:
		out.append(w.centreline())
	return out


func _state_openings(state: CozyBuildingState) -> int:
	var n := 0
	for w in state.walls:
		n += w.openings.size()
	return n


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
