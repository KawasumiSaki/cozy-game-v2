# CozyVale V2 — Roadmap

> **The authoritative block plan lives in Obsidian**, not here:
> `Documents\Obsidian Vault\01-项目\xiansuwd\01-板块\00-目录.md`
>
> This file is the mirror kept next to the code: a status table, the locked
> decisions, and where to find everything else. Block detail, definitions of
> done and the development log are in Obsidian because they are read by a human
> between sessions, not by the engine.

---

## Where things are

| What | Where |
|---|---|
| Block index (start here) | Obsidian `01-板块/00-目录.md` |
| Block detail + DoD + assertions | Obsidian `01-板块/<ID>-<名称>.md` |
| Development log | Obsidian `02-开发日志/游戏开发日志.md` |
| Start / finish protocol | Obsidian `03-流程/更新方案.md` |
| Architecture master (only when changing architecture) | Obsidian `00-架构总纲/V2.2-技术架构总纲.md` |
| Art contract (camera, pixel density, import rules) | `docs/ART_PROFILE.md` |

---

## Status

✅ done ｜ 🚧 partial ｜ ⬜ not started

### Phase 0 — Technical spike
| ID | Block | Status |
|---|---|---|
| V2-00 | Skeleton + headless self-check | ✅ |
| V2-01 | Orthographic camera | ✅ (now locked — see ART-09) |
| V2-02 | Segment wall | ✅ |
| V2-03 | Character billboard | ✅ |
| V2-04 | Occlusion fade | ✅ mechanisms complete 2026-09-12 — stale fade list, slabs never registered, and the ray now marches past the nearest blocker. All 8 probe spots report 0 opaque at every yaw. Probe: `--cozy-probe-occlusion` |

### Phase 1 — Spatial core
| ID | Block | Status |
|---|---|---|
| V2-05 | Floor system | ✅ |
| V2-06 | Room detection (planar face traversal) | ✅ |
| V2-07 | Portal | ✅ |
| V2-08 | Room graph | ✅ |
| V2-09 | Local navigation (grid A*) | ✅ |

### Phase 2 — Terrain
| ID | Block | Status |
|---|---|---|
| V2-10 | Terrain data (cell / chunk / materials) | ✅ |
| V2-11 | Terrain editing (intent / rasterization) | ✅ |
| V2-12 | Road system | ⬜ |
| V2-13 | Foundation solver | 🚧 validator done, solver not |

### Phase 3 — Building
| ID | Block | Status |
|---|---|---|
| V2-14 | Building intent (outline → structure) | ✅ |
| V2-15 | Wall connection solver | ✅ |
| V2-16 | Openings (door / window) | ✅ |
| V2-17 | Roof generator | ✅ |

### Phase 4 — Object & interaction
| ID | Block | Status |
|---|---|---|
| V2-18 | WorldObject | ✅ basic |
| V2-19 | Free placement | ✅ basic |
| V2-20 | InteractionPoint | ✅ |
| V2-21 | Containers | 🚧 storage + item vocabulary (§35) + eating done; §45 production chain remains |

### Phase 5 — NPC
| ID | Block | Status |
|---|---|---|
| V2-22 | NPC data model | ✅ |
| V2-23 | Job / Task | ✅ simplified |
| V2-24 | Cross-floor work | ✅ |
| V2-25 | Schedule & needs | ✅ |

### Phase 6 — Persistence
| ID | Block | Status |
|---|---|---|
| V2-26 | Save / load | ✅ JSON facts to `user://`, F5/F9; no save slots yet. **2026-09-12: the file holds ONE entity list** (`entities: [{kind, state}]`, Core Architecture V1.0 ①) instead of one top-level key per system. `VERSION` is **2**, and the v1→v2 step is the first real migration in the chain. |

### UI — interface
| ID | Block | Status |
|---|---|---|
| UI-01 | Interface basics (HUD / build palette / right-click select) | ✅ |
| UI-02 | Resident panel (attributes / skills / needs / schedule) | ✅ |

### Phase 7-8 — Frozen
| ID | Block | Status |
|---|---|---|
| V2-27 | Gameplay | ⬜ frozen by doc §82 |
| V2-28 | World | ⬜ frozen |

### The house is a PREFAB, and nothing draws walls at runtime (2026-09-14)

Two switches in `main.gd`, and they say different things.

`HOUSE_ENABLED` — **true**. The house was never the auto-generated path:
`_build_house()` is a hand-authored list of eight walls, three slabs and a stair
and never goes through `CozyOutlineGenerator`. What is derived from it — rooms,
portals, room graph, roof — is derived the way everything else is, and none of
those has a known bug.

`BUILDING_ENABLED` — **false**. It gates the only two things that draw a wall at
runtime: the palette's `outline` and `wall` tools, and the live-rebuild stage.

