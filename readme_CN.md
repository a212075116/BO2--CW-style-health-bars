# BOCW 风格僵尸血条 — 黑色行动 2（Alpha）

**[English](readme.md) | 简体中文**

> **《使命召唤：黑色行动 2》（Plutonium T6）— 僵尸模式**
> 仓库：<https://github.com/a212075116/BO2--CW-style-health-bars>

mod：给每只僵尸加一个 **COD17 / 黑色行动冷战风格的悬浮血条**，命中时还有
**漂浮伤害数字**。

---

## 简介
- 这是一个十分缺乏测试的 mod，我仅是单人模式下测试过，并没有进行过像样的多人测试，也没有进行游玩到大后期的程度的测试。也就是说这个 mod 很可能并不稳定。

- **血条挂在头部骨骼上。** 每只僵尸会被绑定一个隐形锚点实体，`linkto()` 到它的眼/头骨骼，
  所以血条跟的是真正的头部——僵尸前倾、扑击、狗低头时都会跟着走，而不是"脚底原点 + 猜测高度"。
- **任意距离都保持透视正确。** 血条的**尺寸**和**离头高度**都随玩家-僵尸距离缩放，
  远处的僵尸得到的是按比例变小的血条，而不是比僵尸还宽、把它盖住的条。
- **离头高度刻意走屏幕空间。** 如果沿**世界铅垂方向**抬升，当你站在高处**俯视**僵尸时，
  这段抬升会按 `cos(俯角)` 被压缩、塌回僵尸身上并遮住它的头；屏幕空间的抬升不受相机俯仰影响。
- **默认近距显示**：僵尸靠近时血条渐显，超过阈值渐隐（隐藏但仍"占位"，避免闪烁）。
- **准星窥探**：把准星对准某只僵尸，**无论多远**都会显示它的血条（仍需有清晰视线）。
- **特殊僵尸有独立名字与图标颜色**：地狱犬、剧院爬行者、起源机甲、监狱典狱长、圣殿火焰僵尸
  等等（完整见下方表格）。
- **可与其它 Lua mod 共存**——`ui_mp/t6/hud.lua` 发布的是**未经修改的官方文件 + 末尾一行
  `require`**，所以入口被别的 mod 占据时也不会丢功能（见"与其它 Lua mod 共存"）。

---

## 功能一览

- **血条**
  - 红条 + 黑框，锚定在僵尸头部骨骼上。
  - 白色"残影"延迟拖尾：受击时红条瞬间掉、白条缓慢跟进，形成平滑掉血。
  - 死亡时血条在约 0.6s 内衰减到 0 再消失。
- **显示规则**
  - 近距渐显：`d ≤ 150` 满亮，`150 < d ≤ 300` 线性淡出，超过 300 隐藏
    （单位为英寸：150 ≈ 3.8 m，300 ≈ 7.6 m）。
  - **准星判定**：对僵尸胸部 `dot > 0.99`（很苛刻），**且没有距离上限**。
  - **视线遮挡（LOS）**：墙/低掩体会挡住显示（`bullettracepassed` 检测）。
- **图标 + 名字**，判定依据是实体的 `animname`（BO2 自己就是靠这个字段区分僵尸种类的）：

  | 僵尸 | 名字 | 图标颜色 |
  |------|------|----------|
  | 普通僵尸 | `ZOMBIE` | 红 |
  | 地狱犬 | `HELLHOUND` | 橙 |
  | 剧院爬行者（quad） | `CRAWLER` | 紫 |
  | 起源机甲僵尸 | `MECH` | 青 |
  | 监狱典狱长（Brutus） | `WARDEN` | 浅红 |
  | 圣殿火焰僵尸 | `FLAME` | 热橙 |
  | 尖啸者 | `SHRIEKER` | 绿 |
  | 跳跃者 | `LEAPER` | 黄 |
  | 幽灵 | `GHOST` | 淡蓝白 |
  | 阿斯特罗僵尸 | `ASTRO` | 蓝 |
  | 猴子炸弹 | `MONKEY` | 棕 |
  | 巨人步行机甲 | `ROBOT` | 钢灰 |

  血条下方显示名字，白字带黑阴影。未登记的类型仍显示 `ZOMBIE`。
