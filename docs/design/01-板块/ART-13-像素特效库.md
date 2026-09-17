# ART-13 · Pixel VFX Library

> **状态** ✅ 最小可验证对象（篝火）已完成
> **阶段** ART 美术管线
> **依赖** ART-10 资产库 ✅ ｜ ART-11 确定性种子 ✅
> **架构依据** 总纲 附录 E.18 / E.14 ｜ 第 58.3 节 Layer 4
> **代码位置** `world/vfx/vfx.gd`、`world/vfx/vfx_defs.gd`、`render/pixel_art.gd`

## 一句话
特效也是像素 sprite，走同一套 Art Grammar —— 不能"篝火像游戏 A、魔法像游戏 B"。

## 交付了什么
- **`CozyVfxDefs`**：数据驱动（帧数 / 帧时长 / 尺寸 / 高度 / 是否 additive）
- **`CozyVfx`**：循环播放的像素 billboard，**相位确定性**
- 三组占位帧：火 / 烟 / 魔法
- **`CozyWorldObject` 按定义发射特效**：`"vfx": ["fire", "smoke"]` 一行数据，
  物体系统不需要改
- 两堆篝火放进场景，用来验证相位不同步

## Definition of Done
| # | 问题 | 答案 |
|---|---|---|
| 1 | 输入是什么 | VFX 定义 id + 实例位置 |
| 2 | State 是什么 | 无 —— 特效是纯表现，不存盘 |
| 3 | Solver / Generator 是什么 | `CozyVfx.create()` + 逐帧推进 |
| 4 | Runtime Node 是什么 | `CozyVfx`（内嵌 Sprite3D） |
| 5 | 如何测试 | 2 条断言：确实在动 + 两个实例不同步 |
| 6 | 如何证明没破坏旧系统 | 51 条断言全绿 |

## 验收断言
```
[cozyv2] vfx: 2 fire effect(s), 4 frame(s), now frame 1, advanced 20  [OK]
[cozyv2] vfx desync: phases 0.095 vs 0.048                            [OK]
```

## 关键决策
- **相位由位置决定，不由定义决定**
  第一版用 `hash(def_id) ^ hash(vfx_id)` → 两堆篝火相位**完全相同**（0.035 vs 0.035），
  断言直接抓出来。总纲 E.21 的种子层级里 `ObjectID` 指的是实例位置，
  不是定义 id。改为由世界坐标生成。
- **特效要在放置后重新播种相位**
  `_build()` 在物体定位**之前**跑，那时 `global_position` 还是原点。
  加了 `refresh_vfx_phase()`，由 `_place_object()` 在定位后调用。
- **特效是数据声明的，不是代码写死的**
  物体定义里一行 `"vfx": [...]`，以后加灯笼、熔炉烟囱都不用碰物体系统。
- **断言必须分帧跑**
  `_ready()` 里一帧都没跑过，动画没东西可报。改成 frame > 120 的阶段检查
  （和遮挡检查同样的模式）。

## 诚实说明
- 特效是程序生成的占位帧，一张真素材都没有
- **只有火/烟/魔法三组**，总纲 E.18 还列了 Dust / Rain / Snow 等，未做
- **没有走粒子系统**：目前是逐帧 sprite，够用且可预测；
  真正的粒子（火星飞散等）留待以后
- VFX 的**统一色板**（E.14 的 Art Grammar）还没落地 —— 现在三组帧各用各的颜色

## 下一步
- **ART-14 NPC Sprite Pipeline**（总纲附录 K 顺序）
- 或还债「楼板/楼梯进 BuildingState」→ **V2-17 屋顶生成器**

---
*读这一份就够开工。若需回溯设计理由，再查总纲对应章节。*
