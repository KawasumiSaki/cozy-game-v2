# Project Layout

> **What lives where, and the rule that decides where new code goes.**
> Read this before adding a file. It is cheaper than moving one afterwards.
>
> Updated 2026-09-12. Code: 68 GDScript files, ~13,950 lines.

---

## 1. The organizing principle

**Folders are FEATURE DOMAINS, not file types.**

There is no `scripts/`, no `managers/`, no `utils/`. A file lives with the system
it belongs to, so that "what does the terrain do" is answered by opening one
folder rather than by grepping the tree. Two consequences worth stating:

- A domain folder may hold both data and behaviour (`data/` is pure tables,
  but `world/terrain/` holds the tables it derives from *and* the code).
- When a folder grows past ~10 files, it grows a **subfolder by subsystem**, not
  a new top-level name. `world/` did exactly that.

---

## 2. The tree

```
cozy-game-v2/
├── project.godot           Godot project. 1280x720, canvas_items stretch.
├── main.tscn               The ONLY scene. Everything else is built in code.
├── main.gd                 Scene root: wiring, input, and the self-check.
│
├── core/                   Cross-cutting primitives with no domain.
│   └── time_system.gd          The clock. Seasons, hour, is_dark().
│
├── data/                   Pure data tables. No behaviour, no nodes.
│   ├── appearance.gd           Character factory vocabulary (ART-14).
│   ├── buildings.gd            Wall material definitions and cost.
│   ├── jobs.gd                 Trades and what point type each seeks.
│   ├── materials.gd            Building materials AND the item vocabulary.
│   ├── objects.gd              Furniture definitions.
│   ├── recipes.gd              Production recipes.
│   ├── schedule.gd             The day. The activity -> point bridge.
│   ├── skills.gd               Skill ids and clamping.
│   └── traits.gd               Trait effects.
│
├── building/               Everything about a structure.
│   ├── state/                  WallState / SlabState / StairState / RoofState
│   ├── building_intent.gd      How a structure is ASKED for.
│   ├── building_system.gd      The rules gate. Nothing bypasses it.
│   ├── wall_*.gd               Generator, connection solver, assembly.
│   ├── roof*.gd  slab.gd  stair.gd  opening.gd
│   └── outline_generator.gd    Polygon -> wall intents.
│
├── world/                  Everything the world IS.
│   ├── terrain/                Cells, chunks, materials, raster, renderer.
│   ├── spatial/                Floors, rooms, portals, room graph, navigation.
│   ├── objects/                WorldObject, containers, inventory, interaction.
│   ├── npc/                    Resident state.
│   ├── scatter/                Vegetation rules, biomes, the art seed.
│   ├── vfx/                    Effect definitions and instances.
│   └── save/                   Serialization.
│
├── dungeon/                A dungeon — which is another batch of walls.
│   ├── dungeon_layout.gd       Outlines -> the walls to build, resolved against
│   │                           each other. No new State, no new Node.
│   └── dungeon_blueprint.gd    The document: what a dungeon file may say, and
│                               what it may not. Refuses what it cannot check.
│
├── character/              Characters, in the 3D-space-plus-sprite sense.
│   ├── character_body.gd       Position, collision, sprite, animation.
│   ├── character_visuals.gd    Appearance -> sprite sheet -> animation choice.
│   └── npc_agent.gd            The FSM. Extends CozyCharacter.
│
├── render/                 Anything that turns state into pixels.
│   ├── camera_rig.gd           The LOCKED camera.
│   ├── occlusion.gd            Fade what blocks the camera->player ray.
│   ├── pixel_art.gd            Procedural PLACEHOLDER textures.
│   ├── asset_definition.gd     Asset metadata contract.
│   └── asset_library.gd        Loads, validates, and gates by approval state.
│
├── ui/                     The interface. Never touches meshes or state directly.
│   ├── hud.gd                  Top bar, tool palette, clock.
│   ├── context_menu.gd         Right-click menu, built from a collider probe.
│   ├── npc_panel.gd            The resident panel.
│   └── ui_theme.gd             Colours, sizes, styleboxes.
│
├── assets/art/             The asset tree (ART-10). Mostly EMPTY by design.
│   ├── bible/ references/ palettes/     Human-facing source material.
│   ├── pixel/                            Sprites, by category.
│   ├── building/                         Materials, modules, roofs, openings.
│   ├── atlases/                          Packed sheets, by category.
│   └── generated/{ai_raw,cleaned,approved}/   The AI asset pipeline.
│
├── tests/                  The self-check. See tests/README.md.
│   ├── self_check.gd           The stage schedule. The checks themselves are
│   │                           still on Main — see debt #1 below.
│   ├── smoke/                  (empty) Runs that boot the real world.
│   ├── unit/                   Pure-logic tests, run by `unit/run.gd`.
│   ├── probe/                  Standalone MEASUREMENTS — they print numbers and
│   │                           assert nothing. Run one with `--script`.
│   └── fixtures/art/           Asset-library test data.
│
└── docs/                   The contracts. Read before changing behaviour.
    ├── INVARIANTS.md          22 bugs this project already paid for.
    ├── ART_PROFILE.md         Camera, pixel density, import rules, pipeline.
    ├── ROADMAP.md             Status table + locked decisions.
    └── PROJECT_LAYOUT.md      This file.
```

