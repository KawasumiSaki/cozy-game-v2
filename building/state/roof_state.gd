class_name CozyRoofState
extends RefCounted
## Pure data for one roof (doc #31 RoofGenerator, doc #18).
##
## The doc is firm that a roof is not a prefab placed on top:
##
##     "屋顶不能使用固定 Prefab 作为逻辑"
##
## Input is the room polygon plus a style; the geometry is derived. So the state
## stores what the roof IS — which room it caps, at what height, in what style —
## and never the mesh.

enum Style { FLAT, GABLE, HIP }

const STYLE_NAMES := {
	Style.FLAT: "flat",
	Style.GABLE: "gable",
	Style.HIP: "hip",
}

var id := ""
var room_id := ""
var floor_id := 0

## Footprint to cap, in the ground plane (x, z).
var polygon := PackedVector2Array()

## Elevation the roof sits on — normally the top floor's slab surface.
var base_y := 0.0

## How far the ridge rises above `base_y`.
var height := 1.6

var style: Style = Style.GABLE
var material_id := "brick"

## Eave overhang, metres beyond the wall line.
var overhang := 0.35

var seed_val := 0


static func create(p_id: String, p_room_id: String, p_polygon: PackedVector2Array,
		p_base_y: float, p_style := Style.GABLE, p_material := "brick",
		p_floor := 0) -> CozyRoofState:
	var r := CozyRoofState.new()
	r.id = p_id
	r.room_id = p_room_id
	r.polygon = p_polygon
	r.base_y = p_base_y
	r.style = p_style
	r.material_id = p_material
	r.floor_id = p_floor
	r.seed_val = hash(p_id)
	return r


func style_name() -> String:
	return STYLE_NAMES.get(style, "flat")


static func style_from_name(n: String) -> Style:
	match n.to_lower():
		"gable":
			return Style.GABLE
		"hip":
			return Style.HIP
		_:
			return Style.FLAT


func bounds() -> Rect2:
	if polygon.is_empty():
		return Rect2()
	var lo := polygon[0]
	var hi := polygon[0]
	for p in polygon:
		lo = Vector2(minf(lo.x, p.x), minf(lo.y, p.y))
		hi = Vector2(maxf(hi.x, p.x), maxf(hi.y, p.y))
	return Rect2(lo, hi - lo)


## A ridge line only exists if the footprint has one clear long axis. A square
## has none, and neither does an L — doc #31's hip style exists for those.
func is_rectangular() -> bool:
	if polygon.size() != 4:
		return false
	var b := bounds()
	return absf(CozyRoom.signed_area(polygon)) > 0.0001 \
		and absf(absf(CozyRoom.signed_area(polygon)) - b.size.x * b.size.y) < 0.05


func describe() -> String:
	return "%s [%s] over %s, base y=%.1f" % [id, style_name(), room_id, base_y]
