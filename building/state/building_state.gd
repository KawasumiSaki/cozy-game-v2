class_name CozyBuildingState
extends RefCounted
## The single source of truth for everything built (V2.1 doc #18 / #64).
##
## Everything else in the building system — meshes, colliders, room polygons,
## navigation grids — is DERIVED. All of it may be thrown away and regenerated
## at any time. This object may not.
##
## That separation is what makes the rest of the doc's rules possible: save only
## stores this (doc #64), the dirty graph starts here (doc #32), and the player
## never edits geometry directly (doc #1.4).

signal changed

var walls: Array[CozyWallState] = []

## Doc #18 lists Floor and Stair alongside Wall as things BuildingState owns.
## They used to be emitted straight into the scene, which meant a roof generator
## had no way to find out where the floors were.
var slabs: Array[CozySlabState] = []
var stairs: Array[CozyStairState] = []
var roofs: Array[CozyRoofState] = []

var _next_wall_id := 1
var _next_slab_id := 1
var _next_stair_id := 1
var _next_roof_id := 1


func add_wall(a: Vector3, b: Vector3, height := 3.0, thickness := 0.25,
		material := "wood", floor_id := 0) -> CozyWallState:
	var w := CozyWallState.create("wall_%03d" % _next_wall_id, a, b,
		height, thickness, material, floor_id)
	_next_wall_id += 1
	walls.append(w)
	changed.emit()
	return w


func add_slab(center: Vector3, size: Vector3, material := "stone",
		floor_id := 0) -> CozySlabState:
	var s := CozySlabState.create("slab_%03d" % _next_slab_id, center, size,
		material, floor_id)
	_next_slab_id += 1
	slabs.append(s)
	changed.emit()
	return s


func add_stair(start: Vector3, end: Vector3, width := 3.0,
		material := "wood") -> CozyStairState:
	var s := CozyStairState.create("stair_%03d" % _next_stair_id, start, end,
		width, material)
	_next_stair_id += 1
	stairs.append(s)
	changed.emit()
	return s


func add_roof(room_id: String, poly: PackedVector2Array, base_y: float,
		style := CozyRoofState.Style.GABLE, material := "brick",
		floor_id := 0) -> CozyRoofState:
	var r := CozyRoofState.create("roof_%03d" % _next_roof_id, room_id, poly,
		base_y, style, material, floor_id)
	_next_roof_id += 1
	roofs.append(r)
	changed.emit()
	return r


func roof(id: String) -> CozyRoofState:
	for r in roofs:
		if r.id == id:
			return r
	return null


func slab(id: String) -> CozySlabState:
	for s in slabs:
		if s.id == id:
			return s
	return null


func stair(id: String) -> CozyStairState:
	for s in stairs:
		if s.id == id:
			return s
	return null


## Slabs whose walkable surface sits at this floor's elevation — what a roof
## generator and a floor query both need.
func slabs_on_floor(floor_id: int) -> Array[CozySlabState]:
	var out: Array[CozySlabState] = []
	for s in slabs:
		if s.floor_id == floor_id:
			out.append(s)
	return out


## Retire a roof so it can be regenerated. Roofs are derived, so "removing" one
## is just dropping it — the generator puts back whatever the rooms now call for.
func remove_roof(id: String) -> bool:
	for i in roofs.size():
		if roofs[i].id == id:
			roofs.remove_at(i)
			changed.emit()
			return true
	return false


func remove_wall(id: String) -> bool:
	for i in walls.size():
		if walls[i].id == id:
			walls.remove_at(i)
			changed.emit()
			return true
	return false


func wall(id: String) -> CozyWallState:
	for w in walls:
		if w.id == id:
			return w
	return null


func walls_on_floor(floor_id: int) -> Array[CozyWallState]:
	var out: Array[CozyWallState] = []
	for w in walls:
		if w.floor_id == floor_id:
			out.append(w)
	return out


func wall_count() -> int:
	return walls.size()


## Total geometry-derived volume — the basis for construction cost (doc #34).
func total_volume() -> float:
	var v := 0.0
	for w in walls:
		v += w.volume()
	return v


func floor_ids() -> Array[int]:
	var seen := {}
	var out: Array[int] = []
	for w in walls:
		if not seen.has(w.floor_id):
			seen[w.floor_id] = true
			out.append(w.floor_id)
	out.sort()
	return out


## Facts only — the shape one WALL takes in a save file (doc #64).
##
## WALLS, SLABS and STAIRS are all AUTHORED state: a slab is a floor someone drew,
## a stair is a route someone placed. All three have to be stored, and for a long
## time only walls were — which meant a load silently dropped the floors and the
## staircase. Nothing caught it because nothing consumed this code.
##
## One entity at a time, because the save holds ONE entity list and the registry
## asks each owner to encode its own kind (Core Architecture V1.0, item 1). The
## id stays inside the payload, where it has always been, so the file never
## carries the same id twice.
##
## `seed_val` is absent on purpose: it is `hash(id)`, so it returns for free on
## load and storing it would create a second source of truth.
func wall_dict(w: CozyWallState) -> Dictionary:
	var ops: Array = []
	for o in w.openings:
		ops.append({
			"kind": o.kind_name(),
			"offset": o.offset,
			"width": o.width,
			"sill": o.sill,
			"head": o.head,
		})
	return {
		"id": w.id,
		"start": [w.start.x, w.start.y, w.start.z],
		"end": [w.end.x, w.end.y, w.end.z],
		"height": w.height,
		"thickness": w.thickness,
		"material_id": w.material_id,
		"floor_id": w.floor_id,
		"openings": ops,
	}


