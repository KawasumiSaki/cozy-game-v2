class_name CozyWall
extends Node3D
## Wall — the most basic building component (V2 doc #19, Wall System).
##
## Core idea: a Wall is NOT "one tile". It is a LINE SEGMENT plus building
## parameters:
##     start / end / height / thickness / material
##
## That is what makes arbitrary length (#20) and arbitrary angle (#21) fall out
## for free. Traditional tile building cannot do this — the doc calls out the
## symptoms in #16: houses look like checkerboards, diagonal walls are painful,
## roofs never join up naturally.
##
## Every wall produces BOTH:
##     Visual Geometry  +  Collision        (doc #16, "buildings connect to simulation")

var start := Vector3.ZERO
var end := Vector3.ZERO
var height := 3.0
var thickness := 0.25
var material_id := "wood"

var mesh_instance: MeshInstance3D = null
var static_body: StaticBody3D = null

var _mat: StandardMaterial3D = null
var _fade := 1.0


func setup(p_start: Vector3, p_end: Vector3, p_height := 3.0,
		p_thickness := 0.25, p_material := "wood") -> void:
	start = p_start
	end = p_end
	height = p_height
	thickness = p_thickness
	material_id = p_material
	_rebuild()


## Solve a segment into the box placement a wall needs.
## Shared with the build-mode preview so the two can never drift apart.
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


func _rebuild() -> void:
	for c in get_children():
		c.queue_free()

	var t := segment_transform(start, end, height)
	var length: float = t["length"]
	var angle: float = t["angle"]

	var box := BoxMesh.new()
	box.size = Vector3(length, height, thickness)

	# Repeat the texture every 2 metres so a long wall reads as individual
	# planks instead of one stretched smear.
	_mat = CozyMaterials.get_material(material_id,
		Vector3(maxf(length / 2.0, 1.0), maxf(height / 2.0, 1.0), 1.0))

	mesh_instance = MeshInstance3D.new()
	mesh_instance.mesh = box
	mesh_instance.material_override = _mat
	mesh_instance.position = t["center"]
	mesh_instance.rotation.y = angle
	add_child(mesh_instance)

	# Collision body (doc #8.6): characters and NPCs cannot walk through walls.
	static_body = StaticBody3D.new()
	static_body.position = mesh_instance.position
	static_body.rotation.y = angle
	var shape := CollisionShape3D.new()
	var box_shape := BoxShape3D.new()
	box_shape.size = box.size
	shape.shape = box_shape
	static_body.add_child(shape)
	add_child(static_body)


## Occlusion fade (doc #12.2): fade the wall when it blocks the player,
## rather than making the player disappear.
func set_fade(a: float) -> void:
	if is_equal_approx(a, _fade) or _mat == null:
		return
	_fade = a
	if a >= 0.999:
		_mat.transparency = BaseMaterial3D.TRANSPARENCY_DISABLED
		_mat.albedo_color = Color(1, 1, 1, 1)
	else:
		_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_mat.albedo_color = Color(1, 1, 1, a)


func midpoint() -> Vector3:
	return (start + end) * 0.5
