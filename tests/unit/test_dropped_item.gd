extends "res://tests/unit/unit_test.gd"
## What lying on the ground is, and the two rules that make it a place rather than
## a formality.
##
## Pure logic: no world, no player node, no frame. `CozyDroppedItem` is a `Node3D`
## but it never needs to be IN anything for any of this — its position is a fact it
## owns and its marker is built from `kind` — which is why the interesting half of
## this system can be checked here instead of in a stage that boots a village.
##
## The two rules are the radius (a drop a player standing at their own reach cannot
## simply absorb) and the payload fork (materials are amounts, items are
## instances), and both are the kind of thing that is invisible when it is wrong:
## the wood still ends up in the pack.
##
## EVERY NODE MADE HERE IS FREED, and that is not tidiness. A `Node3D` builds a
## mesh and a material, and the dummy renderer counts them: twelve unfreed drops
## put six `ERROR` lines on stderr at exit, which turns "0 ERROR" into a lie for
## every check in this file and for the game's own baseline. It was the first
## version of this suite that found that, by doing exactly that.


func _init() -> void:
	suite("dropped item")
	case("a material drop is an id and an amount", _material)
	case("an item drop carries the instance, not the definition", _item)
	case("a drop survives a real serialiser", _round_trip)
	case("a payload that names nothing is refused", _refusals)
	case("materials always fit, items need a slot", _fitting)
	case("a drop that does not fit is left exactly where it was", _refused_is_left_alone)
	case("the radius is flatter than a reach, and shorter", _the_radius)


func _material() -> void:
	var drop := CozyDroppedItem.new()
	drop.setup_material("wood", 4.0)
	eq("it knows which kind it is", drop.kind, CozyDroppedItem.KIND_MATERIAL)
	is_true("and says so", drop.is_material())
	eq("the id came through", drop.material_id, "wood")
	near("and the amount", drop.amount, 4.0)
	eq("it names itself the way a log line wants", drop.display_name(), "Wood x4")
	is_false("and it holds no item", drop.item != null)
	# A colour of its own, taken from the material table — so a pile of wood on the
	# ground and a plank in a wall are recognisably the same stuff.
	eq("its marker wears the material's own colour", drop.mark_color(),
		Color(CozyMaterials.get_def("wood")["color"]))
	drop.free()


## THE FORK THE WHOLE PAYLOAD EXISTS FOR. Two iron swords are two swords, and what
## makes them two is the instance with its own rolled affixes — the same argument
## `CozyItemContainer` makes about why it is not a `CozyInventory`. A drop that
## stored a definition id would put a sword on the ground that is the same sword
## as every other one, and the roll that made it worth picking up would be gone.
func _item() -> void:
	var made := CozyItemInstance.make("item_007", "iron_sword", "rare", 3)
	made.affixes.append({"id": "strength", "value": 6.0})
	var drop := CozyDroppedItem.new()
	drop.setup_item(made)
	eq("it knows which kind it is", drop.kind, CozyDroppedItem.KIND_ITEM)
	is_false("and says so", drop.is_material())
	is_true("it holds THE instance, not a copy of the definition",
		drop.item == made)
	eq("so the roll came with it", drop.item.affixes.size(), 1)
	eq("and the name is the item's", drop.display_name(), made.display_name())
	is_false("and it is not wearing a material's colour",
		drop.mark_color() == Color(CozyMaterials.get_def("wood")["color"]))
	drop.free()


