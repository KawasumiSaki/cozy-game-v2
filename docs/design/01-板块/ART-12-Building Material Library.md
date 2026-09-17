# ART-12 · Building Material Library

> **状态** 🚧 砌块装配机制已完成，真实材质库待素材
> **阶段** ART 美术管线
> **依赖** ART-10 资产库 ✅ ｜ V2-16 开口 ✅
> **架构依据** 总纲 附录 E.16 ｜ 第 58.3 节 Layer 3 ｜ E.49 Procedural Assembly
> **代码位置** `building/wall_assembly.gd`、`data/materials.gd`、`building/wall.gd`

## 一句话
少数原子构件，组合出任意长度/角度的墙 —— 不是每种墙一套模型。

## 要交付什么
- ✅ **砌块排布器** `CozyWallAssembly`：把一段墙拆成砌块（错缝、确定性着色）
- ✅ **砌块尺寸数据驱动**：`data/materials.gd` 每材质一组 `block_length` / `block_height`
- ✅ **合并成单 mesh**：整面墙一次 draw call（总纲 §61）
- ⬜ **真实材质库**：`assets/art/building/materials/` 的真贴图，等素材

## Definition of Done
| # | 问题 | 答案 |
|---|---|---|
| 1 | 输入是什么 | `WallState` 的几何（长度/高度/厚度/材质/seed）+ 材质的砌块尺寸 |
| 2 | State 是什么 | 不变 —— 砌块是**派生结果**，不存盘（总纲 §18） |
| 3 | Solver / Generator 是什么 | `CozyWallAssembly.blocks_for_span()` |
| 4 | Runtime Node 是什么 | 仍然是 `CozyWall`，但 mesh 由 SurfaceTool 合并生成 |
| 5 | 如何测试 | 3 条断言：砌块数 / 确定性 / 随长度伸缩 |
| 6 | 如何证明没破坏旧系统 | 43 条断言全绿（含全部开口断言） |

## 验收断言
```
[cozyv2] wall assembly: 8.0 m wood wall -> 71 blocks in 1 mesh(es)  [OK]
[cozyv2] wall assembly deterministic: 84 vs 84 blocks, shades match=true  [OK]
[cozyv2] wall assembly scaling: 4 m -> 44 blocks, 8 m -> 84  [OK]
```

## 关键决策
- **确定性，不是随机**
  着色来自 `hash(seed, row, col)`，与总纲 E.21 一致。同一面墙在存档重载后
  必须砌成一模一样 —— 否则"昨天这堵墙是这样，今天变了"。
  断言直接比对两次排布的**每一块 shade**，不是只比数量。
- **合并成单 mesh，而不是每块一个节点**
  8m 石墙 ≈ 75 块。一块一个 MeshInstance3D 就是 75 次 draw call，
  正是总纲 §61 禁止的。用 SurfaceTool 累积后 commit 一次。
- **碰撞体保持粗糙**
  每段跨度一个盒子，不是每块一个。碰撞不需要砖缝细节，
  逐块碰撞纯属为无行为付出物理开销。
- **错缝（running bond）**
  奇数层偏移半块。这是让墙"看起来像砌出来的"而不是网格的最便宜手段。
- **数据驱动砌块尺寸**
  木头 1.6×0.28（长板）、石头 0.8×0.4（短层）、砖 0.6×0.3、灰泥 2.0×1.0（大板）。
  加新材质仍是一行数据。

## 现有状态（如实）
**做的是装配机制，不是材质库。** 墙现在由可见的砌块组成，每块有确定性的深浅差异，
但仍使用程序生成的占位色贴图 —— 没有一张真素材。
`data/materials.gd` 里已有一行 `block_size()` 把砌块尺寸接进材质表。

开口逻辑**完全未动**（已通过全部 4 条开口断言）：门洞仍留可走缺口 + 门楣，
窗仍是实心窗台。砌块只填充实体跨度。

## 下一步
1. **真实材质**：等 ART-10 的 Definition + 真贴图，替换 `CozyMaterials` 的程序纹理
2. **拐角处理**：目前错缝在跨度两端会被裁切。总纲 E.16 要求拐角处调用
   V2-15 的解算结果，用专门构件收口
3. **屋顶材质**：归 V2-17，不在这里做

---
*读这一份就够开工。若需回溯设计理由，再查总纲对应章节。*
