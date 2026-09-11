class_name CozySlabState
extends RefCounted
## Pure data for one floor or ceiling slab.
##
## Doc #18 lists Floor alongside Wall as part of what BuildingState owns, and
## until now slabs were emitted straight into the scene — the last big piece of
## geometry that was not in the state. A roof generator cannot work without
## them: it has to know where the floors are before it can put anything on top.
##
## Collision is part of the state's meaning, not a rendering detail. A slab that
## is only drawn is a picture of a floor, and the player walks through it — a
## bug this project has already had once.

var id := ""
var center := Vector3.ZERO
var size := Vector3.ONE
var material_id := "stone"
var floor_id := 0

## Deterministic art seed (doc E.21), so a slab looks identical after a reload.
var seed_val := 0


static func create(p_id: String, p_center: Vector3, p_size: Vector3,
		p_material := "stone", p_floor := 0) -> CozySlabState:
	var s := CozySlabState.new()
	s.id = p_id
	s.center = p_center
	s.size = p_size
	s.material_id = p_material
	s.floor_id = p_floor
	s.seed_val = hash(p_id)
	return s


## The floor's walking surface — the top of the slab, which is what a character
## stands on and what a roof generator measures upward from.
func surface_y() -> float:
	return center.y + size.y * 0.5


func footprint() -> Rect2:
	return Rect2(center.x - size.x * 0.5, center.z - size.z * 0.5, size.x, size.z)


func volume() -> float:
	return size.x * size.y * size.z


func describe() -> String:
	return "%s (%.1fx%.1f at y=%.1f)" % [id, size.x, size.z, center.y]
