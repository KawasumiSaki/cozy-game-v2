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

Slabs are also **fadable**. At the locked camera pitch a slab sits between the
camera and anyone under it (measured at 40 degrees and at every yaw tested — see
"Fading the NEAREST blocker"), so a slab that cannot fade hides the player
exactly the way a wall would.

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

## A wall added at runtime, with a door in it, breaks the navigation

Debt 22, root-caused 2026-09-14 by differential experiment. The resident that
"spent ten hours going in circles" was not a pathfinding failure. A wall added
AFTER the navigation was built, with an opening cut into it, leaves the navigation
grid routing through that opening while the collider is solid at its centre:

    cast through wall_010's door centre: SOLID
    [FAIL, navigation has a hole the collider does not]

The resident paths through the door, walks into the wall, gets stuck, replans, and
repeats. Measured by changing only that one thing:

    house present, live-rebuild test running    -> path crosses geometry: 2 leg(s)
    house present, live-rebuild test gated off  -> path crosses geometry: 0 leg(s)

**The house's own door has never been the problem.** It is cut at startup, before
any navigation exists, and `door gap (walkable) open` has been green since V2-16.
Only a wall that appears afterwards does this.

So `main.gd` has a switch, `BUILDING_ENABLED`, that is currently false and gates
the only two things that draw a wall at runtime: the palette's `outline` and `wall`
tools, and the live-rebuild stage. **Turning it back on brings the bug back** —
verified the same way, same wall, same leg:

    BUILDING_ENABLED = true  ->  path crosses geometry: 2 leg(s), leg 11-12 hits wall_010

Fixing the nav/collider disagreement for runtime-added openings is the price of
player building. It is recorded here so that turning the switch on is a decision
rather than a rediscovery.

**Corollary — the probe's own assertion under-reports.** The
`[FAIL, navigation has a hole the collider does not]` line is gated on the resident
being pressed against the wall at the instant the probe samples. In one run it
sampled at waypoint 12 and fired; in another, with the bug equally present, it
sampled at waypoint 11 and stayed silent. `path crosses geometry` is computed from
the whole path and is the signal to trust. A green probe is not a clean path.

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

## A `to_dict()` that never passes through a serializer is not a save format

Three separate bugs hid behind one function that looked finished (V2-26):

1. `CozyBuildingState.to_dict()` stored walls only, so a load dropped every slab
   and every stair. Rooms survived — they are derived from walls — so the world
   would have looked nearly right while nobody could reach the first floor.
2. `JSON.stringify` does not understand `PackedInt32Array` / `PackedFloat32Array`
   / `PackedByteArray` and silently writes each as a **String**. The field then
   reads back as a string and cannot be assigned to the array it came from.
3. `_sync_views` matched views to states by **id** and never re-pointed
   `v.state`. That was safe only while state objects were never replaced.

The through-line: an in-memory round trip (`b.from_dict(a.to_dict())`) exercises
none of it. It hands back live objects, so the assignment succeeds and the
assertion goes green while the file on disk is unreadable. **A round trip that
never touches a file proves nothing about saving.** Write it to disk and read it
back, or the check is decoration.

Corollary: anything reachable from a save file must be represented with JSON's
own types — plain Array, Dictionary, String, number, bool. Packed arrays and
Vector types are not among them.

## Object identity is not id identity

`_sync_views` / `_sync_group` reconcile runtime views against state by **id**.
That is only equivalent to matching by object as long as state objects are never
replaced — appended and removed is fine, replaced is not.

A load replaces every state object while keeping its ids, which is the first
thing in this project to break the assumption. When a view keeps a reference to
a state no longer in `state.walls`, it refreshes from geometry that no longer
tracks edits, and it looks completely normal.

So: re-point the view's state before refreshing it, and guard the re-assignment
on object identity so the ordinary path stays a no-op (doc #32 — local edits
rebuild locally).

## Two outlines that touch emit their shared edge TWICE, and the rooms merge

Measured 2026-09-12 with `tests/probe/dungeon_layout_probe.gd`, before building
anything on top of the dungeon blueprint's `outlines` format. The probe runs
outlines through the real pipeline — `CozyOutlineGenerator.plan()` into
`CozyRoomDetector.detect()` — with no world, no nodes and no terrain, because
that is the whole claim: **a dungeon is just another batch of walls.**

`plan()` closes every outline into a loop. So two rooms laid out side by side
each emit the edge they share, one wall in each direction on the same segment:

| Layout | Rooms the detector returns |
|---|---|
| one room | 1 (48 m²) |
| one L-shaped room | 1 (84 m²) — concave is fine, as documented |
| **two rooms, each loop closed** | **1 (96 m²)** — the two rooms MERGED |
| two rooms, shared edge emitted once | 2 (48 + 48) |
| **two rooms + corridor, each loop closed** | **1 (104 m²)** — everything merged |
| two rooms + corridor, corridor's end edges dropped | 3 (48 + 48 + 8) |

**Nothing errors in the merged cases.** The traversal returns one room and the
count is the only thing that knows. A dungeon generator built on the naive
reading would ship a single-room dungeon and look like it worked.

