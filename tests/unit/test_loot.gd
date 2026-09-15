extends "res://tests/unit/unit_test.gd"
## What a monster leaves behind, measured without a monster.
##
## A DROP THAT DOES NOT HAPPEN is the hardest kind of bug to notice, because
## nothing is the normal outcome of most rolls. So the cases here lean on the two
## things that make an absent drop visible: a stated chance has to be the rate a
## player actually sees, and a table that could never produce anything has to be
## refused rather than rolled.
##
## Pure logic throughout — a table, a seed, and a list of what fell out.

## How many draws each statistical case takes. Enough that a 0.35 rate lands
## inside a wide band every time, and cheap enough to run on every check.
const ROLLS := 2000


func _init() -> void:
	suite("loot")
	case("the tables describe drops that can happen", _tables_are_sane)
	case("the same seed drops the same things", _deterministic)
	case("a different seed drops different things", _seeds_differ)
	case("a certain drop always drops, and an impossible one never does", _the_extremes)
	case("a stated chance is the rate a player sees", _rates_hold)
	case("a pick table draws in proportion to its weights", _weights_hold)
	case("equipment drops are real rolled items", _equipment_is_real)
	case("a table that is not a drop table says so", _refusals)
	case("ids are only spent on the drops that need them", _ids_are_counted)


# ---------------------------------------------------------------- the tables

func _tables_are_sane() -> void:
	eq("every table can produce what it says", CozyLootDefs.complaints(), [])

	# The control for the line above: an empty complaint list only means
	# something if there are tables to complain about.
	is_true("and there are tables", CozyLootDefs.ids().size() >= 3)
	is_true("and a goblin drops equipment",
		_pick_of("goblin") != "")


# ---------------------------------------------------------------- determinism

func _deterministic() -> void:
	var a := CozyLootRoller.roll("goblin", _rng(7), 1)
	var b := CozyLootRoller.roll("goblin", _rng(7), 1)
	eq("the same seed drops the same number of things", a["drops"].size(), b["drops"].size())
	eq("with the same kinds", _kinds(a), _kinds(b))
	eq("and the same equipment", _equipment_ids(a), _equipment_ids(b))
	is_true("and something actually dropped", (a["drops"] as Array).size() > 0)


func _seeds_differ() -> void:
	var seen := {}
	for s in range(1, 60):
		seen[_kinds(CozyLootRoller.roll("goblin", _rng(s), 1))] = true
	is_true("different seeds produce different drops", seen.size() > 1)


## The two ends of the range, which a rate cannot tell apart from a table that
## is simply wrong in one direction.
func _the_extremes() -> void:
	# Gold is a certain drop in the goblin's table.
	var gold := 0
	for s in range(1, 40):
		for d in (CozyLootRoller.roll("goblin", _rng(s), 1)["drops"] as Array):
			if String((d as Dictionary)["kind"]) == CozyLootRoller.DROP_GOLD:
				gold += 1
	eq("a certain drop drops every time", gold, 39)

	# ... and the slime produces only what its own table names. A table that
	# invented a drop would be caught here.
	#
	# ASKED OF THE TABLE, NOT OF A HARDCODED PAIR OF IDS. This case used to read the
	# `id` of every drop and assert it was wheat or wood, which said the same thing
	# while the slime had exactly two item rows. It stopped saying it the moment
	# the 5% gear entry arrived: an equipment drop carries no `id` at all, so it
	# read as "something not on the table" and the case went red for a table that
	# was perfectly correct. The question was never about `id` — it is "can this
	# drop have come from a row of this table" — so it is asked of the rows.
	#
	# The two constant sets share their values (`DROP_ITEM` is `KIND_ITEM`), which
	# is why a rolled drop's kind can be looked up in the definitions directly.
	var table_items := {}
	var table_kinds := {}
	for e in CozyLootDefs.entries("slime"):
		var row: Dictionary = e
		table_kinds[String(row.get("kind", ""))] = true
		if String(row.get("kind", "")) == CozyLootDefs.KIND_ITEM:
			table_items[String(row.get("id", ""))] = true

	var other := 0
	for s in range(1, 40):
		for d in (CozyLootRoller.roll("slime", _rng(s), 1)["drops"] as Array):
			var drop: Dictionary = d
			var k := String(drop["kind"])
			if not table_kinds.has(k):
				other += 1
			elif k == CozyLootDefs.KIND_ITEM and not table_items.has(String(drop["id"])):
				other += 1
	eq("and nothing that is not on the table", other, 0)
	# THE CONTROL: the loop above counts nothing when nothing drops, so the case
	# only means something if the slime's rare row can actually fire.
	is_true("and the slime can drop gear at all",
		table_kinds.has(CozyLootDefs.KIND_EQUIPMENT))


