class_name CozyTerrainTiles
extends RefCounted
## The ground as TILES: sixteen per material, picked by what is in the four cells
## around a corner.
##
## This is dual-grid tilemapping, the technique Willow pointed at: a display grid
## offset half a tile from the logical one, so every display tile sits where four
## logical cells meet and only has to look at FOUR neighbours rather than eight.
## That is what turns the naive 256 combinations (2^8) into sixteen — and it is a
## DIMENSIONAL reduction rather than a symmetry argument, which is why the corners
## come out consistent instead of hand-matched.
##
## ---------------------------------------------------------------------------
## SIXTEEN PER MATERIAL, NOT SIXTEEN.
##
## A 16-tile set is complete for a BINARY field — filled or not — because each of
## the four neighbours is then one of two things. Ours are six materials, and the
## four cells around a corner can be four DIFFERENT ones: 6^4 = 1296 combinations
## before any symmetry. That is exactly why the reduction works in the 2D case
## and does not here.
##
## Both references solve it the same way, and the research says so plainly:
## TileMapDual ships "one display layer per terrain" (six materials, seven layers)
## and Exonfang ships 28 tiles per terrain with unlimited adjacency. The shape of
## that answer is: a material draws ITS OWN quadrants and leaves the rest alone,
## and the display tile is the pile of those in priority order.
##
## So a display tile emits one quad per material present around it — usually ONE,
## because a tile in the middle of a field has the same material in all four
## cells and its tile is a solid square.

## Texels per tile side. The project's own pixel unit.
const TILE := 16

## Bits, one per quadrant of a display tile.
const MASKS := 16
const QUAD_TL := 1
const QUAD_TR := 2
const QUAD_BL := 4
const QUAD_BR := 8

## How the tiles are laid out in the atlas.
const ATLAS_COLS := 8

## How far a rounded corner is cut back, in texels. A eighth of a tile: enough to
## read as a curve at the locked camera distance and not so much that a lone cell
## of material stops looking like a cell.
const CORNER_RADIUS := 2.0


static func material_count() -> int:
	return CozyTerrainMaterials.ORDER.size()


static func tile_count() -> int:
	return material_count() * MASKS


static func atlas_size() -> Vector2i:
	var rows := int(ceil(float(tile_count()) / float(ATLAS_COLS)))
	return Vector2i(ATLAS_COLS * TILE, rows * TILE)


## Which slot in the atlas one (material, mask) pair lives in.
static func tile_index(material_index: int, mask: int) -> int:
	return material_index * MASKS + mask


## The atlas rect of one tile, in 0..1 UV.
static func tile_uv(material_index: int, mask: int) -> Rect2:
	var size := atlas_size()
	var index := tile_index(material_index, mask)
	var col := index % ATLAS_COLS
	var row := index / ATLAS_COLS
	return Rect2(
		float(col * TILE) / float(size.x), float(row * TILE) / float(size.y),
		float(TILE) / float(size.x), float(TILE) / float(size.y))


## Which of four cells carry this material, as a quadrant mask.
##
## `around` is in quadrant order: top-left, top-right, bottom-left, bottom-right
## of the display tile — which is the order the four cells around a corner are
## read in, and the order the bits mean.
static func mask_of(around: Array, material: String) -> int:
	var m := 0
	for i in mini(around.size(), 4):
		if String(around[i]) == material:
			m |= (1 << i)
	return m


## The material a display tile's quad for `material_index` should be drawn with,
## or -1 when that material is not present at all.
##
## Trivial, and it exists to be the ONE place that decides, so the renderer and
## any assertion cannot disagree about what "present" means.
static func present(around: Array, material_index: int) -> bool:
	return mask_of(around, CozyTerrainMaterials.id_of(material_index)) != 0


# ---------------------------------------------------------------- the artwork

## Every tile, as one image. Procedural, like all the placeholder art here, so a
## new terrain material is a row in `CozyTerrainMaterials` and needs no file.
static func build_atlas() -> ImageTexture:
	var size := atlas_size()
	var atlas := Image.create(size.x, size.y, false, Image.FORMAT_RGBA8)
	atlas.fill(Color(0, 0, 0, 0))
	for m in material_count():
		for mask in MASKS:
			_draw_tile(atlas, m, mask)
	return ImageTexture.create_from_image(atlas)


## One (material, mask) tile: the material's own grain, in the quadrants the mask
## names, with a rounded inner corner where the region TURNS.
##
## THE ROUNDING IS THE POINT OF THE WHOLE TECHNIQUE. Without it a lone cell of
## stone beside grass is a square; with it the corner at the tile's centre curves,
## and it curves the same way in every tile because it comes from one rule rather
## than from sixteen pieces of hand-matched art. That consistency is what the
## references buy and the tile count is a side effect.
##
## Only the CONVEX case is rounded — a mask with exactly one quadrant filled. The
## concave case (three filled, one empty) would need the empty quadrant's corner
## bulging outward, which is a different shape; it is left square for now and says
## so rather than being quietly wrong.
static func _draw_tile(atlas: Image, material_index: int, mask: int) -> void:
	if mask == 0:
		return                            # Nothing of this material here.
	var base := atlas_origin(material_index, mask)
	var corners := [
		[QUAD_TL, Vector2i(0, 0)],
		[QUAD_TR, Vector2i(TILE / 2, 0)],
		[QUAD_BL, Vector2i(0, TILE / 2)],
		[QUAD_BR, Vector2i(TILE / 2, TILE / 2)],
	]

	var filled: Array = []
	for c in corners:
		if (mask & int(c[0])) != 0:
			filled.append(c)

	var single := filled.size() == 1
	for c in filled:
		var off: Vector2i = c[1]
		for y in TILE / 2:
			for x in TILE / 2:
				var p := off + Vector2i(x, y)
				if single and _inside_round_corner(p, off):
					continue
				atlas.set_pixel(base.x + p.x, base.y + p.y,
					_grain(material_index, p.x, p.y))


## The top-left texel of a tile in the atlas.
static func atlas_origin(material_index: int, mask: int) -> Vector2i:
	var index := tile_index(material_index, mask)
	return Vector2i((index % ATLAS_COLS) * TILE, (index / ATLAS_COLS) * TILE)


## Is this texel inside the quarter-disc cut from a lone quadrant's inner corner?
##
## The disc is centred on the tile's CENTRE, so it is the corner the four
## quadrants share that gets rounded — which is exactly where two materials meet.
static func _inside_round_corner(p: Vector2i, off: Vector2i) -> bool:
	var to_centre := Vector2(float(TILE) * 0.5) - Vector2(p) - Vector2(0.5, 0.5)
	return to_centre.length() < CORNER_RADIUS


## The material's colour, grained deterministically so a field does not read as
## flat paint and the same world regenerates identically after a load (doc #53).
static func _grain(material_index: int, x: int, y: int) -> Color:
	var id := CozyTerrainMaterials.id_of(material_index)
	var base := CozyTerrainMaterials.color_of(id)
	var n := float(absi(hash(Vector3i(x, y, hash(id)))) % 1000) / 1000.0
	var shade := 1.0 + (n - 0.5) * 0.18
	return Color(
		clampf(base.r * shade, 0.0, 1.0),
		clampf(base.g * shade, 0.0, 1.0),
		clampf(base.b * shade, 0.0, 1.0),
		1.0)
