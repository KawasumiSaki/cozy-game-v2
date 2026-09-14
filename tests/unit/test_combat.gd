extends "res://tests/unit/unit_test.gd"
## A fight, as arithmetic — no world, no physics, no frames rendered.
##
## Every case here advances an integer clock over `const` tables and says what it
## expects to find. That is only possible because the solver never asks the scene
## tree anything: the single question that needs the world ("is anything in
## front of me?") is a call the DRIVER makes, and the driver is not in this file.
##
## The pairs that matter most are the ones that cannot both pass on a solver that
## is merely permissive or merely strict: a swing asks the world exactly as many
## times as its active span, and a guard from the front stops damage while the
## same guard from behind does not.

const LIGHT := {"light": true}
const BLOCK := {"block": true}
const NOTHING := {}


func _init() -> void:
	suite("combat")
	case("the tables describe attacks that exist", _table_is_sane)
	case("a swing's spans are the spans the table says", _phases)
	case("a swing runs its course and asks six times", _a_swing_runs_its_course)
	case("the world is asked only while the blade is live", _query_only_when_active)
	case("a landed hit freezes the local clock", _hitstop_freezes_the_clock)
	case("one swing touches a body once", _one_swing_hits_a_body_once)
	case("a light chain continues, and lapses", _the_combo_chain)
	case("right click guards with a shield and shoves without", _right_button_needs_a_shield)
	case("a fresh guard parries and a held one only blocks", _guarding)
	case("a guard does nothing from behind", _guard_is_front_only)
	case("a clean hit grants iframes, and they come first", _iframes)
	case("taking a hit ends the swing", _taking_a_hit_interrupts)


# ---------------------------------------------------------------- the table

func _table_is_sane() -> void:
	eq("no combo points at an attack that does not exist", CozyCombatDefs.broken_links(), [])
	is_true("the light chain starts somewhere", CozyCombatDefs.first_of("light") != "")
	eq("and it is light_1", CozyCombatDefs.first_of("light"), "light_1")
	eq("a kind with no attacks yields nothing", CozyCombatDefs.first_of("nope"), "")
	is_true("every attack has a name", CozyCombatDefs.ids().size() >= 5)


func _phases() -> void:
	# light_1 is 6 windup / 6 active / 10 recovery.
	eq("it is active from tick six to twelve", CozyCombatDefs.active_window("light_1"), Vector2i(6, 12))
	eq("which is 22 ticks end to end", CozyCombatDefs.total_ticks("light_1"), 22)
	eq("the window's width is the active span",
		CozyCombatDefs.active_window("light_1").y - CozyCombatDefs.active_window("light_1").x, 6)

	eq("tick 0 is windup", CozyCombatDefs.phase_at("light_1", 0), CozyCombatDefs.WINDUP)
	eq("tick 5 is still windup", CozyCombatDefs.phase_at("light_1", 5), CozyCombatDefs.WINDUP)
	eq("tick 6 is active", CozyCombatDefs.phase_at("light_1", 6), CozyCombatDefs.ACTIVE)
	eq("tick 11 is the last active tick", CozyCombatDefs.phase_at("light_1", 11), CozyCombatDefs.ACTIVE)
	eq("tick 12 is recovery", CozyCombatDefs.phase_at("light_1", 12), CozyCombatDefs.RECOVERY)
	eq("tick 21 is the last recovery tick", CozyCombatDefs.phase_at("light_1", 21), CozyCombatDefs.RECOVERY)
	eq("tick 22 is over", CozyCombatDefs.phase_at("light_1", 22), CozyCombatDefs.IDLE)
	eq("and an attack that does not exist is never active",
		CozyCombatDefs.active_window("nope"), Vector2i.ZERO)


# ---------------------------------------------------------------- the tick

func _a_swing_runs_its_course() -> void:
	var s := CozyCombatSolver.blank_state()
	CozyCombatSolver.step(s, LIGHT)
	eq("the press started a swing", CozyCombatSolver.is_attacking(s), true)
	eq("and it is light_1", String(s["attack_id"]), "light_1")
	eq("in windup", String(s["phase"]), CozyCombatDefs.WINDUP)

	var asked := 0
	for i in 40:
		CozyCombatSolver.step(s, NOTHING)
		if CozyCombatSolver.wants_query(s):
			asked += 1
	eq("the world was asked once per active tick", asked, 6)
	eq("and the swing is over", CozyCombatSolver.is_attacking(s), false)
	eq("back at idle", String(s["phase"]), CozyCombatDefs.IDLE)


