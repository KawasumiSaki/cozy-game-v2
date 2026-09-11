class_name CozySlab
extends Node3D
## The GENERATED VIEW of a CozySlabState (doc #18).
##
## Holds no authoritative data. Rebuilt from the state at any time.
##
## It is FADABLE on purpose. With the camera pitched 52 degrees, a floor slab
## sits between the camera and anyone standing under it, so a slab that cannot
## fade hides the player exactly the way a wall would — the same problem doc #57
## solves for walls.

var state: CozySlabState = null

var _mesh: MeshInstance3D = null
var _body: StaticBody3D = null
var _mat: StandardMaterial3D = null
var _fade := 1.0


func setup_from(p_state: CozySlabState) -> void:
	state = p_state
	_rebuild()


func refresh() -> void:
	if is_inside_tree() and state != null:
		_rebuild()


func _rebuild() -> void:
	for c in get_children():
		c.queue_free()
	_mesh = null
	_body = null
	if state == null:
		return

	var bm := BoxMesh.new()
	bm.size = state.size

	_mat = CozyMaterials.get_material(state.material_id,
		Vector3(maxf(state.size.x / 2.0, 1.0), maxf(state.size.z / 2.0, 1.0), 1.0))
	_mat.vertex_color_use_as_albedo = true

	_mesh = MeshInstance3D.new()
	_mesh.mesh = bm
	_mesh.material_override = _mat
	_mesh.position = state.center
	add_child(_mesh)

	# Collision is not optional — a slab that is only drawn is a picture of a
	# floor, and characters fall through pictures.
	_body = StaticBody3D.new()
	_body.position = state.center
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = state.size
	cs.shape = bs
	_body.add_child(cs)
	add_child(_body)


func bodies() -> Array:
	return [_body] if _body != null else []


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
