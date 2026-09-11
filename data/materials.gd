class_name CozyMaterials
extends RefCounted
## Data-driven material table (V2 doc #134, Data-Driven Design).
##
## Every building material is declared here; code only reads data.
## Adding a "magic stone wall" later means adding one row to this table —
## zero changes to the building system.
##
## This is also the ITEM vocabulary (V2.1 doc #35), which is deliberate:
##
##     "不要为建筑材料建立一套孤立库存系统."
##
##     World Item → Inventory → Construction Cost
##
## One list, so the wood a wall costs, the wood a chest holds and the wood a
## resident carries are the same wood. Food is a CATEGORY in that list, not a
## second table — a loaf is a row here for the same reason a plank is.
##
## (Terrain materials are a genuinely different domain and live in
## `CozyTerrainMaterials`: grass and soil are ground, not goods.)

## What a row IS. Only `material` rows have the geometry fields below; only
## `food` rows have `nourishment`. Asking the wrong one gets a safe default
## rather than a nonsense answer.
const KIND_MATERIAL := "material"
const KIND_FOOD := "food"

const MATERIALS := {
	"wood": {
		"name": "Wood",
		"kind": "material",
		"color": Color(0.62, 0.44, 0.26),
		"pattern": "plank",
		"block_length": 1.6,
		"block_height": 0.28,
	},
	"stone": {
		"name": "Stone",
		"kind": "material",
		"color": Color(0.56, 0.56, 0.58),
		"pattern": "flat",
		"block_length": 0.8,
		"block_height": 0.4,
	},
	"brick": {
		"name": "Brick",
		"kind": "material",
		"color": Color(0.66, 0.36, 0.30),
		"pattern": "plank",
		"block_length": 0.6,
		"block_height": 0.3,
	},
	"plaster": {
		"name": "Plaster",
		"kind": "material",
		"color": Color(0.86, 0.82, 0.72),
		"pattern": "flat",
		"block_length": 2.0,
		"block_height": 1.0,
	},
	# The first FOOD row (debt 15). Doc #114's day has 08:00 吃饭 and 12:00 午餐,
	# and until this row existed there was nothing in the world to eat: `eat` did
	# not even restore hunger, so a resident reached "critical: eat", walked to a
	# seat, and starved there for the rest of the save.
	#
	# No geometry fields: it is never a wall. `nourishment` is in the same units
	# as `hunger`, which runs 0 (fed) to 100 (starving).
	"bread": {
		"name": "Bread",
		"kind": "food",
		"color": Color(0.84, 0.68, 0.40),
		"nourishment": 45.0,
	},
}

const DEFAULT_MATERIAL := "wood"

## Texture cache: each material's texture is generated only once.
static var _tex_cache: Dictionary = {}


# ---------------------------------------------------------------- item queries

static func kind_of(id: String) -> String:
	return String(get_def(id).get("kind", KIND_MATERIAL))


static func display_name(id: String) -> String:
	return String(get_def(id).get("name", id))


## Edible? The category test lives here so no caller has to know the field name.
static func is_food(id: String) -> bool:
	return kind_of(id) == KIND_FOOD


## Hunger points one serving restores.
##
## Returns 0 for anything inedible rather than its (absent) value, so a caller
## cannot feed someone a brick by reading a default.
static func nourishment(id: String) -> float:
	if not is_food(id):
		return 0.0
	return float(get_def(id).get("nourishment", 0.0))


## Every edible item, in a fixed order — so a resident choosing what to eat makes
## the same choice every time, like everything else procedural here.
static func food_ids() -> Array:
	var out: Array = []
	for id in MATERIALS:
		if is_food(id):
			out.append(id)
	out.sort()
	return out


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


## Block dimensions for procedural wall assembly (doc 58.3 Layer 3).
## Wood reads as long planks, stone as shorter courses, plaster as big panels.
static func block_size(id: String) -> Vector2:
	var d := get_def(id)
	return Vector2(float(d.get("block_length", 0.8)), float(d.get("block_height", 0.4)))


static func get_material(id: String, uv_scale := Vector3.ONE) -> StandardMaterial3D:
	return CozyPixelArt.make_material(get_texture(id), uv_scale)