The rule that falls out: **an outline must never emit a wall segment that is
already in the graph.** Where two outlines meet, the generator emits that edge
ONCE, and the connection between them is a `CozyOpening` on that single wall —
which is exactly why openings leave the centre-line intact: the two rooms stay
two rooms, and the Portal is derived between them.

The corridor case is the useful one to keep: its two long sides **butt into** the
rooms' walls rather than coinciding with them, and that works, because the
detector already subdivides T-junctions. Coincident is the trap; butting is not.

---

## An id is only unifying if one place refuses to be ambiguous

Before the entity registry, every system kept its own list under its own id
prefix, and nothing could answer "what is id X" without already knowing which
system minted it. Unifying the ids adds one failure none of them could have had
alone: **two kinds offering the same id**, which each of them would report as
fine. So `state_of(id)` returns null for an ambiguous id rather than whichever
kind registered first, and `duplicate_ids()` is the detector — the self-check
asserts it empty on every run. A lookup whose answer depends on registration
order means several different things, which is the shape of bug 20 (a count
several different wrong worlds produce).

Two corollaries that a tidy-up would undo:

- **The id stays INSIDE the payload.** A saved entity is `{kind, state}`, and the
  state carries its own id, because that is where every serializer here has
  always written it. Drawing the id beside the payload as well would put one fact
  in two places in one file, and the file could then disagree with itself.
- **The id counters are NOT entities.** They travel under `next_ids`. Ids are
  minted `wall_%03d`, so a load that dropped a counter would mint an id that
  already exists on the very next wall someone drew — the collision the registry
  refuses, arriving one action later.

The registry holds **encoders but not decoders**, and that asymmetry is
deliberate: it can index any state, but a decoded wall has to be appended to
`building.state.walls` by the thing that owns that list. Encoding is "describe
what you have"; decoding is "install this", and only the owner can do the second.

---

## A declared capability with no consumer is not a feature

`chest` advertised a `store` interaction point from Phase 4, and `CozyJobDefs`
carried a `hauler` whose `point_type` is `store` for exactly as long. Nothing
consumed either one. The point was decoration, and the job could acquire a
target that no object ever offered, so it could never finish a task.

On screen both read as working features. Neither had ever run.

Before trusting a data table, ask what reads it. Every interaction type in
`CozyObjectDefs` and every `point_type` in `CozyJobDefs` should have a consumer;
`grep` for the constant is the entire check. The same question applies to a
`class_name` — if nothing instantiates it, it has never executed.

## A format refuses what it cannot validate, by name

The rule above, applied to a file format rather than a table. A field that is
parsed and then never read is indistinguishable, from the author's side, from one
that works — so `CozyDungeonBlueprint` refuses such fields rather than tolerating
them, and says which field and what would have to exist first.

The design doc's §3.3 example carries three fields this format does not, and the
three are not the same kind of thing:

- `links` — **never** stored. Which outlines meet, and along which stretch, is a
  MEASUREMENT: `CozyDungeonLayout` derives it from the geometry. A stored copy is
  a second answer to a question already answered, and the runtime answer is the
  one that tracks an edit.
- `spawns`, `content` — **not yet**. They need a vocabulary (what may be spawned,
  what a "room hint" resolves to) that does not exist. They join the format on
  the same day as the system that reads them, together with its validation.

The same reasoning fixes the version policy: **a newer `version` is refused, not
read as well as this build can.** A best-effort read would take the fields it
recognises and DROP whatever the newer format added, and the only symptom would
be a dungeon quietly missing a room — the file loads, the assertion passes, the
world is smaller.

An older version would be a migration step, the way `save_manager.gd` keeps one
per version. **There is deliberately no chain while there is nothing to migrate:**
a chain with one link and no data is the "declared capability with no consumer"
above, just in a new place. When `VERSION` goes to 2, the step goes there, written
against a real v1 file.

Two mechanics that a tidy-up would undo:

- **`reject_reason()` is static and single.** `from_dict()` builds only what it
  accepts, so there is no route to a live blueprint that was never checked. A
  `validate()` that callers may skip is not the same thing.
- **A refusal never prints.** `JSON.parse_string` writes to the log on malformed
  input, which is the trap recorded under "An id is only unifying if one place
  refuses to be ambiguous": a line that means "the refusal worked" must not look
  like the line that means "the build broke". `JSON.new().parse()` returns an
  error code and stays quiet. Note that reverting this turns **no assertion red**
  — the only witness is `0 ERROR` in the log.

## A check that passes for the wrong reason is worse than a skip

When the demo house was parked (2026-09-14, `HOUSE_ENABLED` in `main.gd`), the
self-check lost thirty-four assertions. Three of them did **not** go red. They
kept printing `[OK]`, and that was the dangerous outcome:

```
npc plan ground->upstairs: 1 waypoints, crosses floor=true   [OK]
route room_1_0   -> room_1_0   : (no route)                  [OK]
opening shot at spawn: 0 opaque, 0 faded                     [OK]
```

The route planner had been asked to plan a route between two rooms that no
longer exist, planned it in ONE waypoint, and still reported that it crossed a
floor. The routing check expected "no route" and got one, because neither room
was there. The opening shot found nothing opaque in front of the player, because
there was nothing to be opaque.

