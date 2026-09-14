class_name CozyDungeonLayout
extends RefCounted
## A dungeon's outlines, resolved into the walls that will be built.
##
## The design doc stores WALL OUTLINES rather than rooms, so that rooms, portals,
## navigation, roofs and the save are all produced by systems that already exist
## and are already asserted — "a dungeon is just another batch of walls".
##
## This file is the one step of that which is NOT free, and the reason is
## measured rather than argued. `tests/probe/dungeon_layout_probe.gd` ran the
## outlines of a two-room dungeon through the real pipeline:
##
##     one room                                    ->  1 room  (48 m2)
##     two rooms, each outline closing its loop     ->  1 room  (96 m2)  <-- merged
##     two rooms, shared edge emitted once          ->  2 rooms (48 + 48)
##     two rooms + corridor, each loop closed       ->  1 room  (104 m2) <-- merged
##     two rooms + corridor, corridor ends dropped  ->  3 rooms (48+48+8)
##
## `CozyOutlineGenerator.plan()` closes every outline into a loop, so two rooms
## side by side each emit the edge they share: one wall in each direction, on the
## same segment. The planar face traversal then merges them — silently. No error,
## no warning, one room where there should be two. A dungeon built on the naive
## reading ships as a single room and looks like it worked.
##
## So the outlines are resolved against EACH OTHER first, and the rest of the
## pipeline receives a wall graph with:
##
##   * ONE wall per shared edge, never two
##   * NO wall where an edge merely butts into a longer one — that is a doorway,
##     not a wall, and the longer wall already spans it
##   * a door cut wherever two outlines meet
##
## Everything after that is the existing pipeline, untouched.
##
## ---------------------------------------------------------------------------
## WHAT THIS DOES NOT DO. It places no spawns, reads no spawn tables and knows
## nothing about monsters or loot. Those need a vocabulary that does not exist
## yet, and this project has paid seven times for a table nothing consumes. The
## geometry is the part that has to be right first — everything else can be added
## on top of a wall graph that is known to produce the right rooms.

## Endpoint quantisation, 1 mm, matching `CozyRoomDetector.SNAP`. Two outlines
## drawn to the same coordinates must be recognised as sharing an edge, and
## comparing floats for that is a way to have it work nine times out of ten.
const SNAP := 1000.0

## Matches `CozyOutlineGenerator.DOOR_WIDTH`, so a dungeon door is the same door
## the rest of the game builds.
const DOOR_WIDTH := 1.5

## Narrower than this is not worth cutting a doorway into; the walls on either
## side of it would be slivers.
const MIN_DOOR := 0.8

## Collinearity tolerance, in metres of perpendicular distance. Generous next to
## `SNAP` on purpose: an outline authored by hand will be off by more than a
## millimetre long before it is off by a centimetre.
const COLLINEAR_TOL := 0.01

var outlines: Array = []          ## Array[PackedVector2Array], in plan (x, z)


func set_outlines(p_outlines: Array) -> void:
	outlines.clear()
	for o in p_outlines:
		outlines.append(o)


## The walls to build, with every shared edge resolved.
##
## Returns an Array of `{ "a": Vector2, "b": Vector2, "doors": Array }` where a
## door is `{ "offset": float, "width": float }` measured from `a` along the wall.
##
## The shape is deliberately not `CozyBuildingIntent`: which wall material, which
## floor and how tall are the CALLER's business, and a layout that had opinions
## about materials would be a second place for them to be wrong.
func walls() -> Array:
	var edges := _unique_edges()
	var out: Array = []

	for e in edges:
		if _is_butt_edge(e, edges):
			continue
		var span: float = (e["b"] as Vector2).distance_to(e["a"])
		out.append({
			"a": e["a"],
			"b": e["b"],
			"doors": _doors_for(e, edges, span),
		})

	return out


## The centre of the biggest enclosed outline — a default place to put the
## entrance when nothing more specific is authored (doc: "a boss room is the
## biggest room" generalises to "the entrance is in the biggest space").
func centre() -> Vector2:
	var best := Vector2.ZERO
	var best_area := -1.0
	for o in outlines:
		var a := _area(o)
		if a > best_area:
			best_area = a
			best = _centroid(o)
	return best


func outline_count() -> int:
	return outlines.size()


func describe() -> String:
	return "%d outline(s), %d wall(s)" % [outlines.size(), walls().size()]


# ---------------------------------------------------------------- the union

## One entry per distinct edge, remembering which outlines emitted it.
##
## `from` is the point of this pass: an edge emitted by two outlines IS the
## connection between them, and that is what earns it a door.
func _unique_edges() -> Array:
	var by_key := {}
	var order: Array = []

	for oi in outlines.size():
		var poly: PackedVector2Array = outlines[oi]
		var n := poly.size()
		if n < 3:
			continue
		for i in n:
			var a: Vector2 = poly[i]
			var b: Vector2 = poly[(i + 1) % n]
			if a.distance_to(b) < 0.001:
				continue
			var key := _edge_key(a, b)
			if not by_key.has(key):
				by_key[key] = {"a": a, "b": b, "from": {}, "length": a.distance_to(b)}
				order.append(key)
			(by_key[key]["from"] as Dictionary)[oi] = true

	var out: Array = []
	for k in order:
		out.append(by_key[k])
	return out


