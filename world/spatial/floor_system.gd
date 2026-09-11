class_name CozyFloorSystem
extends RefCounted
## Floors as first-class spatial layers (V2 doc #8.2).
##
## The doc is firm that floor height must be a building-system parameter rather
## than a constant sprinkled through the codebase, and that a floor is a real
## elevation — not a render layer:
##
##     Floor 0  ->  elevation  0
##     Floor 1  ->  elevation  3
##     Basement ->  elevation -3
##
## This object owns the relationship between floor index, world height, and the
## rooms living on each floor. Everything spatial reads it; nothing hard-codes 3.

var floor_height := 3.0

var _rooms: Array[CozyRoom] = []
var _portals: Array[CozyPortal] = []


func floor_index_at(y: float) -> int:
	return int(round(y / floor_height))


func elevation_of(floor_index: int) -> float:
	return float(floor_index) * floor_height


func add_room(room: CozyRoom) -> void:
	_rooms.append(room)


func all_rooms() -> Array[CozyRoom]:
	return _rooms


func rooms_on(floor_index: int) -> Array[CozyRoom]:
	var out: Array[CozyRoom] = []
	for r in _rooms:
		if r.floor_index == floor_index:
			out.append(r)
	return out


func floor_indices() -> Array[int]:
	var seen := {}
	var out: Array[int] = []
	for r in _rooms:
		if not seen.has(r.floor_index):
			seen[r.floor_index] = true
			out.append(r.floor_index)
	out.sort()
	return out


## Which room contains this world position, or null when outdoors.
func room_at(pos: Vector3) -> CozyRoom:
	var fi := floor_index_at(pos.y)
	var xz := Vector2(pos.x, pos.z)
	for r in rooms_on(fi):
		if r.contains_point(xz):
			return r
	return null


# ---------------------------------------------------------------- portals

func add_portal(p: CozyPortal) -> void:
	_portals.append(p)


func all_portals() -> Array[CozyPortal]:
	return _portals


func portals_on(floor_index: int) -> Array[CozyPortal]:
	var out: Array[CozyPortal] = []
	for p in _portals:
		if p.a_floor == floor_index or p.b_floor == floor_index:
			out.append(p)
	return out


## Portals that connect two specific rooms — the edge set for the room graph.
func portals_between(room_a_id: String, room_b_id: String) -> Array[CozyPortal]:
	var out: Array[CozyPortal] = []
	for p in _portals:
		var fwd := p.a_room == room_a_id and p.b_room == room_b_id
		var rev := p.a_room == room_b_id and p.b_room == room_a_id
		if fwd or rev:
			out.append(p)
	return out


## Fill in each portal's floors and rooms by asking the spatial model where its
## endpoints actually land. Call this AFTER rooms have been detected — this is
## what implements doc #29 ("a Door knows room_a and room_b").
func resolve_portals() -> void:
	for p in _portals:
		p.a_floor = floor_index_at(p.a_position.y)
		p.b_floor = floor_index_at(p.b_position.y)
		var ra := room_at(p.a_position)
		var rb := room_at(p.b_position)
		p.a_room = ra.id if ra != null else ""
		p.b_room = rb.id if rb != null else ""


func describe() -> String:
	var lines: Array[String] = []
	for fi in floor_indices():
		var rs := rooms_on(fi)
		lines.append("  floor %d (y=%.1f): %d room(s)" % [fi, elevation_of(fi), rs.size()])
		for r in rs:
			lines.append("    - " + r.describe())
	if not _portals.is_empty():
		lines.append("  portals: %d" % _portals.size())
		for p in _portals:
			lines.append("    - " + p.describe())
	return "\n".join(lines)