**Every one of those is true for a reason that has nothing to do with what the
check is for.** A skip is legible: it says it did not run. A vacuous pass claims
coverage it does not have. So when a subsystem is parked, the checks that measure
it are parked with it — not left running to look green.

The general test, before trusting any green: *would this assertion still pass if
the thing it names were absent entirely?* If yes, it is measuring the absence,
not the thing.

## Parking must be reported, never silent

Same change, and the reason it is a rule rather than a preference: with the house
off the baseline went from 122 assertions to 89, and **89 looks exactly like 122
except for the number**. A run that quietly measures less than it used to is the
"green number that lies" this project has paid for repeatedly, so the parked
checks are a **LIST that is printed when it is skipped**:

```
[cozyv2] house: PARKED, 12 check group(s) NOT RUN (HOUSE_ENABLED=false): rooms, ...
```

`_report_house()` holds `[name, callable]` pairs rather than a run of calls, so
the same list is both the thing that runs and the source of the report. A count
kept by hand beside the calls would drift the first time someone added a check,
and it would drift silently — which is the whole failure mode.

Two corollaries:

- **The switch is verified in BOTH directions.** "Parked, not deleted" is a claim,
  and claims are cheap: `false` gives 89 OK / 0 FAIL / 0 ERROR, `true` gives
  123 OK / 0 FAIL / 0 ERROR. Both were run, in a scratch copy, before the change
  was committed. A switch nobody has flipped back is not known to be a switch.
- **The section that was parked is where the wrong questions get found.** Two
  checks came out of this asking about the world rather than about their subject:
  `save/load applied live` ended with `and building.state.stairs.size() > 0` —
  asserting a stair EXISTS, next to four clauses that compare what went in with
  what came out — and the context probe demanded at least one wall collider to
  resolve. Both are now round trips or skips, which is strictly stronger.

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

## A fade list is a LIVE collection, not something you push once

`CozyOcclusion.fadables` used to be pushed in from a handful of call sites. The
building system **replaces** views as the world changes — a roof follows its
room, a local edit rebuilds a wall — so any replacement landing between two
pushes left a **freed node in the list and the live one missing**.

Measured 2026-09-12 with the occlusion probe: at frame 91 `roof_views` held one
live roof while the fade list held a dead one, and **no roof ever faded**. The
list is now pulled from `fadable_source` on every refresh, which cannot go stale.

Two corollaries:

- **Anything that collects a list of views has this bug available to it.** Ask
  what replaces those views, and what happens to the list when they are.
- **A fade count cannot tell a correct fade from a missing one.** `0 faded` is
  equally the output of "nothing is in the way", "the ray hit nothing at all" and
  "the list is full of freed nodes". Assert the SET — `N listed, M live, freed,
  missing` — never the count. The old check printed `[OK]` through all three.

## A declared fadable that is never registered does not fade

`CozySlab` opens with "It is FADABLE on purpose"; `slab.gd` implements `bodies()`
and `set_fade()`; and this file already required it — a slab between the camera
and anyone under it hides them exactly the way a wall would. **Nothing ever added
a slab to the fade list.** Fifth instance of the same pattern; see "A declared
capability with no consumer".

Corollary: `CozyStair.set_fade(a)` takes the alpha and drops it (`_a` is never
read). Stairs are deliberately NOT in the list — listing one would add a fadable
that never fades, which is the same defect wearing the opposite mask.

## Fading the NEAREST blocker is not the same as clearing the line of sight

`intersect_ray` returns one hit. Taking it alone fades the first thing on the ray
and leaves everything behind it opaque, so the character is still hidden — and
`faded > 0` reads as success.

Measured 2026-09-12 with the yaw sweep in `--cozy-probe-occlusion`: a player
standing **inside floor 0** is reported hidden at yaw 0, 90, 180 **and** 270, and
the blocker is always a `slab`. That slab is the upper floor acting as a ceiling,
and **no camera angle puts the camera underneath it**. The bug is not the angle;
a rule that fades one blocker cannot fix a case where the first blocker is not the
one doing the hiding.

So the ray is **marched**: re-cast from the same origin with everything already
found excluded, until nothing is left. Bounded by `MAX_BLOCKERS_PER_RAY`.

The tempting reasoning to distrust: "fading everything will turn the whole house
to glass." That was the prediction; the measurement said otherwise. Worst case on
the authored house is **3 fadables out of 13** (standing in the doorway at yaw 0),
and each one is genuinely between the camera and the player. Fading exactly what
blocks is the doc's rule (#57) — "fade only the geometry that actually blocks the
line of sight". Predictions about how it *looks* are the ones to measure.

## The camera belongs on the side the building faces

A door is cut into a wall, and that wall is the front. The camera has to be on
that side, or the game opens on the back of the house with the whole building
between the camera and the player.

Here the door is cut into the `z = 0` wall and the player spawns south of it, so
the front faces `-Z`; **yaw 0 put the camera at `+Z`, i.e. behind the house**. The
symptom was "the player is invisible in the front yard", which reads like an
occlusion bug and is not one.