func slab_dict(s: CozySlabState) -> Dictionary:
	return {
		"id": s.id,
		"center": [s.center.x, s.center.y, s.center.z],
		"size": [s.size.x, s.size.y, s.size.z],
		"material_id": s.material_id,
		"floor_id": s.floor_id,
	}


func stair_dict(t: CozyStairState) -> Dictionary:
	return {
		"id": t.id,
		"start": [t.start.x, t.start.y, t.start.z],
		"end": [t.end.x, t.end.y, t.end.z],
		"width": t.width,
		"material_id": t.material_id,
		"floor_from": t.floor_from,
		"floor_to": t.floor_to,
		"steps": t.steps,
	}


## The id counters, which travel with the world but are NOT entities.
##
## Ids are minted as `"wall_%03d" % _next_wall_id`, so a load that reset a counter
## would immediately mint an id that already exists — the collision the registry
## refuses would happen on the very next wall someone drew. They are split out
## because they have no id of their own and cannot be addressed by one.
##
## ROOFS are absent from the entity list but their counter is here: roofs are
## regenerated on load, and a regenerated roof must not reuse a live id.
func counters_to_dict() -> Dictionary:
	return {
		"wall": _next_wall_id,
		"slab": _next_slab_id,
		"stair": _next_stair_id,
		"roof": _next_roof_id,
	}


## Call AFTER `from_dict`: a missing key falls back to "one past the entities
## that are actually here", which is only the right answer once they have loaded.
## Every writer supplies all four keys, so the fallback exists for a file this
## build did not write rather than for the ordinary path.
func counters_from_dict(d: Dictionary) -> void:
	_next_wall_id = int(d.get("wall", walls.size() + 1))
	_next_slab_id = int(d.get("slab", slabs.size() + 1))
	_next_stair_id = int(d.get("stair", stairs.size() + 1))
	_next_roof_id = int(d.get("roof", 1))


## Rebuild in place, so `building.state` keeps its identity and every existing
## connection to its `changed` signal stays valid. Roofs are cleared rather than
## restored — the roof generator refills them from the rooms.
##
## ENTITIES ONLY. The id counters arrive separately through `counters_from_dict`,
## because a caller that regroups a saved entity list by kind has no reason to
## know what a counter is — and reading them here would give the same fact two
## readers.
func from_dict(d: Dictionary) -> void:
	walls.clear()
	slabs.clear()
	stairs.clear()
	roofs.clear()

	for wd in d.get("walls", []):
		var a: Array = wd["start"]
		var b: Array = wd["end"]
		var w := CozyWallState.create(String(wd["id"]),
			Vector3(a[0], a[1], a[2]), Vector3(b[0], b[1], b[2]),
			float(wd.get("height", 3.0)), float(wd.get("thickness", 0.25)),
			String(wd.get("material_id", "wood")), int(wd.get("floor_id", 0)))
		for od in wd.get("openings", []):
			var kind := String(od.get("kind", "door"))
			var off := float(od.get("offset", 0.0))
			var wid := float(od.get("width", 1.0))
			var head := float(od.get("head", 2.1))
			if kind == "window":
				w.add_opening(CozyOpening.window(off, wid,
					float(od.get("sill", 0.9)), head))
			else:
				w.add_opening(CozyOpening.door(off, wid, head))
		walls.append(w)

	for sd in d.get("slabs", []):
		var c: Array = sd["center"]
		var z: Array = sd["size"]
		slabs.append(CozySlabState.create(String(sd["id"]),
			Vector3(c[0], c[1], c[2]), Vector3(z[0], z[1], z[2]),
			String(sd.get("material_id", "stone")), int(sd.get("floor_id", 0))))

	for td in d.get("stairs", []):
		var p: Array = td["start"]
		var q: Array = td["end"]
		var t := CozyStairState.create(String(td["id"]),
			Vector3(p[0], p[1], p[2]), Vector3(q[0], q[1], q[2]),
			float(td.get("width", 3.0)), String(td.get("material_id", "wood")))
		t.floor_from = int(td.get("floor_from", 0))
		t.floor_to = int(td.get("floor_to", 1))
		t.steps = int(td.get("steps", 8))
		stairs.append(t)

	changed.emit()


func describe() -> String:
	return "%d wall(s), %d slab(s), %d stair(s), %d roof(s), %.1f m3" % [
		walls.size(), slabs.size(), stairs.size(), roofs.size(), total_volume()]
