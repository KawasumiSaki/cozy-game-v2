class_name CozyDungeonBlueprint
extends RefCounted
## What a dungeon IS, before anything is built from it: an id and its outlines.
##
## The design doc's own revision of this format (section 3, 2026-09-12) replaced
## `rooms` with `outlines`, on the project's first invariant — *rooms are DERIVED,
## never authored*. A blueprint that listed its rooms would be a second copy of
## something the wall graph already answers, and the two would drift the first
## time a wall moved. So a blueprint stores WALLS, and the rooms, portals, room
## graph, navigation, roofs, occlusion and the save all fall out of systems that
## already exist and are already asserted.
##
## ---------------------------------------------------------------------------
## WHAT THIS FORMAT REFUSES, WHICH IS MOST OF WHAT IT DOES
##
## The doc's example is longer than this format. It also carries `links`, `spawns`
## and `content`, and all three are refused BY NAME rather than parsed and
## ignored. The difference is the whole reason this file has an opinion: a field
## that is accepted and never read is indistinguishable, from the author's side,
## from one that works. This project has paid seven times for a table nothing
## consumes (`docs/INVARIANTS.md`, "A declared capability with no consumer is not
## a feature"), so a refusal names the field and says what would have to exist.
##
##   `links`    What the doc stores as an explicit connection between outlines is
##              a MEASUREMENT, not an input. Which outlines meet, and along which
##              stretch, follows from their geometry — `CozyDungeonLayout`
##              derives the shared edges, the butt edges and the doorways from
##              the outlines alone, and `tests/probe/dungeon_layout_probe.gd`
##              measured that the naive reading merges the rooms silently. A
##              stored copy would be a second answer to a question already
##              answered, and the runtime answer is the one that tracks an edit.
##
##   `spawns`   Need a vocabulary: what may be spawned, what a content table is,
##   `content`  and what a "room hint" resolves to against derived rooms. None of
##              it exists. Both fields join the format on the day the system that
##              reads them does, together with its validation — at which point it
##              is an extension WITH assertions rather than a field that has been
##              sitting in the files, unread, for a year.
##
## Refusal is silent in the sense that nothing reaches the world: the reason is
## RETURNED, never printed. A refusal is a safe outcome and a caller's assertion
## is the detection — the same split `core/entity_registry.gd` settled on after
## a probe and a `push_error` were found fighting each other in the log.

## Bumped when the FORMAT changes, which is not the same thing as a dungeon
## changing — that needs no bump at all, a blueprint is data.
const VERSION := 1

## The keys this format defines. Everything else is refused by name, so a field
## cannot arrive without someone having decided it should.
const KNOWN: Array[String] = ["id", "version", "outlines"]

## Fields the doc's example carries that this format deliberately does not, each
## with the reason it is refused rather than ignored. Kept beside `KNOWN` so that
## "what is in the format" is one list, not something you reconstruct by reading
## the parser and hoping you found every branch.
const REFUSED := {
	"links": "which outlines meet, and where, is derived from their geometry",
	"spawns": "no spawn vocabulary exists to validate it against",
	"content": "no content vocabulary exists to validate it against",
}

## Outline coordinates are x, z in PLAN space, the same frame
## `CozyDungeonLayout` and `CozyRoomDetector` work in.
var id := ""
var outlines: Array = []      ## Array[PackedVector2Array]

## Where this was read from — diagnostics only, never gameplay.
var source_path := ""


# ---------------------------------------------------------------- reading

## Why this document is not a usable blueprint, or "" when it is.
##
## The ONE place that decides. `from_dict` builds only what this accepts, so
## there is no route to a live blueprint that was never checked — which is the
## difference between a validated format and a validate() somebody may call.
static func reject_reason(d: Dictionary) -> String:
	var version_reason := _version_reason(d)
	if version_reason != "":
		return version_reason

	var unknown := _unknown_reason(d)
	if unknown != "":
		return unknown

	var the_id: Variant = d.get("id", "")
	if not (the_id is String) or (the_id as String).strip_edges() == "":
		return "no id: a blueprint has to be nameable"

	var listed: Variant = d.get("outlines", null)
	if not (listed is Array):
		return "'outlines' is missing, or is not a list"
	if (listed as Array).is_empty():
		return "no outlines: a dungeon is its walls, and this one has none"

	for i in (listed as Array).size():
		var poly := _to_polygon((listed as Array)[i])
		if poly.is_empty():
			return "outline %d is not x, z pairs - an even count of finite numbers" % i
		# The SAME guard the building pipeline applies, called rather than
		# restated. Two copies of a rule are two answers the first time one of
		# them is edited, and this one already carries the reasoning about why a
		# concave outline is legal and a self-intersecting one is not.
		var why := CozyOutlineGenerator.reject_reason(poly)
		if why != "":
			return "outline %d: %s" % [i, why]

	return ""


