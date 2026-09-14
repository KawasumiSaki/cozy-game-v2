extends SceneTree
## MEASUREMENT, not an assertion.
##
##     godot --headless --path <repo> --script res://tests/probe/dungeon_layout_probe.gd
##
## ---------------------------------------------------------------------------
## The dungeon blueprint stores WALL OUTLINES, not rooms (design doc section 3,
## revised 2026-09-12), on the claim that a dungeon "is just another batch of
## walls" and needs no parallel system.
##
## That claim has a geometry question hidden inside it that the document does not
## answer. `CozyOutlineGenerator.plan()` closes every outline into a loop of
## walls. So two rooms laid out NEXT TO EACH OTHER each emit the edge they share
## — one wall in each direction, on the same segment. And this project has
## already paid for exactly that class of mistake: duplicate edges corrupt the
## planar face traversal (INVARIANTS, "Openings do NOT modify the centre-line"),
## and a wall butting into another needs subdivision or it silently divides
## nothing ("T-junctions need planar subdivision").
##
## So measure what the EXISTING pipeline does with each way two rooms can be laid
## out beside each other, before designing anything on top of it. Five cases:
##
##   1. one room                          — the baseline the outline path already does
##   2. one L-shaped room                 — concave, deliberately not refused
##   3. two rooms, BOTH loops closed      — the naive reading of the blueprint
##   4. two rooms, shared edge emitted once
##   5. two rooms + a corridor, both loops closed
##   6. two rooms + a corridor, coincident edges emitted once
##
## Every case is pure: outlines -> intents -> centrelines -> CozyRoomDetector.
## No world, no nodes, no terrain. If the dungeon is "just walls", this is the
## whole claim, and it can be checked without booting anything.

func _initialize() -> void:
	print("[probe] dungeon layout: outlines -> CozyRoomDetector, no world")

	var one := [PackedVector2Array([
		Vector2(0, 0), Vector2(8, 0), Vector2(8, 6), Vector2(0, 6)])]

	# Concave on purpose: an L-shaped room is legitimate, and the outline guard
	# refuses only self-intersection.
	var ell := [PackedVector2Array([
		Vector2(0, 0), Vector2(12, 0), Vector2(12, 4),
		Vector2(6, 4), Vector2(6, 10), Vector2(0, 10)])]

	var east := PackedVector2Array([
		Vector2(8, 0), Vector2(16, 0), Vector2(16, 6), Vector2(8, 6)])
	var west := PackedVector2Array([
		Vector2(12, 0), Vector2(20, 0), Vector2(20, 6), Vector2(12, 6)])
	var corridor := PackedVector2Array([
		Vector2(8, 2), Vector2(12, 2), Vector2(12, 4), Vector2(8, 4)])

	_report("1. one room", _segments(one))
	_report("2. one L-shaped room", _segments(ell))
	_report("3. two rooms, both loops closed", _segments([one[0], east]))
	# The edge the two rooms share, emitted once instead of twice. Edge 3 of the
	# east room runs (8,6)->(8,0); the west room's edge 1 runs (8,0)->(8,6).
	_report("4. two rooms, shared edge once",
		_segments([one[0], east], [[1, 3]]))
	_report("5. rooms + corridor, both loops closed",
		_segments([one[0], west, corridor]))
	# The corridor's ends butt INTO each room's wall, so they are dropped: each
	# end lies along a wall the room already emitted. What is left of the
	# corridor is its two long sides, which now T-junction into those walls.
	_report("6. rooms + corridor, ends dropped",
		_segments([one[0], west, corridor], [[2, 1], [2, 3]]))

	quit(0)


## Outlines -> intents -> centrelines in the (x, z) plane the detector wants.
##
## `skip` holds [outline index, edge index] pairs to leave out, which is how a
## coincident edge is emitted once instead of twice.
##
## The door hint is parked far away so `plan()` picks an edge by its own rule
## rather than by where a player happened to stand — this probe is about the wall
## GRAPH, and a door does not modify the centre-line either way.
func _segments(outlines: Array, skip: Array = []) -> Array:
	var out: Array = []
	for oi in outlines.size():
		var poly: PackedVector2Array = outlines[oi]
		var intents := CozyOutlineGenerator.plan(poly, 0.0, 3.0, 0.25, "stone", 0,
			Vector2(999.0, 999.0))
		for i in intents.size():
			if skip.has([oi, i]):
				continue
			var it: CozyBuildingIntent = intents[i]
			out.append([Vector2(it.a.x, it.a.z), Vector2(it.b.x, it.b.z)])
	return out


func _report(label: String, segments: Array) -> void:
	var detector := CozyRoomDetector.new()
	var rooms := detector.detect(segments)
	var areas: Array = []
	for r in rooms:
		areas.append("%.1f" % _area(r))
	print("[probe] %-38s seg=%2d room(s)=%d area(s)=[%s]" % [
		label, segments.size(), rooms.size(), ", ".join(areas)])


## Shoelace. The detector returns polygons, and the AREA is what says whether a
## room came back the size it was drawn or merely came back.
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