**That second switch is the fix for debt 22, not a workaround around it.** A wall
added after the navigation was built, with a door cut into it, leaves the grid
routing through the door while the collider is solid there — and the resident
walks into the wall forever. The house's own door is cut at startup and has never
been the problem. See `docs/INVARIANTS.md`, "A wall added at runtime, with a door
in it, breaks the navigation".

Four states measured in a scratch copy; the last is what makes it causal:

```
prefab ON,  runtime building OFF   ->  122 OK / 0 FAIL / 0 ERROR
   + the pathing probe             ->  0 crossings, and the resident reaches
                                       the chest and works (wp=20/20, stuck=0.0)
HOUSE_ENABLED = false              ->   89 OK / 0 FAIL / 0 ERROR
BUILDING_ENABLED = true (teeth)    ->  2 crossings RETURN, same wall, same leg
```

The furniture is placed independently of the house and stays either way — the
chest is where §45 stores, the bed is where the schedule sleeps. The camera is
deliberately untouched: yaw 180 was measured for this house, and with it present
there is no reason to move it.

**There was a SECOND, independent cause, found on 2026-09-14 and fixed.** That
switch removes walls that appear after the navigation is built; it does not
touch a grid that routes the agent as a POINT. See the section below.

### Navigation clearance — the grid was routing a POINT (2026-09-14)

`CozyLocalNav` rasterised obstacle rects exactly: no inflation by the agent's
radius, no erosion of the room polygon. So it answered *can a point get from
here to there* while the thing that has to get there is a capsule
`CozyCharacter.CAPSULE_RADIUS` (0.3 m) in radius. Two defects were live:

- a gap wider than a cell and narrower than the agent was a route to the planner
  and a wall to the body;
- a room polygon runs through wall CENTRELINES (an 8 x 6 room measures 48.0 m2),
  so the grid's edge was the MIDDLE of every wall and half a wall-thickness of
  wall was walkable space the collider filled.

The fix is the **Minkowski sum** — the textbook answer to exactly this
(Lozano-Perez & Wesley, CACM 22(10), 1979): grow the obstacles by the agent's
radius and the agent becomes a point. `build()` takes `clearance` with **no
default**, so a call site cannot silently keep the bug, and `wall_reach` for the
half-wall the polygon stands in for.

```
stuck  before ->  3.0 x82, 1.4 x34, 1.2 x30, 1.0 x30, 0.8 x30, 0.6 x30
stuck  after  ->  0.0 x 4500                    every one of 4500 frames
resident      ->  GOING 1589 -> 1432, WORKING 2307 -> 2538
```

**It also DELETED a tight space, and nothing said so.** Inflating by 0.425
removed the house's 1.0 m stairwell landing entirely — the stair topped out on
floor no agent could stand on. The only thing that noticed was an assertion
written for it; the existing `npc plan ground->upstairs: crosses floor=true`
stayed green, because `find_path` came back empty and `_local()` fell back to a
straight line. `WELL_X0`/`WELL_X1` moved 1 m west (run unchanged — the stair is
still 50.2 degrees), the landing is 2.0 m, and that check went 33 -> 77
waypoints. See `docs/INVARIANTS.md`.

**Considered and rejected: `NavigationServer3D`.** `NavigationObstacle3D` only
does avoidance at runtime and never changes pathfinding, so it cannot replace a
rebake; `NavigationAgent3D` cannot follow an externally supplied path; every
Godot 4 navigation addon found is stale or archived; and a full rebake of this
house measured **48.5 ms** against the grid's 1.35 ms. The documented objection
to navmeshes still holds. The problem was never the grid.

### Resource line — chop, mine, harvest (opened 2026-09-14)

The loop being built now is farming, woodcutting and mining on open ground. The
vocabulary landed first, and it needed no new system: `_acquire_job()` already
scans every object for `free_points_of_type(want_point_type())` and a job's point
type is data, so three object rows, two jobs and three recipes feed a consumer
written for furniture that does not care what it is looking at.

`tree` / `rock` / `crop` offer `chop` / `mine` / `harvest`;
`woodcutter` / `miner` work at them; `chop_tree` yields wood, `mine_rock` stone,
`harvest_crop` wheat. Chopping is GATHERING — the doc fixes the skill list at ten,
so a new skill would be a change to the doc rather than a row here.

`farmer` used to sit at a `work` point, the same type a research table offers, so
the resident farmed at a desk. It names `harvest` now.

**`tests/unit/test_resource_chain.gd` asserts the vocabulary CLOSES** — every
point an object offers is wanted by something, and every point a job or an
activity wants is offered. That is the machine running the `grep` this project has
done by hand, and "a declared capability with no consumer" is the mistake it has
paid for seven times. Three trees, two rocks and three crops are placed in the
world, and `_check_resource_chain()` asserts their points exist and that the
outdoor grid says a body can stand at each one.

