class_name CozyTimeSystem
extends Node
## The in-game clock (doc #114 / #115, 愿景 §2.2 seasons).
##
## Nothing in this project had a notion of time until now, which is why the
## schedule block could not be built before it.
##
## RATE, and why it is a constant rather than a magic number: the doc says a
## game day is "现实分钟级" — minutes of real time. The default here compresses
## that further so a single headless self-check can cross several schedule
## boundaries and actually observe the behaviour change. It is a tuning value,
## not a design decision, and it is named so it can be argued with.
##
## Seasons exist as a value but nothing consumes them yet — the doc's seasonal
## effects (tint, snow, leaf colour, planting windows) are M4 and belong to the
## renderer and the farming system, neither of which is here.

signal hour_changed(hour: int)
signal day_changed(day: int)

const REAL_SECONDS_PER_GAME_HOUR := 5.0

## A day starts at 06:00 rather than midnight: a resident's day, and the point
## from which their schedule is legible, begins when they wake.
const START_HOUR := 6.0

const HOURS_PER_DAY := 24
const DAYS_PER_SEASON := 10
const SEASONS: Array[String] = ["spring", "summer", "autumn", "winter"]

var day := 1
var hour := START_HOUR

var _last_hour := -1


func _process(delta: float) -> void:
	# One game hour per REAL_SECONDS_PER_GAME_HOUR seconds of real time.
	advance(delta / REAL_SECONDS_PER_GAME_HOUR)


## Advance the clock by `game_hours`. Public so a test can step time directly
## rather than waiting on frames.
func advance(game_hours: float) -> void:
	if game_hours <= 0.0:
		return
	hour += game_hours
	while hour >= float(HOURS_PER_DAY):
		hour -= float(HOURS_PER_DAY)
		day += 1
		day_changed.emit(day)
	var h := hour_index()
	if h != _last_hour:
		_last_hour = h
		hour_changed.emit(h)


func hour_index() -> int:
	return int(floor(hour))


## Hour and minute, as a clock reads them.
func hh_mm() -> String:
	var h := int(floor(hour))
	var m := int(floor((hour - float(h)) * 60.0))
	return "%02d:%02d" % [h, m]


func season() -> String:
	var idx := int(floor(float(day - 1) / float(DAYS_PER_SEASON))) % SEASONS.size()
	return SEASONS[idx]


## Is it dark? Used by traits that care (night_owl) and, later, by lighting.
func is_night() -> bool:
	return hour < 5.0 or hour >= 20.0


func describe() -> String:
	return "day %d %s  %s (%s)" % [day, hh_mm(), season(), "night" if is_night() else "day"]
