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

## Supplies the fadables. Asked for on EVERY refresh, so the list cannot go stale.
##
## It used to be pushed in, and re-pushed from a handful of call sites. That is a
## snapshot of a live collection, and the building system REPLACES views as the
## world changes — a roof follows its room, a local edit rebuilds a wall. Any
## replacement landing between two pushes leaves a FREED node in the list and the
## live one missing.
##
## Measured 2026-09-12 with the occlusion probe: at frame 91 `roof_views` held one
## live roof while the list held a dead one, so NO roof ever faded — and nothing
## reported it, because a fade list is only ever read through entry by entry and a
## freed entry is skipped in silence.
var fadable_source: Callable = Callable()

## A STRUCTURAL reason to fade something, asked about every fadable before the
## ray is cast. The callable takes the fadable and answers whether it should be
## see-through because of WHERE it is.
##
## THE RAY CANNOT ANSWER THIS, and the probe measured why on 2026-09-14. Standing
## on floor 1 of the house, `--cozy-probe-occlusion` reported ONE fadable on the
## ray -- the roof -- while the floor's own south wall was untouched. The ray
## passes through one of that wall's WINDOWS on the way to the player, so the
## wall is not between them; but a wall with an opening in the line of sight is
## still a wall, and the room behind it is still hidden.
##
## It is also the wrong question. The ray answers "what is between the camera and
## the character"; Willow's rule is about the building -- everything ABOVE the
## floor the resident is on, plus the wall on the camera's side of that floor.
## A ceiling is not between the camera and the player when the camera is under
## it, and no camera angle fixes that.
##
## A policy about the building belongs to whoever knows the building, so it is
## supplied from outside rather than guessed at in here -- the same injection
## `fadable_source` already uses.
var structural_source: Callable = Callable()

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

## How many blockers one ray may walk through before giving up.
##
## A bound, not a budget: it exists so a degenerate ray (grazing a wall built from
## many pieces) cannot spin. Crossing a house is a handful of hits, so this is far
## above what a real line of sight produces.
const MAX_BLOCKERS_PER_RAY := 24

## Diagnostics: which target's line of sight each faded object is blocking.
## Read by the self-check so the cause is measured rather than guessed.
var _faded_by: Dictionary = {}


func _process(_delta: float) -> void:
	refresh()


## Recompute the fade set.
##
## Split out of `_process` so it can be driven on demand — the occlusion probe
## steps the followed character from spot to spot and has to ask after each move,
## within the same frame. It also gives this project's "a per-frame refresh must
## be idempotent" rule something with a name to assert against.
func refresh() -> void:
	if camera == null or not camera.is_inside_tree():
		return

	if fadable_source.is_valid():
		fadables = fadable_source.call()

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
		var space := camera.get_world_3d().direct_space_state
		var from: Vector3 = camera.global_position
		var to: Vector3 = t.global_position + Vector3(0.0, AIM_HEIGHT, 0.0)
		# EVERY blocker on the ray, not just the nearest.
		#
		# `intersect_ray` returns one hit, and taking it alone leaves everything
		# behind it opaque — so the character stays hidden. Measured 2026-09-12
		# with the yaw sweep in `--cozy-probe-occlusion`: standing inside floor 0
		# reports an opaque blocker at yaw 0, 90, 180 AND 270, and the blocker is
		# always a slab. That is the upper floor acting as a ceiling, and no camera
		# angle puts the camera under it. Fading only the first hit cannot fix a
		# case where the first hit is not the one doing the hiding.
		var exclude: Array[RID] = []
		if t is CollisionObject3D:
			exclude.append((t as CollisionObject3D).get_rid())
		for _step in MAX_BLOCKERS_PER_RAY:
			var q := PhysicsRayQueryParameters3D.create(from, to)
			q.collide_with_areas = false
			q.exclude = exclude
			var hit := space.intersect_ray(q)
			if hit.is_empty() or not hit.has("collider"):
				break
			blocked[hit["collider"]] = true
			cause[hit["collider"]] = i
			exclude.append(hit["rid"])

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
		# ... and the structural rule is asked as well, because the two answer
		# different questions and either can be the one that matters.
		var structural := false
		if hit_index < 0 and structural_source.is_valid():
			structural = bool(structural_source.call(w))
		# RECORDED FOR EITHER CAUSE, and that is not bookkeeping. The count is
		# what the probe and the self-check read, so a fade that is not recorded
		# is a fade the measurement says did not happen — which is exactly how
		# this looked for an hour: the shader faded nine fadables and the probe
		# reported two. A count that only knows about one of two causes is a count
		# that lies about the other.
		#
		# Index 0 for a structural fade: it is for the followed character's view,
		# which is what index 0 already means.
		if hit_index >= 0 or structural:
			_faded_by[w] = maxi(hit_index, 0)
		w.set_fade(FADE_ALPHA if hit_index >= 0 or structural else 1.0)


## How many fadables are faded right now.
func faded_count() -> int:
	return _faded_by.size()


## Is this particular fadable faded? The probe needs per-object answers, because
## "how many faded" cannot tell a correct fade from a missing one.
func is_faded(f: Object) -> bool:
	return _faded_by.has(f)


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
