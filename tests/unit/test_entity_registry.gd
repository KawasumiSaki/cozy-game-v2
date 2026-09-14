extends "res://tests/unit/unit_test.gd"
## The entity registry: ids, kinds, and the two things it must refuse.
##
## Pure logic, so these are unit tests rather than another stage on `Main`. The
## registry is duck-typed on `.id` — that is the entire contract a kind has to
## satisfy — so a test of it should not need a wall, and these use a stand-in.
## The real state objects are covered by the `entity_registry` stage, which runs
## against the live world.


## A stand-in for a state object: an id, and whatever its owner calls a payload.
class Fake:
	var id := ""
	var payload := {}

	func _init(p_id: String, p_payload := {}) -> void:
		id = p_id
		payload = p_payload


## Something with a MEMBER list, so a test can prove the provider reads the
## member at call time rather than capturing an Array that was there at
## registration time.
class Holder:
	var items: Array = []


func _init() -> void:
	suite("entity registry")
	case("an entity is an id, a kind and a state", _lists_entities)
	case("a lookup returns the state itself", _resolves)
	case("an unknown id is null, not a default", _unknown_id)
	case("kinds are pulled, never collected once", _pulled)
	case("a replaced list is still seen", _replaced_list)
	case("a kind with no encoder is never saved", _derived_kinds)
	case("one id offered by two kinds is caught", _duplicates)
	case("an ambiguous lookup is refused; a kind breaks the tie", _ambiguous)
	case("a saved world is read by kind", _payloads)


func _lists_entities() -> void:
	var reg := _registry()
	var all := reg.entities()
	eq("every state is listed", all.size(), 3)
	eq("in registration order, walls first",
		str(reg.ids()), str(PackedStringArray(["w1", "w2", "s1"])))
	eq("each carries its kind", String((all[0] as Dictionary).get("kind", "")), "wall")
	eq("and its state", (all[2] as Dictionary).get("state"), _slabs[0])

	eq("one kind can be asked for alone", reg.all_of("wall").size(), 2)
	eq("and an unknown kind is empty, not an error", reg.all_of("nothing").size(), 0)


## The claim is not "a lookup returns something" — it is "it returns THIS".
func _resolves() -> void:
	var reg := _registry()
	is_true("the wall comes back", reg.state_of("w1") == _walls[0])
	is_true("the slab comes back", reg.state_of("s1") == _slabs[0])
	is_true("an id is known", reg.has_id("w2"))
	eq("and its kind is reported", reg.kind_of("w2"), "wall")


func _unknown_id() -> void:
	var reg := _registry()
	is_true("an unknown id resolves to null", reg.state_of("w9") == null)
	is_false("and is not reported as present", reg.has_id("w9"))
	eq("with no kind", reg.kind_of("w9"), "")


## Why a kind is registered with a Callable instead of a list.
##
## A list collected once is the shape this project has already paid for twice:
## the fade list that held a freed roof and missed the live one, and `_sync_views`
## matching by id against state objects that had been replaced. Both were green.
func _pulled() -> void:
	var reg := CozyEntityRegistry.new()
	var live: Array = []
	reg.register_kind("wall", func() -> Array: return live)
	eq("an empty provider lists nothing", reg.count(), 0)

	live.append(Fake.new("w1"))
	eq("a state added AFTER registration is seen", reg.count(), 1)
	live.append(Fake.new("w2"))
	eq("and so is the next one", reg.count(), 2)


## The stronger half: a provider must keep working when the owner REPLACES its
## list rather than appending to it. `func() -> Array: return objects` reads the
## member on every call, so it does; a captured Array would not.
func _replaced_list() -> void:
	var holder := Holder.new()
	holder.items = [Fake.new("a1")]
	var reg := CozyEntityRegistry.new()
	reg.register_kind("object", func() -> Array: return holder.items)
	eq("the first list is read", reg.count(), 1)

	holder.items = [Fake.new("b1"), Fake.new("b2")]
	eq("a REPLACED list is read too", reg.count(), 2)
	eq("and it is the new one", str(reg.ids()), str(PackedStringArray(["b1", "b2"])))


