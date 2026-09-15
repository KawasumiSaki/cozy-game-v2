class_name CozyEquipment
extends RefCounted
## What a character is WEARING: one item per slot, and the modifier list that
## comes out of it.
##
## ---------------------------------------------------------------------------
## THIS IS THE BRIDGE BETWEEN TWO HALVES THAT WERE BOTH ALREADY FINISHED.
##
## `CozyItemInstance.modifiers()` produces the resolver's own vocabulary, keyed
## by the instance's id. `CozyStats.resolve()` turns a list of those into a
## number. Between them was nothing: no object held the worn items, so a player
## could roll a legendary sword and there was no way to put it on.
##
## `data/items.gd` says the split between definition and instance is "the most
## important design in the whole equipment system" — this file is where that
## design pays. Two iron swords are two swords because each contributes under its
## OWN id, so taking one off is a subtraction that cannot touch the other.
##
## ---------------------------------------------------------------------------
## THE SLOT LIST IS NOT WRITTEN HERE. `CozyItemDefs.SLOTS` already says what a
## character can wear, and `CozyItemDefs.slot_of()` says where a given item goes.
## A second copy of the eight slots in this file is the kind of duplicate that
## drifts the first time a ninth is added — and it would drift silently, because
## both copies would still be internally consistent.

## slot -> CozyItemInstance. Sparse: an empty slot is an ABSENT KEY rather than a
## null, because "nothing is worn on the head" and "the head slot does not exist"
## are the same answer to every question this class is asked.
var _worn := {}


# ---------------------------------------------------------------- wearing

## Wear `item`, and hand back whatever it displaced.
##
## Displacement is RETURNED rather than silently dropped: the caller has a bag to
## put it in, and a caller that discards it should have to say so. An item
## destroyed by putting another one on is the kind of loss a player reads as a
## bug.
func equip(item: CozyItemInstance) -> CozyItemInstance:
	if item == null:
		return null
	var slot := item.slot()
	if slot == "":
		return null
	var displaced: CozyItemInstance = _worn.get(slot)
	_worn[slot] = item
	return displaced


func unequip(slot: String) -> CozyItemInstance:
	var out: CozyItemInstance = _worn.get(slot)
	_worn.erase(slot)
	return out


func worn(slot: String) -> CozyItemInstance:
	return _worn.get(slot)


func is_wearing(slot: String) -> bool:
	return _worn.has(slot)


## Which slot this item is worn in, or "" when it is not worn at all.
##
## Compared by INSTANCE id, not by definition: a character can own three iron
## swords and be wearing one of them.
func slot_wearing(instance_id: String) -> String:
	for slot in _worn:
		if (_worn[slot] as CozyItemInstance).instance_id == instance_id:
			return String(slot)
	return ""


func worn_slots() -> Array[String]:
	var out: Array[String] = []
	for slot in _worn:
		out.append(String(slot))
	out.sort()
	return out


func items() -> Array[CozyItemInstance]:
	var out: Array[CozyItemInstance] = []
	for slot in worn_slots():
		out.append(_worn[slot])
	return out


func is_empty() -> bool:
	return _worn.is_empty()


# ---------------------------------------------------------------- the point

## Every worn item's modifiers, in one list, ready for `CozyStats.resolve()`.
##
## Concatenated rather than merged: an item's two affixes that touch the same
## stat are two entries, because the resolver's whole job is to know what to do
## with several modifiers on one stat — summing some, multiplying others, letting
## an override discard the rest. Merging them here would decide that in the wrong
## place, and would decide it once, for every stat, forever.
func modifiers() -> Array:
	var out: Array = []
	for slot in worn_slots():
		out.append_array((_worn[slot] as CozyItemInstance).modifiers())
	return out


## One statistic, as this character's equipment says it should be.
##
## A CONVENIENCE OVER `modifiers()`, and deliberately not a second implementation
## — it calls straight through to the resolver, so there is no arithmetic here to
## drift from `CozyStats`. Anything that needs more than one stat at a time
## should call `modifiers()` once and reuse it; this rebuilds the list each call.
func stat(stat_id: String, base: float, mode := CozyStats.DEFAULT_MULTIPLY) -> float:
	return CozyStats.resolve(modifiers(), stat_id, base, mode,
		CozyStats.bounds(stat_id))


# ---------------------------------------------------------------- serialise

## Slot -> the item's own payload. The item's id travels inside its payload, per
## the save rules: an id written beside it as well would let a file disagree with
## itself.
func to_dict() -> Dictionary:
	var out := {}
	for slot in worn_slots():
		out[slot] = (_worn[slot] as CozyItemInstance).to_dict()
	return out


## A file can name a slot the game does not have, and that is REFUSED rather than
## stored: an item in an unwearable slot would contribute to the character's
## stats while being invisible to every screen that draws the eight slots.
## `unknown_slots()` is how a caller finds out it happened.
static func from_dict(d: Dictionary) -> CozyEquipment:
	var eq := CozyEquipment.new()
	for slot in d:
		var name := String(slot)
		if not CozyItemDefs.SLOTS.has(name):
			continue
		eq._worn[name] = CozyItemInstance.from_dict(d[slot])
	return eq


## The slots in this payload that the game does not have. Empty for anything this
## version wrote.
static func unknown_slots(d: Dictionary) -> Array[String]:
	var out: Array[String] = []
	for slot in d:
		var name := String(slot)
		if not CozyItemDefs.SLOTS.has(name):
			out.append(name)
	out.sort()
	return out


func describe() -> String:
	if is_empty():
		return "wearing nothing"
	var parts: Array[String] = []
	for slot in worn_slots():
		parts.append("%s: %s" % [slot, (_worn[slot] as CozyItemInstance).display_name()])
	return ", ".join(parts)
