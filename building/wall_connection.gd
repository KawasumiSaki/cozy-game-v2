class_name CozyWallSolver
extends RefCounted
## Wall connection solver (V2 doc #24 Wall Connection, #25 Procedural Fusion).
##
## The doc's complaint (#25) is that placing two wall meshes next to each other
## reads as "two models that happen to sit side by side" rather than one building
## that was actually constructed.
##
## The visible symptom is at an outer corner. Two boxes that stop at the joint
## each contribute half a thickness, so a thickness-sized square of daylight is
## missing from the outside of the corner:
##
##     (looking down at an L-corner, '#' = wall)
##
##         ##########
##         ##########
##         ##
##         ##        <- the outer corner is notched
##         ##
##
## The fix is the classic one: at a junction, run each wall half a thickness
## past the joint so the boxes overlap and the corner reads as solid. That is
## the "Connection Solver -> Corner -> Beam -> Final Structure" chain in #25,
## reduced to the piece that actually matters for a box-built wall.

const EXTEND_FRACTION := 0.5   ## Of wall thickness, per joined end.

## Position quantisation for deciding two wall ends occupy the same point.
const SNAP := 1000.0


## Set extend_start / extend_end on every wall whose end meets another wall,
## then refresh the geometry. Safe to call on every rebuild.
static func solve(walls: Array) -> void:
	var buckets := {}
	for w in walls:
		_bucket(buckets, w.start).append(w)
		_bucket(buckets, w.end).append(w)

	for w in walls:
		w.extend_start = 0.0
		w.extend_end = 0.0
		var half: float = w.thickness * EXTEND_FRACTION
		# More than one wall sharing this exact point means a junction.
		if _bucket(buckets, w.start).size() > 1:
			w.extend_start = half
		if _bucket(buckets, w.end).size() > 1:
			w.extend_end = half
		w.refresh()


## Is this world point inside any wall's solid volume?
## Used by the self-check to prove the corner actually gained material.
static func any_wall_contains(walls: Array, p: Vector3) -> bool:
	for w in walls:
		if w.contains_point(p):
			return true
	return false


static func _key(p: Vector3) -> Vector3i:
	return Vector3i(int(round(p.x * SNAP)), int(round(p.y * SNAP)), int(round(p.z * SNAP)))


static func _bucket(buckets: Dictionary, p: Vector3) -> Array:
	var k := _key(p)
	if not buckets.has(k):
		buckets[k] = []
	return buckets[k]
