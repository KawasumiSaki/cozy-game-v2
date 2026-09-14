class_name CozyWorldNavigator
extends RefCounted
## Joins the two halves of navigation (V2 doc #41).
##
##     Room Graph  ->  "which rooms must I cross?"     topology, no geometry
##     Local nav   ->  "how do I walk across this one?" geometry, no topology
##
## Neither is sufficient alone. The doc names the failure in #9.2: an NPC given
## a coordinate on the first floor has no idea how to get upstairs — "the
## coordinate exists, the spatial topology does not."
##
## This class is the join. It plans across rooms through portals, and inside a
## room along the local grid, producing a flat list of world waypoints an agent
## can simply follow.

var floor_system: CozyFloorSystem = null
var room_graph: CozyRoomGraph = null
var nav_by_room: Dictionary = {}   ## room id -> CozyLocalNav

## Why the last plan failed, for diagnosis. Empty when it succeeded.
var last_failure := ""


func _init(fs: CozyFloorSystem, rg: CozyRoomGraph, navs: Dictionary) -> void:
	floor_system = fs
	room_graph = rg
	nav_by_room = navs


## World-space waypoints from `from` to `to`, or empty when no route exists.
func plan(from: Vector3, to: Vector3) -> PackedVector3Array:
	var out := PackedVector3Array()

	var from_room := floor_system.room_at(from)
	var to_room := floor_system.room_at(to)
	var a_id := _norm(from_room.id if from_room != null else "")
	var b_id := _norm(to_room.id if to_room != null else "")

	last_failure = ""
	if a_id == b_id:
		return _local(from, to, a_id)

	var route := room_graph.find_route(a_id, b_id)
	if route.is_empty():
		# Unreachable is a legitimate answer — but say WHICH pair was
		# unreachable, so a transient failure can be diagnosed rather than
		# guessed at.
		last_failure = "%s -> %s (no graph route)" % [a_id, b_id]
		return out

	var cursor := from
	var cursor_room := a_id
	for p in route:
		var near: Vector3
		var far: Vector3
		var next_room: String
		if _norm(p.a_room) == cursor_room:
			near = p.a_position
			far = p.b_position
			next_room = _norm(p.b_room)
		else:
			near = p.b_position
			far = p.a_position
			next_room = _norm(p.a_room)

		out.append_array(_local(cursor, near, cursor_room))
		out.append(far)          # Step through the portal.
		cursor = far
		cursor_room = next_room

	out.append_array(_local(cursor, to, cursor_room))
	return out


## Local leg: the waypoints from `from` to `to` inside ONE space.
##
## THE OUTDOORS IS LOOKED UP LIKE ANY ROOM. It used to be special-cased to a
## straight line (`if room_id == OUTDOORS: out.append(to)`), and that one line
## meant the outdoor navigation grid was built, asserted, handed to this class —
## and never read. Every reader of it was a self-check, and `_check_outdoor_nav`,
## which proves the grid routes around the house, was measuring the grid rather
## than the navigator. So the check was green while a resident walking from the
## front of the house to the back walked THROUGH it.
##
## Measured 2026-09-14, before the fix, by asking the navigator for three routes
## with the house between their ends: all three were one waypoint and one leg
## through geometry. After: none. See `docs/INVARIANTS.md`, "A navigation layer
## that nothing consults is not a navigation layer".
##
## Note the fallback is still a straight line, and has to be: a target outside
## the grid has no route, and standing still is worse. What changed is that the
## grid gets asked FIRST.
func _local(from: Vector3, to: Vector3, room_id: String) -> PackedVector3Array:
	var out := PackedVector3Array()
	if not nav_by_room.has(room_id):
		out.append(to)   # No grid for this space; let the agent try a straight line.
		return out

	var nav: CozyLocalNav = nav_by_room[room_id]
	var pts := nav.find_path(Vector2(from.x, from.z), Vector2(to.x, to.z))
	if pts.is_empty():
		out.append(to)   # No grid route; let the agent try a straight line.
		return out
	for p in pts:
		out.append(Vector3(p.x, from.y, p.y))
	return out


static func _norm(room_id: String) -> String:
	return room_id if room_id != "" else CozyRoomGraph.OUTDOORS
