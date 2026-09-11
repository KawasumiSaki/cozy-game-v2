class_name CozyRoof
extends Node3D
## The GENERATED VIEW of a CozyRoofState (doc #31 / #57).
##
## Geometry comes from CozyRoofGenerator, so the shape follows the room polygon
## rather than being a placed prefab. This node only turns the plan into a mesh
## and a collider.
##
## It MUST fade. Doc #57's whole complaint is that a roof which cannot fade
## hides the player the moment they walk inside; that was true of the flat
## placeholder this replaces, and it is truer of a pitched roof, which covers
## more of the screen.

var state: CozyRoofState = null

var _mesh: MeshInstance3D = null
var _body: StaticBody3D = null
var _mat: StandardMaterial3D = null
var _plan: Dictionary = {}
var _fade := 1.0


func setup_from(p_state: CozyRoofState) -> void:
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
	_plan = {}
	if state == null:
		return

	_plan = CozyRoofGenerator.plan(state)
	if _plan.get("faces", []).is_empty() and not _plan.has("box"):
		return

	_mat = CozyMaterials.get_material(state.material_id, Vector3(2.0, 2.0, 1.0))
	_mat.vertex_color_use_as_albedo = true

	_mesh = MeshInstance3D.new()
	_mesh.material_override = _mat

	if _plan.has("box"):
		# Flat: a slab, so a box rather than a face list.
		var box: Dictionary = _plan["box"]
		var bm := BoxMesh.new()
		bm.size = box["size"]
		_mesh.mesh = bm
		_mesh.position = box["center"]
	else:
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		CozyRoofGenerator.emit(st, _plan)
		_mesh.mesh = st.commit()
	add_child(_mesh)

	# Coarse collision: one thin box across the footprint, at eave level. The
	# player never walks on a roof, but the occlusion ray has to be able to hit
	# it, and a per-face collider would be cost for no behaviour.
	var b := state.bounds()
	_body = StaticBody3D.new()
	_body.position = Vector3(b.position.x + b.size.x * 0.5,
		state.base_y + state.height * 0.5, b.position.y + b.size.y * 0.5)
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = Vector3(b.size.x, maxf(state.height, 0.2), b.size.y)
	cs.shape = bs
	_body.add_child(cs)
	add_child(_body)


# ---------------------------------------------------------------- queries

func bodies() -> Array:
	return [_body] if _body != null else []


func face_count() -> int:
	return _plan.get("faces", []).size()


func ridge() -> Array:
	return _plan.get("ridge", [])


func style_name() -> String:
	return _plan.get("style", "-")


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
