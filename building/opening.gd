class_name CozyOpening
extends RefCounted
## A parametric opening cut into a wall (V2 doc #29 Door, #30 Window).
##
## The doc treats doors and windows as OPENINGS IN a wall rather than as separate
## objects parked next to it — #30 is explicit: "a window is also a Wall's
## Opening". That distinction matters, because the wall then generates its own
## geometry around the hole. A doorway no longer has to be hand-carved by
## splitting the wall into two segments with a gap between them.

enum Kind { DOOR, WINDOW }

var kind: Kind = Kind.DOOR

var offset := 0.0   ## Metres from the wall's start to the opening's centre.
var width := 1.0    ## Metres.
var sill := 0.0     ## Height of the bottom of the hole above the floor.
var head := 2.1     ## Height of the top of the hole.


## A doorway: reaches the floor, so an agent can walk through it.
static func door(offset_m: float, width_m: float, head_m := 2.1) -> CozyOpening:
	var o := CozyOpening.new()
	o.kind = Kind.DOOR
	o.offset = offset_m
	o.width = width_m
	o.sill = 0.0
	o.head = head_m
	return o


## A window: starts above the floor. Note this leaves a sill piece below it,
## which is what stops agents walking through — no special-casing required.
static func window(offset_m: float, width_m: float, sill_m := 0.9, head_m := 2.1) -> CozyOpening:
	var o := CozyOpening.new()
	o.kind = Kind.WINDOW
	o.offset = offset_m
	o.width = width_m
	o.sill = sill_m
	o.head = head_m
	return o


func kind_name() -> String:
	return "door" if kind == Kind.DOOR else "window"


func describe() -> String:
	return "%s @%.2fm w%.2f [%.2f..%.2f]" % [kind_name(), offset, width, sill, head]
