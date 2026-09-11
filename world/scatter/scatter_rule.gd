class_name CozyScatterRule
extends RefCounted
## Scatter rules (V2.1 doc E.20).
##
## Scatter is not pure randomness:
##
##     "Scatter 不是纯随机，而是：Terrain Material + Biome + Slope + Moisture
##      + Fertility + Distance to Road + Distance to Building + Seed"
##
##     SpawnProbability = BaseDensity x BiomeMultiplier x TerrainMultiplier
##                      x SlopeMultiplier x DistanceMultiplier x Random(seed)
##
## The doc also fixes the two edge cases that make a world look designed rather
## than sprinkled (E.20.2 / E.20.3):
##
##   - near a building: NO thick grass, big rocks or big trees. Small grass, mud,
##     chips instead — ground people walk on.
##   - road edges: grass thins ON the road and thickens AT its edge, with more
##     pebbles and dirt. That is what produces a natural verge instead of a
##     painted stripe.
##
## Rules are data. Adding a mushroom later is a row here.

const RULES := {
	"grass_tuft": {
		"asset_id": "grass_tuft_01",
		"base_density": 0.42,
		"biomes": {"grassland": 1.0, "forest_edge": 1.0, "village": 0.45,
			"shore": 0.25, "rocky": 0.0},
		"materials": {"grass": 1.0, "soil": 0.45, "sand": 0.0, "stone": 0.0, "water": 0.0},
		"near_building": 0.4,
		"scale": [0.7, 1.3],
	},
	"flower_daisy": {
		"asset_id": "flower_daisy_01",
		"base_density": 0.10,
		"biomes": {"grassland": 1.0, "forest_edge": 0.5, "village": 0.6,
			"shore": 0.0, "rocky": 0.0},
		"materials": {"grass": 1.0, "soil": 0.0, "sand": 0.0, "stone": 0.0, "water": 0.0},
		"near_building": 0.5,
		"scale": [0.8, 1.1],
	},
	"pebble": {
		"asset_id": "rock_small_01",
		"base_density": 0.14,
		"biomes": {"grassland": 0.35, "forest_edge": 0.6, "village": 0.5,
			"shore": 1.0, "rocky": 1.0},
		"materials": {"grass": 0.3, "soil": 0.7, "sand": 1.0, "stone": 1.0, "water": 0.0},
		"near_building": 0.6,
		"scale": [0.6, 1.0],
	},
}

## Ground people walk on may not sprout these (doc E.20.2).
const TALL := ["grass_tuft_thick", "tree", "rock_large"]


static func ids() -> Array:
	var out: Array = RULES.keys()
	out.sort()
	return out


static func get_rule(id: String) -> Dictionary:
	return RULES.get(id, {})


## The deterministic half of E.20.1 — everything except the random term.
##
## Split out from the roll on purpose: this is the part that carries meaning
## ("density here is 0.42, and zero on sand") and it can be asserted directly,
## where a probability that already has noise baked in cannot.
static func base_probability(rule_id: String, biome: String, material: String,
		near_building: bool) -> float:
	var r := get_rule(rule_id)
	if r.is_empty():
		return 0.0

	var p: float = r["base_density"]
	p *= float(r["biomes"].get(biome, 0.0))
	p *= float(r["materials"].get(material, 0.0))
	if near_building:
		p *= float(r["near_building"])
	return clampf(p, 0.0, 1.0)


## Does this rule spawn at this cell?
## `seed_val` must come from CozyArtSeed — never from a random source, or the
## world rearranges itself across a save and reload (doc E.21).
static func spawns(rule_id: String, biome: String, material: String,
		near_building: bool, seed_val: int) -> bool:
	var p := base_probability(rule_id, biome, material, near_building)
	return CozyArtSeed.unit(seed_val) < p
