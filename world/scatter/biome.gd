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


## `building_points` are world positions of built things (wall midpoints,
## furniture). Positions rather than nodes because a wall's node sits at the
## origin — its geometry is baked into vertices, so `global_position` would say
## every wall is at (0,0,0).
static func classify(terrain: CozyTerrainSystem, building_points: Array,
		x: float, z: float) -> String:
	# Water in reach -> shore. Checked on a small cross so a single water cell
	# does not turn its whole neighbourhood into coastline.
	if _near_water(terrain, x, z):
		return SHORE

	var material := terrain.material_id_at(x, z)
	if material == "stone" or material == "sand":
		return ROCKY

	if _near_building(building_points, x, z):
		return VILLAGE

	# Grass that is not near anything built reads as open grassland. Forest edge
	# is reserved for ground the terrain actually marks as wooded — which today
	# is nothing, because there are no trees. Stated rather than faked.
	return GRASSLAND


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
