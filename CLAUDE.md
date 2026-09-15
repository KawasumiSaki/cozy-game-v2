# CozyVale V2 — working instructions

A pixel-art life sim over a **real 3D spatial core**. Godot 4.7.2, GDScript.

---

## Resuming: the user says one line, you run the whole loop

If the user opens a session and says **"继续做这个项目"**, **"接着做"**, or names a
block, **do not ask what to do**. Run this loop yourself:

```
read 00-目录.md            -> where things stand, what is next
read the current block note -> deliverables, DoD, code, current state, assertions
run the baseline self-check -> if it is red, fix THAT first; do not stack work
do the next step in 当前站位
follow the finish protocol (five places)
report: what changed, decisions, bugs hit, assertion output, next step
```

**Stop and ask only** when: art direction or assets are involved, when a change
affects how the game *feels* (camera, controls), or when the doc's hard rules
conflict with the code. Everything else — decide it and report.

---

## TWO LANES, AND WHICH ONE YOU ARE ON DECIDES WHAT YOU READ

This repo is worked by **two lanes at once**, on the same remote, with their own
agents. The split is by FILE, and the boundary is the thing to know first because
crossing it does not raise an error — it quietly overwrites.

| Lane | Owns | Starts by reading |
|---|---|---|
| **Homestead** (world, residents, UI, save, environment) | `world/ building/ character/ ui/ core/ render/` | the two Obsidian files below |
| **Dungeon** (maps, monsters, combat, equipment, affixes, skills) | `dungeon/ combat/ items/` + its rows in `data/` | **`docs/DUNGEON_LANE.md`** |

> **IF YOU ARE ON THE DUNGEON LANE, READ `docs/DUNGEON_LANE.md` AND STOP READING
> THIS SECTION.** That document is self-contained, and it is self-contained ON
> PURPOSE: the Obsidian paths below are on Willow's machine only, so they are not
> a thing a second person can follow.

`main.gd` is the ONE junction between the two — `docs/DUNGEON_LANE.md` §3 has the
three rules for touching it.

---

## Read these two files before doing anything (HOMESTEAD lane)

```
C:\Users\15598\Documents\Obsidian Vault\01-项目\xiansuwd\01-板块\00-目录.md
C:\Users\15598\Documents\Obsidian Vault\01-项目\xiansuwd\01-板块\<板块ID>-<名称>.md
```

The first gives status and the next step. The second is self-contained:
deliverables, definition of done, code locations, current state, and the
assertions that must pass. **That is enough to start work.**

Do **not** read the architecture master (113 KB, in `00-架构总纲/`) unless you
are changing the architecture itself.

If you need recent context — what was decided and what already broke — read the
last couple of entries in
`01-项目\xiansuwd\02-开发日志\游戏开发日志.md`. Faster than reading code.

---

## Baseline check, before touching anything

```bash
GODOT="D:/privacy/Openclaw/Godot-4.7.2/Godot_v4.7.2-stable_win64.exe"

# ① smoke: expect 168 OK / 0 FAIL / 0 ERROR
"$GODOT" --headless --path D:/cozy/cozy-game-v2 --quit-after 4500

# ② unit: expect 28 suites / 237 cases / 3271 checks / 0 failures
"$GODOT" --headless --path D:/cozy/cozy-game-v2 --script res://tests/unit/run.gd

# ③ after adding any `class_name`, import first
"$GODOT" --headless --path D:/cozy/cozy-game-v2 --import
```

**THE REPO IS AT `D:\cozy\cozy-game-v2`.** It moved off `C:` on 2026-09-12, and
this file said `C:/Users/15598/cozy-game-v2` for three days afterwards — which is
the kind of staleness that wastes an afternoon: the command runs, finds nothing,
and the error is about a directory rather than about the code.

**If the baseline is red, fix that first.** Do not stack new work on it.
**The numbers above are a hypothesis, not a fact — re-run them.** They were written
on 2026-09-15 and this project has already been bitten twice by a doc number
nobody re-measured.

