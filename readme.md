# BOCW Style Zombie Health Bars — Black Ops 2 (Alpha)

**English | [简体中文](readme_CN.md)**

> **Call of Duty: Black Ops 2 (Plutonium T6) — Zombies**
> Repo: <https://github.com/a212075116/BO2--CW-style-health-bars>

A small zombies mod that gives every zombie a **COD17 / Black Ops Cold War-style floating
health bar** above its head, plus **floating damage numbers** on hit.

---

## Overview
- This is a mod that is severely lacking in testing. I have only tested it in solo mode, and have not conducted any proper multiplayer testing, nor have I tested it to the extent of playing through to the later stages. In other words, this mod is likely quite unstable.

- **The bar rides the head bone.** Each zombie gets an invisible anchor entity `linkto()`-ed
  to its eye/head bone, so the bar tracks the actual head — including when the zombie leans,
  lunges or crouches — instead of "feet origin plus a guessed height".
- **Perspective-correct at any range.** Both the bar's *size* and its *clearance above the
  head* scale with player→zombie distance, so a far-away zombie gets a proportionally smaller
  bar instead of one that dwarfs and covers it.
- **Clearance is screen-space on purpose.** Lifting the bar along the *world* vertical axis
  collapses onto the zombie when you look DOWN at it from high ground (the lift projects to
  `cos(pitch)`); a screen-space lift is immune to camera pitch.
- **Near-range by default** — the bar fades in as a zombie gets close and fades out past a
  threshold (it stays hidden but "in place" so it doesn't flicker).
- **Sneak a peek at a specific zombie by aiming at it** — landing the crosshair on a zombie
  reveals its bar at *any* range (still requires clear line of sight).
- **Special zombie kinds get their own name and icon colour** — hellhounds, the theater
  crawlers, the Origins mech zombie, the prison warden, the temple fire zombie, and more
  (full table below).
- **Installs alongside other Lua mods** — `ui_mp/t6/hud.lua` ships as the *unmodified official
  file plus a single `require` line*, so it can be replaced by another mod's entry without
  losing anything (see *Coexistence*).

---

## Features

- **Health bar**
  - Red fill with a black frame, anchored to the zombie's head bone.
  - White **"ghost"** after-image that lags behind the red on damage, giving a smooth
    drain transition.
  - On death the bar drains to zero over ~0.6 s, then disappears.
- **Show rules**
  - Proximity fade: full-bright at `d <= 150`, linear fade to nothing at `d > 300`
    (units are inches — 150 ≈ 3.8 m, 300 ≈ 7.6 m).
  - **Crosshair reveal**: `dot > 0.99` against the zombie's chest (very strict),
    with **no distance limit**.
  - **Line-of-sight check**: cover / walls block the reveal (`bullettracepassed`).
- **Icon + name**, keyed off the entity's `animname` (the field BO2 itself uses to tell
  zombie kinds apart):

  | Zombie | Label | Icon colour |
  |--------|-------|-------------|
  | Plain zombie | `ZOMBIE` | red |
  | Hellhound | `HELLHOUND` | orange |
  | Theater crawler ("quad") | `CRAWLER` | violet |
  | Origins mech zombie | `MECH` | cyan |
  | Prison warden (Brutus) | `WARDEN` | salmon |
  | Temple fire zombie | `FLAME` | hot orange |
  | Shrieker | `SHRIEKER` | green |
  | Leaper | `LEAPER` | yellow |
  | Ghost | `GHOST` | pale white-blue |
  | Astro zombie | `ASTRO` | blue |
  | Monkey bomb | `MONKEY` | brown |
  | Giant robot walker | `ROBOT` | steel |

  A name appears under the bar in white with a black shadow. Unmapped kinds keep `ZOMBIE`.