## Through a REAL serialiser. An in-memory round trip cannot see a payload that
## `JSON.stringify` turns into a string, and that is how the terrain chunk's flags
## were lost — the data survived and the thing reading it did not.
func _round_trip() -> void:
	var there := CozyDroppedItem.new()
	there.id = "drop_004"
	there.floor_index = 0
	there.setup_material("copper", 7.0)
	there.place(Vector3(-3.5, 0.0, 8.25))

	var payload: Dictionary = JSON.parse_string(JSON.stringify(there.to_dict()))
	var back := CozyDroppedItem.new()
	is_true("the payload was readable", back.apply_dict(payload))
	eq("the id came back", back.id, "drop_004")
	eq("the kind came back", back.kind, CozyDroppedItem.KIND_MATERIAL)
	eq("what it is came back", back.material_id, "copper")
	near("how much came back", back.amount, 7.0)
	# THE POSITION IS THE ONE THAT MATTERS, and it is the one a `to_dict` that read
	# `global_position` would have silently written as the origin: a node outside
	# the tree has no world transform, and `to_global()` on one is an engine error.
	eq("and it is still where it fell", back.at, Vector3(-3.5, 0.0, 8.25))
	eq("so the two describe themselves the same", back.describe(), there.describe())

	# The other payload, which has more inside it to lose.
	var prize := CozyItemInstance.make("item_011", "steel_sword", "epic", 2)
	prize.affixes.append({"id": "strength", "value": 4.5})
	prize.glamour_id = "iron_sword"
	var gear := CozyDroppedItem.new()
	gear.id = "drop_005"
	gear.setup_item(prize)
	var gear_back := CozyDroppedItem.new()
	is_true("an item payload is readable too",
		gear_back.apply_dict(JSON.parse_string(JSON.stringify(gear.to_dict()))))
	eq("the same item id", gear_back.item.instance_id, "item_011")
	eq("the same definition", gear_back.item.definition_id, "steel_sword")
	eq("the same rarity", gear_back.item.rarity, "epic")
	eq("the rolled affix survived", gear_back.item.affixes.size(), 1)
	near("with its value", float(gear_back.item.affixes[0]["value"]), 4.5)
	eq("and the glamour, which is a field and not an affix",
		gear_back.item.glamour_id, "iron_sword")
	eq("so the two describe themselves the same",
		gear_back.describe(), gear.describe())
	there.free()
	back.free()
	gear.free()
	gear_back.free()


## A DROP WITH NOTHING IN IT IS REFUSED, and it has to be: a box on the ground that
## can never be picked up and never goes away looks exactly like the game working,
## and it would be saved and reloaded forever.
func _refusals() -> void:
	var cases := {
		"no kind at all": {"id": "drop_001", "position": [0.0, 0.0, 0.0]},
		"a kind nothing knows": {"id": "drop_002", "kind": "relic",
			"position": [0.0, 0.0, 0.0]},
		"a material with no id": {"id": "drop_003", "kind": "material",
			"material_id": "", "amount": 2.0, "position": [0.0, 0.0, 0.0]},
		"a material of nothing": {"id": "drop_004", "kind": "material",
			"material_id": "wood", "amount": 0.0, "position": [0.0, 0.0, 0.0]},
		"an item with no payload": {"id": "drop_005", "kind": "item",
			"position": [0.0, 0.0, 0.0]},
		"an item that is not an item": {"id": "drop_006", "kind": "item",
			"item": {"instance_id": "", "definition_id": ""},
			"position": [0.0, 0.0, 0.0]},
		"a position that is not a position": {"id": "drop_007", "kind": "material",
			"material_id": "wood", "amount": 1.0, "position": [1.0, 2.0]},
		"an id nobody can name it by": {"kind": "material",
			"material_id": "wood", "amount": 1.0, "position": [0.0, 0.0, 0.0]},
	}
	var refused := 0
	for why in cases:
		var probe := CozyDroppedItem.new()
		if not probe.apply_dict(cases[why]):
			refused += 1
		probe.free()
	eq("every unreadable payload is refused", refused, cases.size())

	# THE CONTROL, or the case above would pass on an `apply_dict` that refused
	# everything — including the drops the game actually makes.
	var good := CozyDroppedItem.new()
	is_true("and a real one is not",
		good.apply_dict({"id": "drop_008", "kind": "material", "material_id": "wood",
			"amount": 3.0, "position": [1.0, 0.0, 2.0]}))
	eq("with what it says on the label", good.material_id, "wood")
	good.free()


func _fitting() -> void:
	var state := CozyPlayerState.new()
	var wood := CozyDroppedItem.new()
	wood.setup_material("wood", 2.0)
	is_true("a material always fits", wood.fits_in(state))
	is_true("even with nothing to put it in", wood.fits_in(CozyPlayerState.new()))

	# The bag's capacity IS the bag's tier, so a full bag is the one thing that can
	# turn a drop away — and it is the bag's own answer, not a number kept here.
	var bagged := CozyDroppedItem.new()
	bagged.setup_item(CozyItemInstance.make("item_001", "iron_sword"))
	is_true("an item fits an empty bag", bagged.fits_in(state))
	while not state.bag.is_full():
		state.bag.add_item(CozyItemInstance.make(
			"filler_%d" % state.bag.count(), "iron_sword"))
	is_false("and does not fit a full one", bagged.fits_in(state))
	is_false("nor into nothing at all", bagged.fits_in(null))
	wood.free()
	bagged.free()


