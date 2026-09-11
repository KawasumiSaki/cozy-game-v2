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
const ON_EDGE_TOL := 0.001   ## Metres; a node this close to a segment lies on it.


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

	# Pass 1 — collect every endpoint as a candidate node.
	var raw: Array = []
	for seg in segments:
		var a: Vector2 = seg[0]
		var b: Vector2 = seg[1]
		raw.append([a, b])
		_node_index(a)
		_node_index(b)

	# Pass 2 — planar subdivision: split each segment wherever another node
	# lies on its interior.
	#
	# This is NOT optional. A wall that butts into the middle of another wall
	# forms a T-junction, and without splitting, the graph is not planar — the
	# long wall is still one edge, so face traversal cannot see the two rooms
	# the new wall just created. A dividing wall would silently fail to divide.
	var all_nodes := _positions.duplicate()
	for seg in raw:
		for part in _split_at_nodes(seg[0], seg[1], all_nodes):
			_add_segment(part[0], part[1])

	_sort_edges()
	return _trace_faces()


## Break a-b at every known node strictly between its endpoints, ordered along
## the segment. Returns the sub-segments (or the original span when nothing
## lands on it).
func _split_at_nodes(a: Vector2, b: Vector2, nodes: Array) -> Array:
	var d := b - a
	var len_sq := d.length_squared()
	if len_sq < 1e-12:
		return [[a, b]]

	var cuts: Array = []
	for node_pos in nodes:
		var pos: Vector2 = node_pos
		var t: float = (pos - a).dot(d) / len_sq
		if t <= 0.0 or t >= 1.0:
			continue   # Only interior points split; endpoints are already nodes.
		if (a + d * t).distance_to(pos) <= ON_EDGE_TOL:
			cuts.append({"t": t, "p": pos})

	if cuts.is_empty():
		return [[a, b]]

	cuts.sort_custom(func(x: Dictionary, y: Dictionary) -> bool: return x["t"] < y["t"])

	var out: Array = []
	var prev := a
	for c in cuts:
		out.append([prev, c["p"]])
		prev = c["p"]
	out.append([prev, b])
	return out


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
