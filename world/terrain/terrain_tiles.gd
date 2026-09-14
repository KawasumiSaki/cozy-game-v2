class_name CozyTerrainTiles
extends RefCounted
## The dual-grid tile vocabulary, and the ground's material textures.
##
## Dual-grid tilemapping is one idea: put the DISPLAY grid half a tile off the
## logical one, so every display tile sits where four logical cells meet and has
## four neighbours to look at instead of eight. That is what turns the naive 256
## combinations (2^8) into sixteen, and it is a DIMENSIONAL reduction rather than
## a symmetry argument — which is why the corners come out consistent instead of
## hand-matched.
##
## ---------------------------------------------------------------------------
## SIXTEEN PER MATERIAL, WHICH IS WHY THIS IS NOT SIXTEEN.
##
## A 16-tile set is complete for a BINARY field, because each of the four
## neighbours is then one of two things. Ours are six materials and the four cells
## around a corner can be four different ones: 6^4 = 1296 before any symmetry.
## That is exactly why the reduction works in the 2D case and does not here.
##
## Both references solve it by layering — TileMapDual ships "one display layer
## per terrain", Exonfang ships 28 tiles per terrain with unlimited adjacency —
## and `shaders/ground.gdshader` does the same thing per fragment: a material
## claims the quadrants it is present in, and the display tile is the pile of
## those in priority order.
##
## ---------------------------------------------------------------------------
## WHAT LIVES HERE AND WHAT DOES NOT. The SHADER holds the rule, because the rule
## is arithmetic and arithmetic does not need geometry — an earlier version built
## 4096 quads per chunk to say what six lines of fragment code say for free. What
## the shader cannot hold is the vocabulary and the pictures, and those are here:
## the quadrant bits, and one texture per material.
##
## Keep the bits in step with the shader. `ground tiles` in the self-check
## compares the material count on both sides, because a count that disagrees is
## every cell of the newest material drawing as tile 0.

## Bits, one per quadrant of a display tile, in the order the shader's
## `QUAD_TL/TR/BL/BR` mean them.
const MASKS := 16
const QUAD_TL := 1
const QUAD_TR := 2
const QUAD_BL := 4
const QUAD_BR := 8

## Texels per material texture. The project's own pixel unit.
const TILE := 16


static func material_count() -> int:
	return CozyTerrainMaterials.ORDER.size()


## Which of four cells carry this material, as a quadrant mask.
##
## `around` is in quadrant order — top-left, top-right, bottom-left, bottom-right
## of the display tile — which is the order the four cells around a corner are
## read in, and the order the bits mean.
static func mask_of(around: Array, material: String) -> int:
	var m := 0
	for i in mini(around.size(), 4):
		if String(around[i]) == material:
			m |= (1 << i)
	return m


## One material's texture: its colour, grained deterministically.
##
## Procedural, like the rest of the placeholder art, so a seventh material is a
## row in `CozyTerrainMaterials` and needs no file. The grain is what stops a
## large field reading as flat paint, and it is a HASH rather than a random
## number because the same world must regenerate identically after a load
## (doc #53).
static func material_image(id: String) -> Image:
	var img := Image.create(TILE, TILE, false, Image.FORMAT_RGBA8)
	var base := CozyTerrainMaterials.color_of(id)
	var h := hash(id)
	for y in TILE:
		for x in TILE:
			var n := float(absi(hash(Vector3i(x, y, h))) % 1000) / 1000.0
			var shade := 1.0 + (n - 0.5) * 0.18
			img.set_pixel(x, y, Color(
				clampf(base.r * shade, 0.0, 1.0),
				clampf(base.g * shade, 0.0, 1.0),
				clampf(base.b * shade, 0.0, 1.0),
				1.0))
	return img
