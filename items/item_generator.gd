class_name CozyItemGenerator
extends RefCounted
## Rolls an item: rarity, then which affixes, then what each one is worth.
##
## Section 20 of the design document gives the flow, and none of it is allowed to
## know what a monster is, what a player is, or where any of it goes. Given a
## definition, a rarity and a source of randomness it hands back an instance —
## which is why this can be asserted without a world, and why a loot table can
## call it without a monster existing.
##
## ---------------------------------------------------------------------------
## THE CALLER OWNS THE SEED, AND THERE IS NO OTHER SOURCE OF RANDOMNESS.
##
## `docs/INVARIANTS.md`: everything procedural is deterministic, "never `randf()`",
## and a seed has to come from somewhere the world can save. A generator that
## reached for the global RNG would be untestable — the same sword could not be
## rolled twice — and a loot drop could not be replayed from a save. So the
## `RandomNumberGenerator` is a parameter, and a test sets its seed and asserts
## the exact item that comes out.
##
## A consequence worth stating: two drops rolled from the same seed are the same
## item. That is not a limitation to work around, it is the property that lets a
## bug report say which seed produced it.


## The precision a rolled value is kept to. See `quantise`: a value that cannot
## survive `JSON.stringify` is a value that changes when the game is reloaded.
const ROLL_DECIMALS := 3


## A rolled value, kept to `ROLL_DECIMALS` — AND KEPT BY GOING THROUGH TEXT.
##
## `snappedf` is NOT enough, and the round-trip assertion is what proved it.
## `round(v * 1000) / 1000` lands on a double that is not the nearest one to the
## three-decimal number it meant, so `JSON.stringify` wrote "4.915" and reading
## it back produced a different double. The failure message printed both
## dictionaries and they looked identical — `str()` shortens floats for display,
## so two different numbers read the same. That is worth knowing on its own: any
## test that reports a mismatch by printing a float is reporting less than it
## appears to.
##
## Printing to three decimals and parsing the result gives the SAME double that
## reading the file will give, which is the only form that can round-trip. The
## quantization and the serializer have to be the same operation, not two
## operations that agree most of the time.
static func quantise(v: float) -> float:
	return float(("%." + str(ROLL_DECIMALS) + "f") % v)


## Why this pair cannot be rolled, or "" when it can.
##
## A REASON rather than a null, the shape `CozyOutlineGenerator.reject_reason` and
## `CozyDungeonBlueprint.reject_reason` settled on: a caller that refuses has to
## be able to say why, and a test can assert on the words.
static func reject_reason(definition_id: String, rarity_id: String) -> String:
	if not CozyItemDefs.exists(definition_id):
		return "no item definition '%s'" % definition_id
	if not CozyItemDefs.is_rarity(rarity_id):
		return "'%s' is not a rarity" % rarity_id
	# A rarity that wants more affixes than the pool holds is not an error — the
	# roll stops at the pool — but a rarity that wants FEWER than zero would be,
	# and the table is data.
	if CozyItemDefs.affix_count(rarity_id) < 0:
		return "rarity '%s' asks for a negative number of affixes" % rarity_id
	return ""


## Roll one item, or null when `reject_reason` refuses the pair.
##
## `instance_id` is minted by the caller: ids belong to whoever owns the list
## they are unique within, which is the rule the entity registry already follows.
static func generate(definition_id: String, rarity_id: String, level: int,
		rng: RandomNumberGenerator, instance_id := "") -> CozyItemInstance:
	if reject_reason(definition_id, rarity_id) != "":
		return null
	var it := CozyItemInstance.make(instance_id, definition_id, rarity_id, maxi(1, level))
	it.affixes = roll_affixes(CozyItemDefs.type_of(definition_id), rarity_id, rng)
	return it


## Which rarity drops, from the weights in `CozyItemDefs.RARITY`.
##
## Walked in `RARITY_ORDER` rather than in dictionary order, because a dictionary
## does not promise an order and a roll that depends on one is a roll that
## changes when the table is edited.
static func roll_rarity(rng: RandomNumberGenerator) -> String:
	var total := 0.0
	for id in CozyItemDefs.RARITY_ORDER:
		total += float(CozyItemDefs.rarity(id).get("weight", 0.0))
	if total <= 0.0:
		return "common"
	var roll := rng.randf() * total
	return _walk(CozyItemDefs.RARITY_ORDER, roll, "common",
		func(id: String) -> float: return float(CozyItemDefs.rarity(id).get("weight", 0.0)))


## The affixes this item rolls, in the order they were rolled.
##
## WITHOUT REPLACEMENT, which is section 19: two `+5 Attack` lines on one sword
## is a bug the player cannot distinguish from a feature. The pool is a local
## copy, so an affix that is taken is gone for the rest of this item and is back
## for the next one.
##
## A pool that runs out first is not an error — a legendary ring simply has fewer
## affixes that fit it than four — so the loop stops rather than refusing.
static func roll_affixes(item_type: String, rarity_id: String,
		rng: RandomNumberGenerator) -> Array:
	var out: Array = []
	var want := CozyItemDefs.affix_count(rarity_id)
	if want <= 0:
		return out
	var pool := CozyAffixDefs.pool_for(item_type)
	for i in want:
		var id := _pick_weighted(pool, rng)
		if id == "":
			break
		pool.erase(id)
		var def := CozyAffixDefs.get_def(id)
		out.append({"id": id, "value": quantise(
			rng.randf_range(float(def["min"]), float(def["max"])))})
	return out


## Pick one id from the pool, more likely the larger its weight (section 21).
##
## The roll is a single `randf()` scaled by the total, not a per-entry dice: one
## draw means the outcome is fixed by one number from the seed, so a test can
## predict it and a save can replay it.
static func _pick_weighted(pool: Array[String], rng: RandomNumberGenerator) -> String:
	if pool.is_empty():
		return ""
	var total := 0.0
	for id in pool:
		total += float(CozyAffixDefs.get_def(id).get("weight", 0.0))
	if total <= 0.0:
		return ""
	return _walk(pool, rng.randf() * total, "",
		func(id: String) -> float: return float(CozyAffixDefs.get_def(id).get("weight", 0.0)))


## The shared walk: take ids in order, accumulating weight, until the roll is
## covered. One implementation, so the rarity roll and the affix roll cannot
## disagree about what a weighted draw means.
static func _walk(ids: Array, roll: float, fallback: String, weight_of: Callable) -> String:
	var acc := 0.0
	for id in ids:
		acc += float(weight_of.call(String(id)))
		if roll <= acc:
			return String(id)
	# Only reachable by floating-point error at the very top of the range, and
	# falling back to the LAST id rather than the first keeps it biased towards
	# the rarest thing rather than the commonest.
	return String(ids[ids.size() - 1]) if not ids.is_empty() else fallback
