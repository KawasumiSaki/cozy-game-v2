class_name CozyCombatSolver
extends RefCounted
## One tick of a fight, as arithmetic over the tables in `CozyCombatDefs`.
##
## PURE, AND IT NEVER TOUCHES THE WORLD. Every function here reads a Dictionary
## and writes a Dictionary; nothing asks the scene tree, the physics server or
## the clock. That is what lets a fight be asserted without booting anything —
## and it is why the one function that DOES need the world (`_shape_query`, in
## whatever node drives this) is a single short seam rather than a system.
##
## ---------------------------------------------------------------------------
## THE INPUT IS TWO BUTTONS AND THE STATE IS A DICTIONARY. Willow's rule is
## "left mouse attacks, right mouse guards with a shield and does something else
## without one" — and the shield is deliberately NOT the input's business. The
## input says `block` was pressed; whether that means guarding or shoving is a
## question about the character, so it is a fact on the state and the solver
## answers it. An input handler that knew about shields would be a rule living in
## a mouse handler, which `docs/INVARIANTS.md` forbids.
##
## ---------------------------------------------------------------------------
## WHY A TICK AND NOT A TIMER. `hitstop_ticks` suppresses the LOCAL clock: the
## hit lands, time stops for four ticks, and the swing resumes mid-frame. The
## obvious implementation is `Engine.time_scale`, and it is wrong — it changes
## the physics delta and makes results vary with framerate (godot#24334), which
## costs exactly the determinism this file exists to provide.

## Ticks of invulnerability after a clean hit. Without it, three enemies standing
## together are one large number instead of a fight.
const IFRAME_TICKS := 20

## A block staggers, a parry does not, and a clean hit interrupts. These are the
## three ways `_land` can stop the clock.
const NO_HITSTOP := 0


static func blank_state() -> Dictionary:
	return {
		"attack_id": "",        ## The swing in progress, or "".
		"frame": 0,             ## Ticks into that swing.
		"phase": CozyCombatDefs.IDLE,
		"pending_combo": "",    ## Where a second press leads, once a swing ends.
		"combo_window": 0,      ## Ticks left to take it.
		"iframe_ticks": 0,
		"hitstop_ticks": 0,
		"guarding": false,
		"guard_held": 0,        ## How long the guard has been up; this is the parry.
		"has_shield": false,    ## A FACT ABOUT THE CHARACTER, not about the input.
		"already_hit": [],      ## Target ids this swing has already touched.
	}


# ---------------------------------------------------------------- the tick

## Advance one tick. `buttons` is `{light, heavy, block}` and unknown keys are
## ignored, so an input layer can pass whatever it has.
static func step(s: Dictionary, buttons: Dictionary) -> void:
	# A landed hit stops the LOCAL clock. Everything below is inside the freeze,
	# including the swing that landed it — which is what makes the pause read as
	# impact rather than as a dropped frame.
	if int(s["hitstop_ticks"]) > 0:
		s["hitstop_ticks"] = int(s["hitstop_ticks"]) - 1
		return

	if int(s["iframe_ticks"]) > 0:
		s["iframe_ticks"] = int(s["iframe_ticks"]) - 1

	if int(s["combo_window"]) > 0:
		s["combo_window"] = int(s["combo_window"]) - 1
		if int(s["combo_window"]) == 0:
			s["pending_combo"] = ""   ## The chain is closed; a press starts over.

	# Guarding needs both hands. A swing in progress owns them.
	var block_held := bool(buttons.get("block", false))
	var guarding: bool = block_held and String(s["attack_id"]) == ""
	s["guarding"] = guarding
	s["guard_held"] = (int(s["guard_held"]) + 1) if guarding else 0

	var id := String(s["attack_id"])
	if id != "":
		s["frame"] = int(s["frame"]) + 1
		var ph := CozyCombatDefs.phase_at(id, int(s["frame"]))
		if ph != CozyCombatDefs.IDLE:
			s["phase"] = ph
			return
		# The swing is over.
		var nxt := String(CozyCombatDefs.attack(id).get("combo_next", ""))
		s["attack_id"] = ""
		s["frame"] = 0
		s["phase"] = CozyCombatDefs.IDLE
		s["already_hit"].clear()
		if nxt != "":
			s["pending_combo"] = nxt
			s["combo_window"] = int(CozyCombatDefs.attack(id).get("combo_window", 0))
		return

	# Hands free. A button starts something.
	if bool(buttons.get("light", false)):
		var chain := String(s["pending_combo"])
		_start(s, chain if chain != "" else CozyCombatDefs.first_of("light"))
	elif block_held and not bool(s["has_shield"]):
		# Right click with nothing to guard with. Willow's rule, as a row.
		_start(s, "shove")