---

## 3. Where does new code go?

Answer in order; the first match wins.

| If the new thing is… | It goes in… |
|---|---|
| A table of ids, costs, or definitions | `data/` |
| About walls, floors, roofs, stairs, openings | `building/` |
| About land, rooms, navigation, objects, residents | `world/<subsystem>/` |
| About a dungeon's layout or generation | `dungeon/` |
| About a character's body, look, or behaviour | `character/` |
| About how something is drawn or lit | `render/` |
| A panel, menu, or widget | `ui/` |
| A primitive with no domain (clock, math, ids) | `core/` |
| Light on an existing system | **The folder that owns the system** |

**The last row is the one that matters.** There is no `utils.gd` and there should
never be one — a helper that "everything uses" is a helper that belongs to
nobody, and it is where the rule the project cares about quietly goes to die.

### The rules a file must respect wherever it lives

| Rule | Source |
|---|---|
| **Intent → State → Solver → Generator → Node** | doc §1.4 |
| **UI never touches a Mesh or a Cell** | doc §70 |
| Code and comments in **English** | Willow 2026-09-11 |
| **No `randf()`** — use `CozyArtSeed` | doc §53 |
| A new subsystem ships with **at least one assertion** | project protocol |

---

## 4. Naming

| Thing | Convention | Example |
|---|---|---|
| Class | `CozyPascalCase` | `CozyTerrainSystem` |
| File | `snake_case.gd`, named for the class | `terrain_system.gd` |
| Private member / method | leading underscore | `_dirty`, `_till_cell()` |
| Assertion function | `_check_<thing>()` | `_check_farming_chain()` |
| Probe function | `_probe_<thing>()` | `_probe_yaw_sweep()` |
| Data table constant | `SCREAMING_SNAKE` | `MATERIALS`, `ORDER` |
| Test fixture | `<name>_draft.json` / `<name>_01.json` | `malformed_draft.json` |

> **Names in this project are engine-generated** (`@Node3D@88`), so a node's
> `name` identifies nothing. Identify by the **class of the parent**, which is
> why the probe helpers all work that way (`_describe_fadable`).

---

## 5. Documentation map

Two homes, and the split is deliberate.

| Document | Home | Read it when |
|---|---|---|
| `docs/INVARIANTS.md` | **Repo** | **Before changing any subsystem's behaviour** |
| `docs/ART_PROFILE.md` | **Repo** | Before producing or importing art |
| `docs/ROADMAP.md` | **Repo** | To see status next to the code |
| `docs/PROJECT_LAYOUT.md` | **Repo** | Before adding a file |
| 《无冕之乡》技术架构 V2.2 | Obsidian | Only when changing architecture |
| Block index + current position | Obsidian | **Every session, first** |
| Handoff (`交接.md`) | Obsidian | Every session, first |
| Development log | Obsidian | To see why something is the way it is |

