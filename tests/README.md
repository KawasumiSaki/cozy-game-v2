# tests/

> **The self-check, and where its data lives.**
> Read `docs/PROJECT_LAYOUT.md` §6 first: this tree is deliberately incomplete.

---

## Running it

**Nothing new to learn. The entry point is the game:**

```bash
GODOT="D:/privacy/Openclaw/Godot-4.7.2/Godot_v4.7.2-stable_win64.exe"
"$GODOT" --headless --path D:/cozy/cozy-game-v2 --quit-after 4500
```

**Expect `118 OK / 0 FAIL / 0 ERROR`.**

The game runs its own checks when launched headless. There is no separate test
binary, no framework invocation, and no second command to remember — a deliberate
property, and one that must not be traded away for tidiness.

```bash
# Occlusion probe: eight positions plus a camera-angle sweep
"$GODOT" --headless --path D:/cozy/cozy-game-v2 --quit-after 400 -- --cozy-probe-occlusion

# Unit tests — a SEPARATE entry point, no world booted
"$GODOT" --headless --path D:/cozy/cozy-game-v2 --script res://tests/unit/run.gd
```

**Two commands, and they do different jobs.** The game's self-check boots a real
world and drives it for ~1,880 physics frames; the unit runner boots nothing and
finishes in under a second. That split is the whole point of `unit/`.

---

## What is here

```
tests/
├── self_check.gd     The schedule: which stages exist, when each is due, and
│                     whether it ran. It owns everything AROUND the checks.
├── smoke/            (empty) Integration runs that boot the real world.
├── unit/             Pure-logic tests. 6 suites, 31 cases, 718 checks.
│   ├── run.gd            The entry point. `--script` it; main.gd never sees it.
│   ├── unit_test.gd      ~40 lines of assertion helpers. No framework.
│   └── test_*.gd         One file per subject.
└── fixtures/
    └── art/          Asset-library test data. 5 definitions: 3 APPROVED,
                      1 RAW, 1 deliberately malformed.
```

**The checks themselves are NOT here yet.** All 40 of them are still methods on
`Main`, because they read `terrain`, `building`, `npc`, `hud`, `camera` and
`scatter` as members of it. Moving them is an architecture change rather than a
file move, and doing it inside a tidy-up is how a tidy-up breaks a working
project. It is recorded as debt #1 in `docs/PROJECT_LAYOUT.md` and gets its own
session.

What is already separated is the part that cost nothing to separate: **the
schedule**. It used to be seven boolean members plus a chain of `if` blocks in
`Main._run_headless_stages()`. Adding a check meant editing two places. Now it is
one line in `_build_self_check()`.

---

## Two things that will bite you

### ⚠️ The frame budget: `--quit-after` is not physics frames

`--quit-after` counts **idle** frames, and under headless the physics tick
advances at roughly **0.42** of that rate. So the 4500-frame baseline reaches
only about **physics frame 1880**.

**A stage scheduled past that never fires, and it fails silently** — no error, no
warning, and the suite looks exactly as green as it does when the stage passed.
Scheduling one at 3200 against a 4500 baseline quietly retires a check. (This is
not hypothetical: the first draft of the schedule assertion did exactly that.)

Two guards, because one is not enough:

- `self-check schedule:` asserts every **ungated** stage ran. It sits at frame
  1600, below the budget.
- `self-check at exit:` prints the same thing from `_exit_tree()`, so a run too
  short to reach the assertion still reports what never ran.

### ⚠️ A new `class_name` needs one `--import` run

`tests/self_check.gd` declares `class_name CozySelfCheck`. Until the project has
been imported once, every reference to it fails to parse with
`Identifier "CozySelfCheck" not declared`:

```bash
"$GODOT" --headless --path D:/cozy/cozy-game-v2 --import
```

---

## What the first batch caught

Two of the first 72 checks FAILED, and both times **the test was wrong, not the
code** — which is the useful direction for a first batch:

- `accepts_building()` is true for **PREPARED as well as BUILDABLE**. The
  assumption that only BUILDABLE qualifies came from the doc's four-step chain
  (`Grassland -> CLEARED -> PREPARED -> BUILDABLE`), but the code deliberately
  treats "levelled and consolidated" as good enough.
- `from_name()` falls back to NATURAL for a name it does not know. That fallback
  is **silent**, but the direction is the safe one — refusing to build beats
  allowing it. The real risk it leaves is a typo in a `default_buildability`
  string, and that is now caught **at the source**:
  `test_terrain_materials.every material names a real state`.

The teeth test worth keeping: moving `farmland` from the end of `ORDER` into the
middle produces six failures, including `stone resolves to index 3: got 4` —
which is the saved-world corruption itself, named.

---

## House rules

| Rule | Why |
|---|---|
| **One assertion prints one line ending in `[OK]` or `[FAIL, reason]`** | Counting is done by grepping. A `[FAIL` with a reason must not be written `[FAIL]`, or the count misses it — see the warning in `docs/ROADMAP.md` |
| **A failure must say WHY** | Same rule as the terrain gate (doc §72). "FAIL" alone costs the next person an hour |
| **A check that changes the world must restore it** | Two checks once emptied a live container and went green on an empty world |
| **Test data belongs in `tests/fixtures/`, not in `assets/`** | An assertion counting what sits in the production asset folder measures the FOLDER, not the loader |
| **Paths are parameters** | `CozyAssetLibrary.load_dir(path)` — production passes `ART_ROOT`, the check passes `FIXTURE_ROOT` |

---

## What goes here next

In the order the project will actually need it:

1. ~~**`unit/` — pure logic, no world.**~~ **DONE 2026-09-12.** Six suites cover
   the material table (including the APPEND-ONLY rule, which until now rested on
   a single boolean inside an integration check), buildability, the animation
   selector, the schedule bridge, the appearance table, and intent shapes.

   **Next candidates**, found while writing these: `CozyMaterials.cost_for()`
   (wall cost from volume — pure arithmetic with a `ceilf` on the end),
   `CozyTraits` / `CozySkills` clamping, and `CozyWallAssembly.blocks_for_span()`
   (the running-bond geometry, which currently has an integration check that
   boots a world to compare block counts).
2. **Extract the checks** out of `Main`, one domain at a time, starting with the
   ones that need the least world.
3. **A framework** (GUT / GdUnit4) — only once `unit/` has enough in it to be
   worth the addon. The 118 assertions here are integration checks that boot a
   real world for thousands of frames; a unit-test framework does not run those.
