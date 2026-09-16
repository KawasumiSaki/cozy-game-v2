# 副本 lane 交接 · CozyVale V2

> **给做「副本世界」的人和他的 agent 读的。读完这一份就能开工。**
>
> 这个仓库同时有两拨人在改。这一份的第一件事就是**把边界划清楚** ——
> 边界比技术细节重要，因为**越界不会报错，只会互相覆盖**。

---

## 0. 一句话分工

```
我们：家园（地形 / 建筑 / 居民 / 界面 / 存档 / 环境）
你们：副本（地图 / 怪物 / 战斗 / 装备数值 / 词条 / 技能）
```

**为什么能这么分**：两条 lane 的文件**基本不相交**，各自跑**同一套 headless 断言**。
交点只有一个 —— 见第 2 节的 `main.gd`。

---

## 1. ⚠️ 开工前必须先拍板的一件事（不是技术问题）

Willow 让你做 **"镶嵌石 + 鉴定书系统"**，但**你自己的设计文档不允许**：

> `docs/design/副本世界_装备词条掉落系统_V1.0.md` **§59「V1 不要加入的复杂系统」**：
> ```
> 传奇装备特殊技能 / 套装 / 词条重铸 / 洗练 / 强化 / 宝石 / 镶嵌 /
> 装备等级压制 / Greater Affix / Ancient / Set Bonus / Runes / Aspects / 随机传奇池
> ```
> **§60 未来扩展路线**把它们排在 **V3**（`Socket` / `Gem`）。

**所以有两条路，选一条再动手：**

| | |
|---|---|
| **A** | **按文档**：宝石/镶嵌推到 V3，现在只做 §58 的 Phase 8/9 |
| **B** | **改文档**：把 `Socket`/`Gem` 提到 V1，**并写清楚 V1 的规格**（现在文档里只有"镶嵌"两个字，**没有任何设计**） |

**「鉴定书」在整份文档里一个字都没有** —— 概念、数据形状、交互全都没有。
**那不是"照着做"，那是从零设计**，要先有规格。

**这一条请先问 Willow 一句。** 不要因为"她说了"就开始 —— 设计文档是这个项目的权威，
而它明说不要做，**冲突本身就是一个需要人回答的问题**。

---

## 2. 地盘：哪些文件是你们的

**✅ 你们的**（随便改、随便加）

```
dungeon/            dungeon_layout.gd       蓝图 → 一套不重复的墙（含 to_intents()）
                    dungeon_blueprint.gd    文档契约：收 id/version/outlines，其余一律拒收
combat/             combat_defs.gd          帧数据（起手/判定期/收招/hitstop/连段）
                    combat_solver.gd        纯求解器，不碰节点
items/              item_instance.gd        Definition ≠ Instance；词条按实例 id 记账
                    item_generator.gd       播种随机，可复现
                    item_container.gd       背包：N 格一格一件，capacity 就是背包等级
                    equipment.gd            10 类 13 个槽（3 护石 + 2 戒指）
                    loot_roller.gd          掉落表 → 掉落列表
                    glamour.gd              改外观不改数值
character/monster.gd                        怪物节点（**不还手、不移动**，是决定不是遗漏）
data/               items.gd  affixes.gd  stats.gd  loot.gd  monsters.gd
tests/unit/         test_items / test_stats / test_loot / test_equipment /
                    test_glamour / test_combat / test_dungeon_layout /
                    test_dungeon_blueprint
```

**⛔ 我们的**（**不要碰**，改了我们这边会红）

```
world/              地形 / 散布 / 导航 / 房间 / NPC / 物体 / 存档 / 特效
building/           墙 / 板 / 梯 / 屋顶 / 开口
character/          npc_agent.gd  character_body.gd  character_visuals.gd  player_state.gd
ui/                 HUD / 面板 / 右键菜单
core/  render/      时钟 / 风 / 实体注册表 / 像素美术
data/               objects.gd  materials.gd  recipes.gd  jobs.gd  schedule.gd
                    work.gd  buildings.gd  appearance.gd  traits.gd  item_icons.gd
```

