class_name CozyDirtyRegion
extends RefCounted
## What an edit actually touched (V2.1 doc #33).
##
##     DirtyRegion
##     ├── world_bounds
##     ├── chunk_ids
##     ├── affected_walls
##     ├── affected_rooms
##     ├── affected_objects
##     └── nav_dirty
##
## The doc's rule is blunt — "局部修改，局部重建" — and Appendix C forbids
## "letting one local change trigger a world rebuild". This object is how an
## edit says what it disturbed, so downstream stages can rebuild only that.
##
## Floors are the coarse unit here because that is the granularity room
## detection actually needs: rooms are derived from the wall graph of ONE floor,
## so a wall on floor 0 cannot change the rooms on floor 1.

var walls: Dictionary = {}     ## wall id -> true
var floors: Dictionary = {}    ## floor id -> true
var chunks: Dictionary = {}    ## terrain chunk coord (Vector2i) -> true


func add_wall(id: String, floor_id: int) -> void:
	walls[id] = true
	floors[floor_id] = true


func add_floor(floor_id: int) -> void:
	floors[floor_id] = true


func add_chunk(coord: Vector2i) -> void:
	chunks[coord] = true


func merge(other: CozyDirtyRegion) -> void:
	for k in other.walls:
		walls[k] = true
	for k in other.floors:
		floors[k] = true
	for k in other.chunks:
		chunks[k] = true


func is_empty() -> bool:
	return walls.is_empty() and floors.is_empty() and chunks.is_empty()


## Sorted, so behaviour is deterministic and logs are comparable between runs.
func floor_list() -> Array[int]:
	var out: Array[int] = []
	for f in floors:
		out.append(f)
	out.sort()
	return out


func wall_list() -> Array[String]:
	var out: Array[String] = []
	for w in walls:
		out.append(w)
	out.sort()
	return out


func describe() -> String:
	return "dirty(walls=%d floors=%s chunks=%d)" % [
		walls.size(), str(floor_list()), chunks.size()]
