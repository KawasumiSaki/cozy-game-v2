class_name CozyStairState
extends RefCounted
## Pure data for one staircase (doc #18 / #30 StairSystem).
##
## Doc #30 fixes three things a stair must have, and each of them is a bug this
## project already hit:
##
##     Low-end entry   — the collider is a tilted slab, so from the side it is a
##                       vertical wall; a stair must be entered from its foot.
##     Landing         — arriving at full height with nothing to stand on means
##                       stepping off into space.
##     Floor-level exit— a ramp that tops out below floor level leaves a lip.
##
## So a stair is not "a ramp": it is a ramp plus where it starts, where it ends,
## and which floors those are.

var id := ""
var start := Vector3.ZERO      ## Foot of the stair, at the lower floor.
var end := Vector3.ZERO        ## Head of the stair, at floor level above.
var width := 3.0
var floor_from := 0
var floor_to := 1
var material_id := "wood"

## Number of visual steps; the collider is a single slope regardless.
var steps := 8

var seed_val := 0


static func create(p_id: String, p_start: Vector3, p_end: Vector3,
		p_width := 3.0, p_material := "wood") -> CozyStairState:
	var s := CozyStairState.new()
	s.id = p_id
	s.start = p_start
	s.end = p_end
	s.width = p_width
	s.material_id = p_material
	s.seed_val = hash(p_id)
	return s


func rise() -> float:
	return end.y - start.y


## Horizontal run, in the ground plane.
func run() -> float:
	return Vector2(end.x - start.x, end.z - start.z).length()


## Slope in radians. Doc #30's landing rule is what keeps this under an agent's
## floor_max_angle; a stair steeper than that is climbed by nobody.
func slope_angle() -> float:
	var r := run()
	if r < 0.0001:
		return PI * 0.5
	return atan2(rise(), r)


func floor_span() -> String:
	return "%d -> %d" % [floor_from, floor_to]


func describe() -> String:
	return "%s (%.1f m run, %.1f m rise, %.1f deg)" % [
		id, run(), rise(), rad_to_deg(slope_angle())]
