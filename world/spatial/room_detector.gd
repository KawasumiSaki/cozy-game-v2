class_name CozyRoomDetector
extends RefCounted
## Derive rooms from the wall graph (V2 doc #26).
##
## The doc is explicit: rooms must NOT be hand-authored by the player. Given
## the wall segments on a single floor, the enclosed regions fall out of a
## standard planar face traversal:
##
##   1. snap endpoints, so walls that meet at a corner share one node
##   2. build half-edges — both directions of every segment
##   3. sort each node's outgoing half-edges by angle
##   4. walk faces: next(h) = the outgoing edge one step clockwise from twin(h)
##   5. keep positively-wound cycles — those are the enclosed rooms;
##      the outer boundary comes out negatively wound and is discarded
##
## This is why the wall system stores segments (start/end) rather than tiles:
## the same data that draws the wall also defines the room.

const SNAP := 1000.0   ## Quantise endpoints to 1mm so shared corners unify.
const MAX_STEPS := 100000


var _positions: Array[Vector2] = []
var _node_of: Dictionary = {}      ## Vector2i (snapped) -> node index
var _out_edges: Array = []         ## node index -> Array[int] half-edge ids

var _he_from: Array[int] = []
var _he_to: Array[int] = []
var _he_twin: Array[int] = []
var _he_angle: Array[float] = []
var _he_used: Array[bool] = []


## segments: Array of [Vector2, Vector2] in the floor's (x, z) plane.
## Returns: Array[PackedVector2Array], one polygon per enclosed room.
func detect(segments: Array) -> Array:
	_reset()
	for seg in segments:
		_add_segment(seg[0], seg[1])
	_sort_edges()
	return _trace_faces()


func _reset() -> void:
	_positions.clear()
	_node_of.clear()
	_out_edges.clear()
	_he_from.clear()
	_he_to.clear()
	_he_twin.clear()
	_he_angle.clear()
	_he_used.clear()


func _node_index(p: Vector2) -> int:
	var k := Vector2i(int(round(p.x * SNAP)), int(round(p.y * SNAP)))
	if _node_of.has(k):
		return _node_of[k]
	var idx := _positions.size()
	_node_of[k] = idx
	_positions.append(p)
	_out_edges.append([])
	return idx


func _add_segment(a: Vector2, b: Vector2) -> void:
	var ia := _node_index(a)
	var ib := _node_index(b)
	if ia == ib:
		return   # Degenerate: zero-length segment contributes no topology.

	var h := _he_from.size()
	_he_from.append(ia)
	_he_to.append(ib)
	_he_twin.append(h + 1)
	_he_angle.append((_positions[ib] - _positions[ia]).angle())

	_he_from.append(ib)
	_he_to.append(ia)
	_he_twin.append(h)
	_he_angle.append((_positions[ia] - _positions[ib]).angle())

	_out_edges[ia].append(h)
	_out_edges[ib].append(h + 1)
	_he_used.append(false)
	_he_used.append(false)


func _sort_edges() -> void:
	for lst in _out_edges:
		lst.sort_custom(func(x: int, y: int) -> bool: return _he_angle[x] < _he_angle[y])


## The next half-edge around a face.
## Arriving at node v along h, twin(h) points back the way we came; stepping one
## place clockwise from it keeps the face on a consistent side.
func _next_half_edge(h: int) -> int:
	var v := _he_to[h]
	var lst: Array = _out_edges[v]
	var idx := lst.find(_he_twin[h])
	var n := lst.size()
	return lst[(idx - 1 + n) % n]


func _trace_faces() -> Array:
	var faces: Array = []
	var steps := 0
	for start in _he_from.size():
		if _he_used[start]:
			continue
		var cycle: Array[int] = []
		var cur := start
		while not _he_used[cur] and steps < MAX_STEPS:
			_he_used[cur] = true
			cycle.append(cur)
			cur = _next_half_edge(cur)
			steps += 1

		if cycle.size() < 3:
			continue

		var poly := PackedVector2Array()
		for h in cycle:
			poly.append(_positions[_he_from[h]])

		# Positively-wound cycles are enclosed rooms; the outer boundary is
		# wound the other way and drops out here.
		if CozyRoom.signed_area(poly) > 0.0:
			faces.append(poly)

	# Large rooms first — stable, readable output.
	faces.sort_custom(func(a: PackedVector2Array, b: PackedVector2Array) -> bool:
		return absf(CozyRoom.signed_area(a)) > absf(CozyRoom.signed_area(b)))
	return faces
