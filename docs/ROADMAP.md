# CozyVale V2 — Block Roadmap

> Engine: Godot 4.7.2 · Repo: `~/cozy-game-v2` · Started: 2026-09-11
> Upstream: 《游戏 V2 技术架构》 (tech architecture) + 《游戏-愿景-v2》 (north star)
> This file is the working map. One block ≈ one session of work.
> **Every block must end with the demo still runnable.**

---

## Axis convention (locked decision)

The tech doc records height as **Z** (`Floor 0 = Z 0`, `Floor 1 = Z 3`).
Godot is **Y-up**. This project maps the doc's Z onto Godot's +Y:

```
doc(x, y, z)  ->  godot(x, z, y)
```

Semantics are identical — a floor is still a real elevation, not a render layer.
Only the axis label changes. All spatial code follows this mapping.

---

## Render style (locked decision, 2026-09-11)

**Characters are NOT 3D. This is a 3D-render-to-2D look — HD-2D / 3D-to-2D.**

Confirmed by Willow: the world is genuinely 3D underneath, but everything the
player sees is pixel art. Think Tiny Glade / RimWorld presentation, not a
fully-modelled 3D RPG.

What that means concretely:

| Layer | Reality |
|---|---|
| Position, floors, collision, line-of-sight | **Real 3D** |
| Wall / slab geometry | **Real 3D meshes + 3D colliders** |
| Lighting and shadows | **Real 3D** |
| Camera | **3D, orthographic** (no perspective convergence) |
| Characters | **2D pixel sprites** (billboards fixed to Y) |
| Surfaces | **Pixel-art textures, nearest-neighbour, no smoothing** |
| Output | 640×360, **integer-scaled** to the window |

So "3D rendering that looks 2D" is the target, and it is already what the code
does. No rework was needed when this was confirmed.

---

## Current state

**Phase 0 technical spike — COMPLETE and verified.**

Headless self-check (`--quit-after 900`) drives the player through the Phase 0
acceptance path and reports physics state every frame:

```
frame  24  (3.25, 0.00, -3.50)  floor=0   gravity settles
frame 107  (3.25, 0.00,  2.92)  floor=0   walks north through the doorway
frame 156  (5.45, 0.72,  4.08)  floor=0   onto the staircase
frame 190  (6.87, 2.13,  4.08)  floor=1   reaches the upper floor
frame 206  (7.53, 2.80,  4.08)  floor=1   arrives, stops
```

Proven: gravity, doorway traversal, stair climbing, floor detection,
occlusion raycasting — zero errors, zero warnings.

**Rooms are now derived from the wall graph** (V2-06). No room is authored by
hand — the detector runs a planar face traversal over the wall segments and the
enclosed regions fall out:

```
floor 0 (y=0.0): 1 room — 48.0 m2, 6 verts   (8x6; 6 verts because the
                                              doorway splits the south wall)
floor 1 (y=3.0): 1 room — 48.0 m2, 4 verts   (clean rectangle ring)

room_at((4.0, 0.1, 3.0)) -> room_0_0   [OK]
room_at((4.0, 3.1, 3.0)) -> room_1_0   [OK]   same XZ, upper floor
room_at((4.0, 0.1, -6.0)) -> outdoors  [OK]
```