func _rates_hold() -> void:
	var r := CozyLootRoller.simulate("goblin", ROLLS, 20260914)
	var rate := float(r["equipment_rate"])
	# The table says 0.35. Four sigma on 2000 draws is about 0.043, so a band of
	# 0.05 is generous enough never to flicker and tight enough that a table
	# stating the wrong number fails.
	near("the goblin's equipment rate is what the table says", rate, 0.35, 0.05)

	# REPRODUCIBLE, which is the whole reason `simulate` takes a seed. Nothing
	# else asserts it: the determinism case above passes its own rng, so a
	# `simulate` that seeded itself would have gone unnoticed while its signature
	# went on promising a number it did not honour.
	eq("the same seed simulates the same run",
		CozyLootRoller.simulate("goblin", 200, 99),
		CozyLootRoller.simulate("goblin", 200, 99))
	ne("and a different seed does not",
		CozyLootRoller.simulate("goblin", 200, 99),
		CozyLootRoller.simulate("goblin", 200, 100))

	# The control that keeps the band honest: a rate of zero would also be
	# "inside" a badly written check, so the count is asserted too.
	is_true("and equipment really did drop", int((r["kinds"] as Dictionary)
		.get(CozyLootRoller.DROP_EQUIPMENT, 0)) > 0)

	# AND THE SLIME'S FIVE PER CENT — Willow's own example, and the first rate in
	# the game small enough that a table stating the wrong number would not be
	# noticed by playing. Measured, not read back off the row.
	var s := CozyLootRoller.simulate("slime", ROLLS, 20260915)
	near("the slime's gear rate is what the table says",
		float(s["equipment_rate"]), 0.05, 0.02)
	is_true("and it really did drop", int((s["kinds"] as Dictionary)
		.get(CozyLootRoller.DROP_EQUIPMENT, 0)) > 0)


func _weights_hold() -> void:
	# Over the drops that DID happen, a weapon is 40 of 100 by weight.
	var weapons := 0
	var gear := 0
	var rng := _rng(4242)
	for i in ROLLS:
		for d in (CozyLootRoller.roll("goblin", rng, 1)["drops"] as Array):
			var drop: Dictionary = d
			if String(drop["kind"]) != CozyLootRoller.DROP_EQUIPMENT:
				continue
			gear += 1
			if (drop["item"] as CozyItemInstance).item_type() == "weapon":
				weapons += 1
	is_true("equipment dropped at all", gear > 0)
	near("a weapon is 40% of the gear", float(weapons) / float(gear), 0.40, 0.07)


func _equipment_is_real() -> void:
	# Every piece of gear that fell, over a wide sweep of seeds, has to be a real
	# definition with a real rarity and its own id — not a name that happens to
	# look right.
	var seen := {}
	for s in range(1, 400):
		for d in (CozyLootRoller.roll("goblin", _rng(s), 1)["drops"] as Array):
			var drop: Dictionary = d
			if String(drop["kind"]) != CozyLootRoller.DROP_EQUIPMENT:
				continue
			var it: CozyItemInstance = drop["item"]
			is_true("a dropped item names a real definition", CozyItemDefs.exists(it.definition_id))
			is_true("with a real rarity", CozyItemDefs.is_rarity(it.rarity))
			is_true("a slot something can be worn in",
				CozyItemDefs.SLOTS.has(it.slot()))
			seen[it.definition_id] = true
	is_true("and more than one kind of thing dropped", seen.size() > 1)


func _refusals() -> void:
	is_true("a table that does not exist is refused",
		CozyLootRoller.reject_reason("dragon") != "")
	is_true("and the reason names it",
		CozyLootRoller.reject_reason("dragon").contains("dragon"))
	is_true("a PICK table is not a drop table",
		CozyLootRoller.reject_reason("goblin_gear") != "")
	is_true("and the reason says which it is",
		CozyLootRoller.reject_reason("goblin_gear").contains("drop"))
	eq("a real drop table is not", CozyLootRoller.reject_reason("goblin"), "")
	eq("and a refused table drops nothing",
		(CozyLootRoller.roll("dragon", _rng(1), 1)["drops"] as Array).size(), 0)


## Ids belong to whoever owns the list they are unique within, so the roller hands
## the counter back. Only the drops that NEED one spend it: three goblins that
## drop no equipment must not have burned three ids, or the world's item ids would
## depend on how lucky the player was.
##
## HONESTLY: THIS CANNOT FAIL TODAY, and mutation testing is what says so.
## Moving the counter advance outside the "was anything made" branch changed
## nothing, because every valid pick resolves to an item — a type with none is
## refused before it can be rolled. It is the guard for the day a table gets past
## that, and it is written down as unreachable rather than left looking like
## coverage.
func _ids_are_counted() -> void:
	var spent := 0
	var made := 0
	for s in range(1, 200):
		var r := CozyLootRoller.roll("goblin", _rng(s), 100)
		var gear := 0
		for d in (r["drops"] as Array):
			if String((d as Dictionary)["kind"]) == CozyLootRoller.DROP_EQUIPMENT:
				gear += 1
		spent += int(r["next_id"]) - 100
		made += gear
	eq("the counter advances by exactly the number of items made", spent, made)
	is_true("and some were made", made > 0)


# ---------------------------------------------------------------- helpers

func _rng(seed_value: int) -> RandomNumberGenerator:
	var r := RandomNumberGenerator.new()
	r.seed = seed_value
	return r


## The kinds of drop, sorted, as a string — a comparable fingerprint of one roll.
func _kinds(result: Dictionary) -> String:
	var out: Array[String] = []
	for d in (result["drops"] as Array):
		var drop: Dictionary = d
		out.append("%s:%s" % [drop["kind"], drop.get("id", "")])
	out.sort()
	return ",".join(out)


func _equipment_ids(result: Dictionary) -> String:
	var out: Array[String] = []
	for d in (result["drops"] as Array):
		var drop: Dictionary = d
		if String(drop["kind"]) == CozyLootRoller.DROP_EQUIPMENT:
			out.append((drop["item"] as CozyItemInstance).definition_id)
	return ",".join(out)


## The pick table an equipment entry names, or "".
func _pick_of(table_id: String) -> String:
	for e in CozyLootDefs.entries(table_id):
		var entry: Dictionary = e
		if String(entry.get("kind", "")) == CozyLootDefs.KIND_EQUIPMENT:
			return String(entry.get("pick", ""))
	return ""
