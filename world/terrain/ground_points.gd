class_name CozyGroundPoints
extends Node3D
## Interaction points that come from the GROUND rather than from a world object.
##
## Doc #94's contract is that a thing ADVERTISES the points it can be used at, and
## until now the only things that could advertise were `CozyWorldObject`s. A tilled
## field is not an object: it is terrain — no node, no id, nothing in the save and
## nothing to initialise. So there was nowhere for a `plant` point to come from,
## and the farmer could only reap what the player had already put in the ground.
## `data/objects.gd` says so in the crop's own comment.
##
## THIS IS A POINT SOURCE AND NOTHING ELSE. It derives points from the terrain and
## answers the same `free_points_of_type()` a world object answers, so the agent's
## scan does not learn a second vocabulary. It has no behaviour, and no id.
##
## ---- derived on read, NOT cached -------------------------------------------
##
## Every answer is computed from the terrain and the object list at the moment it
## is asked. The shape is `CozyObjectDefs.available()`'s: "the same question asked
## twice at the same hour gives the same answer".
##
## That was decided after trying to place a refresh hook and finding there is no
## safe place to put one. Ten sites change terrain; the obvious funnel
## (`_rebuild_spatial_after_terrain`) is reached by four of them, and
## `_prepare_crop_ground()` — the function that creates the very field this
## depends on — is not one of the four. Three more change material without passing
## ANY funnel (`terrain.set_material_at` in a check, `terrain.from_dict` on load,
## and `_remove_target`, which deletes a crop and makes its tile sowable again).
## A cache would be correct until someone edits ground by a path nobody thought
## of, and there is no cache, so there is no such path.
##
## The cost is one lattice walk per query, and the lattice is coarse: see `TILE`.
## What keeps it cheap is that most chunks hold no farmland at all and are skipped
## by a single flag (see below).

## The SAME array `main.gd` owns, by reference. READ, NEVER WRITTEN — and never
## appended to. `objects` is `Array[CozyWorldObject]`, so folding a point source
## into it is a runtime error; and even if it were not, `_outdoor_obstacles`,
## `_obstacles_on_floor`, `_grow_the_world`, `_larder_food`, `_first_object` and
## the save's entity list all iterate it assuming a world object. A separate
## source is the only correct shape here, not a convenience.
var objects: Array = []

var terrain: CozyTerrainSystem = null


## A sow point is one CROP-SIZED square of bare ground, not one terrain cell.
##
## The terrain grid is 0.25 m and a crop is 1 m across, so a per-cell rule would
## offer sixteen overlapping points per plantable spot. The size comes from the
## thing being planted rather than from this file — `_tile_size()` reads it off the
## definition, so a 2 x 2 m crop gets 2 m squares without anything here changing.
const DEFAULT_TILE := 1.0


## What the ground can be asked for, from the recipes rather than from a constant:
## a point type belongs here exactly when some recipe SPAWNS something at it.
##
## Hardcoding `"plant"` would work today and would be a second copy of a fact the
## recipe table already holds — the shape this project has paid for seven times.
static func offers() -> Array[String]:
	return CozyRecipeDefs.ground_point_types()


## Which object a point of this type produces, or "" when the type is not worked
## on the ground. The ground rule is asked about THAT object, so "what may be
## planted here" is answered by `CozyObjectDefs.ground_problem` and never by a
## material name repeated in this file (INVARIANTS: "A rule that lives only in a
## mouse handler is not a rule").
static func spawn_for(point_type: String) -> String:
	return CozyRecipeDefs.spawn_for_point(point_type)


## The skill work at this point trains, or "" when the ground offers no such
## point. Read off the planted thing's own interaction row, so a slower or
## differently-skilled crop is a row rather than a change here.
##
## Public because the AGENT needs it: a resident decides what they are willing to
## do by asking what skill the work trains (doc §10's aversion), and for `plant`
## the answer exists nowhere else — no object offers that point.
static func skill_for(point_type: String) -> String:
	var spawn_def := spawn_for(point_type)
	return "" if spawn_def == "" else _skill_of(spawn_def)


## Every free point of `t` on the ground, right now.
##
## Freshly built per call, which is the whole design — and it has one honest
## limitation: **a derived point cannot be reserved.** `occupy()` writes to an
## object that is thrown away when this call returns, so `is_free()` is always
## true and `_arrive()`'s "spot taken" check can never fire for ground work. With
## one resident that is unobservable; with two, both would walk to the same tile
## and neither would find it taken. Making the ground reservable means keeping the
## points alive between calls, which is exactly the cache this file exists
## without. Recorded rather than hidden; it belongs with "reserve on take" in the
## work-priority research.
func free_points_of_type(t: String) -> Array[CozyInteractionPoint]:
	var out: Array[CozyInteractionPoint] = []
	var spawn_def := spawn_for(t)
	if spawn_def == "" or terrain == null:
		return out
	for pos in plan(_area(), _tile_size(), _material_at, _height_at, spawn_def, _blockers(spawn_def)):
		out.append(CozyInteractionPoint.new(t, pos, _skill_of(spawn_def), _duration_of(spawn_def)))
	return out


# ---------------------------------------------------------------- derivation

