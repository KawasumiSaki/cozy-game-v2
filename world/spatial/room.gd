class_name CozyRoom
extends RefCounted
## A room: a region of real space (V2 doc #8.3 / #27).
##
## Rooms are NOT authored by hand. They are derived from the wall graph —
## see CozyRoomDetector. That is what lets the doc treat a building as
## "a dynamic spatial structure" rather than a static picture (#28): move a
## wall, and the room polygon is recomputed.

var id := ""
var floor_index := 0

## Footprint in the floor's horizontal plane, as (x, z) pairs in world units.
var polygon := PackedVector2Array()

## Centroids / area are cached because navigation and NPC logic query them often.
var centroid := Vector2.ZERO
var area := 0.0


func _init(p_id := "", p_floor := 0, p_polygon := PackedVector2Array()) -> void:
	id = p_id
	floor_index = p_floor
	polygon = p_polygon
	_recompute()


func _recompute() -> void:
	area = absf(signed_area(polygon))
	centroid = _centroid(polygon)


## Shoelace formula. Sign encodes winding order, which is how the detector
## distinguishes an enclosed room from the outer boundary.
static func signed_area(poly: PackedVector2Array) -> float:
	var n := poly.size()
	if n < 3:
		return 0.0
	var acc := 0.0
	for i in n:
		var a := poly[i]
		var b := poly[(i + 1) % n]
		acc += a.x * b.y - b.x * a.y
	return acc * 0.5


static func _centroid(poly: PackedVector2Array) -> Vector2:
	var n := poly.size()
	if n == 0:
		return Vector2.ZERO
	var acc := Vector2.ZERO
	for p in poly:
		acc += p
	return acc / float(n)


## Point-in-polygon (ray casting). Used to answer "which room is this entity in?"
func contains_point(xz: Vector2) -> bool:
	var n := polygon.size()
	if n < 3:
		return false
	var inside := false
	var j := n - 1
	for i in n:
		var a := polygon[i]
		var b := polygon[j]
		if ((a.y > xz.y) != (b.y > xz.y)) \
				and (xz.x < (b.x - a.x) * (xz.y - a.y) / (b.y - a.y) + a.x):
			inside = not inside
		j = i
	return inside


func describe() -> String:
	return "%s (floor %d, %.1f m2, %d verts)" % [id, floor_index, area, polygon.size()]
