# Art Profile — Fixed Camera Pixel World

> V2.1 doc Appendix E (ART-09). This file is the contract between the code and
> whoever produces the art. If an asset disagrees with this file, the asset is
> wrong, not the file.

---

## 1. Camera — LOCKED

Doc E.1.1 locks the camera, and gives the reason:

> 固定机位可以让我们为一个确定的观察方向制作像素资产，从而显著降低植物、NPC、
> VFX 和环境装饰的生产成本，同时提高 AI 生成资产的一致性。

One observation direction means every plant, prop and character sprite is drawn
for **exactly one viewpoint**. Unlock the camera and that cost multiplies by the
number of angles — which is why doc E.1.1 forbids free rotation as a gameplay
feature.

| Property | Value | Where |
|---|---|---|
| Projection | **Perspective, narrow FOV** (8–40°, derived from zoom) | `CozyCameraRig.USE_PERSPECTIVE` |
| Yaw | **180°** — locked | `CozyCameraRig.FIXED_YAW` |
| Pitch | **40°** — locked | `CozyCameraRig.FIXED_PITCH` |
| Distance | 75 m back along the view axis | `CozyCameraRig.CAM_DISTANCE` |
| Zoom | 5 discrete steps: 11.25 / 16.875 / **22.5** / 33.75 / 48.75 m visible height (default in bold) | `CozyCameraRig.ZOOM_STEPS` |
| Follow | Position follows the player; **angle never changes** | `_process` |

> **Changed 2026-09-12; this table used to read 45° / 52° / orthographic.** The
> yaw moved to 180 for a measured reason, not a stylistic one: the house door is
> cut into the `z = 0` wall, so the front of a building faces `-Z`, and a camera
> at `+Z` opens the game on the back of the house. See
> "The camera belongs on the side the building faces" in `INVARIANTS.md`.
>
> **What this means for an asset:** the view is now **front-on and 40° above the
> horizon**, where it used to be a 45° three-quarter view. A sprite drawn as a
> three-quarter view is now wrong. Sprites stay **straight-on** — do NOT bake the
> downward tilt into the artwork; billboards are fixed-Y and the engine supplies
> the tilt.

"Fixed" means the ANGLE is fixed, not that the view is bolted to one spot — the
camera must follow or the player could not walk anywhere.

### Debug unlock

Press `L` to unlock rotation for inspection. This is a testing aid, off by
default, and **no production asset may ever be authored from a view it
produces** — by definition that view is out of spec. Press `L` again to return
to spec.

---

## 2. Pixel density — asset-driven, not a global downscale

Doc E.2:

> 不强制所有画面最终缩到同一个极低分辨率再放大。第一版优先让资产本身具备正确
> 像素密度，再根据实际截图决定是否增加全屏低分辨率后处理。

So the project renders at **native resolution** (1280×720 base, `canvas_items`
stretch). Pixel size comes from each asset's own texel density, not from
crushing the whole frame. Full-screen pixelation remains available as an
OPTIONAL post-process, to be decided from real screenshots.

### What that means for an asset

Given the locked camera, work out how many screen pixels one world metre covers,
then author at that density. At the default zoom (**22.5 m** visible height over
720 px):

```
32 screen px per world metre
```

So a 1 m wide object drawn at 1:1 wants exactly **32 px** of width to look
native. An object authored at a different density will look too sharp or too
coarse next to everything else, even if it is beautiful on its own.

**This number is not independent of the camera.** It is `720 / ZOOM_STEPS[2]`
written down, and `_check_camera` asserts the division — change the default zoom
without changing this and every asset in the game is at the wrong magnification,
with nothing anywhere saying so. (60 px/m until 2026-09-15, when the view widened
to 22.5 m; the two moved together.)

`_check_scatter` prints every sprite's distance from this density as a
magnification factor, and that line is the **work list** for redrawing them.

### 2.1 Density per asset kind

One world density (32 px/m) with deliberate exceptions. A sprite drawn at a
different density is a different texture scale, not a bigger or smaller drawing of
the same thing — so the exceptions are listed here rather than chosen per asset.

