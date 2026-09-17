# V2-22 · NPC 数据模型

> **状态** ⬜ 未开始 ｜ **阶段** Phase 5 NPC
> **依赖** V2-20 ✅
> **架构依据** 总纲 §43 NPCSystem ｜ §44 Job 与 Task ｜ 愿景 §9 / §10
> **代码位置** `character/npc_agent.gd`（目前是简化版）

## 一句话
NPC 是有需求、技能、激情的居民，不是会走路的 sprite。

## 要交付什么
- 完整 NPCState：identity / attributes / skills(10项) / needs / inventory / job / schedule
- 数据驱动（`data/jobs/`、`data/characters/`）
- 激情四档：厌恶 / 无感×1 / 感兴趣×2 / 热爱×4（愿景 §10）

## Definition of Done（总纲 §84 六问）
| # | 问题 | 答案 |
|---|---|---|
| 1 | 输入是什么 | 数据定义（job、技能倾向、初始需求、特性） |
| 2 | State 是什么 | `CozyNpcState` —— **这是 State，不是节点**（总纲 §18 的规则同样适用） |
| 3 | Solver / Generator 是什么 | 无（纯数据 + 每 tick 更新规则） |
| 4 | Runtime Node 是什么 | `CozyNpcAgent` 读取 State 驱动行为 |
| 5 | 如何测试 | 断言 State 可序列化往返；技能随时间成长；需求随时间衰减；激情影响工作速度 |
| 6 | 如何证明没破坏旧系统 | **现有 headless 断言必须继续全绿** |

## 现有状态
`CozyNpcAgent` 只有 `job_id` / `job_point_type` / `state` / `completions` / `last_status`。**没有技能、没有需求、没有属性、没有特性。** 工作循环是硬编码的：找 work 点 → 走 → 工作 → 重复。

## 验收断言（做完后应新增）
```
[cozyv2] npc state round-trip: skills=%d needs=%d job=%s  [OK]
```

## 下一步动作
1. `world/npc/npc_state.gd`
2. 10 项技能表（愿景 §9）+ 激情四档
3. 需求衰减规则（饥饿 / 精力 / 心情）
4. `CozyNpcAgent` 改为读 State，行为不变（先证明不回归）

---
*读这一份就够开工。若需回溯设计理由，再查总纲对应章节。*
