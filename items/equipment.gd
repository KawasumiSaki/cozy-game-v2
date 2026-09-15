class_name CozyEquipment
extends RefCounted
## What a character is WEARING: items in slots, and the modifier list that comes
## out of it.
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
## A SLOT IS A KIND WITH A CAPACITY, NOT A PLACE.
##
## Willow, 2026-09-15: three charms and two rings. With one place per kind a
## second ring could only ever displace the first, and `ring_1` / `ring_2` as
## separate ids would make the ring a definition names a different thing from the
## ring it is worn in — `slot_of("copper_ring")` would have to answer "which
## one", and it cannot know.
##
## So the kind is what an item knows about itself, the capacity is what the
## character knows, and this file is the only place the two meet.
##
## ---------------------------------------------------------------------------
## THE SLOT TABLES ARE NOT WRITTEN HERE. `CozyItemDefs.SLOTS` and
## `SLOT_CAPACITY` already say what a character can wear and how many; a second
## copy in this file is the kind of duplicate that drifts the first time a
## fifteenth slot is added, and it would drift silently, because both copies
## would still be internally consistent.

## kind -> Array of `capacity` entries, each a `CozyItemInstance` or null.
##
## The array is built ONCE in `_init` and never resized, so a place is a thing
## with a position rather than a thing that appears. An empty place is a null,
## which is what a panel draws as an empty square.
var _worn := {}


func _init() -> void:
	for kind in CozyItemDefs.SLOTS:
		var places: Array = []
		places.resize(CozyItemDefs.capacity_of(kind))
		places.fill(null)
		_worn[kind] = places


# ---------------------------------------------------------------- wearing

## Wear `item`, and hand back whatever it displaced.
##
## A FREE PLACE IS TAKEN FIRST, and only a full kind displaces anything — the
## second ring goes in the second ring place rather than bumping the first.
## Displacement is RETURNED rather than silently dropped: the caller has a bag to
## put it in, and a caller that discards it should have to say so. An item
## destroyed by putting another one on is the kind of loss a player reads as a
## bug.
##
## Returns null both when nothing was displaced AND when the item cannot be worn
## at all — the caller that cares which can ask `slot_of` first, and the one that
## does not is not made to.
func equip(item: CozyItemInstance) -> CozyItemInstance:
	if item == null:
		return null
	var kind := item.slot()
	if not _worn.has(kind):
		return null
	var places: Array = _worn[kind]
	for i in places.size():
		if places[i] == null:
			places[i] = item
			return null
	# Every place taken: the first one gives way.
	var displaced: CozyItemInstance = places[0]
	places[0] = item
	return displaced


## Take whatever is in one place. `index` -1 means the first place holding
## something, which is what a "take that off" button wants and what a caller
## naming a kind rather than a place means.
func unequip(slot_kind: String, index := -1) -> CozyItemInstance:
	if not _worn.has(slot_kind):
		return null
	var places: Array = _worn[slot_kind]
	if index < 0:
		for i in places.size():
			if places[i] != null:
				return unequip(slot_kind, i)
		return null
	if index >= places.size():
		return null
	var out: CozyItemInstance = places[index]
	places[index] = null
	return out


## Take off one PARTICULAR item, wherever it is. This is what an inventory screen
## calls when the player clicks the sword they are wearing, and it is the reason
## identity is per-instance: two iron swords are two swords and only one of them
## comes off.
func unequip_instance(instance_id: String) -> CozyItemInstance:
	var at := place_of(instance_id)
	if at.is_empty():
		return null
	return unequip(String(at["kind"]), int(at["index"]))


func worn(slot_kind: String, index := 0) -> CozyItemInstance:
	if not _worn.has(slot_kind):
		return null
	var places: Array = _worn[slot_kind]
	if index < 0 or index >= places.size():
		return null
	return places[index]


## Where an item is worn, as `{"kind": String, "index": int}`, or `{}`.
##
## Compared by INSTANCE id, not by definition: a character can own three iron
## swords and be wearing one of them.
func place_of(instance_id: String) -> Dictionary:
	for kind in _worn:
		var places: Array = _worn[kind]
		for i in places.size():
			var it: CozyItemInstance = places[i]
			if it != null and it.instance_id == instance_id:
				return {"kind": String(kind), "index": i}
	return {}


