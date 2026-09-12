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
```

---

## What is here

```
tests/
├── self_check.gd     The schedule: which stages exist, when each is due, and
│                     whether it ran. It owns everything AROUND the checks.
├── smoke/            (empty) Integration runs that boot the real world.
├── unit/             (empty) Pure-logic tests. Nothing here yet.
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

1. **`unit/` — pure logic, no world.** Several real candidates already exist and
   have NO test today: `CozyTerrainIntent.cells()` shape resolution,
   `CozyTerrainMaterials.index_of()` (the APPEND-ONLY rule currently rests on a
   single boolean inside an integration check), `CozyCharacterVisuals.select()`
   (already a pure function), `CozyAppearanceDefs.normalise()`.
2. **Extract the checks** out of `Main`, one domain at a time, starting with the
   ones that need the least world.
3. **A framework** (GUT / GdUnit4) — only once `unit/` has enough in it to be
   worth the addon. The 118 assertions here are integration checks that boot a
   real world for thousands of frames; a unit-test framework does not run those.
