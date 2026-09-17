# ART · 资产生成提示词包（给 Gemini）

> ## ⚠️ 2026-09-12 收到第二条风格线：「3D 像素立体」提示词
>
> Willow 同日给了**两条互斥的风格线**，用哪条**尚未拍板**：
>
> | | A 线（本文档主线） | B 线（Willow 新给，见 §9） |
> |---|---|---|
> | 形态 | 2D 透明精灵 | 3D 低多边形 + 像素贴图 |
> | 视角 | 正面平视，禁俯视 | 固定角度的立体视图 |
> | 适用 | 草/花/石/树/角色/墙面材质 | 家具、建筑、3D 立体道具 |
> | 依据 | 总纲 §1.2 / E.1.4（角色与 NPC **明列**在 billboard 名单） | 尚无总纲依据 |
>
> **§9 的提示词已按你要求存好**，但它描述的是 **3D 模型**（"low-poly model"、
> "soft 3D volume"、"fixed-angle 3D camera view"），**不是精灵**。
> 按现行总纲它不能用于角色和植被 —— 见 §9 的适用范围说明。


> **用途**：把"要什么格式、什么尺寸、什么风格"一次性写死，避免生成回来接不上。
> **依据**：仓库 `docs/ART_PROFILE.md`（合同，2026-09-12 已更新相机段）
> **状态**：提示词可用；**但下面第 6 节有两个待你拍板的点**

---

## 1. 先分清四类资产 —— 它们是四种不同的文件

**"草和地面贴图不一样、家具又是另一种" —— 对的，而且是四种不是三种。**
按错的类型生成，回来是接不上的。

| 类 | 形态 | 现在接得上吗 |
|---|---|---|
| 草 / 花 / 石头 / 树 | **2D 精灵**，透明 PNG，底边中心锚点 | ✅ 换 `VegetationScatter._texture_for()` 一处 |
| 家具 / 道具 | **2D 精灵**（合同 §3 把 props 归到 billboard） | ⚠️ 见第 6 节 |
| 角色 / NPC | **2D 精灵**，fixed-Y billboard | ✅ 换程序贴图 |
| 建筑材质（墙/屋顶/楼板） | **可平铺贴图**，贴在 3D 砌块上 | ⚠️ 墙现在是顶点色，要改装配器 |
| 地面（草/泥/沙/石/水） | ❗**不是贴图** | ❌ 现在**接不了**，见第 5 节 |

---

## 2. 视角铁律（最容易错的一条）

相机 2026-09-12 改过：**现在是 yaw 180 / pitch 40 / 透视**，以前是 yaw 45 / pitch 52 / 正交。

**画法：正面平视，不要俯视，不要透视缩略。**
相机那 40° 的俯角是**引擎给的**（billboard 是 fixed-Y，只绕竖轴转、不跟俯仰），
**不要烘焙进画里**。画成四分之三视角的精灵现在是错的。

**光照方向固定：从左上来**（屏幕左上）。所有资产必须一致，否则世界会花。

---

## 3. 通用风格前缀（**每条提示词都贴这段**）

```
16-bit era pixel art sprite for a cozy life-sim game. Single object, isolated,
centred horizontally, its base resting exactly on the bottom edge of the canvas.
Fully transparent background - no scene, no ground plane, no cast shadow, no
vignette, no backdrop. Hard-edged pixels only: no anti-aliasing, no blur, no
gradients, no photographic texture, no noise. One-pixel dark outline (#261F2E)
around the entire silhouette. Light source from the UPPER LEFT. Flat cel shading,
at most three tones per material (base, shadow, highlight) plus the outline.
Muted, slightly desaturated natural palette. STRAIGHT-ON FRONT VIEW: do not draw
the object from above, do not add perspective, do not add foreshortening. No
text, no watermark, no signature, no border.
```

### 分辨率规则：`像素 = 世界米数 × 60`

默认缩放下 **60 屏幕像素 = 1 世界米**。画布两个方向都要按这个算，因为 billboard 是正方形
被拉伸填满的。

| 资产 | 世界尺寸 | 画布 |
|---|---|---|
| `grass_tuft_01` | 0.55 m | **32 × 32** |
| `flower_daisy_01` | 0.45 m | **32 × 32** |
| `rock_small_01` | 0.40 m | **32 × 32** |
| `tree_oak_01` | 2.40 m | **144 × 144** |

**画不满画布是对的，改画布尺寸是错的。** 物体在画布里留透明边距，不要拉伸去填充。

### 现有占位色（让生成物和现在的世界不打架）

`草 #6BB354` · `泥土 #735438` · `沙 #D1BD85` · `石 #85858A` · `水 #3D75B8`
`木 #9E7042` · `砖 #A85C4D` · `灰泥 #DBD1B8` · `描边 #261F2E`

