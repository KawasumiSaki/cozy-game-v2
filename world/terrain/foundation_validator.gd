class_name CozyFoundationValidator
extends RefCounted
## Building placements must ask the terrain for permission (V2.1 doc #12).
##
## The doc's framing is the reason the terrain phase had to come before real
## building: a building is no longer allowed to appear anywhere. It has to be
## supported by ground that has been made ready.
##
##     Natural Terrain -> Modification -> Buildable Mask
##                     -> Foundation Validation -> Building Intent -> Building
##
## Results mirror the doc's list, minus the two support variants that need a
## real foundation solver (level / stepped / column foundations, doc #13):
##
##     VALID                  ground is ready as-is
##     VALID_WITH_FOUNDATION  ground is right but uneven; a foundation would fix it
##     INVALID                something fundamental is wrong
##
## The rejection carries a REASON, because doc #72 requires it:
## "不允许建筑时有明确原因."

enum Result { VALID, VALID_WITH_FOUNDATION, INVALID }

## Height difference across a footprint that no longer counts as level.
const LEVEL_TOLERANCE := 0.35


static func result_name(r: int) -> String:
	match r:
		Result.VALID:
			return "valid"
		Result.VALID_WITH_FOUNDATION:
			return "valid_with_foundation"
		_:
			return "invalid"


## Sample the footprint on the terrain's own grid and report what is wrong.
## Returns { result, reason, cells, min_height, max_height }.
static func validate(terrain: CozyTerrainSystem, footprint: Rect2) -> Dictionary:
	var step := CozyTerrainSystem.CELL_SIZE
	var min_h := INF
	var max_h := -INF
	var sampled := 0
	var bad_reason := ""

	var x := footprint.position.x + step * 0.5
	while x < footprint.position.x + footprint.size.x:
		var z := footprint.position.y + step * 0.5
		while z < footprint.position.y + footprint.size.y:
			var b := terrain.buildability_at(x, z)
			var m := terrain.material_id_at(x, z)

			if bad_reason == "" and not CozyBuildability.accepts_building(b):
				bad_reason = "%.0f,%.0f is %s (%s)" % [
					x, z, CozyBuildability.name_of(b), m]

			var h := terrain.height_at(x, z)
			min_h = minf(min_h, h)
			max_h = maxf(max_h, h)
			sampled += 1
			z += step
		x += step

	if sampled == 0:
		return {"result": Result.INVALID, "reason": "footprint samples no terrain",
			"cells": 0, "min_height": 0.0, "max_height": 0.0}

	if bad_reason != "":
		return {"result": Result.INVALID, "reason": bad_reason,
			"cells": sampled, "min_height": min_h, "max_height": max_h}

	var drop := max_h - min_h
	if drop > LEVEL_TOLERANCE:
		# Ground is the right kind, just not level. That is what foundations are
		# for (doc #13); doing it properly is a later block, so this reports the
		# situation rather than pretending the ground is fine.
		return {"result": Result.VALID_WITH_FOUNDATION,
			"reason": "uneven by %.2f m" % drop,
			"cells": sampled, "min_height": min_h, "max_height": max_h}

	return {"result": Result.VALID, "reason": "",
		"cells": sampled, "min_height": min_h, "max_height": max_h}
