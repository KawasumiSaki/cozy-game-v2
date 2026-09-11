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


## Placeholder ground vegetation. Anchored at the BOTTOM CENTRE — the sprite
## stands ON the ground, which is the anchor rule in docs/ART_PROFILE.md.
##
## Everything here is procedural, per doc 58.1: art may be empty, but no system
## may depend on art existing. Real sprites replace these without touching the
## scatter rules.
static func make_grass_tuft_texture(seed_val := 1) -> ImageTexture:
	const W := 16
	const H := 16
	var img := Image.create(W, H, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_val
	var base := Color(0.36, 0.62, 0.28)
	for b in 4:
		var x0 := 4 + b * 3
		var h := 7 + rng.randi_range(0, 5)
		var lean := rng.randi_range(-1, 1)
		for i in h:
			var y := H - 2 - i
			var x := x0 + int(round(float(lean) * float(i) / float(h)))
			var shade := 1.0 - float(i) * 0.03
			img.set_pixel(x, y, Color(base.r * shade, base.g * shade, base.b * shade, 1.0))
	return _outline(img, Color(0.16, 0.26, 0.14, 1.0))


static func make_flower_texture(petal := Color(0.94, 0.86, 0.42), seed_val := 2) -> ImageTexture:
	const W := 16
	const H := 16
	var img := Image.create(W, H, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var stem := Color(0.34, 0.56, 0.28)
	for y in range(8, H - 1):
		img.set_pixel(8, y, stem)
	for d in [Vector2i(0, 0), Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
		img.set_pixel(8 + d.x, 6 + d.y, petal)
	img.set_pixel(8, 6, Color(0.92, 0.74, 0.28))
	return _outline(img, Color(0.20, 0.24, 0.14, 1.0))


static func make_pebble_texture(base := Color(0.56, 0.56, 0.58), seed_val := 3) -> ImageTexture:
	const W := 16
	const H := 16
	var img := Image.create(W, H, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_val
	for y in range(9, H - 1):
		for x in range(4, 12):
			var n := rng.randf_range(-0.05, 0.05)
			img.set_pixel(x, y, Color(
				clampf(base.r + n, 0.0, 1.0), clampf(base.g + n, 0.0, 1.0),
				clampf(base.b + n, 0.0, 1.0), 1.0))
	return _outline(img, Color(0.24, 0.24, 0.26, 1.0))


## Billboarding material for scattered vegetation. Fixed-Y so a sprite never
## tips with the camera (docs/ART_PROFILE.md), alpha-cut so depth sorting stays
## correct and walls still occlude it.
static func make_billboard_material(tex: Texture2D) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_texture = tex
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	m.billboard_mode = BaseMaterial3D.BILLBOARD_FIXED_Y
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
	m.alpha_scissor_threshold = 0.5
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.roughness = 1.0
	m.metallic_specular = 0.0
	return m


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
