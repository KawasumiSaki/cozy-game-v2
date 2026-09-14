extends "res://tests/unit/unit_test.gd"
## Rolling an item: rarity, affixes, values — and the two properties that make a
## loot drop a fact rather than a mood.
##
## The design document's section 2.1 calls Definition-versus-Instance its most
## important decision, and section 21 makes the weights the core of the loot
## system. Both are asserted here without a world, because neither needs one.
##
## Every case carries a control, because "the seed is respected" and "nothing is
## ever random" are the same green number.


func _init() -> void:
	suite("items")
	case("the tables describe items that can be rolled", _tables_are_sane)
	case("the same seed rolls the same item, twice", _deterministic)
	case("a different seed rolls a different item", _seeds_differ)
	case("rarity decides how many affixes, and nothing else", _rarity_decides_count)
	case("one sword never rolls the same affix twice", _no_duplicates)
	case("an affix fits the item it rolled on", _pool_is_respected)
	case("every rolled value is inside its own range", _values_in_range)
	case("a definition is not an instance", _definition_is_not_instance)
	case("two of the same sword are two sources", _instances_are_separate_sources)
	case("an item is worth what its definition and affixes say", _modifiers)
	case("the roll ratio is derived from the value", _roll_ratio)
	case("an item survives a real serializer", _round_trip)
	case("a pair that cannot be rolled says so", _refusals)


# ---------------------------------------------------------------- the tables

func _tables_are_sane() -> void:
	eq("every affix names a real stat and a sane range", CozyAffixDefs.complaints(), [])
	eq("every item is worn in a real slot for a real stat", CozyItemDefs.complaints(), [])

	# The control for the pair above: an empty complaint list has to mean
	# something. If the tables were empty, both would pass and prove nothing.
	is_true("and there are affixes to complain about", CozyAffixDefs.ids().size() >= 8)
	is_true("and items", CozyItemDefs.ids().size() >= 5)


# ---------------------------------------------------------------- determinism

func _deterministic() -> void:
	var a := _roll("iron_sword", "rare", 42)
	var b := _roll("iron_sword", "rare", 42)
	eq("the same seed gives the same rarity", a.rarity, b.rarity)
	eq("the same affixes", a.affixes, b.affixes)
	eq("and the same values", a.to_dict()["affixes"], b.to_dict()["affixes"])

	# The control: a generator that ignored the seed would pass everything above.
	is_true("and the item actually has something rolled on it", a.affixes.size() > 0)


func _seeds_differ() -> void:
	var seen := {}
	for s in range(1, 40):
		seen[_roll("iron_sword", "legendary", s).to_dict()["affixes"]] = true
	is_true("different seeds produce different items", seen.size() > 1)


# ---------------------------------------------------------------- rarity

func _rarity_decides_count() -> void:
	eq("a common item has nothing rolled on it", _roll("iron_sword", "common", 7).affixes.size(), 0)
	eq("an uncommon has one", _roll("iron_sword", "uncommon", 7).affixes.size(), 1)
	eq("a rare has two", _roll("iron_sword", "rare", 7).affixes.size(), 2)
	eq("an epic has three", _roll("iron_sword", "epic", 7).affixes.size(), 3)
	eq("a legendary has four", _roll("iron_sword", "legendary", 7).affixes.size(), 4)

	# The control for the whole case: the count comes from the RARITY, so the same
	# rarity on a different item is the same number.
	eq("and the count follows the rarity, not the item",
		_roll("copper_ring", "rare", 7).affixes.size(), 2)


func _no_duplicates() -> void:
	for s in range(1, 60):
		var ids := {}
		for a in _roll("iron_sword", "legendary", s).affixes:
			ids[String((a as Dictionary)["id"])] = true
		var it := _roll("iron_sword", "legendary", s)
		eq("seed %d rolled %d affix(es) with no repeat" % [s, it.affixes.size()],
			ids.size(), it.affixes.size())


# ---------------------------------------------------------------- the pool

## Section 18: an affix that names weapons must not turn up on boots, and the
## reverse. Asserted over many rolls rather than one, because a single roll could
## pass by luck.
func _pool_is_respected() -> void:
	for s in range(1, 40):
		for a in _roll("leather_boots", "legendary", s).affixes:
			var id := String((a as Dictionary)["id"])
			is_true("'%s' fits boots" % id, _fits(id, "boots"))
		for a in _roll("iron_sword", "legendary", s).affixes:
			var id := String((a as Dictionary)["id"])
			is_true("'%s' fits a sword" % id, _fits(id, "weapon"))

	# The control: there IS an affix that fits a weapon and not boots, so the
	# pools genuinely differ and the case above is not "everything fits".
	is_true("life steal fits a weapon", _fits("life_steal", "weapon"))
	is_false("and does not fit boots", _fits("life_steal", "boots"))


