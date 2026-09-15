class_name CozyEntityRegistry
extends RefCounted
## The world's entity index (Core Architecture V1.0, item 1).
##
## AN ENTITY IS an id plus the State object that owns it. What this adds is the
## one question no single system could answer before: "give me the entity with
## id X". Walls, slabs, stairs, roofs, furniture and residents each kept their
## own list under their own id prefix, so resolving an id meant already knowing
## which system minted it.
##
## ---------------------------------------------------------------------------
## THIS IS NOT AN ECS, and the four things that would make it one are absent on
## purpose: no component base class, no component arrays, no per-frame system
## traversal, and nothing here is read at frame rate. Entity counts in this
## project are in the hundreds, so traversal has never been the bottleneck; the
## hard question has always been "what has to be told when this changes", and
## that is answered by the dirty graph (doc #32), not here.
##
## ---------------------------------------------------------------------------
## KINDS ARE PULLED, NEVER COPIES. A kind is registered with a provider Callable
## and every query calls it. A list collected once would be the bug this project
## has already paid for twice: the fade list that held a freed roof and missed
## the live one (INVARIANTS, bug 19), and `_sync_views` matching by id against
## state objects that had been replaced (bug 18). "Collected once" is the shape
## that goes stale; "asked now" cannot.
##
## ---------------------------------------------------------------------------
## THE OWNER ENCODES ITS OWN STATE. The registry indexes entities; it does not
## know what a wall is, so it never builds a wall's payload itself. A kind is
## registered with an optional encoder, and a kind WITHOUT one is a kind that is
## never saved. That is how roofs are excluded — they are derived from the rooms
## (doc #63 / #68), so storing one would let the file disagree with the
## generator. The exclusion is part of the registration rather than a filter at
## the save site, so a new derived kind cannot be saved by forgetting to skip it.

## The kinds this project has today. Constants rather than free strings, so a
## typo is a failure rather than a kind that silently never matches.
const WALL := "wall"
const SLAB := "slab"
const STAIR := "stair"
const ROOF := "roof"
const OBJECT := "object"
const NPC := "npc"

## Something lying on the ground, waiting to be walked over (2026-09-15).
##
## A kind of its own rather than a `world_object`, because the two are different
## questions: an object is placed, blocks movement and advertises interaction
## points, and a drop is none of those. It is loaded back through `_apply_world`
## like any other persisted kind.
const DROP := "drop"

## The PLAYER's own ledger (Willow 2026-09-15: two accounts, the village's and
## the player's). One state object, like a resident's — the difference between
## them is WHO the goods belong to, not what shape a ledger is.
const PLAYER := "player"

## kind -> {"provider": Callable() -> Array, "encode": Callable(state) -> Dictionary}
##
## A Dictionary, so registration order is the iteration order: a save lists walls
## before slabs before stairs, and reading a save back puts them back in that
## order.
var _kinds: Dictionary = {}


# ---------------------------------------------------------------- registration

## Register one kind.
##
## `provider()` returns the OWNING system's live array of state objects. It is
## called on every query, never read once — see the header.
##
## `encode(state)` turns one state into its saved payload, or is omitted for a
## kind that is never saved. The id stays INSIDE the payload, where every
## serializer in this project already writes it, so the file never carries the
## same id twice and cannot disagree with itself.
func register_kind(kind: String, provider: Callable, encode := Callable()) -> void:
	_kinds[kind] = {"provider": provider, "encode": encode}


func unregister_kind(kind: String) -> bool:
	return _kinds.erase(kind)


func clear() -> void:
	_kinds.clear()


func kinds() -> PackedStringArray:
	var out := PackedStringArray()
	for k in _kinds:
		out.append(String(k))
	return out


## Is this kind written to a save? A kind with no encoder is derived state.
func is_persisted(kind: String) -> bool:
	return _kinds.has(kind) and (_kinds[kind]["encode"] as Callable).is_valid()


# ---------------------------------------------------------------- queries

## Every entity in the world, as `{id, kind, state}`.
##
## A freed node can still be sitting in a caller's array — `main.gd` guards the
## same case in `_check_vfx`. Reading `.id` off one is an engine error, and an
## index that throws on a stale entry is worse than one that skips it.
func entities() -> Array:
	var out: Array = []
	for kind in _kinds:
		for s in _states_of(kind):
			if not is_instance_valid(s):
				continue
			out.append({"id": String(s.id), "kind": String(kind), "state": s})
	return out


