extends "res://tests/unit/unit_test.gd"
## The two swaps between what a player CARRIES and what a player WEARS.
##
## `CozyEquipment` already has its own suite for the rules of a body — which place
## a second ring goes in, what displacement returns. What is tested here is the
## layer above it, and it exists because the two swaps are the only places in the
## game where an item can go MISSING rather than merely go wrong:
##
##   take it off, then find there is nowhere to put it  -> worn by nobody, carried
##                                                         by nobody
##   put it on, and drop whatever it displaced          -> the same, from the other
##                                                         direction
##
## Neither shows up on screen as anything but "my sword is gone", and neither can
## be seen in an assertion about the state, because the state after the loss is
## consistent — it just no longer contains the item.
##
## Pure logic: no world, no panels, no frames.


func _init() -> void:
	suite("player gear")
	case("taking something off puts it in the pack", _stow_moves_it)
	case("a full pack refuses, and the item stays on the body", _stow_refuses_whole)
	case("taking off something that is not worn is refused", _stow_nothing)
	case("putting something on hands back what it displaced", _wear_swaps)
	case("a swap never loses anything", _nothing_is_lost)
	case("putting on something not in the pack is refused", _wear_nothing)
	case("and what is worn survives a file, place by place", _round_trip)


func _stow_moves_it() -> void:
	var s := CozyPlayerState.new()
	var ring := CozyItemInstance.make("item_001", "copper_ring")
	s.equipment.equip(ring)
	is_true("it is worn first", s.equipment.is_wearing("item_001"))
	is_true("taking it off works", s.stow("item_001"))
	is_false("and it is no longer worn", s.equipment.is_wearing("item_001"))
	is_true("it is in the pack instead", s.bag.has_item("item_001"))


## THE SWAP THAT CAN LOSE A THING, refused.
##
## The other order — take it off, then discover the pack is full — is what this
## exists to make impossible. What is asserted is not just the return value: it is
## that the item is STILL ON THE BODY afterwards, because "returned false" and
## "returned false and dropped the item anyway" are the same to a caller that only
## reads the return value.
func _stow_refuses_whole() -> void:
	var s := CozyPlayerState.new()
	var sword := CozyItemInstance.make("item_001", "iron_sword")
	s.equipment.equip(sword)
	while not s.bag.is_full():
		s.bag.add_item(CozyItemInstance.make("filler_%d" % s.bag.count(), "iron_sword"))
	var carried := s.bag.count()

	is_false("it refuses", s.stow("item_001"))
	is_true("and the sword is STILL WORN", s.equipment.is_wearing("item_001"))
	is_false("and did not also end up in the pack", s.bag.has_item("item_001"))
	eq("and nothing else in the pack moved", s.bag.count(), carried)

	# And with one place free it goes, which is the control that keeps the case
	# above from passing on a `stow` that refuses everything.
	s.bag.remove_at(0)
	is_true("with a place free it moves", s.stow("item_001"))
	is_false("off the body", s.equipment.is_wearing("item_001"))
	is_true("and into the pack", s.bag.has_item("item_001"))


func _stow_nothing() -> void:
	var s := CozyPlayerState.new()
	is_false("an id nobody is wearing is refused", s.stow("item_999"))
	eq("and the pack is untouched", s.bag.count(), 0)


## DISPLACEMENT IS RETURNED, which is the reason `equip` is written the way it is:
## the caller has somewhere to put the item, and the two places that call it are
## both swaps. A body that silently dropped what it pushed out would have been
## simpler and would have eaten a sword every time a better one was found.
func _wear_swaps() -> void:
	var s := CozyPlayerState.new()
	var steel := CozyItemInstance.make("item_001", "steel_sword")
	var iron := CozyItemInstance.make("item_002", "iron_sword")
	s.equipment.equip(steel)
	s.bag.add_item(iron)

	is_true("putting the second sword on works", s.wear("item_002"))
	is_true("it is the one being worn", s.equipment.is_wearing("item_002"))
	is_false("the first is no longer worn", s.equipment.is_wearing("item_001"))
	is_true("and it went into the pack", s.bag.has_item("item_001"))
	is_false("and it is not also still in the pack", s.bag.has_item("item_002"))


