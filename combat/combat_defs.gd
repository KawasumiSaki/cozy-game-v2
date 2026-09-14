class_name CozyCombatDefs
extends RefCounted
## What an attack IS, in frames — and what a raised guard does (2026-09-14).
##
## FRAME DATA, NOT ANIMATION. An attack is expressed as three spans of ticks and
## a damage number; the animation is a VIEW of this, never the authority. The
## research is blunt about why: `AnimationPlayer` advances on the render frame
## while hit detection runs in `_physics_process`, so "the hitbox opens on frame
## 6" would depend on frame pacing — and a method track has no way at all to
## answer "which frame does `attack_02` activate on?" without a `.tscn`, which
## puts the answer out of reach of every assertion this project owns.
##
## A TICK IS A PHYSICS FRAME. Not seconds, not milliseconds: an integer, so a
## fight replays identically and a test can advance five ticks and say what it
## expects to find.
##
## ---------------------------------------------------------------------------
## WHAT IS NOT HERE, AND WHY. No reach, no hitbox shape, no hitstop multiplier,
## no knockback distance. Those belong to the world, and the solver deliberately
## cannot see the world — the shape of the swing is the Node's business and this
## table would only be guessing at it. They arrive on the day something reads
## them, which is the rule this project has paid for seven times.

## The three spans one swing is made of, and then it is over.
const WINDUP := "windup"
const ACTIVE := "active"
const RECOVERY := "recovery"
const IDLE := "idle"

## Attacks, by id. `combo_next` is what a second press inside `combo_window`
## leads to; empty means the chain ends here.
##
## The chain is what makes a light attack worth pressing twice, and the window is
## generous on purpose: a fight where the combo drops unless you press on the
## exact frame is a fight about input latency, not about the game.
const ATTACKS := {
	"light_1": {
		"name": "Light 1",
		"windup": 6, "active": 6, "recovery": 10,
		"damage": 8, "hitstop": 4,
		"combo_next": "light_2", "combo_window": 12,
	},
	"light_2": {
		"name": "Light 2",
		"windup": 5, "active": 6, "recovery": 10,
		"damage": 9, "hitstop": 4,
		"combo_next": "light_3", "combo_window": 12,
	},
	"light_3": {
		"name": "Light 3",
		"windup": 8, "active": 8, "recovery": 18,
		"damage": 14, "hitstop": 6,
		"combo_next": "", "combo_window": 0,
	},
	"heavy_1": {
		"name": "Heavy 1",
		"windup": 14, "active": 8, "recovery": 22,
		"damage": 22, "hitstop": 8,
		"combo_next": "heavy_2", "combo_window": 14,
	},
	"heavy_2": {
		"name": "Heavy 2",
		"windup": 16, "active": 10, "recovery": 26,
		"damage": 30, "hitstop": 10,
		"combo_next": "", "combo_window": 0,
	},
	# What the right button does when there is no shield in hand. Willow's rule:
	# right is guard WITH a shield and this WITHOUT one — so it is a row here
	# rather than a branch somewhere in the input code.
	"shove": {
		"name": "Shove",
		"windup": 5, "active": 4, "recovery": 14,
		"damage": 5, "hitstop": 3,
		"combo_next": "", "combo_window": 0,
	},
}

## What a raised guard does.
const GUARD := {
	## Taken off an incoming hit. 0.6 means a blocked hit deals 40% of its damage.
	"reduction": 0.6,
	## Guard held for no longer than this is a PARRY: nothing gets through. The
	## window is why guarding is a decision rather than a held button.
	"parry_window": 6,
	## Ticks of recovery forced by a blocked hit. Longer than most attacks'
	## recovery, so blocking something big is safe but not free.
	"stagger": 18,
}

## A swing that lands hurts the attacker for this many ticks. It suppresses the
## LOCAL clock rather than the engine's: `Engine.time_scale` changes the physics
## delta and makes results "vary wildly" (godot#24334), which would cost the
## determinism the whole design is built on.
const DEFAULT_HITSTOP := 0


static func exists(id: String) -> bool:
	return ATTACKS.has(id)


static func attack(id: String) -> Dictionary:
	return ATTACKS.get(id, {})


static func display_name(id: String) -> String:
	return String(attack(id).get("name", id))


## The span this swing is ACTIVE for, as [first_tick, last_tick_exclusive).
##
## Half-open on purpose: `active_window(a).y - active_window(a).x` is the number
## of ticks a hitbox is open, and an off-by-one there is a hit that lands on the
## frame the animation says it should not.
static func active_window(id: String) -> Vector2i:
	var d := attack(id)
	if d.is_empty():
		return Vector2i.ZERO
	var start := int(d["windup"])
	return Vector2i(start, start + int(d["active"]))


## How long one swing takes, windup through recovery. The combo window starts
## when this many ticks have passed.
static func total_ticks(id: String) -> int:
	var d := attack(id)
	if d.is_empty():
		return 0
	return int(d["windup"]) + int(d["active"]) + int(d["recovery"])


## Which span a swing is in at `frame`, counting from the first tick of windup.
static func phase_at(id: String, frame: int) -> String:
	var d := attack(id)
	if d.is_empty():
		return IDLE
	if frame < int(d["windup"]):
		return WINDUP
	if frame < int(d["windup"]) + int(d["active"]):
		return ACTIVE
	if frame < total_ticks(id):
		return RECOVERY
	return IDLE


## The id a chain of this kind starts with. `"light"` -> `"light_1"`.
##
## Derived from the table rather than written down twice, so renaming a chain's
## first swing is a row change and not a second place to remember.
static func first_of(kind: String) -> String:
	var want := kind + "_1"
	return want if ATTACKS.has(want) else ""


## Every id, sorted, so a test can walk the table without hardcoding it.
static func ids() -> Array[String]:
	var out: Array[String] = []
	for k in ATTACKS:
		out.append(String(k))
	out.sort()
	return out


## A chain is only a chain if every link resolves. The self-check asserts this,
## because a `combo_next` naming an attack that does not exist is a combo that
## silently stops after the first swing — and it would look like a design choice.
static func broken_links() -> Array[String]:
	var out: Array[String] = []
	for id in ATTACKS:
		var nxt := String(ATTACKS[id].get("combo_next", ""))
		if nxt != "" and not ATTACKS.has(nxt):
			out.append("%s -> %s" % [id, nxt])
		if nxt == "" and int(ATTACKS[id].get("combo_window", 0)) != 0:
			out.append("%s has a combo window but nowhere to go" % id)
	return out