**🔶 公共文件**（**加行可以，改行/删行要打招呼**）

| 文件 | 为什么共享 | 规矩 |
|---|---|---|
| **`main.gd`** | **汇合点**：世界在这里搭起来，两边的系统都在这儿接线 | **见第 3 节** |
| `data/materials.gd` | 物品词汇表（§35：一个 store，多个调用者）—— 木材是墙的造价、箱子的存货、你的掉落物 | **只加行，不改已有行的 id/kind** |
| `docs/INVARIANTS.md` | 已付过代价的 bug 清单 | 只加 |
| `docs/CREDITS.md` | 素材授权台账 | 只加 |

---

## 3. `main.gd` —— 唯一的汇合点，唯一会冲突的地方

`main.gd` 6800 行，**两边的接线都在这里面**。规矩三条：

1. **改动越小越好。** 一行调用 > 一段逻辑。逻辑写进你自己的文件，`main.gd` 里只留接线。
2. **加在文件末尾。** 不要插到中间 —— 中间是家园那部分的断言和建造逻辑，
   插进去的每一行都会让下一次合并变成手工解冲突。
3. **每次改完，两边都要重跑基线。** 见第 6 节。

**已经接好的线，你可以照着抄**（都是我们做的，形状是对的）：

```gdscript
# 玩家的挥砍：主循环里 _tick_combat() → _resolve_swing() → 命中 → _kill_monster()
# 怪物死亡 → CozyLootRoller.roll(表, rng, _next_item_id) → _lay_drops(掉落, 位置)
# 地上的东西 → 每帧 _tick_pickups() → 走近自动进玩家的包
```

**⚠️ 掉落物落在**地上**，不是直接进包**（2026-09-15 定的）。
`_lay_drops()` 收的是 **roller 自己那三种字典**：

```gdscript
{"kind": "gold",      "amount": 7}
{"kind": "item",      "id": "wheat", "amount": 2}
{"kind": "equipment", "item": CozyItemInstance}
```

**保持这个形状**，你们加多少种掉落都不用改 `main.gd`。

---

## 4. 铁律（全是这个项目已经付过代价的）

1. **代码和注释全英文。** 游戏内文本必须 ASCII（防豆腐块）。
2. **绝不自动启动 GUI。** 验证只用 `--headless`。要看画面先问 Willow。
3. **现有断言必须继续全绿**，**每个板块至少新增一条断言**（不是 print）。
4. **没红过的断言不算断言**：新断言要**先把代码改坏，看它红一次**，再改回去。
5. **踩到 bug 先加探针把数字量出来**，不要凭猜。**凭猜写进文档就是下一个坑。**
6. **`0 ERROR` 也是基线的一部分。** 数错误要**合流 + 不收窄前缀**（见第 6 节）。
7. **一切程序化生成必须确定**：不用 `randf()`，用**调用者传进来的 seeded RNG**
   （`CozyArtSeed` / `RandomNumberGenerator`）。同一个种子必须给同一个世界。
8. **数据是 `const` 字典，不是 `.tres`。** 这是**冻结的架构决定**，不要改。
9. **不做 ECS，不做 EventBus，不引入全局状态管理器。** 数据表 + 纯函数求解器 + 节点只做表现。
10. **"声明了没有消费者"不是功能。** 加一个字段/接口/交互点之前先问：**谁会读它？读它的东西今天存在吗？**
    （这条在 `docs/INVARIANTS.md` 里有**八条**记录，是这个项目最贵的习惯。）
11. **两个账本**：玩家 `player_state.pack`／村庄 `building.inventory`。**副本掉落是玩家的。**
    两者形状一样、方法名一样、单位一样，**写错是看不见的**（有断言盯着）。
12. **改任何子系统行为之前，先读 `docs/INVARIANTS.md`。** 42 节 = **41 条不变量 + 1 张表（27 个已付过代价的 bug）**，都是付过代价的。

---

## 5. 已经建好的：**不要重造**

装备这条 lane 的**主体已经完成**（Phase 1–7）。下表是**已有的东西**，
你要做的是**加行、加规则、加内容**，不是重新实现：

