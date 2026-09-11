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
	"tree": {
		"asset_id": "tree_oak_01",
		"base_density": 0.17,
		# Trees belong to the woodland region and are essentially absent
		# elsewhere — a lone tree on open grassland should be an event.
		"biomes": {"forest_edge": 1.0, "grassland": 0.015, "village": 0.0,
			"shore": 0.0, "rocky": 0.0},
		"materials": {"grass": 1.0, "soil": 0.6, "sand": 0.0, "stone": 0.0, "water": 0.0},
		# doc E.20.2 — "建筑周围不应出现：厚草 / 大石头 / 大树". Not a thinning
		# factor but an absolute: zero means zero.
		"near_building": 0.0,
		"scale": [0.85, 1.25],
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


## Flatten a rule's tables once, so a hot loop does not re-do dictionary
## lookups for every candidate. Purely a cache — it changes no behaviour.
static func resolve(rule_id: String) -> Dictionary:
	var r := get_rule(rule_id)
	if r.is_empty():
		return {}
	return {
		"id": rule_id,
		"asset_id": r["asset_id"],
		"biomes": r["biomes"],
		"materials": r["materials"],
		"base_density": float(r["base_density"]),
		"near_building": float(r["near_building"]),
		"scale_lo": float(r["scale"][0]),
		"scale_hi": float(r["scale"][1]),
	}


## The deterministic half of E.20.1 — everything except the random term.
##
## Split out from the roll on purpose: this is the part that carries meaning
## ("density here is 0.42, and zero on sand") and it can be asserted directly,
## where a probability that already has noise baked in cannot.
##
## The formula lives HERE and only here. The by-id and by-resolved entry points
## both funnel through it, because two copies of a density rule will drift.
static func base_probability_resolved(res: Dictionary, biome: String,
		material: String, near_building: bool) -> float:
	if res.is_empty():
		return 0.0
	var p: float = res["base_density"]
	p *= float(res["biomes"].get(biome, 0.0))
	p *= float(res["materials"].get(material, 0.0))
	if near_building:
		p *= float(res["near_building"])
	return clampf(p, 0.0, 1.0)


static func base_probability(rule_id: String, biome: String, material: String,
		near_building: bool) -> float:
	return base_probability_resolved(resolve(rule_id), biome, material, near_building)


## Does this rule spawn at this cell?
## `seed_val` must come from CozyArtSeed — never from a random source, or the
## world rearranges itself across a save and reload (doc E.21).
static func spawns(rule_id: String, biome: String, material: String,
		near_building: bool, seed_val: int) -> bool:
	return CozyArtSeed.unit(seed_val) \
		< base_probability(rule_id, biome, material, near_building)


static func spawns_resolved(res: Dictionary, biome: String, material: String,
		near_building: bool, seed_val: int) -> bool:
	return CozyArtSeed.unit(seed_val) \
		< base_probability_resolved(res, biome, material, near_building)