这些是**占位**色，真调色板由你定；但过渡期生成物靠近它们，画面才不会一半新一半旧。

---

## 4. 逐类提示词

### A. 草（`grass_tuft_01`，6 个变体）

```
[第 3 节通用风格前缀]

Subject: a small tuft of wild grass - 5 to 8 blades fanning up and outward from a
single point at the bottom centre. Blades 8 to 16 px tall. Base tone #6BB354,
lower/inner blades darker #4E8A3C, a few tip highlights #8FCC6E. Slight natural
lean, no symmetry.

Canvas: exactly 32 x 32 pixels. The tuft fills roughly the lower two thirds.

Output SIX separate tufts side by side in one image, one row, each with a
different blade count and lean direction, well separated with clear empty space
between them so they can be cut apart.
```

### B. 花（`flower_daisy_01`）

```
[第 3 节通用风格前缀]

Subject: a single small daisy on a short stem. Thin green stem #578E47, 8 to 12 px
tall, two small leaves. Flower head 7 to 9 px across, at the top: soft white
petals (#EFEAD8) with a warm yellow centre (#EBC74A) and one shadow tone
(#C9C2A6) under the petals.

Canvas: exactly 32 x 32 pixels. The daisy fills roughly the lower two thirds.
```

### C. 石头（`rock_small_01`）

```
[第 3 节通用风格前缀]

Subject: a small rounded field stone / pebble. Grey #85858A, with a lighter top
face (#A3A3A8) where the light hits and a darker underside (#5E5E63). Two or
three flat facets, chipped irregular silhouette, sitting flat on its base.

Canvas: exactly 32 x 32 pixels. The stone fills roughly the lower half.
Output FOUR variants in one row, differing in silhouette, well separated.
```

### D. 树（`tree_oak_01`，2.40 m）

```
[第 3 节通用风格前缀]

Subject: a single stylised oak tree. Trunk 10 to 14 px wide, brown #6B4A2E with
darker bark shading #4A3120, splitting into two short branches. Canopy a rounded,
slightly irregular cluster of leaf lobes in three tones: shadow #3F7A33, mid
#5FA84A, highlight #83C462 on the upper left. Canopy widest around two thirds up.

Canvas: exactly 144 x 144 pixels. Trunk base sits ON the bottom edge, canopy
occupies the upper two thirds. Leave the top ~8 px and the sides transparent.
```

### E. 家具 / 道具 —— ✅ **已定：保持 3D**（Willow 2026-09-12）

**所以不要给家具画精灵。** 家具是 3D 几何，需要的是**材质贴图**（见 G 节的做法），
不是 billboard。

现状如实：`world_object.gd` 的 `_build()` 建的是 `BoxMesh` + 16×16 程序贴图，
也就是**家具现在是"贴了色的盒子"**。真资产到位时换的是**盒子的贴图**，
或者换 mesh —— 但**不动 billboard 这条路**。

`ART_PROFILE.md` §3 把 props 归到 billboard 锚点是**上一版的遗留**，
以本条决定为准（低矮家具做成正面精灵读不出来，床尤其明显）。

尺寸来自 `data/objects.gd`（宽 × 深，米），正面可见宽度 × 高：

| 物体 | 占地 (X × Z) | 高 | 画布 |
|---|---|---|---|
| `research_table` 研究台 | 1.8 × 1.0 | 0.9 | **108 × 54** |
| `chest` 箱子 | 1.0 × 0.7 | 0.7 | **60 × 42** |
| `chair` 椅子 | 0.6 × 0.6 | 0.5 | **36 × 30** |
| `campfire` 篝火 | 0.9 × 0.9 | 0.3 | **54 × 18** |
| `bed` 床 | 0.9 × 2.0 | 0.5 | ⚠️ 躺着的物体正面画读不出来 |

**家具要的是材质，不是整体精灵。** 每个物体按它的主材质要一张可平铺贴图
（木/铁/布），做法同 G 节；盒子各面用同一张，UV 按世界尺度平铺即可。
形状本身是 3D 盒子，**不需要画**。

### F. 角色

⚠️ **代码里的占位是 16×24 像素 / 0.8 m 宽**，也就是 **20 像素每米** ——
和画布规则的 60 px/m **差 3 倍**。真资产到位时 `character_body.gd` 的
`SPRITE_TEX_W/H` 和 `SPRITE_WORLD_W` 要一起改。**这是个待定项，见第 6 节。**

按 60 px/m 的建议值：**画布 64 × 96**（≈ 1.6 m 高的人）。

