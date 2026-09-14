class_name CozyWorldObject
extends Node3D
## A placeable thing in the world (V2 doc #65–#68).
##
## The doc's insight (#66) is that a chair, a bed, a chest and a research table
## look completely different, but to the engine they are the same thing:
## a position, a footprint, collision, and a set of ways they can be used.
## So they are ONE abstraction reading a data definition — not four systems
## that call into each other (#125).
##
## Each object ADVERTISES its interaction points (#87) rather than containing
## the behaviour of whoever uses it. The NPC side knows nothing about tables.

## Entity id (Core Architecture V1.0, item 1), minted by whoever creates the
## object — `_place_object` for an authored one.
##
## Until this existed an object was identified by its INDEX in `main.objects`,
## which means its identity did not survive a save at all: a load frees every
## object and rebuilds them from a list, so anything still holding a reference
## held a freed node, and "give me the chest" could only be answered by walking
## the list and comparing `def_id`.
var id := ""

var def_id := ""
var floor_index := 0

var interaction_points: Array[CozyInteractionPoint] = []

## Effects this object emits (doc E.18), built from its definition.
var vfx: Array[CozyVfx] = []

## What this object HOLDS, when its definition says it is a container (V2-21).
##
## Until this existed, `chest` advertised a `store` interaction point and the
## `hauler` job in the data table pointed at it — and nothing anywhere answered
## either. The point was decoration and the job could never complete a task.
var container: CozyContainerState = null

## What has been taken from this node in the current season, and when that season
## began — in GAME hours, so a save reloads into the same season it was left in.
##
## FACTS, so they are saved. Everything else about growth is derived from them by
## `CozyObjectDefs.available`, which is why nothing here counts `delta` and no
## node owns a `Timer`: two reads at the same hour must agree, and a timer cannot
## promise that across a save.
var taken := 0
var worked_at := -1.0

var _def: Dictionary = {}
var _size := Vector2.ONE
var _specs: Array = []          ## {local: Vector3, ...} mirrors interaction_points
var _mat: StandardMaterial3D = null
var _body: StaticBody3D = null


func setup(p_def_id: String, p_floor := 0) -> void:
	def_id = p_def_id
	floor_index = p_floor
	_def = CozyObjectDefs.get_def(def_id)
	_build()


func _build() -> void:
	for c in get_children():
		c.queue_free()
	interaction_points.clear()
	_specs.clear()
	vfx.clear()
	if _def.is_empty():
		return

	_size = _def["size"]
	var h: float = _def["height"]

	var bm := BoxMesh.new()
	bm.size = Vector3(_size.x, h, _size.y)

	var mi := MeshInstance3D.new()
	mi.mesh = bm
	mi.position = Vector3(0.0, h * 0.5, 0.0)
	_mat = CozyPixelArt.make_material(
		CozyPixelArt.make_texture(16, _def["color"], 0.05, hash(def_id)), Vector3.ONE)
	mi.material_override = _mat
	add_child(mi)

	# Collision — furniture blocks movement (doc #85), which also means placing
	# it must update navigation (doc #86).
	_body = StaticBody3D.new()
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = bm.size
	cs.shape = bs
	cs.position = Vector3(0.0, h * 0.5, 0.0)
	_body.add_child(cs)
	add_child(_body)

	_make_points()

	# The other half of a `store` point: the point says "you can put things here",
	# the container is where they actually go.
	container = null
	if String(_def.get("kind", "")) == "container":
		container = CozyContainerState.new()
		container.capacity = float(_def.get("capacity",
			CozyContainerState.DEFAULT_CAPACITY))

	_build_vfx()
	refresh_vfx_phase()


func is_container() -> bool:
	return container != null


## Re-seed effect phases from this object's world position.
##
## `_build()` runs before the caller positions the object, so the first pass can
## only see the definition — and two campfires share one, which leaves them
## flickering in lockstep. Position is what distinguishes instances.
func refresh_vfx_phase() -> void:
	if vfx.is_empty():
		return
	var cell := Vector3i(roundi(global_position.x * 10.0),
		floori(global_position.y), roundi(global_position.z * 10.0))
	for fx in vfx:
		var h := CozyArtSeed.mix4(hash(def_id), cell.x, cell.y, cell.z) ^ hash(fx.vfx_id)
		fx.set_phase(CozyArtSeed.unit(h) * 0.5)


func _process(_delta: float) -> void:
	refresh_points()


## Effects are declared by the definition and phased from the object's own id,
## so two campfires never flicker in lockstep (doc E.21).
func _build_vfx() -> void:
	for vfx_id in _def.get("vfx", []):
		var phase := CozyArtSeed.unit(hash(def_id) ^ hash(vfx_id)) * 0.5
		var fx := CozyVfx.create(vfx_id, phase)
		add_child(fx)
		vfx.append(fx)