- **伤害数字**
  - 从**命中点**弹出，**竖直向上**飘并淡出。
  - 颜色从**红渐变到白**。
  - 上飘速度随距离自适应：贴脸的命中滞空更久（近战也看得清），远距离正常速度。
  - 数字池 16 个，快速连击能各自叠一个。
  - **致命一击也弹。** 原版 `_zm_spawner::enemy_death_detection()` 会在伤害回调触发之前
    就用 `if ( !isalive(self) ) return;` 提前返回，所以一击必杀根本走不到任何伤害回调。
    本 mod 改走引擎的 actor-KILLED 通道捕获，且那里的伤害值已经是**乘算之后**的数值——
    也就是显示的数字等于实际掉的血。
  - 致命一击的数字会优先复用**上一次非致命命中的位置**，所以它出现在你打中的地方，
    而不是尸体身上。
- **击杀提示** —— `+100 Zombie Elimination`；致命一击打在头上时是琥珀色的 `+100 Zombie Critical Kill`
  - 显示在**准星右侧**，与还原对象的做法一致。
  - `critical` 的条件是**致命那一击**落在 `head` / `helmet`——与原版计分代码认定的爆头部位完全相同，
    所以提示文字和实际加的分永远对得上。近战与燃烧击杀也照搬原版优先级（一律不算 critical）。
  - 分数**不是写死的表**：它重放了原版 `_zm_score::player_add_points()` 的 death 分支——
    `get_zombie_death_player_points()` + 部位奖励，再 `round_up_score(…, 5)`，最后 `× get_points_multiplier()`。
    因此人数对应的击杀分、分数倍率、以及任何分数改平衡都会自动跟随，这边无需维护数字。
  - **先静止 3 秒**，随后淡出并向右滑约 14 px。竖直方向不会自己乱动：新提示**插到最上面一行**，
    把已有的每一条往下顶一行——是平滑滑行，不是瞬移——所以连续击杀看起来像队伍不断从顶部补进来；
    中途消失的那条也会让下面的平滑回位。被顶出最后一行的那条，会在往下走的过程中淡掉，永远不会
    作为"第 6 行"静止出现——这也是元素池刻意做成 `MaxKill + 1` 个的原因。
  - 分数与文字是**两个独立元素**，因为两者的入场方式不同（慢放视频里看出来的）：`+100` 以约 1.9 倍
    尺寸弹出、并在约 0.26 秒内缓动收回到 1.0 倍；文字则是直接出现。缩放过程每帧重算分数的框位，
    让它的**右缘始终钉在文字的左边缘**——否则「以元素中心缩放」会让两者之间的间隙一开一合。

---

## 控制台变量

| 命令 | 作用 |
|------|------|
| `setdvar zh_animname 1` | **名字探针（诊断用）。** 任何*没有*登记在上表的僵尸，会把它的原始 `animname` 直接当作标签显示出来，于是新怪物会在屏幕上"自报家门"。你把那串字填进 GSC 的分发链并在 `ICON_TINT` 加一行配色，就可以关掉探针了。 |
| `setdvar zh_animname 0` | 关闭（默认）。已登记的名字**永远不受探针影响**，所以找新怪时可以让它一直开着。 |

该 dvar 是每轮实时读取的，不是加载时快照：**改完立刻生效，不用重启**。（但改代码要重启——
GSC 不是热重载的。）

---

## 文件构成

```text
scripts/
  zh_healthbars.gsc                  # 服务端 GSC（自带 init() 入口，完全自包含）

ui_mp/
  t6/hud.lua                         # 官方 hud.lua + 末尾一行 require
  t6/zombie/zombiehealthbars.lua     # LUI 组件本体（血条 + 伤害数字）
  t6/zombie/zhbmount.lua             # 挂载 shim：包住宿主的 HUD 入口函数
```

`hud.lua` 现在**已经不是一份被改写的文件**——拿它和游戏原版做 diff，唯一的区别就是末尾几行：

```lua
require("T6.Zombie.ZHBMount")     -- 本 mod 放进 hud.lua 的全部内容

DisableGlobals()
Engine.StopEditingPresetClass()
```

这一行就是全部的接入面。它刻意放在 `DisableGlobals()` **之前**：挂载过程仍需要写全局，
而 `DisableGlobals()` 会把这扇门关上。两种安装路线见下面"与其它 Lua mod 共存"一节。

---

## 工作原理（数据流）

GSC 每约 0.1s 遍历所有僵尸 / 地狱犬 / 爬行者，把数据打包进多个**客户端 dvar**
（分批，避免单个 dvar 过长被截断）：

```text
zh_data_0 .. zh_data_N    "entityNum:ratio100:alpha100:name:distance;..."
```

