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

## Read these two files before doing anything

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
D:/privacy/Openclaw/Godot-4.7.2/Godot_v4.7.2-stable_win64.exe \
  --headless --path C:/Users/15598/cozy-game-v2 --quit-after 4500
```

Expect `exit=0`, no `ERROR`/`WARNING`, and every assertion `[OK]`.
**If the baseline is red, fix that first.** Do not stack new work on it.

---

## Iron rules

- **Code and comments in English.** Obsidian notes are Chinese.
- **Never auto-launch a GUI.** Verify headless only; the assertion suite is
  stricter than looking at a screen. Launch the editor only when asked.
- **Every existing assertion must stay green**, and each block adds at least one
  *assertion* — a pass/fail check, not a print.
- **Intent → State → Solver → Generator → Node.** UI never touches a mesh.
- **Local edits rebuild locally.**
- **Art is placeholder.** `render/pixel_art.gd` is the boundary; nothing real is
  committed.
- **Camera is locked** (yaw 45 / pitch 52). `L` is a debug unlock only.
- **Diagnose with a probe, don't guess.** Measure before claiming a cause.

---

## Before changing any subsystem's behaviour

Read `docs/INVARIANTS.md`. It lists the rules that assertions **cannot** derive —
sixteen invariants and fifteen bugs this project has already paid for. The code
can pass every test while violating them, and it will look fine until it isn't.

Thirteen of those fourteen bugs were found by an assertion, not by looking at the
screen. Several are invisible in a still frame.

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
