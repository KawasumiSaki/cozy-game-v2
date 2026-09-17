# ENV · 环境系统 V1.0

> **来源** Willow 2026-09-15，原样收录（本文档是权威，不重写）。
> **状态** ⬜ 未开始 ｜ **授权** Willow：「你记一下这个，没事的时候你自己去完成这些内容」
> **代码位置** 未定 —— 见下面「落地前必须先拍板的三件事」
> **写作风格要求** Willow 2026-09-15：技术文档风格，少废话、少 emoji、不堆图。

---

## ⚠️ 落地前必须先拍板的三件事（开工前读这一节）

### A. PixelRenderer 会改画风管线，与 ART-09 / `ART_PROFILE.md` 冲突

现有管线是**直接渲染**：相机锁定 `yaw 180 / pitch 40` + 窄 FOV 透视（2026-09-12 量出来的，
不是口味），像素密度与导入规则写在仓库 `docs/ART_PROFILE.md`。
本文档 §4 要求**整场景过 SubViewport → 低分辨率 → 后处理**。

**改画风属危险信号（「要拍板美术风格 → 停下来问」），所以在拍板前 V0.1 不动。**
需要一句话：PixelRenderer 是否**取代**现有渲染路径，还是只作为可切换的调试档？

### B. §3 的九个 Manager + 全局 `EnvironmentState` 与冻结的架构风格冲突

项目冻结过：**不做 ECS、不做 EventBus**（`Core Architecture V1.0 冻结提案`），
且现有写法是**数据表 + 纯求解器 + 派生**，没有 autoload，一切靠注入
（`navigator` / `clock` / `objects` / `ground` 都是注入的）。
`INVARIANTS.md` 两条硬规则：**派生不存储**、**逐帧刷新必须幂等**。
一个常驻的、可变的、被九个系统共享的全局 `EnvironmentState` 正是那条路上最容易出事的东西。

**建议（需 Willow 点头）**：分层保留（Time / Season / Weather / Wind / Cloud / Water /
Vegetation / Animal / Renderer 各司其职），但落成
**一张数据表（天气/季节/风的定义）+ 纯函数求解器（由 clock 推出 env 状态）+ 节点只做表现**，
和 `CozyBiome` / `CozyTerrainMaterials` 同一个形状 —— 而不是九个常驻单例互相读写一块大状态。

### C. §1 的真实素材 —— ✅ **已解冻**（Willow 2026-09-15）

原铁律（总纲 §58.1）「美术全部占位，不提交真实素材」**已由 Willow 解冻**，
换成一条关于**出处**的规则而不是关于占位的规则：

> **素材可以进仓库，但每一条都要在仓库 `docs/CREDITS.md` 记
> 来源 / 作者 / 授权，且授权必须允许再分发（MIT / CC0 / CC BY）。
> 授权不明的，一律不收。**

**所以 §1 那一串（Ninja Adventure / Kenney / Tiny Forest / OpenGameArt /
Poly Haven）现在可以用了**，但**每一条落盘时都要带一条 CREDITS 记录**。
CC BY 的署名义务还要能到玩家手里 —— 游戏里目前**没有 credits 界面**，
这笔账记在 `docs/CREDITS.md` 里，别让它变成"声明了没有消费者"。

---

## 已经有东西在跑（别重做）

| 本文档 | 现状 |
|---|---|
| V0.2 昼夜 | **大半已有**：`core/time_system.gd`（day/hour/season/`is_night()`）+ `main.gd` 的 `_light_the_world()`（太阳方向/颜色/环境光）+ 灯的 `CozyWorldObject.set_light_level(darkness)`（2026-09-14）。**缺的是天气与云对光的联动** |
| §11 四季 | **有时钟里的季节值，但「nothing consumes them yet」**（`time_system.gd` 自己的注释）。所以四季是「值在、消费者没有」 |
| §6 风 · 植物摆动 | 地形散布已是 MultiMesh + 地面 shader（ART-11）。**风是加进 shader 的参数，不是新系统** |
| §10 地面/岸线 | 地形材质链 `Grass → Soil → Farmland` 在（V2-11），**但没有湿度/湿岸** |
| §2 小动物 | 完全没有。NPC 侧只有 `CozyNpcAgent` 一个居民 |

## 开发顺序（按依赖重排的建议）

