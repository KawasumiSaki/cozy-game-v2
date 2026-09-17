# ART-11 · Terrain Scatter

> **状态** ✅ 已完成（2026-09-11）
> **阶段** ART 美术管线
> **依赖** ART-10 资产库 ✅ ｜ V2-10 地形数据 ✅
> **架构依据** 总纲 附录 E.20 / E.21 / E.19 ｜ 第 58.4 / 58.5 节 ｜ §61
> **代码位置** `world/scatter/`（`art_seed` / `biome` / `scatter_rule` / `vegetation_scatter`）

## 一句话
草不要做成一株株模型 —— 用极少的原子 + 规则生成整片草原。

## 交付了什么
- **`CozyArtSeed`**（E.21）：`WorldSeed + ChunkCoord + ObjectID + ArtRuleID` 的确定性种子。
  **美术路径上任何地方都不许直接用随机源。**
- **`CozyBiome`**（E.19）：grassland / shore / rocky / village。
  **派生而非存储** —— 地面一变 biome 立刻跟着变，且不需要存档（§67）
- **`CozyScatterRule`**（E.20.1）：概率公式拆成 **基础概率**（数据、可断言）+ **确定性掷骰**
- **`CozyVegetationScatter`**：扫格 → 判定 → **一个资产一个 MultiMesh**
- 3 种占位植被贴图（草簇 / 花 / 卵石），进 `render/pixel_art.gd`

## Definition of Done
| # | 问题 | 答案 |
|---|---|---|
| 1 | 输入是什么 | 地形材料场 + biome + 离建筑距离 + world seed |
| 2 | State 是什么 | ScatterInstance 是**派生结果**，不存盘（§67） |
| 3 | Solver / Generator 是什么 | `CozyVegetationScatter.rebuild()` + `CozyScatterRule` |
| 4 | Runtime Node 是什么 | `MultiMeshInstance3D`（一个资产一个） |
| 5 | 如何测试 | 5 条断言：数量 / 实例化 / 密度场 / 建筑减薄 / 确定性 |
| 6 | 如何证明没破坏旧系统 | 48 条断言全绿 |

## 验收断言
```
[cozyv2] scatter: 2097 instance(s) in 3 mesh(es), 4096 candidate(s)  [OK]
[cozyv2] scatter instancing: 2097 instance(s) -> 3 draw call(s)      [OK]
[cozyv2] scatter density: grass=0.42 sand=0.00 water=0.00            [OK]
[cozyv2] scatter near building: 0.08 vs 0.42 open                    [OK]
[cozyv2] scatter deterministic: fingerprint 167335444 vs 167335444   [OK]
```

## 关键决策
- **概率公式拆两半**
  `base_probability()` 是确定性的、承载语义的那一半（"草地 0.42、沙地 0"），
  **可以直接断言**；掷骰是另一半。混在一起就没法断言"密度对不对"。
- **确定性用指纹验证，不是比数量**
  上一块（ART-12）的教训：排布可以重排而总数不变。所以 `fingerprint()`
  把**每个实例的位置**都哈希进去，两次 rebuild 必须完全相同。
- **实例化是硬要求**
  2097 株植物若各自一个节点就是 2097 次 draw call，总纲 §61 明令禁止。
  一个资产一个 MultiMesh → **3 次**。
- **biome 派生而不存储**
  地面一改 biome 立刻变，不用存档也不会与地形漂移。这是整个地形阶段的回报。
- **建筑的"位置"要用中点**
  墙的**节点在原点**（几何烘进顶点里），`global_position` 会说所有墙都在 (0,0,0)。
  所以 `building_points` 传的是中点数组 —— 这个坑在写断言前就发现了。

## 后续补做

### `forest_edge` 已实现（原缺口 1）
林地现在是**区域**而非逐格掷骰：`CozyArtSeed.value_noise` 生成一张值噪声场，
超过阈值即林地。逐格随机永远只能得到"更密的斑点"，得不到一片森林。
树规则 `near_building: 0.0` 是**绝对零**，不是衰减 —— 总纲 E.20.2
"建筑周围不应出现大树"。

```
scatter forest: forest=0.17 open=0.003 near-building=0.00, 165 tree(s)  [OK]
```

### 全量重建 vs 脏区（原缺口 2）—— **测量后决定不做**

先说结论：**脏区减少的是重建频率，不是单次重建成本。** 而 `rebuild()`
目前只在启动时跑一次，没有挂到地形编辑上——没有"脏"可言。

实测（`--headless`）：

| 阶段 | 耗时 |
|---|---|
| 采样 4096 个候选点 | 130.8 ms |
| 建 MultiMesh | 5.7 ms |
| **合计** | **138.1 ms** |

采样是瓶颈，且**不是算法问题**：每个候选点约 70 次 GDScript 函数调用，
4096 × 70 ≈ 29 万次，是解释器调用开销。做过两次优化：
- 去掉 `locate()` 的 Array 分配 → 176→169 ms（几乎无效）
- 水体早退（世界里没有水就不查 5 个邻居）→ 176→**138 ms**（有效，因为省的正是字典查找）

**真正该做的是正确性**：现在挖地植物不跟着变，违背总纲"Terrain → 植物跟随"。
但那要等散布置信挂上编辑路径之后，届时 138 ms 停顿才成为问题。
**届时的做法**：按 chunk 分块重建 —— 代价是每个 (chunk, asset) 一个 MultiMesh，
draw call 从 4 涨到 ~64。这个取舍现在写下来，免得将来重新推一遍。

### 真实材质库（原缺口 3）
仍等素材。装配机制（ART-12）已完成，不阻塞。

### 其他诚实说明
- 植被是**程序生成的占位 sprite**，一张真素材都没有（总纲 §58.1）。
  换真素材只需改 `_texture_for()` 一处。

## 下一步
- **ART-13 Pixel VFX Library**（篝火是最小可验证对象）
- 或还债「楼板/楼梯进 BuildingState」→ 解锁 **V2-17 屋顶生成器**

---
*读这一份就够开工。若需回溯设计理由，再查总纲对应章节。*
