# V2-22 · NPC 数据模型

> **状态** ✅ 已完成（2026-09-11）
> **阶段** Phase 5 NPC
> **依赖** V2-20 InteractionPoint ✅ ｜ V2-23 Job/Task ✅
> **架构依据** 总纲 §43 / §44 / §138 ｜ 愿景 §9 / §10
> **代码位置** `world/npc/npc_state.gd`、`data/skills.gd`、`data/jobs.gd`、`data/traits.gd`

## 一句话
居民是**有属性、技能、激情、特性的数据**，不是会走路的 sprite。

## 交付了什么
- **`CozyNpcState`** —— 居民的数据（**State，不是节点**）
  - 属性：HP / 饥饿 / 精力 / 心情 / 移速 / 攻速 / 防御 / 幸运（愿景 §9）
  - 技能：10 项，0~20，**越界会被钳位而不是存进去**
  - 激情：四档，倍率 ×1 / ×2 / ×4，**厌恶＝不可指派**
  - 特性：1~3 个，由种子**确定性抽取**（E.21）
  - 背包、工种、`to_dict()`/`from_dict()`（给 V2-26 存档用）
- **`CozySkills`** —— 10 项技能表 + 激情倍率（文档规定的数值，写死在常量里）
- **`CozyJobDefs`** —— 工种表（研究员/建造/搬运/厨师/农夫）
- **`CozyTraitDefs`** —— 10 个特性，效果用 **modifier 字典**，加特性不用改代码
- **`CozyNpcAgent` 改为读 State** —— 不再自己存字段

## Definition of Done
| # | 问题 | 答案 |
|---|---|---|
| 1 | 输入是什么 | `data/` 的工种表 / 技能表 / 特性表 + 一个种子 |
| 2 | State 是什么 | **`CozyNpcState`** —— 这是本块的核心交付 |
| 3 | Solver / Generator 是什么 | 无（纯数据 + 更新规则） |
| 4 | Runtime Node 是什么 | `CozyNpcAgent` 只**读** State，不拥有它 |
| 5 | 如何测试 | 5 条断言：激情倍率 / 技能成长 / 钳位 / 特性确定性 / 序列化往返 |
| 6 | 如何证明没破坏旧系统 | 69 条断言全绿 |

## 验收断言
```
[cozyv2] passions: neutral x1 interested x2 passionate x4, hate blocked=true  [OK]
[cozyv2] working trained the skill: research=8 after 1 job(s)  [OK]
[cozyv2] skill clamp: 0..20 held  [OK]
[cozyv2] traits deterministic: ["hard_worker", "gourmet", "night_owl"]  [OK]
[cozyv2] npc state round-trip: job=Researcher traits=3 skill=0  [OK]
```

**最有说服力的是第二条**：初始 research=6、激情「感兴趣」×2 → 干完一个活变 **8**。
这证明**技能成长回路是活的**，不是一份静态快照。

## 关键决策
- **State 归数据，节点只读**
  和建筑系统同一条规则（§18）。这是 V2-26 存档能不做场景树序列化的前提。
- **激情倍率写死在常量，不写进 NPC 实例**
  文档规定了 ×1/×2/×4。放在实例上，就有实例可以不同意。
- **厌恶是"不可指派"，不是 ×0**
  **×0 仍然让工作发生、只是没收益**；文档说的是**工作不发生**。
  这两者在代码里必须是不同的分支。
- **属性越界钳位，不信任调用方**
  技能从多个地方写入，一个越界值会静默污染所有下游判定。
- **特性用 modifier 字典，不用命名字段**
  加特性是一行数据；**未知 key 是惰性的而非报错**——这样特性可以先写、效果后补。
- **`effective_work_speed()` 里故意不含激情**
  文档里激情放大的**经验**，不是**速度**。混在一起会让"热爱"的人变**快**而不是变**好**。

## 现有状态（如实）
- **只有 1 个 NPC**（Alice），工种研究员
- **特性效果大多未实现**：`modifier_sum("mood_aura")` 之类只是把数存着，
  没有系统去消费（心情衰减在 V2-25）
- **无日程、无需求衰减** —— 明确属于 V2-25，提前塞进来是猜它们的形状
- **工种只影响"找哪类交互点"和"练哪个技能"**，还没有生产链（V2-21 容器之后）
- **`CozyWorldObject` 仍只声明 `work`/`store`/`sit`/`sleep`**，
  `CozyJobDefs` 里的 `cook`/`plant`/`harvest` 目前没有对象会响应

## 下一步
- **④ NPC UI 现在有真东西可显示了**（静态值；要看到变化需 V2-25）
- 或 **V2-25 日程与需求**（解锁动态值 + 特性效果落地）
- 或 **ART-14 NPC Sprite Pipeline**（表现层）

---
*读这一份就够开工。若需回溯设计理由，再查总纲对应章节。*