| Asset kind | Density | Why |
|---|---|---|
| **Environment** (ground, vegetation, props, buildings) | **32 px/m** | The world's own density. 1 m = 32 px |
| **Characters** | **64 px/m** | **Drawn at twice the world's density and displayed at half.** A person is the one thing on screen worth oversampling, and this is what keeps a face readable at 22.5 m of visible height |
| **Important items** (icons, the thing a pickup looks like) | **32–64 px/m** | 64 when it will be seen large or in a UI cell, 32 when it sits in the world |
| **Small decorations** (pebbles, single flowers) | **16–32 px/m** | Whole multiples of the world density ONLY (32, 16) — anything between puts the texel grid out of step with the world grid and the sprite shimmers as it moves |

**A character sheet is therefore 112 px tall per 1.75 m** (`64 px/m × 1.75 m`), and
the game displays it at 1.75 m. `CozyPixelArt.CHARACTER_TEX_H` is that number and
`CozyCharacter.CAPSULE_HEIGHT` is the other half of it; the two are checked against
each other rather than typed twice.

### 2.2 World sizes — the module table

Willow, 2026-09-15. These are **module sizes for the building system**, in metres,
and they are the numbers a new asset or a new building block should be drawn to.

| Thing | Size | Notes |
|---|---|---|
| One ground grid cell | 1 × 1 m | The *module*. Terrain's own cell is still 0.25 m — see below |
| Door | 1 × 2 m | |
| Plain wall | 1 × 1 m | 3 m tall |
| Large wall | 2 × 1 m | |
| Window | 1 × 1 m | |
| Stair | 1 × 2 m | |
| Small room | 4 × 4 m | |
| Small house | 4 × 5 m | |
| Medium house | 6 × 6 m | |
| Large building | 8 × 8 m and up | |
| One storey | 3 m | `main.gd`'s `FLOOR_H` agrees |
| Second storey | +3 m | |
| **Player height** | **1.75 m** | `CozyCharacter.CAPSULE_HEIGHT` agrees |

**Two things this table is NOT yet, both on purpose:**

1. **The demo house is a hand-written PREFAB, not built from modules.** It is 8 × 6 m
   with a 1.2 m doorway and a 2.5 m stairwell — it never went through the outline
   generator (see `INVARIANTS.md`). It will be rebuilt on these modules when the
   building system is unparked; changing its fixtures now would move navigation
   geometry for no gameplay gain.