**A crop needs farmland, and the world farms the plot first** (2026-09-14).
`Grass -> Soil -> Farmland` has been a chain since V2-11 and refuses to skip a
step, and a crop could be dropped on virgin grass regardless. It is a row —
`"requires_ground": ["farmland"]` — and `CozyObjectDefs.ground_problem(id, ground)`
returns WHY it refuses rather than a bool, so the refusal can be asserted on. It
lives with the data because a rule that lives only in a mouse handler is not a
rule. `_place_object` consults it, silently, and the self-check reads the reason
back by making a placement that must be refused.

The world has to farm before it plants: `_prepare_crop_ground()` clears to soil
and tills to farmland, in that order, and runs beside `_prepare_starter_plot`
ending the same way — an edit after the renderer's `setup()` leaves the mesh stale
and the dirty marks pending, and `describe()` reports those marks.

Still to do: the placed trees are not the 165 instanced ones from
`vegetation_scatter`, and nothing sows — a farmer harvests and the player plants,
because no object offers a `plant` point and sowing has to be worked at the
ground, which is terrain rather than an object.

#### The want-list is ranked, and the trade leads it (2026-09-15)

`want_point_type()` returned one string, and a string cannot say "and if that is
not there, this". So a resident whose single preference had no free point stood
still and retried. It returns `want_point_types()` now — a ranked list, most
wanted first — and `_acquire_job()` takes the first kind that HAS a free point
before distance is consulted at all. Ranking first, distance second: taking the
nearest point of any acceptable kind would do a trade only when the trade happened
to be closer than the alternative, which is not a priority, it is a coin toss with
a tape measure. `_best_point(from, want)` is that rule as a pure function, so it
can be asserted without a world.

**And the bug it uncovered is not in the agent.** At 09:00 every trade wanted
`work` — because `CozySchedule.ACTIVITY_POINTS` mapped the activity `work` onto
the point TYPE `work`, which is what a research table offers. So the schedule
overrode every trade that is not `work`: a woodcutter sought a desk, and so did a
miner and a farmer, and `hauler` (whose trade point is `store`) never hauled
during working hours either. The three gathering trades existed in the tables and
could not do their own work in the game.

It hid for a day because every job in the table had `point_type: "work"` when that
bridge was written — the rule was only ever exercised by the one case it was
written for. `work` is a CATEGORY (doc #115: the schedule picks the kind of hour,
the Task System picks the place), and mapping a category onto a member of the set
it contains is the whole bug. The working block names no point type now, so the
trade decides; `tests/probe/work_priority_probe.gd` is the measurement that found
it, per trade and per hour, and it is worth re-running before touching either
side.

Teeth, all three seen red: reverting the schedule placeholder fails 10 unit checks
and 3 live ones and prints the bug's own signature (`woodcutter->[work]`);
reverting rank-before-distance fails exactly the case that names it; and making the
container leg REPLACE the trade instead of preceding it fails the fallback in both
places. What is still single-valued is the JOB (`point_type`) and the RECIPE
(`point_type`) — a job that names two kinds of work is a row change away, on the
day something offers the second kind.

### Dungeon lane (opened 2026-09-12)

Runs in parallel with the home lane and is deliberately **file-disjoint** from
it: a lane that edits another lane's files is not parallel, it is a conflict.
Nothing here touches the running game yet, and nothing here will until the home
loop closes.

| ID | Block | Status |
|---|---|---|
| DG-01 | Outline → wall union | ✅ **2026-09-14** — `dungeon/dungeon_layout.gd`. Wall union, blueprint contract, and `to_intents()` |
| DG-02 | Blueprint contract + validation | ✅ **2026-09-14** — `dungeon/dungeon_blueprint.gd`. 13 cases / 67 checks |
| DG-03 | Generator into the building pipeline | 🚧 generator done — `to_intents()` emits `CozyBuildingIntent[]` with its openings. Runtime hookup blocked on the home loop |

**`to_intents()` completes the chain and stops there** (2026-09-14). A blueprint
becomes intents the existing building pipeline already knows how to consume, and
13 cases / 40 checks cover it — including one that drives the intents through the
real `CozyBuildingState` and asserts the rooms still come out two rather than the
one the naive path merges them into.

**It also fixed a convention bug that would have shifted every door 0.75 m.**
`walls()` reported a doorway's NEAR EDGE (`mid - width * 0.5`); `CozyOpening.offset`
means its CENTRE, which is what `CozyOutlineGenerator` uses (`edge_len * 0.5`).
Nothing consumed the old field, so the convention was settled at the source
rather than repaired at the one call site with a `+ width * 0.5` no one would
question. The tooth: on a 6 m shared wall the offset must be 3.0, and the
near-edge reading gives 2.25.

