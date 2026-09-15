class_name CozyWindSystem
extends Node
## The wind, as one data source that everything that moves in it reads.
##
## ENV V1.0 §6, phase V0.3: "一个数据源 + 注入，风格与 clock 一致". It owns
## `wind_direction`, `wind_speed` and `wind_gust`, and it is a NODE for the same
## reason `CozyTimeSystem` is: something has to pull on a frame, and the thing it
## pulls on is a clock.
##
## ---------------------------------------------------------------------------
## DERIVED FROM THE CLOCK, NOT STORED, AND THAT IS THE WHOLE DESIGN
##
## `wind_at(hours)` is a pure function. The wind at 14:30 on day 3 is the same wind
## every time that hour comes round, in every session, and after any save — with
## nothing in the save file about it. `docs/INVARIANTS.md` has the two bugs this
## shape prevents: a value that is stored can disagree with the thing it was derived
## from, and a value that accumulates drifts a little further every frame it runs.
##
## It also means a TEST can ask what the wind will be at any hour without running
## the game, which is not true of anything that advances itself with `randf()`.
##
## ---------------------------------------------------------------------------
## WHAT IT DOES NOT DO: it does not bend anything.
##
## The plants are bent by `shaders/vegetation.gdshader`, and how much each KIND of
## plant bends is `CozyVegetationScatter.WIND_STRENGTH` — a fact about a plant, and
## the scatter's business. This file answers "how windy is it", and nothing else.
## The scatter listens and re-tells its materials; see `CozyVegetationScatter.
## apply_wind`. One question, one owner.

## Told whenever the wind has moved. Carries the three numbers so a listener does
## not have to ask back — and so the signal is the record of what was published.
signal wind_changed(direction: Vector2, speed: float, gust: float)

## INJECTED, like `navigator` and `clock` on the agents: nothing here reaches for
## the world, which is what keeps this runnable in a test with no world at all.
var clock: CozyTimeSystem = null

## Where the wind blows from when nothing is drifting it, in world XZ. The
## shader's own default, kept as the base so a world with no wind system in it
## looks the way it did before there was one.
const BASE_DIRECTION := Vector2(0.0, 1.0)

## How far the direction wanders either side of the base, in degrees, and how
## slowly. A wind that never turns reads as a fan.
const DRIFT_DEG := 22.0
const DRIFT_RATE := 0.07

## Metres of noise the field scrolls per second, at gust 0.5 — the shader's own
## `wind_speed` default. Read by everything that scrolls: the plants today, the
## clouds and the rain when they arrive.
const SPEED_BASE := 0.025
const SPEED_SWING := 0.6

## How often the wind is re-published, in real seconds. THE VALUE IS A FUNCTION OF
## GAME HOURS, so this is not part of the answer — it is how often the answer is
## handed out. A frame is far more often than a gust changes, and eight materials
## rewritten sixty times a second for a number that moves on the scale of minutes.
const PUBLISH_INTERVAL := 0.25

## Seeded per world, so two saves of different worlds do not share a weather
## pattern — and the same world always has the same one.
var world_seed := 20260911

# The published state. Read by anything that wants the wind without listening.
var direction := BASE_DIRECTION
var speed := SPEED_BASE
var gust := 0.5

var _since_publish := 0.0


func _process(delta: float) -> void:
	_since_publish += delta
	if _since_publish < PUBLISH_INTERVAL:
		return
	_since_publish = 0.0
	publish()


## Work out the wind from the clock and tell everyone.
##
## Public and separate from `_process` so a check can publish on demand instead of
## waiting for real seconds to pass — the same reason `CozyTimeSystem.advance` is.
func publish() -> void:
	var hours := game_hours()
	var d := direction_at(hours)
	var s := speed_at(hours)
	var g := gust_at(hours)
	# NOTHING MOVED, NOTHING SAID. A signal every quarter second that carries the
	# same three numbers is a signal that trains its listeners to ignore it.
	if d.is_equal_approx(direction) and is_equal_approx(s, speed) \
			and is_equal_approx(g, gust):
		return
	direction = d
	speed = s
	gust = g
	wind_changed.emit(direction, speed, gust)


## The clock as one number, so every curve below is a function of ONE thing: total
## game hours. `day * 24 + hour` rather than the hour alone, or the wind would
## repeat every morning.
func game_hours() -> float:
	if clock == null:
		return 0.0
	return float(clock.day - 1) * float(CozyTimeSystem.HOURS_PER_DAY) + clock.hour


# ---------------------------------------------------------------- the curves
#
# PURE, and each takes the hour rather than reading the clock — so a test can ask
# what the wind does over a week without advancing anything.


## Which way it blows, wandering either side of the base.
func direction_at(hours: float) -> Vector2:
	var deg := DRIFT_DEG * sin(hours * DRIFT_RATE + float(world_seed % 89))
	var a := deg_to_rad(deg)
	return Vector2(BASE_DIRECTION.x * cos(a) - BASE_DIRECTION.y * sin(a),
		BASE_DIRECTION.x * sin(a) + BASE_DIRECTION.y * cos(a)).normalized()


## How fast the field scrolls. Never zero and never negative: a wind that stops
## dead and starts again is a bug with a shape, not a lull.
func speed_at(hours: float) -> float:
	return SPEED_BASE * (1.0 + SPEED_SWING * sin(hours * 0.19 + float(world_seed % 61)))


## How strong it is, 0..1. THIS IS THE GUST THE WHOLE SYSTEM TURNS ON.
##
## TWO SINES AT RATES THAT DO NOT DIVIDE INTO ONE ANOTHER. One sine is a fan going
## on and off on a schedule; two at incommensurate rates never come back round in
## any time a player will sit through, for the cost of one more `sin`.
func gust_at(hours: float) -> float:
	var a := sin(hours * 0.37 + float(world_seed % 97))
	var b := sin(hours * 0.11 + float(world_seed % 53))
	return clampf((a * 0.6 + b * 0.4) * 0.5 + 0.5, 0.0, 1.0)


## The wind right now, as the three numbers, for a caller that wants them without
## listening — a check, or a system that arrives later than the last publish.
func state() -> Dictionary:
	return {"direction": direction, "speed": speed, "gust": gust}


func describe() -> String:
	return "wind %.2f from (%.2f, %.2f) at %.4f" % [
		gust, direction.x, direction.y, speed]
