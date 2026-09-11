class_name CozyInteractionPoint
extends RefCounted
## InteractionPoint — the thing that decouples NPCs from furniture (V2 doc #87 / #94).
##
## The doc is emphatic that an NPC must never know what a research table looks
## like. It only needs to know "there is a WorkPoint of type research here".
## So the table advertises a point, and the NPC's job is to find one — not to
## have special code for tables.
##
## That is what makes moving the machine to the basement a no-op in code (#113).

var type := "work"          ## work / sit / sleep / store
var skill := ""             ## e.g. "research"; empty means anyone may use it
var world_position := Vector3.ZERO
var duration := 4.0         ## Seconds of work once the agent arrives.
var capacity := 1
var occupied_by: Node = null


func _init(p_type := "work", p_world := Vector3.ZERO,
		p_skill := "", p_duration := 4.0) -> void:
	type = p_type
	world_position = p_world
	skill = p_skill
	duration = p_duration


func is_free() -> bool:
	return occupied_by == null


func occupy(agent: Node) -> void:
	occupied_by = agent


func release() -> void:
	occupied_by = null


func describe() -> String:
	return "%s@(%.1f,%.1f,%.1f)%s" % [
		type, world_position.x, world_position.y, world_position.z,
		(" skill=" + skill) if skill != "" else ""]