**What the blueprint format refuses is most of what it does** (2026-09-14). The
design doc's §3.3 example also carries `links`, `spawns` and `content`, and
`CozyDungeonBlueprint` refuses all three BY NAME rather than parsing and ignoring
them — a field that is accepted and never read is indistinguishable, from the
author's side, from one that works. `links` is *never* stored (which outlines
meet, and where, is derived from their geometry); `spawns` and `content` have no
vocabulary to be validated against yet, and join the format together with the
system that reads them. A newer `version` is refused too, rather than read as
well as this build can: that would drop whatever the newer format added, and the
only symptom would be a dungeon quietly missing a room.
See `docs/INVARIANTS.md`.

**The measurement that shaped it** (`tests/probe/dungeon_layout_probe.gd`): two
outlines laid side by side each close their own loop, so the edge they share is
emitted TWICE, and the planar face traversal **merges the two rooms into one**
— silently. The naive reading ships a single-room dungeon that looks like it
worked. `CozyDungeonLayout` resolves the outlines against each other first.
See `docs/INVARIANTS.md`.

### ART — Art pipeline (doc Appendix E / K)
| ID | Block | Status |
|---|---|---|
| ART-09 | Fixed camera art profile | ✅ |
| ART-10 | Pixel asset library | ✅ |
| ART-11 | Terrain scatter | ✅ |
| ART-12 | Building material library | 🚧 assembly done, textures await assets |
| ART-13 | Pixel VFX library | ✅ campfire |
| ART-14 | NPC sprite pipeline | 🚧 game-side contract DONE 2026-09-12 — appearance data, animation selection, `AnimatedSprite3D`. Awaiting the Blender factory's sheets (step 2+). |
| ART-15 | NPC Skeleton2D | ⬜ superseded in part: the skeleton now lives in Blender, not Godot. See `ART_PROFILE.md` §9. |
| ART-16 | NPC animation controller | ⬜ |
| ART-17 | Pixel corrective animation | ⬜ |
| ART-18 | Art QA scene | ⬜ |
| ART-19 | AI asset ingest | ⬜ |

---

## Locked decisions

| Decision | Value | Source |
|---|---|---|
| Axis mapping | `doc(x,y,z) -> godot(x,z,y)` — height is real elevation, never a render layer | doc §1.1 |
| Render style | Real 3D + orthographic + 2D pixel billboards. **Characters are NOT 3D.** | doc §1.2, E.1.2 |
| Camera | **Locked**, 5 zoom steps, `L` = debug unlock only. The ANGLE is **yaw 180 / pitch 40 + narrow-FOV perspective as of 2026-09-12**. The yaw is a measurement, not a taste call: the door is cut into the `z = 0` wall, so the front of the house faces `-Z`, and the camera has to be on that side or the game opens on the back of the building. Zoom is remembered across runs; the angle deliberately is not. | doc E.1.1, `_check_opening_shot` |
| Resolution | **Native 1280×720**, `canvas_items` stretch. Pixel size comes from asset texel density, not a global downscale. | doc E.2 |
| Buildings | Remain real 3D geometry | doc E.1.3 |
| Everything else | Pixel sprite / billboard by default | doc E.1.4 |
| Art | **Real assets may enter the repo, but every one records source / author / a licence that permits redistribution (MIT / CC0 / CC BY) in `docs/CREDITS.md`. An unclear licence is refused.** Replaces doc §58.1's "placeholder only", which was doing two jobs — and only the first of them (keep the repo replaceable until the direction was set) is finished. | Willow 2026-09-15 |
| **Art pipeline** | **Hybrid Pixel Diorama**: buildings/furniture = 3D, **large trees = 2.5D shells**, grass/small = sprites, **NPC = Blender-rendered sprite sheets**. Blender is a factory, not a runtime dependency — `Characters are NOT 3D` (§1.2) still holds. See `ART_PROFILE.md` §9. | Willow 2026-09-12 |
| Language | Code and comments in English | Willow 2026-09-11 |
| UI tool grouping | By OPERATION, not by resulting object — a Door is a wall opening, not a tool | doc #24 |
| UI selection | Right-click probes what is under the cursor; the menu is built from that | Willow 2026-09-11 |
| HP / stamina | Shown **only in dungeons**, never on the home HUD | Willow 2026-09-11 |
| Passion | Scales EXPERIENCE (x1/x2/x4), never speed; aversion means not assignable | 愿景 §10 |
| Schedule | Resolves to an ACTIVITY, then to an interaction-point TYPE — never to an object | doc #115 |
| Traits | Change how FAST a value moves, not where it lands | this project |

---

## Known debt

Stated plainly so it is not rediscovered later.

1. **Terrain height is not displaced into the mesh.** The field carries it and
   DIG/FILL change it, but rendering is still flat. Needs a subdivided grid per
   chunk.