Two rules fall out, and both are asserted rather than eyeballed:

- **The opening shot must need NO fade.** `_check_opening_shot` asserts `0 opaque`
  **and** `0 faded` at `SPAWN_POINT`. The opaque count alone passes at any angle
  the fade rule happens to rescue; requiring that nothing faded is what says the
  *framing* is right. At yaw 0 the spawn needs the roof and the upper south wall
  faded; at 180 it needs nothing.
- **One definition of the spawn.** `SPAWN_POINT` — the setup code, the probe and
  the check all read it. A probe that teleports to a hardcoded copy of the spawn
  point stops measuring the spawn the moment the spawn moves.

`ground_forward()` / `ground_right()` derive from the yaw, so changing it does
**not** change the controls — only which side of a building you see.

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
| 16 | `BuildingState.to_dict()` stored walls only → a load dropped every slab and stair | save/load round-trip |
| 17 | `JSON.stringify` wrote `PackedByteArray` as a String → the file was unreadable while the in-memory round trip passed | pushing the dict through a real serializer |
| 18 | `_sync_views` matched by id and never re-pointed `v.state` → views refreshed from replaced state | wall-connection (corner) assertion, after a live load |
| 19 | The fade list held a freed roof, missed the live one, and had never contained a slab → no roof ever faded | occlusion probe (`occlusion fade set`) |
| 20 | `0 faded` printed OK while the fade set was wrong — a count that several different wrong worlds produce | same probe, once bug 19 was fixed |
| 21 | Occlusion faded only the NEAREST blocker; the player stayed hidden indoors at all four camera angles (always behind a slab) | yaw sweep in the occlusion probe |
| 22 | The locked camera sat on the far side of the house from the door — the opening shot was the back of the building | `opening shot at spawn` assertion |
| 23 | `JSON.parse_string` printed on every malformed dungeon file, so refusing a bad file looked exactly like a broken build | mutation testing — see below |
| 24 | `_check_building_state()` took `s.stairs[0]` outright: with no stair in the world it CRASHED rather than failing, and took its two neighbouring measurements with it | removing the demo house — the check died instead of reporting |
| 25 | A wall added at RUNTIME with a door cut into it leaves the navigation routing through a door the collider keeps shut — the resident walks into the wall forever (debt 22) | the pathing probe, then a differential experiment on that one cause |
| 26 | The schedule mapped the activity `work` onto the point type `work`, so at 09:00 it overrode every trade that is not `work` — a woodcutter sought a desk, and the three gathering trades could not do their own work in the game | `tests/probe/work_priority_probe.gd`, one day after the trades landed |
| 27 | `Array[CozyWorldObject].has(a_drop)` is not `false`, it is a typed-array **error**: the assertion written to prove that a thing on the ground is not furniture printed two `ERROR` lines and answered `false`, which happened to be the wanted answer | `0 ERROR`, which the smoke run counts and which the check's own author was not watching |

**Twenty of the twenty-seven were found by an assertion, not by looking at the
screen.** Several were invisible in a still frame. That is the whole argument for
the assertion discipline in `03-流程/更新方案.md`.

Bug 22 is the sharpest case of the pattern yet, because **the old assertion was
still green while it was happening**: `occlusion, player outdoors:` printed
`2 faded ... [OK]` at yaw 0 and `0 faded, 0 for non-followed [OK]` at yaw 180.
The same `[OK]` for the broken angle and the correct one. Only a check that names
the thing being asserted — *the opening view is clear* — could tell them apart.

Bugs 15 and 16 share a shape worth naming: **both lived in code that had never
once been executed.** Bug 15 was in a widget nothing instantiated; bug 16 was in
a function nothing called, whose only test never let it touch a file. Neither was
reachable by looking at the game, because neither had ever run in it.

Bug 23 is the first one on this list found by neither an assertion nor the
screen, and it is worth saying how it turned up. The fix was already written and
the suite was green. Reverting the fix — putting `JSON.parse_string` back — left
**thirteen cases and sixty-seven checks passing exactly as before**, and the only
difference in the whole run was one `ERROR: Parse JSON failed` line. Nothing was
asserting the property that had been fixed.

So the rule this list keeps arriving at has a corollary it had not stated:
**an assertion is not the only thing that can be green while it is lying, so
break the code on purpose and see what notices.** Six mutations were run against
this file, and the reason to report all six is that **two of them turned no
assertion red at all** — the flattering summary would have been "four for four".

| mutation | assertions red | log |
|---|---|---|
| `to_dict` emits a `PackedVector2Array` | **6** (incl. the file round trip) | 2 script errors |
| `_unknown_reason` accepts every key | **11** | quiet |
| `_version_reason` allows a newer version | **5** | quiet |
| `from_dict` drops the outlines | **5** | 3 script errors |
| `parse` back to `JSON.parse_string` | **0** | 1 `ERROR: Parse JSON failed` |
| `_to_polygon` loses its shape check | **0** | 2 `SCRIPT ERROR: Out of bounds` |

