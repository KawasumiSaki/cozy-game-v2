class_name CozyDroppedItem
extends Node3D
## Something lying on the ground, waiting to be walked over.
##
## ---------------------------------------------------------------------------
## WHY THIS IS A SYSTEM AND NOT WHAT ONE BUTTON DOES
##
## Willow, 2026-09-15: "右键树，砍树，然后会掉下来木头*4，打怪会掉下来装备 ...
## 我们靠近自动拾取." Until this node existed, BOTH of those went straight into
## the player's ledgers — the chop wrote `player_state.pack` and the kill wrote
## the bag — so nothing in the game was ever on the ground, and there was nowhere
## to express the case this is really for: it did not fit, so it stayed there.
##
## The producers are now three and they are the same road: a felled tree, a killed
## monster, and — when the equipment panel lands — taking a worn item off. That is
## what makes it a system. `卸下` is not a special case of it; it is a caller.
##
## ---------------------------------------------------------------------------
## TWO PAYLOADS, BECAUSE THERE ARE TWO KINDS OF THING AND THEY ARE NOT ALIKE
##
## A MATERIAL is an id and an amount — the vocabulary `CozyInventory` speaks,
## where two wood are one number and two wood and one wood are three wood. An
## ITEM is an instance with rolled affixes, where two swords are two swords and a
## stack of them is not a thing that can exist. `CozyItemContainer`'s header makes
## the same argument about why it is not a `CozyInventory`; the fork shows up
## again here because it is the same fork.
##
## ---------------------------------------------------------------------------
## WHAT A DROP IS NOT
##
## IT IS NOT A NAVIGATION OBSTACLE. A dropped sword must not stop a resident
## walking to the chest. `_outdoor_obstacles` reads the object list, and this is
## deliberately not in it.
##
## IT DOES NOT TICK. Nothing about a drop changes over time, so there is no
## `_process` here and no `Timer` — one node per dropped thing with a per-frame
## callback would be the "instancing is not optional" mistake in a new place. The
## only per-frame work is the player's pickup pass, and that lives in `main.gd`
## where the player is.
##
## IT IS NOT PICKED UP BY RESIDENTS. The residents have their own ledgers and
## their own work; a resident that went round collecting dropped loot would be a
## hauler with a job nobody wrote a row for.

const KIND_MATERIAL := "material"
const KIND_ITEM := "item"

## How close the player has to stand, on the ground plane.
##
## SHORTER THAN EVERY REACH, AND THAT IS THE WHOLE REASON THERE IS A GROUND AT ALL.
## `_gather_from` refuses to work a node from further away than its reach, and a
## drop lands at that node's edge — the side the player is on — so the gap between
## a player standing at the limit of their reach and the thing they just knocked
## loose IS the reach. A radius as long as the shortest reach would take every drop
## on the frame it appeared, and "掉在地上" would be the same code as "直接进包"
## with a different comment.
##
## 0.6 IS SET BY THE SMALLEST ONE, which is a crop's 0.8 m — not by the 1.3 m that
## a tree, a rock and everything else use. The first version of this was 1.0, which
## felt right and was wrong by exactly the amount that makes harvesting a crop
## silently different from felling a tree. `test_dropped_item` asserts the relation
## for EVERY gathered node rather than for the tree, so the next row with a short
## reach cannot reintroduce it.
const PICKUP_RADIUS := 0.6

## How big the marker is and how far it floats. A drop is a MARKER rather than a
## model: it says "something is here" and nothing reads it for anything else. The
## art pass can replace the box with a sprite or a coloured beam without touching
## a single caller.
const MARK_SIZE := 0.32
const MARK_LIFT := 0.18

## What a piece of equipment looks like on the ground. One colour for every item
## rather than one per rarity: rarity is a number the tooltip owns and nothing
## renders it yet, and five colours invented here would be art direction with no
## one asking for it.
const LOOT_COLOR := Color(0.86, 0.74, 0.36)

## The entity id, minted by `main.gd`. NOT OPTIONAL: `CozyEntityRegistry` looks
## every state up by `id`, and an entity without one takes the whole registry down
## with it rather than failing alone — see `CozyPlayerState.PLAYER_ID` for the
## long version, which is how that was found.
var id := ""

## WHERE IT IS, as a fact rather than as a transform.
##
## The transform is set FROM this, not the other way round. `to_global()` on a
## node outside the tree returns the identity transform and logs an engine error —
## the trap `CozyWorldObject.apply_dict` documents at length — and a drop has to
## be constructible, saveable and comparable without ever being in a scene. So the
## position is a fact this object owns, and the transform is a view of it.
var at := Vector3.ZERO

var floor_index := 0

## `KIND_MATERIAL` or `KIND_ITEM`, and the payload below follows it.
##
## One string rather than inferring from which fields are set: "no material id"
## and "a material drop whose id is blank" would be the same state, and one of
## them is a bug.
var kind := ""

var material_id := ""
var amount := 0.0
var item: CozyItemInstance = null

## Whether the player has already been told this one does not fit.
##
## NOT SAVED, because it is not a fact about the drop — it is a fact about what
## this session has already said. Without it, standing next to a sword with a full
## bag prints a line every frame, which is the same as printing nothing.
var refused := false


func setup_material(p_material_id: String, p_amount: float) -> void:
	kind = KIND_MATERIAL
	material_id = p_material_id
	amount = p_amount
	item = null
	_build_mark()


