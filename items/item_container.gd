class_name CozyItemContainer
extends RefCounted
## A bag of items: N slots, one item in each.
##
## ---------------------------------------------------------------------------
## THIS IS THE CONSUMER THE LOOT ROLLER NEVER HAD.
##
## `CozyItemGenerator` rolls a `CozyItemInstance` and `CozyLootRoller` hands it
## back as a drop — and until this file existed, NOTHING IN THE GAME COULD HOLD
## ONE. Only the tests could. That is the "declared with no consumer" shape this
## project has paid for eight times, sitting at the top of the equipment lane
## where it was easiest not to notice, because every part of it works.
##
## ---------------------------------------------------------------------------
## WHY NOT `CozyInventory`, AND WHY NOT STACKING
##
## `CozyInventory` already exists and is a RESOURCE STORE: an id and an amount,
## wood 600. That IS stacking, and it already works — the request "basic
## materials should stack" is answered by the container that was already there.
##
## An ITEM is the other thing. `CozyItemInstance` is unique by construction: its
## modifiers are keyed by its own instance id, so two iron swords are two swords
## and equipping the second must not replace the first. A stack of them is not
## a thing that can exist, so there is no `count` here and no merge on insert.
## Two vocabularies, two containers, and neither is a special case of the other.
##
## ---------------------------------------------------------------------------
## WHY SLOTS RATHER THAN A LIST
##
## `cozy` design doc section 37 draws the inventory as a grid of empty squares
## and puts the item's position in it in front of the player. A slot index IS
## that position for a uniform grid, so this holds an Array and the UI can read
## `item_at(slot)` for each square it draws.
##
## A VARIABLE-FOOTPRINT grid — the "search, fight, extract" style, where a rifle
## takes six squares and a bandage takes one — is NOT this, and it is not here.
## It would add a width and a height to the definition and a placement map to
## this class; the slot array stays, as the map's owner. That is a change rather
## than a rewrite, which is the reason to say so now rather than discover it.
##
## ---------------------------------------------------------------------------
## CAPACITY IS THE BAG'S LEVEL. "Backpacks of different tiers" is this number
## and nothing else, so a small pouch and a large pack are two rows of data.

## How many slots the bag has. This IS the bag's tier — a pouch and a pack are
## two numbers, not two classes.
var capacity := 0

## The slots. `null` is an EMPTY SLOT rather than an absent entry: the player can
## see a hole in a bag, and an Array that only holds the items cannot show one.
var _slots: Array = []


func _init(p_capacity := 0) -> void:
	resize(p_capacity)


## Change the number of slots, keeping what still fits IN THE SLOTS IT WAS IN.
##
## A smaller bag DROPS the overflow rather than shuffling it down, and the reason
## is the same one `add_item_at` refuses an occupied slot: an item that moves is
## an item in a slot the player never saw it in. `from_dict` reports its drops
## with `dropped_on_load`; a caller resizing a live bag can compare before and
## after itself.
func resize(p_capacity: int) -> void:
	var kept := _slots
	capacity = maxi(0, p_capacity)
	_slots = []
	_slots.resize(capacity)
	_slots.fill(null)
	for i in mini(kept.size(), capacity):
		_slots[i] = kept[i]


# ---------------------------------------------------------------- the doc's API

## Put an item in the first free slot. Returns the slot it landed in, or -1 when
## the bag is full.
##
## Section 27 names this `add_item`; the name is kept because the document is the
## authority and a second vocabulary for one operation is how two names for the
## same thing start drifting.
func add_item(item: CozyItemInstance) -> int:
	if item == null:
		return -1
	var slot := first_free_slot()
	if slot < 0:
		return -1
	_slots[slot] = item
	return slot


## Put an item in a PARTICULAR slot. Refuses an occupied slot rather than
## swapping: "put this here" and "replace what is there" are different
## intentions, and a caller that means the second one can say so.
func add_item_at(slot: int, item: CozyItemInstance) -> bool:
	if item == null or not in_bounds(slot) or _slots[slot] != null:
		return false
	_slots[slot] = item
	return true


## Take an item out by its own id. Returns what was removed, or null.
func remove_item(instance_id: String) -> CozyItemInstance:
	var slot := slot_of(instance_id)
	return remove_at(slot) if slot >= 0 else null


func remove_at(slot: int) -> CozyItemInstance:
	if not in_bounds(slot):
		return null
	var out: CozyItemInstance = _slots[slot]
	_slots[slot] = null
	return out


func has_item(instance_id: String) -> bool:
	return slot_of(instance_id) >= 0


func get_items() -> Array[CozyItemInstance]:
	var out: Array[CozyItemInstance] = []
	for it in _slots:
		if it != null:
			out.append(it)
	return out


# ---------------------------------------------------------------- queries

func in_bounds(slot: int) -> bool:
	return slot >= 0 and slot < capacity


func item_at(slot: int) -> CozyItemInstance:
	return _slots[slot] if in_bounds(slot) else null


func slot_of(instance_id: String) -> int:
	for i in capacity:
		var it: CozyItemInstance = _slots[i]
		if it != null and it.instance_id == instance_id:
			return i
	return -1


## The first slot holding an item of this DEFINITION — "do I have a sword" as
## opposed to "do I still have that particular sword".
func slot_of_definition(definition_id: String) -> int:
	for i in capacity:
		var it: CozyItemInstance = _slots[i]
		if it != null and it.definition_id == definition_id:
			return i
	return -1


func first_free_slot() -> int:
	for i in capacity:
		if _slots[i] == null:
			return i
	return -1


func free_slots() -> int:
	var n := 0
	for i in capacity:
		if _slots[i] == null:
			n += 1
	return n


func count() -> int:
	return capacity - free_slots()


func is_empty() -> bool:
	return count() == 0


func is_full() -> bool:
	return first_free_slot() < 0


# ---------------------------------------------------------------- serialise

## Only the occupied slots are written, keyed by their index — a bag is mostly
## empty and a file full of nulls is a file that gets bigger with the bag's level
## rather than with what is in it.
##
## The instance id travels INSIDE the item's own payload, per the save rules in
## `docs/INVARIANTS.md`: writing it beside the payload as well would let a file
## disagree with itself.
func to_dict() -> Dictionary:
	var filled := {}
	for i in capacity:
		var it: CozyItemInstance = _slots[i]
		if it != null:
			filled[str(i)] = it.to_dict()
	return {"capacity": capacity, "slots": filled}


## An item in a slot the bag does not have is DROPPED rather than moved, and the
## count is returned so the caller can say so. Silently relocating it would put a
## sword in a slot the player never saw.
static func from_dict(d: Dictionary) -> CozyItemContainer:
	var bag := CozyItemContainer.new(int(d.get("capacity", 0)))
	var filled: Dictionary = d.get("slots", {})
	for key in filled:
		var slot := int(String(key))
		if not bag.in_bounds(slot):
			continue
		bag._slots[slot] = CozyItemInstance.from_dict(filled[key])
	return bag


## How many items a load could not place. A caller that cares about losing things
## asks; one that does not is not made to.
static func dropped_on_load(d: Dictionary) -> int:
	var cap := int(d.get("capacity", 0))
	var n := 0
	for key in d.get("slots", {}):
		if int(String(key)) >= cap:
			n += 1
	return n


func describe() -> String:
	return "bag %d/%d: %s" % [count(), capacity,
		", ".join(get_items().map(func(i: CozyItemInstance) -> String:
			return i.display_name())) if count() > 0 else "empty"]
