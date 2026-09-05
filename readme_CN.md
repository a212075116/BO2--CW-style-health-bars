# BOCW 风格僵尸血条 — 黑色行动 2（Alpha）

> **《使命召唤：黑色行动 2》（Plutonium T6）— 丧尸模式**

一个丧尸 mod：给每只僵尸加一个 **COD17 / 黑色行动冷战风格的悬浮血条**，命中时还有
**漂浮伤害数字**。


---

## 简介

- **默认近距显示**：丧尸靠近时血条渐显，超过阈值渐隐（隐藏但仍"占位"，避免闪烁）。
- **准星窥探**：把准星对准某只丧尸，即使隔远也会显示它的血条（但必须有清晰视线）。
- **支持地狱犬**：有独立的血条、橙色图标、名字显示 `HELLHOUND`。

---

## 功能一览

- **血条**
  - 红条 + 黑框，悬浮在头顶上方。
  - 白色"残影"延迟拖尾：受击时红条瞬间掉、白条缓慢跟进，形成平滑掉血。
  - 死亡时血条在约 0.6s 内衰减到 0 再消失。
- **显示规则**
  - 近距渐显：越近越亮（≤100 满亮，超过约 260 隐藏）。
  - **准星判定**：对丧尸胸部 `dot > 0.99`（很苛刻）。
  - **视线遮挡（LOS）**：墙/低掩体会挡住显示（`bullettracepassed` 检测）。
- **图标 + 名字**
  - 血条左侧一个方形图标：丧尸=红、地狱犬=橙。
  - 血条下方名字（`ZOMBIE` / `HELLHOUND`），白字带黑阴影。
- **伤害数字**
  - 从命中点弹出，**竖直向上**飘并淡出。
  - 颜色从**红渐变到白**。
  - 起始高度、上飘速度随**玩家-丧尸距离**自适应：贴脸起点低、飘得慢（近战也能看清），
    远距离起点高、正常速度。
  - 数字池 16 个，快速连击能各自叠一个。
  - **致命一击也弹**（每个数字锚定在 GSC 于命中点生成的**静态锚点**上，不跟着丧尸跑、
    也不掉回地图原点）。

---

## 文件构成

```text
scripts/
  zh_healthbars.gsc                  # 服务端 GSC（自带 init() 入口，完全自包含）

ui_mp/
  t6/hud.lua                         # LUI 覆写：装载血条组件
  t6/zombie/zombiehealthbars.lua     # LUI 组件本体（血条 + 伤害数字）
```

各自放入对应注入目录：

| 文件 | 放入 |
|------|------|
| `scripts\zh_healthbars.gsc` | `%localappdata%\Plutonium\storage\t6\scripts` |
| `ui_mp\t6\hud.lua`、`ui_mp\t6\zombie\zombiehealthbars.lua` | `%localappdata%\Plutonium\storage\t6\ui_mp` |

> GSC 与 LUI 是两套独立注入，**两个都必须放到位**才生效。

---

## 工作原理（数据流）

GSC 每约 0.1s 遍历所有丧尸/地狱犬，把数据打包进多个**客户端 dvar**（分批，避免单个
dvar 过长被截断）：

```text
zh_data_0 .. zh_data_N    "entityNum:ratio100:alpha100:name;..."
```

LUI 每约 0.1s 轮询这些 dvar，按实体号 key 出每只的血条，用 `setupEntityContainer` 跟随实体。

伤害数字走独立事件通道：

```text
zh_dmg    "entityNum:amount:seq:distance;..."
```

LUI 读取后，每个命中占用数字池一个槽位，锚定到 GSC 在命中点生成的静态锚点，竖直上飘。

**为何不用 `luinotifyevent` / client field / server dvar？** 本作这些通道不可用或预算耗尽；
**客户端 dvar + `UIExpression.DvarString`** 是实测唯一能到达 LUI 的可靠通道。

---

## 可调参数

### LUI —— `ui_mp\t6\zombie\zombiehealthbars.lua` 顶部

| 常量 | 含义 | 默认 |
|------|------|------|
| `BARW` / `BARH` | 血条宽 / 高 | `60` / `6` |
| `HEADZ` | 血条相对头顶的偏移 | `70` |
| `ICONW` / `ICONGAP` | 左侧图标尺寸 / 与血条间距 | `12` / `6` |
| `MaxDmg` | 伤害数字池大小 | `16` |
| `DMGSTEPS` | 上飘帧数（约 0.85s；越大越慢） | `17` |
| `DMGRISE` | 总上升像素 | `30` |
| `DMGTOP` | 远距离起点相对血条的偏移 | `6` |
| `DMGBODY` | 贴脸起点高度（丧尸身体） | `30` |
| `DMGDISTREF` | 达到"远距离起点"所需距离 | `200` |
| `DMGSLOW` | 近距离额外滞空帧数（越近越慢） | `18` |
| `NUMDVARS` | 分批 dvar 数量 | `8` |

### GSC —— `scripts\zh_healthbars.gsc`

| 设置 | 值 |
|------|-----|
| 显示距离 | 近距阈值 `260`；满亮 `100`；准星显示上限 `900` |
| 准星判定 | `dot > 0.99` |
| 死亡衰减窗口 | `600` ms |
| 分批大小 | `zh_batch = 10`（每批丧尸数）；`zh_dvars = 8`（dvar 数） |

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

> 每个文件的完整路径见上方"文件构成"一节。

---

## 已知限制

- 伤害数字锚点是**共享的静态实体池**：若同时有超过 `MaxDmg` 个数字在飘，最旧的数字可能
  被新命中"借用"同一锚点而跳位（单人/LAN 基本无感）。
- 多人游戏中每个玩家的伤害数字发到各自 client dvar，彼此独立。
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