- `entityNum` 在有锚点时是**头部锚点实体**的编号（该锚点 `linkto()` 在僵尸眼/头骨骼上），
  没有可用骨骼时才是僵尸本体。
- `distance` 是服务端算好的玩家-僵尸距离，LUI 正是靠它给每只僵尸分别缩放血条尺寸与离头高度。

LUI 每约 0.1s 轮询这些 dvar，按实体号 key 出每只的血条，用 `setupEntityContainer` 跟随实体。

伤害数字走独立事件通道：

```text
zh_dmg    "entityNum:amount:seq:distance;..."
```

LUI 读取后，每个命中占用数字池一个槽位，锚定到 GSC 在命中点生成的静态锚点，竖直上飘。
`seq` 是每个玩家各自的计数器，用于去重，保证同一次命中不会在相邻两次轮询里被画两遍。

击杀提示走第三条通道，格式与去重方式相同：

```text
zh_kill   "seq:score:isCritical;..."
```

它的队列保留时间是 **1.2 秒而不是 0.3 秒**：提示要在屏幕上停留好几秒，事件就必须活得足够久，
让 0.1 秒的轮询即使在极快双杀时也至少抓到一次。每条都带着击杀者自己的计数器，且只写那个玩家的
客户端 dvar——合作模式下谁也看不到别人的提示。

**为何不用 `luinotifyevent` / client field / server dvar？** 本作这些通道不可用或预算耗尽；
**客户端 dvar + `UIExpression.DvarString`** 是实测唯一能到达 LUI 的可靠通道。

**为什么用逐实体的击杀钩子，而不是全局回调？** 本 mod 刻意**不占用任何 `level.*` 回调单例**
（`level.callbackActorDamage`、`level.callbackactorkilled` 一概不碰）：伤害侧注册进的是
**数组式**回调列表（多个注册者可共存），击杀侧只写自己实体的 `actor_killed_override` 槽位。
因此它与其它改武器伤害的 mod 完全互不干扰——叠在武器伤害 mod 上面安装是安全的，而且显示的数字
就是那些 mod 实际打出来的伤害。

---

## 可调参数

### LUI —— `ui_mp\t6\zombie\zombiehealthbars.lua` 顶部

| 常量 | 含义 | 默认 |
|------|------|------|
| `BARW` / `BARH` | 参考距离下的血条宽 / 高 | `60` / `6` |
| `HEADZ_TABLE` | 距离 → 离头高度（像素）曲线。每行 `{ 距离, 像素 }`；行**之间**线性插值，所以随距离平滑抬升、不会有台阶。可自由增改，距离必须递增。 | `50→13, 100→16, 150→18, 250→21, 500→23` |
| `HEADZSCALE` | 整条曲线的整体倍率（一次性上下平移） | `1.0` |
| `BARDISTREF` | 该距离上血条等于设计尺寸；缩放为 `k = BARDISTREF / dist` | `300` |
| `BARSCALEMAX` | **只给"放大"这一侧设上限**。随距离缩小永远不封顶，所以远处的透视缩放依然真实。取 `1.2` 时，近于 `BARDISTREF / BARSCALEMAX`（= 250）就不再变大。 | `1.2` |
| `ICONW` / `ICONGAP` | 左侧图标尺寸 / 与血条间距 | `12` / `6` |
| `ICON_TINT` | 名字 → 图标 RGB。新僵尸种类 = 这里加一行（外加 GSC 里一个 `else if`）。未知名字回退到 `ZOMBIE` 的颜色。 | 见上表 |
| `MaxDmg` | 伤害数字池大小 | `16` |
| `DMGSTEPS` | 上飘帧数（约 0.85s；越大越慢） | `17` |
| `DMGRISE` | 总上升像素 | `30` |
| `DMGSLOW` | 近距离额外滞空帧数（越近越慢） | `18` |
| `DMGDISTREF` | *上飘速度*自适应所用的距离参考 | `200` |
| `NUMDVARS` | 分批 dvar 数量 | `8` |
| `MaxKill` | **可见行数**。元素池是 `MaxKill + 1` 个，好让被挤出去的那条仍有元素可以用来淡出 | `5` |
| `KillMoveMs` | 走完一行所需的毫秒数——即新提示插入时整队往下滑多快 | `200` |
| `KillEjectMs` | 被顶出最后一行的那条，一边往下走一边淡出所需的毫秒数 | `300` |
| `KillHold` / `KillFade` | 静止显示帧数，随后的淡出帧数（每帧 50ms） | `60`（3.0s）/ `16`（0.8s） |
| `KillX` / `KillY` | 提示起点，单位是 **LUI 逻辑单位**，相对屏幕中心向右 / 向上 | `137` / `-18` |
| `KillSlide` | 淡出阶段向右平移的逻辑单位（仅此阶段发生） | `10` |
| `KillStack` / `KillH` | 车道间距 / 文本框高度 | `18` / `20` |
| `KillNumW` | 为分数部分预留的宽度；它的右缘就是文字的左边缘 | `64` |
| `KillPop` / `KillPopMs` | 分数弹出：起始倍率 / 收缩持续多久 | `1.9` / `260` 毫秒 |
| `KillTick` | 驱动缩放的快速时钟间隔。只在有提示存在时存在，所以不击杀时零开销 | `25` 毫秒 |

