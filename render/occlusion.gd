class_name CozyOcclusion
extends Node3D
## Occlusion fade (V2.1 doc #57).
##
## Buildings block the player. Rendered naively, walking indoors makes the
## player simply disappear. The fix is NOT to hide the whole house — the doc
## rejects that — but to fade only the geometry that actually blocks the line
## of sight:
##
##     Camera -> Player Raycast -> Blocking Geometry -> Fade only those
##
## TWO RULES, and the second one was learned the hard way:
##
##   1. Only fade what blocks the FOLLOWED character. The camera follows the
##      player, so the player is the one who must never be hidden.
##   2. Do NOT fade on behalf of a character you are not following. See
##      `watch_non_followed` below.

var camera: Camera3D = null

## Characters whose line of sight must stay clear. In practice: the one the
## camera follows.
var targets: Array = []

var fadables: Array = []   ## Anything exposing bodies() + set_fade()

## Fade geometry that blocks the OTHER characters too (NPCs).
##
## This defaults to FALSE, and that default is deliberate. With it on, a
## stationary NPC standing indoors makes the camera fade the house from
## outside: the ray to the NPC crosses the south wall and the roof, so the
## whole building turns to glass while the player is standing in the open with
## nothing in front of them. The house looks broken, and nothing is actually
## blocking the player.
##
## Turn it on only for a deliberate x-ray view.
var watch_non_followed := false

const FADE_ALPHA := 0.22
const AIM_HEIGHT := 1.0   ## Aim at chest height, not at the feet

## Diagnostics: which target's line of sight each faded object is blocking.
## Read by the self-check so the cause is measured rather than guessed.
var _faded_by: Dictionary = {}


func _process(_delta: float) -> void:
	if camera == null or not camera.is_inside_tree():
		return

	var watched: Array = []
	if targets.size() > 0:
		watched.append(targets[0])          # The followed character — always.
	if watch_non_followed:
		for i in range(1, targets.size()):
			watched.append(targets[i])

	var blocked := {}      # collider -> true
	var cause := {}        # collider -> index into `watched`

	for i in watched.size():
		var t = watched[i]
		if not is_instance_valid(t):
			continue
		var from: Vector3 = camera.global_position
		var to: Vector3 = t.global_position + Vector3(0.0, AIM_HEIGHT, 0.0)
		var q := PhysicsRayQueryParameters3D.create(from, to)
		q.collide_with_areas = false
		var hit := camera.get_world_3d().direct_space_state.intersect_ray(q)
		if hit and hit.has("collider"):
			blocked[hit["collider"]] = true
			cause[hit["collider"]] = i

	_faded_by.clear()
	for w in fadables:
		if not is_instance_valid(w):
			continue
		# A wall is built from several pieces (sills, lintels, spans between
		# openings), so "is this wall blocking?" means "is ANY of its pieces
		# the collider the ray hit?".
		var hit_index := -1
		for b in w.bodies():
			if blocked.has(b):
				hit_index = cause[b]
				break
		if hit_index >= 0:
			_faded_by[w] = hit_index
		w.set_fade(FADE_ALPHA if hit_index >= 0 else 1.0)


## How many fadables are faded right now.
func faded_count() -> int:
	return _faded_by.size()


## How many fadables are faded on behalf of someone OTHER than the followed
## character. This is the number that must be zero: whatever the followed
## character is behind is legitimately hidden, but nothing should fade for a
## character the player is not looking through.
func faded_for_others() -> int:
	var n := 0
	for f in _faded_by:
		if int(_faded_by[f]) > 0:
			n += 1
	return n


## How many fadables are faded right now, and on whose behalf.
func debug_summary() -> String:
	if _faded_by.is_empty():
		return "0 faded"
	var per := {}
	for f in _faded_by:
		var k: int = _faded_by[f]
		per[k] = per.get(k, 0) + 1
	var parts: Array[String] = []
	var keys: Array = per.keys()
	keys.sort()
	for k in keys:
		parts.append("target#%d blocks %d" % [k, per[k]])
	return "%d faded (%s)" % [_faded_by.size(), ", ".join(parts)]
