extends "res://tests/unit/unit_test.gd"
## The wind (ENV V1.0 V0.3), the pure half.
##
## The whole design is that the wind is DERIVED from the clock rather than stored:
## the wind at 14:30 on day 3 is the same wind every time that hour comes round,
## after any save, in any session, with nothing about it in the save file. That is
## a property of a pure function, so it is checked here rather than by running the
## game — and it is the property two recorded bugs in `docs/INVARIANTS.md` are
## about: a stored value can disagree with what it was derived from, and an
## accumulating one drifts a little further every frame it runs.
##
## No world, no frames. Every curve takes the hour as an argument.
##
## EVERY SYSTEM MADE HERE IS FREED, and that is not tidiness: `CozyWindSystem` is a
## Node, and an unreleased Node puts leak lines on stderr at exit — which turns
## `0 ERROR` into a lie for the whole baseline. The dropped-item suite learned that
## the hard way.


func _init() -> void:
	suite("wind")
	case("the same hour is always the same wind", _deterministic)
	case("the wind is not a constant", _it_moves)
	case("it never repeats within a day, or on any day", _no_short_period)
	case("the direction wanders but stays a wind", _direction)
	case("the gust is a strength, and the speed is never zero", _ranges)
	case("it says nothing when nothing changed", _quiet_when_still)


func _wind() -> CozyWindSystem:
	var w := CozyWindSystem.new()
	w.world_seed = 20260911
	return w


## THE PROPERTY THE WHOLE FILE IS FOR. Two calls, same hour, same answer — and a
## second system with the same seed agrees with the first, which is what lets a
## save that says nothing about the wind come back to the right weather.
func _deterministic() -> void:
	var a := _wind()
	var b := _wind()
	for h in [0.0, 6.5, 23.9, 100.25, 240.0]:
		eq("the gust at hour %s is the same twice" % str(h),
			a.gust_at(h), a.gust_at(h))
		eq("and a second system agrees at %s" % str(h), b.gust_at(h), a.gust_at(h))
		eq("the direction too", str(b.direction_at(h)), str(a.direction_at(h)))
		eq("and the speed", b.speed_at(h), a.speed_at(h))

	# ...and the SEED is what the pattern hangs off, or two worlds would share one
	# weather and `world_seed` would be a field with no consumer.
	var other := _wind()
	other.world_seed = 7
	ne("a different world has a different wind", other.gust_at(6.5), a.gust_at(6.5))
	a.free()
	b.free()
	other.free()


## A wind that never changes is not wind. This is the cheap half of "is it alive";
## the expensive half — that it changes at a rate a player notices — is the clock's
## business, not this file's.
func _it_moves() -> void:
	var w := _wind()
	var gusts := {}
	var dirs := {}
	var speeds := {}
	for i in 240:
		var h := float(i) * 0.25
		gusts[snappedf(w.gust_at(h), 0.001)] = true
		dirs[snappedf(w.direction_at(h).x, 0.0001)] = true
		speeds[snappedf(w.speed_at(h), 0.00001)] = true
	is_true("the gust takes many values over a day", gusts.size() > 50)
	is_true("so does the direction", dirs.size() > 20)
	is_true("and the speed", speeds.size() > 50)
	w.free()


## TWO SINES AT RATES THAT DO NOT DIVIDE INTO ONE ANOTHER, and this is what says
## so. A single sine — or two at rates that are multiples of each other — comes
## back round on a period a player will sit through, and then the weather is a fan
## going on and off on a schedule.
func _no_short_period() -> void:
	var w := _wind()
	var same_day := 0
	var same_week := 0
	for i in 200:
		var h := float(i) * 1.5
		if is_equal_approx(w.gust_at(h), w.gust_at(h + 24.0)):
			same_day += 1
		if is_equal_approx(w.gust_at(h), w.gust_at(h + 24.0 * 7.0)):
			same_week += 1
	eq("no hour repeats tomorrow at the same time of day", same_day, 0)
	eq("nor the same time next week", same_week, 0)
	w.free()


## A WIND HAS A DIRECTION, and "the direction" means about 22 degrees either side of
## the base — not a vector slowly spinning through every compass point, which is a
## different phenomenon with a different name.
func _direction() -> void:
	var w := _wind()
	var base: Vector2 = CozyWindSystem.BASE_DIRECTION
	var worst := 0.0
	var shortest := 2.0
	for i in 400:
		var d := w.direction_at(float(i) * 0.5)
		near("it stays a unit vector", d.length(), 1.0, 0.0001)
		worst = maxf(worst, rad_to_deg(d.angle_to(base)))
		shortest = minf(shortest, d.length())
	is_true("it never turns further than the drift allows (%.1f deg)" % worst,
		worst <= CozyWindSystem.DRIFT_DEG + 0.5)
	is_true("and it does use the range it has (%.1f deg)" % worst, worst > 10.0)
	is_true("and it is never a zero vector", shortest > 0.99)
	w.free()


func _ranges() -> void:
	var w := _wind()
	var lo := 2.0
	var hi := -1.0
	for i in 2000:
		var g := w.gust_at(float(i) * 0.05)
		lo = minf(lo, g)
		hi = maxf(hi, g)
	is_true("the gust is a strength in 0..1 (%.2f..%.2f)" % [lo, hi],
		lo >= 0.0 and hi <= 1.0)
	is_true("and it uses that range", lo < 0.1 and hi > 0.9)
	# A WIND THAT STOPS DEAD is a bug with a shape rather than a lull: the noise
	# field would freeze and start again. The speed swings but never reaches zero.
	var slowest := 99.0
	for i in 2000:
		slowest = minf(slowest, w.speed_at(float(i) * 0.05))
	is_true("the field never stops scrolling (min %.4f)" % slowest, slowest > 0.0)
	w.free()


## NOTHING MOVED, NOTHING SAID. A signal every quarter second carrying the same
## three numbers is a signal that trains its listeners to ignore it — and these
## listeners rewrite eight materials.
func _quiet_when_still() -> void:
	var w := _wind()
	var clock := CozyTimeSystem.new()
	w.clock = clock
	var heard: Array[int] = [0]
	w.wind_changed.connect(_count_into.bind(heard))
	w.publish()
	var first: int = heard[0]
	w.publish()
	w.publish()
	eq("it spoke once and then held its tongue", heard[0], first)
	clock.hour = w.game_hours() + 40.0
	w.publish()
	eq("and it speaks again when the clock has actually moved", heard[0], first + 1)
	w.free()
	clock.free()


## A BOUND METHOD RATHER THAN A LAMBDA — and the bound argument goes LAST, which is
## not where it reads as going: `Callable.bind` APPENDS to the signal's own
## arguments, so a receiver written `(heard, d, s, g)` is handed `(d, s, g, heard)`
## and the connection fails at every emission with a conversion error that the
## suite reports as "it never spoke". One word: the order is the API's, not mine.
func _count_into(_d: Vector2, _s: float, _g: float, heard: Array[int]) -> void:
	heard[0] += 1
