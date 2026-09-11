class_name CozyVfx
extends Node3D
## A looping pixel VFX sprite (V2.1 doc E.18 / 58.3 Layer 4 / E.21).
##
## VFX follow the same rules as every other art asset: pixel sprites, fixed-Y
## billboards, nearest filtering, and a DETERMINISTIC phase offset so a row of
## campfires does not flicker in lockstep. Two fires lit at different places
## must animate out of step with each other, and must do so identically after a
## save and reload — which is doc E.21 applied to time rather than to position.
##
## Frames are held as plain textures rather than an AnimatedSprite3D because
## the doc's VFX library is sprite-based and this keeps the dependency surface
## to one node and one timer.

var vfx_id := ""
var frames: Array[Texture2D] = []
var frame_time := 0.12
var world_size := 0.6
var height := 0.3

## The deterministic offset this instance started at, kept for inspection.
var start_phase := 0.0

var _sprite: Sprite3D = null
var _t := 0.0
var _frame := -1
var _advances := 0     ## Frames shown so far — read by the self-check.


## Build one from a definition id. `phase` desynchronises instances (doc E.21).
static func create(p_id: String, phase := 0.0) -> CozyVfx:
	var def := CozyVfxDefs.get_def(p_id)
	var v := CozyVfx.new()
	v.setup(p_id, def, _frames_for(p_id), phase)
	return v


static func _frames_for(id: String) -> Array[Texture2D]:
	match id:
		"smoke":
			return CozyPixelArt.make_smoke_frames()
		"magic":
			return CozyPixelArt.make_magic_frames()
		_:
			return CozyPixelArt.make_fire_frames()


func setup(p_id: String, def: Dictionary, textures: Array[Texture2D],
		p_phase := 0.0) -> void:
	vfx_id = p_id
	frames = textures
	frame_time = float(def.get("frame_time", 0.12))
	world_size = float(def.get("size", 0.6))
	height = float(def.get("height", 0.3))

	_sprite = Sprite3D.new()
	_sprite.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	_sprite.billboard = BaseMaterial3D.BILLBOARD_FIXED_Y
	_sprite.pixel_size = world_size / 32.0
	_sprite.alpha_cut = SpriteBase3D.ALPHA_CUT_DISCARD
	_sprite.shaded = false
	_sprite.double_sided = true
	_sprite.position = Vector3(0.0, height, 0.0)
	add_child(_sprite)

	# Phase is the deterministic offset, not a random one (doc E.21).
	var total := maxf(frame_time * float(frames.size()), 0.0001)
	start_phase = fmod(p_phase, total)
	_t = start_phase
	_apply_frame()


## Re-seed the phase. Used after placement, because an object's effects are
## built before it has a world position — and the phase has to depend on WHERE
## the instance is, not merely on which definition it uses. Two campfires share
## a definition; only their positions tell them apart (doc E.21).
func set_phase(p_phase: float) -> void:
	var total := maxf(frame_time * float(frames.size()), 0.0001)
	start_phase = fmod(p_phase, total)
	_t = start_phase
	_frame = -1
	_apply_frame()


func _process(delta: float) -> void:
	if frames.is_empty():
		return
	_t += delta
	var total := frame_time * float(frames.size())
	if total <= 0.0:
		return
	var f := int(_t / frame_time) % frames.size()
	if f != _frame:
		_frame = f
		_advances += 1
		_apply_frame()


func _apply_frame() -> void:
	if _sprite == null or frames.is_empty():
		return
	_sprite.texture = frames[maxi(_frame, 0) % frames.size()]


# ---------------------------------------------------------------- queries

func current_frame() -> int:
	return maxi(_frame, 0)


func advances() -> int:
	return _advances


func describe() -> String:
	return "%s frame %d/%d" % [vfx_id, current_frame(), frames.size()]
