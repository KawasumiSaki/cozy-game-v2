class_name CozyRoomGraph
extends RefCounted
## Room Graph — macro routing between spaces (V2 doc #8.4 / #41).
##
## The doc splits navigation in two, and this is the upper half:
##
##     Room Graph  ->  macro route   ("go from Storage to the Textile Room")
##     Navigation  ->  local route   ("now walk the last few metres")
##
## Why it has to exist (#9.2): without it an NPC knows a target coordinate but
## has no idea how to get there. The doc calls that failure mode out by name —
## "坐标存在，但空间拓扑不存在" (the coordinate exists, the spatial topology
## does not). A target on floor 1 is unreachable by coordinates alone.
##
## Nodes are rooms, plus a synthetic node for "outside". Edges are portals, so
## doors and staircases are the same kind of thing to a router.

const OUTDOORS := "__outdoors__"

## node id -> Array of { "to": node_id, "portal": CozyPortal }
var _adj: Dictionary = {}


func build(fs: CozyFloorSystem) -> void:
	_adj.clear()
	for r in fs.all_rooms():
		_adj[r.id] = []
	_adj[OUTDOORS] = []

	for p in fs.all_portals():
		var a := p.a_room if p.a_room != "" else OUTDOORS
		var b := p.b_room if p.b_room != "" else OUTDOORS
		if not _adj.has(a):
			_adj[a] = []
		if not _adj.has(b):
			_adj[b] = []
		_adj[a].append({"to": b, "portal": p})
		_adj[b].append({"to": a, "portal": p})


func node_count() -> int:
	return _adj.size()


func has_node(id: String) -> bool:
	return _adj.has(id)


## Shortest sequence of portals to traverse, or an empty array when there is no
## route (or the endpoints are the same).
func find_route(from_id: String, to_id: String) -> Array[CozyPortal]:
	var out: Array[CozyPortal] = []
	if from_id == to_id:
		return out
	if not _adj.has(from_id) or not _adj.has(to_id):
		return out

	# Breadth-first: fewest portals crossed, which is what a router should prefer.
	var prev := {from_id: {"node": "", "portal": null}}
	var queue: Array[String] = [from_id]
	var head := 0
	while head < queue.size():
		var cur := queue[head]
		head += 1
		if cur == to_id:
			break
		for e in _adj[cur]:
			var nxt: String = e["to"]
			if prev.has(nxt):
				continue
			prev[nxt] = {"node": cur, "portal": e["portal"]}
			queue.append(nxt)

	if not prev.has(to_id):
		return out   # Unreachable — a real answer, not an error.

	# Walk the predecessor chain backwards, then flip it.
	var walk := to_id
	while walk != from_id:
		var step: Dictionary = prev[walk]
		out.append(step["portal"])
		walk = step["node"]
	out.reverse()
	return out


## Convenience for the self-check: render a room id the way humans read it.
static func display_name(room_id: String) -> String:
	return "outdoors" if room_id == OUTDOORS else room_id


func route_description(route: Array[CozyPortal]) -> String:
	if route.is_empty():
		return "(no route)"
	var parts: Array[String] = []
	for p in route:
		parts.append("%s[%s]" % [p.id, p.kind_name()])
	return " -> ".join(parts)