## THE PROPERTY, rather than the two cases: whatever was carried before is carried
## or worn after, and nothing is in both places. Taking the item out of the pack
## frees exactly the place the displaced one needs, so this cannot fail while the
## container and the capacity table agree — and if they ever stop agreeing, this is
## the assertion that says so.
func _nothing_is_lost() -> void:
	var s := CozyPlayerState.new()
	# Exactly what the body has places for, so nothing is displaced on the way in
	# and the only swap under test is the one below.
	for i in 2:
		s.equipment.equip(CozyItemInstance.make("ring_%d" % i, "copper_ring"))
	for i in 3:
		s.equipment.equip(CozyItemInstance.make("charm_%d" % i, "jade_charm"))
	s.equipment.equip(CozyItemInstance.make("steel", "steel_sword"))
	s.bag.add_item(CozyItemInstance.make("swap_me", "iron_sword"))
	s.bag.add_item(CozyItemInstance.make("spare", "wooden_axe"))

	var before := _all_ids(s)
	eq("the body started full", before.size(), 8)
	is_true("the swap happened", s.wear("swap_me"))
	var after := _all_ids(s)

	eq("nothing was lost and nothing was duplicated", after.size(), before.size())
	for id in before:
		is_true("'%s' is still somewhere" % id, after.has(id))
	is_true("and the new one is worn", s.equipment.is_wearing("swap_me"))
	is_true("and the one it displaced is in the pack", s.bag.has_item("steel"))


func _wear_nothing() -> void:
	var s := CozyPlayerState.new()
	is_false("an id that is not in the pack is refused", s.wear("item_999"))
	# ...and so is something that is in the pack but names no body place. A file can
	# carry an item id this build has never heard of, and `equip` would take it and
	# put it nowhere.
	var stray := CozyItemInstance.make("item_003", "no_such_item")
	s.bag.add_item(stray)
	is_false("and so is a thing with no place on a body", s.wear("item_003"))
	is_true("which is left in the pack rather than eaten", s.bag.has_item("item_003"))


## PLACE BY PLACE, not as a set. A ring in the second place and a ring in the first
## are two different states of the same two rings, and a save that put both back in
## the first would look exactly like a save that worked.
func _round_trip() -> void:
	var s := CozyPlayerState.new()
	s.equipment.equip(CozyItemInstance.make("item_001", "copper_ring"))
	s.equipment.equip(CozyItemInstance.make("item_002", "copper_ring"))
	s.equipment.equip(CozyItemInstance.make("item_003", "iron_helmet"))
	s.bag.add_item(CozyItemInstance.make("item_004", "steel_sword"))
	# Through a real serialiser, and BOTH halves of the state: the worn slots and
	# the pack they swap with are one round trip.
	var back := CozyPlayerState.from_dict(
		JSON.parse_string(JSON.stringify(s.to_dict())))

	eq("the first ring is still in the first place",
		back.equipment.worn("ring", 0).instance_id, "item_001")
	eq("and the second in the second",
		back.equipment.worn("ring", 1).instance_id, "item_002")
	eq("the helmet is where a helmet goes",
		back.equipment.worn("helmet", 0).instance_id, "item_003")
	is_true("nothing is in the third ring place the body does not have",
		back.equipment.worn("ring", 2) == null)
	eq("the pack came back too", back.bag.item_at(0).instance_id, "item_004")
	eq("and the two describe themselves the same", back.describe(), s.describe())


# ---------------------------------------------------------------- helpers

## Every item id this player has anywhere — worn or carried. A SET, because the
## question is whether anything went missing, and a count cannot tell one lost item
## from one duplicated item.
func _all_ids(s: CozyPlayerState) -> Array:
	var out: Array = []
	for it in s.equipment.items():
		out.append(it.instance_id)
	for it in s.bag.get_items():
		out.append(it.instance_id)
	return out
