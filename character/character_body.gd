class_name CozyCharacter
extends CharacterBody3D
## Character — 3D position + 2D pixel billboard (V2 doc #10.3 / #156).
##
## The core idea: a character genuinely EXISTS in three dimensions (it has
## X/Y/Z, a floor, gets blocked by walls, can climb stairs), but what the
## player sees is a pixel drawing. That is the whole thesis of the doc:
##     #3.6  "Real Space Under the Hood, Pixel Art on the Surface."

## The billboard's canvas, in texels. TAKEN FROM `CozyPixelArt` rather than typed
## here: the placeholder sheet is drawn on that canvas, and a body that expected a
## different one would draw a correctly-authored figure at the wrong size — with no
## error, no warning, and nothing but "the characters look off" to go on.
const SPRITE_TEX_W := CozyPixelArt.CHARACTER_TEX_W
const SPRITE_TEX_H := CozyPixelArt.CHARACTER_TEX_H

## How wide the figure stands in the world. `pixel_size` is this over the canvas
## width, so these two together decide the sprite's world HEIGHT — 112 texels at
## 0.5/32 m each is 1.75 m, which is what `CAPSULE_HEIGHT` says.
##
## THE SHEET IS AUTHORED AT 64 px/m AND DRAWN AT 32. That factor of two is the
## whole reason the canvas is 112 texels rather than 56, and it is the number the
## Blender factory is asked to match (`ART_PROFILE.md` §2.1).
const SPRITE_WORLD_W := 0.5

## A person, in metres. The capsule and the sprite agree, which is the rule this
## pair has always followed — it used to read 1.2, which is nobody's height.
const CAPSULE_HEIGHT := 1.75

## NOT a height and NOT an art number: this is the NAVIGATION CLEARANCE.
## `main.gd`'s `NAV_CLEARANCE` IS this value, and both navigation grids inflate
## every obstacle by it — so changing it changes which gaps a resident can walk
## through. It is deliberately left at 0.3 while the body around it became a real
## size; 0.6 m is a person's shoulders and a door is narrower than that.
const CAPSULE_RADIUS := 0.3

const GRAVITY := 24.0

var display_name := "NPC"
var move_speed := 5.0
var uses_gravity := false
var is_player := false

## AnimatedSprite3D, NOT AnimatedSprite2D — an AnimatedSprite2D is a CanvasItem
## and cannot stand in a 3D world. The 3D one extends SpriteBase3D, so every
## property this file sets below (billboard, pixel_size, alpha_cut) still applies
## exactly as it did on Sprite3D; only `texture` became `sprite_frames`.
var sprite: AnimatedSprite3D = null

## Who this character looks like (ART-14). Data, not a scene — see
## `CozyAppearanceDefs`. Assigning a new one only takes effect on `rebuild_visual`.
var appearance: Dictionary = CozyAppearanceDefs.make_default()

var _skin := Color(0.96, 0.80, 0.66)
var _cloth := Color(0.55, 0.42, 0.72)
var _hair := Color(0.32, 0.22, 0.16)
var _playing := ""


func setup(p_name: String, p_skin: Color, p_cloth: Color, p_hair: Color, p_is_player := false) -> void:
	display_name = p_name
	_skin = p_skin
	_cloth = p_cloth
	_hair = p_hair
	is_player = p_is_player


func _ready() -> void:
	_build_visual()
	_build_collision()


func _build_visual() -> void:
	sprite = AnimatedSprite3D.new()
	sprite.sprite_frames = CozyCharacterVisuals.frames_for(appearance)
	sprite.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	# Fixed-Y billboard: rotate around the vertical axis only, never follow the
	# camera's pitch — otherwise the sprite lays down as the camera tilts.
	sprite.billboard = BaseMaterial3D.BILLBOARD_FIXED_Y
	sprite.pixel_size = SPRITE_WORLD_W / float(SPRITE_TEX_W)
	# Alpha-cut rather than blended transparency, so depth sorting stays correct
	# and walls occlude the character properly.
	sprite.alpha_cut = SpriteBase3D.ALPHA_CUT_DISCARD
	sprite.shaded = false
	sprite.double_sided = true
	# The texture centre is not the feet: lift by half the height so the
	# sprite's feet land exactly on the node origin.
	sprite.position = Vector3(0.0, CAPSULE_HEIGHT * 0.5, 0.0)
	_playing = ""
	add_child(sprite)
	_update_animation()


## Rebuild the sprite from `appearance`. Separate from `_build_visual` so a
## resident can be re-dressed without being re-created — and so the caller can
## assign `appearance` after `_ready()` has already run.
func rebuild_visual() -> void:
	if sprite != null and is_instance_valid(sprite):
		sprite.queue_free()
	_build_visual()


## What this character believes it is doing. Overridden by residents; the player
## only ever walks and stands.
func current_activity() -> String:
	return "work"


## Is the character engaged in a task rather than idle? The player never is.
func is_occupied() -> bool:
	return false


## Which animation should be playing right now. Derived from the ACTUAL velocity
## rather than from a movement intent, so there is one source of truth for "am I
## moving" — the physics — instead of two that can disagree.
func current_animation() -> String:
	var flat := Vector2(velocity.x, velocity.z)
	return CozyCharacterVisuals.select(
		current_activity(), flat.length_squared() > 0.01, is_occupied())


## Idempotent by construction: it reads state and only calls into the sprite when
## the answer changed, so running it N times is the same as running it once.
func _update_animation() -> void:
	if sprite == null or not is_instance_valid(sprite):
		return
	if sprite.sprite_frames == null:
		return
	var want := current_animation()
	if want == _playing:
		return
	if not sprite.sprite_frames.has_animation(want):
		return
	_playing = want
	sprite.play(want)


func _build_collision() -> void:
	var cs := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = CAPSULE_RADIUS
	cap.height = CAPSULE_HEIGHT
	cs.shape = cap
	cs.position = Vector3(0.0, CAPSULE_HEIGHT * 0.5, 0.0)
	add_child(cs)


func _physics_process(delta: float) -> void:
	if uses_gravity:
		if not is_on_floor():
			velocity.y -= GRAVITY * delta
		elif velocity.y < 0.0:
			velocity.y = 0.0
	move_and_slide()
	# After move_and_slide, so the animation reads this frame's velocity rather
	# than the previous frame's — one frame of lag is invisible in a still and
	# obvious in a walk cycle.
	_update_animation()


## Set this frame's horizontal movement intent (world-space, already normalised).
func set_move_dir(dir: Vector3) -> void:
	velocity.x = dir.x * move_speed
	velocity.z = dir.z * move_speed


func stop() -> void:
	velocity.x = 0.0
	velocity.z = 0.0


## Which floor this character is on (doc #8.2). Floor height is a building-system
## parameter, never hard-coded into the logic.
func current_floor(floor_height := 3.0) -> int:
	return int(round(global_position.y / floor_height))