static func _start(s: Dictionary, id: String) -> void:
	if id == "" or not CozyCombatDefs.exists(id):
		return
	s["attack_id"] = id
	s["frame"] = 0
	s["phase"] = CozyCombatDefs.phase_at(id, 0)
	s["pending_combo"] = ""
	s["combo_window"] = 0
	s["already_hit"].clear()
	# A swing ends the guard: you cannot attack and block with the same hands.
	s["guarding"] = false
	s["guard_held"] = 0


# ---------------------------------------------------------------- queries

## Should the driver ask the world whether anything is in the way this tick?
##
## TRUE ONLY ON ACTIVE FRAMES, which is the whole reason the query is explicit
## rather than an `Area3D` that is always listening: the cost is paid on the
## twelve ticks a swing is live and on no others.
static func wants_query(s: Dictionary) -> bool:
	return String(s["attack_id"]) != "" \
		and String(s["phase"]) == CozyCombatDefs.ACTIVE


## Is this character mid-swing?
static func is_attacking(s: Dictionary) -> bool:
	return String(s["attack_id"]) != ""


## Has this swing already touched that body? One swing, one hit per target —
## without it a wide swing inside a crowd bills every physics frame it overlaps.
static func has_hit(s: Dictionary, target_id: String) -> bool:
	return (s["already_hit"] as Array).has(target_id)


# ---------------------------------------------------------------- landing

## The swing connected with `target_id`. Returns whether it counted.
##
## The hitstop is read HERE rather than by the caller, so the table has exactly
## one reader — a second caller reading `ATTACKS[...]["hitstop"]` for itself is
## how two places come to disagree about how long impact lasts.
static func note_swing_landed(s: Dictionary, target_id: String) -> bool:
	if not wants_query(s) or has_hit(s, target_id):
		return false
	(s["already_hit"] as Array).append(target_id)
	var stop := int(CozyCombatDefs.attack(String(s["attack_id"])).get("hitstop", 0))
	s["hitstop_ticks"] = maxi(int(s["hitstop_ticks"]), stop)
	return true


## What happens to THIS character when something hits it.
##
## This one function is the entire answer to invulnerability and to guarding, and
## the order matters:
##
##   1. i-frames first — a character that cannot be hit is not hit, whatever it
##      is doing. Checking the guard first would let a parry extend invulnerability
##      and make the two rules fight.
##   2. the guard, but only against something IN FRONT. A guard that works from
##      behind is not a guard, it is immunity.
##   3. `guard_held <= parry_window` is a PARRY: recent enough to be a read rather
##      than a held button, and it stops everything.
##
## `from_front` is passed in rather than computed, because facing is a fact about
## the world and this file does not have one.
static func apply_hit(s: Dictionary, incoming: int, from_front: bool) -> Dictionary:
	if int(s["iframe_ticks"]) > 0:
		return {"damage": 0, "kind": "iframe"}

	if bool(s["guarding"]) and from_front:
		var guard: Dictionary = CozyCombatDefs.GUARD
		var held := int(s["guard_held"])
		if held <= int(guard["parry_window"]):
			_land(s, NO_HITSTOP)
			return {"damage": 0, "kind": "parry"}
		var through := int(round(float(incoming) * (1.0 - float(guard["reduction"]))))
		_land(s, int(guard["stagger"]))
		return {"damage": through, "kind": "block"}

	_land(s, NO_HITSTOP)
	s["iframe_ticks"] = IFRAME_TICKS
	return {"damage": incoming, "kind": "hit"}


## Taking a hit interrupts whatever was in progress.
##
## A swing that survives being hit finishes anyway, which is the "why did my
## attack still come out" bug — and it is worse than it looks, because the swing
## that comes out was started before the player knew they had been hit.
static func _land(s: Dictionary, stop: int) -> void:
	s["attack_id"] = ""
	s["frame"] = 0
	s["phase"] = CozyCombatDefs.IDLE
	s["pending_combo"] = ""
	s["combo_window"] = 0
	s["already_hit"].clear()
	s["guarding"] = false
	s["guard_held"] = 0
	if stop > int(s["hitstop_ticks"]):
		s["hitstop_ticks"] = stop


func describe_state(s: Dictionary) -> String:
	return "%s frame %d (%s)%s%s" % [
		s["attack_id"] if String(s["attack_id"]) != "" else "idle",
		int(s["frame"]), String(s["phase"]),
		", guard %d" % int(s["guard_held"]) if bool(s["guarding"]) else "",
		", iframes %d" % int(s["iframe_ticks"]) if int(s["iframe_ticks"]) > 0 else ""]
