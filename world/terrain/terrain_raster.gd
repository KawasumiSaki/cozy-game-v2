class_name CozyTerrainRaster
extends RefCounted
## Turns an edit's SHAPE into the cells it covers (V2.1 doc #9).
##
## The doc is clear that the player works in continuous space — Vector3, polygon,
## spline — while the terrain simulates on a discrete grid:
##
##     Continuous World -> Terrain Rasterization -> FineGrid
##
## This is that conversion, and the only place either side needs to know about
## the other. Callers pass world-space geometry in; they get world-space cell
## CENTRES back, which they hand straight to the terrain system.


## Every cell whose centre falls inside the polygon.
## Works for triangles, rectangles and arbitrary polygons alike — the doc's
## "画三角形" case is not a special shape, it is just a 3-point polygon.
static func polygon_cells(poly: PackedVector2Array, cell_size: float,
		origin: Vector2) -> Array[Vector2]:
	var out: Array[Vector2] = []
	if poly.size() < 3:
		return out

	var lo := poly[0]
	var hi := poly[0]
	for p in poly:
		lo = Vector2(minf(lo.x, p.x), minf(lo.y, p.y))
		hi = Vector2(maxf(hi.x, p.x), maxf(hi.y, p.y))

	# Half a cell of slack so a centre exactly on the boundary is still tested.
	var gx0 := int(floor((lo.x - origin.x) / cell_size)) - 1
	var gx1 := int(ceil((hi.x - origin.x) / cell_size)) + 1
	var gz0 := int(floor((lo.y - origin.y) / cell_size)) - 1
	var gz1 := int(ceil((hi.y - origin.y) / cell_size)) + 1

	for gz in range(gz0, gz1 + 1):
		for gx in range(gx0, gx1 + 1):
			var c := origin + Vector2((float(gx) + 0.5) * cell_size,
				(float(gz) + 0.5) * cell_size)
			if point_in_polygon(c, poly):
				out.append(c)
	return out


## Every cell whose centre is within `radius` of `center` — the brush shape.
static func circle_cells(center: Vector2, radius: float, cell_size: float,
		origin: Vector2) -> Array[Vector2]:
	var out: Array[Vector2] = []
	var gx0 := int(floor((center.x - radius - origin.x) / cell_size)) - 1
	var gx1 := int(ceil((center.x + radius - origin.x) / cell_size)) + 1
	var gz0 := int(floor((center.y - radius - origin.y) / cell_size)) - 1
	var gz1 := int(ceil((center.y + radius - origin.y) / cell_size)) + 1
	var r2 := radius * radius

	for gz in range(gz0, gz1 + 1):
		for gx in range(gx0, gx1 + 1):
			var c := origin + Vector2((float(gx) + 0.5) * cell_size,
				(float(gz) + 0.5) * cell_size)
			if c.distance_squared_to(center) <= r2:
				out.append(c)
	return out


## Every cell whose centre falls inside the axis-aligned rectangle.
static func rect_cells(rect: Rect2, cell_size: float,
		origin: Vector2) -> Array[Vector2]:
	var poly := PackedVector2Array([
		rect.position,
		rect.position + Vector2(rect.size.x, 0.0),
		rect.position + rect.size,
		rect.position + Vector2(0.0, rect.size.y),
	])
	return polygon_cells(poly, cell_size, origin)


## Ray casting. The polygon's last vertex wraps to its first.
static func point_in_polygon(p: Vector2, poly: PackedVector2Array) -> bool:
	var n := poly.size()
	if n < 3:
		return false
	var inside := false
	var j := n - 1
	for i in n:
		var a := poly[i]
		var b := poly[j]
		if ((a.y > p.y) != (b.y > p.y)) \
				and (p.x < (b.x - a.x) * (p.y - a.y) / (b.y - a.y) + a.x):
			inside = not inside
		j = i
	return inside