2. ~~Openings do not create Portals~~ — **fixed in V2-25**: a door portal is
   derived from the wall's DOOR opening, and the hand-written `door_south`
   fixture is gone. `no route` failures dropped from 2017 to 1.
3. **The asset library scans with DirAccess.** Works in the editor and in
   headless runs; an exported build would need the definitions declared as
   resources or bundled into a manifest first.
4. ~~Terrain has no biome concept~~ — solved by ART-11 (`CozyBiome`, derived).
5. ~~Outdoor navigation is a straight line~~ — **fixed**: the outdoors gets its
   own (coarser) grid with building footprints as obstacles. Verified by
   asserting no route point lands inside the house.
6. **UI is PC only.** No touch input exists (0 handlers). Willow: mobile later.
7. **Scatter does not follow terrain edits.** Digging does not re-scatter the
   plants on the patch. A full rebuild costs 138 ms, so hooking it to edits
   needs a chunk-scoped rebuild first; the trade-off is recorded in ART-11.
8. **Roofs go to rooms with nothing above them** (corrected from "top floor",
   which left one-storey outbuildings bare). A non-rectangular room still falls
   back to flat; the plan reports that rather than applying it silently.
9. **Outlines emit walls and one doorway only.** Windows and automatic stairs
   are not built, self-intersecting outlines are not guarded against, and a roof
   does not regenerate when the room polygon under it changes.
10. **Trait effects are partly live.** `mood_aura` and friends are stored but
   nothing consumes them yet — they need V2-25's needs system.
11. **The wall assembler does not tile roofs** — ART-12's idea applied to roofs
   is not built.
12. **Object ids exist, but nothing re-resolves a reference through one yet.**
   Furniture now has a stable id (`obj_%03d`) that survives a save, and
   `CozyEntityRegistry.state_of(id)` can find it. `CozyNpcAgent._target_object`
   is still a LIVE node reference, and a load frees every object and rebuilds
   them — so pressing F9 while a resident is working can hand `_finish_work()`
   a freed node. Nothing today does, which is why this is debt and not a bug.
   The fix is now direct: store the id, re-resolve through the registry.
13. ~~**The §45 live production chain has no assertion**~~ — **closed 2026-09-15,
    and the debt was misdiagnosed.** The note it replaces said the chain stayed
    untouched (`chest wheat 8 of 8, chest bread 0`). It was read at frame 900 —
    **the resident's first withdrawal is at frame 1372**. The chain ran the whole
    time, including under the configuration that note was written about.

        production chain ran live: chest wheat 8 -> 6, bread 0 -> 1, 4 job(s)  [OK]

    The assertion requires BOTH legs, and `bread > 0` alone is not evidence: the
    resident spawns with a larder of three loaves and `_haul` deposits before it
    withdraws, so a world whose chest starts EMPTY still ends with bread in it.
    The first version of the check passed on exactly that world. See
    `docs/INVARIANTS.md`, "Firing too EARLY reports 'broken'".

    **The stall and the chain turned out to be independent**: reverting the
    navigation clearance and the landing widening together reproduces the original
    stall exactly and the chain still completes four jobs.

---

## The equipment lane, end to end (2026-09-15)

Everything below was finished and UNREACHABLE until a monster existed: the stats
resolved, the generator rolled, the roller dropped, the container held and the
equipment wore — and nothing in the world produced an item. Six commits closed
the loop.

| Block | Where |
|---|---|
| Stats / modifiers (four passes, credited by source) | `data/stats.gd` |
| Item definitions | `data/items.gd` — 10 slot kinds, **13 slots** (3 charms, 2 rings) |
| Rolled instances | `items/item_instance.gd` · `items/item_generator.gd` |
| The bag | `items/item_container.gd` |
| What is worn, and the modifier list | `items/equipment.gd` |
| Loot tables and the roller | `data/loot.gd` · `items/loot_roller.gd` |
| **Appearance without stats** | `items/glamour.gd` |
| The source | `data/monsters.gd` · `character/monster.gd` |
| The player's ledger, bag and swing | `character/player_state.gd` · `main.gd` |
| Prices and the stall | `data/prices.gd` · `data/objects.gd` (`market_stall`) |
| **Things on the ground** | `world/objects/dropped_item.gd` · `main.gd` (`_lay_drops` / `_tick_pickups`) |
| **The two item panels** | `ui/gear_panel.gd` · `ui/item_slot.gd` · `ui/pack_panel.gd` |
| The pack, on screen | `ui/pack_panel.gd` |

**The fight, measured rather than described:**

```
a swing from 25 m missed=true; up close one swing landed 1 hit(s), hurt=true;
killed=true, fell 1 thing(s) on the ground spread over 3 spot(s), incl. 'Steel Sword',
bag stayed empty=true, purse unmoved=true; walked over -> bag 1 item(s) incl. 'Steel Sword',
copper 11, ground cleared=true, village untouched  [OK]
```

