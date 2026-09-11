class_name CozyPixelArt
extends RefCounted
## Placeholder art factory — every texture is generated procedurally, zero external assets.
##
## Per the V2 tech doc #36 "systems first, art later":
## phase one uses procedural graphics; swapping in real pixel art later means
## replacing this one file, not rewriting any game logic.
##
## ART IS DELIBERATELY A PLACEHOLDER HERE.
## When real pixel-art materials arrive, only CozyMaterials + this file change.

const NEIGHBORS: Array[Vector2i] = [
	Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1),
]


## Generic NxN procedural pixel texture with noise, so it is not a dead flat color.
static func make_texture(size: int, base: Color, noise: float, seed_val: int) -> ImageTexture:
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_val
	for y in size:
		for x in size:
			var n := rng.randf_range(-noise, noise)
			img.set_pixel(x, y, Color(
				clampf(base.r + n, 0.0, 1.0),
				clampf(base.g + n, 0.0, 1.0),
				clampf(base.b + n, 0.0, 1.0),
				1.0))
	return ImageTexture.create_from_image(img)


## Plank-style pixel texture (horizontal bands + noise), used for wooden walls.
static func make_plank_texture(size: int, base: Color, seed_val: int) -> ImageTexture:
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_val
	var band := maxi(2, size / 4)
	for y in size:
		# Alternate brightness every `band` rows to fake individual planks.
		var plank := y / band
		var shade := 1.0 + (0.06 if plank % 2 == 0 else -0.06)
		for x in size:
			var n := rng.randf_range(-0.03, 0.03)
			img.set_pixel(x, y, Color(
				clampf(base.r * shade + n, 0.0, 1.0),
				clampf(base.g * shade + n, 0.0, 1.0),
				clampf(base.b * shade + n, 0.0, 1.0),
				1.0))
	return ImageTexture.create_from_image(img)


## Simple 16x24 pixel character sprite — the Phase 0 stand-in.
## Replace this single function when real character art is ready.
static func make_character_texture(skin: Color, cloth: Color, hair: Color) -> ImageTexture:
	const W := 16
	const H := 24
	var img := Image.create(W, H, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))

	var head_top := 3
	var head_bot := 10
	var body_top := 10
	var body_bot := 19

	# Head (top two rows read as hair)
	for y in range(head_top, head_bot):
		for x in range(5, 11):
			img.set_pixel(x, y, hair if y < head_top + 2 else skin)

	# Torso
	for y in range(body_top, body_bot):
		for x in range(4, 12):
			img.set_pixel(x, y, cloth)

	# Legs
	for y in range(body_bot, H - 1):
		for x in range(5, 7):
			img.set_pixel(x, y, skin)
		for x in range(9, 11):
			img.set_pixel(x, y, skin)

	return _outline(img, Color(0.15, 0.12, 0.18, 1.0))


## Trace a dark outline around opaque pixels so the sprite stays readable on grass.
static func _outline(img: Image, line: Color) -> ImageTexture:
	var w := img.get_width()
	var h := img.get_height()
	var out := Image.create(w, h, false, Image.FORMAT_RGBA8)
	out.fill(Color(0, 0, 0, 0))
	for y in h:
		for x in w:
			var c := img.get_pixel(x, y)
			if c.a > 0.0:
				out.set_pixel(x, y, c)
				continue
			var near := false
			for d in NEIGHBORS:
				var nx: int = x + d.x
				var ny: int = y + d.y
				if nx >= 0 and nx < w and ny >= 0 and ny < h:
					if img.get_pixel(nx, ny).a > 0.0:
						near = true
						break
			if near:
				out.set_pixel(x, y, line)
	return ImageTexture.create_from_image(out)


## Build a 3D material with nearest-neighbour filtering forced on.
## Pixel art must never be smoothed (doc #35).
static func make_material(tex: Texture2D, uv_scale := Vector3.ONE) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_texture = tex
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	m.uv1_scale = uv_scale
	m.roughness = 1.0
	m.metallic_specular = 0.0   # kill highlights, keep the flat pixel-art look
	return m
