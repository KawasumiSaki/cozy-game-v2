class_name CozyBiome
extends RefCounted
## Biome classification (V2.1 doc E.19).
##
## The doc makes biomes the query key for scatter — "这个东西能不能放在水边？
## 能不能生成在道路旁？是不是森林植物？是不是只能出现在魔域？"
##
## Biomes here are DERIVED, never stored. They follow from material and
## proximity, so they need no save entry and no generation pass: recomputing
## them from world facts is cheaper than storing them and cannot drift out of
## sync with the terrain (doc §67 — save facts, not derived cache).
##
## That also means a biome changes the instant the ground under it changes,
## which is the behaviour the whole terrain phase was built for.

const GRASSLAND := "grassland"
const FOREST_EDGE := "forest_edge"
const VILLAGE := "village"
const SHORE := "shore"
const ROCKY := "rocky"

const ALL: Array[String] = [GRASSLAND, FOREST_EDGE, VILLAGE, SHORE, ROCKY]

## How close a building has to be before ground counts as village.
const VILLAGE_RADIUS := 7.0

## How far water's influence reaches for shore.
const SHORE_REACH := 2.5

## Woodland is a REGION, not a per-cell roll: a value-noise field decides where
## forest exists at all, and trees then scatter densely inside it. Per-cell
## scatter alone can only ever produce denser speckle, never a forest.
const FOREST_SCALE := 17.0
const FOREST_THRESHOLD := 0.60


## `building_points` are world positions of built things (wall midpoints,
## furniture). Positions rather than nodes because a wall's node sits at the
## origin — its geometry is baked into vertices, so `global_position` would say
## every wall is at (0,0,0).
## `any_water` is the caller's answer to "does this world contain water at all".
## Passed in rather than looked up per call, because the shore test probes five
## neighbours per sample point and in a world with no water that is five lookups
## per point spent proving a negative — measured at the dominant cost of a
## scatter rebuild.
static func classify(terrain: CozyTerrainSystem, building_points: Array,
		x: float, z: float, world_seed := 0, any_water := true) -> String:
	# Water in reach -> shore. Checked on a small cross so a single water cell
	# does not turn its whole neighbourhood into coastline.
	if any_water and _near_water(terrain, x, z):
		return SHORE

	var material := terrain.material_id_at(x, z)
	if material == "stone" or material == "sand":
		return ROCKY

	# Woodland is decided by a region field, before anything built is considered
	# — a forest does not stop being a forest because a house is nearby.
	if is_woodland(x, z, world_seed):
		return FOREST_EDGE

	if _near_building(building_points, x, z):
		return VILLAGE

	return GRASSLAND


## Is this point inside the woodland region? Deterministic from the world seed
## (doc E.21), so the forest is in the same place after a save and reload.
static func is_woodland(x: float, z: float, world_seed: int) -> bool:
	if world_seed == 0:
		return false
	return CozyArtSeed.value_noise(x, z, FOREST_SCALE, world_seed) > FOREST_THRESHOLD


static func _near_water(terrain: CozyTerrainSystem, x: float, z: float) -> bool:
	for d in [Vector2.ZERO, Vector2(SHORE_REACH, 0.0), Vector2(-SHORE_REACH, 0.0),
			Vector2(0.0, SHORE_REACH), Vector2(0.0, -SHORE_REACH)]:
		if terrain.material_id_at(x + d.x, z + d.y) == "water":
			return true
	return false


static func _near_building(points: Array, x: float, z: float) -> bool:
	var r2 := VILLAGE_RADIUS * VILLAGE_RADIUS
	for p in points:
		var v: Vector3 = p
		var dx := v.x - x
		var dz := v.z - z
		if dx * dx + dz * dz <= r2:
			return true
	return false


## Terrain-only classification, for when no building list is available.
static func classify_terrain_only(terrain: CozyTerrainSystem, x: float, z: float) -> String:
	return classify(terrain, [], x, z)
