class_name CozyGlamour
extends RefCounted
## Making one item look like another, without changing a single number.
##
## ---------------------------------------------------------------------------
## WHY THIS IS CHEAP HERE, AND WHY IT WOULD NOT BE ELSEWHERE
##
## The whole system is one field on the instance (`CozyItemInstance.glamour_id`)
## and the rules for setting it. That is all, because this project already split
## the thing that a glamour needs split:
##
##     a DEFINITION is what an item IS  — its name, its slot, its base numbers
##     an INSTANCE  is the one in your hand — the affixes rolled onto it
##
## An appearance is a third thing of the same kind, and it belongs on the
## instance for the same reason the affixes do: TWO IRON SWORDS ARE TWO SWORDS,
## so one of them can be made to look like a steel sword while the other stays as
## it was. Put the field on the definition and the result is a game-wide reskin,
## which is a different feature and a worse one.
##
## ---------------------------------------------------------------------------
## THE RULE THAT MUST NOT BREAK
##
##     A GLAMOUR CHANGES NOTHING THAT `modifiers()` RETURNS.
##
## It is the whole promise of the system and it is one careless line away: read
## the appearance into `base_stats()` and every cosmetic becomes a stat item, and
## the player who glamoured a sword for the look has silently been given its
## numbers. `test_items` asserts it over the whole affix roll, not over one item.
##
## ---------------------------------------------------------------------------
## COSTUME PIECES — "时装" — ARE THIS SYSTEM'S SECOND CUSTOMER.
##
## An item with no stats whose only use is to be a source is not a special case
## here: `reject_reason` already refuses a source that does not fit the slot, and
## a costume names the slot it covers like anything else. What it does not do is
## make the target worse, because the target's numbers are never read from the
## glamour at all. That is the entire reason a costume system is a row of data
## rather than a second equip layer.

## No glamour. The state every item starts in.
const NONE := ""


## Why this item may not be made to look like `source_id`, or "".
##
## A REASON rather than a bool, the shape `CozyObjectDefs.ground_problem` and
## `CozyDungeonBlueprint.reject_reason` settled on: whatever refuses has to be
## able to say why, and a menu can then disable a row with the words in it
## instead of hiding the row and teaching the player nothing.
static func reject_reason(target: CozyItemInstance, source_id: String) -> String:
	if target == null:
		return "there is nothing to glamour"
	if source_id == "":
		return "nothing was chosen to look like"
	if not CozyItemDefs.exists(source_id):
		return "'%s' is not an item" % source_id
	if source_id == target.definition_id:
		return "%s already looks like itself" % target.display_name()
	# THE SLOT RULE. A sword cannot be made to look like a helmet, and the reason
	# is not realism — it is that the two are drawn in different places, so the
	# result would be a helmet worn on the hand. Everything a glamour needs to
	# know is already in the definition.
	var want := CozyItemDefs.slot_of(source_id)
	if want != target.slot():
		return "%s goes on the %s, and this is a %s" % [
			CozyItemDefs.display_name(source_id),
			CozyItemDefs.slot_name(want), CozyItemDefs.slot_name(target.slot())]
	if source_id == target.glamour_id:
		return "it already looks like that"
	return ""


static func can_glamour(target: CozyItemInstance, source_id: String) -> bool:
	return reject_reason(target, source_id) == ""


## Make `target` look like `source_id`. Returns whether it took.
##
## NOTHING HERE TOUCHES `target.affixes`, which is not an implementation detail
## but the contract: see the header.
static func apply(target: CozyItemInstance, source_id: String) -> bool:
	if not can_glamour(target, source_id):
		return false
	target.glamour_id = source_id
	return true


## Take the appearance off, so the item looks like itself again. Returns whether
## anything changed — removing a glamour from an unglamoured item is a no-op
## rather than a failure, the same shape `take_one` and `refresh_availability`
## have.
static func remove(target: CozyItemInstance) -> bool:
	if target == null or target.glamour_id == "":
		return false
	target.glamour_id = ""
	return true


## Every definition that could be used as a source for this item, in id order.
##
## FOR A MENU, and the ORDER IS THE DECISION rather than the table's: id order is
## stable across runs and across a save, so a list the player is scanning does not
## reshuffle between two openings. Sorting by name would be friendlier and would
## move the moment a name changed.
static func sources_for(target: CozyItemInstance) -> Array[String]:
	var out: Array[String] = []
	if target == null:
		return out
	for id in CozyItemDefs.ids():
		if can_glamour(target, id):
			out.append(id)
	return out


## The items the PLAYER OWNS that could be used as a source.
##
## Ownership is the bag and what is worn, because a glamour in every game of this
## kind consumes the source — and consuming something the player does not have is
## not a rule, it is a bug waiting for a menu. Recalling a previously owned
## appearance is a GLAMOUR DRESSER (a catalogue), which is a storage question and
## arrives with somewhere to store them.
static func owned_sources(target: CozyItemInstance, bag: CozyItemContainer,
		equipment: CozyEquipment) -> Array[String]:
	var owned := {}
	if bag != null:
		for it in bag.get_items():
			owned[it.definition_id] = true
	if equipment != null:
		for it in equipment.items():
			owned[it.definition_id] = true
	var out: Array[String] = []
	for id in sources_for(target):
		if owned.has(id):
			out.append(id)
	return out
