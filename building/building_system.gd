class_name CozyBuildingSystem
extends Node3D
## Owns BuildingState and regenerates the view from it (V2.1 doc #70).
##
## This is the ONLY place in the codebase permitted to create wall nodes. Every
## other system submits an Intent and reads back derived facts — that is what
## keeps doc #70's dependency direction intact:
##
##     UI -> Intent -> State -> Rules/Solver -> Generator -> Runtime Nodes
##
## Regeneration is incremental (doc #32 / #33): a change marks the walls it
## actually touched, and only those views are rebuilt. "One local edit triggers
## a world rebuild" is on the doc's forbidden list.

signal structure_changed

var state := CozyBuildingState.new()
var wall_views: Array[CozyWall] = []

## Optional terrain gate (doc #12). When set, a DRAW_WALL intent must be
## approved by the ground before it may change state. The rule lives HERE, not
## in the UI — doc #70 puts rules and solvers between State and Generator, and
## a placement rule that only exists in a mouse handler is not a rule.
var terrain: CozyTerrainSystem = null

## Why the last intent was refused, for the UI to surface. Doc #72 requires an
## explicit reason: "不允许建筑时有明确原因."
var last_rejection := ""

var _view_root: Node3D = null


func setup(p_view_root: Node3D) -> void:
	_view_root = p_view_root


# ---------------------------------------------------------------- intent entry

## Submit an edit. Returns the wall it touched, or null when a rule rejected it.
func submit(intent: CozyBuildingIntent) -> CozyWallState:
	return submit_many([intent])


## Submit several edits, then regenerate once. Startup builds a whole house this
## way; regenerating after every wall would rebuild the view repeatedly for no
## benefit, since the connection solver only settles once all walls exist.
func submit_many(intents: Array) -> CozyWallState:
	var touched: Array[String] = []
	var result: CozyWallState = null

	for intent in intents:
		match intent.kind:
			CozyBuildingIntent.Kind.DRAW_WALL:
				if not _ground_approves(intent):
					continue
				result = state.add_wall(intent.a, intent.b, intent.height,
					intent.thickness, intent.material_id, intent.floor_id)
				for o in intent.openings:
					result.add_opening(o)
				touched.append(result.id)

			CozyBuildingIntent.Kind.REMOVE_WALL:
				state.remove_wall(intent.wall_id)

			CozyBuildingIntent.Kind.ADD_OPENING:
				var w := state.wall(intent.wall_id)
				if w != null and intent.opening != null:
					w.add_opening(intent.opening)
					touched.append(w.id)

	regenerate(touched)
	return result


## State -> Solver -> Generator -> Runtime nodes (doc #70).
##
## `seed_ids` names the walls the caller knows changed. The connection solver
## may touch neighbours too (a new wall creates a junction on the wall it meets),
## so it reports back everything it modified and those get rebuilt as well.
func regenerate(seed_ids: Array[String] = [], skip_solve := false) -> void:
	var dirty := {}
	if skip_solve:
		# Used by the self-check to inspect geometry with the solver switched
		# off, so it can prove the solver is what changes the corner.
		for ws in state.walls:
			dirty[ws.id] = true
	else:
		for id in seed_ids:
			dirty[id] = true
		for id in CozyWallSolver.solve_states(state.walls):
			dirty[id] = true

	_sync_views(dirty)
	structure_changed.emit()


## Create, refresh or retire views so the scene matches the state.
func _sync_views(dirty: Dictionary) -> void:
	# Retire views whose state is gone.
	var alive := {}
	for ws in state.walls:
		alive[ws.id] = true
	for i in range(wall_views.size() - 1, -1, -1):
		var v := wall_views[i]
		if not is_instance_valid(v) or not alive.has(v.state.id):
			if is_instance_valid(v):
				v.queue_free()
			wall_views.remove_at(i)

	# Create or refresh the rest.
	var have := {}
	for v in wall_views:
		have[v.state.id] = v

	for ws in state.walls:
		if have.has(ws.id):
			if dirty.has(ws.id):
				have[ws.id].refresh()
		else:
			var v := CozyWall.new()
			_view_root.add_child(v)
			v.setup_from(ws)
			wall_views.append(v)


# ---------------------------------------------------------------- terrain gate

## Ask the ground for permission (doc #12). A no-op until a terrain system is
## attached, so the building system stays usable on its own.
func _ground_approves(intent: CozyBuildingIntent) -> bool:
	if terrain == null:
		return true

	# A wall's footprint is its span widened by its thickness, since the wall is
	# centred on the centre-line.
	var pad: float = intent.thickness + 0.05
	var r := Rect2(
		Vector2(minf(intent.a.x, intent.b.x) - pad, minf(intent.a.z, intent.b.z) - pad),
		Vector2(absf(intent.b.x - intent.a.x) + pad * 2.0,
			absf(intent.b.z - intent.a.z) + pad * 2.0))

	var verdict := CozyFoundationValidator.validate(terrain, r)
	var res: int = verdict["result"]
	if res == CozyFoundationValidator.Result.INVALID:
		last_rejection = String(verdict["reason"])
		return false

	last_rejection = ""
	return true


# ---------------------------------------------------------------- queries

## Walls whose centre-line lies on this floor — what room detection consumes.
func centrelines_on_floor(floor_id: int) -> Array:
	var out: Array = []
	for ws in state.walls_on_floor(floor_id):
		out.append(ws.centreline())
	return out


func describe() -> String:
	return state.describe()
