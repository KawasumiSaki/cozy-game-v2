extends "res://tests/unit/unit_test.gd"
## The bag and what a character is wearing.
##
## These two files are the CONSUMER the loot roller never had: `CozyItemGenerator`
## rolls an instance and `CozyLootRoller` hands it back, and until now nothing in
## the game could hold one — only a test could. So the first case below is the
## one that matters, and it is the claim the whole split between a definition and
## an instance was built for:
##
##     TWO IRON SWORDS ARE TWO SWORDS.
##
## Both contribute, both are visible, and taking one off removes exactly one.
## Everything else here is bookkeeping, and bookkeeping is where a system that
## "works" quietly loses a player's item.

const BAG := 4


func _init() -> void:
	suite("equipment")
	case("a fresh bag is empty and shows its holes", _fresh_bag)
	case("an item lands in the first free slot", _add)
	case("a full bag refuses rather than replaces", _full)
	case("two swords are two swords", _two_swords)
	case("removing one sword leaves the other", _remove_one)
	case("a bag survives a file", _bag_round_trip)
	case("a smaller bag drops rather than shuffles", _resize)
	case("an item in a slot the bag lacks is dropped, and counted", _load_overflow)

	case("wearing displaces, and hands back what it displaced", _equip)
	case("two swords worn is still two swords", _two_worn_swords)
	case("the numbers move when it is put on", _stats_move)
	case("an unwearable slot is refused and named", _unknown_slot)
	case("what is worn survives a file", _equipment_round_trip)


# ---------------------------------------------------------------- the bag

func _fresh_bag() -> void:
	var bag := CozyItemContainer.new(BAG)
	eq("capacity", bag.capacity, BAG)
	eq("nothing in it", bag.count(), 0)
	is_true("empty", bag.is_empty())
	eq("every slot free", bag.free_slots(), BAG)
	# A hole is a slot, not an absence — the UI draws `capacity` squares.
	for i in BAG:
		eq("slot %d is a hole" % i, bag.item_at(i), null)
	eq("a slot past the end is not a slot", bag.item_at(BAG), null)


func _add() -> void:
	var bag := CozyItemContainer.new(BAG)
	eq("lands in slot 0", bag.add_item(_sword("a")), 0)
	eq("then slot 1", bag.add_item(_axe("b")), 1)
	eq("two items", bag.count(), 2)
	eq("two free", bag.free_slots(), 2)
	is_true("it has the sword", bag.has_item("a"))
	is_false("and not one it never had", bag.has_item("zzz"))
	eq("the sword is where it said", bag.item_at(0).definition_id, "iron_sword")
	# By definition, which is a different question from by id.
	eq("a sword is in the bag", bag.slot_of_definition("iron_sword"), 0)
	eq("no shield is", bag.slot_of_definition("wooden_shield"), -1)
	eq("an unknown id is nowhere", bag.slot_of("zzz"), -1)
	# Into a PARTICULAR slot, on purpose — a player dragging an item to a square.
	is_true("an empty slot accepts one", bag.add_item_at(3, _sword("c")))
	eq("it is where it was put", bag.item_at(3).instance_id, "c")
	is_false("and refuses a second into the same square", bag.add_item_at(3, _sword("d")))


func _full() -> void:
	var bag := CozyItemContainer.new(2)
	bag.add_item(_sword("a"))
	bag.add_item(_sword("b"))
	is_true("full", bag.is_full())
	eq("a third item is refused", bag.add_item(_sword("c")), -1)
	eq("and nothing was evicted", bag.count(), 2)
	is_false("the refused one is not in there", bag.has_item("c"))
	# `add_item_at` refuses an occupied slot rather than swapping: "put this here"
	# and "replace what is there" are different intentions.
	is_false("an occupied slot refuses a second item", bag.add_item_at(0, _sword("d")))
	eq("and slot 0 still holds the first", bag.item_at(0).instance_id, "a")
	is_false("and a slot the bag does not have", bag.add_item_at(2, _sword("e")))
	eq("nothing was placed", bag.count(), 2)


## THE CLAIM THE DEFINITION/INSTANCE SPLIT EXISTS FOR.
func _two_swords() -> void:
	var bag := CozyItemContainer.new(BAG)
	bag.add_item(_sword("a"))
	bag.add_item(_sword("b"))
	eq("both are in the bag", bag.count(), 2)
	ne("they are not the same object", bag.item_at(0), bag.item_at(1))
	ne("and not the same id", bag.item_at(0).instance_id, bag.item_at(1).instance_id)
	eq("same definition", bag.item_at(0).definition_id, bag.item_at(1).definition_id)
	eq("each is found by its own id", bag.slot_of("b"), 1)
	# `slot_of_definition` answers a DIFFERENT question, and only one of them.
	eq("and the definition question answers with one of them",
		bag.slot_of_definition("iron_sword"), 0)


func _remove_one() -> void:
	var bag := CozyItemContainer.new(BAG)
	bag.add_item(_sword("a"))
	bag.add_item(_sword("b"))
	var gone := bag.remove_item("a")
	ne("something came out", gone, null)
	eq("it was the right one", gone.instance_id, "a")
	eq("one left", bag.count(), 1)
	eq("and it is the other", bag.item_at(1).instance_id, "b")
	eq("its slot was not shuffled", bag.item_at(0), null)
	is_false("the removed one is gone", bag.has_item("a"))
	eq("removing it again is nothing", bag.remove_item("a"), null)


