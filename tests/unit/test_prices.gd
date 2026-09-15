extends "res://tests/unit/unit_test.gd"
## The price table, and the one rule that must never be broken.
##
##     buy > sell, for every row.
##
## A shop that pays more for a thing than it charges is not badly tuned, it is an
## INFINITE MONEY SOURCE: buy one, sell it, repeat. It needs no monster, no
## exploit and no timing — two menu clicks and the economy is over. So it is
## checked here rather than watched, because it is a fact about this table and
## nothing at runtime can make it false.
##
## The rest of the suite is the same question in smaller pieces: money must not
## be tradable for money, and a trade must not half-happen.

func _init() -> void:
	suite("prices")
	case("every row is priced so the shop cannot be farmed", _buy_beats_sell)
	case("every priced thing exists", _ids_are_real)
	case("the shelf only names things with prices", _shelf_is_priced)
	case("money is a material like any other", _currency_is_real)
	case("money is not for sale", _currency_is_not_tradable)
	case("a purchase is refused whole when it cannot be afforded", _cannot_overspend)
	case("you cannot sell what you do not have", _cannot_sell_nothing)
	case("a purchase and a sale move the purse by the price", _moves_by_the_price)


## THE RULE. Stated once, checked over the whole table, so a new row cannot join
## without answering it.
func _buy_beats_sell() -> void:
	is_true("the table is not empty", CozyPrices.ids().size() > 0)
	for id in CozyPrices.ids():
		var b := CozyPrices.buy(id)
		var s := CozyPrices.sell(id)
		is_true("'%s' costs more than it returns (%d > %d)" % [id, int(b), int(s)],
			b > s)
		# And both halves are real numbers: a row with only a buy price is a
		# thing the shop will not take back, which is a decision rather than a
		# mistake — but a row with a NEGATIVE price is a shop that pays you to
		# take its goods.
		is_true("'%s' does not have a negative price" % id, b >= 0.0 and s >= 0.0)


## A price is a claim about a thing, and a claim about a thing that does not
## exist is a row nothing can ever match.
func _ids_are_real() -> void:
	for id in CozyPrices.ids():
		is_true("'%s' is a material" % id, CozyMaterials.MATERIALS.has(id))
		is_true("'%s' has a name to show" % id,
			CozyMaterials.display_name(id) != "")


func _shelf_is_priced() -> void:
	is_true("the shelf is not empty", CozyPrices.SHELF.size() > 0)
	for id in CozyPrices.SHELF:
		is_true("'%s' is on the shelf and has a price" % id,
			CozyPrices.has_price(String(id)))


func _currency_is_real() -> void:
	is_true("the currency is a material",
		CozyMaterials.MATERIALS.has(CozyPrices.CURRENCY))
	# The currency's own row would be a shop selling money for money, and the
	# exchange rate in it would be the whole economy.
	is_false("and it is not itself priced",
		CozyPrices.has_price(CozyPrices.CURRENCY))


## THE SMALLEST MONEY LOOP THERE IS: hand the shop copper, get copper back.
## Nothing else in this file knows that money is a material, so without the guard
## in `buy_from`/`sell_to` a stall would do this happily and at a profit.
func _currency_is_not_tradable() -> void:
	var purse := CozyInventory.new()
	purse.add(CozyPrices.CURRENCY, 50.0)
	is_false("the shop will not sell you money",
		CozyPrices.buy_from(purse, CozyPrices.CURRENCY, 1))
	is_false("and will not buy money from you",
		CozyPrices.sell_to(purse, CozyPrices.CURRENCY, 1))
	eq("the purse did not move", purse.count(CozyPrices.CURRENCY), 50.0)


func _cannot_overspend() -> void:
	var purse := CozyInventory.new()
	var price := CozyPrices.buy("bread")
	purse.add(CozyPrices.CURRENCY, price - 1.0)
	is_false("one copper short is short",
		CozyPrices.buy_from(purse, "bread", 1))
	is_false("and the bread did not arrive", purse.count("bread") > 0.0)
	# All-or-nothing: the copper is still there, not half spent.
	eq("nothing was paid", purse.count(CozyPrices.CURRENCY), price - 1.0)

	purse.add(CozyPrices.CURRENCY, 1.0)
	is_true("with exactly enough it goes through",
		CozyPrices.buy_from(purse, "bread", 1))
	eq("the bread arrived", purse.count("bread"), 1.0)
	eq("and the purse is empty", purse.count(CozyPrices.CURRENCY), 0.0)


func _cannot_sell_nothing() -> void:
	var purse := CozyInventory.new()
	purse.add(CozyPrices.CURRENCY, 0.0)
	is_false("selling what you do not have is refused",
		CozyPrices.sell_to(purse, "wheat", 1))
	eq("and no copper appeared", purse.count(CozyPrices.CURRENCY), 0.0)
	purse.add("wheat", 1.0)
	is_false("selling two of the one you have is refused",
		CozyPrices.sell_to(purse, "wheat", 2))
	is_true("selling the one you have goes through",
		CozyPrices.sell_to(purse, "wheat", 1))
	eq("and was paid for", purse.count(CozyPrices.CURRENCY),
		CozyPrices.sell("wheat"))


func _moves_by_the_price() -> void:
	var purse := CozyInventory.new()
	purse.add(CozyPrices.CURRENCY, 100.0)
	CozyPrices.buy_from(purse, "seed", 1)
	eq("a purchase costs the buy price",
		purse.count(CozyPrices.CURRENCY), 100.0 - CozyPrices.buy("seed"))
	eq("and delivers one", purse.count("seed"), 1.0)
	# Several at once, because the total is what has to be right, not the single.
	CozyPrices.sell_to(purse, "seed", 1)
	eq("a sale pays the sell price",
		purse.count(CozyPrices.CURRENCY),
		100.0 - CozyPrices.buy("seed") + CozyPrices.sell("seed"))
	eq("and takes the goods away", purse.count("seed"), 0.0)
