class_name CozyMaterials
extends RefCounted
## Data-driven material table (V2 doc #134, Data-Driven Design).
##
## Every building material is declared here; code only reads data.
## Adding a "magic stone wall" later means adding one row to this table —
## zero changes to the building system.

const MATERIALS := {
	"wood": {
		"name": "Wood",
		"color": Color(0.62, 0.44, 0.26),
		"pattern": "plank",
	},
	"stone": {
		"name": "Stone",
		"color": Color(0.56, 0.56, 0.58),
		"pattern": "flat",
	},
	"brick": {
		"name": "Brick",
		"color": Color(0.66, 0.36, 0.30),
		"pattern": "plank",
	},
	"plaster": {
		"name": "Plaster",
		"color": Color(0.86, 0.82, 0.72),
		"pattern": "flat",
	},
}

const DEFAULT_MATERIAL := "wood"

## Texture cache: each material's texture is generated only once.
static var _tex_cache: Dictionary = {}


static func get_def(id: String) -> Dictionary:
	if MATERIALS.has(id):
		return MATERIALS[id]
	return MATERIALS[DEFAULT_MATERIAL]


static func get_texture(id: String) -> ImageTexture:
	if _tex_cache.has(id):
		return _tex_cache[id]
	var def := get_def(id)
	var tex: ImageTexture
	if def["pattern"] == "plank":
		tex = CozyPixelArt.make_plank_texture(16, def["color"], hash(id))
	else:
		tex = CozyPixelArt.make_texture(16, def["color"], 0.04, hash(id))
	_tex_cache[id] = tex
	return tex


static func get_material(id: String, uv_scale := Vector3.ONE) -> StandardMaterial3D:
	return CozyPixelArt.make_material(get_texture(id), uv_scale)
