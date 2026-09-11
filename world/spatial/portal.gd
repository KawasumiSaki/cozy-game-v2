class_name CozyPortal
extends RefCounted
## Portal — a connector between two spaces (V2 doc #8.5).
##
## The doc deliberately unifies Door, Stair, Elevator, Tunnel and Cave Entrance
## under a single abstraction: *something that joins space A to space B*.
##
## That abstraction is what keeps NPC routing generic. The doc's worked example
## (#112) is explicit that this must NOT exist:
##
##     if npc_is_textile_worker:
##         go_upstairs()
##
## Instead an NPC that wants floor 1 finds a Portal whose two sides sit on
## different floors, walks to side A, crosses, and continues from side B.
## Moving the machine to the basement later needs no new code (#113).

enum Kind { DOOR, STAIR, ELEVATOR, TUNNEL }

const KIND_NAMES := {
	Kind.DOOR: "door",
	Kind.STAIR: "stair",
	Kind.ELEVATOR: "elevator",
	Kind.TUNNEL: "tunnel",
}

var id := ""
var kind: Kind = Kind.DOOR

## Both sides of the connection, in world space.
var a_position := Vector3.ZERO
var b_position := Vector3.ZERO

## Filled in by CozyFloorSystem.resolve_portals() once rooms are known.
## This is what implements doc #29 — "a Door knows room_a and room_b".
var a_floor := 0
var b_floor := 0
var a_room := ""
var b_room := ""


func _init(p_id := "", p_kind: Kind = Kind.DOOR,
		p_a := Vector3.ZERO, p_b := Vector3.ZERO) -> void:
	id = p_id
	kind = p_kind
	a_position = p_a
	b_position = p_b


## Does this portal move you between floors? Doors usually do not; stairs do.
func crosses_floor() -> bool:
	return a_floor != b_floor


## Given one side's position, return the far side — the traversal primitive.
func other_side(from: Vector3) -> Vector3:
	return b_position if from.distance_squared_to(a_position) \
		< from.distance_squared_to(b_position) else a_position


func kind_name() -> String:
	return KIND_NAMES.get(kind, "portal")


func describe() -> String:
	return "%s [%s] %s(f%d/%s) <-> %s(f%d/%s)" % [
		id, kind_name(),
		_str_pos(a_position), a_floor, (a_room if a_room != "" else "outdoors"),
		_str_pos(b_position), b_floor, (b_room if b_room != "" else "outdoors"),
	]


static func _str_pos(v: Vector3) -> String:
	return "(%.1f,%.1f,%.1f)" % [v.x, v.y, v.z]
