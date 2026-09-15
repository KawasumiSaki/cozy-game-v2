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
