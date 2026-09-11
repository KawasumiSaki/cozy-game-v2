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
## A wall also generates its OWN geometry around any openings cut into it
## (#29 Door, #30 Window). A doorway is therefore a property of the wall rather
## than a gap the caller has to carve by splitting the wall into two segments.
##
## Every wall produces both Visual Geometry and Collision (doc #16).

## Shared by the wall and the build-mode preview so the two cannot drift apart.
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


var start := Vector3.ZERO
var end := Vector3.ZERO
var height := 3.0
var thickness := 0.25
var material_id := "wood"

## How far this wall runs past each end. Set by CozyWallSolver at junctions so
## corners close up (doc #24 / #25) instead of leaving a notched outer edge.
var extend_start := 0.0
var extend_end := 0.0

## Holes cut through this wall, measured from the original `start`.
var openings: Array[CozyOpening] = []

var _meshes: Array[MeshInstance3D] = []
var _bodies: Array[StaticBody3D] = []
var _pieces: Array = []          ## {center, angle, size} for point tests
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


func add_opening(o: CozyOpening) -> void:
	openings.append(o)
	if is_inside_tree():
		_rebuild()


func _rebuild() -> void:
	for c in get_children():
		c.queue_free()
	_meshes.clear()
	_bodies.clear()
	_pieces.clear()

	var seg := effective_segment()
	var a: Vector3 = seg[0]
	var b: Vector3 = seg[1]
	var base := segment_transform(a, b, height)
	var length: float = base["length"]
	var angle: float = base["angle"]

	# One material per wall, shared by every piece, so a single fade call covers
	# the whole wall including its sills and lintels.
	_mat = CozyMaterials.get_material(material_id,
		Vector3(maxf(length / 2.0, 1.0), maxf(height / 2.0, 1.0), 1.0))

	var flat := Vector3(b.x - a.x, 0.0, b.z - a.z)
	var dir := flat.normalized() if flat.length() > 0.0001 else Vector3.RIGHT

	# Openings are measured from the ORIGINAL start, so shift them into the
	# extended frame before laying pieces out.
	var shift := extend_start

	var sorted := openings.duplicate()
	sorted.sort_custom(func(x: CozyOpening, y: CozyOpening) -> bool: return x.offset < y.offset)

	var cursor := 0.0
	for o in sorted:
		var o0: float = clampf(o.offset + shift - o.width * 0.5, 0.0, length)
		var o1: float = clampf(o.offset + shift + o.width * 0.5, 0.0, length)
		if o1 <= o0:
			continue

		if o0 > cursor:
			_emit(a, dir, angle, cursor, o0, 0.0, height)          # wall before the hole
		if o.sill > 0.0001:
			_emit(a, dir, angle, o0, o1, 0.0, o.sill)              # sill under a window
		if o.head < height - 0.0001:
			_emit(a, dir, angle, o0, o1, o.head, height)           # lintel over the hole
		cursor = maxf(cursor, o1)                                  # a door leaves a gap

	if cursor < length:
		_emit(a, dir, angle, cursor, length, 0.0, height)          # wall after the hole

	if _pieces.is_empty():
		# Degenerate wall (e.g. entirely consumed by an opening) — nothing to draw.
		_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_mat.albedo_color = Color(1, 1, 1, 0)


## Emit one solid box covering distances d0..d1 along the wall and heights y0..y1.
func _emit(a: Vector3, dir: Vector3, angle: float,
		d0: float, d1: float, y0: float, y1: float) -> void:
	var w := d1 - d0
	var h := y1 - y0
	if w <= 0.0001 or h <= 0.0001:
		return

	var center := a + dir * ((d0 + d1) * 0.5) + Vector3(0.0, (y0 + y1) * 0.5, 0.0)
	var size := Vector3(w, h, thickness)

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

## The segment actually built, after junction extensions are applied.
func effective_segment() -> Array:
	var d := end - start
	d.y = 0.0
	var len := d.length()
	if len < 0.001:
		return [start, end]
	var dir := d / len
	return [start - dir * extend_start, end + dir * extend_end]


func bodies() -> Array[StaticBody3D]:
	return _bodies


## Rebuild geometry after extend_start / extend_end change.
func refresh() -> void:
	if is_inside_tree():
		_rebuild()


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


## Occlusion fade (doc #12.2): fade the wall when it blocks the player, rather
## than making the player disappear.
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
