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
##
## `pose` and `step` exist so `CozyCharacterVisuals` can build a whole sprite
## sheet from one function. These are PLACEHOLDER POSES, not animation: each is a
## couple of pixels of difference, which is all a 16x24 figure can carry and all
## the pipeline contract needs exercised. They have to be DISTINGUISHABLE, though
## — a selector that plays `work` through a resident's sleep is invisible if
## every pose draws the same figure.
##
## Replace this function when real character art is ready. Neither the selection
## logic nor the sheet contract changes when it is.
static func make_character_texture(skin: Color, cloth: Color, hair: Color,
		pose := "idle", step := 0) -> ImageTexture:
	const W := 16
	const H := 24
	var img := Image.create(W, H, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))

	# Lying down is a different SHAPE, not an offset — a standing figure shifted
	# a few pixels still reads as standing.
	if pose == "sleep":
		for y in range(H - 7, H - 3):
			for x in range(3, 13):
				img.set_pixel(x, y, cloth)
		for x in range(12, 16):                      # head at the far end
			for y in range(H - 8, H - 3):
				img.set_pixel(x, y, hair if y < H - 6 else skin)
		return _outline(img, Color(0.15, 0.12, 0.18, 1.0))

	# Sitting drops the whole figure and shortens the legs.
	var drop := 2 if pose == "sit" else 0
	var breathe := 1 if (pose == "idle" or pose == "work") and step % 2 == 1 else 0
	var lean := 1 if pose == "work" and step % 2 == 1 else 0

	var head_top := 3 + drop + breathe
	var head_bot := 10 + drop + breathe
	var body_top := 10 + drop + breathe
	var body_bot := 19 + drop
	var leg_bot := H - 1 if pose != "sit" else H - 4

	# Head (top two rows read as hair)
	for y in range(head_top, head_bot):
		for x in range(5 + lean, 11 + lean):
			img.set_pixel(x, y, hair if y < head_top + 2 else skin)

	# Torso
	for y in range(body_top, body_bot):
		for x in range(4 + lean, 12 + lean):
			img.set_pixel(x, y, cloth)

	# Legs. Walking swings them in opposite directions; everything else is still.
	var lx := 5
	var rx := 9
	if pose == "walk":
		var swing: int = [0, 1, 0, -1][step % 4]
		lx += swing
		rx -= swing
	for y in range(body_bot, leg_bot):
		for x in range(lx, lx + 2):
			img.set_pixel(x, y, skin)
		for x in range(rx, rx + 2):
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