**A MONSTER DOES NOT FIGHT BACK AND DOES NOT MOVE**, and both are decisions
rather than omissions — an aggression row arrives with the driver that reads it.
**NOTHING DRAWS WORN EQUIPMENT** (Willow: the character visuals come after the
animation work), so a glamour's sprite half has no consumer yet and a renderer
will ask `CozyItemInstance.appearance_id()` and nothing else.

### The ground (2026-09-15)

A felled tree and a killed monster both leave a marker at the edge of whatever
dropped it, and a per-frame pass moves whatever the player is standing on into
their ledgers. Until this existed BOTH wrote the ledgers directly, so nothing was
ever on the ground and there was nowhere to put "it did not fit, so it stayed".

**THE PICKUP RADIUS IS BOUNDED BY THE SHORTEST REACH IN THE OBJECT TABLE**, which
is a crop's 0.8 m and not a tree's 1.3 — `_gather_from` refuses to work a node from
further than its reach and a drop lands at that node's edge, so the gap between a
player at the limit of their reach and their own loot IS the reach. The first
version used 1.0 because 1.3 was the number in front of it, which would have made
harvesting a crop a different mechanic from felling a tree. `test_dropped_item`
asserts the relation for EVERY gathered node. See `docs/INVARIANTS.md`.

**A DROP THAT DOES NOT FIT STAYS WHERE IT IS.** The bag has a capacity and the pack
does not, so exactly one kind of drop can be refused; it stays with a line saying
why, and it is still there when room is made. Taken-and-destroyed is the one
outcome a player experiences as a loss rather than as a convenience.

**A DROP IS NOT FURNITURE**: it does not join `objects`, so it blocks no movement
and advertises no interaction point — a dropped sword must not become a wall a
hauler walks around.

### The two item panels (2026-09-15)

`ui/gear_panel.gd` draws the thirteen PLACES a body has — `CozyItemDefs.SLOTS` order
and `capacity_of()` counts, so three charm cells and two ring cells — and
`ui/pack_panel.gd` gained a grid of the bag's own places. Both draw their cell with
`ui/item_slot.gd`, and both draw EMPTY CELLS: a hole is information, which is why a
grid rather than a list, and why `CozyEquipment.capacity`/`filled` exist separately
from a count of what happens to be worn.

**THE TWO PANELS ARE ONE COLUMN** in the top-right corner, because taking a sword
off in one and watching it land in the other is the whole of what "the panels should
work together" means. `MOUSE_FILTER_IGNORE` on the column, so a click in the space
around the panels still reaches the world.

**THREE VERBS, AND TWO OF THEM CAN LOSE AN ITEM.** `stow` (take off into the pack),
`wear` (put on from the pack) and `unwear` (throw on the ground). Both swaps are
methods on `CozyPlayerState`, which is the only thing that owns both containers:

- **`stow` asks the destination FIRST and moves second.** The other order — take it
  off, then find there is no room — ends with an item that is neither worn nor
  carried, and the state after that is CONSISTENT: nothing looks wrong, there is
  simply one fewer thing, which no assertion and no screen can see.
- **`wear` cannot lose anything**, and that is a property rather than luck: taking
  the item out of the pack frees exactly the place its displaced item needs.
  `equip()` returns what it pushed out so a caller can decide; the only decision
  left is "put it back".

**A DROPPED ITEM IS THROWN AHEAD**, `TOSS_DISTANCE` (1.4) against
`CozyDroppedItem.PICKUP_RADIUS` (0.6). A drop at the player's own position is inside
the pickup radius by definition, so "drop it" would be taken back on the next frame
and the button would look broken. Both the geometry and the relation between the two
constants are asserted.

**A CELL SHOWS `appearance_name()`** — what a glamoured item looks like — and the
tooltip carries `describe()`, which is what it IS. That method was written for this
and had no caller until the grid existed.

**NOTHING DRAWS WORN EQUIPMENT ON THE CHARACTER** (Willow: the visuals come after the
animation work).

**A CELL SHOWS AN ICON WHEN THERE IS ONE, AND ITS NAME ALWAYS** (2026-09-15). The icon
comes from `data/item_icons.gd`, which reads `appearance_id()` — so a glamoured item
wears the icon of what it LOOKS like, the same promise the name makes. **Six of
thirty-one drawable ids have a picture**, and `missing()` returns the other twenty-five:
the gap is a measured work list, not the sentence "we still need icons". The icon is
HIDDEN rather than blank when there is none, because an empty `TextureRect` still takes
its width and a bag of mixed icons would have a ragged left edge.

**Two ledgers, and they are asserted apart**: the player's pack and the village's
account have the same shape, the same method names and the same units, so a
mistake between them is invisible on screen. Teeth: routing the player's chopped
wood into `building.inventory` reports "fell on the ground 0 of 4".