> `DMGTOP` 和 `DMGBODY` 仍保留定义但**已不再被引用**——早先基于距离的"起始高度"插值，已被
> "直接在命中点生成数字"取代。

> **LUI 单位不是像素。** 16:9 下逻辑空间是 **1280×720**（`spectate.lua:16` 里
> `CoD.SpectateHUD.ScreenWidth = 1280`），所以 `1 单位 = 显示宽度 / 1280`
> （在宽 1775 px 的截取画面上约等于 1.387 px）。也就是说从截图量出来的像素要先除以这个比例：
> `190 px → 137 单位`、`25 px → 18 单位`。代码注释里写的"px"其实都是这些逻辑单位。

> **可用的字号**（`codbase.lua:112-118`）：`ExtraSmall` < `Default`(smallFont)
> < `Condensed`(normalFont) < `Big`(bigFont) < `Morris`(extraBigFont)。既**没有** `CoD.fonts.Bold`，
> 也**没有** `setFontSize`——取一个未注册的名字不会报错，只会静默退化成默认字体。

### GSC —— `scripts\zh_healthbars.gsc`

| 设置 | 值 |
|------|-----|
| 显示距离 | 满亮 `150`；超过 `300` 隐藏 |
| 准星显示 | `dot > 0.99`，**无距离上限** |
| 死亡衰减窗口 | `600` ms |
| 分批大小 | `zh_batch = 10`（每批僵尸数）；`zh_dvars = 8`（dvar 数） |
| 头部骨骼探测 | `tag_eye`、`j_head`、`J_EyeBall_LE`、`tag_head`（取第一个能解析出来的） |
| 采集轮询 | `0.05` s |

---

## 安装

两种安装方式：

**方式一：装到已有的 mod 上**

```text
%localappdata%\Plutonium\storage\t6\mods\<你想装的那个 mod 文件夹>
```

**方式二：直接装到存储目录下**

```text
%localappdata%\Plutonium\storage\t6
```

> GSC 与 LUI 是两套独立注入，**两边都必须放到位**才生效。
> mod 目录里的散装 `.gsc` 会覆盖打包好的 `mod.ff`，所以改了重启即可，不用重新打包。

按文件对应放置（`<位置>` = 上面选定的那一个）：

| 文件 | 放到 `<位置>\` 下 |
|------|------|
| `scripts\zh_healthbars.gsc` | `scripts\` |
| `ui_mp\t6\zombie\zombiehealthbars.lua` | `ui_mp\t6\zombie\` |
| `ui_mp\t6\zombie\zhbmount.lua` | `ui_mp\t6\zombie\` |
| `ui_mp\t6\hud.lua` | `ui_mp\t6\` —— **仅当没有其它 mod 占用该文件时装**，见下一节 |

---

## 与其它 Lua mod 共存

LUI 只有**一个**入口文件：`ui_mp/t6/hud.lua`。两个 mod 都带它时，Plutonium 按 mod 优先级
**整文件覆盖**（不报错、不提示），输的那份**完全不执行**。更糟的是官方 `hud.lua` 里的辅助函数
都是**全局函数**，即使两份都执行了，最后定义 `HUD_FirstSnapshot_Zombie` 的那个会把对方的实现
**静默吃掉**。

所以规则是：**入口唯一，其余全部走 `require`**。本 mod 只贡献一行 `require`，剩下的都在自己的
文件里完成；`zhbmount.lua` 是**包住（wrap）**宿主的函数，而不是重定义它：

```lua
local prev = HUD_FirstSnapshot_Zombie
HUD_FirstSnapshot_Zombie = function(HUDWidget, ClientInstance)
    prev(HUDWidget, ClientInstance)   -- 先跑宿主原版，一行不损
    zhBarsAttach(HUDWidget)           -- 再挂我们自己的 widget
