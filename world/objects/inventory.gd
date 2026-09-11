class_name CozyInventory
extends RefCounted
## A plain resource store (V2.1 doc #35).
##
##     "不要为建筑材料建立一套孤立库存系统."
##
## The doc's point is that construction materials are not a special subsystem:
## the same wood a wall costs is the wood a chest holds, an NPC carries, and a
## recipe consumes. One store, many callers. Making a separate "building
## materials" pool would be the mistake the doc names.
##
## Amounts are floats so fractional yields (a tree giving 3.5 wood) work without
## a second unit; costs are whole numbers (doc #36).

var items: Dictionary = {}   ## resource id -> amount


func add(id: String, n: float) -> void:
	items[id] = count(id) + n


func count(id: String) -> float:
	return float(items.get(id, 0.0))


func can_afford(costs: Dictionary) -> bool:
	for res in costs:
		if count(res) < float(costs[res]):
			return false
	return true


## All-or-nothing: a half-paid-for wall is worse than a refused one.
func spend(costs: Dictionary) -> bool:
	if not can_afford(costs):
		return false
	for res in costs:
		items[res] = count(res) - float(costs[res])
	return true


func refund(costs: Dictionary) -> void:
	for res in costs:
		add(res, float(costs[res]))


## What is missing, for the refusal message doc #72 requires.
func shortfall(costs: Dictionary) -> Dictionary:
	var out := {}
	for res in costs:
		var missing := float(costs[res]) - count(res)
		if missing > 0.0:
			out[res] = missing
	return out


func total() -> float:
	var t := 0.0
	for k in items:
		t += float(items[k])
	return t


func describe() -> String:
	var keys: Array = items.keys()
	keys.sort()
	var parts: Array[String] = []
	for k in keys:
		parts.append("%s x%d" % [k, int(items[k])])
	return ", ".join(parts) if not parts.is_empty() else "empty"