---

## Running

```bash
GODOT="D:/privacy/Openclaw/Godot-4.7.2/Godot_v4.7.2-stable_win64.exe"
"$GODOT" --path D:/cozy/cozy-game-v2                                   # play
"$GODOT" --headless --path D:/cozy/cozy-game-v2 --quit-after 4500      # self-check
"$GODOT" --headless --path D:/cozy/cozy-game-v2 \
  --script res://tests/unit/run.gd                                     # unit tests
```

Every block must end with the self-check green and the demo still runnable.

---

## ENV V0.3 — the wind (2026-09-15)

`core/wind_system.gd`. The doc's §6 V0.3 is "一个数据源 + 注入，风格与 clock 一致":
it owns `wind_direction`, `wind_speed` and `wind_gust`, and it is a Node for the
same reason the clock is — something has to pull on a frame.

**DERIVED FROM THE CLOCK, NOT STORED.** `wind_at(hours)` is a pure function, so the
wind at 14:30 on day 3 is the same wind every time that hour comes round, in any
session, after any save, with **nothing about it in the save file**. `INVARIANTS`
has the two bugs this prevents: a stored value that can disagree with what it was
derived from, and an accumulating one that drifts every frame.

**IT DOES NOT BEND ANYTHING.** How much a KIND of plant moves is
`CozyVegetationScatter.WIND_STRENGTH` — a fact about a plant. How windy it is is
this file's — a fact about the world. The scatter multiplies them in one place, so
a lull leaves the order intact: a trunk still moves less than its leaves when the
wind drops, rather than the tree coming apart.

The gust is two sines at rates that do not divide into one another (one sine is a
fan switching on and off on a schedule); the scroll speed never reaches zero (a
field that stops dead and starts again is a bug with a shape rather than a lull);
and nothing is published when nothing changed — a signal every quarter second
carrying the same three numbers trains its listeners to ignore it, and these
listeners rewrite eight materials.

```
wind reaches the plants: calm hour 0.0 gust 0.05, windy hour 23.8 gust 0.61;
front leaves 0.063 -> 1.095, trunk 0.005 < leaves in the calm=true,
exactly strength x gust=true, direction told=true  [OK]
```

The check reads the **material**, not the wind system: a check that asked the wind
would pass just as well against materials nothing ever writes to.

**Open: the camera is too far** (Willow, 2026-09-15, after looking at it). Density
and visible height are ONE number — `720 / visible_height = px/m` — so bringing the
view closer means re-scaling every asset. Three options are written up in the
Obsidian board index; **C** (default zoom step 0 at 11.25 m, density 64) makes the
world density equal the character sheet's authoring density and removes the "art at
2x" special case entirely.

Willow, 2026-09-16: **C, provisionally.** The two constants and the 16 regenerated
canvases are NOT flipped yet — the cost has to be measured and the "provisionally"
honoured before every asset is re-scaled twice.

---

## Harvest resolves by the PLANT, not by the verb (2026-09-15)

Willow: "不同的植物 harvest 会产生不同的产物，你逻辑先做好."

`CozyRecipeDefs.for_point()` returned the FIRST recipe naming a point type, iterating
ids in **alphabetical** order. Three plants that all offer `harvest` therefore resolved
to ONE recipe, and two of them yielded the wrong thing **silently** — a flax plant
handing over wheat, with nothing anywhere saying so.

The first attempt added a verb per plant (`cut` for grass, `pull` for flax). That is
the same trap with more vocabulary rather than the logic that was asked for, and it is
gone: every gatherable offers `harvest`, and **the object names its recipe**.
`for_object(def_id, point_type)` reads an interaction row's `recipe` and falls back to
`for_point` for everything that predates this. Both consumers — the player's gather and
the resident's produce — now go through it.

`ambiguous_offers()` names any gatherable offering a verb that more than one recipe
claims without saying which one it is, and the suite asserts it empty. **The rule that
makes alphabetical order safe is not "there is only one recipe per verb" — it is "no
two recipes may claim the same verb without the object saying which".**

The assertion for the logic itself asks all three `harvest` plants one at a time, then
counts how many of them the VERB alone could have been right for: **at most one, and
not none.** The first version compared a value against itself — a tautology, and the
third one this session.

Also in: the chain's raw materials (stick / hay / fibre / rope / cloth) and its goal
(a simple tent — a MATERIAL rather than an object, so placing it stays the build
system's business), plus the two gatherables it starts from: `grass_patch` (3 hay,
regrows in 4 h) and `flax` (2 fibre, 8 h).

Baseline 168 OK / 0 FAIL / 0 ERROR; unit 27/232/3210 -> 27/233/3237.

---

## Icons: six of thirty-one (2026-09-15)