## Recompute the world position of each advertised point from the current
## transform, so moving or rotating furniture moves its usable spots too
## (doc #120).
##
## Also called immediately after placement: the first frame has not run yet at
## that point, and an agent asking for a work point before then would be handed
## (0,0,0) — which reads as "the work is on the ground floor at the origin".
## Build the interaction points this definition advertises. Points sit in front
## of the object, where a person would stand to use it.
##
## Separate from `_build()` because a gathered node loses and regains its points
## as the seasons pass, and rebuilding them is the only honest way to express
## "there is nothing here to take" — a point that exists and refuses is a point
## an agent will walk to for nothing.
func _make_points() -> void:
	_specs.clear()
	interaction_points.clear()
	for it in _def["interactions"]:
		var reach: float = it["reach"]
		var local := Vector3(0.0, 0.0, _size.y * 0.5 + reach)
		_specs.append(local)
		interaction_points.append(CozyInteractionPoint.new(
			it["type"], Vector3.ZERO, it["skill"], it["duration"]))
	refresh_points()


## Is there anything left here to take, at this hour?
func is_available(now: float) -> bool:
	return CozyObjectDefs.available(def_id, taken, worked_at, now)


## Give the points back, or take them away, according to the clock.
##
## IDEMPOTENT, and that is the whole design: it recomputes from `taken` and
## `worked_at` rather than toggling a flag, so calling it every hour and calling
## it once an hour are the same thing. `INVARIANTS` demands exactly this of
## anything refreshed repeatedly — a refresh that reads its own output
## accumulates corruption at the rate it runs.
##
## Returns whether anything changed, so the caller can skip the work.
func refresh_availability(now: float) -> bool:
	var want := is_available(now)
	if want == not interaction_points.is_empty():
		return false
	if want:
		_make_points()
	else:
		_specs.clear()
		interaction_points.clear()
	return true


## Take one from this node, at this hour.
##
## THE REGROW IS APPLIED HERE rather than by a tick, because this is the only
## moment the counter needs to be right: a season that has already elapsed is a
## new season, and `available()` would have said so. Doing it on the action keeps
## the read pure and the write in one place.
func take_one(now: float) -> void:
	if taken >= int(_def.get("yields", 0)) and worked_at >= 0.0:
		var regrow := float(_def.get("regrow_hours", 0.0))
		if regrow > 0.0 and now - worked_at >= regrow:
			taken = 0                      # A new season; the old count is spent.
	taken += 1
	worked_at = now


func refresh_points() -> void:
	for i in interaction_points.size():
		interaction_points[i].world_position = to_global(_specs[i])


func collision_body() -> StaticBody3D:
	return _body


## Axis-aligned footprint in world XZ, used to register the object as a
## navigation obstacle. Rotation is folded in via the rotated extents.
func footprint_rect() -> Rect2:
	var c := absf(cos(rotation.y))
	var s := absf(sin(rotation.y))
	var ex := c * _size.x * 0.5 + s * _size.y * 0.5
	var ez := s * _size.x * 0.5 + c * _size.y * 0.5
	var p := global_position
	return Rect2(p.x - ex, p.z - ez, ex * 2.0, ez * 2.0)


## Free points of a given type — what an NPC asks for (doc #94).
func free_points_of_type(t: String) -> Array[CozyInteractionPoint]:
	var out: Array[CozyInteractionPoint] = []
	for p in interaction_points:
		if p.type == t and p.is_free():
			out.append(p)
	return out


func describe() -> String:
	return "%s@(%.1f,%.1f)" % [def_id, global_position.x, global_position.z]


# ---------------------------------------------------------------- serialise

## Facts only (doc #68): what it is, where it is, and what is inside it.
##
## The mesh, the collider, the material and the interaction points are all
## rebuilt by `setup()` from the definition, so storing them would be storing
## derived results — and would let the file disagree with the definition.
func to_dict() -> Dictionary:
	var d := {
		"id": id,
		"def_id": def_id,
		"floor_index": floor_index,
		"position": [global_position.x, global_position.y, global_position.z],
		"yaw": rotation.y,
	}
	# Saved only when they say something. A chest has never been worked, and
	# writing `taken: 0, worked_at: -1` for every piece of furniture would put a
	# growth cycle in files that have no growth in them.
	if taken != 0 or worked_at >= 0.0:
		d["taken"] = taken
		d["worked_at"] = worked_at
	if container != null:
		d["container"] = container.to_dict()
	return d


## Apply saved facts to an object that is ALREADY in the tree.
##
## Deliberately not a static factory. `setup()` builds VFX whose phase comes from
## the object's world position, and `to_global()` on a node outside the tree
## returns the identity transform and logs an engine error — twelve of them, once
## per object, before this was a method. `_place_object` has the same ordering
## requirement for the same reason: add first, then set up, then re-phase.
func apply_dict(d: Dictionary) -> void:
	# The id first: `setup()` rebuilds derived things, and a replaced object that
	# came back under a different id would be a duplicate the registry refuses.
	id = String(d.get("id", ""))
	setup(String(d.get("def_id", "")), int(d.get("floor_index", 0)))
	var p: Array = d.get("position", [0.0, 0.0, 0.0])
	global_position = Vector3(p[0], p[1], p[2])
	rotation.y = float(d.get("yaw", 0.0))
	taken = int(d.get("taken", 0))
	worked_at = float(d.get("worked_at", -1.0))
	# `setup()` built a container with the definition's capacity; the saved one
	# replaces it wholesale, so contents and capacity can never drift apart.
	if container != null and d.has("container"):
		container = CozyContainerState.from_dict(d["container"])
	refresh_points()
	refresh_vfx_phase()
