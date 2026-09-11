class_name CozyWallState
extends RefCounted
## Pure data for one wall (V2.1 doc #19).
##
## This is where the wall LIVES. The Node3D that draws it is a generated view
## (doc #18: "Mesh 永远重新生成", deleting a mesh never deletes building logic).
##
## Nothing here knows about meshes, materials, or Godot nodes — only about the
## structure the player asked for.

var id := ""
var start := Vector3.ZERO
var end := Vector3.ZERO
var height := 3.0
var thickness := 0.25
var material_id := "wood"
var floor_id := 0
var openings: Array[CozyOpening] = []

## Deterministic art seed (doc #53). Same state must regenerate identically.
var seed_val := 0

## Written by the connection solver, never authored by the player (doc #22).
## Cached rather than recomputed so the generator can be re-run cheaply.
var extend_start := 0.0
var extend_end := 0.0


static func create(p_id: String, p_start: Vector3, p_end: Vector3,
		p_height := 3.0, p_thickness := 0.25, p_material := "wood",
		p_floor := 0) -> CozyWallState:
	var w := CozyWallState.new()
	w.id = p_id
	w.start = p_start
	w.end = p_end
	w.height = p_height
	w.thickness = p_thickness
	w.material_id = p_material
	w.floor_id = p_floor
	w.seed_val = hash(p_id)
	return w


func midpoint() -> Vector3:
	return (start + end) * 0.5


func length() -> float:
	var d := end - start
	d.y = 0.0
	return d.length()


## The segment the generator actually builds, after junction extensions.
func effective_segment() -> Array:
	var d := end - start
	d.y = 0.0
	var len := d.length()
	if len < 0.001:
		return [start, end]
	var dir := d / len
	return [start - dir * extend_start, end + dir * extend_end]


## Solve a segment into the box placement a wall needs.
##
## A wall extends across the ground plane; height is handled separately, so
## length only cares about the XZ delta. Aligning the box's local +X with the
## segment direction means rotating +X about Y by theta to get (cos t, 0, -sin t),
## which matches the unit segment direction when theta = atan2(-dz, dx).
static func segment_transform(a: Vector3, b: Vector3, wall_height: float) -> Dictionary:
	var d := b - a
	d.y = 0.0
	var length := maxf(d.length(), 0.001)
	return {
		"length": length,
		"angle": atan2(-d.z, d.x),
		"center": (a + b) * 0.5 + Vector3(0.0, wall_height * 0.5, 0.0),
	}


func add_opening(o: CozyOpening) -> void:
	openings.append(o)


## Centre-line span as (x, z) pairs — what the room detector consumes.
func centreline() -> Array:
	return [Vector2(start.x, start.z), Vector2(end.x, end.z)]


## Geometry-derived volume, the basis for construction cost (doc #34).
## Openings are not subtracted yet — a refinement, not a structural change.
func volume() -> float:
	return length() * height * thickness


func describe() -> String:
	return "%s (%.1f m, %.2f m3, %s)" % [id, length(), volume(), material_id]
