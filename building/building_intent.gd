class_name CozyBuildingIntent
extends RefCounted
## Every player edit enters the system as an Intent (V2.1 doc #1.4).
##
## The rule is absolute — UI must never touch a mesh. The chain is always:
##
##     Player Input -> Intent -> State Mutation -> Spatial / Rule Analysis
##                  -> Generator -> Runtime World
##
## Appendix C of the doc lists "UI directly edits Mesh" as a forbidden pattern,
## and the existing drag-to-place prototype is explicitly only a test tool until
## it goes through here (doc #75, Phase 3).

enum Kind { DRAW_WALL, REMOVE_WALL, ADD_OPENING, ADD_SLAB, ADD_STAIR, ADD_ROOF }

var kind: Kind = Kind.DRAW_WALL

## DRAW_WALL / ADD_OPENING targets
var a := Vector3.ZERO
var b := Vector3.ZERO
var wall_id := ""
var opening: CozyOpening = null

## DRAW_WALL / ADD_SLAB parameters
var height := 3.0
var thickness := 0.25
var material_id := "wood"
var floor_id := 0

## ADD_SLAB / ADD_STAIR / ADD_ROOF parameters
var size := Vector3.ONE
var width := 3.0
var room_id := ""
var polygon := PackedVector2Array()
var roof_style := CozyRoofState.Style.GABLE

## Openings to cut into the wall as it is created. Carried on the intent so a
## wall and its doorway are one atomic edit — the wall's id does not exist until
## the state accepts it, so a separate ADD_OPENING pass would need the id first.
var openings: Array[CozyOpening] = []


func with_opening(o: CozyOpening) -> CozyBuildingIntent:
	openings.append(o)
	return self


static func draw_wall(p_a: Vector3, p_b: Vector3, p_height := 3.0,
		p_thickness := 0.25, p_material := "wood", p_floor := 0) -> CozyBuildingIntent:
	var i := CozyBuildingIntent.new()
	i.kind = Kind.DRAW_WALL
	i.a = p_a
	i.b = p_b
	i.height = p_height
	i.thickness = p_thickness
	i.material_id = p_material
	i.floor_id = p_floor
	return i


static func remove_wall(p_wall_id: String) -> CozyBuildingIntent:
	var i := CozyBuildingIntent.new()
	i.kind = Kind.REMOVE_WALL
	i.wall_id = p_wall_id
	return i


## A floor or ceiling slab. `a` is its centre, `size` its extents.
static func add_slab(p_center: Vector3, p_size: Vector3, p_material := "stone",
		p_floor := 0) -> CozyBuildingIntent:
	var i := CozyBuildingIntent.new()
	i.kind = Kind.ADD_SLAB
	i.a = p_center
	i.size = p_size
	i.material_id = p_material
	i.floor_id = p_floor
	return i


## A staircase from `a` (foot) to `b` (head, at the upper floor's level).
static func add_stair(p_start: Vector3, p_end: Vector3, p_width := 3.0,
		p_material := "wood") -> CozyBuildingIntent:
	var i := CozyBuildingIntent.new()
	i.kind = Kind.ADD_STAIR
	i.a = p_start
	i.b = p_end
	i.width = p_width
	i.material_id = p_material
	return i


## A roof over a room's footprint (doc #31). The generator derives the ridge
## and slopes from `polygon`, so nothing here is a placed prefab.
static func add_roof(p_room_id: String, p_polygon: PackedVector2Array,
		p_base_y: float, p_style := CozyRoofState.Style.GABLE,
		p_material := "brick", p_floor := 0) -> CozyBuildingIntent:
	var i := CozyBuildingIntent.new()
	i.kind = Kind.ADD_ROOF
	i.room_id = p_room_id
	i.polygon = p_polygon
	i.a = Vector3(0.0, p_base_y, 0.0)
	i.roof_style = p_style
	i.material_id = p_material
	i.floor_id = p_floor
	return i


static func add_opening(p_wall_id: String, p_opening: CozyOpening) -> CozyBuildingIntent:
	var i := CozyBuildingIntent.new()
	i.kind = Kind.ADD_OPENING
	i.wall_id = p_wall_id
	i.opening = p_opening
	return i


func describe() -> String:
	match kind:
		Kind.DRAW_WALL:
			return "DRAW_WALL %s -> %s" % [a, b]
		Kind.REMOVE_WALL:
			return "REMOVE_WALL %s" % wall_id
		Kind.ADD_OPENING:
			return "ADD_OPENING %s %s" % [wall_id, opening.describe() if opening else "-"]
	return "INTENT"
