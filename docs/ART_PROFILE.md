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
| Projection | Orthographic | `CozyCameraRig._ready()` |
| Yaw | **45°** — locked | `CozyCameraRig.FIXED_YAW` |
| Pitch | **52°** — locked | `CozyCameraRig.FIXED_PITCH` |
| Distance | 40 m back along the view axis | `CozyCameraRig.CAM_DISTANCE` |
| Zoom | 5 discrete steps: 6 / 9 / 12 / 18 / 26 m visible height | `CozyCameraRig.ZOOM_STEPS` |
| Follow | Position follows the player; **angle never changes** | `_process` |

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
then author at that density. At the default zoom (12 m visible height over 720
px):

```
60 screen px per world metre
```

So a 1 m wide object drawn at 1:1 wants roughly **60 px** of width to look
native. An object authored at a different density will look too sharp or too
coarse next to everything else, even if it is beautiful on its own.

**Scale reference is the house**: walls are 3 m tall, floors 3 m apart, the
doorway 1.5 m wide.

---

## 3. Anchors and pivots

| Asset kind | Pivot | Notes |
|---|---|---|
| Ground vegetation (grass, flower, pebble) | bottom-centre | Sits ON the ground plane |
| Trees, bushes, props | bottom-centre | Trunk base at the pivot |
| Characters | bottom-centre | Feet at the pivot — the billboard is already offset by half the capsule height in code |
| Walls and building parts | centre of the footprint | Generated geometry, not authored sprites |
| VFX | centre, unless it has a clear origin (fire: bottom) | |

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
- **No scatter system.** Doc E.20's `VegetationScatterSystem` (ART-11) is not
  built, so there is no vegetation to place.
- **No deterministic art seed.** Doc E.21's
  `WorldSeed + ChunkCoord + ObjectID + ArtRuleID` hierarchy (ART-09/ART-10) is
  not implemented; the placeholder uses `hash()` per material.
- **No atlas pipeline**, because there are no atlases.

The point of writing this file now is that the contract exists before the assets
do. Doc 58.1: **美术资源可以为空，系统不能依赖资源本身才能运行。**
