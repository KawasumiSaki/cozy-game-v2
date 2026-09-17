# cozy-game-v2

A pixel-art life / adventure / building sim built in Godot 4.

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
├── docs/                  # the contracts: INVARIANTS, ART_PROFILE, ROADMAP, LAYOUT
│   └── design/            # the design prose — architecture, per-system specs, art templates
└── tests/
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

## Art

Most textures are generated procedurally at runtime. The few real assets that
are committed are listed with source, author and licence in
[`docs/CREDITS.md`](docs/CREDITS.md) — an asset goes in only if its licence
allows redistribution.

When pixel-art materials arrive on a larger scale, only `render/pixel_art.gd`
and `data/materials.gd` change — game logic is untouched.
