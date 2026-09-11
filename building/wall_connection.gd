class_name CozyWallSolver
extends RefCounted
## Wall connection solver (V2.1 doc #22, originally #24/#25).
##
## Two boxes that stop at a joint each contribute half a thickness, so a
## thickness-sized square of daylight is missing from the outside of an L-corner:
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
## past the joint so the boxes overlap and the corner reads as solid.
##
## This operates on STATES, not on generated geometry — the solver is part of
## the Rules/Solver stage in doc #70's chain, upstream of the generator. It
## reports which walls it modified so regeneration stays incremental (doc #32).

const EXTEND_FRACTION := 0.5   ## Of wall thickness, per joined end.
const SNAP := 1000.0           ## Position quantisation for "same point".


## Set extend_start / extend_end on every wall whose end meets another wall.
## Returns the ids of walls whose extension actually changed, so the caller can
## rebuild only those views.
static func solve_states(walls: Array) -> Array[String]:
	var buckets := {}
	for w in walls:
		_bucket(buckets, w.start).append(w)
		_bucket(buckets, w.end).append(w)

	var changed: Array[String] = []
	for w in walls:
		var prev_start: float = w.extend_start
		var prev_end: float = w.extend_end
		var half: float = w.thickness * EXTEND_FRACTION

		# More than one wall sharing this exact point means a junction.
		w.extend_start = half if _bucket(buckets, w.start).size() > 1 else 0.0
		w.extend_end = half if _bucket(buckets, w.end).size() > 1 else 0.0

		if not is_equal_approx(prev_start, w.extend_start) \
				or not is_equal_approx(prev_end, w.extend_end):
			changed.append(w.id)
	return changed


## Is this world point inside any generated wall volume?
## Used by the self-check to prove a corner actually gained material.
static func any_view_contains(views: Array, p: Vector3) -> bool:
	for v in views:
		if is_instance_valid(v) and v.contains_point(p):
			return true
	return false


static func _key(p: Vector3) -> Vector3i:
	return Vector3i(int(round(p.x * SNAP)), int(round(p.y * SNAP)), int(round(p.z * SNAP)))


static func _bucket(buckets: Dictionary, p: Vector3) -> Array:
	var k := _key(p)
	if not buckets.has(k):
		buckets[k] = []
	return buckets[k]
