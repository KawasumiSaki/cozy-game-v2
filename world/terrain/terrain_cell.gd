class_name CozyTerrainCell
extends RefCounted
## The terrain cell shape from V2.1 doc #6, as a VALUE object.
##
## Chunks do NOT store one of these per cell — see CozyTerrainChunk for the
## storage note. This is the shape the API speaks in and the shape a save file
## records, so the doc's data model is still what callers see.
##
## V1 only needs material_id / height / buildability (doc #6). The rest are
## extension points, present so they do not have to be retrofitted later.

var material_id := CozyTerrainMaterials.DEFAULT
var height := 0.0
var moisture := 0.0
var fertility := 0.0
var temperature := 0.0
var buildability := CozyBuildability.NATURAL
var flags := 0


static func create(p_material := CozyTerrainMaterials.DEFAULT, p_height := 0.0) -> CozyTerrainCell:
	var c := CozyTerrainCell.new()
	c.material_id = p_material
	c.height = p_height
	c.buildability = CozyTerrainMaterials.default_buildability(p_material)
	c.fertility = float(CozyTerrainMaterials.def(p_material).get("fertility", 0.0))
	return c


func is_buildable() -> bool:
	return CozyBuildability.accepts_building(buildability)


func describe() -> String:
	return "%s h=%.2f %s" % [
		material_id, height, CozyBuildability.name_of(buildability)]


func to_dict() -> Dictionary:
	return {
		"material_id": material_id,
		"height": height,
		"buildability": CozyBuildability.name_of(buildability),
	}


static func from_dict(d: Dictionary) -> CozyTerrainCell:
	var c := CozyTerrainCell.new()
	c.material_id = String(d.get("material_id", CozyTerrainMaterials.DEFAULT))
	c.height = float(d.get("height", 0.0))
	c.buildability = CozyBuildability.from_name(
		String(d.get("buildability", "natural")))
	return c
