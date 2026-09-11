class_name CozyRoofGenerator
extends RefCounted
## Roof geometry derived from a room's footprint (V2.1 doc #31).
##
## Doc #31: "屋顶不能使用固定 Prefab 作为逻辑". Input is the room polygon,
## the elevation and a style; the ridge, slopes and gables are worked out from
## them. Change the room and the roof follows.
##
## Supports the three styles the doc lists for the first version — FLAT, GABLE,
## HIP — over a RECTANGULAR footprint. Non-rectangular footprints fall back to
## flat, because a proper gable over an L needs ridge-line decomposition that is
## its own block. The fallback is reported rather than silently applied.
##
## Output is a plan (faces + ridge), not a mesh. The view turns it into geometry,
## so the layout can be asserted without building anything.

## Thickness of a flat roof slab, metres.
const FLAT_THICKNESS := 0.25

## How far a hip ridge is inset from each gable end, as a fraction of the
## shorter footprint dimension. 0 would make it a gable; 0.5 would make it a
## pyramid.
const HIP_INSET_FRACTION := 0.5


## Returns { style, faces: [{verts: Array[Vector3], shade: float}], ridge: Array }.
static func plan(state: CozyRoofState) -> Dictionary:
	var b := state.bounds()
	if b.size.x <= 0.001 or b.size.y <= 0.001:
		return {"style": "flat", "faces": [], "ridge": []}

	# Overhang the eaves beyond the wall line (doc #31: 屋檐).
	b = Rect2(b.position - Vector2(state.overhang, state.overhang),
		b.size + Vector2(state.overhang * 2.0, state.overhang * 2.0))

	var style := state.style
	if style != CozyRoofState.Style.FLAT and not state.is_rectangular():
		# Ridge-based styles need one clear long axis. Say so rather than
		# quietly building something that does not fit.
		style = CozyRoofState.Style.FLAT

	match style:
		CozyRoofState.Style.GABLE:
			return _gable(state, b)
		CozyRoofState.Style.HIP:
			return _hip(state, b)
		_:
			return _flat(state, b)


# ---------------------------------------------------------------- styles

static func _flat(state: CozyRoofState, b: Rect2) -> Dictionary:
	var y := state.base_y
	var t := FLAT_THICKNESS
	# A flat roof is a slab, so it is emitted as a box rather than a face list.
	return {
		"style": "flat",
		"box": {
			"center": Vector3(b.position.x + b.size.x * 0.5, y + t * 0.5,
				b.position.y + b.size.y * 0.5),
			"size": Vector3(b.size.x, t, b.size.y),
		},
		"faces": [],
		"ridge": [],
	}


static func _gable(state: CozyRoofState, b: Rect2) -> Dictionary:
	var x0 := b.position.x
	var x1 := b.position.x + b.size.x
	var z0 := b.position.y
	var z1 := b.position.y + b.size.y
	var eave := state.base_y
	var peak := state.base_y + state.height

	# The ridge runs along the longer axis, so the slope is always the gentle one.
	var along_x := b.size.x >= b.size.y
	var faces: Array = []
	var ridge: Array = []

	if along_x:
		var mz := (z0 + z1) * 0.5
		ridge = [Vector3(x0, peak, mz), Vector3(x1, peak, mz)]
		faces.append({"verts": [Vector3(x0, eave, z0), Vector3(x1, eave, z0),
			Vector3(x1, peak, mz), Vector3(x0, peak, mz)], "shade": 0.92})
		faces.append({"verts": [Vector3(x1, eave, z1), Vector3(x0, eave, z1),
			Vector3(x0, peak, mz), Vector3(x1, peak, mz)], "shade": 1.06})
		# Gable ends close the triangle between the two slopes.
		faces.append({"verts": [Vector3(x0, eave, z1), Vector3(x0, eave, z0),
			Vector3(x0, peak, mz)], "shade": 0.84})
		faces.append({"verts": [Vector3(x1, eave, z0), Vector3(x1, eave, z1),
			Vector3(x1, peak, mz)], "shade": 0.84})
	else:
		var mx := (x0 + x1) * 0.5
		ridge = [Vector3(mx, peak, z0), Vector3(mx, peak, z1)]
		faces.append({"verts": [Vector3(x1, eave, z0), Vector3(x1, eave, z1),
			Vector3(mx, peak, z1), Vector3(mx, peak, z0)], "shade": 0.92})
		faces.append({"verts": [Vector3(x0, eave, z1), Vector3(x0, eave, z0),
			Vector3(mx, peak, z0), Vector3(mx, peak, z1)], "shade": 1.06})
		faces.append({"verts": [Vector3(x0, eave, z0), Vector3(x1, eave, z0),
			Vector3(mx, peak, z0)], "shade": 0.84})
		faces.append({"verts": [Vector3(x1, eave, z1), Vector3(x0, eave, z1),
			Vector3(mx, peak, z1)], "shade": 0.84})

	return {"style": "gable", "faces": faces, "ridge": ridge}