## An edge that lies entirely inside a LONGER collinear edge is a doorway, not a
## wall: the longer wall already spans it, and emitting both would put two walls
## on one segment — which is the merge this whole file exists to prevent.
##
## "Strictly longer" is what keeps a shared edge alive. Two rooms sharing a full
## edge produce two identical copies, which the dedup pass has already collapsed
## into one, so there is no longer edge for it to hide inside.
func _is_butt_edge(e: Dictionary, edges: Array) -> bool:
	for f in edges:
		if f == e:
			continue
		if float(f["length"]) <= float(e["length"]) + 0.001:
			continue
		var ov := _overlap(e, f)
		if ov.size() == 2 and float(ov[0]) <= 0.001 and float(ov[1]) >= 0.999:
			return true
	return false


## Where this wall is walked through: the whole span when two outlines share it,
## plus every stretch a neighbouring outline opens onto it.
func _doors_for(e: Dictionary, edges: Array, span: float) -> Array:
	var covered: Array = []

	# Shared outright — the two outlines agreed on this whole edge, so this is
	# the passage between them.
	if (e["from"] as Dictionary).size() >= 2:
		covered.append([0.0, 1.0])

	# Butted onto — a neighbour's edge runs along part of this wall.
	for f in edges:
		if f == e:
			continue
		if _same_outlines(e, f):
			continue
		var ov := _overlap(e, f)
		if ov.size() == 2:
			covered.append(ov)

	var merged := _merge(covered)

	var out: Array = []
	for iv in merged:
		var t0: float = iv[0]
		var t1: float = iv[1]
		var width: float = minf(DOOR_WIDTH, (t1 - t0) * span)
		if width < MIN_DOOR:
			continue
		var mid: float = (t0 + t1) * 0.5 * span
		out.append({"offset": mid - width * 0.5, "width": width})
	return out


## Two edges with identical outline sets are the same wall's own edges, or two
## edges of one outline; neither is a connection between outlines.
func _same_outlines(a: Dictionary, b: Dictionary) -> bool:
	var fa: Dictionary = a["from"]
	var fb: Dictionary = b["from"]
	if fa.size() != fb.size():
		return false
	for k in fa:
		if not fb.has(k):
			return false
	return true


## The parameter interval of `b`'s span along `a`, in [0, 1], or [] when they are
## not collinear and overlapping. Collinear-but-touching at a single point gives
## an empty interval, which is a shared corner rather than a doorway.
func _overlap(a: Dictionary, b: Dictionary) -> Array:
	var a1: Vector2 = a["a"]
	var a2: Vector2 = a["b"]
	var d := a2 - a1
	var len_sq := d.length_squared()
	if len_sq < 0.000001:
		return []
	var len := sqrt(len_sq)
	var perp := Vector2(-d.y, d.x) / len

	for p in [b["a"], b["b"]]:
		if absf((p - a1).dot(perp)) > COLLINEAR_TOL:
			return []

	var t0: float = (b["a"] - a1).dot(d) / len_sq
	var t1: float = (b["b"] - a1).dot(d) / len_sq
	var lo: float = maxf(0.0, minf(t0, t1))
	var hi: float = minf(1.0, maxf(t0, t1))
	if hi - lo < 0.0001:
		return []
	return [lo, hi]


## Union of parameter intervals over one wall, so a neighbour that meets it in
## two stretches gets one doorway per stretch rather than two overlapping ones.
func _merge(intervals: Array) -> Array:
	if intervals.is_empty():
		return []
	var sorted := intervals.duplicate()
	sorted.sort_custom(func(x, y): return float(x[0]) < float(y[0]))
	var out: Array = [sorted[0]]
	for iv in sorted.slice(1):
		var last: Array = out[out.size() - 1]
		if float(iv[0]) <= float(last[1]) + 0.0001:
			last[1] = maxf(float(last[1]), float(iv[1]))
		else:
			out.append([float(iv[0]), float(iv[1])])
	return out


# ---------------------------------------------------------------- geometry

## Direction-independent key, so an edge and its reverse are one edge.
func _edge_key(a: Vector2, b: Vector2) -> String:
	var ka := _quant(a)
	var kb := _quant(b)
	if ka.x > kb.x or (ka.x == kb.x and ka.y > kb.y):
		var t := ka
		ka = kb
		kb = t
	return "%d,%d|%d,%d" % [ka.x, ka.y, kb.x, kb.y]


func _quant(p: Vector2) -> Vector2i:
	return Vector2i(roundi(p.x * SNAP), roundi(p.y * SNAP))


func _area(poly: PackedVector2Array) -> float:
	var n := poly.size()
	if n < 3:
		return 0.0
	var acc := 0.0
	for i in n:
		var a := poly[i]
		var b := poly[(i + 1) % n]
		acc += a.x * b.y - b.x * a.y
	return absf(acc) * 0.5


func _centroid(poly: PackedVector2Array) -> Vector2:
	if poly.is_empty():
		return Vector2.ZERO
	var acc := Vector2.ZERO
	for p in poly:
		acc += p
	return acc / float(poly.size())
