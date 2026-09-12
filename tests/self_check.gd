class_name CozySelfCheck
extends RefCounted
## The headless self-check's schedule and its bookkeeping.
##
## WHAT IS HERE: when each stage is due, whether it has run, and which stages
## exist at all.
##
## WHAT IS DELIBERATELY NOT HERE YET: the checks themselves. All 40 of them still
## live on `Main`, because they read `terrain`, `building`, `npc`, `hud`, `camera`
## and `scatter` as members of it — moving them is an architecture change, not a
## file move, and it gets its own session (Willow 2026-09-12). This module is the
## seam that makes that move possible later, one stage at a time, instead of in
## one risky sweep.
##
## It replaces a boolean member per stage plus a chain of `if` blocks in
## `Main._run_headless_stages()`. Adding a check is now one line in one place,
## rather than a member and an if-block in two.
##
## ─────────────────────────────────────────────────────────────────────────────
## THE ONE THING TO KNOW: the game runs the self-check when it is launched
## headless. The entry point is the same command as always —
##
##     godot --headless --path <repo> --quit-after 4500
##
## — and it must keep working that way. The runner exists to organise the check,
## not to gate it behind a new invocation.

## One stage: a name, the physics frame it becomes due, and what to call.
## `gate` is optional — a stage only fires when it returns true.
var _stages: Array = []


## Register a stage. Called once, from `Main._build_self_check()`.
##
## `at_frame` is a PHYSICS frame. `--quit-after` counts idle frames, and the two
## diverge under a variable step, so a stage scheduled on the wrong clock fires
## at a different moment than the one it was measured at.
func add(name: String, at_frame: int, call: Callable, gate := Callable()) -> void:
	_stages.append({
		"name": name, "at": at_frame, "call": call, "gate": gate, "run": false,
	})


## Every stage that has come due and has not run yet, taking each exactly once.
##
## It MARKS as it takes, so the same stage cannot be returned twice however often
## this is called. A stage whose `gate` says no is left pending rather than
## consumed — a command-line flag is fixed for the run, but "not yet" and "never"
## are different answers and collapsing them would hide a gate that never opens.
func take_due(frame: int) -> Array:
	var out: Array = []
	for s in _stages:
		if s["run"] or frame <= int(s["at"]):
			continue
		var g: Callable = s["gate"]
		if g.is_valid() and not bool(g.call()):
			continue
		s["run"] = true
		out.append(s)
	return out


## Run everything due this frame. Returns the names that ran, so a caller can log
## or assert on them.
func run_due(frame: int) -> Array[String]:
	var ran: Array[String] = []
	for s in take_due(frame):
		ran.append(String(s["name"]))
		(s["call"] as Callable).call()
	return ran


func stage_names() -> Array[String]:
	var out: Array[String] = []
	for s in _stages:
		out.append(String(s["name"]))
	return out


## The stages that are expected to run in EVERY run — the ones with no gate.
##
## A gated stage is opt-in by definition (a probe behind a command-line flag), so
## "it did not run" is the normal case for it and must not read as a failure.
func required_names() -> Array[String]:
	var out: Array[String] = []
	for s in _stages:
		if not (s["gate"] as Callable).is_valid():
			out.append(String(s["name"]))
	return out


func has_run(name: String) -> bool:
	for s in _stages:
		if String(s["name"]) == name:
			return bool(s["run"])
	return false


func run_count() -> int:
	var n := 0
	for s in _stages:
		if s["run"]:
			n += 1
	return n


## One line, for the log: how much of the schedule this run got through.
func describe() -> String:
	return "%d stage(s), %d run" % [_stages.size(), run_count()]