The last row is the one worth keeping. The guard stops `flat[i + 1]` reading past
the end of an odd-length list, and its removal is invisible to every assertion —
but it is **not** invisible. GDScript raises `SCRIPT ERROR: Out of bounds get
index '5' (on base: 'Array')`, measured directly, so the guard is the difference
between a clean refusal and an error path. **It is exactly the kind of check a
tidy-up deletes with the suite still green.** Do not delete it.

Both log-only witnesses end in the same place, which is why the two bugs are
adjacent: `0 ERROR` on a healthy build is a property nothing in `tests/unit/`
asserts, and it is the only thing standing under either fix. **A check that has
never been seen to fail is a check nobody has any evidence about — including the
ones that are right.**

## A navigation layer that nothing consults is not a navigation layer

**FIXED 2026-09-14.** The one-line cause was in `_local()`; the rest of this entry
is kept because the way it was found, and the two ways the check that found it
first proved nothing, are the useful part.

Found 2026-09-14 while building the resource line, by following a check that could
not fail. The outdoors has its own navigation grid — synthesised from the terrain
bounds with buildings registered as obstacles, coarser than a room's on purpose
(see "The outdoors needs a navigation grid too"). It is built, it is asserted, and
it is handed to `CozyWorldNavigator`. `_local()` never reads it:

    if room_id == CozyRoomGraph.OUTDOORS or not nav_by_room.has(room_id):
        out.append(to)
        return out

So **any move from one outdoor point to another is a straight line**, and a
resident walking from the front of the house to the back walks through it. Every
reader of that grid is a self-check:

    main.gd:942   builds it
    main.gd:918   hands it to the navigator      -> which returns early, above
    main.gd:4537  _check_outdoor_nav             <- a self-check
    main.gd:1863  _check_resource_chain          <- a self-check

`_check_outdoor_nav` proves the grid routes around the house — 14.7 m walked
against 12.7 m straight, no waypoint inside — and none of that reaches the
navigator. **The check is green and the behaviour it describes never happens.**

This is the same failure as "A declared capability with no consumer", one layer
down: there the table had no reader, here the data structure has no reader, and
the assertion written to prove it works is what made it look used.

Two things to carry forward, the second more important than the first:

- **Do not trust "a path exists" as a reachability test.** The straight-line
  return makes it true for a target placed at (500, 500) — outside the world
  entirely. The first version of the resource check did this and mutation testing
  is what caught it. Ask the grid a body would stand on (`is_walkable`), or ask
  what the navigator actually does.
- **A self-check is not a consumer.** An assertion proves a system is correct; it
  does not prove anything uses it. When every reader of a thing is a check, the
  thing is not wired up, and the check will say it is.

### What the fix was, and what the check had to survive

`_local()` now looks the outdoors up like any other space. Measured before and
after, by asking the navigator for three routes with the house between their ends:

    before  -> 1 waypoint each, all three with a leg through geometry
    after   -> 27, 35 and 34 waypoints, nothing hit

Reverting the line brings all three back, naming `wall wall_001` and
`wall wall_004` — the check is doing the work, not the fix's absence.

**Three versions of that check were green while proving nothing**, and each fails
in a way worth recognising:

- **"A path exists" is not reachability.** The first version asked `plan()` — the
  same function with the same straight-line branch — so a tree at (500, 500) was
  "reachable". Ask the grid a body would stand on, or ask what the navigator does.
- **A physics ray in `_ready()` sees an unpositioned world.** The first run from
  `_report()` reported a 0.5 m ray hitting a table at (2, 3, 2) — the node's
  position, not the body's. Cast-based checks belong in a scheduled stage; the
  cast in `_report()` is not wrong, it is early.
- **`plan()` does not include where the agent already is.** Counting legs from
  index 1 means a one-waypoint path has zero legs and the loop never runs. A
  canary — one cast that must hit something known — is what told the difference
  between "nothing was hit" and "nothing was looked at". It is still in the check.

**And the mutation test caught a fix of mine that was not one.** Objects ARE
outdoor obstacles; the function that builds the list appends them at the bottom.
Reading only its first line made them look missing, and switching the helper to
the one that folds objects in delivered them twice — thirteen duplicate rects and
no behaviour change. **The tell was that reverting the "fix" turned nothing red.**
Read the whole function; a fix that changes a count but not a path is not a fix.

## A grid that rasterises obstacles exactly is routing a POINT

`CozyLocalNav` grew its cells around obstacle rects and nothing else. No
inflation by the agent's radius, no erosion of the room polygon. So it answered
*can a point get from here to there* while the thing that has to get there is a
capsule `CozyCharacter.CAPSULE_RADIUS` (0.3 m) in radius. Two defects fell out of
that, and both were live:

- **A gap wider than a cell and narrower than the agent was a route to the
  planner and a wall to the body.** The agent walks at it, is stopped, waits,
  abandons the job, replans, and is handed the same route again.
- **A room polygon runs through wall CENTRELINES.** An 8 x 6 room measures
  48.0 m2 — centreline to centreline — so the grid's edge was the MIDDLE of every
  wall, and half a wall-thickness of wall was walkable space the collider filled.

