# ART-14 · NPC Sprite Pipeline

> **状态** 🚧 **Godot 侧契约已完成**（2026-09-12），等 Blender 工厂出图
> **阶段** ART 美术管线
> **依赖** ART-10 ✅ ｜ V2-22 NPC 数据模型 ✅
> **架构依据** 总纲 附录 E.26 / E.33 / E.44 ｜ **管线改定见 `ART_PROFILE.md` §9**
> **代码位置** `data/appearance.gd`、`character/character_visuals.gd`、
> `character/character_body.gd`、`assets/art/pixel/characters/`

## 一句话

角色**长什么样是数据**；Blender 是**离线工厂**，把一组数据渲成一张精灵表，
游戏只负责加载。**运行时角色仍然是 2D 精灵，总纲 §1.2 没有被推翻。**

## 管线（Willow 2026-09-12 拍板 · Hybrid Pixel Diorama）

```
AI 概念图 → Blender 低模 → 骨架 → 动画 → 正交渲染 → 精灵表 → AnimatedSprite3D
```

四层资产各走各的生产者：

| 层 | 生产者 | 运行时形态 |
|---|---|---|
| 建筑 / 家具 | 程序化 / 手工 3D | 真 3D 几何 |
| **大树** | Blender 多层同心壳 | **2.5D 伪 3D mesh** |
| 草 / 花 / 小石 | AI 精灵 | Quad + billboard |
| **角色 / NPC** | **Blender 角色工厂** | **精灵表** |

## 要交付什么

- ✅ **外观数据表** `CozyAppearanceDefs`（hair 5 / face 3 / clothes 8 / body 3 / color 6）
- ✅ **动画选择器** `CozyCharacterVisuals.select()` —— 纯逻辑，不含美术
- ✅ **精灵表契约** `frames_for()` —— 有渲好的就用，没有就回退占位，**调用方看不出区别**
- ✅ **节点迁移** `Sprite3D` → `AnimatedSprite3D`
- ⬜ **Blender 工厂**（第 2 步）—— 低模 + 骨架 + 蒙皮 + 5 个动画
- ⬜ **正交渲染 → 精灵表**（第 3 步）
- ⬜ **模块化参数化**（第 4 步）
- ⬜ **批量随机 NPC**（第 5 步）

## Definition of Done

| # | 问题 | 答案 |
|---|---|---|
| 1 | 输入是什么 | 外观字典（5 个槽位）+ 每帧的 `activity` / `moving` / `busy` |
| 2 | State 是什么 | `CozyAppearanceDefs` 的字典；外观**不进存档**（现在） |
| 3 | Solver / Generator 是什么 | `CozyCharacterVisuals`：选动画 → 找表 → 没有就造占位 |
| 4 | Runtime Node 是什么 | `AnimatedSprite3D`，父节点仍是 `CozyCharacter` |
| 5 | 如何测试 | 4 条断言，见下 |
| 6 | 如何证明没破坏旧系统 | 111 → **115 OK / 0 FAIL / 0 ERROR** |

## 验收断言

```
[cozyv2] character anim select: 8 case(s), sit=eat,leisure,social  [OK]
[cozyv2] character sheet: 5 animation(s), reachable=idle,sit,sleep,walk,work, orphan=none  [OK]
[cozyv2] character anim node: AnimatedSprite3D playing "walk", 240 update(s) stable, npc=sleep/sleep  [OK]
[cozyv2] character appearance: 5 slot(s), 5 hair / 3 face / 8 clothes / 3 body / 6 color, typo caught=true  [OK]
```

## 关键决策

- **节点是 `AnimatedSprite3D`，不是 `AnimatedSprite2D`**
  后者是 **CanvasItem，根本站不进 3D 世界** —— 而且症状是**空屏不是报错**。
  前者继承 `SpriteBase3D`，所以 `billboard` / `pixel_size` / `alpha_cut` 原样有效，
  迁移只有 `texture` → `sprite_frames` 一处。

- **⚠️ 动画选择不能只看 FSM**
  FSM 只有 **3 个状态**（IDLE / GOING / WORKING），
  而 `CozySchedule.ACTIVITY_POINTS` 有 **6 个活动**（sleep / wake / eat / work / leisure / social）。
  **睡觉和吃饭都发生在 `WORKING` 里**（实测 `npc WORKING ... want=sleep act=sleep`）。
  → 只看 FSM 选动画，**居民睡八小时都在播 `work`，而且什么都不报**。

  正确顺序，每一步都是承重的：
  ```
  ① 在移动？      → walk     （走去床上是"走路"，不是"睡觉"）
  ② 有任务吗？    → 没有就是 idle
  ③ 才看活动      → sleep / sit / work
  ```

- **坐姿活动是从表里派生的，不是重抄的**
  坐姿有 **3 个**：`eat` / `leisure` / `social`（我一开始以为是 2 个）。
  从 `CozySchedule.ACTIVITY_POINTS` 派生 —— 那张表被注释写明是
  "the only place that bridge exists"，抄第二份就是两边漂移的开始。

- **精灵表加载是全有或全无**
  半渲染的角色会一半真美术一半占位，那看起来像**游戏坏了**而不是像**美术没到**。

- **两条方向的可达性都断言**
  正向：选择器能返回的必须有表，否则那一刻角色会变空。
  **反向：表里有、但没有任何输入能触发的，是没人会看到的表** ——
  就是本项目撞过五次的"声明了没有消费者"。
  **`carry` 今天正好落在这一条上**（搬运跑在 `WORKING` 里，和普通工作无法区分）。

- **BODY 不带 scale 乘数**
  工厂用"图形占画布多少"控制体型；游戏侧再放一个乘数就是同一件事的两个来源。

## 现有状态（如实）

**做的是契约，不是美术。** 屏幕上仍是程序占位图（§58.1），
但**每种外观画出来都不一样**（肤色/发色/衣色都来自数据），所以选错 id 是**看得出来**的。

**没有任何一张真素材。** `assets/art/pixel/characters/` 下还没有渲染结果。

## 下一步

1. **第 2 步：Blender 工厂**（Willow 正在装 Blender）
   基础低模 → 骨架 → 蒙皮 → `idle` / `walk` / `work` / `sit` / `sleep` 五个动画
2. 第 3 步：正交渲染 → 精灵表，落到
   `assets/art/pixel/characters/<body>/<hair>__<face>__<clothes>__<color>/<anim>.png`
3. 第 4 步：模块化参数化（换发型/脸/衣服/配饰）
4. 第 5 步：批量随机 NPC

**帧数契约**（工厂必须匹配，否则表会静默播成乱码）：
`idle 2 ｜ walk 4 ｜ work 2 ｜ sit 1 ｜ sleep 2`

---
*读这一份就够开工。若需回溯设计理由，再查总纲对应章节。*
