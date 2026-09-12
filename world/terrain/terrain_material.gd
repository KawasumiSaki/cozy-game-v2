class_name CozyTerrainMaterials
extends RefCounted
## Data-driven terrain material table (V2.1 doc #7).
##
## The doc is explicit: "材料不要写死在 TerrainSystem 中." Everything a terrain
## material means — how hard it is to dig, whether it can carry a building,
## whether it burns — is declared here and read by the systems.
##
## Adding MAGIC_SOIL or CORRUPTED_GROUND for the Veil later means adding a row
## to this table (doc #3.1), not editing the terrain system.

const MATERIALS := {
	"grass": {
		"display_name": "Grass",
		"color": Color(0.42, 0.70, 0.33),
		"hardness": 0.1,
		"buildable_default": false,
		"fertility": 0.7,
		"default_buildability": "natural",
		"tags": ["natural", "vegetation"],
	},
	"soil": {
		"display_name": "Soil",
		"color": Color(0.45, 0.33, 0.22),
		"hardness": 0.2,
		"buildable_default": true,
		"fertility": 0.9,
		"default_buildability": "buildable",
		"tags": ["natural", "diggable", "buildable_candidate"],
	},
	"sand": {
		"display_name": "Sand",
		"color": Color(0.82, 0.74, 0.52),
		"hardness": 0.1,
		"buildable_default": false,
		"fertility": 0.1,
		"default_buildability": "restricted",
		"tags": ["natural", "loose"],
	},
	"stone": {
		"display_name": "Stone",
		"color": Color(0.52, 0.52, 0.54),
		"hardness": 0.8,
		"buildable_default": true,
		"fertility": 0.0,
		"default_buildability": "buildable",
		"tags": ["natural", "solid"],
	},
	"water": {
		"display_name": "Water",
		"color": Color(0.24, 0.46, 0.72),
		"hardness": 0.0,
		"buildable_default": false,
		"fertility": 0.0,
		"default_buildability": "restricted",
		"tags": ["natural", "liquid"],
	},
	"farmland": {
		"display_name": "Farmland",
		"color": Color(0.36, 0.24, 0.15),
		"hardness": 0.15,
		# NOT buildable, and that is the point: you do not drop a wall onto a crop
		# field. Fill it back to soil first. The material's own default carries the
		# rule — `set_material` reads it, so no extra code is involved.
		"buildable_default": false,
		"fertility": 1.0,
		"default_buildability": "natural",
		"tags": ["natural", "cultivated", "farmable"],
	},
}

## Fixed storage order. Chunk cell arrays store INDICES into this list rather
## than strings — a PackedInt32Array per chunk instead of thousands of Strings.
##
## ⚠️ APPEND ONLY. A saved chunk stores indices, so inserting a material in the
## middle silently re-labels every existing cell: `stone` would read back as
## whatever moved into slot 3. New materials go on the END.
const ORDER: Array[String] = ["grass", "soil", "sand", "stone", "water", "farmland"]

const DEFAULT := "grass"


static func index_of(id: String) -> int:
	var i := ORDER.find(id)
	return i if i >= 0 else ORDER.find(DEFAULT)


static func id_of(index: int) -> String:
	if index < 0 or index >= ORDER.size():
		return DEFAULT
	return ORDER[index]


static func def(id: String) -> Dictionary:
	return MATERIALS.get(id, MATERIALS[DEFAULT])


static func color_of(id: String) -> Color:
	return def(id).get("color", Color.MAGENTA)


static func is_buildable_by_default(id: String) -> bool:
	return bool(def(id).get("buildable_default", false))


## The buildability a freshly generated cell of this material starts at
## (doc #11). Data-driven, so adding CORRUPTED_GROUND later needs no code change.
static func default_buildability(id: String) -> int:
	return CozyBuildability.from_name(String(def(id).get("default_buildability", "natural")))


static func exists(id: String) -> bool:
	return MATERIALS.has(id)
