# ART-10 · Pixel Asset Library

> **状态** ✅ 已完成（2026-09-11）｜ **阶段** ART 美术管线
> **依赖** ART-09 ✅
> **架构依据** 总纲 附录 E.3 / E.4 / E.5 ｜ 第 58.3 节 Layer 1-2
> **代码位置** `assets/art/`、`render/asset_definition.gd`、`render/asset_library.gd`

## 一句话
资产目录 + Definition 元数据 + 三状态流转。**不需要素材就能做完。**

## 交付了什么
- **`assets/art/` 目录骨架**（33 个目录），按 E.3：`bible / references / pixel / building / atlases / palettes / generated`
- **`CozyAssetDefinition`**：E.4.1 全部字段 + `validate()` 严格校验 + RAW/CLEANED/APPROVED 三状态
- **`CozyAssetLibrary`**：递归扫描 JSON、拒绝并**记录原因**、按 category / biome / tag 查询
- **`runtime_definitions()` 只返回 APPROVED** —— 把 E.3.1「禁止直接把 AI 原图放进正式运行目录」变成代码而非文档
- 5 份测试用 Definition（3 份 APPROVED、1 份 RAW 测排除、1 份残缺测拒绝），真素材到位后替换

## Definition of Done
| # | 问题 | 答案 |
|---|---|---|
| 1 | 输入是什么 | `assets/art/**/*.json` 的 Asset Definition |
| 2 | State 是什么 | `CozyAssetDefinition`（纯数据） |
| 3 | Solver / Generator 是什么 | 加载器：扫描 → 解析 → 校验必填字段 |
| 4 | Runtime Node 是什么 | 无 —— 只提供查询 API 给未来的 Scatter 与生成器 |
| 5 | 如何测试 | 4 条断言：加载数 / 拒绝带原因 / RAW 被排除 / biome 查询 |
| 6 | 如何证明没破坏旧系统 | 40 条断言全绿 |

## 验收断言
```
[cozyv2] asset library: 4 loaded, 1 rejected, 3 runtime  [OK]
[cozyv2] asset library rejects malformed_draft: malformed_draft.json: missing or invalid 'category', missing or invalid 'source', missing or invalid 'resolution'  [OK]
[cozyv2] asset library raw exclusion: runtime=3, vegetation query=3  [OK]
[cozyv2] asset library biome query: grassland+vegetation -> 2  [OK]
```

## 关键决策
- **校验严格、拒绝要带原因**：E.4.2 的目的是让 runtime generator **能信任**查询结果。
  一份少字段的资产是 bug，应该大声报出来而不是静默跳过。
  拒绝原因格式与地形门禁一致（总纲 §72 要求"不允许建筑时有明确原因"）。
- **查询与"可运行"是两件事**：`by_category()` 看到**全部**已加载定义，
  `runtime_definitions()` 才做审批过滤。混为一谈就是未审批美术流进运行时的路径。
  断言特意同时验证这两者（`runtime=3, vegetation query=3`）。
- **本块不含任何视觉输出**：ART-10 只交付契约。真正画东西从 ART-11 开始。

## 已知限制（写下来，不是忘了）
- 用 `DirAccess` 扫描目录，**编辑器与 headless 可用，导出构建不行** ——
  导出后需要把定义声明为 resource 或打进 manifest。已在代码注释里标明。

## 下一步
**ART-11 Terrain Scatter**（总纲 E.20）—— 但先要：
1. 群系（biome）概念进地形，现在只有材质没有群系分组
2. 确定性种子（E.21）：`WorldSeed + ChunkCoord + ObjectID + ArtRuleID`
3. billboard 实例化时注意 §61，不要一株一个 draw call

也可选 **ART-12 Building Material Library**，它不依赖群系概念，路径更短。

---
*读这一份就够开工。若需回溯设计理由，再查总纲对应章节。*
