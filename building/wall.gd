class_name CozyWall
extends Node3D
## The GENERATED VIEW of a CozyWallState (V2.1 doc #18).
##
## This node holds no authoritative data. Everything it draws comes from
## `state`, and it can be destroyed and rebuilt at any time without losing
## anything — which is the entire point of separating State from Mesh:
##
##     doc #18 — "BuildingState 是唯一真相。删除 Mesh 不会删除建筑逻辑。"
##
## A wall generates its own geometry around any openings cut into it
## (doc #24): a door reaches the floor and leaves a walkable gap plus a lintel
## above; a window leaves a solid sill below, which is what stops an agent
## walking through it. Neither needs special-casing anywhere else.

var state: CozyWallState = null

var _meshes: Array[MeshInstance3D] = []
var _bodies: Array[StaticBody3D] = []
var _pieces: Array = []          ## {center, angle, size} for point tests
var _mat: StandardMaterial3D = null
var _fade := 1.0


func setup_from(p_state: CozyWallState) -> void:
	state = p_state
	_rebuild()


## Rebuild geometry from the current state (doc #18: meshes are always derived).
func refresh() -> void:
	if is_inside_tree() and state != null:
		_rebuild()


func _rebuild() -> void:
	for c in get_children():
		c.queue_free()
	_meshes.clear()
	_bodies.clear()
	_pieces.clear()

	if state == null:
		return

	var seg := state.effective_segment()
	var a: Vector3 = seg[0]
	var b: Vector3 = seg[1]
	var t := CozyWallState.segment_transform(a, b, state.height)
	var length: float = t["length"]
	var angle: float = t["angle"]

	# One material per wall, shared by every piece, so a single fade call covers
	# the whole wall including its sills and lintels.
	_mat = CozyMaterials.get_material(state.material_id,
		Vector3(maxf(length / 2.0, 1.0), maxf(state.height / 2.0, 1.0), 1.0))

	var flat := Vector3(b.x - a.x, 0.0, b.z - a.z)
	var dir := flat.normalized() if flat.length() > 0.0001 else Vector3.RIGHT

	# Openings are measured from the ORIGINAL start, so shift them into the
	# extended frame before laying pieces out.
	var shift := state.extend_start

	var sorted := state.openings.duplicate()
	sorted.sort_custom(func(x: CozyOpening, y: CozyOpening) -> bool: return x.offset < y.offset)

	var cursor := 0.0
	for o in sorted:
		var o0: float = clampf(o.offset + shift - o.width * 0.5, 0.0, length)
		var o1: float = clampf(o.offset + shift + o.width * 0.5, 0.0, length)
		if o1 <= o0:
			continue

		if o0 > cursor:
			_emit(a, dir, angle, cursor, o0, 0.0, state.height)   # wall before the hole
		if o.sill > 0.0001:
			_emit(a, dir, angle, o0, o1, 0.0, o.sill)             # sill under a window
		if o.head < state.height - 0.0001:
			_emit(a, dir, angle, o0, o1, o.head, state.height)    # lintel over the hole
		cursor = maxf(cursor, o1)                                 # a door leaves a gap

	if cursor < length:
		_emit(a, dir, angle, cursor, length, 0.0, state.height)   # wall after the hole


## Emit one solid box covering distances d0..d1 along the wall and heights y0..y1.
func _emit(a: Vector3, dir: Vector3, angle: float,
		d0: float, d1: float, y0: float, y1: float) -> void:
	var w := d1 - d0
	var h := y1 - y0
	if w <= 0.0001 or h <= 0.0001:
		return

	var center := a + dir * ((d0 + d1) * 0.5) + Vector3(0.0, (y0 + y1) * 0.5, 0.0)
	var size := Vector3(w, h, state.thickness)

	var bm := BoxMesh.new()
	bm.size = size
	var mi := MeshInstance3D.new()
	mi.mesh = bm
	mi.material_override = _mat
	mi.position = center
	mi.rotation.y = angle
	add_child(mi)
	_meshes.append(mi)

	var body := StaticBody3D.new()
	body.position = center
	body.rotation.y = angle
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = size
	cs.shape = bs
	body.add_child(cs)
	add_child(body)
	_bodies.append(body)

	_pieces.append({"center": center, "angle": angle, "size": size})


# ---------------------------------------------------------------- queries

func bodies() -> Array[StaticBody3D]:
	return _bodies


## Is this world point inside any of the wall's solid pieces?
func contains_point(p: Vector3) -> bool:
	for piece in _pieces:
		if _piece_contains(piece, p):
			return true
	return false


static func _piece_contains(piece: Dictionary, p: Vector3) -> bool:
	var c: Vector3 = piece["center"]
	var size: Vector3 = piece["size"]
	var ca := cos(float(piece["angle"]))
	var sa := sin(float(piece["angle"]))
	# Undo the Y rotation to land in the piece's local frame.
	var rel := p - c
	var lx := rel.x * ca - rel.z * sa
	var lz := rel.x * sa + rel.z * ca
	return absf(lx) <= size.x * 0.5 + 0.0001 \
		and absf(rel.y) <= size.y * 0.5 + 0.0001 \
		and absf(lz) <= size.z * 0.5 + 0.0001


## Occlusion fade (doc #57): fade the wall when it blocks the player, rather
## than making the player disappear or hiding the whole building.
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