static func _hip(state: CozyRoofState, b: Rect2) -> Dictionary:
	var x0 := b.position.x
	var x1 := b.position.x + b.size.x
	var z0 := b.position.y
	var z1 := b.position.y + b.size.y
	var eave := state.base_y
	var peak := state.base_y + state.height

	var along_x := b.size.x >= b.size.y
	var faces: Array = []
	var ridge: Array = []

	if along_x:
		var mz := (z0 + z1) * 0.5
		var inset := b.size.y * HIP_INSET_FRACTION
		var rx0 := x0 + inset
		var rx1 := x1 - inset
		if rx1 <= rx0:
			rx0 = (x0 + x1) * 0.5
			rx1 = rx0
		ridge = [Vector3(rx0, peak, mz), Vector3(rx1, peak, mz)]
		# Two trapezoid slopes along the long sides.
		faces.append({"verts": [Vector3(x0, eave, z0), Vector3(x1, eave, z0),
			Vector3(rx1, peak, mz), Vector3(rx0, peak, mz)], "shade": 0.92})
		faces.append({"verts": [Vector3(x1, eave, z1), Vector3(x0, eave, z1),
			Vector3(rx0, peak, mz), Vector3(rx1, peak, mz)], "shade": 1.06})
		# Two triangular ends, sloping inward instead of rising vertically —
		# which is the whole difference between a hip and a gable.
		faces.append({"verts": [Vector3(x0, eave, z1), Vector3(x0, eave, z0),
			Vector3(rx0, peak, mz)], "shade": 0.86})
		faces.append({"verts": [Vector3(x1, eave, z0), Vector3(x1, eave, z1),
			Vector3(rx1, peak, mz)], "shade": 0.86})
	else:
		var mx := (x0 + x1) * 0.5
		var inset2 := b.size.x * HIP_INSET_FRACTION
		var rz0 := z0 + inset2
		var rz1 := z1 - inset2
		if rz1 <= rz0:
			rz0 = (z0 + z1) * 0.5
			rz1 = rz0
		ridge = [Vector3(mx, peak, rz0), Vector3(mx, peak, rz1)]
		faces.append({"verts": [Vector3(x1, eave, z0), Vector3(x1, eave, z1),
			Vector3(mx, peak, rz1), Vector3(mx, peak, rz0)], "shade": 0.92})
		faces.append({"verts": [Vector3(x0, eave, z1), Vector3(x0, eave, z0),
			Vector3(mx, peak, rz0), Vector3(mx, peak, rz1)], "shade": 1.06})
		faces.append({"verts": [Vector3(x0, eave, z0), Vector3(x1, eave, z0),
			Vector3(mx, peak, rz0)], "shade": 0.86})
		faces.append({"verts": [Vector3(x1, eave, z1), Vector3(x0, eave, z1),
			Vector3(mx, peak, rz1)], "shade": 0.86})

	return {"style": "hip", "faces": faces, "ridge": ridge}


## Emit a plan's faces into a SurfaceTool, shading each by its own factor so the
## slopes read apart without needing a texture per face.
static func emit(st: SurfaceTool, plan: Dictionary) -> void:
	for f in plan.get("faces", []):
		var verts: Array = f["verts"]
		var shade := float(f["shade"])
		var col := Color(shade, shade, shade, 1.0)
		if verts.size() == 3:
			_tri(st, verts[0], verts[1], verts[2], col)
		else:
			var n := _face_normal(verts[0], verts[1], verts[2])
			_quad(st, verts[0], verts[1], verts[2], verts[3], n, col)


static func _tri(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, col: Color) -> void:
	var n := _face_normal(a, b, c)
	for v in [a, b, c]:
		st.set_normal(n)
		st.set_color(col)
		st.add_vertex(v)


static func _quad(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3,
		n: Vector3, col: Color) -> void:
	for v in [a, b, c, a, c, d]:
		st.set_normal(n)
		st.set_color(col)
		st.add_vertex(v)


static func _face_normal(a: Vector3, b: Vector3, c: Vector3) -> Vector3:
	var n := (b - a).cross(c - a)
	return n.normalized() if n.length() > 0.00001 else Vector3.UP
