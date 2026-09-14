extends "res://tests/unit/unit_test.gd"
## Many sources of `+X`, `xY%` and `=Z`, resolved into one number.
##
## The case this suite is really about is the one in the header of
## `data/stats.gd`: a modifier belongs to a NAMED SOURCE, and setting one from a
## source that already has one replaces it. Everything else here protects that
## from being true by accident.
##
## Every pair carries a control, because "the sword's bonus went away" and "no
## bonus ever stacked" are the same green number.

const AD := CozyStats.Op.ADD
const MUL := CozyStats.Op.MULTIPLY
const OVR := CozyStats.Op.OVERRIDE


func _init() -> void:
	suite("stats")
	case("a flat modifier moves the base", _flat_adds)
	case("a source replaces its own modifier, and only its own", _source_keyed)
	case("taking equipment off leaves no residue", _removal_is_clean)
	case("the passes run add, multiply, override, clamp", _four_passes)
	case("an override discards the arithmetic it overrides", _override_wins)
	case("bounds hold whatever the modifiers say", _clamps)
	case("the two ways to combine percentages are different games", _multiply_modes)
	case("a source can be asked what it is giving", _from_source)
	case("the touched stats are sorted and unique", _touched)
	case("the default combine is the one the design document fixes", _v1_default)


func _flat_adds() -> void:
	var m: Array = []
	CozyStats.put(m, "boots", "armour", AD, 5)
	CozyStats.put(m, "ring", "armour", AD, 3)
	near("two sources of flat armour add up", CozyStats.resolve(m, "armour", 10.0), 18.0)
	near("and a stat nothing touches is its base", CozyStats.resolve(m, "speed", 10.0), 10.0)


## THE CASE THE WHOLE FILE EXISTS FOR. A second modifier from the same source
## replaces the first rather than piling on — which is what lets equipment be
## taken off by name instead of by remembering what it gave.
func _source_keyed() -> void:
	var m: Array = []
	CozyStats.put(m, "weapon", "damage", AD, 10)
	CozyStats.put(m, "weapon", "damage", AD, 25)
	near("the same source replaces its own number", CozyStats.resolve(m, "damage", 0.0), 25.0)
	eq("and there is still one modifier", m.size(), 1)

	# The control: a DIFFERENT source stacks. Without this, "25 not 35" would
	# pass on a `set` that simply refused the second call.
	CozyStats.put(m, "helmet", "damage", AD, 10)
	near("a different source does stack", CozyStats.resolve(m, "damage", 0.0), 35.0)
	eq("and that is two modifiers", m.size(), 2)

	# Upgrading one piece does not disturb the other.
	CozyStats.put(m, "weapon", "damage", AD, 40)
	near("upgrading the weapon keeps the helmet's flat", CozyStats.resolve(m, "damage", 0.0), 50.0)


func _removal_is_clean() -> void:
	var m: Array = []
	CozyStats.put(m, "weapon", "damage", AD, 10)
	CozyStats.put(m, "weapon", "speed", MUL, 0.2)
	CozyStats.put(m, "boots", "damage", AD, 4)
	near("worn, the weapon is worth both", CozyStats.resolve(m, "damage", 0.0), 14.0)

	eq("taking it off removes both of its modifiers", CozyStats.remove_source(m, "weapon"), 2)
	near("and its damage is gone", CozyStats.resolve(m, "damage", 0.0), 4.0)
	near("and its speed bonus with it", CozyStats.resolve(m, "speed", 10.0), 10.0)
	is_false("nothing of it is left", CozyStats.has_source(m, "weapon"))
	eq("removing it again removes nothing", CozyStats.remove_source(m, "weapon"), 0)
	eq("the boots are untouched", m.size(), 1)


## ADD, then MULTIPLY, then OVERRIDE, then CLAMP — and the order is the design,
## not an implementation detail.
func _four_passes() -> void:
	var m: Array = []
	CozyStats.put(m, "ring", "damage", AD, 50)      # (base + 50)
	CozyStats.put(m, "buff", "damage", MUL, 0.2)    # then x1.2
	near("flat first, then percentage", CozyStats.resolve(m, "damage", 100.0), 180.0)

	# The order is visible in the number: (100 + 50) x 1.2 is 180, and doing it
	# the other way round would be 170. Asserted rather than described.
	ne("and it is not the other order", int(CozyStats.resolve(m, "damage", 100.0)), 170)