```
[第 3 节通用风格前缀]

Subject: a single character standing idle, STRAIGHT-ON FRONT VIEW, full body from
the top of the head to the soles of the feet. Simple cozy villager: rounded head,
short hair, plain tunic and trousers, small boots. Flat cel shading, three tones
per material. Friendly neutral expression.

Canvas: exactly 64 x 96 pixels. Feet rest ON the bottom edge, the figure is
centred horizontally, leave transparent margin at the sides.

Output as a SHEET: one row of 4 frames - idle, walk step A, walk step B, idle
again - identical character, only the legs and arms move.
```

### G. 建筑材质（可平铺）

⚠️ 墙现在是**顶点色**，没有贴图采样器 —— 这批生成回来要改 `wall_assembly.gd` 才能用。
砌块尺寸来自 `data/materials.gd`，@60 px/m：

| 材质 | 砌块 长 × 高 | 一块的像素 | 可平铺贴图画布建议 |
|---|---|---|---|
| wood 木板 | 1.6 × 0.28 m | 96 × 17 | **96 × 16**（一块一行板） |
| stone 石砌 | 0.8 × 0.4 m | 48 × 24 | **96 × 48**（2×2 块，错缝） |
| brick 砖 | 0.6 × 0.3 m | 36 × 18 | **72 × 36**（2×2 块，错缝） |
| plaster 灰泥 | 2.0 × 1.0 m | 120 × 60 | **120 × 60** |

```
[第 3 节通用风格前缀, but replace the outline sentence with: "No outline - this
is a surface texture, not a sprite."]

Subject: a SEAMLESSLY TILING texture of [wooden planks / stacked stone masonry /
brickwork / smooth plaster]. Flat, evenly lit surface fill - this is a wall
material sampled in world space, so it must read as a surface, not as an object.
Keep value contrast LOW so characters and props stay readable on top of it.
Tone: wood #9E7042 base / #7A5533 shadow; stone #8F8F94 / #6E6E73; brick
#A85C4D / #8A4A3E with #CFC6B4 mortar; plaster #DBD1B8 / #C4BAA2.

Canvas: exactly [W] x [H] pixels. EDGES MUST TILE PERFECTLY - the left edge must
continue into the right edge and the top into the bottom with no visible seam and
no unique feature at the border. Output a single flat texture, no scene, no
perspective, no lighting gradient across the image.
```

### H. 地面 —— ❗**先别生成**

见第 5 节。**现在生成回来一定接不上，是浪费。**

---

## 5. 为什么地面贴图现在接不了

`world/terrain/terrain_renderer.gd` 的地面**不是贴图**：

- 一个 chunk = 16 × 16 米 = **一张 64 × 64 像素的图**
- **一个 cell（0.25 米）= 一个像素**，颜色直接取自 `CozyTerrainMaterials` 的表
- 也就是 **4 像素每米**，而其它资产是 **60 像素每米，差 15 倍**

所以：

- 一张"草地贴图"**没有地方可以贴** —— 采样器根本不存在
- 要让地面用真贴图，得先改渲染器（chunk 拆块 / 用 splat 或图集着色器）
- 那是一次**架构改动**，不是美术任务

**现在值得做的**其实是**调色板**：把 `terrain_material.gd` 里 5 行的
`color` 换成人定的值，一行一个，立刻全地图生效。这个不需要 Gemini。

**真要做贴图的话**，规格是：可无缝平铺、60 px/m、
一张 tile 覆盖整数个 cell（0.25 m 的倍数），例如 **1 m tile = 60 × 60 px**。
但**先等渲染器改完再说**。

---

## 6. ⚠️ 两个要你拍板的点

### ① 家具 2D 还是 3D？ —— ✅ **已定：保持 3D**（Willow 2026-09-12）

合同（`ART_PROFILE.md` §3）把 props 归到 billboard 锚点，代码建的是 `BoxMesh` ——
两者本来不一致。**Willow 拍板走 3D**，理由是矮家具做成正面精灵读不出来
（床最明显：0.9 × 2.0 m，正面只看到 0.9 米那条边）。

**尚未落地**：`ART_PROFILE.md` §3 那张锚点表还写着 props 是 billboard，**要改**；
`world_object.gd` 的盒子仍是占位。家具的真资产 = **材质贴图**，不是精灵。

### ② 角色像素密度：20 还是 60 px/m？

占位是 16×24 px / 0.8 m = **20 px/m**，合同说 **60 px/m**，差 3 倍。

按 60 走 → 画布 64 × 96，同时要改 `character_body.gd` 三个常量。
按 20 走 → 画布 21 × 32，角色会比较糊，但和现有占位一致。

**这两个定了，第 4 节 E 和 F 才能定稿。**

---

## 7. 资产回来放哪 + 每个资产要配一份 JSON

**放这里**（三级流转，**RAW 绝不能进运行时**）：
```
assets/art/generated/ai_raw/       ← Gemini 原图先扔这
assets/art/generated/cleaned/      ← 去背景、修像素、配色调、缩放到正确尺寸
assets/art/generated/approved/     ← 游戏里验过
```