The licence is checked FIRST, because that is the gate. Kenney Vleugels' Roguelike /
RPG pack is **CC0-1.0** — a public-domain dedication, no conditions, redistribution
allowed — which the pack's own `License.txt` states. A CC BY-SA pack was rejected on
sight for the same rule: **share-alike is a condition this project cannot meet.**

The sheet is committed WHOLE (94 KB, 57x31 tiles of 16x16) rather than only the tiles
in use, so the other ~1700 sprites are addressable by coordinate without another
download, and a tile in the game can be traced back to the sheet it came from.
`docs/CREDITS.md` records source, author and licence. CC0 asks for no attribution and
the entry is there anyway — "nobody is owed this one" is a reason to write less, not a
reason to write nothing.

`data/item_icons.gd` maps an id to a tile, and **drawable ids are ONE vocabulary**: a
bag cell holds an equipment instance and a pack row holds a material, and both are an
id with a sprite beside it.

**Six of thirty-one have a picture, and the other twenty-five are the point.**
`missing()` returns them, so the gap is a measured work list rather than the sentence
"we still need icons". **The denominator comes from the vocabularies, not from the
table** — a table that quietly lost a row cannot look like progress.

Only what could be read off the sheet is mapped. The pack ships no sprite index, so
every entry was checked by looking at the tile, and an id is mapped only when the
reading is honest: `wood` is a wooden branch, `copper` is a pile of coins,
`wooden_shield` is a shield. **A plausible-looking wrong icon is worse than no icon** —
a bag showing a hammer over an axe is a bug report about a lie, which is the argument
`appearance_name()` already makes about names.

Both consumers draw it: the bag/gear cell puts a 16 px icon at the left of the name and
**hides it when there is none** (an empty `TextureRect` still takes its width, so a bag
of mixed icons would have a ragged left edge), and the pack's material rows do the
same. The cell reads `appearance_id()`, so a glamoured item wears the icon of what it
looks like.

`detect_3d/compress_to` defaults to `1` and would swap these for VRAM-compressed on
their first trip into 3D — applied by hand, and it has to be re-applied whenever these
are re-imported.

Baseline 168 OK / 0 FAIL / 0 ERROR; unit 27/233/3237 -> 28/237/3271.

---

## Write safety: a save is never written in place (2026-09-16)

`save_world` opened the live path with `FileAccess.WRITE`, which truncates the old
world before a byte of the new one is written. A crash in that window does not
leave a damaged world — it leaves **no** world, and `load_world` returns `{}`. Not
a hypothetical: `tests/probe/save_write_probe.gd` builds that file and prints
`load_world -> {} (the world is GONE)`.

It now writes `<path>.tmp`, renames the live file to `<path>.bak`, and renames the
temp into place — chosen so that **at every instant at least one complete
generation exists on disk**. A crash between the two renames leaves no live file
and a complete backup, which is why `load_world` falls back.

**The fallback is not silent.** `CozySaveManager.last_source` records `main` or
`backup` and recovering pushes a warning. A silent fallback would hand the player
a world one save old and never say so — and pass every check, because the checks
ask whether a world came back, not **which** one.

**This also turned up bug 23's second occurrence.** `_read_doc` used
`JSON.parse_string`, which PRINTS on a malformed document, so refusing a corrupt
save looked exactly like a broken build. Bug 23's fix had been applied to the
dungeon blueprint and nothing else, and it stayed invisible for two days because
**no test had ever fed the save layer a file it could not read**. The first one
that did turned the unit run's `0 ERROR` into `1 ERROR` with every check green.

Two measured platform facts, rather than assumed ones: replace-by-rename **works
here and does replace an existing destination** (four spellings, on this project's
own `user://` path, which contains a space) — but Windows does not *guarantee*
what POSIX does, which is why the `.bak` is the real net rather than the rename;
and `FileAccess.flush()` is the closest primitive Godot exposes to fsync, so a
power cut can still lose a save that reported success.

`save_manager.exists()` is gone. It had **no callers** — a declared capability with
no consumer, this project's most expensive habit — and `load_world` answers the
same question by returning `{}`.

**Not in this card:** addressing a world by id, and autosave on safe boundaries.
Both belong to the per-player-world shape the online direction needs (doc §82's
three obligations) and neither is a write-safety question.

```
save/load: 531223 byte(s) survived the disk  [OK]
save/load a v1 file through the real path: 10 wall(s), 3 slab(s), 1 stair(s), 6 object(s)  [OK]
save safety  7 case(s), 15 check(s)  [OK]

mutation (tools/mutation_check_save.py, outside the repo)  FAIL  ERROR
  write in place (the pre-2026-09-16 bug)                     2      9
  JSON.parse_string back                                      0      1   <- log only
  never try the backup                                        2      1
  erase the live file but keep the backup                     2      0

Baseline unchanged: 168 OK / 0 FAIL / 0 ERROR; unit 28/237/3271 -> 29/244/3286.
```
