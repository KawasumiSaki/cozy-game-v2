extends "res://tests/unit/unit_test.gd"
## The blueprint contract: what a dungeon document may say, and what it may not.
##
## Two halves, and they are each other's teeth. If the format accepted
## everything, every refusal case here would pass for the wrong reason; if it
## accepted nothing, the round trip and the room count could not pass at all.
##
## The room count is the case that makes the contract LOAD-BEARING rather than
## decorative: it parses a document written the way the design doc writes it,
## resolves it through `CozyDungeonLayout`, and asserts the outlines still derive
## TWO rooms. A `from_dict` that lost or mangled the coordinates would pass every
## other case in this file and fail that one.
##
## Pure logic — no world is booted, no file is written except where a serializer
## is the thing under test.

const ROOM_A := [0, 0, 8, 0, 8, 6, 0, 6]
const ROOM_B := [8, 0, 16, 0, 16, 6, 8, 6]


func _init() -> void:
	suite("dungeon blueprint")
	case("a document written as the doc writes it parses", _parses_doc_shape)
	case("a round trip goes through a real serializer", _round_trip)
	case("and through a real file, not just a string", _round_trip_through_a_file)
	case("the serialized coordinates are JSON's numbers", _json_native)
	case("the outlines still derive two rooms, not one", _resolves_to_rooms)
	case("a newer version is refused, not read", _newer_version_refused)
	case("a document with no version is refused", _no_version_refused)
	case("links is refused, and the reason says why", _links_refused)
	case("spawns and content are refused by name", _content_refused)
	case("an unknown key is refused by name", _unknown_key_refused)
	case("a self-intersecting outline is refused", _crossing_refused)
	case("a malformed outline is refused", _malformed_refused)
	case("a refused document yields no blueprint", _refusal_yields_nothing)


# ---------------------------------------------------------------- accepting

## The design doc's own example shape: a flat `[x, z, ...]` list per outline, and
## a document that is only what this format defines.
func _parses_doc_shape() -> void:
	var r := CozyDungeonBlueprint.parse(_json(ROOM_A, ROOM_B))
	eq("nothing to object to", r["reason"], "")
	is_true("a blueprint came back", r["blueprint"] != null)
	var b: CozyDungeonBlueprint = r["blueprint"]
	eq("with the id from the document", b.id, "forest_dungeon_01")
	eq("and both outlines", b.outline_count(), 2)
	eq("the first one intact",
		b.outlines[0], PackedVector2Array([Vector2(0, 0), Vector2(8, 0), Vector2(8, 6), Vector2(0, 6)]))


## `docs/INVARIANTS.md`: a `to_dict()` that never passes through a serializer is
## not a save format. An in-memory round trip hands back live objects, so the
## assignment succeeds and the assertion is decoration. This goes out as TEXT and
## comes back through the parser, which is the only shape that proves anything.
func _round_trip() -> void:
	var b: CozyDungeonBlueprint = _ok(ROOM_A, ROOM_B)
	var again := CozyDungeonBlueprint.parse(b.to_json())
	eq("the serialized document is accepted", again["reason"], "")
	is_true("and parses", again["blueprint"] != null)
	var a: CozyDungeonBlueprint = again["blueprint"]
	eq("with the id", a.id, b.id)
	eq("the same number of outlines", a.outline_count(), b.outline_count())
	for i in b.outline_count():
		eq("outline %d survived the serializer" % i, a.outlines[i], b.outlines[i])


## `docs/INVARIANTS.md` does not stop at "go through a serializer" — it says
## write it to DISK and read it back, because a round trip that never touches a
## file proves nothing about saving. A string is not a file: this goes through
## `FileAccess`, which is what a dungeon file will actually go through, and it
## catches the encoding and trailing-byte problems a string comparison cannot.
func _round_trip_through_a_file() -> void:
	var b: CozyDungeonBlueprint = _ok(ROOM_A, ROOM_B)
	var path := "user://test_dungeon_blueprint.json"

	var w := FileAccess.open(path, FileAccess.WRITE)
	is_true("the file opens for writing", w != null)
	w.store_string(b.to_json())
	w.close()

	var r := FileAccess.open(path, FileAccess.READ)
	is_true("and reads back", r != null)
	var text := r.get_as_text()
	r.close()

	var again := CozyDungeonBlueprint.parse(text, path)
	eq("the file's contents are accepted", again["reason"], "")
	var a: CozyDungeonBlueprint = again["blueprint"]
	is_true("and parse", a != null)
	eq("the id survived the file", a.id, b.id)
	for i in b.outline_count():
		eq("outline %d survived the file" % i, a.outlines[i], b.outlines[i])
	eq("and it still derives two rooms", _rooms(_segments(a.layout())), 2)

	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


