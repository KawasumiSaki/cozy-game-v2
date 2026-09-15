class_name CozyPlayerState
extends RefCounted
## What the PLAYER carries — which is not what the village owns.
##
## ---------------------------------------------------------------------------
## TWO LEDGERS, AND THAT IS A GAMEPLAY DECISION RATHER THAN A DATA ONE.
##
## Willow, 2026-09-15: the resident economy runs itself — a farmer sows and
## reaps on the schedule, and `harvest_crop` yields two wheat and one seed
## against the one seed `sow_crop` eats, so the village's larder fills with NO
## PLAYER INVOLVED. A shop that buys from the VILLAGE would therefore be a number
## that goes up on its own, which is not a game.
##
## So the player's share comes from the player's OWN work: what they chop and
## mine. `building.inventory` is the village's — it pays for walls. This is the
## other one. They are separate objects on purpose, and `main.gd` asserts that
## they are separate objects, because the failure this prevents is that they
## quietly become one and the player's money turns out to have been the
## village's all along.
##
## ---------------------------------------------------------------------------
## WHY ONLY `pack`, AND NOT A BAG AND A SET OF WORN SLOTS TOO
##
## `CozyItemContainer` and `CozyEquipment` exist and are tested. Adding them here
## before anything can put an item in them would be a field with no consumer —
## this project's most expensive habit, with eight entries in
## `docs/INVARIANTS.md`. Nothing drops an item for the PLAYER yet; monsters do
## not exist yet. They arrive together with whatever fills them.
##
## `pack` is a `CozyInventory` — an id and an amount — because what a player
## chops is MATERIAL, the same vocabulary a wall's cost is in (doc #35: one
## store, many callers). Wood in a pack and wood in the village's account are the
## same kind of thing in two different places.

## THE ENTITY ID, and it is not optional. `CozyEntityRegistry` looks every state
## up by `id` — an entity that has none cannot be indexed, cannot be saved, and
## breaks the registry for every OTHER kind when it is asked for its list, which
## is how this was found: with no `id`, `_world_to_dict()` threw and the save
## came out empty, taking forty assertions with it.
##
## A FIXED STRING rather than a generated one, because there is exactly one
## player. A resident needs an id that distinguishes them from the next resident;
## the player needs one that a file can name.
const PLAYER_ID := "player"

var id := PLAYER_ID

## How many items the player can carry. A plain number until a backpack does
## something to it — see the note in `data/items.gd`.
const BAG_SLOTS := 12

## What the player's bare hands are worth, before anything is worn. Every number
## an item contributes lands on top of this (`CozyStats.resolve`), so a sword is
## "four plus eighteen" rather than "eighteen", and a player is never at nothing.
const BASE_ATTACK := 4.0
const BASE_HP := 40.0
const BASE_DEFENSE := 0.0

## Materials. `wood`, `stone`, `wheat`, and — when there is something to spend
## it on — `copper`.
var pack := CozyInventory.new()

## The items themselves: what was picked up and not yet worn.
var bag := CozyItemContainer.new(BAG_SLOTS)

## What is worn. Its `modifiers()` is where every number below comes from, and
## the reason an item in the bag does nothing until it is put on.
var equipment := CozyEquipment.new()

## The swing in progress: `CozyCombatSolver.blank_state()`.
##
## ON THE PLAYER'S STATE rather than on the character node, because it has to
## survive a frame, a panel being opened, and a save — a swing interrupted by a
## menu is the kind of bug that only shows up in a real session.
var combat := CozyCombatSolver.blank_state()


## One statistic, as the player's equipment says it should be.
##
## The BASE is passed in rather than read off a table here, so this file does not
## own what a person is worth with nothing on. Called through to the resolver
## every time — no arithmetic lives here to drift from `CozyStats`.
func attack() -> float:
	return equipment.stat("attack", BASE_ATTACK)


func max_hp() -> float:
	return equipment.stat("max_hp", BASE_HP)


