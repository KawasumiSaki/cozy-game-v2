# UI-02 · NPC 居民面板

> **状态** ✅ ｜ **阶段** UI 界面（本项目新增编号）
> **依赖** V2-22 NPC 数据模型 / V2-25 日程与需求 / UI-01 界面基础
> **架构依据** 总纲 §70（UI 不许碰 Mesh）
> **代码位置** `ui/npc_panel.gd`（面板）· `main.gd`（`_build_hud` / `_open_npc_panel` / `_refresh_npc_panel` / `_check_npc_panel`）

## 一句话
把 V2-22 和 V2-25 已经算出来但**没人看得见**的居民数据（属性 / 十项技能 / 激情 / 需求 / 日程）
变成右键一个人就能看的活面板。

## 要交付什么
- 右键居民 → 菜单出现 `Resident` → 打开面板
- 面板五段：header（名字 / 工种 / 当下在做什么）、NEEDS（三条会动的条）、
  ATTRIBUTES、SKILLS（十项 + 激情标记）、SCHEDULE（文档 §114 那一天，当前段高亮）
- 面板每帧刷新，需求值随时间真实变化
- `Esc` 关闭面板

## Definition of Done（总纲 §84 六问）
| # | 问题 | 答案 |
|---|---|---|
| 1 | 输入是什么 | 右键命中的 `CozyNpcAgent` + `clock.hour` |
| 2 | State 是什么 | **无新 State**。只读 `CozyNpcState` / `CozySchedule`，面板从不改居民 |
| 3 | Solver / Generator 是什么 | 无。表现层，没有求解 |
| 4 | Runtime Node 是什么 | `CozyNpcPanel extends PanelContainer`，挂在 HUD 的 CanvasLayer 上 |
| 5 | 如何测试 | `_check_npc_panel()`，6 条断言，含**幂等性**与菜单→面板端到端 |
| 6 | 如何证明没破坏旧系统 | **现有 headless 断言必须继续全绿**（75 → 81） |

## 现有状态
已做完并接线。面板挂在 HUD 的 CanvasLayer，锚定右上，初始隐藏。

**刻意不做 Relations 页**：没有社交系统，做出来必然永远空白 ——
一个永远空白的页在教玩家"这个面板坏了"。

**刻意不做 Inventory 页**：V2-21 只完成了库存类，没有物品系统，同理。

## 验收断言（做完后应新增）
```
[cozyv2] npc panel: built on the HUD, hidden until asked  [OK]
[cozyv2] npc panel rows: 10/10 skill(s), 9/9 schedule row(s)  [OK]
[cozyv2] npc panel content: "Probe Resident" hunger=40 frac=0.40 marked=09:00  [OK]
[cozyv2] npc panel refresh idempotent over 600 frames: unchanged  [OK]
[cozyv2] menu opens the resident panel: npc_001 -> "Alice"  [OK]
[cozyv2] resident panel closes again: true  [OK]
```

> **幂等那条是这里唯一真正有价值的一条。**
> 面板每帧重绘，而它出生时带的版本会从**自己上一次的输出**里重新推导每一行日程文本
> （`substr(6)`，而 6 对两种格式都不对），于是每秒腐蚀 60 次。
> 其余每一条断言在那个 bug 存在时**全都照样通过** —— 面板存在、接线正确、
> 行数对、单次刷新输出正确。只有"刷两次"能抓到它。
>
> 已实测验证过这条断言的牙齿：把旧代码放回去，它确实变红，并打出
> `"> 09:00  0  Working" -> "> 09:00  0  0  0  0 ... Working"`。

## 坑（已付过代价）
1. **`agent.state` 不是居民状态**。`CozyNpcAgent.state` 是它的 **FSM 枚举**
   （`IDLE/GOING/WORKING`），居民数据在 `npc_state`。照抄墙上那句 `probe["node"].state`
   会拿到一个整数 —— **不报错、不崩，只是面板永远空白**。
2. **`▶`（U+25B6）在默认字体里不保证有**。本项目不加载任何字体文件，
   UI 全用 Godot 默认字，缺字渲染成豆腐块。已换成 ASCII `>`。
3. 面板出生时**没有任何地方引用它**（grep 全仓库只有它自己第 1 行的 `class_name`）。
   写完了、磁盘上有、能 import —— 但没被实例化、没被测试过一次。
   **"能解析"离"能用"很远**，这正是上面 bug 1 和 2 能活下来的原因。

## 下一步动作
1. 从目录「已知欠债」里挑：V2-12 道路系统 / V2-13 地基求解器 / V2-21 容器与背包 / V2-26 存档系统

---
*读这一份就够开工。若需回溯设计理由，再查总纲对应章节。*