func _bag_round_trip() -> void:
	var bag := CozyItemContainer.new(BAG)
	bag.add_item(_sword("a"))
	bag.add_item_at(3, _axe("b"))
	# THROUGH A REAL SERIALISER, not just dict to dict. An in-memory round trip
	# cannot see a payload that `JSON.stringify` writes as a string — that is how
	# the chunk save was broken for as long as it was (`INVARIANTS`).
	var text := JSON.stringify(bag.to_dict())
	var back := CozyItemContainer.from_dict(JSON.parse_string(text))
	eq("capacity survived", back.capacity, BAG)
	eq("both items survived", back.count(), 2)
	eq("in their slots", back.item_at(3).instance_id, "b")
	eq("with their definitions", back.item_at(0).definition_id, "iron_sword")
	eq("and the same description", back.describe(), bag.describe())


func _resize() -> void:
	var bag := CozyItemContainer.new(4)
	bag.add_item(_sword("a"))
	bag.add_item_at(3, _axe("b"))
	bag.resize(2)
	eq("the bag is smaller", bag.capacity, 2)
	eq("what fitted in the kept slots stayed",
		bag.item_at(0).instance_id, "a")
	eq("and what did not is gone rather than shuffled",
		bag.count(), 1)


func _load_overflow() -> void:
	var d := {"capacity": 2, "slots": {"0": _sword("a").to_dict(),
		"5": _axe("b").to_dict()}}
	eq("the loader can say how many it could not place",
		CozyItemContainer.dropped_on_load(d), 1)
	var bag := CozyItemContainer.from_dict(d)
	eq("nothing was placed out of range", bag.count(), 1)
	eq("and it did not grow the bag to fit", bag.capacity, 2)


# ---------------------------------------------------------------- what is worn

func _equip() -> void:
	var eq := CozyEquipment.new()
	is_true("wearing nothing", eq.is_empty())
	is_true("nothing was displaced by the first", eq.equip(_sword("a")) == null)
	eq("it is on", eq.worn("weapon").instance_id, "a")
	is_true("in the slot its definition says",
		eq.is_wearing(CozyItemDefs.slot_of("iron_sword")))
	# A second sword in HAND displaces the first and HANDS IT BACK. An item
	# destroyed by putting another one on is the kind of loss that reads as a bug.
	eq("a second displaces the first", eq.equip(_sword("b")).instance_id, "a")
	eq("and the new one is on", eq.worn("weapon").instance_id, "b")
	eq("the first is not worn anywhere", eq.slot_wearing("a"), "")
	eq("but the second is", eq.slot_wearing("b"), "weapon")
	# Different slots do not displace each other.
	eq("a shield displaces nothing", eq.equip(_shield("s")), null)
	eq("two slots are worn", eq.worn_slots().size(), 2)
	eq("a slot it cannot go in is refused", eq.equip(null), null)


func _two_worn_swords() -> void:
	var eq := CozyEquipment.new()
	eq.equip(_sword("a"))
	eq.equip(_shield("s"))
	var mods := eq.modifiers()
	var sources := {}
	for m in mods:
		sources[String((m as Dictionary)["source"])] = true
	is_true("the sword is a source", sources.has("item:a"))
	is_true("and so is the shield", sources.has("item:s"))
	eq("two items, one list", eq.items().size(), 2)


## THE POINT OF THE WHOLE FILE: a rolled sword changes a number.
func _stats_move() -> void:
	var eq := CozyEquipment.new()
	var bare := eq.stat("attack", 0.0)
	eq.equip(_sword("a"))
	var armed := eq.stat("attack", 0.0)
	is_true("wearing a sword raises attack (%.1f -> %.1f)" % [bare, armed],
		armed > bare)
	# And it says the same thing as the resolver fed by hand, because it IS the
	# resolver — a second implementation here is a second thing to drift.
	var by_hand := CozyStats.resolve(eq.worn("weapon").modifiers(), "attack", 0.0)
	near("and it agrees with the resolver", armed, by_hand)
	eq("a stat nothing touches is the base", eq.stat("crit_chance", 0.0), 0.0)


func _unknown_slot() -> void:
	var d := {"weapon": _sword("a").to_dict(), "tail": _sword("b").to_dict()}
	var names := CozyEquipment.unknown_slots(d)
	eq("the slot the game does not have is named", names.size(), 1)
	eq("by name", names[0], "tail")
	var eq := CozyEquipment.from_dict(d)
	eq("and it was refused rather than stored", eq.worn_slots().size(), 1)
	eq("so it cannot contribute to a stat while being invisible",
		eq.items().size(), 1)


func _equipment_round_trip() -> void:
	var eq := CozyEquipment.new()
	eq.equip(_sword("a"))
	eq.equip(_shield("s"))
	var payload := eq.to_dict()
	var back := CozyEquipment.from_dict(JSON.parse_string(JSON.stringify(payload)))
	eq("both slots came back", back.worn_slots(), eq.worn_slots())
	eq("with the same items", back.worn("weapon").instance_id, "a")
	eq("and the same description", back.describe(), eq.describe())
	is_true("so the numbers match", is_equal_approx(
		back.stat("attack", 0.0), eq.stat("attack", 0.0)))


# ---------------------------------------------------------------- fixtures

func _sword(instance_id: String) -> CozyItemInstance:
	return CozyItemInstance.make(instance_id, "iron_sword", "common", 1)


func _axe(instance_id: String) -> CozyItemInstance:
	return CozyItemInstance.make(instance_id, "wooden_axe", "common", 1)


func _shield(instance_id: String) -> CozyItemInstance:
	return CozyItemInstance.make(instance_id, "wooden_shield", "common", 1)
