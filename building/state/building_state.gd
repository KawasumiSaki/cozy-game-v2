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

var _next_wall_id := 1


func add_wall(a: Vector3, b: Vector3, height := 3.0, thickness := 0.25,
		material := "wood", floor_id := 0) -> CozyWallState:
	var w := CozyWallState.create("wall_%03d" % _next_wall_id, a, b,
		height, thickness, material, floor_id)
	_next_wall_id += 1
	walls.append(w)
	changed.emit()
	return w


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


## Facts only — the shape a save file will take (doc #64).
func to_dict() -> Dictionary:
	var ws: Array = []
	for w in walls:
		var ops: Array = []
		for o in w.openings:
			ops.append({
				"kind": o.kind_name(),
				"offset": o.offset,
				"width": o.width,
				"sill": o.sill,
				"head": o.head,
			})
		ws.append({
			"id": w.id,
			"start": [w.start.x, w.start.y, w.start.z],
			"end": [w.end.x, w.end.y, w.end.z],
			"height": w.height,
			"thickness": w.thickness,
			"material_id": w.material_id,
			"floor_id": w.floor_id,
			"seed": w.seed_val,
			"openings": ops,
		})
	return {"walls": ws, "next_wall_id": _next_wall_id}


func describe() -> String:
	return "%d wall(s), %.1f m3" % [walls.size(), total_volume()]