```
可以现在做（不依赖 PixelRenderer）
  V0.3 WindManager          —— 一个数据源 + 注入，风格与 clock 一致   ✅ **已完成 2026-09-15**（`core/wind_system.gd`）
  V0.4 草/树 风 shader      —— 加进现有 MultiMesh shader
  V0.5 云 / 云影            —— World space + noise，不动主渲染路径
  V0.7 雨雪                 —— GPUParticles3D + 现有 light/vfx 词汇

要等拍板
  V0.1 PixelRenderer        —— 见 A

最大的一块，单独排
  V0.6 水 / 河流 / 水位     —— 新水体 + Path3D/Spline + 岸线湿度 + 结冰

依赖前面
  V0.8 SeasonManager（消费已有的季节值）
  V0.9 AnimalManager（新一类 actor）
```

**核心原则（原文照录）**：
> 3D素材负责内容；Shader负责视觉；Manager负责逻辑；EnvironmentState负责全局状态；PixelRenderer负责最终统一画风。

---

# 以下为 Willow 原文

## 1. 素材

### 3D基础素材

* 树木：Tree / Pine / Bush / Dead Tree
* 植物：Grass / Flower / Mushroom / Crop
* 地形：Grass / Dirt / Sand / Stone / Snow
* 建筑：Wall / Floor / Roof / Door / Window / Stair
* 家具：Bed / Table / Chair / Chest / Crafting Station
* 动物：Rabbit / Bird / Butterfly / Deer / Fish
* 环境：Rock / Log / Branch / Fallen Leaf
* 天空：Sky / Cloud / Moon / Sun

### 推荐免费来源

* Ninja Adventure：森林、建筑、NPC、动物、怪物、VFX，CC0
* Kenney：Pixel / 3D / Dungeon 等，CC0
* Tiny Forest：森林、草、树、花，CC0
* OpenGameArt：Pixel Art / Tileset / VFX
* Poly Haven：3D模型、材质、HDRI，CC0

原则：**普通3D素材优先，统一通过 Godot Pixel Renderer 转成像素风。**

---

# 2. 最终效果

### 昼夜

* 黎明 → 白天 → 黄昏 → 夜晚
* 太阳方向、强度、颜色变化
* Sky / Fog / Ambient Light 联动

### 四季

* 春、夏、秋、冬
* 草木颜色变化
* 开花、落叶、积雪
* 水位、动物活动变化

### 天气

* 晴天
* 多云
* 下雨
* 暴雨
* 下雪
* 暴雪

### 云

* 晴天少云
* 多云增加云量
* 下雨出现大型厚云
* 云随风移动
* 大型云影扫过地面
* 云量影响环境亮度

### 风

* 草、树、树叶摆动
* 云移动
* 雨雪倾斜
* 支持阵风

### 水

* 湖泊、池塘、河流、溪流
* 溪流有流向和流速
* 水位动态变化
* 暴雨导致水位上涨
* 水边地面变湿/泥化
* 冬季可扩展结冰

### 小动物

* 兔、鸟、蝴蝶、鹿、鱼
* 漫游、进食、休息、逃跑
* 昼夜、天气、季节影响行为

---

# 3. 总体架构

```text
World
├── WorldTime
├── SeasonManager
├── WeatherManager
├── WindManager
├── CloudManager
├── WaterManager
├── VegetationManager
├── AnimalManager
└── PixelRenderer
```

所有系统共享：

```text
EnvironmentState
├── time_of_day
├── season
├── temperature
├── humidity
├── rain_intensity
├── snow_intensity
├── wind_speed
├── wind_direction
├── wind_gust
├── cloud_coverage
├── cloud_density
├── cloud_darkness
├── cloud_speed
└── water_level
```

---

# 4. Pixel Renderer

```text
3D Scene
↓
SubViewport
↓
低分辨率渲染
↓
Nearest Filter
↓
Depth + Normal + Albedo
↓
Post Process Shader
├── Pixelation
├── Depth Edge
├── Normal Edge
├── Outline
└── Color Quantization
↓
Final Image
```

普通3D模型不需要制作成像素模型。

---

# 5. CloudManager

## 天空云

使用 Noise：

```text
Low Frequency Noise
+
High Frequency Noise
↓
Cloud Shape
↓
Cloud Coverage
↓
Cloud Density
```

参数：

```text
cloud_coverage
cloud_density
cloud_speed
cloud_scale
cloud_softness
```