Doorways are physically open but topologically **close** a room — a door
separates two spaces while staying passable (doc #29). Detection therefore
bridges the opening.

**Portals and macro routing** (V2-07, V2-08):

```
portals: 2
  - door_south [door]  f0/outdoors <-> f0/room_0_0     (a door does not change floor)
  - stair_main [stair] f0/room_0_0 <-> f1/room_1_0     (a stair does)

route outdoors -> room_1_0 : door_south[door] -> stair_main[stair]  [OK]
route room_0_0 -> room_1_0 : stair_main[stair]                      [OK]
route room_1_0 -> room_1_0 : (no route)                             [OK]
```

The last block is the important one: **standing outside the house, the room
graph derives "go through the door, then up the stairs" using topology alone** —
no geometry, no per-floor special-casing. That is doc #41's macro route, and the
prerequisite for the NPC reaching a second-floor machine (#112) without any
`if npc_is_textile_worker: go_upstairs()`.

**Local navigation** (V2-09) closes Phase 1 — the lower half of the doc's split:
the room graph says *which* room to cross, local nav says *how*.

```
nav door->stair:       15 pts,  4.33 m  [OK]
nav after obstacle:    22 pts,  5.56 m  [OK, detour +1.23 m]
```

Dropping a 0.6 x 4.0 m obstacle (a table) across the direct line makes the route
wrap around it and grow by 1.23 m. That is doc #86's hard requirement —
"when furniture changes, navigation MUST update" — demonstrated rather than
asserted. A grid was chosen over a baked navmesh precisely because marking
cells is synchronous and cheap, while rebaking at runtime is neither.

Run it yourself:
```bash
godot --headless --path ~/cozy-game-v2 --quit-after 900
```

---

## Block list

### Phase 0 — Technical spike
| # | Block | One-liner | Size | Status |
|---|---|---|---|---|
| V2-00 | Skeleton + self-check | Project layout, axis convention, headless autopilot harness | S | ✅ 09-11 |
| V2-01 | Orthographic camera | Ortho rig, follow, zoom steps, yaw/pitch, ground-space basis | S | ✅ 09-11 |
| V2-02 | Segment wall | start/end/height/thickness → mesh + collider; any length, any angle | S | ✅ 09-11 |
| V2-03 | Character billboard | Real 3D position + 2D pixel sprite, capsule collision | S | ✅ 09-11 |
| V2-04 | Occlusion fade | Ray camera→character; fade only the blocking wall | S | ✅ 09-11 |

### Phase 1 — Spatial core
| # | Block | One-liner | Size | Status |
|---|---|---|---|---|
| V2-05 | Floor system | Elevation registry; floor as a first-class spatial layer | S | ✅ 09-11 |
| V2-06 | Room detection | Closed regions auto-derived from the wall graph | M | ✅ 09-11 |
| V2-07 | Portal | Door / stair / elevator unified as a space connector | S | ✅ 09-11 |
| V2-08 | Room graph | Macro routing: room → portal → room, across floors | M | ✅ 09-11 |
| V2-09 | Local navigation | Navmesh per room; furniture updates it | M | ✅ 09-11 |

### Phase 2 — Terrain
| # | Block | One-liner | Size | Status |
|---|---|---|---|---|
| V2-10 | Fine grid + chunk | Sub-metre terrain cells, chunked for memory | M | ⬜ |
| V2-11 | Materials + dig/fill | Grass↔Soil↔Sand↔Stone↔Water, brush editing | M | ⬜ |
| V2-12 | Road rasterization | Draw a path → smooth → rasterize to a terrain mask | M | ⬜ |
| V2-13 | Foundation | Building sits on terrain; support check | S | ⬜ |

### Phase 3 — Building
| # | Block | One-liner | Size | Status |
|---|---|---|---|---|
| V2-14 | Building intent | Draw an outline → system generates the structure | M | ⬜ |
| V2-15 | Wall connection solver | Corners, beams, joints where segments meet | M | ⬜ |
| V2-16 | Openings | Door / window cut into a wall as parametric openings | M | ⬜ |
| V2-17 | Roof generator | Polygon → ridge → roof geometry (gable/hip/flat) | L | ⬜ |

### Phase 4 — Object & interaction
| # | Block | One-liner | Size | Status |
|---|---|---|---|---|
| V2-18 | WorldObject | Unified base for furniture / machine / container / item | M | ⬜ |
| V2-19 | Free placement | No tile snap + validation (wall / overlap / support / doorway) | M | ⬜ |
| V2-20 | InteractionPoint | Decouples NPC from furniture entirely | M | ⬜ |
| V2-21 | Containers | Inventory + capacity + access point | S | ⬜ |

### Phase 5 — NPC
| # | Block | One-liner | Size | Status |
|---|---|---|---|---|
| V2-22 | NPC data model | Identity, attributes, skills, needs, inventory | M | ⬜ |
| V2-23 | Job / Task | Job = what I'm responsible for; Task = what I do now | L | ⬜ |
| V2-24 | Cross-floor work | Warehouse → stair → floor 1 → machine, no hard-coding | L | ⬜ |
| V2-25 | Schedule & needs | Time-of-day behaviour; hunger / energy drive tasks | M | ⬜ |

### Phase 6 — Persistence
| # | Block | One-liner | Size | Status |
|---|---|---|---|---|
| V2-26 | Save / load | Save world facts, not transient computation (doc #132–133) | M | ⬜ |

---

## Hard non-goals until the vertical slice works (doc #178)

Explicitly **banned** from core development before Phase 0–5 hold together:

❌ open world ❌ multiplayer ❌ complex combat ❌ 100+ NPC
❌ full economy ❌ world-tree storyline ❌ the Veil as a full system
❌ airship piloting ❌ large-scale weather ❌ water simulation
❌ fluid dynamics ❌ infinite procedural world ❌ genetics/growth systems

The danger is never "we can't write code" — it's **dependency creep between
systems** (doc #179). Space → terrain → building → object → interaction → NPC.

---

## Target set for 2026-09-11

| # | Block | Notes |
|---|---|---|
| V2-00…04 | Phase 0 spike | ✅ done |
| V2-05 | Floor system | ✅ done |
| V2-06 | Room detection | ✅ done — walls now mean something |
| V2-07 | Portal | ✅ done |
| V2-08 | Room graph | ✅ done — cross-floor routing works |
| V2-09 | Local navigation | ✅ done — and reacts to obstacles |

**Phase 1 (spatial core) is complete.** The world now has real floors, rooms
derived from geometry, portals, cross-floor routing, and local pathfinding.

Next: **Phase 3 building interaction** pulled forward as a vertical slice —
let the player drag out a wall in-game and watch rooms, portals, the room graph
and local nav all re-derive live. That exercises every block above at once and
is the doc's "dynamic spatial structure" claim (#28) made visible.

Reaching V2-06 today means the world stops being "a box you can walk in" and
starts having **rooms that the system understands** — which is the prerequisite
for navigation and NPC work in later sessions.

---

## Art policy

**Art is intentionally a placeholder.** All textures are generated
procedurally at runtime (`render/pixel_art.gd`). Nothing is a real asset.

When real pixel-art materials arrive from an external generator, only two
files change — nothing in the game logic:

- `render/pixel_art.gd` — texture factory
- `data/materials.gd` — the material table

That is the whole point of doc #134 (Data-Driven Design).