The fix is the Minkowski sum, which is the textbook answer to exactly this
(Lozano-Perez & Wesley, *An algorithm for planning collision-free paths among
polyhedral obstacles*, CACM 22(10):560-570, 1979): grow the obstacles by the
agent's radius and the agent becomes a point.

**Measured, on the project's own house:**

    stuck  before ->  3.0 x82, 1.4 x34, 1.2 x30, 1.0 x30, 0.8 x30, 0.6 x30
    stuck  after  ->  0.0 x 4500          every one of 4500 frames
    resident      ->  GOING 1589 -> 1432, WORKING 2307 -> 2538
                      the same amount of activity, less of it spent walking

**Three things follow, and the last is the one that cost time.**

1. **`clearance` has no default.** A default of 0 would leave every existing
   call site rasterising with no room for the body — the bug — silently, at the
   one moment nobody looks: the call that was already written.

2. **The grid is COARSE, and the clearance is not the agent's width.** A cell is
   0.25 m and rasterising blocks every cell a grown obstacle touches at all, so
   the real threshold is the agent's width plus about a cell on each side, and a
   1.0 m doorway closes. Asserting only "narrower than the agent is refused"
   would give a case that fails for a reason nobody wrote down the day the cell
   size changes.

3. **Giving the grid clearance DELETES tight spaces, and nothing says so.**
   Inflating by 0.425 removed the house's 1.0 m stairwell landing entirely — the
   stair topped out on floor no agent could stand on, and **the only thing that
   noticed was an assertion written for it.** The existing check said:

       npc plan ground->upstairs: 33 waypoints, crosses floor=true   [OK]
       landing beside the stairwell: 1.00 m of floor, walkable=false [FAIL]

   `find_path` came back empty, `_local()` fell back to a straight line, and
   `crosses floor=true` stayed green while the navigator had stopped navigating.
   **A green assertion and a navigator that has given up look identical.** The
   landing is 2.0 m now — the stairwell moved 1 m west, run unchanged, so the
   stair is still 50.2 degrees and `ground->upstairs` went 33 -> 77 waypoints.

### The snap radius is a budget, not a search

`_nearest_walkable` spiralled out to 12 cells — three metres. Harmless while
obstacles were exact, because an agent was rarely far from a free cell. Once they
grow by the agent's clearance it stops being harmless: a resident standing in a
spot that has just been closed off is a couple of centimetres inside a grown
obstacle, and a spiral that reaches three metres turns that into a route to a
DIFFERENT place. It is 4 cells now.

**It had no assertion on it until mutation testing said so** — putting the spiral
back to 12 changed nothing in the suite. Writing the case took three attempts,
and the first two were wrong for the same reason: **the spiral reached a cell on
the far side of the wall first**, and a route that cannot reach its goal returns
empty whether or not the snap reached too far. The case had to wall off the wrong
side before it measured anything.

## The same measurement can be right and still fire at the wrong moment

One probe, one session, three attempts at timing, all three wrong:

- **A fixed frame samples a calm moment.** `--cozy-probe-npc-pathing` reported
  `blocking cast: nothing between the agent and waypoint N` while the same build
  at the same time had a resident stuck for hundreds of frames at `wp=2/29
  stuck=1.5`. The probe was correct and the moment was not.
- **"Not moving" is not the symptom.** The first watcher fired on a resident
  standing still for 3.5 s — at a workbench, `WORKING`, `stuck=0.0`, doing its
  job. The symptom is not moving *while trying to move*.
- **A jittering agent resets a stillness timer.** Gated on `GOING`, the watcher
  never fired at all: the resident moves a few centimetres often enough to reset
  the clock, and the agent's own `_stuck_time` accumulates per-frame movement
  instead.

**A probe that fires at the wrong moment does not report "unknown". It reports
"fine".** Three times in one session is not bad luck; it is what happens when the
trigger is chosen by reasoning rather than measured.

## Firing too EARLY reports "broken", and that is the same mistake facing the other way

The same wrong-moment fault, one level up and with the opposite verdict.

`_check_npc_work` carried a note explaining why §45's live chain was not asserted:
the resident "spends ten game hours there with `stuck` climbing to 1.5-3.0 ...
Both ends of the chain therefore stay untouched: **chest wheat 8 of 8, chest bread
0**." That observation was read off a run before the resident had done anything.

    first transfer the resident makes        frame 1372
    where the chest was read                frame  900

The chain runs. It ran the whole time, including under the configuration the note
was written about. **A check that fires before its subject exists does not report
"not yet"; it reports "broken", and the note was recorded as a debt for it.**

The first version of the replacement check made the SAME mistake at frame 900 and
reported `withdrew=false delivered=false` on a working chain. The second version
at frame 1700 reports `chest wheat 8 -> 6, bread 0 -> 1, 4 job(s)`.

**Two more things came out of writing it, and both were measured:**

- **`bread > 0` in the chest is NOT evidence the chain ran.** The resident spawns
  with a starter larder of three loaves (`_build_characters`), and `_haul` deposits
  what it carries BEFORE it withdraws anything. So a world whose chest starts
  EMPTY still ends with bread in it — and the first version of the check passed on
  exactly that world, agreeing with a chain that had never run. What cannot be
  produced that way is wheat LEAVING the chest, so the assertion requires both
  legs, and compares against what the chest actually held rather than against the
  constant that was supposed to fill it.