- **Damage numbers**
  - Pop from the **hit point**, float **straight up**, and fade out.
  - Colour fades **red → white** over the pop.
  - Rise speed adapts to distance: point-blank hits linger longer (so melee stays readable),
    long-range hits float at normal speed.
  - A pool of 16 lets several numbers stack during fast fire.
  - **The killing blow works too.** Vanilla `_zm_spawner::enemy_death_detection()` bails out
    with `if ( !isalive(self) ) return;` *before* the damage callbacks fire, so a one-shot
    kill reaches no damage hook at all. This mod catches it on the engine's actor-KILLED
    path instead, where the damage value is already post-multiplier — i.e. the number shown
    matches the health actually lost.
  - The killing number reuses the **last non-lethal hit position** when one exists, so it
    appears where you hit rather than at the corpse.

---

## Console variables

| Command | Effect |
|---------|--------|
| `setdvar zh_animname 1` | **Label probe (diagnostic).** Any zombie whose kind is *not* in the table above prints its raw `animname` as its label, so an unknown monster reveals its own real name on screen. Add a row in the GSC dispatcher and a colour row in `ICON_TINT`, then set it back to `0`. |
| `setdvar zh_animname 0` | Off — the default. Already-labelled kinds are never affected, so the probe can stay on while you hunt for new ones. |

The dvar is read per pass, not snapshotted at load: switching it takes effect immediately,
without a restart. (Code changes *do* need one — GSC is not hot-reloaded.)

---

## File structure

```text
scripts/
  zh_healthbars.gsc                  # server-side GSC (own init() entry, self-contained)

ui_mp/
  t6/hud.lua                         # the OFFICIAL hud.lua + ONE trailing require line
  t6/zombie/zombiehealthbars.lua     # the LUI widget (bars + damage numbers)
  t6/zombie/zhbmount.lua             # mount shim: wraps the host's HUD entry
```

`hud.lua` is deliberately **not** a rewritten file any more — diff it against the stock game
version and the only difference is the last few lines:

```lua
require("T6.Zombie.ZHBMount")     -- the only thing this mod puts in hud.lua

DisableGlobals()
Engine.StopEditingPresetClass()
```

That single line is the whole integration surface. It sits **before** `DisableGlobals()`
on purpose, because mounting still needs to assign globals.

---

## Coexistence with another Lua mod

LUI has exactly **one** entry file: `ui_mp/t6/hud.lua`. If two mods both ship it, Plutonium
keeps only one (mod priority, whole-file overwrite, no warning) and the loser stops working
entirely. Worse, stock `hud.lua` defines its helpers as **global functions**, so if both
files somehow ran, whichever defined `HUD_FirstSnapshot_Zombie` last would silently
overwrite the other's version.

So the rule is: **one entry file, everything else via `require`.** This mod contributes a
single `require` line and does the rest in its own files; `zhbmount.lua` **wraps** the host's
function instead of redefining it:

```lua
local prev = HUD_FirstSnapshot_Zombie
HUD_FirstSnapshot_Zombie = function(HUDWidget, ClientInstance)
    prev(HUDWidget, ClientInstance)   -- the host mod runs first, untouched
    zhBarsAttach(HUDWidget)           -- then our widget is mounted
end
```

### Pick whichever applies

**A — no other Lua mod touches `hud.lua`** (the common case): install all three files as
listed above. Done.

**B — another mod owns `hud.lua`:** do **not** install this mod's `hud.lua`. Instead add the
same one line to the **very end** of *that* mod's `hud.lua`, just before `DisableGlobals()`:

```lua
require("T6.Zombie.ZHBMount")
```

Then install only the two `t6/zombie/*.lua` files. Both mods keep working, and updating
the other mod never reverts our mount.

### Where the two mods could still collide

| Shared resource | What this mod uses | Risk |
|---|---|---|
| `ui_mp/t6/hud.lua` | official file + 1 line | the only hard conflict — avoided by path B above |
| Global functions | wrapped, never redefined | low |
| Global namespace | `CoD.ZombieHealthBars`, `CoD.ZombieHealthBarsMount` | own names, safe |
| `LUI.createMenu` key | `ZombieHealthBars` | own name, safe |
| Event names | `zombie_bars` | custom name, safe |
| Client dvars | `zh_data_0..7`, `zh_dmg` | own prefix, safe |
| GSC callbacks | never grabs a `level.*` singleton | verified against weapon-damage mods |