## The other half of the invariant, asserted directly rather than inferred:
## `JSON.stringify` writes a `PackedVector2Array` out as a STRING, and the field
## then reads back as a string and cannot be assigned to the array it came from.
## So every coordinate in the document must be a number, and the list a list.
func _json_native() -> void:
	var doc: Dictionary = _ok(ROOM_A, ROOM_B).to_dict()
	var reread: Variant = JSON.parse_string(JSON.stringify(doc))
	is_true("the document survives stringify as an object", reread is Dictionary)
	eq("every outline is still a list", _all_lists((reread as Dictionary)["outlines"]), true)
	eq("and every coordinate is still a number", _all_numbers((reread as Dictionary)["outlines"]), true)


## The case this contract exists for. DG-01's first half measured that the naive
## reading of two adjacent outlines MERGES the rooms into one 96 m2 space,
## silently. Here the outlines arrive through the document format, so a contract
## that dropped or reordered them would show up as the merge coming back.
func _resolves_to_rooms() -> void:
	var layout := _ok(ROOM_A, ROOM_B).layout()
	eq("seven walls for two rooms sharing an edge", layout.walls().size(), 7)
	eq("and TWO rooms, not the merged one", _rooms(_segments(layout)), 2)


# ---------------------------------------------------------------- refusing

## A build that reads a newer document as well as it can takes the fields it
## recognises and DROPS whatever the newer format added. The symptom is a dungeon
## quietly missing a room — the file loads, the assertion passes, the world is
## smaller than it should be.
func _newer_version_refused() -> void:
	var why := _reason({"id": "d", "version": 2, "outlines": [ROOM_A]})
	is_true("a v2 document is refused, not read", why != "")
	is_true("and the reason names the version it is", why.contains("newer"))
	eq("the refusal says nothing arrived", CozyDungeonBlueprint.parse(
		_json_version(2, ROOM_A))["blueprint"], null)


## A document that does not say what it is cannot be read safely. Defaulting the
## version would make every future bump a silent misread of old files.
func _no_version_refused() -> void:
	var why := _reason({"id": "d", "outlines": [ROOM_A]})
	is_true("no version is a refusal", why != "")
	is_true("and the reason says why", why.contains("version"))


## What the doc stores as an explicit connection is a MEASUREMENT, not an input:
## `CozyDungeonLayout` derives which outlines meet, and along which stretch, from
## the geometry alone. A stored copy is a second answer that drifts from the one
## the runtime derives.
func _links_refused() -> void:
	var why := _reason({"id": "d", "version": 1, "outlines": [ROOM_A, ROOM_B],
		"links": [{"a": 0, "b": 1, "kind": "door"}]})
	is_true("links is refused", why != "")
	is_true("and the reason names the field", why.contains("links"))
	is_true("and says it is derived, not authored", why.contains("derived"))


## Both need a vocabulary that does not exist. Accepting them now would be an
## eighth "declared capability with no consumer" — a field sitting in the files,
## unread, indistinguishable from one that works.
func _content_refused() -> void:
	for field in ["spawns", "content"]:
		var doc := {"id": "d", "version": 1, "outlines": [ROOM_A]}
		doc[field] = [{"room_hint": "entrance"}]
		var why := _reason(doc)
		is_true("%s is refused" % field, why != "")
		is_true("and the reason names it", why.contains(field))


func _unknown_key_refused() -> void:
	var why := _reason({"id": "d", "version": 1, "outlines": [ROOM_A], "monsters": []})
	is_true("an undefined field is refused", why != "")
	is_true("and named", why.contains("monsters"))


## Refused in the BUILDING PIPELINE'S own words, because the guard is called
## rather than restated — a self-intersecting outline produces walls that cross,
## and room detection is handed a non-planar graph. It fails the way the
## T-junction bug failed: quietly, by a room that does not appear.
func _crossing_refused() -> void:
	var bowtie := [0, 0, 4, 4, 4, 0, 0, 4]
	var why := _reason({"id": "d", "version": 1, "outlines": [bowtie]})
	is_true("a bowtie outline is refused", why != "")
	is_true("by the outline guard, in its words", why.contains("crosses itself"))