- **The stall and the chain are independent.** Reverting the clearance and the
  landing widening together reproduces the original stall exactly
  (`stuck` 3.0 x82, 1.4 x34, 1.2 x30 ...) **and the chain still completes four
  jobs**. The stall was real; it was never what stopped the production chain.

## `--quit-after` is not a frame budget

`--quit-after 4500` reaches physics frame **1883**, not 4500 — measured, and
stable across runs. A self-check stage numbered past that ceiling never fires at
all, and the run reports `pending=<stage>` and turns the schedule guard red.

Worse, the two counters are not fixed relative to each other: `--quit-after`
counts main-loop iterations and the physics frame advances with wall-clock, so a
faster machine reaches FEWER physics frames before quitting. A stage's frame
number is therefore a budget against an unknown ceiling, and the honest place for
a late stage is one measured against the real one.

## A category is not a member of the set it contains

`CozySchedule.ACTIVITY_POINTS` is the bridge from "what kind of thing should I be
doing" to "which interaction point do I want". It said:

    "work": "work"

`work` is a CATEGORY — doc #115: *"Schedule 只决定现在应该做什么类型的事情"*, the
schedule names the kind of HOUR and the Task System names the place. `work` is
also, separately, a POINT TYPE that a research table offers. Mapping the category
onto one member of the set it contains answered a question the trade was supposed
to answer, and it answered it for every trade at once.

    at 09:00   a woodcutter sought `work`
               a miner sought `work`
               a farmer sought `work`
               a hauler (trade point `store`) sought `work`

`work` is what a table offers, so all four were routed to a desk and the three
gathering trades added the day before could not do their own work in the game.
The tables said they could; the game did not.

**Why it stayed invisible.** Every job in `CozyJobDefs` had
`point_type: "work"` when that bridge was written, so the override was a no-op for
all of them. The rule was only ever exercised by the one case it was written for —
which is the same shape as `## A declared capability with no consumer is not a
feature`, one level up: not a row nobody reads, but a rule whose only reader is the
case it was designed around. **When a mapping takes a value from a set, ask what
happens on the day the set has more than one member.**

The block names no point type now (`""`, the same as `wake`), so the trade decides.
`tests/probe/work_priority_probe.gd` prints what each trade wants at each hour of
the day; it is what found this, and it is worth re-running before touching either
side of the bridge.

## A resident's preference is a LIST, and the first one that exists wins

`want_point_type()` returned a single string, and a string cannot express "and if
that is not there, this". A resident whose one preference had no free point stood
still and retried once a second — a trade with nothing ripe in front of it became
a resident doing nothing at all.

`want_point_types()` returns a ranked list and `_best_point(from, want)` takes the
first kind that HAS a free point, consulting distance only within that kind.

**Ranking first, distance second, and the order is not a detail.** Choosing the
nearest point of any acceptable kind would perform a trade only when the trade
happened to be closer than the alternative — that is not a priority, it is a coin
toss with a tape measure. The tiers, most wanted first: a critical need (which is
NOT a preference and does not queue behind the trade), then §45's container legs,
then the trade itself.

**And there is no single-string accessor.** One existed alongside the list for a
day; by the end of that day its only readers were the tests and a probe, kept
alive by a doc comment claiming the HUD used it. That is
`## A declared capability with no consumer` again, in the one place this project
is most tempted to allow it — a convenience wrapper. A display that wants one word
takes the first element; a decision that wants one word is the bug.

## A pickup radius is bounded by the SHORTEST reach, not by the longest

Things on the ground (2026-09-15) work like this: a felled tree or a killed
monster leaves a marker at the edge of whatever dropped it, on the side the player
is standing, and a pass over `drops` each frame moves whatever the player is
standing on into their ledgers.

The radius is the whole mechanic. Too long and every drop is taken on the frame it
appeared, which makes 掉在地上 and 直接进包 the same code with different comments —
the ledgers, the numbers and the moment are all identical. Too short and loot is a
pixel hunt. Nothing in the game can tell a right radius from a wrong one, because
both end with the wood in the pack.

**The bound comes from the shortest reach in the object table, not the one you are
looking at.** `_gather_from` refuses to work a node from further than its reach,
and a drop lands at that node's edge — so the gap between a player standing at the
limit of their reach and the thing they just knocked loose IS the reach. A tree's
is 1.3 m. A crop's is **0.8 m**, and a first version of this shipped a radius of
1.0 because 1.3 was the number in front of it. Harvesting a crop would have put
the wheat straight into the pack while felling a tree left something to walk to,
and nothing anywhere would have said so.

    pickup radius 0.6  <  crop reach 0.8  <  tree reach 1.3

`test_dropped_item` asserts the relation for EVERY gathered node rather than for
the tree, so the next row with a short reach cannot reintroduce it. **When a
constant is bounded by a table, the bound is the table's minimum, and a check that
names one row is a check that has stopped looking.**

## A drop that does not fit stays where it is