func is_wearing(instance_id: String) -> bool:
	return not place_of(instance_id).is_empty()


## How many places this kind has, and how many of them are filled. The panel
## draws `capacity` squares and fills `filled` of them, so both numbers come from
## here rather than from a count of what happens to be worn.
func capacity(slot_kind: String) -> int:
	return (_worn[slot_kind] as Array).size() if _worn.has(slot_kind) else 0


func filled(slot_kind: String) -> int:
	var n := 0
	for it in _worn.get(slot_kind, []):
		if it != null:
			n += 1
	return n


func worn_kinds() -> Array[String]:
	var out: Array[String] = []
	for kind in CozyItemDefs.SLOTS:
		if filled(String(kind)) > 0:
			out.append(String(kind))
	return out


func items() -> Array[CozyItemInstance]:
	var out: Array[CozyItemInstance] = []
	for kind in CozyItemDefs.SLOTS:
		for it in _worn.get(String(kind), []):
			if it != null:
				out.append(it)
	return out


func is_empty() -> bool:
	return items().is_empty()


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
	for it in items():
		out.append_array(it.modifiers())
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

## kind -> a list of `capacity` entries, each a payload or null. Nulls are
## WRITTEN rather than skipped, because the POSITION is the information: a ring
## in the second place and a ring in the first are different states of the same
## two rings, and a sparse list would put both back in the first.
##
## The item's id travels inside its payload, per the save rules: an id written
## beside it as well would let a file disagree with itself.
func to_dict() -> Dictionary:
	var out := {}
	for kind in CozyItemDefs.SLOTS:
		var places: Array = _worn[String(kind)]
		var payloads: Array = []
		for it in places:
			payloads.append((it as CozyItemInstance).to_dict() if it != null else null)
		out[String(kind)] = payloads
	return out


## A file can name a slot the game does not have, or list more of them than the
## character has places. Both are REFUSED rather than stored: an item in an
## unwearable slot would contribute to the character's stats while being
## invisible to every screen that draws the slots.
## `unknown_slots()` is how a caller finds out it happened.
static func from_dict(d: Dictionary) -> CozyEquipment:
	var eq := CozyEquipment.new()
	for kind in d:
		var name := String(kind)
		if not eq._worn.has(name):
			continue
		# A FILE CAN CARRY ANYTHING. A payload that is not the list this format
		# writes is skipped rather than iterated — the loader is the one place
		# that cannot assume the file is well formed, and a crash here is a game
		# that will not start rather than one item that does not appear.
		if not (d[kind] is Array):
			continue
		var listed: Array = d[kind]
		var places: Array = eq._worn[name]
		for i in mini(listed.size(), places.size()):
			if listed[i] == null:
				continue
			places[i] = CozyItemInstance.from_dict(listed[i])
	return eq


## The slots in this payload the game does not have. Empty for anything this
## version wrote.
static func unknown_slots(d: Dictionary) -> Array[String]:
	var out: Array[String] = []
	for kind in d:
		var name := String(kind)
		if not CozyItemDefs.is_slot(name):
			out.append(name)
	out.sort()
	return out


## How many items a load could not place — in a slot that does not exist, or past
## the end of one that does. A caller that cares about losing things asks.
static func dropped_on_load(d: Dictionary) -> int:
	var n := 0
	for kind in d:
		var name := String(kind)
		if not CozyItemDefs.is_slot(name):
			n += (d[kind] as Array).size()
			continue
		if not (d[kind] is Array):
			continue
		var cap := CozyItemDefs.capacity_of(name)
		var listed: Array = d[kind]
		n += maxi(0, listed.size() - cap)
	return n


func describe() -> String:
	if is_empty():
		return "wearing nothing"
	var parts: Array[String] = []
	for kind in worn_kinds():
		var names: Array[String] = []
		for it in _worn[kind]:
			if it != null:
				names.append((it as CozyItemInstance).display_name())
		parts.append("%s: %s" % [CozyItemDefs.slot_name(kind), ", ".join(names)])
	return "; ".join(parts)