func setup_item(p_item: CozyItemInstance) -> void:
	kind = KIND_ITEM
	item = p_item
	material_id = ""
	amount = 0.0
	_build_mark()


func is_material() -> bool:
	return kind == KIND_MATERIAL


## Put it in the world at `p_at`.
##
## Separate from `setup_*` because the caller adds the node to the tree first —
## the same order `_place_object` uses, and for the same reason: everything that
## reads a world position has to run after there is one.
func place(p_at: Vector3) -> void:
	at = p_at
	# A NODE OUTSIDE THE TREE HAS NO WORLD TRANSFORM TO SET, and asking for one is
	# an engine error rather than a no-op — the trap `CozyWorldObject.apply_dict`
	# documents at length. Guarding it is what keeps a drop constructible, saveable
	# and comparable in a unit test with no scene at all, which is where everything
	# about a drop that is not about the world gets checked.
	if get_parent() != null:
		global_position = p_at
	else:
		position = p_at


# ---------------------------------------------------------------- being taken

## Would the player have room for this, right now?
##
## MATERIALS ALWAYS FIT. `CozyInventory` is an id and an amount with no ceiling,
## and inventing one here would be a second rule about capacity living in a file
## that does not own capacity — the pouch and the pack are `CozyItemContainer`'s
## `capacity`, and that is where the question belongs. Items are the ones that can
## be turned away, and the bag itself says so.
func fits_in(state: CozyPlayerState) -> bool:
	if state == null:
		return false
	if kind == KIND_MATERIAL:
		return true
	return item != null and not state.bag.is_full()


## Put it in the player's hands. Returns whether it went in.
##
## FALSE IS NOT AN ERROR, and the caller has to SAY SO rather than let it vanish:
## "a drop that silently disappears" is the exact failure this node exists to
## prevent, and a sword the player watched fall and can never find is worse than
## one they were told they could not carry.
func collect_into(state: CozyPlayerState) -> bool:
	if not fits_in(state):
		return false
	if kind == KIND_MATERIAL:
		state.pack.add(material_id, amount)
		return true
	return state.bag.add_item(item) >= 0


## Is the player standing close enough, measured on the ground plane?
##
## FLAT, like the swing's reach and for the same reason: a thing on a slope is not
## further away because of the slope, and a 3D distance would refuse to pick up
## something lying at the player's feet on the other side of a kerb.
func in_range(from: Vector3) -> bool:
	return Vector2(from.x - at.x, from.z - at.z).length() <= PICKUP_RADIUS


func display_name() -> String:
	if kind == KIND_MATERIAL:
		return "%s x%d" % [CozyMaterials.display_name(material_id), int(amount)]
	return "" if item == null else item.display_name()


func describe() -> String:
	return "%s@(%.1f,%.1f)" % [display_name(), at.x, at.z]


func _build_mark() -> void:
	for c in get_children():
		c.queue_free()
	var box := BoxMesh.new()
	box.size = Vector3(MARK_SIZE, MARK_SIZE, MARK_SIZE)
	var mi := MeshInstance3D.new()
	mi.mesh = box
	mi.position = Vector3(0.0, MARK_LIFT, 0.0)
	mi.material_override = CozyPixelArt.make_flat_material(mark_color())
	add_child(mi)


## What colour the marker is. A material wears its own colour — the same number a
## wooden wall is drawn with, so a pile of wood on the ground and a plank in a
## wall are recognisably the same stuff. An item has no colour of its own.
func mark_color() -> Color:
	if kind == KIND_MATERIAL:
		return Color(CozyMaterials.get_def(material_id).get("color", Color.WHITE))
	return LOOT_COLOR


# ---------------------------------------------------------------- serialise

## Facts only, the shape every serializer in this project follows: no marker, no
## colour, no node. The mesh is rebuilt from `kind`, and the colour is derived
## from what the drop holds.
func to_dict() -> Dictionary:
	var d := {
		"id": id,
		"kind": kind,
		"floor_index": floor_index,
		"position": [at.x, at.y, at.z],
	}
	if kind == KIND_MATERIAL:
		d["material_id"] = material_id
		d["amount"] = amount
	else:
		d["item"] = item.to_dict() if item != null else {}
	return d


## Apply saved facts. Returns whether the payload was readable.
##
## A PAYLOAD THAT NAMES NOTHING IS REFUSED rather than loaded as an empty drop. A
## drop with no payload would be a box on the ground that can never be picked up
## and never goes away — it looks like the game working and is the one shape of
## this that a player cannot report clearly.
func apply_dict(d: Dictionary) -> bool:
	var p: Array = d.get("position", [0.0, 0.0, 0.0])
	var saved_id := String(d.get("id", ""))
	if p.size() != 3:
		return false
	var k := String(d.get("kind", ""))
	id = saved_id
	floor_index = int(d.get("floor_index", 0))
	if k == KIND_MATERIAL:
		var mat := String(d.get("material_id", ""))
		var n := float(d.get("amount", 0.0))
		if saved_id == "" or mat == "" or n <= 0.0:
			return false
		setup_material(mat, n)
	elif k == KIND_ITEM:
		if saved_id == "" or not d.has("item"):
			return false
		var it := CozyItemInstance.from_dict(d["item"])
		if it.instance_id == "" or it.definition_id == "":
			return false
		setup_item(it)
	else:
		return false
	place(Vector3(p[0], p[1], p[2]))
	return true
