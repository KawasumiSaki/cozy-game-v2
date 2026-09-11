class_name CozyWallAssembly
extends RefCounted
## Procedural wall assembly (V2.1 doc 58.3 Layer 3 / E.16 / E.49).
##
## The doc's rule for surfaces is: do NOT author a model per wall.
##
##     "4m / 8m / 12m 的墙可以保持统一风格而不必准备 3 套完整模型"
##
## So a wall is built by arranging atomic blocks. Two things matter here.
##
## 1. The arrangement is DETERMINISTIC (doc E.21). The same wall state must
##    produce the same blocks after a save and reload, so shading comes from a
##    hash of the wall's own seed and the block's grid position — never from a
##    random source. "昨天这棵树在左边，今天跑到右边" is the failure the doc
##    names.
##
## 2. The blocks become ONE merged mesh, not one node each. Doc #61 forbids
##    "10000 objects = 10000 draw calls", and an 8 m stone wall is already ~75
##    blocks at its coursing. This is why the assembler appends into a
##    SurfaceTool rather than returning nodes.

## Peak-to-peak brightness variation across blocks, as a fraction of albedo.
const SHADE_RANGE := 0.14

## Blocks thinner than this in either axis are dropped rather than emitted as
## slivers — a running-bond course leaves a clipped block at each end, and a
## 2 cm sliver reads as an artefact rather than as masonry.
const MIN_BLOCK := 0.02


## Split one solid span of wall into blocks. Distances are along the wall from
## `d0` to `d1`, heights from `y0` to `y1`.
##
## Returns [{d0, d1, y0, y1, shade}] — geometry-neutral, so the self-check can
## assert on the layout without touching a mesh.
static func blocks_for_span(d0: float, d1: float, y0: float, y1: float,
		block_len: float, block_h: float, seed_val: int) -> Array:
	var out: Array = []
	if d1 - d0 <= MIN_BLOCK or y1 - y0 <= MIN_BLOCK:
		return out

	block_len = maxf(block_len, 0.05)
	block_h = maxf(block_h, 0.05)

	var rows := int(ceil((y1 - y0) / block_h))
	for r in rows:
		var ry0 := y0 + float(r) * block_h
		var ry1 := minf(ry0 + block_h, y1)
		if ry1 - ry0 <= MIN_BLOCK:
			continue

		# Running bond: every other course is offset half a block, which is what
		# makes a wall read as masonry rather than as a grid.
		var offset := (block_len * 0.5) if (r % 2 == 1) else 0.0
		var d := d0 - offset
		var col := 0
		while d < d1 - MIN_BLOCK:
			var bx0 := maxf(d, d0)
			var bx1 := minf(d + block_len, d1)
			if bx1 - bx0 > MIN_BLOCK:
				out.append({
					"d0": bx0, "d1": bx1, "y0": ry0, "y1": ry1,
					"shade": shade_for(seed_val, r, col),
				})
			d += block_len
			col += 1
	return out


## Deterministic brightness multiplier for one block (doc E.21).
## Identical inputs must always give an identical value, across runs and across
## save/load, which rules out any global RNG.
static func shade_for(seed_val: int, row: int, col: int) -> float:
	var h := absi(hash(Vector3i(seed_val, row, col)))
	var n := float(h % 1000) / 1000.0
	return 1.0 + (n - 0.5) * SHADE_RANGE


## Append an axis-aligned box, rotated about Y and moved to `center`, into a
## SurfaceTool. Winding is counter-clockwise when viewed from outside so the
## faces are front-facing; normals are supplied per face.
static func add_oriented_box(st: SurfaceTool, center: Vector3, size: Vector3,
		rot_y: float, color: Color) -> void:
	var hx := size.x * 0.5
	var hy := size.y * 0.5
	var hz := size.z * 0.5
	var ca := cos(rot_y)
	var sa := sin(rot_y)

	# Local corner -> world: rotate about Y, then translate.
	var r := func(p: Vector3) -> Vector3:
		return Vector3(p.x * ca + p.z * sa, p.y, -p.x * sa + p.z * ca) + center

	var p000: Vector3 = r.call(Vector3(-hx, -hy, -hz))
	var p100: Vector3 = r.call(Vector3(hx, -hy, -hz))
	var p110: Vector3 = r.call(Vector3(hx, hy, -hz))
	var p010: Vector3 = r.call(Vector3(-hx, hy, -hz))
	var p001: Vector3 = r.call(Vector3(-hx, -hy, hz))
	var p101: Vector3 = r.call(Vector3(hx, -hy, hz))
	var p111: Vector3 = r.call(Vector3(hx, hy, hz))
	var p011: Vector3 = r.call(Vector3(-hx, hy, hz))

	var nx := Vector3(ca, 0.0, -sa)     # local +X after rotation
	var nz := Vector3(sa, 0.0, ca)      # local +Z after rotation

	_quad(st, p001, p101, p111, p011, nz, color)      # +Z
	_quad(st, p100, p000, p010, p110, -nz, color)     # -Z
	_quad(st, p101, p100, p110, p111, nx, color)      # +X
	_quad(st, p000, p001, p011, p010, -nx, color)     # -X
	_quad(st, p010, p011, p111, p110, Vector3.UP, color)     # +Y
	_quad(st, p000, p100, p101, p001, Vector3.DOWN, color)   # -Y


static func _quad(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3,
		d: Vector3, n: Vector3, color: Color) -> void:
	for v in [a, b, c, a, c, d]:
		st.set_normal(n)
		st.set_color(color)
		st.add_vertex(v)