func _override_wins() -> void:
	var m: Array = []
	CozyStats.put(m, "ring", "damage", AD, 500)
	CozyStats.put(m, "buff", "damage", MUL, 2.0)
	CozyStats.put(m, "hex", "damage", OVR, 7.0)
	near("an override discards everything else", CozyStats.resolve(m, "damage", 100.0), 7.0)

	# The control: without the override the same two modifiers do the arithmetic.
	CozyStats.remove_source(m, "hex")
	near("and without it they apply again", CozyStats.resolve(m, "damage", 100.0), 1800.0)


func _clamps() -> void:
	var bounds := {"min": 0.0, "max": 100.0}
	var m: Array = []
	CozyStats.put(m, "ring", "hp", AD, 500)
	near("a floor and a ceiling hold", CozyStats.resolve(m, "hp", 10.0,
		CozyStats.DEFAULT_MULTIPLY, bounds), 100.0)

	var low: Array = []
	CozyStats.put(low, "curse", "hp", AD, -500)
	near("and so does the floor", CozyStats.resolve(low, "hp", 10.0,
		CozyStats.DEFAULT_MULTIPLY, bounds), 0.0)

	# The control: with no bounds, the same modifier is not held.
	near("unbounded, the same modifier is not held",
		CozyStats.resolve(m, "hp", 10.0), 510.0)

	# And a clamp applies to an override as well — the last pass is last.
	var hex: Array = []
	CozyStats.put(hex, "hex", "hp", OVR, 9999.0)
	near("an override is clamped too", CozyStats.resolve(hex, "hp", 10.0,
		CozyStats.DEFAULT_MULTIPLY, bounds), 100.0)


## THE DECISION THE SURVEY COULD NOT MAKE FOR US. Two references, the same two
## modifiers, two different games — and the difference grows with every item.
func _multiply_modes() -> void:
	var m: Array = []
	CozyStats.put(m, "ring", "damage", MUL, 0.2)
	CozyStats.put(m, "buff", "damage", MUL, 0.1)

	near("separately they give 1.32", CozyStats.resolve(m, "damage", 100.0,
		CozyStats.Multiply.SEPARATE), 132.0, 0.001)
	near("summed they give 1.30", CozyStats.resolve(m, "damage", 100.0,
		CozyStats.Multiply.SUMMED), 130.0, 0.001)

	# Neither is a rounding error, which is why both are kept rather than one
	# being written down and the other remembered.
	is_true("and the gap is real", absf(132.0 - 130.0) > 1.0)

	# Commutative either way: the order modifiers happen to be in is not a fact
	# about the character.
	var reversed: Array = []
	CozyStats.put(reversed, "buff", "damage", MUL, 0.1)
	CozyStats.put(reversed, "ring", "damage", MUL, 0.2)
	near("and the order they were added does not matter",
		CozyStats.resolve(reversed, "damage", 100.0, CozyStats.Multiply.SEPARATE), 132.0)


func _from_source() -> void:
	var m: Array = []
	CozyStats.put(m, "weapon", "damage", AD, 12)
	CozyStats.put(m, "ring", "damage", AD, 5)
	near("a source reports its own number, not the total",
		CozyStats.from_source(m, "weapon", "damage"), 12.0)
	near("an unworn source reports nothing", CozyStats.from_source(m, "cloak", "damage"), 0.0)
	near("and a stat it does not touch reports nothing",
		CozyStats.from_source(m, "weapon", "speed"), 0.0)


func _touched() -> void:
	var m: Array = []
	CozyStats.put(m, "weapon", "speed", MUL, 0.1)
	CozyStats.put(m, "ring", "armour", AD, 3)
	CozyStats.put(m, "boots", "speed", AD, 2)
	eq("every stat something touches is listed once, in order",
		CozyStats.touched_stats(m), ["armour", "speed"] as Array[String])
	eq("and an empty character touches nothing",
		CozyStats.touched_stats([]).size(), 0)


## Willow's V1 rule, asserted as the DEFAULT rather than only as an option:
## `副本世界_装备词条掉落系统_V1.0.md` section 8 fixes `(Base + Flat) x (1 + Percent)`.
## A later version may switch it; until then the default must be the document.
func _v1_default() -> void:
	eq("the default is the one the design document fixes",
		CozyStats.DEFAULT_MULTIPLY, CozyStats.Multiply.SUMMED)

	var m: Array = []
	CozyStats.put(m, "ring", "damage", MUL, 0.2)
	CozyStats.put(m, "buff", "damage", MUL, 0.1)
	near("so the percentages are summed by default", CozyStats.resolve(m, "damage", 100.0), 130.0)

	# ... and the other one is still reachable, deliberately.
	near("and the multiplicative reading is still one argument away",
		CozyStats.resolve(m, "damage", 100.0, CozyStats.Multiply.SEPARATE), 132.0, 0.001)
