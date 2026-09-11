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


func describe() -> String:
	var lines: Array[String] = []
	for fi in floor_indices():
		var rs := rooms_on(fi)
		lines.append("  floor %d (y=%.1f): %d room(s)" % [fi, elevation_of(fi), rs.size()])
		for r in rs:
			lines.append("    - " + r.describe())
	return "\n".join(lines)
