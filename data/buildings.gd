class_name CozyBuildingDefs
extends RefCounted
## Data-driven building definitions (V2.1 doc #36).
##
## The doc's rule about cost is geometric, not arbitrary:
##
##     "建造成本必须与几何结构绑定"
##
## A 8 x 3 x 0.3 m wall is 7.2 m3 of material, and the definition converts that
## volume into resources. The doc explicitly warns against inventing a fixed
## "1 m3 = 100 units" ratio in code — the conversion belongs in the definition,
## which is what this table is.
##
## Adding a new wall material is a row here, and the building system, the cost
## calculation and the inventory all pick it up unchanged (doc #139).

const WALLS := {
	"wood": {
		"id": "wood_wall",
		"category": "wall",
		"material": "wood",
		"base_cost": {"wood": 2.0},
		"cost_per_m3": {"wood": 6.0},
		"terrain_requirements": ["buildable"],
	},
	"stone": {
		"id": "stone_wall",
		"category": "wall",
		"material": "stone",
		"base_cost": {"stone": 3.0},
		"cost_per_m3": {"stone": 8.0},
		"terrain_requirements": ["buildable"],
	},
	"brick": {
		"id": "brick_wall",
		"category": "wall",
		"material": "brick",
		"base_cost": {"brick": 3.0, "stone": 1.0},
		"cost_per_m3": {"brick": 7.0},
		"terrain_requirements": ["buildable"],
	},
	"plaster": {
		"id": "plaster_wall",
		"category": "wall",
		"material": "plaster",
		"base_cost": {"plaster": 1.0},
		"cost_per_m3": {"plaster": 6.0},
		"terrain_requirements": ["buildable"],
	},
}

const DEFAULT_WALL := "wood"


static func wall_def(material_id: String) -> Dictionary:
	return WALLS.get(material_id, WALLS[DEFAULT_WALL])


## Volume (m3) -> {resource: amount}. Base cost is charged once, the per-m3
## rate scales with the geometry.
static func cost_for(material_id: String, volume_m3: float) -> Dictionary:
	var d := wall_def(material_id)
	var out := {}
	for res in d.get("base_cost", {}):
		out[res] = out.get(res, 0.0) + float(d["base_cost"][res])
	for res in d.get("cost_per_m3", {}):
		out[res] = out.get(res, 0.0) + float(d["cost_per_m3"][res]) * volume_m3
	# Whole units — the doc's numbers are resources, not fractions of one.
	for res in out:
		out[res] = ceilf(out[res])
	return out


static func describe_cost(costs: Dictionary) -> String:
	var parts: Array[String] = []
	var keys: Array = costs.keys()
	keys.sort()
	for k in keys:
		parts.append("%s x%d" % [k, int(costs[k])])
	return ", ".join(parts) if not parts.is_empty() else "free"
