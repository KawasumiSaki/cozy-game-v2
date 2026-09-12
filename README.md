# 《无冕之乡》 (CozyVale V2)

> **Real Space Under the Hood, Pixel Art on the Surface.**
>
> Home sim × party loot ARPG × procedural fantasy building × pixel 3D.
> Repo name is historical; the game is 《无冕之乡》.

A pixel-art life / adventure / building sim. The world genuinely exists in 3D —
X/Y/Z, real floors, real occlusion, real collision — while everything the player
sees is pixel art.

Rebuilt from scratch on the architecture in 《无冕之乡》技术架构 V2.2 (Obsidian vault,
$00-架构总纲/$; V2.1 archived under ).
The previous 2D prototype lives on separately in `~/cozy-game` and is **not**
the ancestor of this code.

**Current position: all of it is in prose in the Obsidian vault**
(`01-项目/xiansuwd/`), which is where a session starts. The repo carries the
contracts the code depends on (`docs/`).

---

## Why 3D underneath

The original plan was a pure 2D tilemap with Y-sorting. That works fine until
you want free building, multi-floor houses, furniture placed at any angle, and
NPCs walking upstairs — then screen-Y simply cannot express the real spatial
relationship between two entities on different floors.

So: **use 3D to solve space, use pixel art to solve looks.**

---

## Layout

**The full layout, with the rule that decides where new code goes, is in
[`docs/PROJECT_LAYOUT.md`](docs/PROJECT_LAYOUT.md).** In short:

```
cozy-game-v2/
├── main.tscn / main.gd    # the ONLY scene; everything else is built in code
├── core/                  # clock, and primitives with no domain
├── data/                  # pure data tables — no behaviour, no nodes
├── building/              # walls, floors, roofs, stairs, openings
├── world/                 # terrain · spatial · objects · npc · scatter · vfx · save
├── character/             # body, appearance, the NPC FSM
├── render/                # camera, occlusion, placeholder art, asset library
├── ui/                    # hud, context menu, resident panel, theme
├── assets/art/            # the asset tree — mostly empty by design
└── docs/                  # the contracts: INVARIANTS, ART_PROFILE, ROADMAP, LAYOUT
```

Folders are **feature domains, not file types**. There is no `utils/`.

## Axis convention

The design doc writes height as **Z**; Godot is **Y-up**. This project maps
doc Z onto Godot +Y: `doc(x, y, z) -> godot(x, z, y)`. Same meaning, different
label.

## Running

```bash
# Interactive
godot --path cozy-game-v2

# Headless self-check. Expect 117 OK / 0 FAIL / 0 ERROR.
godot --headless --path cozy-game-v2 --quit-after 4500

# Occlusion probe: eight positions plus a camera-angle sweep
godot --headless --path cozy-game-v2 --quit-after 400 -- --cozy-probe-occlusion
```

Controls: `WASD` move · `B` build mode · `TAB` cycle tool · `1-9`/`0` tools
(`Shift+1..0` for the second ten) · wheel zoom.

**The camera angle is LOCKED** (doc E.1.1). `L` unlocks it for debugging only —
no production asset may ever be authored from a view that produces.

Renamed 2026-09-12: the game is now **_无冕之乡_**. The repo keeps the
`cozy-game-v2` name.

## Art

**All art is a placeholder.** Textures are generated procedurally at runtime.
No real assets are committed. When pixel-art materials arrive, only
`render/pixel_art.gd` and `data/materials.gd` change — game logic is untouched.
