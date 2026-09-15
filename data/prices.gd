class_name CozyPrices
extends RefCounted
## What things cost, and what a shop pays for them.
##
## ---------------------------------------------------------------------------
## MONEY IS A MATERIAL, and that is not a shortcut.
##
## Doc #35 says the project has ONE store — "不要为建筑材料建立一套孤立库存系统"
## — and money is not an exception to that: copper is an id in the same
## vocabulary as wood, held in the same `CozyInventory`. It rides in the player's
## pack (`CozyPlayerState.pack`) beside everything else they are carrying, and it
## saves, stacks and displays through code that already exists.
##
## Willow, 2026-09-15: three tiers — copper, silver, gold — **copper only for
## now**. So `CURRENCY` below is one id and there is no exchange table, because a
## denomination system with nothing to denominate is two thirds of a mechanic
## with none of the consumers. Silver is a row here and a row in the material
## table, on the day something can be bought that copper cannot reach.
##
## ---------------------------------------------------------------------------
## THE ONE RULE THAT MUST NOT BE BROKEN.
##
##     buy > sell, for every row.
##
## A shop that pays more for a thing than it charges is not badly tuned, it is an
## INFINITE MONEY SOURCE: buy one, sell it, repeat. It needs no monster, no
## exploit and no timing — two menu clicks and the economy is over. So it is
## checked rather than watched, and the check is a unit test rather than an
## assertion in the world, because it is a fact about this table and nothing at
## runtime can make it false.

## The id money is. A material like any other, so a purse is a pack.
const CURRENCY := "copper"

## What a shop will sell an id for and pay for it, in `CURRENCY`.
##
## ONE PRICE PER ID rather than per shop. Two shops with different prices is a
## real thing to want and it is not this: the first shop that charges less than
## another pays for the arbitrage before it pays for anything else, and neither
## shop has been built yet.
const PRICES := {
	# Buy a seed, grow two wheat, sell the wheat: the loop Willow described on
	# 2026-09-15, and the reason seed has a price at all. The gap between seed
	# (4) and wheat (3) is deliberately narrow — the profit is meant to come from
	# the LAND and the time, not from the spread.
	"seed": {"buy": 4, "sell": 1},
	"wheat": {"buy": 9, "sell": 3},
	"bread": {"buy": 14, "sell": 6},
	# Materials the player gathers by hand. Selling wood is what makes chopping
	# worth doing before there is anything to build with it.
	"wood": {"buy": 3, "sell": 1},
	"stone": {"buy": 5, "sell": 2},
}

## What a stall offers, in the order a menu should show it.
##
## A LIST rather than "everything with a price", because those are different
## questions: a price says what a thing is WORTH, and this says what this shop
## deals in. Two shops with different shelves is the point of having shelves.
const SHELF: Array[String] = ["seed", "bread", "wood", "stone", "wheat"]


static func ids() -> Array[String]:
	var out: Array[String] = []
	for id in PRICES:
		out.append(String(id))
	out.sort()
	return out


static func has_price(id: String) -> bool:
	return PRICES.has(id)


static func row(id: String) -> Dictionary:
	return PRICES.get(id, {})


## What it costs to buy one. 0 for something no shop sells — and the callers read
## that as "not for sale" rather than as "free", which is why `has_price` exists
## and why nothing should treat 0 as a price.
static func buy(id: String) -> float:
	return float(row(id).get("buy", 0))


## What a shop pays for one. 0 for something nothing buys.
static func sell(id: String) -> float:
	return float(row(id).get("sell", 0))


static func is_sold(id: String) -> bool:
	return buy(id) > 0.0


static func is_bought(id: String) -> bool:
	return sell(id) > 0.0


## What a shop pays for `count` of an id.
static func sell_total(id: String, count: int) -> float:
	return sell(id) * float(maxi(0, count))


## What a difficulty of a purchase this is: can this purse afford `count`?
##
## Takes the PURSE rather than a number so the caller cannot ask a different
## container than the one it will spend from — the two-ledger mistake in its
## smallest form.
static func can_afford(purse: CozyInventory, id: String, count := 1) -> bool:
	if not has_price(id) or not is_sold(id) or purse == null:
		return false
	return purse.count(CURRENCY) >= buy(id) * float(count)


## Buy `count` of an id. All-or-nothing, the same way `CozyInventory.spend` is:
## a half-paid-for purchase is worse than a refused one.
##
## The CURRENCY itself is refused, which is not obvious and matters: without it a
## stall would happily sell you copper for copper at a profit, because nothing
## else in this file knows that money is a material.
static func buy_from(purse: CozyInventory, id: String, count := 1) -> bool:
	if count <= 0 or id == CURRENCY or not can_afford(purse, id, count):
		return false
	purse.spend({CURRENCY: buy(id) * float(count)})
	purse.add(id, float(count))
	return true


## Sell `count` of an id. Refused unless the seller actually has them, so a
## caller cannot mint money by selling what it does not own.
static func sell_to(purse: CozyInventory, id: String, count := 1) -> bool:
	if count <= 0 or id == CURRENCY or not is_bought(id) or purse == null:
		return false
	if purse.count(id) < float(count):
		return false
	purse.spend({id: float(count)})
	purse.add(CURRENCY, sell_total(id, count))
	return true


## Every row, as a line of text. For a check that has to print what it examined
## rather than how many rows it looked at.
static func describe() -> String:
	var parts: Array[String] = []
	for id in ids():
		parts.append("%s %d/%d" % [id, int(buy(id)), int(sell(id))])
	return ", ".join(parts)
