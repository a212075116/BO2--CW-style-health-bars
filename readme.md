# BOCW Style Zombie Health Bars — Black Ops 2 (Alpha)

> **Call of Duty: Black Ops 2 (Plutonium T6) — Zombies**

A small zombies mod that gives every zombie a **COD17 / Black Ops Cold War-style floating
health bar** above its head, plus **floating damage numbers** on hit.

**Author:** ab212ab

---

## Overview

- Near-range only by default — the bar fades in as a zombie gets close, and fades out
  past a threshold (it stays hidden but "in place" so it doesn't flicker).
- Sneak a peek at a specific zombie by **aiming at it** — landing the crosshair on a
  zombie reveals its bar even at long range (but only with clear line of sight).
- **Hellhounds are supported too** — they get their own bar, an orange icon, and the
  name `HELLHOUND`.

---

## Features

- **Health bar**
  - Red fill with a black frame, floating above/behind the head.
  - White **"ghost"** after-image that lags behind the red on damage, giving a smooth
    drain transition.
  - On death the bar drains to zero over ~0.6 s, then disappears.
- **Show rules**
  - Proximity fade: closer = brighter (full-bright ≤ 100, gone past ~260).
  - **Crosshair reveal**: `dot > 0.99` against the zombie's chest (very strict).
  - **Line-of-sight check**: cover / walls block the reveal (`bullettracepassed`).
- **Icon + name**
  - A square icon left of the bar: **red** for zombies, **orange** for hellhounds.
  - A name under the bar (`ZOMBIE` / `HELLHOUND`) in white with a black shadow.
- **Damage numbers**
  - Pop from the hit point, float **straight up**, and fade out.
  - Colour fades **red → white** over the pop.
  - Start height and rise speed adapt to player→zombie **distance**: point-blank hits
    start low and rise slowly (so melee is readable), long-range hits start higher and
    rise at normal speed.
  - A pool of 16 lets several numbers stack during fast fire.
  - The killing blow works too (each number is pinned to a **static anchor** GSC spawns
    at the hit point, so it doesn't ride the zombie or fall back to the map origin).

---

## File structure

```text
scripts/
  zh_healthbars.gsc                  # server-side GSC (own init() entry, self-contained)

ui_mp/
  t6/hud.lua                         # LUI override that mounts the widget
  t6/zombie/zombiehealthbars.lua     # LUI widget (bars + damage numbers) itself
```

Drop each half into its injection folder:

| File | Goes to |
|------|---------|
| `scripts\zh_healthbars.gsc` | `%localappdata%\Plutonium\storage\t6\scripts` |
| `ui_mp\t6\hud.lua`, `ui_mp\t6\zombie\zombiehealthbars.lua` | `%localappdata%\Plutonium\storage\t6\ui_mp` |

> The GSC and the LUI are two separate injectables; **both** must be in place to work.

---

## How it works (data flow)

GSC walks every zombie / hellhound every ~0.1 s and packs the data into several
**client dvars** (batched so a single dvar doesn't grow too long and get truncated):

```text
zh_data_0 .. zh_data_N    "entityNum:ratio100:alpha100:name;..."
```

LUI polls those dvars every ~0.1 s, keys each bar by entity number, and follows the
entity via `setupEntityContainer`.

Damage numbers travel on a separate event channel:

```text
zh_dmg    "entityNum:amount:seq:distance;..."
```

LUI reads it; each hit takes a slot from the damage-number pool, anchors to a static
anchor GSC spawns at the hit point, and floats up.

**Why not `luinotifyevent` / client field / server dvar?** Those channels are either
unavailable or their budgets are exhausted in this title. The **client dvar +
`UIExpression.DvarString`** channel is the only one actually proven to reach the LUI.

---

## Tunables

### LUI — `ui_mp\t6\zombie\zombiehealthbars.lua` (top of file)

| Constant | Meaning | Default |
|----------|---------|---------|
| `BARW` / `BARH` | Bar width / height | `60` / `6` |
| `HEADZ` | Bar offset above the head | `70` |
| `ICONW` / `ICONGAP` | Left icon size / gap to bar | `12` / `6` |
| `MaxDmg` | Damage-number pool size | `16` |
| `DMGSTEPS` | Float-up frames (~0.85 s; bigger = slower) | `17` |
| `DMGRISE` | Total rise in px | `30` |
| `DMGTOP` | Long-range start offset above the bar | `6` |
| `DMGBODY` | Point-blank start height (zombie body) | `30` |
| `DMGDISTREF` | Distance at which it reaches the long-range start | `200` |
| `DMGSLOW` | Extra linger frames at close range (slower when close) | `18` |
| `NUMDVARS` | Number of batched dvars | `8` |

### GSC — `scripts\zh_healthbars.gsc`

| Setting | Value |
|---------|-------|
| Show distance | near threshold `260`, full-bright `100`, aim-show cap `900` |
| Aim check | `dot > 0.99` |
| Death drain window | `600` ms |
| Batch size | `zh_batch = 10` (zombies/dvar), `zh_dvars = 8` (dvars) |

---

## Installation

Two ways to install:

**Method 1 — install onto an existing mod**

```text
%localappdata%\Plutonium\storage\t6\mods\<the mod folder you want>
```

**Method 2 — install directly under the storage folder**

```text
%localappdata%\Plutonium\storage\t6
```

> Full per-file paths are listed in the *File structure* section above.

---

## Known limitations

- The damage-number anchors are a **shared static-entity pool**: if more than `MaxDmg`
  numbers are floating at once, the oldest may be "borrowed" by a newer hit and jump.
  Barely noticeable solo / on LAN.
- In multiplayer each player's damage numbers go to their own client dvar, so they're
  independent per player.
- The bars are a **client injection (ui_mp)**; if `ui_mp` is cleared or fails to load,
  the health bars are missing.

---

## Credits / References

Special thanks to the following projects and people — this work builds heavily on them:

- **JariKCoding** — [CoDLUIDecompiler](https://github.com/JariKCoding/CoDLUIDecompiler) & [CoDLuaDecompiler](https://github.com/JariKCoding/CoDLuaDecompiler)
- **plutoniummod** — [t6-scripts](https://github.com/plutoniummod/t6-scripts)
- **Treyarch / Activision** — `bo3_scriptapifunctions`
- **KingslayerKyle** — [T7LuaRepo](https://github.com/KingslayerKyle/T7LuaRepo)

---

*Built quickly via "vibe coding" — including parts of this document. If you know a
better way to do any of it, improvements are welcome.*