func defense() -> float:
	return equipment.stat("defense", BASE_DEFENSE)


## Whether a guard is even possible. Right click guards WITH a shield and shoves
## without one (section 12), and the solver reads this rather than the input
## layer deciding — a fact about the character, not about the button.
func has_shield() -> bool:
	return equipment.filled("offhand") > 0


## What this state looks like as a line of text. For the HUD and for a check that
## needs to say what is in there rather than how much of it there is.
func describe() -> String:
	return pack.describe()


# ---------------------------------------------------------------- wearing

## Take a worn item off and stow it in the bag. Returns whether it moved.
##
## REFUSES WHOLE WHEN THE BAG IS FULL — the item stays on the body and NOTHING
## changes. The other shape, handing the item back to the caller to deal with,
## would make it the menu's problem, and the menu has nowhere to put it: the
## failure this avoids is a sword that is neither worn nor carried, which is a
## thing a player can neither see nor report.
##
## The ORDER is why this is a method rather than two calls at the menu. Asking the
## bag first and taking the item off second is the only order that cannot lose it;
## the other order has to be undone when the answer is no.
func stow(instance_id: String) -> bool:
	if bag.is_full() or not equipment.is_wearing(instance_id):
		return false
	bag.add_item(equipment.unequip_instance(instance_id))
	return true


## Put a bagged item on, and hand back to the bag whatever it displaced.
##
## THE DISPLACED ITEM ALWAYS FITS, and that is not luck: taking this item out of
## the bag frees exactly the one place the displaced one needs. So a swap made this
## way can never lose anything, which is the property worth having — `equip()`
## returns what it pushed out precisely so the caller can decide, and the only
## decision left here is "put it back".
##
## Returns false without touching anything when the id is not in the bag, or names
## something with no place on a body.
func wear(instance_id: String) -> bool:
	var at := bag.slot_of(instance_id)
	if at < 0:
		return false
	var item := bag.item_at(at)
	if item == null or not CozyItemDefs.is_slot(item.slot()):
		return false
	bag.remove_item(instance_id)
	var displaced := equipment.equip(item)
	if displaced != null and bag.add_item(displaced) < 0:
		# UNREACHABLE while the container and the capacity table agree, and an
		# ERROR rather than a return value because there is no correct way to carry
		# on: an item that exists nowhere is the one failure a player cannot see,
		# describe, or get back. Reaching here means the two disagree, which is a
		# broken build rather than a refused action.
		push_error("player: wearing %s displaced %s with nowhere to put it" % [
			item.display_name(), displaced.display_name()])
	return true


# ---------------------------------------------------------------- serialise

## Facts only. The shape follows `CozyNpcState`'s and the save rules in
## `docs/INVARIANTS.md`: no derived values, and nothing written that can be
## recomputed from what is.
func to_dict() -> Dictionary:
	return {
		"id": id,
		"pack": pack.items.duplicate(),
		"bag": bag.to_dict(),
		"equipment": equipment.to_dict(),
	}


static func from_dict(d: Dictionary) -> CozyPlayerState:
	var s := CozyPlayerState.new()
	s.id = String(d.get("id", PLAYER_ID))
	var items: Dictionary = d.get("pack", {})
	# The loop variable is named `material` rather than `id`, because `id`
	# would shadow the entity id above. GDScript permits the shadowing and
	# the bug it hides is not one anybody would look for.
	# GDScript lets it — the shadowing is legal and the bug it hides is not.
	for material in items:
		s.pack.add(String(material), float(items[material]))
	# ABSENT IS NOT AN ERROR: a file written before the player had a bag has no
	# bag in it, and the honest reading of "no bag" is "an empty one".
	if d.has("bag"):
		s.bag = CozyItemContainer.from_dict(d["bag"])
	if d.has("equipment"):
		s.equipment = CozyEquipment.from_dict(d["equipment"])
	return s