The bag has a capacity and the pack does not, so exactly one kind of drop can be
refused. The refusal is `CozyItemContainer.add_item` returning -1, and what
matters is where it goes from there.

**Taken-and-destroyed is the one outcome the player experiences as a loss.** They
watched a sword fall, they have no room, and it is not there — with nothing to
explain it and no way to get it back. The rule is therefore: take it only if it
fits, and remove it from the ground only after the ledger says it arrived. It
stays, with a line saying why, and it is still there when room is made.

Two ways to get this wrong that no state assertion can see: a drop that is taken
but NOT removed is taken again next frame (the same sword, forever), and a drop
that does not fit and is removed anyway is bug-shaped silence. Both are asserted,
and both were checked by breaking them on purpose.

**A per-frame "it did not fit" message is the same as no message.** `refused` is
one bool per drop, set once, and it is deliberately NOT saved — it is a fact about
what this session has already said, not about the drop.

**AND THE MESSAGE IS THE ONLY THING THAT BRANCH IS FOR, which mutation testing had
to say out loud.** `_tick_pickups` asks `fits_in` before taking a drop, and
`collect_into` asks it again — so replacing the outer test with `if false:`
changed NOTHING that any assertion could see: the drop was still refused, still
stayed on the ground, and was still there when room was made. The mutation came
back green, and the honest reading is not "the check is weak" but **"that branch
is the difference between a refusal and a refusal the player is told about."**

So the branch has its own assertion now: after a refused pickup the HUD message
NAMES the thing that did not fit. **Defence in depth makes the outer layer
untestable by behaviour, and the only way to test it is to test the thing it alone
produces — here, a sentence.**

## Compare a loaded payload by READING it, not by stringifying it

A save round trip gives every number back as a float. `0` on the way out is `0.0`
on the way in, and the two are unequal as text and equal as numbers — this is
written at the top of `CozySaveManager` and it is still the thing that gets
forgotten.

The first version of the drop section in `_check_save_load` compared
`JSON.stringify(live_payload)` with `JSON.stringify(loaded_payload)` and reported
a perfectly faithful round trip as `(CHANGED)`. The fix is not a tolerance: it is
to put both payloads through the drop's own `apply_dict` and compare what the two
drops then say about themselves. That asserts the property that matters — the file
is READABLE and yields the same thing — where string equality asserted a
coincidence of formatting.

**The general shape: a serialiser round trip is a claim about two readers
agreeing, so test it by reading.** Comparing the bytes tests the writer twice.

**AND A ROUND TRIP IS SYMMETRIC, SO IT CANNOT SEE A FIELD THAT IS NEVER WRITTEN
AT ALL.** The drop section compares `live_payload` against `loaded_payload`, and
stripping the position out of `to_dict` broke BOTH sides identically: both loaded
at the origin, agreed perfectly, and the check went green. Mutation testing found
it — the unit suite caught it only because that case compares against the position
it PLACED the drop at (`Vector3(-3.5, 0.0, 8.25)`), which is a constant rather
than a comparison.

    live   payload without "position"  -> drop at (0,0,0)
    loaded payload without "position"  -> drop at (0,0,0)   -> equal, green

The fix is one line and it is the same rule the production chain learned: **compare
against something the subject cannot forge.** The drop's expected position is
`DROP_MARK_AT`, the constant this check chose, so the assertion is now that the
loaded drop is *there* rather than that it agrees with its twin.


## A check written from the drawing rather than from the failure is a tautology

The item panels' layout check runs in two stages (`item_panels_open` at frame 600,
`item_panels_layout` at 640) because `Control.size` does not exist until a layout
pass has run, and a container SKIPS its hidden children. That part is fine. What is
worth recording is that the first version of the check asserted THREE things and
**two of them could never fail**:

    "the panel is at least as wide as it needs"
        get_combined_minimum_size() <= size
        ALWAYS TRUE — a container never lays a child out below its own minimum.

    "the panel fits the column it lives in"
        size.x <= column.size.x
        ALWAYS TRUE — the column GROWS to hold its children.

    "everything is inside the window"
        real.

Measured, not reasoned about: with an 88 px cell instead of 68 the column simply
went from 300 px to 354 px, **both dead clauses stayed true**, and the panel ran off
the right-hand edge of a 1280 px window — the exact failure the check was written
for, reported as `[OK]`.

**The tell is what the clauses were made of.** Both dead ones describe what the
layout rules DO ("it is laid out inside the column"), and anything derivable from a
rule cannot witness that the rule was violated. The live one names a FAILURE — "the
right-hand column of cells is not on the screen" — and a failure is something a
world can be in.

The fix keeps the two things that can actually be false:

    the content needs more room than the width the file DECLARES for it
    the column carrying that overflow is off the edge of the window

Both go red under the same mutation, and both are red for the right reason.

**And this is the same lesson as `## A declared capability with no consumer`, one
level up.** There it was a field nobody reads; here it is a clause nothing can
falsify. In both cases the artifact is present, well written, and load-bearing in
appearance only — and the way to find either is the same: **break the thing it is
supposed to be watching, and see whether it notices.**
