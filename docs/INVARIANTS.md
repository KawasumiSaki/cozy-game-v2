# Invariants — do not "simplify" these away

> Each of these was paid for with a real bug. They are the rules that assertions
> cannot derive: the code can be made to pass tests while violating every one of
> them, and it will look like it works until it doesn't.
>
> Read this before changing how any of these subsystems behave.

---

## Rooms are DERIVED, never authored

A planar face traversal over the wall graph produces the room polygons
(`CozyRoomDetector`). **Never hand-place a room.** The payoff is that moving a
wall re-derives the rooms, the portals, the room graph and the navigation on its
own — one wall splits a room in two and both portals re-bind to the correct new
rooms, with no code that handles that case.

## T-junctions need planar subdivision

When a wall's end lands in the *middle* of another wall, split that wall's
segment at the node. Without it the graph is not planar, face traversal cannot
see the enclosed regions, and **the wall silently fails to divide anything**.

This was a real bug: a dividing wall produced one room instead of two, and the
symptom looked like the wall had not been built at all.

## Openings do NOT modify the centre-line

A door carves geometry but leaves the wall's centre-line intact, so the graph is
already closed around it and the room is detected with no help. There must be
**no doorway bridging** — a bridge spanning an intact edge is a duplicate edge,
and duplicate edges corrupt the face traversal.

This was a real bug, and fixing it **deleted** code rather than adding it. The
bridging mechanism was built when a doorway was a physical gap between two wall
segments; the opening change made it obsolete, and it was left in place long
enough to break rooms entirely. Do not bring it back.

Bonus from the same change: the ground-floor room polygon went from 6 vertices
to 4, because splitting the wall into segments had been polluting the topology.

## Walls extend half a thickness past a junction

Two boxes that stop at a joint each contribute half a thickness, so a
thickness-sized square of daylight is missing from the outside of an L-corner.
`CozyWallSolver` runs every wall half a thickness past the joint.

The self-check *unsolves* first, measures, then re-solves — so it proves the
solver fills the corner rather than assuming it.

## A drawn floor is not a floor

Slabs carry collision. The project once had an upper floor that was only
rendered: characters walked off the edge and dropped to the ground floor. The
bug read as a navigation failure and was nothing of the sort.

Slabs are also **fadable**. At a 52-degree camera pitch a slab sits between the
camera and anyone under it, so a slab that cannot fade hides the player exactly
the way a wall would.

## Stairs need three things

Doc §30, and each is a bug this project hit:

- **Low-end entry.** A ramp's tilted collider presents a *vertical* face when
  approached from the side, because the slab is tilted and its short end is
  perpendicular to the run. A stair can only be entered from its foot.
- **A landing.** Arriving at full height with nothing to stand on means stepping
  off into space.
- **A floor-level exit.** A ramp that tops out short leaves a lip.

Also: the visual is steps, the collider is **one hidden slope**. Colliding
against the step boxes makes CharacterBody3D catch on every riser. And the
collider's basis must be built as `Basis(Y, yaw) * Basis(Z, slope)` — setting
only the yaw leaves a *horizontal* box, a ceiling to walk under rather than a
ramp to walk up. That one is invisible in a still frame.

## The outdoors needs a navigation grid too

"Outdoors" is not a room and has no polygon, so it is tempting to treat it as
open space and walk a straight line across it. That works until there is a
building in the way: a route from the front door to a point behind the house
went **through** the house, and the symptom was an NPC sitting at
`blocked, replanning` with no hint of the cause.