## The cost of an explicit query is paid on live frames and nowhere else — which
## is the reason the hitbox is not an `Area3D` that is always listening.
func _query_only_when_active() -> void:
	var s := CozyCombatSolver.blank_state()
	eq("nothing is asked before anything happens", CozyCombatSolver.wants_query(s), false)
	CozyCombatSolver.step(s, LIGHT)
	eq("nor during the windup", CozyCombatSolver.wants_query(s), false)
	for i in 6:
		CozyCombatSolver.step(s, NOTHING)
	eq("but it is asked on the first active tick", CozyCombatSolver.wants_query(s), true)
	for i in 6:
		CozyCombatSolver.step(s, NOTHING)
	eq("and not once the blade is past", CozyCombatSolver.wants_query(s), false)


func _hitstop_freezes_the_clock() -> void:
	var s := CozyCombatSolver.blank_state()
	CozyCombatSolver.step(s, LIGHT)
	for i in 6:
		CozyCombatSolver.step(s, NOTHING)
	eq("the swing is live", String(s["phase"]), CozyCombatDefs.ACTIVE)

	is_true("the first contact counts", CozyCombatSolver.note_swing_landed(s, "goblin_1"))
	eq("and stops the clock for the attack's own number of ticks",
		int(s["hitstop_ticks"]), int(CozyCombatDefs.attack("light_1")["hitstop"]))

	var frozen := int(s["frame"])
	for i in int(s["hitstop_ticks"]):
		CozyCombatSolver.step(s, NOTHING)
	eq("the swing does not advance while frozen", int(s["frame"]), frozen)
	CozyCombatSolver.step(s, NOTHING)
	eq("and resumes on the tick after", int(s["frame"]), frozen + 1)


func _one_swing_hits_a_body_once() -> void:
	var s := CozyCombatSolver.blank_state()
	CozyCombatSolver.step(s, LIGHT)
	for i in 6:
		CozyCombatSolver.step(s, NOTHING)

	is_true("the first contact counts", CozyCombatSolver.note_swing_landed(s, "goblin_1"))
	is_false("the same body on the next live tick does not",
		CozyCombatSolver.note_swing_landed(s, "goblin_1"))
	is_true("a second body in the arc does", CozyCombatSolver.note_swing_landed(s, "goblin_2"))
	eq("two bodies, two hits", (s["already_hit"] as Array).size(), 2)
	is_true("and the record knows which", CozyCombatSolver.has_hit(s, "goblin_1"))


# ---------------------------------------------------------------- the chain

func _the_combo_chain() -> void:
	var s := CozyCombatSolver.blank_state()
	CozyCombatSolver.step(s, LIGHT)
	eq("the chain starts at light_1", String(s["attack_id"]), "light_1")
	for i in CozyCombatDefs.total_ticks("light_1"):
		CozyCombatSolver.step(s, NOTHING)
	eq("when it ends, the next link is offered", String(s["pending_combo"]), "light_2")
	is_true("with a window to take it", int(s["combo_window"]) > 0)

	CozyCombatSolver.step(s, LIGHT)
	eq("a press inside the window continues the chain", String(s["attack_id"]), "light_2")
	eq("instead of starting over", CozyCombatSolver.is_attacking(s), true)

	# The control: the same swing, the same silence, long enough that the window
	# closes. Without this the case above would pass on a solver that always
	# chains, which is a different game.
	var t := CozyCombatSolver.blank_state()
	CozyCombatSolver.step(t, LIGHT)
	var run_out := CozyCombatDefs.total_ticks("light_1") \
		+ int(CozyCombatDefs.attack("light_1")["combo_window"])
	for i in run_out:
		CozyCombatSolver.step(t, NOTHING)
	eq("letting the window lapse closes the chain", String(t["pending_combo"]), "")
	eq("and the window is spent", int(t["combo_window"]), 0)
	CozyCombatSolver.step(t, LIGHT)
	eq("so the next press starts over", String(t["attack_id"]), "light_1")


# ---------------------------------------------------------------- the guard

## Willow's rule, and the reason the shield is a fact on the STATE rather than a
## branch in the input: the same button means two different things.
func _right_button_needs_a_shield() -> void:
	var unarmed := CozyCombatSolver.blank_state()
	CozyCombatSolver.step(unarmed, BLOCK)
	eq("right click with no shield shoves", String(unarmed["attack_id"]), "shove")

	var armed := CozyCombatSolver.blank_state()
	armed["has_shield"] = true
	for i in 3:
		CozyCombatSolver.step(armed, BLOCK)
	is_false("right click with a shield does not attack", CozyCombatSolver.is_attacking(armed))
	is_true("it guards", bool(armed["guarding"]))
	eq("and the guard has been up three ticks", int(armed["guard_held"]), 3)

	var idle := CozyCombatSolver.blank_state()
	idle["has_shield"] = true
	CozyCombatSolver.step(idle, NOTHING)
	is_false("letting go drops the guard", bool(idle["guarding"]))
	eq("and the parry clock with it", int(idle["guard_held"]), 0)