2. **The ground grid is a module, not the terrain cell.** Terrain is still
   0.25 m (`CozyTerrainChunk.CELL_SIZE`) and objects still snap at 0.25 m. That
   question — edit unit vs pixel scale — is a separate decision with a measured
   6.25× cost, and it is still open (`03-流程/待拍板-C类.md` #5).

**Why the door is 1 m and the prefab's is 1.2 m is worth knowing before it bites:**
the navigation grid rasterises obstacles exactly and inflates by the agent radius,
so a **1.0 m doorway is sealed by the 0.25 m grid** (see `INVARIANTS.md`, "A grid
that rasterises obstacles exactly is routing a POINT"). A 1 m door module needs the
finer clearance field first, or the resident walks into the frame.

**Scale reference is the house**: walls are 3 m tall, floors 3 m apart.

---

## 3. Anchors and pivots

| Asset kind | Pivot | Notes |
|---|---|---|
| Ground vegetation (grass, flower, pebble) | bottom-centre | Sits ON the ground plane |
| Trees, bushes | bottom-centre | Trunk base at the pivot |
| **Props and furniture** | **not a sprite at all** | **3D geometry — see below** |
| Characters | bottom-centre | Feet at the pivot — the billboard is already offset by half the capsule height in code |
| Walls and building parts | centre of the footprint | Generated geometry, not authored sprites |
| VFX | centre, unless it has a clear origin (fire: bottom) | |

> **Furniture is 3D, decided 2026-09-12.** This table used to file "props" under
> the bottom-centre billboard pivot, which contradicted the code —
> `WorldObject._build()` makes a `BoxMesh`. The 3D path wins because a low object
> does not read as a front-on sprite: a bed is 0.9 x 2.0 m, so from the front you
> see only its 0.9 m edge. Furniture's real asset is therefore a **material
> texture**, not a sprite.

Billboards are drawn as **fixed-Y** (rotate about the vertical axis only, never
follow the camera's pitch). An asset that only reads correctly when tilted does
not fit this project.

---

## 4. Import rules

| Setting | Value | Why |
|---|---|---|
| Filter | **Nearest** | Pixel art must never be smoothed (doc #35) |
| Mipmaps | **Off** | Mipmaps average texels and destroy the pixel grid |
| Repeat | Off for sprites, On for tiling surfaces | |
| Compression | Lossless | Lossy compression puts noise in flat pixel clusters |
| Alpha | Straight, not premultiplied | |

Atlas layout (doc E.3 `atlases/`): pack by category — `vegetation/`,
`characters/`, `vfx/`, `props/`. Leave **2 px between entries** so nearest
sampling cannot bleed between neighbours.

---

## 5. Asset Definition (doc E.4.1)

Every production asset carries metadata. Filenames alone cannot tell a runtime
generator whether something may sit by water, appear beside a road, or belongs
in a forest:

```json
{
  "id": "grass_tuft_01",
  "category": "vegetation",
  "subcategory": "grass",
  "style_set": "cozy_pixel_world",
  "source": "ai_cleaned",
  "license": "project_verified",
  "resolution": [32, 32],
  "pixel_scale": 1,
  "pivot": [0.5, 1.0],
  "billboard": true,
  "casts_shadow": false,
  "biomes": ["grassland", "village", "forest_edge"],
  "variants": 6,
  "tags": ["small", "ground", "vegetation"]
}
```

### Asset states (doc E.3.1)

```
RAW  ->  CLEANED  ->  APPROVED
```

`RAW` is whatever the generator produced. `CLEANED` has had its background
removed, pixels fixed, palette matched and scale corrected. `APPROVED` has been
verified in-game.

**Never ship a RAW asset into the runtime library.**

---

## 6. Naming (doc E.5)

```
<category>_<type>_<style>_<variant>_<direction>_<action>_<frame>
```

```
grass_tuft_cozy_01.png
tree_oak_cozy_01_back.png
npc_villager_01_front_idle_00.png
vfx_fire_small_01_07.png
```

---

## 7. What is deliberately NOT done yet

- **No pixel assets exist.** Everything on screen is the procedural placeholder
  in `render/pixel_art.gd`; see the doc's own Art Policy (58.1).
- **No atlas pipeline**, because there are no atlases. Sprites are currently
  individual textures keyed by asset id in `VegetationScatter._texture_for()`.
- **The terrain surface cannot take a tiling texture.** Each chunk is one quad
  wearing a `CELLS x CELLS` (64 x 64) image in which **one cell is one pixel** —
  a per-cell colour map at 4 px per world metre, not a texture. Ground "textures"
  need `terrain_renderer.gd` changed first. See §8.
- **Walls are vertex-coloured, not textured.** `CozyWallAssembly` shades each
  block deterministically; there is no texture sampler on a wall face yet.

Done since this section was first written (it used to say otherwise):

- **The scatter system exists** — `CozyVegetationScatter` (ART-11), instanced
  into one MultiMesh per asset, with real scatter rules.
- **A deterministic art seed exists** — `CozyArtSeed` (doc E.21).

The point of writing this file now is that the contract exists before the assets
do. Doc 58.1: **美术资源可以为空，系统不能依赖资源本身才能运行。**

---

## 8. The four asset classes, and how each one plugs in

They are genuinely different kinds of file. Authoring a ground texture the way
you author a tree sprite produces something that cannot be used.

| Class | Form | Plug-in point | Ready? |
|---|---|---|---|
| Vegetation, rocks, props, characters | **2D sprite**, transparent PNG, bottom-centre pivot | `VegetationScatter._texture_for()` / the billboard material | ✅ replacing a placeholder texture |
| Building materials (wall, roof, slab) | **Seamless tiling texture**, applied to a 3D block face | `CozyWallAssembly` (vertex colour today) | ⚠️ needs the assembly to sample a texture |
| Terrain ground (grass/soil/sand/stone/water) | **Per-cell colour map**, 1 cell = 1 px | `terrain_renderer._make_chunk_texture()` | ❌ needs the renderer reworked |
| VFX | **2D sprite sequence**, centre or bottom pivot | VFX library | ✅ replacing a placeholder texture |

### Resolution: `px = world_metres x 32`

From §2 — at the default zoom, 32 screen px per world metre. A sprite's canvas
should be `world_size x 32` px in **both** dimensions, because the billboard quad
is square and the sprite is stretched to fill it:

| Asset | World size | Canvas |
|---|---|---|
| `grass_tuft_01` | 0.40 m | 13 x 13 |
| `flower_daisy_01` | 0.45 m | 14 x 14 |
| `rock_small_01` | 0.40 m | 13 x 13 |
| `tree_oak_01` | 2.40 m | 77 x 77 |

**THE TWO REAL SPRITES ARE STILL 24 x 24, WHICH IS THE OLD DENSITY** — they cover
0.75 m of world now instead of 0.40 m, unless redrawn. `vegetation_scatter.REAL_SIZE`
pins the grass tuft's world size at 0.40 m so the ground's coverage does not move,
which means the sprite is now drawn at 0.53x and `_check_scatter` says so: the
tuft wants redrawing at 13 px. That line is the work list, not a complaint.

Draw into the canvas with transparent margins rather than resizing it — a sprite
that does not fill its canvas is correct, a canvas that does not match the world
size is not.

### Where generated art goes

`assets/art/generated/ai_raw/` -> `cleaned/` -> `approved/`. **RAW never reaches
the runtime library** — `CozyAssetLibrary.runtime_definitions()` returns APPROVED
only, and that is enforced in code rather than by convention (ART-10).

---

## 9. The Hybrid Pixel Diorama pipeline (Willow, 2026-09-12)

Four asset classes, four different producers. **The runtime is never 3D-animated
for anything in the "sprite" rows** — §1.2's "2D Pixel Characters" is unchanged.

| Layer | Producer | Runtime form |
|---|---|---|
| Buildings, furniture | Procedural / authored 3D | Real 3D geometry |
| **Large trees** | Blender, multi-layer concentric shells | **2.5D pseudo-3D mesh** |
| Grass, flowers, small rocks | AI sprites | Quad + billboard |
| **Characters / NPCs** | **Blender as a character factory** | **Sprite sheet** |

### Characters: Blender renders, Godot plays sprites

```
concept art -> Blender low-poly -> Skeleton -> animation
            -> ORTHOGRAPHIC render -> sprite sheet -> AnimatedSprite3D
```

Blender is a **factory**, not a runtime dependency. It bakes appearance
(hair / face / clothes / body / colour) into a sheet; the game loads PNGs.

Two details that decide the implementation:

- **The node is `AnimatedSprite3D`, not `AnimatedSprite2D`.** Godot 4.7 has
  `AnimatedSprite3D`, and it extends `SpriteBase3D` — so every property
  `CozyCharacter._build_visual()` sets today (`billboard`, `pixel_size`,
  `alpha_cut`, `texture_filter`, `shaded`, `double_sided`) still applies. The
  migration is `sprite.texture` -> `sprite.sprite_frames` and nothing else.
  An `AnimatedSprite2D` is a CanvasItem and cannot stand in a 3D world.
- **Render ORTHOGRAPHIC even though the game camera is perspective.** A character
  is a flat quad that always faces the camera, so it has no depth within itself
  and orthographic vs perspective changes nothing about it. The camera is 40 m
  out with a ~17 degree frame, so the scale at the focal plane matches too.

### Large trees are 2.5D, and that has one consequence

The multi-layer concentric-shell tree only reads if the mesh **does not
billboard** — a billboard rotates to face the camera every frame, which cancels
the parallax the layers exist to produce. So the tree asset needs a world-fixed
path, while grass keeps `make_billboard_material()`. Measured payoff at the
locked camera: about 4.6 px of layer separation at the screen edge at default
zoom, 0 at the centre (see the yaw sweep in `--cozy-probe-occlusion`).