## Text to blueprint — the path a real file takes.
##
## Returns `{"blueprint": CozyDungeonBlueprint, "reason": String}` with exactly
## one of the two meaningful. The reason is not optional reading: a caller that
## drops it is a caller that loads an empty dungeon and reports success.
##
## Malformed input is refused QUIETLY — nothing is printed, on any path. A
## dungeon file that does not parse is a refusal like any other, and the log has
## to stay clean enough that `0 ERROR` means the build is healthy.
static func parse(text: String, from_path := "") -> Dictionary:
	# `JSON.parse_string` PRINTS on malformed input, which is the trap
	# `core/entity_registry.gd` recorded: a line that means "the refusal worked"
	# must not look like the line that means "the build broke", or `0 ERROR`
	# stops being a true statement about a healthy build. A refusal here is a
	# silent, returned outcome, and `JSON.new()` is the only form that gives one.
	var json := JSON.new()
	if json.parse(text) != OK:
		return {"blueprint": null, "reason": "not valid JSON: %s (line %d)" % [
			json.get_error_message(), json.get_error_line()]}
	var parsed: Variant = json.data
	if not (parsed is Dictionary):
		return {"blueprint": null, "reason": "not a JSON object"}
	var why := reject_reason(parsed)
	if why != "":
		return {"blueprint": null, "reason": why}
	return {"blueprint": from_dict(parsed, from_path), "reason": ""}


## Build a blueprint, or null when `reject_reason` refuses the document. There is
## deliberately no way to get one that was not checked.
static func from_dict(d: Dictionary, from_path := "") -> CozyDungeonBlueprint:
	if reject_reason(d) != "":
		return null

	var b := CozyDungeonBlueprint.new()
	b.source_path = from_path
	b.id = String(d["id"]).strip_edges()
	for raw in (d["outlines"] as Array):
		b.outlines.append(_to_polygon(raw))
	return b


# ---------------------------------------------------------------- writing

## JSON's OWN types, nothing else.
##
## `Vector2` and `PackedVector2Array` are not among them, and `JSON.stringify`
## writes a packed array out as a STRING — which then reads back as a string and
## cannot be assigned to the array it came from. `docs/INVARIANTS.md` has the
## three separate bugs that hid behind one `to_dict()` that only ever made an
## in-memory round trip.
func to_dict() -> Dictionary:
	var listed: Array = []
	for poly: PackedVector2Array in outlines:
		var flat: Array = []
		for p: Vector2 in poly:
			flat.append(p.x)
			flat.append(p.y)
		listed.append(flat)
	return {"id": id, "version": VERSION, "outlines": listed}


## The document, serialized. Paired with `parse`, this is the round trip a
## blueprint has to survive to be a file format rather than an in-memory shape.
func to_json() -> String:
	return JSON.stringify(to_dict())


# ---------------------------------------------------------------- use

## The wall graph this blueprint resolves to — the bridge to DG-01's first half,
## and the reason the contract is load-bearing rather than decorative.
func layout() -> CozyDungeonLayout:
	var l := CozyDungeonLayout.new()
	l.set_outlines(outlines)
	return l


func outline_count() -> int:
	return outlines.size()


func describe() -> String:
	return "%s v%d, %d outline(s)" % [id, VERSION, outlines.size()]


# ---------------------------------------------------------------- guards

## A blueprint that does not say what it is cannot be read safely.
##
## A NEWER version is refused rather than read as well as this build can. This
## build would take the fields it recognises and DROP whatever the newer format
## added, and the only symptom would be a dungeon that is quietly missing a room
## — the failure mode this project has paid for more than once, where the file
## loads, the assertion passes, and the world is smaller than it should be.
##
## An OLDER version would be a migration step here, the way `save_manager.gd`
## keeps one per version. There is nothing below 1, so there is no chain to
## build: a chain with one link and no data is exactly the "declared capability
## with no consumer" this file refuses two fields over. When VERSION goes to 2,
## the step goes here, written against a real v1 file.
static func _version_reason(d: Dictionary) -> String:
	var v: Variant = d.get("version", null)
	if typeof(v) != TYPE_INT and typeof(v) != TYPE_FLOAT:
		return "no version: a blueprint that does not say what it is cannot be read safely"
	var n := int(v)
	if n > VERSION:
		return "version %d is newer than %d - this build would read it as v%d and silently drop whatever v%d added" % [
			n, VERSION, VERSION, n]
	if n < VERSION:
		return "version %d is older than %d, and there is no migration step for it" % [n, VERSION]
	return ""


## Any key that is not in `KNOWN`. A field the doc defines but this format does
## not gets its own sentence, so an author is told what would have to exist
## first rather than only that the key was unexpected.
static func _unknown_reason(d: Dictionary) -> String:
	for k in d:
		var key := String(k)
		if KNOWN.has(key):
			continue
		if REFUSED.has(key):
			return "'%s' is not part of the blueprint format: %s" % [key, REFUSED[key]]
		return "'%s' is not a blueprint field" % key
	return ""


## A flat `[x, z, x, z, ...]` list as a polygon, or an EMPTY array when the list
## is not one. Empty is the sentinel because it is never a legal outline, and the
## count minimum is left to the outline guard so that "needs at least 3 points"
## is said in one place rather than two.
static func _to_polygon(raw: Variant) -> PackedVector2Array:
	var out := PackedVector2Array()
	if not (raw is Array):
		return out
	var flat: Array = raw
	if flat.size() < 2 or flat.size() % 2 != 0:
		return out
	for i in range(0, flat.size(), 2):
		var x: Variant = flat[i]
		var z: Variant = flat[i + 1]
		if not _is_number(x) or not _is_number(z):
			return PackedVector2Array()
		var fx := float(x)
		var fz := float(z)
		if not is_finite(fx) or not is_finite(fz):
			return PackedVector2Array()
		out.append(Vector2(fx, fz))
	return out


## JSON has no literal for infinity or NaN, so this only ever fires on a document
## assembled in code rather than parsed. It is here because "only ever fires on
## the path nobody tests" is the definition of a bug that ships.
static func _is_number(v: Variant) -> bool:
	return typeof(v) == TYPE_INT or typeof(v) == TYPE_FLOAT
