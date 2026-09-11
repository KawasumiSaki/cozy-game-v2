class_name CozyTerrainIntent
extends RefCounted
## Every land edit enters the system as an Intent (V2.1 doc #1.4 / #8).
##
## The doc's phrase is "Shape + Operation + Parameters + Target Material" — the
## same Intent-first rule the building system follows, applied to terrain. UI
## must not reach into cells any more than it may reach into a wall mesh.

enum Op {
	CLEAR,            ## Remove vegetation: Grass -> Soil, and the ground can be built on.
	PAINT_MATERIAL,   ## Set an explicit material.
	DIG,              ## Lower the surface.
	FILL,             ## Raise the surface.
	FLATTEN,          ## Level the area to its mean height.
}

enum Shape { POLYGON, CIRCLE, RECT }

var operation: Op = Op.CLEAR
var shape: Shape = Shape.POLYGON

## World-space geometry of the edit, in the ground plane (x, z).
var points: PackedVector2Array = PackedVector2Array()
var radius := 2.0
var rect := Rect2()

var material_id := "soil"
var depth := 0.5
var intensity := 1.0


# ---------------------------------------------------------------- constructors

## The doc's worked example (#10): draw a patch — a triangle in their telling,
## any polygon here — and clear it so building becomes possible.
static func clear_polygon(poly: PackedVector2Array) -> CozyTerrainIntent:
	var i := CozyTerrainIntent.new()
	i.operation = Op.CLEAR
	i.shape = Shape.POLYGON
	i.points = poly
	return i


static func dig_brush(center: Vector2, p_radius := 2.0,
		p_depth := 0.25) -> CozyTerrainIntent:
	var i := CozyTerrainIntent.new()
	i.operation = Op.DIG
	i.shape = Shape.CIRCLE
	i.points = PackedVector2Array([center])
	i.radius = p_radius
	i.depth = p_depth
	return i


static func fill_brush(center: Vector2, p_radius := 2.0,
		p_depth := 0.25) -> CozyTerrainIntent:
	var i := CozyTerrainIntent.new()
	i.operation = Op.FILL
	i.shape = Shape.CIRCLE
	i.points = PackedVector2Array([center])
	i.radius = p_radius
	i.depth = p_depth
	return i


static func clear_brush(center: Vector2, p_radius := 2.0) -> CozyTerrainIntent:
	var i := CozyTerrainIntent.new()
	i.operation = Op.CLEAR
	i.shape = Shape.CIRCLE
	i.points = PackedVector2Array([center])
	i.radius = p_radius
	return i


static func paint_polygon(poly: PackedVector2Array, p_material: String) -> CozyTerrainIntent:
	var i := CozyTerrainIntent.new()
	i.operation = Op.PAINT_MATERIAL
	i.shape = Shape.POLYGON
	i.points = poly
	i.material_id = p_material
	return i


static func dig_polygon(poly: PackedVector2Array, p_depth := 0.5) -> CozyTerrainIntent:
	var i := CozyTerrainIntent.new()
	i.operation = Op.DIG
	i.shape = Shape.POLYGON
	i.points = poly
	i.depth = p_depth
	return i


static func fill_polygon(poly: PackedVector2Array, p_depth := 0.5) -> CozyTerrainIntent:
	var i := CozyTerrainIntent.new()
	i.operation = Op.FILL
	i.shape = Shape.POLYGON
	i.points = poly
	i.depth = p_depth
	return i


# ---------------------------------------------------------------- helpers

func op_name() -> String:
	return ["clear", "paint", "dig", "fill", "flatten"][operation]


## Resolve the intent's shape into world-space cell centres.
func cells(cell_size: float, origin: Vector2) -> Array[Vector2]:
	match shape:
		Shape.CIRCLE:
			var c := points[0] if not points.is_empty() else Vector2.ZERO
			return CozyTerrainRaster.circle_cells(c, radius, cell_size, origin)
		Shape.RECT:
			return CozyTerrainRaster.rect_cells(rect, cell_size, origin)
		_:
			return CozyTerrainRaster.polygon_cells(points, cell_size, origin)


func describe() -> String:
	return "%s [%s] %d pt(s)" % [op_name(), Shape.keys()[shape], points.size()]