end
```

### 两种情况任选其一

**A —— 没有别的 mod 动 `hud.lua`**（常见情况）：把"文件构成"里的三个文件按路径装好，收工。

**B —— 别的 mod 占据了 `hud.lua`**：**不要**装本 mod 的 `hud.lua`。改为在*对方*那份
`hud.lua` 的**最末尾**、`DisableGlobals()` 之前，加上同样的一行：

```lua
require("T6.Zombie.ZHBMount")
```

然后只装 `t6\zombie\` 下的那两个文件。两个 mod 都能正常工作，而且**对方日后更新也不会把我们的
挂载覆盖掉**（入口始终由对方自己维护）。

### 仍然可能撞车的点

| 共享资源 | 本 mod 用的名字 | 风险 |
|---|---|---|
| `ui_mp/t6/hud.lua` | 官方文件 + 1 行 | 唯一的硬冲突——用上面的 B 方案绕开 |
| 全局函数 | 只 wrap，不重定义 | 低 |
| 全局命名空间 | `CoD.ZombieHealthBars`、`CoD.ZombieHealthBarsMount` | 独占，安全 |
| `LUI.createMenu` 键 | `ZombieHealthBars` | 独占，安全 |
| 事件名 | `zombie_bars` | 自定义，安全 |
| 客户端 dvar | `zh_data_0..7`、`zh_dmg` | 独占前缀，安全 |
| GSC 回调 | 不占用任何 `level.*` 单例 | 已与武器伤害类 mod 实测共存 |

剩下唯一需要眼睛确认的是 **HUD 图层顺序**：我们的 widget 是 `addElement` 到 HUD 根，绘制次序
跟随添加次序。若对方 mod 也在 HUD 根画大面积元素，可能互相遮挡——调换两边 `require` 的先后即可，
不涉及功能损失。

---

## 已知限制

- **测试严重不足**，且仅单人。见"简介"。
- 血条跟随的是**骨骼锚点**，因此需要模型上真有可用的头骨。若探测列表里的骨骼一个都解析不出，
  会退回使用僵尸本体原点，该怪的血条就会偏低——火焰僵尸之类的自定义模型最可能是这种情况。
- 尺寸随距离变化意味着**远处的血条确实很小**。这正是目的（它不再盖住僵尸），但代价是极远处
  会难以读清。
- 伤害数字锚点是**共享的静态实体池**：若同时有超过 `MaxDmg` 个数字在飘，最旧的数字可能
  被新命中"借用"同一锚点而跳位（单人/LAN 基本无感）。
- **引擎的击杀回调不给命中坐标**（那里的 `shitloc` 是"命中部位名"，例如 `"helmet"`，不是坐标）。
  所以致命一击的数字会优先复用上一次非致命命中的位置；若是从满血一发带走，则退回身体命中位置、
  再退回僵尸位置，只能说是近似值。
- 如果有**第三个** mod 也 wrap 了 `HUD_FirstSnapshot_Zombie`，包装顺序决定谁最后执行。我们只是
  往 HUD 上加一个 widget，所以先后都能叠加，但多层 HUD mod 叠装时仍请留意。
- 多人游戏中每个玩家的伤害数字发到各自 client dvar，彼此独立。但血条**可见性**虽按玩家分别计算，
  共享的仍是同一批僵尸集合，4 人以上未做压力测试。
- 血条是**客户端注入（ui_mp）**；若 `ui_mp` 被清空或加载失败，血条会缺失。

---

## 致谢 / 参考资料
- **JariKCoding** — [CoDLUIDecompiler](https://github.com/JariKCoding/CoDLUIDecompiler) 与 [CoDLuaDecompiler](https://github.com/JariKCoding/CoDLuaDecompiler)
- **plutoniummod** — [t6-scripts](https://github.com/plutoniummod/t6-scripts)
- **Treyarch / Activision** — `bo3_scriptapifunctions`
- **KingslayerKyle** — [T7LuaRepo](https://github.com/KingslayerKyle/T7LuaRepo)
- **Laupetin** - [OpenAssetTools](https://github.com/Laupetin/OpenAssetTools)

---

*通过"vibe coding"快速完成（包括本文档的一部分）。如果你知道更好的做法，欢迎改进。*