`CozyAssetLibrary.runtime_definitions()` **只返回 APPROVED** —— 这是代码强制的，不是约定。

**每个资产配一份同名 JSON**（严格校验，少字段会被拒绝并报原因）：

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
  "anchor": "bottom_center",
  "billboard": true,
  "casts_shadow": false,
  "biomes": ["grassland", "village", "forest_edge"],
  "tags": ["small", "ground", "vegetation"],
  "variants": 6,
  "state": "approved"
}
```

**导入设置**（错了像素就糊）：Filter = **Nearest** ｜ Mipmaps = **Off** ｜
Compression = **Lossless** ｜ Alpha = Straight。
进图集就按 `vegetation/ characters/ vfx/ props/` 分，**条目间留 2 px** 防 nearest 采样串色。

---

## 8. 一句话总结给 Gemini 用的顺序

1. 先贴**第 3 节通用风格前缀**
2. 再贴第 4 节对应那一条
3. **草 / 花 / 石头 / 树 / 角色** —— 现在就能生成，回来能用
4. **墙面材质** —— 能生成，但要等装配器改完才贴得上
5. **地面贴图** —— **先别生成**
6. **家具** —— 等第 6 节 ① 拍板

---

## 9. Willow 提供的「3D 像素立体」提示词（2026-09-12）

**原文照存：**

```
Stylized cozy fantasy game asset for a 3D pixel diorama world.
Inspired by handcrafted miniature worlds, Octopath Traveler lighting,
Tiny Glade atmosphere and classic RPG environments.

Single isolated game asset, centered, transparent background.
Designed for a fixed-angle 3D camera view.

The object should look like a handcrafted low-poly model with
pixel-art inspired textures.

Clean readable silhouette.
Simple geometric shapes.
Soft rounded forms.
Slightly exaggerated proportions.
Charming and friendly fantasy style.

Use a limited natural color palette.
Muted warm colors.
Painterly pixel texture details.

Hard pixel edges mixed with soft 3D volume.
No realistic texture.
No photographic details.
No PBR realism.

Lighting:
warm sunlight from upper-left.
Soft ambient occlusion.
Clear light and shadow separation.

Do not use:
realistic perspective,
photorealism,
high detail,
complex textures,
sharp realistic edges,
modern AAA style.

The asset must feel like it belongs to a cozy fantasy village game.
```

### 这条提示词描述的是 3D 模型，不是精灵

它要的是 "handcrafted low-poly **model**"、"soft 3D **volume**"、
"fixed-angle **3D camera** view" —— 是**给 3D 资产用的**。

按现行总纲，它能覆盖和不能覆盖的范围：

| 资产 | 这条提示词能用吗 | 依据 |
|---|---|---|
| 家具（已定 3D） | ✅ 能 | Willow 2026-09-12 拍板 |
| 建筑 / 墙 / 屋顶 / 楼板 | ✅ 能 | 总纲 E.1.3「建筑必须继续使用真实 3D Geometry」 |
| 少量特殊世界对象 | ✅ 能 | 总纲 E.1.4「除少量必须 3D 化的特殊世界对象外」 |
| **角色 / NPC** | ❌ **不能** | 总纲 §1.2 锁定「角色 = 2D Pixel Sprite / Billboard」；E.1.4 **明列 NPC** 在 billboard 名单 |
| **草 / 花 / 石 / 树** | ❌ **不能** | 总纲 E.1.4 明列 Grass / Small Rocks / Small Tree Canopy 在 pixel 名单 |

### 三条不自洽的地方，用它之前要先解决

1. **"transparent background" 对 3D 资产没有意义** ——
   3D 资产要的是 **GLB/FBX 模型**，不是带透明通道的图。若生成的是图，
   那就是一张**渲染参考图**，不是可用资产。**要明确告诉 Gemini 输出什么格式。**
2. **"Hard pixel edges mixed with soft 3D volume"** 在**一张 2D 图**里是含糊的 ——
   Gemini 会把它理解成"像素风渲染图"。真正的像素立体感来自
   **低分辨率渲染 + nearest 采样**，那是**管线**的事，不是提示词的事。
3. **"warm sunlight from upper-left"** 和本文档 §2 的光照铁律**一致** ✅ ——
   这一条可以直接沿用。

### 要用它之前，先做这三件事

1. **确认输出格式**：GLB？还是"多视角正交渲染图"？
2. **确认它覆盖哪些资产类别**（上表 ❌ 的两类要 Willie 明确推翻总纲才动）
3. 若要**整项目转向 3D 像素立体风**，那是一次**架构级转向**，
   受影响的有：总纲 §1.2、`ART_PROFILE.md`、ART-14/15（2D 骨骼）、
   `vegetation_scatter` 的 billboard MultiMesh —— **要单独拍板，不能顺手做**
