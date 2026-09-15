class_name CozyWorkDefs
extends RefCounted
## The kinds of work there are, and the order a resident tries them in.
##
## Willow, 2026-09-15: "没有工种这个概念，我们参考 rimworld，所有人都可以干所有事，
## 除非有那种特殊特质禁止了做什么事情."
##
## So the unit of "who does what" is a WORK TYPE, not a trade. A trade
## (`CozyJobDefs`) says where a resident STARTS; this table says what exists and
## what comes after. Every resident has the whole list — the only thing that takes
## an entry away is a rule about the resident, and the one that exists today is
## doc §10's skill aversion (`CozyNpcState.is_assignable()`).
##
## WHY AN ORDER AT ALL, with one resident and no UI: it is the difference between
## a resident who stands still and one who does something else. Every kind of work
## has moments when it has nothing to offer — crops that were just reaped and are
## a day from ripe, a tree already felled — and until this list existed the
## resident waited out those moments one second at a time. `want_point_types()`
## walks the list and takes the first kind that HAS somewhere to go.
##
## It is also the shape the player-facing priority table needs (RimWorld's
## per-colonist work list). That UI is not built and is not this table's job; this
## is the order it will edit.

## Most wanted first. Food before materials, materials before crafting, and
## hauling last — a colony eats, then builds, then tidies. The last entry is what
## a resident falls back to when their trade has nothing, which is the "先种田，
## 没有就砍树，再没有就搬运" chain the work-priority research described.
##
## Every entry must be a point type some recipe is worked at, or a point something
## offers; `test_resource_chain` holds both directions.
const ORDER: Array[String] = [
	"harvest",     ## reap what is ripe
	"plant",       ## sow what is bare (a point the GROUND offers)
	"chop",        ## wood
	"mine",        ## stone
	"work",        ## a workstation: baking, research, building
	"store",       ## hauling — the universal fallback
]


static func work_order() -> Array[String]:
	return ORDER.duplicate()


static func exists(t: String) -> bool:
	return ORDER.has(t)


## A trade's full list: its own specialty first, then everything else in this
## order. Lives here rather than in `CozyJobDefs` so the ordering has one home and
## a trade row cannot quietly disagree with it.
static func ranked_for(first: String) -> Array[String]:
	var out: Array[String] = [first]
	for t in ORDER:
		if t != first:
			out.append(t)
	return out
