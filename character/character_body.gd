class_name CozyCharacter
extends CharacterBody3D
## Character — 3D position + 2D pixel billboard (V2 doc #10.3 / #156).
##
## The core idea: a character genuinely EXISTS in three dimensions (it has
## X/Y/Z, a floor, gets blocked by walls, can climb stairs), but what the
## player sees is a pixel drawing. That is the whole thesis of the doc:
##     #3.6  "Real Space Under the Hood, Pixel Art on the Surface."

const SPRITE_TEX_W := 16       ## Sprite is 16px wide
const SPRITE_TEX_H := 24       ## Sprite is 24px tall
const SPRITE_WORLD_W := 0.8    ## Want the character 0.8m wide -> pixel_size = 0.8/16

const CAPSULE_RADIUS := 0.3
const CAPSULE_HEIGHT := 1.2    ## Matches the sprite's world height, so visuals and collision agree

const GRAVITY := 24.0

var display_name := "NPC"
var move_speed := 5.0
var uses_gravity := false
var is_player := false

var sprite: Sprite3D = null

var _skin := Color(0.96, 0.80, 0.66)
var _cloth := Color(0.55, 0.42, 0.72)
var _hair := Color(0.32, 0.22, 0.16)


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
	sprite = Sprite3D.new()
	sprite.texture = CozyPixelArt.make_character_texture(_skin, _cloth, _hair)
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
	add_child(sprite)


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