## THE PURE PART: which squares of ground are worth offering a point at.
##
## Pure so it can be asserted without a world — the terrain arrives as two
## `Callable`s and the things already standing there as rectangles. That is the
## same reason `CozyObjectDefs.available()` takes `now` as an argument.
##
## `area` is in world XZ (y is the height axis). The lattice is aligned to the
## WORLD ORIGIN rather than to the terrain's, so a field's points do not move when
## the terrain is placed somewhere else.
##
## A square qualifies when all four corners AND the centre are ground the spawned
## definition accepts — stricter than `_place_object`, which asks only about the
## centre. Strict is the safe direction: a crop hanging off the edge of a field
## looks like a bug and the placement rule would not have caught it.
static func plan(area: Rect2, tile: float, material_at: Callable, height_at: Callable,
		spawn_def: String, blockers: Array[Rect2]) -> Array[Vector3]:
	var out: Array[Vector3] = []
	if tile <= 0.0 or spawn_def == "" or not CozyObjectDefs.exists(spawn_def):
		return out

	var start_x := floorf(area.position.x / tile) * tile
	var start_z := floorf(area.position.y / tile) * tile
	var cols := int(floorf((area.end.x - start_x) / tile))
	var rows := int(floorf((area.end.y - start_z) / tile))

	for gz in rows:
		for gx in cols:
			var x0 := start_x + float(gx) * tile
			var z0 := start_z + float(gz) * tile
			var rect := Rect2(x0, z0, tile, tile)

			var clash := false
			for b in blockers:
				if b.intersects(rect):
					clash = true
					break
			if clash:
				continue
			if not _ground_accepts(spawn_def, material_at, rect):
				continue

			var c := rect.get_center()
			out.append(Vector3(c.x, float(height_at.call(c.x, c.y)), c.y))
	return out


## The four corners and the centre, all of them ground the spawn accepts.
##
## THE RULE IS ASKED ONCE PER DISTINCT MATERIAL, not once per probe. `ground_problem`
## builds a human-readable refusal string — a `join`, a lookup and a format — and
## the lattice probes five points on each of 4096 tiles: measured at 45 ms per
## derivation, which is far too slow for something a resident asks for whenever it
## looks for work. Materials are six ids, so memoising turns 20,480 string builds
## into at most six.
##
## The memo is LOCAL to the call rather than a member: a cache that outlives the
## call is the thing this file exists without (see the header), and six strings
## per query is not worth a staleness risk.
static func _ground_accepts(spawn_def: String, material_at: Callable, rect: Rect2) -> bool:
	var verdicts := {}          # material id -> bool
	var probes: Array[Vector2] = [
		rect.position,
		Vector2(rect.end.x, rect.position.y),
		rect.end,
		Vector2(rect.position.x, rect.end.y),
		rect.get_center(),
	]
	for p in probes:
		var material := String(material_at.call(p.x, p.y))
		if not verdicts.has(material):
			verdicts[material] = CozyObjectDefs.ground_problem(spawn_def, material) == ""
		if not bool(verdicts[material]):
			return false
	return true


## What already stands in the way, as rectangles: each object's footprint grown by
## the spawn's own REACH.
##
## The growth is the point of this function. A crop's interaction point sits
## `reach` metres out from its own footprint (`_make_points`: `size.y * 0.5 + reach`
## in local z), so a new crop one tile away from an old one can put its own point
## inside the old one's body — and then the existing assertion that every offered
## point is standable goes red for a reason that looks like a navigation fault and
## is not. Growing by `reach` on all four sides keeps both bodies and both points
## clear, in every direction.
##
## GROWING ON ALL FOUR SIDES IS DELIBERATELY CONSERVATIVE, and the reason is the
## one `_outdoor_obstacles` gives for over-blocking walls: "an agent walking a
## slightly longer way is a nuisance, an agent walking through a wall is a defect".
## Fewer sow points is a nuisance; two crops in one square is a defect.
func _blockers(spawn_def: String) -> Array[Rect2]:
	var out: Array[Rect2] = []
	var reach := _reach_of(spawn_def)
	for o in objects:
		if is_instance_valid(o) and o.has_method("footprint_rect"):
			out.append(o.footprint_rect().grow(reach))
	return out


func _area() -> Rect2:
	return Rect2(terrain.origin, Vector2(terrain.width_m, terrain.depth_m))


func _material_at(x: float, z: float) -> String:
	return terrain.material_id_at(x, z)


func _height_at(x: float, z: float) -> float:
	return terrain.height_at(x, z)


## The planted thing's own footprint decides how big a sow square is — after
## whichever axis is larger, so a non-square crop still gets a square of ground.
static func _tile_size() -> float:
	var spawn_def := _first_spawn()
	if spawn_def == "":
		return DEFAULT_TILE
	var size: Vector2 = CozyObjectDefs.get_def(spawn_def).get("size", Vector2.ONE)
	return maxf(size.x, size.y)


static func _first_spawn() -> String:
	for t in offers():
		return spawn_for(t)
	return ""


## The planted thing's first interaction: its reach, its duration and the skill
## the work trains. Read from the definition rather than repeated here, so a
## slower or different crop is a row.
static func _first_interaction(spawn_def: String) -> Dictionary:
	var rows: Array = CozyObjectDefs.get_def(spawn_def).get("interactions", [])
	return rows[0] if not rows.is_empty() else {}


static func _reach_of(spawn_def: String) -> float:
	return float(_first_interaction(spawn_def).get("reach", 0.0))


static func _duration_of(spawn_def: String) -> float:
	return float(_first_interaction(spawn_def).get("duration", 4.0))


static func _skill_of(spawn_def: String) -> String:
	return String(_first_interaction(spawn_def).get("skill", ""))
