class_name CozyCameraRig
extends Camera3D
## Fixed orthographic camera (V2.1 doc E.1.1 / E.1.2).
##
## ROTATION IS LOCKED. The camera always views the world from one angle, and
## the player cannot rotate it. That is not a stylistic preference — doc E.1.1
## gives the reason:
##
##     "固定机位可以让我们为一个确定的观察方向制作像素资产，
##      从而显著降低植物、NPC、VFX 和环境装饰的生产成本，
##      同时提高 AI 生成资产的一致性。"
##
## In other words: one observation direction means every plant, prop and
## character sprite has to be authored for exactly one viewpoint. Let the camera
## spin and that cost multiplies by the number of angles.
##
## The camera still FOLLOWS its target — "fixed" means the angle is fixed, not
## that the view is bolted to one spot, or the player could not walk anywhere.
## Zoom keeps a few discrete steps, which the doc allows ("Zoom：有限档位").
##
## Free rotation survives as a DEBUG UNLOCK only (see `free_look`). It is off by
## default, and no production asset may ever be authored for an angle it
## produces.
##
## AXIS CONVENTION: the design doc records height as Z, but Godot is Y-up.
## This maps the doc's Z onto Godot's +Y — same meaning, different label:
##     doc(x, y, z)  ->  godot(x, z, y)

## The locked viewing angle. Chosen once, here, so nothing else can drift.
const FIXED_YAW := 45.0
const FIXED_PITCH := 52.0

## Node the camera follows.
var target: Node3D = null

## How far back along the view axis the camera sits. Under orthographic
## projection this does not change framing, but it must be large: occlusion
## casts a ray from the camera to each character, and a camera sitting on top of
## them gives a zero-length ray.
const CAM_DISTANCE := 40.0

## Visible height in world metres. A small set of steps — doc E.1.1 permits
## limited zoom, and a continuous zoom would invite framing that assets were
## never authored for.
const ZOOM_STEPS: Array[float] = [6.0, 9.0, 12.0, 18.0, 26.0]
var _zoom_idx := 2

## Debug escape hatch: allow free rotation for inspection.
##
## NOT a gameplay feature (doc E.1.1 forbids that). Anything you see at a
## non-locked angle is out of spec by definition, so do not author art from it.
var free_look := false

var yaw_deg := FIXED_YAW
var pitch_deg := FIXED_PITCH
var follow_speed := 6.0

const PITCH_MIN := 25.0
const PITCH_MAX := 88.0


func _ready() -> void:
	projection = PROJECTION_ORTHOGONAL
	size = ZOOM_STEPS[_zoom_idx]
	near = 0.1
	far = 400.0
	lock_view()


## Force the camera back to the locked angle.
func lock_view() -> void:
	free_look = false
	yaw_deg = FIXED_YAW
	pitch_deg = FIXED_PITCH
	_apply_angles()


func _apply_angles() -> void:
	rotation_degrees = Vector3(-pitch_deg, yaw_deg, 0.0)


func _process(delta: float) -> void:
	if target and is_instance_valid(target):
		global_position = global_position.lerp(_desired_position(), clampf(follow_speed * delta, 0.0, 1.0))


## Ideal camera position = the target, pulled back along the camera's own view
## axis (local +Z) by CAM_DISTANCE.
func _desired_position() -> Vector3:
	return target.global_position + global_transform.basis.z * CAM_DISTANCE


## Snap immediately to the target (used at startup so the camera does not fly in).
func snap_to_target() -> void:
	if target and is_instance_valid(target):
		global_position = _desired_position()


func zoom_in() -> void:
	_zoom_idx = maxi(0, _zoom_idx - 1)
	size = ZOOM_STEPS[_zoom_idx]


func zoom_out() -> void:
	_zoom_idx = mini(ZOOM_STEPS.size() - 1, _zoom_idx + 1)
	size = ZOOM_STEPS[_zoom_idx]


## Refused unless the debug unlock is on. Returns whether the angle moved, so
## the self-check can prove the lock holds.
func rotate_by(delta_deg: float) -> bool:
	if not free_look:
		return false
	yaw_deg = fmod(yaw_deg + delta_deg, 360.0)
	_apply_angles()
	return true


func pitch_by(delta_deg: float) -> bool:
	if not free_look:
		return false
	pitch_deg = clampf(pitch_deg + delta_deg, PITCH_MIN, PITCH_MAX)
	_apply_angles()
	return true


func is_locked() -> bool:
	return not free_look \
		and is_equal_approx(yaw_deg, FIXED_YAW) \
		and is_equal_approx(pitch_deg, FIXED_PITCH)


## Camera forward projected onto the ground plane (used to convert input to
## world space). Derived from the FIXED yaw, so movement is always relative to
## the one viewing direction.
func ground_forward() -> Vector3:
	var yaw := deg_to_rad(yaw_deg)
	return Vector3(-sin(yaw), 0.0, -cos(yaw))


func ground_right() -> Vector3:
	var yaw := deg_to_rad(yaw_deg)
	return Vector3(cos(yaw), 0.0, -sin(yaw))
