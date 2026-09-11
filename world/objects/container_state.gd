class_name CozyContainerState
extends RefCounted
## A container is an inventory with a capacity (V2.1 doc #42, and #35).
##
## Deliberately NOT a second storage system. It OWNS a `CozyInventory` and adds
## the only two things a chest has that a wallet does not: a limit, and contents
## that belong to a place in the world rather than to a person.
##
## Doc #35 is explicit that a wall's wood, a chest's contents and a resident's
## pack are one store with many callers:
##
##     "不要为建筑材料建立一套孤立库存系统."
##
## So the building inventory, the resident's pack and this all speak the same
## `CozyInventory` vocabulary — `add` / `count` / `spend` — and a material added
## to the game flows through all three without any of them changing.
##
## EVERY transfer is all-or-nothing. A half-emptied pack is worse than a refused
## deposit, because by the time the caller learns it failed they have already
## been told the load moved.

const DEFAULT_CAPACITY := 20.0

var inventory := CozyInventory.new()
var capacity := DEFAULT_CAPACITY


func stored() -> float:
	return inventory.total()


func free_space() -> float:
	return maxf(0.0, capacity - stored())


## Amounts are floats (a tree giving 3.5 wood, doc #36), so `20.0` minus a
## sum of thirds must not read as full and wedge the container shut.
func has_room_for(n: float) -> bool:
	return n <= free_space() + 0.0001


## Returns false and moves NOTHING if the whole amount does not fit.
func deposit(id: String, n: float) -> bool:
	if n <= 0.0 or not has_room_for(n):
		return false
	inventory.add(id, n)
	return true


func withdraw(id: String, n: float) -> bool:
	if n <= 0.0:
		return false
	return inventory.spend({id: n})


func is_empty() -> bool:
	return stored() <= 0.0


## Contents in a fixed order, so callers that iterate (the hauler picking a load)
## make the same choice every time. Everything procedural here is deterministic.
func sorted_ids() -> Array:
	var ids: Array = inventory.items.keys()
	ids.sort()
	return ids


func describe() -> String:
	return "%s  %.0f/%.0f" % [inventory.describe(), stored(), capacity]