**Repo docs are contracts the code depends on. Obsidian docs are read by a human
between sessions.** When the two disagree about *behaviour*, the repo wins;
about *intent*, Obsidian wins.

---

## 6. Organizational debt

Honest list. These are known and not yet fixed.

| # | Debt | Size |
|---|---|---|
| 1 | **`main.gd` is 3,879 lines — 28% of the codebase.** ~1,780 of those are the headless self-check (40 `_check_*` functions + 6 probes) | 🔴 the real problem |
| 2 | ~~Test fixtures live in the production asset tree~~ — **FIXED 2026-09-12.** Moved to `tests/fixtures/art/`, and `CozyAssetLibrary.load_dir()` takes the path as a parameter: production passes `ART_ROOT`, the check passes `FIXTURE_ROOT`. Deleting the fixtures from `assets/art` had been impossible without breaking the count assertion — which is the tell that the assertion was measuring the folder rather than the loader | ✅ |
| 3 | The self-check's **schedule** is separated (`tests/self_check.gd`), but its **40 checks** are still methods on `Main` | 🟡 half done |
| 4 | `project.godot` and `README.md` still say 640×360; the project has run at 1280×720 since 2026-09-12 | 🟢 cosmetic |
| 5 | 47 markdown files but no `CHANGELOG`. History lives in the Obsidian dev log, which is not in the repo | 🟢 |

**Why #1 has not been fixed yet:** the checks read `terrain`, `building`, `npc`,
`hud`, `camera`, `scatter` and more as members of `Main`. Extracting them means
introducing a context object and re-pointing 40 functions — an architecture
change, not a file move, and it should be done deliberately rather than as part
of a tidy-up.

---

## 7. Verifying a move

Moving a `.gd` file in Godot is not free: `res://` paths in `preload()`/`load()`
and `.tscn` ext_resource entries are strings, and a broken one is a runtime error
rather than a compile error.

**The self-check is the safety net.** After any move:

```bash
GODOT="D:/privacy/Openclaw/Godot-4.7.2/Godot_v4.7.2-stable_win64.exe"
"$GODOT" --headless --path D:/cozy/cozy-game-v2 --quit-after 4500
```

Expect **117 OK / 0 FAIL / 0 ERROR**. A path that broke shows up as a FAIL or a
SCRIPT ERROR, not as a silent nothing.

Two extra rules learned here:

- **A new `class_name` needs one `--import` run** before anything can reference
  it, or every reference fails to parse.
- **`.uid` files are tracked** and must move with their script.
- **`--quit-after` counts IDLE frames, not physics frames**, and under headless
  the physics tick advances at roughly **0.42** of that rate: a 4500-frame run
  reaches about physics frame 1880. A scheduled stage past that never fires, and
  it fails *silently*. See `tests/README.md`.

## 8. What "professional" meant here

Willow asked which layout a studio would use. The honest answer, and the one
that shaped this document:

| Practice | Do pros do it? | Done here? |
|---|---|---|
| Feature-domain folders, not `scripts/`+`sprites/` | Yes, consensus | ✅ already |
| Tests in their own tree | Yes, universally (GUT / UTF / Unreal Automation) | ✅ `tests/` |
| Fixtures out of the production asset tree | Yes | ✅ 2026-09-12 |
| Production paths injected, not hard-coded | Yes | ✅ `ART_ROOT` / `FIXTURE_ROOT` |
| Tests never in the main scene script | Yes | ❌ **debt #1** |
| A unit-test framework | Yes, once there is unit logic to test | ⏳ `unit/` is empty |

**The disagreement worth recording:** the self-check here is an *integration
smoke test* — it boots the real world for thousands of frames. A framework like
GUT runs unit tests and would not help with it. Studios keep both layers, and
this project currently has only the second. The next useful move is not a
framework; it is writing the first `unit/` tests for logic that is already pure
and already untested. See `tests/README.md`.
