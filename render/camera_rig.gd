class_name CozyCameraRig
extends Camera3D
## Orthographic camera rig (V2 doc #10.1).
##
## Why orthographic instead of perspective:
##   1. Distance never changes pixel size -> pixel art stays controllable
##   2. Building proportions stay uniform -> multi-floor is manageable
##   3. Reads closer to a classic isometric/top-down RPG
##
## AXIS CONVENTION (important):
##   The design doc records height as Z, but Godot is Y-up.
##   This project maps the doc's Z (height) onto Godot's +Y —
##   identical semantics (a floor IS a real elevation), different axis label.
##       doc(x, y, z)  ->  godot(x, z, y)

## Node the camera follows.
var target: Node3D = null

## How far back along the view axis the camera sits.
## Under orthographic projection this distance does not change framing,
## but it must be large: occlusion casts a ray from the camera to each
## character, and a camera sitting on top of them gives a zero-length ray.
const CAM_DISTANCE := 40.0

## Visible height in world metres (orthographic cameras zoom via `size`).
const ZOOM_STEPS: Array[float] = [6.0, 9.0, 12.0, 18.0, 26.0]
var _zoom_idx := 2

var pitch_deg := 55.0   ## Descending angle; higher = closer to straight top-down
var yaw_deg := 45.0     ## Horizontal rotation
var follow_speed := 6.0

const PITCH_MIN := 25.0
const PITCH_MAX := 88.0


func _ready() -> void:
	projection = PROJECTION_ORTHOGONAL
	size = ZOOM_STEPS[_zoom_idx]
	near = 0.1
	far = 400.0
	_apply_angles()


func _apply_angles() -> void:
	rotation_degrees = Vector3(-pitch_deg, yaw_deg, 0.0)


func _process(delta: float) -> void:
	if target and is_instance_valid(target):
		global_position = global_position.lerp(_desired_position(), clampf(follow_speed * delta, 0.0, 1.0))


## Ideal camera position = the target, pulled back along the camera's own view axis
## (local +Z) by CAM_DISTANCE.
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


func rotate_by(delta_deg: float) -> void:
	yaw_deg = fmod(yaw_deg + delta_deg, 360.0)
	_apply_angles()


func pitch_by(delta_deg: float) -> void:
	pitch_deg = clampf(pitch_deg + delta_deg, PITCH_MIN, PITCH_MAX)
	_apply_angles()


## Camera forward projected onto the ground plane (used to convert input to world space).
func ground_forward() -> Vector3:
	var yaw := deg_to_rad(yaw_deg)
	return Vector3(-sin(yaw), 0.0, -cos(yaw))


func ground_right() -> Vector3:
	var yaw := deg_to_rad(yaw_deg)
	return Vector3(cos(yaw), 0.0, -sin(yaw))
