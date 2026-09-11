class_name CozyStair
extends Node3D
## The GENERATED VIEW of a CozyStairState (doc #18 / #30).
##
## Two things this view exists to get right, both learned the hard way:
##
## 1. THE VISUAL IS STEPS, THE COLLIDER IS ONE SLOPE. Colliding against the step
##    boxes themselves makes CharacterBody3D catch on every riser; carrying the
##    collision on one hidden slope keeps it walkable while still looking like a
##    staircase.
##
## 2. THE RAMP'S TILTED COLLIDER IS A VERTICAL WALL FROM THE SIDE. A stair is
##    only enterable from its foot. That is a property of where the stair IS, so
##    it belongs to the state (start/end), not to this view.
##
## The steps are merged into one mesh — a stair is ~8 boxes, and one node each
## would be the draw-call-per-block problem doc #61 forbids.

var state: CozyStairState = null

var _mesh: MeshInstance3D = null
var _ramp: StaticBody3D = null
var _pieces: Array = []      ## {center, angle, size} for point tests


func setup_from(p_state: CozyStairState) -> void:
	state = p_state
	_rebuild()


func refresh() -> void:
	if is_inside_tree() and state != null:
		_rebuild()


func _rebuild() -> void:
	for c in get_children():
		c.queue_free()
	_mesh = null
	_ramp = null
	_pieces.clear()
	if state == null:
		return

	var d := state.end - state.start
	d.y = 0.0
	var length := maxf(d.length(), 0.001)
	var dir := d / length
	# The stair runs along its own +X; rotating +X about Y by theta gives
	# (cos t, 0, -sin t), so theta = atan2(-dz, dx).
	var yaw := atan2(-d.z, d.x)

	var rise := state.rise()
	var step_run := length / float(state.steps)
	var step_rise := rise / float(state.steps)

	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var mat := CozyMaterials.get_material(state.material_id, Vector3(length / 2.0, 1.0, 1.0))

	for i in state.steps:
		var top := float(i + 1) * step_rise
		var cx := (float(i) + 0.5) * step_run
		var center := state.start + dir * cx + Vector3(0.0, top * 0.5, 0.0)
		var size := Vector3(step_run, top, state.width)
		var shade := CozyArtSeed.range_f(state.seed_val ^ i, 0.94, 1.06)
		CozyWallAssembly.add_oriented_box(st, center, size, yaw,
			Color(shade, shade, shade, 1.0))

	_mesh = MeshInstance3D.new()
	_mesh.mesh = st.commit()
	_mesh.material_override = mat
	add_child(_mesh)

	# One hidden slope carries the collision. Its top edge lands exactly at the
	# stair head, so an agent arrives on level floor (doc #30's landing rule).
	#
	# The basis is built explicitly — tilt about Z, THEN yaw — rather than by
	# setting rotation.y alone. Setting only the yaw leaves a horizontal box: a
	# ceiling to walk under rather than a ramp to walk up, and the agent simply
	# never arrives. Steps above are correctly yaw-only, because they are
	# stacked boxes, not a tilted one.
	var ramp_len := sqrt(length * length + rise * rise)
	_ramp = StaticBody3D.new()
	_ramp.transform.basis = Basis(Vector3(0.0, 1.0, 0.0), yaw) \
		* Basis(Vector3(0.0, 0.0, 1.0), state.slope_angle())
	_ramp.position = state.start + dir * (length * 0.5) + Vector3(0.0, rise * 0.5, 0.0)
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = Vector3(ramp_len, 0.2, state.width)
	cs.shape = bs
	_ramp.add_child(cs)
	add_child(_ramp)

	_pieces.append({
		"center": _ramp.position,
		"angle": yaw,
		"size": Vector3(length, rise, state.width),
	})


# ---------------------------------------------------------------- queries

func bodies() -> Array:
	return [_ramp] if _ramp != null else []


func contains_point(p: Vector3) -> bool:
	for piece in _pieces:
		var c: Vector3 = piece["center"]
		var size: Vector3 = piece["size"]
		var ca := cos(float(piece["angle"]))
		var sa := sin(float(piece["angle"]))
		var rel := p - c
		var lx := rel.x * ca - rel.z * sa
		var lz := rel.x * sa + rel.z * ca
		if absf(lx) <= size.x * 0.5 + 0.0001 \
				and absf(rel.y) <= size.y * 0.5 + 0.0001 \
				and absf(lz) <= size.z * 0.5 + 0.0001:
			return true
	return false


## Stairs do not fade: an invisible staircase is worse than an occluded one.
func set_fade(_a: float) -> void:
	pass
