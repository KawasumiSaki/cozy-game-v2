# CozyVale V2

> **Real Space Under the Hood, Pixel Art on the Surface.**

A pixel-art life / adventure / building sim. The world genuinely exists in 3D —
X/Y/Z, real floors, real occlusion, real collision — while everything the player
sees is pixel art.

Rebuilt from scratch on the architecture in 《游戏 V2 技术架构》.
The previous 2D prototype lives on separately in `~/cozy-game` and is **not**
the ancestor of this code.

---

## Why 3D underneath

The original plan was a pure 2D tilemap with Y-sorting. That works fine until
you want free building, multi-floor houses, furniture placed at any angle, and
NPCs walking upstairs — then screen-Y simply cannot express the real spatial
relationship between two entities on different floors.

So: **use 3D to solve space, use pixel art to solve looks.**

---

## Layout

```
cozy-game-v2/
├── project.godot          # 640x360 base, integer-scaled, no smoothing
├── main.tscn / main.gd    # Phase 0 scene: ground + house + 2 characters
├── core/                  # (reserved) game manager, event bus, time
├── world/
│   ├── spatial/           # (reserved) floors, rooms, portals
│   └── terrain/           # (reserved) fine grid, dig/fill
├── building/
│   └── wall.gd            # segment wall -> geometry + collision
├── character/
│   └── character_body.gd  # 3D position + 2D pixel billboard
├── render/
│   ├── camera_rig.gd      # orthographic camera
│   ├── occlusion.gd       # fade the wall that blocks the player
│   └── pixel_art.gd       # PLACEHOLDER texture factory
├── data/
│   └── materials.gd       # data-driven material table
└── docs/
    └── ROADMAP.md         # block plan and current status
```

## Axis convention

The design doc writes height as **Z**; Godot is **Y-up**. This project maps
doc Z onto Godot +Y: `doc(x, y, z) -> godot(x, z, y)`. Same meaning, different
label.

## Running

```bash
# Interactive
godot --path cozy-game-v2

# Headless self-check: drives the player outside -> doorway -> upstairs
# and prints physics state every frame
godot --headless --path cozy-game-v2 --quit-after 900
```

Controls: `WASD` move · `Q`/`E` rotate camera · `R`/`F` pitch · wheel zoom.

## Art

**All art is a placeholder.** Textures are generated procedurally at runtime.
No real assets are committed. When pixel-art materials arrive, only
`render/pixel_art.gd` and `data/materials.gd` change — game logic is untouched.
