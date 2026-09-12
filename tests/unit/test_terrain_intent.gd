extends "res://tests/unit/unit_test.gd"
## Land edit intents: the operation vocabulary, and the shapes they resolve to.
##
## Structural properties only — "a bigger brush covers more ground" and "every
## cell a rect reports is inside that rect". Pinning exact cell counts would make
## this a test of the rasteriser's rounding rather than of the intent.

const CELL := 0.25
const ORIGIN := Vector2.ZERO


func _init() -> void:
	suite("terrain intent")
	case("every operation names itself", _op_names)
	case("the constructors set what they promise", _constructors)
	case("a rect covers only itself", _rect_cells)
	case("a bigger brush covers more ground", _circle_scales)
	case("a circle stays inside its radius", _circle_bounded)
	case("an empty intent resolves to nothing", _empty)


func _op_names() -> void:
	var ops: Array = [
		CozyTerrainIntent.Op.CLEAR, CozyTerrainIntent.Op.PAINT_MATERIAL,
		CozyTerrainIntent.Op.DIG, CozyTerrainIntent.Op.FILL,
		CozyTerrainIntent.Op.FLATTEN, CozyTerrainIntent.Op.TILL,
	]
	for op in ops:
		var i := CozyTerrainIntent.new()
		i.operation = op
		ne("op %d has a name" % op, i.op_name(), "")
	eq("TILL names itself", CozyTerrainIntent.till_brush(Vector2.ZERO).op_name(), "till")


func _constructors() -> void:
	var t := CozyTerrainIntent.till_brush(Vector2(4.0, 4.0), 3.0)
	eq("till is a TILL", t.operation, CozyTerrainIntent.Op.TILL)
	eq("till is a circle", t.shape, CozyTerrainIntent.Shape.CIRCLE)
	near("till keeps its radius", t.radius, 3.0)
	# Tilling is a MATERIAL edit, not a height edit. A depth here would be the
	# first step towards elevation editing, which is explicitly out of scope.
	near("till does not touch height", t.depth, CozyTerrainIntent.new().depth)
	eq("clear is a CLEAR", CozyTerrainIntent.clear_brush(Vector2.ZERO).operation,
		CozyTerrainIntent.Op.CLEAR)
	eq("dig keeps its depth", CozyTerrainIntent.dig_brush(Vector2.ZERO, 2.0, 0.5).depth, 0.5)


func _rect_cells() -> void:
	var r := Rect2(2.0, 2.0, 4.0, 4.0)
	var i := CozyTerrainIntent.new()
	i.shape = CozyTerrainIntent.Shape.RECT
	i.rect = r
	var cells := i.cells(CELL, ORIGIN)
	is_true("a 4x4 rect covers some ground", cells.size() > 0)
	for c in cells:
		is_true("cell (%.2f, %.2f) is inside the rect" % [c.x, c.y], r.has_point(c))


func _circle_scales() -> void:
	var small := CozyTerrainIntent.clear_brush(Vector2(8.0, 8.0), 1.0).cells(CELL, ORIGIN)
	var big := CozyTerrainIntent.clear_brush(Vector2(8.0, 8.0), 3.0).cells(CELL, ORIGIN)
	is_true("a 3 m brush beats a 1 m brush (%d vs %d)" % [big.size(), small.size()],
		big.size() > small.size())


func _circle_bounded() -> void:
	var centre := Vector2(8.0, 8.0)
	var radius := 2.0
	var cells := CozyTerrainIntent.clear_brush(centre, radius).cells(CELL, ORIGIN)
	is_true("the brush covers some ground", cells.size() > 0)
	# One cell of slack: a cell whose CENTRE is just outside can still be struck.
	for c in cells:
		is_true("cell (%.2f, %.2f) is within the brush" % [c.x, c.y],
			c.distance_to(centre) <= radius + CELL)


func _empty() -> void:
	var i := CozyTerrainIntent.new()
	i.shape = CozyTerrainIntent.Shape.POLYGON
	eq("a polygon with no points resolves to no cells",
		i.cells(CELL, ORIGIN).size(), 0)
	ne("and it still describes itself", i.describe(), "")