| 设计文档的 Phase | 状态 | 在哪 |
|---|---|---|
| **1 近战地基** | ✅ 帧数据 + 纯求解器，**已接进世界**（左键挥砍 / 右键格挡或推击） | `combat/` |
| **2/3/5 Item / Affix / Generator** | ✅ Definition ≠ Instance，播种随机，按类型限定的词条池 | `data/items.gd` `data/affixes.gd` `items/` |
| **4 Stats / Modifier / Aggregator** | ✅ 四遍结算、**按来源记账**（`source` = 实例 id，所以脱下一把剑只能减它自己） | `data/stats.gd` |
| **6 LootTable / LootRoller** | ✅ drop 表（每行独立 roll）与 pick 表（按权重抽）**是两种表**，混用会被拒 | `data/loot.gd` `items/loot_roller.gd` |
| — 背包 / 穿着 / 幻化 / 怪物 | ✅ 13 个槽、`appearance_name()` 只改外观不改数值 | `items/` |
| **7 UI（背包 / 装备 / 提示）** | ✅ 13 个槽的面板 + 背包格子（**格子画的是名字 + 可选图标**） | `ui/gear_panel.gd` `ui/item_slot.gd` `ui/pack_panel.gd` |
| — 地上的物品 | ✅ 掉落落地 + 走近自动拾取（**背包满就留在地上并说一句**） | `world/objects/dropped_item.gd` + `main.gd` |
| **DG-01/02/03 蓝图** | ✅ 墙联合 + 数据契约 + `to_intents()`；**未接运行时** | `dungeon/` |
| **8 双世界 Home ↔ Dungeon** | ⬜ **要先跟家园这边定** | — |
| **9 开发者模式** | ⬜ 你们的 | — |

**所以你们真正要做的是**：Phase 8 / Phase 9 / **副本地图生成接运行时** /
**加装备与词条的内容** / **技能系统**（`data/skills.gd` 现在只有 `combat` `melee` 两行，
**没有任何技能机制**），以及第 1 节那条要拍板的东西。

---

## 6. 怎么验证（**三条命令，路径别抄错**）

```bash
GODOT="D:/privacy/Openclaw/Godot-4.7.2/Godot_v4.7.2-stable_win64.exe"

# ① 冒烟自检（期望 168 OK / 0 FAIL / 0 ERROR）
"$GODOT" --headless --path D:/cozy/cozy-game-v2 --quit-after 4500

# ② 单元测试（期望 28 套件 / 237 用例 / 3271 检查 / 0 失败）
"$GODOT" --headless --path D:/cozy/cozy-game-v2 --script res://tests/unit/run.gd

# ③ 加了新的 class_name 之后，必须先跑一次 import
"$GODOT" --headless --path D:/cozy/cozy-game-v2 --import
```

**⚠️ 路径换成你自己克隆的位置。** 上面写的 `D:/cozy/cozy-game-v2` 是 Willow 机器上的路径，
**你克隆到哪就改成哪** —— 这一行是这份文档里唯一一处只对一个人成立的东西，
所以单独说一遍。（`CLAUDE.md` 里原来写的 C 盘旧路径已修正。）

### 三个会骗人的数数陷阱（都真发生过）

```bash
... 2>&1 | grep -c "ERROR"   # 正确：必须合流
                             #   只收 stdout → 漏掉 Godot 写在 stderr 的 ERROR
                             #   收窄成 "^ERROR" → 漏掉 SCRIPT ERROR
grep -c '\[FAIL'             # 正确
grep -c '\[FAIL\]'           # 错误！会漏掉所有 [FAIL, 原因] 形式的失败
```

**数错了会把结论整个反过来 —— 而且数错的形态不止一种。**

### 断言的牙齿

新写一条断言之后，**把代码改坏，看它红**。红的条数、红的理由都要看。
**一条从没被看见红过的检查，等于没有人对它有任何证据。**

我们这边存了一个可重跑的工具做这件事（会改源文件，所以**故意放在仓库外**）：
`D:\cozy\tools\mutation_check_*.py`（一次一条、跑、数 FAIL、**从内存还原**）。

### 另外三个坑

