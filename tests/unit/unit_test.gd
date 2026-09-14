extends RefCounted
## Minimal unit-test base. NO FRAMEWORK, on purpose.
##
## Why not GUT or GdUnit4: those run unit tests well, and this project's other
## 118 assertions are INTEGRATION checks that boot a real world for thousands of
## frames — a unit framework would not run them, so adopting one buys a second
## harness rather than replacing the first. What was missing was somewhere to put
## PURE-LOGIC tests, and that needs about forty lines, not an addon.
##
## Revisit when `unit/` has enough in it that the bookkeeping hurts. See
## tests/README.md.
##
## Subclass by PATH, not by class_name:
##
##     extends "res://tests/unit/unit_test.gd"
##
## A `class_name` would need a `--import` run before anything could reference it,
## and a test file that cannot be loaded until the project is re-imported is a
## test file that silently stops running.

var _suite := ""
var _cases: Array = []              ## {name: String, call: Callable}
var _failures: Array[String] = []
var _checks := 0
var _silent: Array[String] = []     ## cases that ran without asserting anything


func suite(p_name: String) -> void:
	_suite = p_name


## Register a case. Order is preserved: a test suite reads best as a list of
## statements about the system.
func case(case_name: String, call: Callable) -> void:
	_cases.append({"name": case_name, "call": call})


# ---------------------------------------------------------------- assertions

func eq(case_name: String, got, want) -> void:
	_checks += 1
	if got != want:
		_failures.append("%s: got %s, wanted %s" % [case_name, str(got), str(want)])


func ne(case_name: String, got, unwanted) -> void:
	_checks += 1
	if got == unwanted:
		_failures.append("%s: got %s, which is what it must not be" % [case_name, str(got)])


func is_true(case_name: String, cond: bool) -> void:
	_checks += 1
	if not cond:
		_failures.append("%s: expected true" % case_name)


func is_false(case_name: String, cond: bool) -> void:
	_checks += 1
	if cond:
		_failures.append("%s: expected false" % case_name)


## Numeric closeness. Exact equality on floats is a way to write a test that
## fails for a reason nobody cares about.
func near(case_name: String, got: float, want: float, tol := 0.0001) -> void:
	_checks += 1
	if absf(got - want) > tol:
		_failures.append("%s: got %f, wanted %f (+-%f)" % [case_name, got, want, tol])


# ---------------------------------------------------------------- results

## Each case is counted, because a case that asserts NOTHING is a case that
## cannot fail — and the way that happens is not a mistake in the case, it is a
## GDScript runtime error partway through it.
##
## There is no `try` in GDScript. An invalid call aborts the FUNCTION and returns
## to here, so every assertion after it is skipped, the suite stays green, and the
## only mark left is a `SCRIPT ERROR` on stderr. That is the same shape as the
## `[FAIL` counting bug and the `JSON.parse_string` one: a green number that is
## green because nothing looked.
##
## This catches the case that aborted BEFORE its first assertion. One that aborts
## after three of them still counts three, and only the log can tell — which is
## why `tests/README.md` makes counting `ERROR` part of running this, not advice.
func run() -> void:
	for c in _cases:
		var before := _checks
		(c["call"] as Callable).call()
		if _checks == before:
			_silent.append(String(c["name"]))


func suite_name() -> String:
	return _suite


func failures() -> Array[String]:
	return _failures


## Cases that ran and asserted nothing. Reported as failures by `run.gd`: a case
## nobody can watch fail is not coverage.
func silent_cases() -> Array[String]:
	return _silent


func checks() -> int:
	return _checks


func case_count() -> int:
	return _cases.size()


func passed() -> bool:
	return _failures.is_empty()