The outdoor grid is synthesised from the terrain bounds with the buildings
registered as obstacles, and it is deliberately **coarser** (0.5 m against a
room's 0.25 m): it spans the whole terrain, and 0.25 m over 64 x 64 m is 65,536
cells — precision nobody can see at that scale, bought at startup cost.

Two traps, both met:

- **The prune loop erases it.** `_rebuild_spatial` drops every nav grid whose id
  is not a live room, and the outdoor grid is keyed by a space no room has.
  `OUTDOORS` has to be listed as alive.
- **Wall footprints are bounding boxes.** Exact for the axis-aligned walls this
  project builds, conservative for a diagonal one. Over-blocking is the safe
  direction: a longer walk is a nuisance, walking through a wall is a defect.

## Everything procedural is deterministic

Position, shading, scatter and VFX phase all come from `CozyArtSeed` —
**never `randf()`**. The same world must rebuild identically after a save and
reload. The doc names the failure: "昨天这棵树在左边，今天跑到右边."

Two specific traps:

- **Phase must come from the INSTANCE's position, not its definition.** Two
  campfires share a definition; seeding from `def_id` left them flickering in
  perfect lockstep.
- **An object's effects are built before it is positioned**, so the phase has to
  be re-seeded after placement.

A determinism check must compare a **fingerprint of every instance**, not a
count. A layout can be reordered while keeping the same total.

## Biomes are derived, not stored

They follow from material and proximity (`CozyBiome`), so they update the
instant the ground changes and cannot drift out of sync with the terrain. Storing
them would need a save entry and a generation pass, and would be wrong between
the edit and the next pass.

## Instancing is not optional

2000 plants go into one MultiMesh, not 2000 nodes. Wall blocks merge into one
mesh per wall — an 8 m stone wall is ~84 blocks. Doc §61 forbids the
alternative outright.

Collision, by contrast, stays **coarse**: one box per wall span, one per slab,
one slope per stair. Collision does not need masonry detail, and a per-block
collider is a physics cost for no behaviour.

## A rule that lives only in a mouse handler is not a rule

The terrain gate and the material cost live inside `CozyBuildingSystem.submit`,
not in the input code. Doc #70 puts rules and solvers between State and
Generator. A placement rule that only exists in a UI callback will be bypassed
by the next caller.

## A roof goes where nothing is above it

Not "on the highest floor". A one-storey outbuilding on floor 0 is topmost for
its own footprint and must be roofed. And "is anything above it" must **sample
the room's interior**, not just its centroid — the centroid of the ground-floor
room beside the stairwell falls inside the opening, and a single-point test is
right for most rooms by luck.

---

## Measuring beats guessing

Two cases worth remembering, because both went the opposite way from the
intuition:

**The scatter rebuild.** 176 ms. Split into phases (sampling 130, mesh build 5)
before touching anything. The cost turned out to be GDScript call overhead, not
the algorithm. Removing an Array allocation did nothing (169 ms); an early-out
that removed *dictionary lookups* did (138 ms). The failed attempt is recorded
in the commit rather than quietly dropped.

**The roof-fade "bug".** Reported as a defect. It was correct — the **assertion**
was wrong. Outdoors is not the same as a clear view: with the camera pitched and
sitting on the far side of the house, the line of sight to a player standing
outside genuinely passes through the roof.

When a fix does not move the number, say so. When a test fails after a correct
change, check the test.

---

## A per-frame refresh must be idempotent

Anything that redraws every frame has to satisfy: `refresh()` called N times
produces the same result as `refresh()` called once. The moment a refresh reads
its own output — rebuilding a label's text out of that label's text — it
accumulates corruption at frame rate.

The trap is that **every single-frame check passes**. The widget exists, it is
wired, it has the right number of rows, and one refresh draws the correct
string. Assert it as "one refresh versus N refreshes", never as "does it draw
the right thing". (UI-02: 600 refreshes turned `"> 09:00  0  Working"` into a
line with three hundred zeros in it.)

Corollary: when a string is formatted in two places, it will drift. One
formatter, two callers.

## `agent.state` is the FSM, `agent.npc_state` is the resident

`CozyNpcAgent.state` is an enum (`IDLE` / `GOING` / `WORKING`). A resident's
actual data is on `npc_state`.

This bites because `main.gd` legitimately reads `.state` off a **wall**
(`CozyWallState`). Copying that line for an NPC yields an int — no error, no
crash, no warning. Just a blank panel. Nothing in the type system stops you.

---

## Bugs this project has already paid for

Recorded here so they are not re-derived. Full narratives are in the development
log (`02-开发日志/游戏开发日志.md`).

| # | Bug | Caught by |
|---|---|---|
| 1 | T-junction left the graph non-planar; a dividing wall divided nothing | live-rebuild assertion |
| 2 | Doorway bridging outlived its purpose and corrupted face traversal | room assertions |
| 3 | Floor slabs had **no collision** — the upper floor was a picture | NPC job assertion |
| 4 | "Out of waypoints" treated as arrival — the NPC worked from the floor below | NPC job assertion |
| 5 | Stuck detection never reset, so any long walk was abandoned | NPC trace |
| 6 | A ramp's collider is a vertical wall from the south | NPC trace |
| 7 | The stairwell is an obstacle on both floors, for opposite reasons | navigation assertion |
| 8 | Interaction points were `(0,0,0)` at planning time (only `_process` updated them) | route assertion |
| 9 | Occlusion faded the house on a **non-followed** character's behalf | dedicated probe |
| 10 | Stair ramp collider built with yaw only → a horizontal box | NPC job assertion |
| 11 | `_build_roofs()` not idempotent → duplicate roofs stacked | outline assertion |
| 12 | Roof rule "highest floor" left one-storey outbuildings bare | outline assertion |
| 13 | "anything above" tested by centroid alone; the stairwell fooled it | outline assertion |
| 14 | VFX phase from `def_id` → two campfires in lockstep | VFX assertion |
| 15 | Per-frame panel refresh re-derived its input from its own output → schedule text corroded 60×/s | panel idempotence assertion |

**Fourteen of the fifteen were found by an assertion, not by looking at the
screen.** Several were invisible in a still frame. That is the whole argument
for the assertion discipline in `03-流程/更新方案.md`.

Bug 15 was never once rendered on screen — nothing instantiated the widget that
had it. It was written, it imported cleanly, and it sat on disk as a `class_name`
with no callers. **Parsing is not working.**