---

## Iron rules

- **Code and comments in English.** Obsidian notes are Chinese.
- **Never auto-launch a GUI.** Verify headless only; the assertion suite is
  stricter than looking at a screen. Launch the editor only when asked.
- **Every existing assertion must stay green**, and each block adds at least one
  *assertion* — a pass/fail check, not a print.
- **Intent → State → Solver → Generator → Node.** UI never touches a mesh.
- **Local edits rebuild locally.**
- **Assets may be committed, but only with their source recorded** — origin,
  author, and a licence that permits REDISTRIBUTION (MIT / CC0 / CC BY) in
  `docs/CREDITS.md`. **An asset whose licence is unclear is not accepted.**
  (This REPLACED "art is all placeholder" on 2026-09-15; the placeholder rule
  had finished doing its job and the licence rule never goes away.)
- **Camera is locked** (yaw **180** / pitch **40**, perspective). `L` is a debug
  unlock only. yaw was MEASURED, not chosen: the door is cut into the `z = 0`
  wall, so the front of a building faces `-Z` and a camera at `+Z` opens the
  game on the back of the house.
- **Diagnose with a probe, don't guess.** Measure before claiming a cause.

---

## Before changing any subsystem's behaviour

Read `docs/INVARIANTS.md`. It holds the rules that assertions **cannot** derive,
plus the bugs this project has already paid for, each with the assertion that
caught it. The code can pass every test while violating them, and it will look
fine until it isn't.

**Most of those bugs were found by an assertion, not by looking at the screen.**
Several are invisible in a still frame. That is the whole argument for the
discipline — and its corollary, which took this project three separate bugs to
learn: **break the code on purpose and see what notices.** A check nobody has
seen fail is a check nobody has evidence about.

---

## Finishing a block

Follow `01-项目\xiansuwd\03-流程\更新方案.md`. Five places, none optional:

1. The block note — status, **real assertion output**, next step
2. `00-目录.md` — status table, current position, new debt
3. The dev log — decisions, **bugs hit**, verification
4. `docs/ROADMAP.md` — the mirror kept next to the code
5. Commit and push

Status only moves ⬜ → 🚧 → ✅. No skipping the middle, and ✅ requires assertion
output as evidence.

---

## Where everything is

| | |
|---|---|
| Block index (start here) | Obsidian `01-板块/00-目录.md` |
| Block notes | Obsidian `01-板块/<ID>-<名称>.md` |
| Development log | Obsidian `02-开发日志/游戏开发日志.md` |
| Finish protocol | Obsidian `03-流程/更新方案.md` |
| Ready-made prompts | Obsidian `03-流程/开工提示词.md` |
| **Dungeon lane — read this first if that is your lane** | **`docs/DUNGEON_LANE.md`** |
| The dungeon/equipment design doc (sections 1-66) | `docs/design/副本世界_装备词条掉落系统_V1.0.md` |
| **Invariants — read before changing behaviour** | `docs/INVARIANTS.md` |
| Art contract (camera, pixel density, import) | `docs/ART_PROFILE.md` |
| Status table | `docs/ROADMAP.md` |
| Godot skills (MIT, third-party) | `.claude/skills/` |
| Godot binary | `D:\privacy\Openclaw\Godot-4.7.2\Godot_v4.7.2-stable_win64.exe` |
| Python | `D:\Anaconda\python.exe` |

---

## Asking the user vs deciding alone

**Stop and ask** when a decision changes how the game *feels* or *looks*, when
the art direction is involved, or when the doc's rules would have to change.

**Decide alone** for anything with a clear right answer — and then report,
including what you tried that did not work.

Two habits worth keeping, both learned here:

- When a fix does not move the number, say so and record the attempt rather than
  quietly dropping it.
- When a test fails after a change you believe is correct, **check the test
  first**. That has been the answer more than once.