func _malformed_refused() -> void:
	# The control first: the fixture these cases are built around IS accepted, so
	# a refusal below is about the malformation and not about the document
	# around it.
	eq("the well-formed fixture is accepted", _reason(_doc([ROOM_A])), "")

	var cases := {
		"an odd count of coordinates": [0, 0, 8, 0, 8],
		"a coordinate that is not a number": [0, 0, 8, "north", 8, 6],
		"an outline that is not a list": "0,0 8,0",
		"an outline with nothing in it": [],
		"an outline of one point": [3, 4],
		"a self-intersecting outline": [0, 0, 4, 4, 4, 0, 0, 4],
	}
	for label in cases:
		is_true("%s is refused" % label, _reason(_doc([cases[label]])) != "")
		# One bad outline refuses the whole document — a blueprint that built the
		# rooms it could and skipped the rest would be a dungeon with a hole in
		# it and no complaint.
		is_true("and it refuses the document it is in",
			_reason(_doc([cases[label], ROOM_A, ROOM_B])) != "")

	is_true("an empty outline list is refused",
		_reason(_doc([])) != "")
	is_true("a document with no outlines key is refused",
		_reason({"id": "d", "version": 1}) != "")
	is_true("a document with no id is refused",
		_reason({"version": 1, "outlines": [ROOM_A]}) != "")
	is_true("and an id of spaces is no id either",
		_reason({"id": "   ", "version": 1, "outlines": [ROOM_A]}) != "")


## Every refusal above returns a reason. This asserts the other end of it: the
## reason comes with NO blueprint, so a caller that skips reading it does not get
## a half-built dungeon to use by accident.
func _refusal_yields_nothing() -> void:
	var bad := [
		"not json at all",
		"[1, 2, 3]",
		'{"id": "d", "version": 99, "outlines": [[0,0, 8,0, 8,6]]}',
		'{"id": "d", "version": 1, "outlines": [[0,0, 8,0]]}',
		'{"id": "d", "version": 1, "outlines": [[0,0, 8,0, 8,6]], "links": []}',
	]
	for text in bad:
		var r := CozyDungeonBlueprint.parse(text)
		eq("no blueprint for %s" % text.substr(0, 24), r["blueprint"], null)
		is_true("and a reason for %s" % text.substr(0, 24), r["reason"] != "")


# ---------------------------------------------------------------- helpers

func _json(a: Array, b: Array) -> String:
	return JSON.stringify({"id": "forest_dungeon_01", "version": 1, "outlines": [a, b]})


func _json_version(v: int, outline: Array) -> String:
	return JSON.stringify({"id": "d", "version": v, "outlines": [outline]})


## A minimal acceptable document around the outlines under test, so a case never
## fails for a reason it was not asking about.
func _doc(outlines: Array) -> Dictionary:
	return {"id": "d", "version": 1, "outlines": outlines}


func _reason(d: Dictionary) -> String:
	return CozyDungeonBlueprint.reject_reason(d)


func _ok(a: Array, b: Array) -> CozyDungeonBlueprint:
	var r := CozyDungeonBlueprint.parse(_json(a, b))
	if r["blueprint"] == null:
		# The accepted-document cases must fail loudly if the format stops
		# accepting them, rather than dereferencing null and looking like a crash.
		eq("a document this test expects to be accepted: %s" % r["reason"], false, true)
		return CozyDungeonBlueprint.new()
	return r["blueprint"]


func _all_lists(listed: Variant) -> bool:
	if not (listed is Array):
		return false
	for o in listed:
		if not (o is Array):
			return false
	return true


func _all_numbers(listed: Variant) -> bool:
	for o in listed:
		for v in o:
			if typeof(v) != TYPE_INT and typeof(v) != TYPE_FLOAT:
				return false
	return true


func _segments(layout: CozyDungeonLayout) -> Array:
	var out: Array = []
	for w in layout.walls():
		out.append([w["a"], w["b"]])
	return out


func _rooms(segments: Array) -> int:
	return CozyRoomDetector.new().detect(segments).size()