static func make_tree_texture(seed_val := 4) -> ImageTexture:
	const W := 24
	const H := 32
	var img := Image.create(W, H, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_val

	# Trunk
	var trunk := Color(0.42, 0.29, 0.19)
	for y in range(20, H - 1):
		for x in range(10, 14):
			img.set_pixel(x, y, trunk)

	# Canopy: a rough disc, with a lit top and shaded underside.
	var leaf := Color(0.28, 0.52, 0.24)
	var cx := 12.0
	var cy := 12.0
	for y in range(2, 22):
		for x in range(1, W - 1):
			var dx := float(x) - cx
			var dy := (float(y) - cy) * 1.15
			if dx * dx + dy * dy <= 92.0:
				var n := rng.randf_range(-0.06, 0.06)
				var shade := 1.0 - float(y) * 0.012
				img.set_pixel(x, y, Color(
					clampf(leaf.r * shade + n, 0.0, 1.0),
					clampf(leaf.g * shade + n, 0.0, 1.0),
					clampf(leaf.b * shade + n, 0.0, 1.0), 1.0))
	return _outline(img, Color(0.14, 0.22, 0.12, 1.0))


## ---------------------------------------------------------------- UI icons
##
## 16x16, procedural, placeholder like everything else. Each one must be
## distinguishable at a glance IN SILHOUETTE ALONE — an icon that only reads by
## its colour stops working the moment two materials share a palette, which
## wood / brick / plaster already do.

static func make_material_icon(id: String, base: Color) -> ImageTexture:
	const S := 16
	var img := Image.create(S, S, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var dark := base.darkened(0.35)
	var light := base.lightened(0.18)

	match id:
		"wood":
			# A log seen end-on: a disc with two growth rings.
			_fill_rect(img, 2, 4, 13, 11, dark)
			_fill_rect(img, 3, 5, 12, 10, base)
			_ring(img, 7, 8, 3, light)
			_ring(img, 7, 8, 1, dark)
		"stone", "brick":
			# Stacked blocks, offset like a wall.
			_fill_rect(img, 2, 4, 13, 7, base)
			_fill_rect(img, 2, 9, 13, 11, dark)
			_fill_rect(img, 7, 4, 8, 7, dark)
			_fill_rect(img, 4, 9, 5, 11, base)
		_:
			# Anything else: a simple faceted chunk.
			_fill_rect(img, 4, 5, 11, 12, base)
			_fill_rect(img, 6, 3, 9, 5, light)
			_fill_rect(img, 4, 11, 11, 12, dark)
	return _outline(img, Color(0.11, 0.09, 0.13, 1.0))


static func make_tool_icon(tool: String) -> ImageTexture:
	const S := 16
	var img := Image.create(S, S, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var ink := Color(0.90, 0.87, 0.80)
	var shade := Color(0.55, 0.52, 0.47)

	match tool:
		"wall":
			# A course of bricks — solid, laid.
			_fill_rect(img, 1, 5, 14, 8, ink)
			_fill_rect(img, 1, 9, 14, 12, shade)
			_fill_rect(img, 7, 5, 8, 8, shade)
			_fill_rect(img, 4, 9, 5, 12, ink)
		"outline":
			# A drawn rectangle — hollow, by intent.
			_rect_outline(img, 2, 4, 13, 12, ink)
		"research_table":
			_fill_rect(img, 1, 6, 14, 8, ink)          # top
			_fill_rect(img, 3, 9, 4, 13, shade)        # legs
			_fill_rect(img, 11, 9, 12, 13, shade)
		"chest":
			_fill_rect(img, 2, 6, 13, 13, ink)
			_fill_rect(img, 2, 9, 13, 10, shade)
			_fill_rect(img, 7, 8, 8, 11, shade)        # lock
		"bed":
			_fill_rect(img, 1, 5, 14, 13, ink)
			_fill_rect(img, 2, 5, 6, 8, shade)         # pillow
			_fill_rect(img, 1, 11, 14, 13, shade)
		"chair":
			_fill_rect(img, 4, 4, 11, 8, ink)          # back
			_fill_rect(img, 2, 9, 13, 11, ink)         # seat
			_fill_rect(img, 3, 11, 4, 14, shade)
			_fill_rect(img, 11, 11, 12, 14, shade)
		"campfire":
			_fill_rect(img, 2, 11, 13, 13, shade)      # logs
			_fill_rect(img, 6, 4, 9, 11, Color(0.95, 0.72, 0.30))
			_fill_rect(img, 7, 7, 8, 11, Color(0.98, 0.88, 0.55))
		_:
			_rect_outline(img, 3, 3, 12, 12, ink)
	return _outline(img, Color(0.11, 0.09, 0.13, 1.0))


static func _fill_rect(img: Image, x0: int, y0: int, x1: int, y1: int, c: Color) -> void:
	for y in range(y0, y1 + 1):
		for x in range(x0, x1 + 1):
			if x >= 0 and y >= 0 and x < img.get_width() and y < img.get_height():
				img.set_pixel(x, y, c)


static func _rect_outline(img: Image, x0: int, y0: int, x1: int, y1: int, c: Color) -> void:
	for x in range(x0, x1 + 1):
		_fill_rect(img, x, y0, x, y0, c)
		_fill_rect(img, x, y1, x, y1, c)
	for y in range(y0, y1 + 1):
		_fill_rect(img, x0, y, x0, y, c)
		_fill_rect(img, x1, y, x1, y, c)


static func _ring(img: Image, cx: int, cy: int, r: int, c: Color) -> void:
	for a in 32:
		var t := TAU * float(a) / 32.0
		var x := cx + int(round(cos(t) * float(r)))
		var y := cy + int(round(sin(t) * float(r)))
		if x >= 0 and y >= 0 and x < img.get_width() and y < img.get_height():
			img.set_pixel(x, y, c)


## VFX frame sets (doc E.18). Placeholder like everything else — real VFX come
## from the asset library later. Each set is a short loop of 32x32 frames.

static func make_fire_frames() -> Array[Texture2D]:
	var out: Array[Texture2D] = []
	var rng := RandomNumberGenerator.new()
	rng.seed = 909
	for f in 4:
		var img := Image.create(32, 32, false, Image.FORMAT_RGBA8)
		img.fill(Color(0, 0, 0, 0))
		# Flame height and lean change per frame; the base stays put.
		var h := 13 + f * 2
		var lean := (f - 1) * 0.6
		for y in range(32 - h, 30):
			var t := float(30 - y) / float(h)          # 0 at base, 1 at tip
			var half := maxf(1.0, (1.0 - t) * 7.0 - t * 1.5)
			var cx := 16.0 + lean * t
			for x in range(int(cx - half), int(cx + half) + 1):
				if x < 0 or x >= 32:
					continue
				# Core is yellow-white, edges orange-red.
				var edge := absf(float(x) - cx) / half
				var c := Color(0.98, 0.82, 0.30).lerp(Color(0.85, 0.30, 0.12), edge)
				c = c.lerp(Color(0.55, 0.14, 0.06), t * 0.75)
				if rng.randf() < 0.12:
					c = c.darkened(0.25)
				img.set_pixel(x, y, Color(c.r, c.g, c.b, 1.0))
		out.append(ImageTexture.create_from_image(img))
	return out


static func make_smoke_frames() -> Array[Texture2D]:
	var out: Array[Texture2D] = []
	var rng := RandomNumberGenerator.new()
	rng.seed = 4242
	for f in 4:
		var img := Image.create(32, 32, false, Image.FORMAT_RGBA8)
		img.fill(Color(0, 0, 0, 0))
		var rise := float(f) * 2.0
		var spread := 6.0 + float(f) * 1.6
		var cx := 16.0 + (float(f) - 1.5) * 0.8
		var cy := 22.0 - rise
		for y in 32:
			for x in 32:
				var d := Vector2((float(x) - cx) / spread, (float(y) - cy) / (spread * 1.2))
				if d.length() > 1.0:
					continue
				var a := (1.0 - d.length()) * (0.55 - float(f) * 0.08)
				var n := rng.randf_range(-0.05, 0.05)
				img.set_pixel(x, y, Color(
					clampf(0.62 + n, 0, 1), clampf(0.62 + n, 0, 1),
					clampf(0.64 + n, 0, 1), clampf(a, 0, 1)))
		out.append(ImageTexture.create_from_image(img))
	return out


static func make_magic_frames() -> Array[Texture2D]:
	var out: Array[Texture2D] = []
	for f in 4:
		var img := Image.create(32, 32, false, Image.FORMAT_RGBA8)
		img.fill(Color(0, 0, 0, 0))
		var rng := RandomNumberGenerator.new()
		rng.seed = 77 + f
		for i in 10:
			var a := rng.randf() * TAU
			var r := 4.0 + rng.randf() * 10.0
			var x := int(16.0 + cos(a) * r)
			var y := int(18.0 + sin(a) * r * 0.6) - int(float(f) * 1.5)
			if x >= 0 and x < 32 and y >= 0 and y < 32:
				img.set_pixel(x, y, Color(0.72, 0.86, 0.98, 1.0))
		out.append(ImageTexture.create_from_image(img))
	return out


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
