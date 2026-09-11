class_name CozyOcclusion
extends Node3D
## Occlusion fade (V2 doc #12 / #12.2 Interior Fade).
##
## Buildings block the player. Rendered naively, walking indoors makes
## the player simply disappear. The fix is NOT to hide the whole house
## (the doc explicitly rejects that shortcut). Instead:
##
##     cast camera -> character; whichever wall blocks the line of sight
##     fades out, and only that wall.
##
## The player stays visible and the building keeps its structure.

var camera: Camera3D = null
var targets: Array = []   ## Characters that must stay visible
var walls: Array = []     ## Fadeable walls (each needs a static_body)

const FADE_ALPHA := 0.22
const AIM_HEIGHT := 1.0   ## Aim at chest height, not at the feet


func _process(_delta: float) -> void:
	if camera == null or not camera.is_inside_tree():
		return

	var blocked := {}
	var space := camera.get_world_3d().direct_space_state

	for t in targets:
		if not is_instance_valid(t):
			continue
		var from: Vector3 = camera.global_position
		var to: Vector3 = t.global_position + Vector3(0.0, AIM_HEIGHT, 0.0)
		var q := PhysicsRayQueryParameters3D.create(from, to)
		q.collide_with_areas = false
		var hit := space.intersect_ray(q)
		if hit and hit.has("collider"):
			blocked[hit["collider"]] = true

	for w in walls:
		if not is_instance_valid(w) or w.static_body == null:
			continue
		w.set_fade(FADE_ALPHA if blocked.has(w.static_body) else 1.0)