The one thing left to check by eye is **HUD layering**: our widget is `addElement`-ed to the
HUD root, and draw order follows insertion order. If the other mod also paints a large
full-screen element, one may cover the other — swapping the `require` order fixes that and
loses no functionality.

---

## How it works (data flow)

GSC walks every zombie / hellhound / crawler every ~0.1 s and packs the data into several
**client dvars** (batched so a single dvar doesn't grow too long and get truncated):

```text
zh_data_0 .. zh_data_N    "entityNum:ratio100:alpha100:name:distance;..."
```

- `entityNum` is the **head-anchor entity's** number when an anchor exists (the anchor is
  `linkto()`-ed to the zombie's eye/head bone), otherwise the zombie itself.
- `distance` is the server-computed player→zombie range, which is what lets the LUI scale the
  bar's size and head clearance per zombie.

LUI polls those dvars every ~0.1 s, keys each bar by entity number, and follows the entity
via `setupEntityContainer`.

Damage numbers travel on a separate event channel:

```text
zh_dmg    "entityNum:amount:seq:distance;..."
```

LUI reads it; each hit takes a slot from the damage-number pool, anchors to a static anchor
GSC spawns at the hit point, and floats up. `seq` is a per-player counter used to dedupe,
so the same hit is never drawn twice across polls.

**Why not `luinotifyevent` / client field / server dvar?** Those channels are either
unavailable or their budgets are exhausted in this title. The **client dvar +
`UIExpression.DvarString`** channel is the only one actually proven to reach the LUI.

**Why a per-entity kill hook instead of a global one?** The mod deliberately grabs **no**
`level.*` callback singleton (`level.callbackActorDamage`, `level.callbackactorkilled`).
It registers into the *array*-based damage callback list, where many registrants coexist, and
assigns only its own per-entity `actor_killed_override` slot. That keeps it fully independent
of any other mod's damage overrides — installing it on top of a weapon-damage mod is safe,
and the numbers reflect the damage those mods actually dealt.

---

## Tunables

### LUI — `ui_mp\t6\zombie\zombiehealthbars.lua` (top of file)

| Constant | Meaning | Default |
|----------|---------|---------|
| `BARW` / `BARH` | Bar width / height at reference distance | `60` / `6` |
| `HEADZ_TABLE` | Distance → clearance above the head, in px. Rows are `{ distance, pixels }`; values **between** rows are linearly interpolated, so the bar lifts smoothly with range. Edit freely, keep distances ascending. | `50→13, 100→16, 150→18, 250→21, 500→23` |
| `HEADZSCALE` | Global multiplier on that curve (shift the whole thing up/down) | `1.0` |
| `BARDISTREF` | Distance at which the bar equals its design size; scale is `k = BARDISTREF / dist` | `300` |
| `BARSCALEMAX` | Ceiling on the **zoom-in** side only. Shrinking with distance is never capped, so far-away scaling stays perspective-true. At `1.2` the bar stops growing closer than `BARDISTREF / BARSCALEMAX` (= 250). | `1.2` |
| `ICONW` / `ICONGAP` | Left icon size / gap to bar | `12` / `6` |
| `ICON_TINT` | Label → icon RGB. New zombie kind = one row here (+ one `else if` in the GSC). Unknown labels fall back to `ZOMBIE`'s colour. | see table above |
| `MaxDmg` | Damage-number pool size | `16` |
| `DMGSTEPS` | Float-up frames (~0.85 s; bigger = slower) | `17` |
| `DMGRISE` | Total rise in px | `30` |
| `DMGSLOW` | Extra linger frames at close range (slower when close) | `18` |
| `DMGDISTREF` | Distance reference used for the *rise-speed* adaptation | `200` |
| `NUMDVARS` | Number of batched dvars | `8` |

> `DMGTOP` and `DMGBODY` are still declared but **no longer used** — the old distance-based
> *start-height* interpolation was replaced by spawning the number directly at the hit point.

### GSC — `scripts\zh_healthbars.gsc`

| Setting | Value |
|---------|-------|
| Show distance | full-bright `150`, gone past `300` |
| Aim reveal | `dot > 0.99`, **no distance cap** |
| Death drain window | `600` ms |
| Batch size | `zh_batch = 10` (zombies/dvar), `zh_dvars = 8` (dvars) |
| Head bone probe | `tag_eye`, `j_head`, `J_EyeBall_LE`, `tag_head` (first one that resolves) |
| Watch poll | `0.05` s |

---

## Installation

**Step 1 — pick a location.** Either way works:

```text
%localappdata%\Plutonium\storage\t6\mods\<the mod folder you want>
```
```text
%localappdata%\Plutonium\storage\t6
```

**Step 2 — install the files** (full per-file paths in *File structure* above):

| File | Goes to |
|------|---------|
| `scripts\zh_healthbars.gsc` | `<location>\scripts` |
| `ui_mp\t6\zombie\zombiehealthbars.lua` | `<location>\ui_mp\t6\zombie` |
| `ui_mp\t6\zombie\zhbmount.lua` | `<location>\ui_mp\t6\zombie` |
| `ui_mp\t6\hud.lua` | `<location>\ui_mp\t6` — **only if no other mod owns that file**, see *Coexistence* |

> The GSC and the LUI are two separate injectables; **both** must be in place to work.
> A loose `.gsc` in a mod folder overrides the packed `mod.ff`, so you can edit and restart
> without repacking.

---

## Known limitations

- **Heavily under-tested**, solo only. See *Overview*.
- The bar follows a **bone anchor**, which needs a head bone to resolve. A model with none of
  the probed tags falls back to the zombie's own origin, so its bar sits lower — the fire
  zombie and other custom models are the likeliest candidates.
- Distance-driven sizing means **far-away bars are genuinely small**. That is the point
  (they no longer cover the zombie), but it also makes them hard to read at extreme range.
- Damage-number anchors are a **shared static-entity pool**: if more than `MaxDmg` numbers are
  floating at once, the oldest may be "borrowed" by a newer hit and jump. Barely noticeable
  solo / on LAN.
- The **killing blow has no hit coordinate** in the engine's kill callback (`shitloc` there is a
  hit-*location name* like `"helmet"`, not a position). The number therefore reuses the last
  non-lethal hit's position when there was one; a pure one-shot kill from full health falls
  back to the body hit position and then to the zombie's position, so it can be approximate.
- If a **third** mod also wraps `HUD_FirstSnapshot_Zombie`, wrapping order decides who runs
  last. Ours only adds a widget, so it composes in either order, but keep it in mind when
  stacking several HUD mods.
- In multiplayer each player's damage numbers go to their own client dvar, so they're
  independent per player. Bar *visibility*, however, is still computed per player but shares
  the same zombie set — not stress-tested with 4+ players.
- The bars are a **client injection (ui_mp)**; if `ui_mp` is cleared or fails to load, the
  health bars are missing.

---

## Credits / References
- **JariKCoding** — [CoDLUIDecompiler](https://github.com/JariKCoding/CoDLUIDecompiler) & [CoDLuaDecompiler](https://github.com/JariKCoding/CoDLuaDecompiler)
- **plutoniummod** — [t6-scripts](https://github.com/plutoniummod/t6-scripts)
- **Treyarch / Activision** — `bo3_scriptapifunctions`
- **KingslayerKyle** — [T7LuaRepo](https://github.com/KingslayerKyle/T7LuaRepo)
- **Laupetin** - [OpenAssetTools](https://github.com/Laupetin/OpenAssetTools)

---

*Built quickly via "vibe coding" — including parts of this document. If you know a
better way to do any of it, improvements are welcome.*