## Roofs, in the real world. A kind registered without an encoder is derived
## state: it can be addressed by id and is never written to a file.
func _derived_kinds() -> void:
	var reg := _registry()
	reg.register_kind("roof", func() -> Array: return [Fake.new("r1")])

	is_false("a kind with no encoder is not persisted", reg.is_persisted("roof"))
	is_true("a kind with one is", reg.is_persisted("wall"))
	eq("it is still an entity", reg.count(), 4)

	var persisted := reg.persisted_entities()
	eq("but it is not in the list a save writes", persisted.size(), 3)
	for e in persisted:
		ne("no roof is in the saved list", String((e as Dictionary).get("kind", "")), "roof")

	eq("and encoding one gives back nothing", str(reg.encode_entity({"kind": "roof",
		"state": Fake.new("r1")})), str({}))

	# The saved shape is the kind plus the owner's own payload, and the id stays
	# inside the payload — so a file never carries the same id twice.
	var wire := reg.encode_entity({"kind": "wall", "state": _walls[0]})
	eq("an entity on the wire names its kind", String(wire.get("kind", "")), "wall")
	eq("and its state is the owner's payload",
		String((wire.get("state", {}) as Dictionary).get("id", "")), "w1")


## No single system could notice this: each one only ever saw its own list.
func _duplicates() -> void:
	var reg := _registry()
	eq("a healthy registry reports none", str(reg.duplicate_ids()), str(PackedStringArray()))

	reg.register_kind("probe", func() -> Array: return [_walls[0]])
	eq("one id from two kinds is reported",
		str(reg.duplicate_ids()), str(PackedStringArray(["w1"])))
	eq("and only once, however many times it is offered",
		reg.duplicate_ids().size(), 1)


func _ambiguous() -> void:
	var reg := _registry()
	reg.register_kind("probe", func() -> Array: return [_walls[0]])

	is_true("an unqualified lookup of a duplicated id is REFUSED",
		reg.state_of("w1") == null)
	is_true("a kind breaks the tie", reg.state_of("w1", "wall") == _walls[0])
	is_true("and so does the other kind", reg.state_of("w1", "probe") == _walls[0])
	is_true("an id only one kind has is unaffected",
		reg.state_of("s1") == _slabs[0])


## The file's shape is this vocabulary, so reading it back lives here rather than
## being re-derived by every reader.
func _payloads() -> void:
	var doc := {"entities": [
		{"kind": "wall", "state": {"id": "w1"}},
		{"kind": "object", "state": {"id": "o1"}},
		{"kind": "wall", "state": {"id": "w2"}},
	]}
	eq("one kind comes out alone", CozyEntityRegistry.payloads(doc, "wall").size(), 2)
	eq("in file order", String((CozyEntityRegistry.payloads(doc, "wall")[0]
		as Dictionary).get("id", "")), "w1")
	eq("an absent kind is empty", CozyEntityRegistry.payloads(doc, "npc").size(), 0)
	eq("and so is a document with no entities",
		CozyEntityRegistry.payloads({}, "wall").size(), 0)


# ---------------------------------------------------------------- fixtures

var _walls: Array = []
var _slabs: Array = []


## Two kinds, three entities: enough for every case below to be about one thing.
func _registry() -> CozyEntityRegistry:
	_walls = [Fake.new("w1", {"id": "w1"}), Fake.new("w2", {"id": "w2"})]
	_slabs = [Fake.new("s1", {"id": "s1"})]
	var reg := CozyEntityRegistry.new()
	reg.register_kind("wall", func() -> Array: return _walls,
		func(s) -> Dictionary: return s.payload)
	reg.register_kind("slab", func() -> Array: return _slabs,
		func(s) -> Dictionary: return s.payload)
	return reg
