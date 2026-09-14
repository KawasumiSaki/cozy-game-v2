class_name CozyStats
extends RefCounted
## Many sources of `+X`, `xY%` and `=Z`, resolved into one number.
##
## This is the piece of an equipment system that is actually hard, and the survey
## of what exists found nobody giving it away: a dozen Godot inventory addons, and
## the best of them stores `stat_modifiers = {"speed": 10}` — a flat dictionary
## with no order, no additive-versus-multiplicative distinction and no way to take
## a modifier back off. That last one is the bug the whole design here is shaped
## around.
##
## ---------------------------------------------------------------------------
## SOURCE-KEYED, WHICH IS THE WHOLE IDEA. A modifier is not a number that gets
## added to a running total; it is a number belonging to a NAMED SOURCE — a piece
## of equipment, a buff, a trait. Adding one from a source that already has one
## for the same stat and operation REPLACES it.
##
##     set(mods, "weapon", "damage", ADD, 10)
##     set(mods, "weapon", "damage", ADD, 25)   # replaces; still 25, not 35
##
## Without that, "take the sword off" has to know how much the sword gave, and
## the answer has to be found somewhere — which is how a character ends up with
## the stats of equipment they are no longer wearing. Removing a source is then
## one call and cannot leave a residue behind.
##
## ---------------------------------------------------------------------------
## THE FOUR PASSES. Every statistic resolves the same way, in this order:
##
##     1. ADD      — sum every flat modifier, add to the base
##     2. MULTIPLY — apply the percentages
##     3. OVERRIDE — if anything says "= Z", it wins and the arithmetic above is
##                   discarded
##     4. CLAMP    — hold the result inside the stat's own bounds
##
## Override being late is the point: it is how a "set your speed to exactly this"
## effect works regardless of what else is on the character.

enum Op { ADD, MULTIPLY, OVERRIDE }

const OP_NAMES := {
	Op.ADD: "add",
	Op.MULTIPLY: "multiply",
	Op.OVERRIDE: "override",
}

## How two MULTIPLY modifiers on the same stat combine. THE TWO ANSWERS ARE
## DIFFERENT GAMES, and the survey found the two best references disagreeing:
##
##   SEPARATE  each multiplies on its own        +20% and +10% -> x1.32
##   SUMMED    the percentages are added first   +20% and +10% -> x1.30
##
## SUMMED IS THE DEFAULT, and that is Willow's call rather than a preference:
## `副本世界_装备词条掉落系统_V1.0.md` section 8 fixes V1 at
##
##     Final = (Base + Flat) x (1 + Percent)
##
## with "More Damage / Less Damage / Multiplicative" explicitly deferred to a
## later version that adds new operations. So V1 sums the percentages and applies
## them once.
##
## SEPARATE is implemented anyway, and asserted, because the difference is not a
## rounding error — ten percent-modifiers apart is nearly a factor of two — and a
## design document that says "V1 does not need it" is a document that expects to
## need it. Flipping this constant is the entire change.
enum Multiply { SEPARATE, SUMMED }

const DEFAULT_MULTIPLY := Multiply.SUMMED


## One modifier: who gave it, what it touches, how it combines, how much.
static func make(source: String, stat: String, op: int, value: float) -> Dictionary:
	return {"source": source, "stat": stat, "op": op, "value": value}


## Put a modifier on, replacing whatever that source already said about that
## stat and operation.
##
## THE REPLACEMENT IS THE FEATURE, not a tidiness. See the header: it is what
## makes taking a sword off a subtraction that cannot go wrong.
static func put(mods: Array, source: String, stat: String, op: int, value: float) -> void:
	for i in mods.size():
		var m: Dictionary = mods[i]
		if m["source"] == source and m["stat"] == stat and int(m["op"]) == op:
			m["value"] = value
			return
	mods.append(make(source, stat, op, value))


## Take everything a source said off the character. One call, no residue.
static func remove_source(mods: Array, source: String) -> int:
	var removed := 0
	for i in range(mods.size() - 1, -1, -1):
		if (mods[i] as Dictionary)["source"] == source:
			mods.remove_at(i)
			removed += 1
	return removed


## What this source is currently contributing to this stat, ADD modifiers only.
## A caller asking "what did the sword give me" gets the sword's own answer rather
## than a total other things are also in.
static func from_source(mods: Array, source: String, stat: String) -> float:
	var total := 0.0
	for m in mods:
		var d: Dictionary = m
		if d["source"] == source and d["stat"] == stat and int(d["op"]) == Op.ADD:
			total += float(d["value"])
	return total


static func has_source(mods: Array, source: String) -> bool:
	for m in mods:
		if (m as Dictionary)["source"] == source:
			return true
	return false


## Every stat any modifier touches, sorted. Sorted so a display is stable and a
## test can walk the set without the order of an Array deciding the answer.
static func touched_stats(mods: Array) -> Array[String]:
	var out: Array[String] = []
	for m in mods:
		var s := String((m as Dictionary)["stat"])
		if not out.has(s):
			out.append(s)
	out.sort()
	return out


# ---------------------------------------------------------------- the four passes

## Resolve one statistic. `base` is the character's own number before anything is
## worn, `bounds` is the stat's own limits (or anything with `min`/`max`).
##
## Pure: the same modifiers and the same base always give the same answer, and
## nothing here reads the world or the clock.
static func resolve(mods: Array, stat: String, base: float,
		mode: int = DEFAULT_MULTIPLY, bounds: Dictionary = {}) -> float:
	var flat := 0.0
	var percents: Array = []
	var overridden := false
	var override_value := 0.0

	for m in mods:
		var d: Dictionary = m
		if d["stat"] != stat:
			continue
		match int(d["op"]):
			Op.ADD:
				flat += float(d["value"])
			Op.MULTIPLY:
				percents.append(float(d["value"]))
			Op.OVERRIDE:
				overridden = true
				override_value = float(d["value"])

	# An override discards the arithmetic rather than joining it — that is what
	# makes "set this stat to exactly Y" work regardless of what else is worn.
	if overridden:
		return _clamp(override_value, bounds)

	var total := base + flat
	if mode == Multiply.SEPARATE:
		# Applied one after another. Multiplication commutes, so the order the
		# modifiers happen to be in cannot change the answer and none is sorted.
		for p in percents:
			total *= 1.0 + p
	else:
		var summed := 0.0
		for p in percents:
			summed += p
		total *= 1.0 + summed
	return _clamp(total, bounds)


static func _clamp(v: float, bounds: Dictionary) -> float:
	if bounds.is_empty():
		return v
	return clampf(v, float(bounds.get("min", -INF)), float(bounds.get("max", INF)))


static func op_name(op: int) -> String:
	return String(OP_NAMES.get(op, "?"))