## The entities a save stores — everything except the derived kinds.
func persisted_entities() -> Array:
	var out: Array = []
	for e in entities():
		if is_persisted(String(e["kind"])):
			out.append(e)
	return out


## One entity's saved payload: `{"kind": ..., "state": {...}}`.
##
## Empty when the kind is derived, or when its encoder gives back something that
## is not a Dictionary — a payload that cannot be written must not be written
## half-way.
func encode_entity(e: Dictionary) -> Dictionary:
	var kind := String(e["kind"])
	if not is_persisted(kind):
		return {}
	var payload: Variant = (_kinds[kind]["encode"] as Callable).call(e["state"])
	if typeof(payload) != TYPE_DICTIONARY:
		return {}
	return {"kind": kind, "state": payload}


## The states of one kind, freshly pulled. A filtered COPY, so a caller can
## iterate without re-deriving the freed-node guard every time; the pull is what
## keeps it current, not the copy.
func all_of(kind: String) -> Array:
	var out: Array = []
	for s in _states_of(kind):
		if is_instance_valid(s):
			out.append(s)
	return out


## The single resolution entry point: the state behind an id, or null.
##
## `kind` narrows the search and is the escape hatch for an ambiguous id. With no
## kind, an id that more than one kind offers is REFUSED rather than resolved to
## whichever kind registered first — a lookup whose answer depends on
## registration order is a lookup that means several different things, which is
## the shape this project has already been burned by (INVARIANTS, bug 20: a count
## several different wrong worlds produce).
##
## The refusal is silent ON PURPOSE, and the reporting is not: `duplicate_ids()`
## is the detector and the self-check asserts it is empty on every run. A
## `push_error` here would fire inside the check that deliberately provokes it,
## and a log line that means "the probe worked" must not look like the log line
## that means the build is broken. Detection is an assertion; refusal is the
## safety behaviour, so an ambiguous id never resolves to the wrong entity.
func state_of(id: String, kind := "") -> Object:
	var found: Object = null
	var hits := 0
	for e in entities():
		if String(e["id"]) != id:
			continue
		if kind != "" and String(e["kind"]) != kind:
			continue
		hits += 1
		if hits == 1:
			found = e["state"]
	return null if hits > 1 else found


func kind_of(id: String) -> String:
	var e := _entry_of(id)
	return String(e.get("kind", "")) if not e.is_empty() else ""


func ids() -> PackedStringArray:
	var out := PackedStringArray()
	for e in entities():
		out.append(String(e["id"]))
	return out


func has_id(id: String) -> bool:
	return not _entry_of(id).is_empty()


## Ids offered by more than one entity. Empty in a healthy world, and the only
## way to notice when it is not: each system only ever saw its own list, so two
## systems minting the same id is a defect none of them could detect alone.
func duplicate_ids() -> PackedStringArray:
	var seen := {}
	var dupes := PackedStringArray()
	for e in entities():
		var id := String(e["id"])
		if seen.has(id):
			if not dupes.has(id):
				dupes.append(id)
		else:
			seen[id] = true
	return dupes


func count() -> int:
	return entities().size()


## One line for a log: how much of each kind the world holds.
func describe() -> String:
	var parts: Array = []
	for kind in _kinds:
		var n := all_of(kind).size()
		if n > 0:
			parts.append("%d %s" % [n, kind])
	if parts.is_empty():
		return "no entities"
	return "%d entity(ies): %s" % [count(), ", ".join(parts)]


# ---------------------------------------------------------------- reading a file

## The payloads of one kind out of a saved world.
##
## Static because a loader reads a FILE, before there is a world to index — and
## the file's shape is this registry's vocabulary, so it belongs here rather than
## being re-derived by every reader.
static func payloads(doc: Dictionary, kind: String) -> Array:
	var out: Array = []
	for e in doc.get("entities", []):
		if typeof(e) != TYPE_DICTIONARY:
			continue
		if String((e as Dictionary).get("kind", "")) != kind:
			continue
		out.append((e as Dictionary).get("state", {}))
	return out


# ---------------------------------------------------------------- internals

func _states_of(kind: String) -> Array:
	if not _kinds.has(kind):
		return []
	var provider: Callable = _kinds[kind]["provider"]
	if not provider.is_valid():
		return []
	var got: Variant = provider.call()
	return got if typeof(got) == TYPE_ARRAY else []


func _entry_of(id: String) -> Dictionary:
	for e in entities():
		if String(e["id"]) == id:
			return e
	return {}