- **单元测试"卡住不退出"通常不是死循环** —— 是某个 `test_*.gd` **解析失败**：
  `load()` 返回一个非 null 但 `new()` 不了的脚本，`run.gd` 的守卫接不住。
  **去看日志开头的 Parse Error。**
- **单元测试里造 `Node`/`Node3D` 必须 `free()`**，否则退出时会打 ERROR（RID 泄漏），
  **`0 ERROR` 立刻变成假话**。
- **`--quit-after` 不是帧预算**，它数的是 idle 帧，和 physics 帧不同步。

---

## 7. git：两个人一个仓库

- **提交用显式路径，绝不 `git add -A`。** 另一个人（我们）的工作树里可能有未提交的改动，
  `git add -A` 会把它们一起卷进你的提交，**而且看不出是谁的**。
  ```bash
  git add items/ data/items.gd dungeon/   # 只加你改的
  ```
- **提交前先 `git pull --rebase`**，尤其是动过 `main.gd` 之后。
- **commit message 用英文**，最后一行写：
  `Co-Authored-By: Claude Code <noreply@anthropic.com>`
- **一次提交一件事。** 把"重跑了一遍格式化"混进功能提交里，会让下一次合并无法判断。

---

## 8. 停下来问的情况（不要自己定）

- 要改**美术方向 / 素材 / 相机 / 操作手感**
- 要**推翻总纲的硬规则**（不 ECS、不 EventBus、数据表 `const` 字典）
- 要改**公共文件里已有的行**（`data/materials.gd` / `docs/INVARIANTS.md`）
- 要做的东西**设计文档 §59 明说不要做**（第 1 节那条）
- **想顺手重构一个正在跑的系统** —— **借着做事做架构，是这个项目最容易翻车的地方**

---

## 9. 第一个任务建议

按依赖顺序，**从能立刻验证的开始**：

1. **Phase 9 开发者模式**（`Item Generator` / `Loot Simulator` / `Debug Stats`）——
   **纯逻辑、零世界耦合、立刻能测**，而且做完之后**后面每一条都能靠它验证**，
   不用反复手动打怪。这是文档自己写的完成标准。
2. **加装备与词条内容**（`data/items.gd` / `data/affixes.gd` 加行）——
   测试已经在跑，加行就能验证。
3. **技能系统**（现在只有两行数据，没有任何机制）—— 但**先想清楚"技能"在 V1 是什么**：
   主动技能？被动？文档 §59 把"传奇装备特殊技能"排除了，**普通技能没写**，要先定。
4. **副本地图接运行时**（`dungeon/dungeon_layout.gd` 的 `to_intents()` 已经能出墙）——
   但**注意**：运行时加墙会让导航穿过门洞（`docs/INVARIANTS.md` 记过，也是我们
   `BUILDING_ENABLED=false` 的唯一原因）。**接之前先读那一节。**
5. **Phase 8 双世界** —— **要和我们一起定**（进副本时家园那边怎么处理：暂停？卸载？）

---

## 10. 读什么（按顺序，别多读）

| 想知道 | 读 |
|---|---|
| **这个项目的硬规则 + 已经付过代价的 27 个坑** | `docs/INVARIANTS.md` ← **改行为前必读**（42 节） |
| 你的权威设计文档（Phase / 数值 / 词条 / 掉落） | `docs/design/副本世界_装备词条掉落系统_V1.0.md` |
| 架构为什么是这样（**只在要改架构时读**） | `docs/ROADMAP.md` ｜ 总纲在 Willow 那边，**先别要** |
| 美术规范（相机锁死、像素密度） | `docs/ART_PROFILE.md` |
| 素材授权台账 | `docs/CREDITS.md` |
| 状态镜像表 | `docs/ROADMAP.md` |

**不要读**：`00-架构总纲`（113 KB，改架构才读）、`main.gd` 全文（6800 行，
要接线就读第 3 节列的三个函数）。

---

*这份文档的存在理由只有一个：**让边界比技术细节先被知道**。*
*边界越界不会报错 —— 它会安静地互相覆盖，然后两个人都以为是对方的 bug。*