通过 World/UV + TIME 控制移动。

## 地面云影

使用 World Space：

```text
WorldPosition.xz
↓
Large Scale Noise
↓
Wind Direction × Time
↓
Cloud Shadow Mask
↓
降低地面亮度
```

特点：

* 云影不随屏幕移动
* 大面积云块
* 软边缘
* 云量越高，阴影越明显

## 光照联动

```text
CloudDarkness
↓
DirectionalLight3D Energy ↓
Ambient Light ↓
Ground Shadow ↑
```

天气转换：

```text
晴天
↓
多云
↓
厚云
↓
天空变暗
↓
云影增强
↓
下雨
```

---

# 6. WindManager

统一控制：

```text
wind_direction
wind_speed
wind_gust
```

影响：

```text
Cloud
Rain
Snow
Grass
Tree
Leaves
```

植物使用 Vertex Shader：

```text
Wind =
sin(
    TIME * WindSpeed
    + WorldPosition.x * FrequencyX
    + WorldPosition.z * FrequencyZ
    + InstanceRandom
)
```

根部基本不动，顶部摆动最大。

不同实例加入 Random，避免所有植物同步运动。

---

# 7. WeatherManager

天气：

```text
SUNNY
CLOUDY
RAIN
STORM
SNOW
BLIZZARD
```

使用插值过渡：

```text
CurrentWeather
↓
Transition
↓
TargetWeather
```

天气不是瞬间切换。

例如：

```text
SUNNY
→ CLOUDY
→ RAIN
→ STORM
→ RAIN
→ CLOUDY
→ SUNNY
```

---

# 8. Rain / Snow

## Rain

使用 `GPUParticles3D`：

```text
rain_intensity
rain_velocity
rain_lifetime
rain_direction
```

方向受 WindManager 控制。

## Snow

使用 `GPUParticles3D` + 地面积雪 Shader：

```text
snow_intensity
snow_accumulation
temperature
wind
```

积雪逐渐覆盖：

```text
Grass
Ground
Roof
Tree
```

---

# 9. WaterManager

WaterBody：

```text
type
height
water_level
flow_direction
flow_speed
depth
shore_mask
```

类型：

```text
LAKE
POND
RIVER
STREAM
```

## 溪流

```text
Path3D / Spline
↓
生成 River Mesh
↓
计算 Flow Direction
↓
Water Shader
```

水流：

```text
UV += FlowDirection × FlowSpeed × TIME
```

## 水位

```text
Rain
+
River Inflow
-
Evaporation
↓
WaterLevel
```

水位变化影响河面高度和岸线。

---

# 10. Ground / Shore

根据水体距离计算：

```text
WaterDistance
↓
Wetness
```

```text
Wetness ↑
↓
颜色变暗
Reflection ↑
Roughness ↓
```

形成：

```text
Water
↓
Wet Shore
↓
Mud
↓
Grass
```

---

# 11. SeasonManager

```text
SPRING
SUMMER
AUTUMN
WINTER
```

优先使用 Shader / Material 参数，而不是大量替换模型。

### Spring

* 草变绿
* 花增加
* 植物生长

### Summer

* 植被最茂盛
* 水位较高
* 雷雨概率增加

### Autumn

* 树叶变黄/红
* 落叶
* 风增强

### Winter

* 落叶树变裸
* 积雪
* 水体可结冰

---

# 12. AnimalManager

状态：

```text
IDLE
WALK
EAT
RUN
FLEE
SLEEP
```

Spawn条件：

```text
Biome
Season
TimeOfDay
Weather
```

行为示例：

```text
白天 + 晴天
→ 鸟、蝴蝶、兔子活动增加

夜晚
→ 鸟类减少，夜行动物增加

下雨
→ 动物寻找遮蔽物

玩家靠近
→ FLEE
```

---

# 13. 开发顺序

```text
V0.1 PixelRenderer
V0.2 WorldTime / DayNight
V0.3 WindManager
V0.4 Grass / Tree Wind Shader
V0.5 Cloud / Cloud Shadow
V0.6 Water / River / WaterLevel
V0.7 Rain / Snow
V0.8 SeasonManager
V0.9 AnimalManager
V1.0 全系统联动
```

核心原则：

> **3D素材负责内容；Shader负责视觉；Manager负责逻辑；EnvironmentState负责全局状态；PixelRenderer负责最终统一画风。**