func _values_in_range() -> void:
	for s in range(1, 40):
		for a in _roll("iron_sword", "legendary", s).affixes:
			var d := a as Dictionary
			var def := CozyAffixDefs.get_def(String(d["id"]))
			var v := float(d["value"])
			is_true("%s rolled inside its range" % d["id"],
				v >= float(def["min"]) and v <= float(def["max"]))


# ---------------------------------------------------------------- instance

## Section 2.1, as an assertion: the table is shared, the rolls are not.
func _definition_is_not_instance() -> void:
	var a := _roll("iron_sword", "rare", 3)
	var b := _roll("iron_sword", "rare", 4)
	eq("both are iron swords", a.definition_id, b.definition_id)
	eq("from the same definition", a.definition(), b.definition())
	ne("but they are not the same item", a.affixes, b.affixes)


## THE REASON THE SOURCE IS THE INSTANCE ID. Two of the same sword must add to
## each other rather than replace, and only a per-instance source can do that —
## keyed by definition, the second sword would silently erase the first.
func _instances_are_separate_sources() -> void:
	var a := _roll("iron_sword", "rare", 11, "item_001")
	var b := _roll("iron_sword", "rare", 12, "item_002")
	is_true("they are different sources", a.source() != b.source())

	var worn: Array = []
	for it in [a, b]:
		for m in it.modifiers():
			worn.append(m)
	eq("wearing both keeps both swords' modifiers",
		CozyStats.has_source(worn, a.source()) and CozyStats.has_source(worn, b.source()), true)

	# Taking one off leaves the other untouched, which is the whole point.
	CozyStats.remove_source(worn, a.source())
	is_false("the first is gone", CozyStats.has_source(worn, a.source()))
	is_true("and the second is not", CozyStats.has_source(worn, b.source()))


func _modifiers() -> void:
	var it := CozyItemInstance.make("item_009", "iron_sword", "common", 1)
	var m := it.modifiers()
	near("the sword's own attack is there", CozyStats.resolve(m, "attack", 0.0), 10.0)
	near("and its attack speed multiplies", CozyStats.resolve(m, "attack_speed", 1.0), 2.0)

	# ... and a rolled affix lands on the same footing.
	var rolled := CozyItemInstance.make("item_010", "iron_sword", "common", 1)
	rolled.affixes = [{"id": "strength", "value": 6.0}]
	near("a rolled +6 attack adds to the sword's own 10",
		CozyStats.resolve(rolled.modifiers(), "attack", 0.0), 16.0)


func _roll_ratio() -> void:
	var it := CozyItemInstance.make("item_011", "iron_sword", "common", 1)
	it.affixes = [{"id": "strength", "value": 2.0}]   # strength is 2.0 .. 8.0
	near("the bottom of the range is a zero ratio", it.roll_ratio("strength"), 0.0)
	it.affixes = [{"id": "strength", "value": 8.0}]
	near("the top is one", it.roll_ratio("strength"), 1.0)
	it.affixes = [{"id": "strength", "value": 5.0}]
	near("and the middle is the middle", it.roll_ratio("strength"), 0.5)
	near("an affix it does not have is no ratio at all", it.roll_ratio("life_steal"), 0.0)


## `docs/INVARIANTS.md`: a `to_dict()` that never passes through a serializer is
## not a save format. This goes out as TEXT and comes back through the parser.
func _round_trip() -> void:
	var it := _roll("wooden_axe", "epic", 21, "item_021")
	var again := CozyItemInstance.from_dict(
		JSON.parse_string(JSON.stringify(it.to_dict())))
	eq("the id survives", again.instance_id, it.instance_id)
	eq("the definition survives", again.definition_id, it.definition_id)
	eq("the rarity survives", again.rarity, it.rarity)
	eq("the level survives", again.level, it.level)
	eq("the affixes survive", again.affixes, it.affixes)
	eq("so does the source, so a reload can still take it off",
		again.source(), it.source())


func _refusals() -> void:
	is_true("an item that does not exist is refused",
		CozyItemGenerator.reject_reason("excalibur", "rare") != "")
	is_true("and the reason names it",
		CozyItemGenerator.reject_reason("excalibur", "rare").contains("excalibur"))
	is_true("a rarity that does not exist is refused",
		CozyItemGenerator.reject_reason("iron_sword", "mythic") != "")
	eq("a real pair is not", CozyItemGenerator.reject_reason("iron_sword", "rare"), "")
	eq("and a refused pair produces no item",
		CozyItemGenerator.generate("excalibur", "rare", 1, _rng(1), "item_000"), null)


# ---------------------------------------------------------------- helpers

func _rng(seed_value: int) -> RandomNumberGenerator:
	var r := RandomNumberGenerator.new()
	r.seed = seed_value
	return r


func _roll(definition: String, rarity: String, seed_value: int,
		id := "item_001") -> CozyItemInstance:
	return CozyItemGenerator.generate(definition, rarity, 1, _rng(seed_value), id)


func _fits(affix_id: String, item_type: String) -> bool:
	return (CozyAffixDefs.get_def(affix_id)["types"] as Array).has(item_type)