func _guarding() -> void:
	var parry := CozyCombatSolver.blank_state()
	parry["has_shield"] = true
	for i in 3:
		CozyCombatSolver.step(parry, BLOCK)
	eq("a guard raised a moment ago parries for nothing",
		CozyCombatSolver.apply_hit(parry, 20, true), {"damage": 0, "kind": "parry"})

	var held := CozyCombatSolver.blank_state()
	held["has_shield"] = true
	for i in 40:
		CozyCombatSolver.step(held, BLOCK)
	eq("a guard held too long only blocks",
		CozyCombatSolver.apply_hit(held, 20, true), {"damage": 8, "kind": "block"})

	# The control: no guard at all takes it whole. Without this, "blocking works"
	# would pass on a solver that reduces damage unconditionally.
	var open := CozyCombatSolver.blank_state()
	open["has_shield"] = true
	eq("a guard that is not raised takes it whole",
		CozyCombatSolver.apply_hit(open, 20, true), {"damage": 20, "kind": "hit"})


func _guard_is_front_only() -> void:
	var s := CozyCombatSolver.blank_state()
	s["has_shield"] = true
	for i in 40:
		CozyCombatSolver.step(s, BLOCK)
	eq("the same guard, hit from behind, does nothing",
		CozyCombatSolver.apply_hit(s, 20, false), {"damage": 20, "kind": "hit"})


func _iframes() -> void:
	var s := CozyCombatSolver.blank_state()
	eq("a clean hit lands", CozyCombatSolver.apply_hit(s, 20, true), {"damage": 20, "kind": "hit"})
	eq("and grants iframes", int(s["iframe_ticks"]), CozyCombatSolver.IFRAME_TICKS)
	eq("so the next one is refused",
		CozyCombatSolver.apply_hit(s, 20, true), {"damage": 0, "kind": "iframe"})
	eq("and the refused one grants nothing",
		int(s["iframe_ticks"]), CozyCombatSolver.IFRAME_TICKS)

	# I-frames are answered FIRST. Checking the guard first would let a parry
	# renew invulnerability, and the two rules would fight over the same tick.
	var g := CozyCombatSolver.blank_state()
	g["has_shield"] = true
	CozyCombatSolver.apply_hit(g, 20, true)
	for i in 2:
		CozyCombatSolver.step(g, BLOCK)
	eq("iframes beat the guard", String(CozyCombatSolver.apply_hit(g, 20, true)["kind"]), "iframe")

	# ... and they run out.
	var e := CozyCombatSolver.blank_state()
	CozyCombatSolver.apply_hit(e, 20, true)
	for i in CozyCombatSolver.IFRAME_TICKS:
		CozyCombatSolver.step(e, NOTHING)
	eq("and they expire", int(e["iframe_ticks"]), 0)
	eq("after which a hit lands again",
		CozyCombatSolver.apply_hit(e, 20, true), {"damage": 20, "kind": "hit"})


func _taking_a_hit_interrupts() -> void:
	var s := CozyCombatSolver.blank_state()
	CozyCombatSolver.step(s, LIGHT)
	for i in 6:
		CozyCombatSolver.step(s, NOTHING)
	is_true("mid-swing", CozyCombatSolver.is_attacking(s))

	CozyCombatSolver.apply_hit(s, 5, true)
	is_false("being hit ends the swing", CozyCombatSolver.is_attacking(s))
	eq("at idle", String(s["phase"]), CozyCombatDefs.IDLE)
	eq("with nothing to continue", String(s["pending_combo"]), "")
	eq("and a clean slate of contacts", (s["already_hit"] as Array).size(), 0)

	# The control: the same swing, uninterrupted, does finish — so "being hit
	# ends it" is not passing on a solver where swings never end at all.
	var u := CozyCombatSolver.blank_state()
	CozyCombatSolver.step(u, LIGHT)
	for i in 6:
		CozyCombatSolver.step(u, NOTHING)
	is_true("the same swing is still live when nothing hits it", CozyCombatSolver.is_attacking(u))