## THE FAILURE THE PLAYER EXPERIENCES AS A LOSS. A drop that does not fit and is
## destroyed anyway is a sword somebody watched fall and can never find — worse
## than being told there is no room, because there is nothing to explain.
func _refused_is_left_alone() -> void:
	var state := CozyPlayerState.new()
	while not state.bag.is_full():
		state.bag.add_item(CozyItemInstance.make(
			"filler_%d" % state.bag.count(), "iron_sword"))
	var prize := CozyItemInstance.make("item_002", "steel_sword", "legendary", 4)
	var drop := CozyDroppedItem.new()
	drop.setup_item(prize)
	drop.place(Vector3(2.0, 0.0, -1.0))

	var before := state.bag.count()
	is_false("it is not collected", drop.collect_into(state))
	eq("the bag did not change", state.bag.count(), before)
	is_false("and it now does not hold the sword", state.bag.has_item("item_002"))
	is_true("the drop still holds it, so it can be picked up later",
		drop.item == prize)
	eq("and it has not moved", drop.at, Vector3(2.0, 0.0, -1.0))

	# Make room, and it is still there to be had. This is the sentence the whole
	# system exists for.
	state.bag.remove_at(0)
	is_true("with a slot free it is collected", drop.collect_into(state))
	is_true("and the sword is the one that went in", state.bag.has_item("item_002"))

	# And a material drop goes to the PACK, which is a different container holding
	# a different kind of thing from the bag the sword is in — the same fork, seen
	# from the side that has no capacity at all.
	var wood := CozyDroppedItem.new()
	wood.setup_material("wood", 5.0)
	is_true("a material is collected", wood.collect_into(state))
	near("into the pack", state.pack.count("wood"), 5.0)
	eq("and the bag did not grow a wood", state.bag.count(), state.bag.capacity)
	drop.free()
	wood.free()


## THE GROUND IS ONLY A PLACE IF SOMETHING CAN BE LEFT ON IT.
##
## `_gather_from` refuses to work a node from further away than its reach, and a
## drop lands at the node's edge — on the side the player is standing. So the gap
## between a player at the limit of their reach and the thing they just knocked
## loose IS the reach: 1.3 m for a tree, a rock and everything else, and 0.8 m for
## a crop. A pickup radius as long as the SHORTEST of those would take every drop
## on the frame it appeared, and "掉在地上" would be the same code as "直接进包"
## with a different comment.
##
## ASSERTED FOR EVERY GATHERED NODE, not just the tree, because a short reach is
## exactly the row that reintroduces it — and it already did once. The radius was
## 1.0 when this case was written, which felt right and quietly made harvesting a
## crop a different mechanic from felling a tree. Nothing in the game would have
## said so; the wood simply would have arrived without anyone walking to it.
func _the_radius() -> void:
	is_true("the radius is a real distance", CozyDroppedItem.PICKUP_RADIUS > 0.0)
	var checked := 0
	for id in CozyObjectDefs.OBJECTS:
		var row := String(id)
		if not CozyObjectDefs.is_gathered(row):
			continue
		var reach := CozyObjectDefs.reach_of(row)
		if reach <= 0.0:
			continue
		checked += 1
		is_true("a drop from '%s' lands further away than the radius" % row,
			reach > CozyDroppedItem.PICKUP_RADIUS)
	is_true("and there was something to check", checked > 0)

	# Flat, like the swing's reach and for the same reason: a thing on a slope is
	# not further away because of the slope, and a height difference of a storey
	# must not hide something lying at the player's feet.
	var drop := CozyDroppedItem.new()
	drop.setup_material("stone", 1.0)
	drop.place(Vector3(1.0, 0.0, 0.0))
	is_true("a metre away is out of reach",
		not drop.in_range(Vector3(1.0 + CozyDroppedItem.PICKUP_RADIUS + 0.05, 0.0, 0.0)))
	is_true("just inside is in reach",
		drop.in_range(Vector3(1.0 + CozyDroppedItem.PICKUP_RADIUS - 0.05, 0.0, 0.0)))
	is_true("and a floor above it does not matter",
		drop.in_range(Vector3(1.0, 3.0, 0.0)))
	drop.free()
