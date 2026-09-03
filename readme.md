================================================================================
  BO2 — BOCW style health bars (Alpha)
  Call of Duty: Black Ops 2 (Plutonium T6) Zombie mode
================================================================================

Author: ab212ab

================================================================================

References: mainly BO2's unpacked/decompiled sources and decompiled Lua files,
plus some borrowings from BO3's Lua. This was built quickly via "vibe coding"
(this document is largely AI-written too). If there's a better way to do any of
it, improvements are welcome.

--------------------------------------------------------------------------------
1. How it works (data flow)
--------------------------------------------------------------------------------
  GSC iterates every zombie/hellhound every 0.1s and packs the data into several
  "client dvars" (batched so a single dvar doesn't get too long and get truncated):
      zh_data_0 .. zh_data_N   "entNum:ratio100:alpha100:name;..."
  LUI polls these dvars every 0.1s, keys each health bar by entity number, and
  follows the entity with setupEntityContainer.

  Damage numbers use a separate event channel:
      zh_dmg                    "entNum:amount:seq:distance;..."
  LUI reads it; each hit takes a slot in the damage-number pool, gets anchored to a
  static anchor GSC spawns at the hit point, and floats straight up.

  Why not luinotifyevent / client field / server dvar: those channels are
  unavailable or exhausted in this game; the client dvar + UIExpression.DvarString
  is the only channel actually proven to reach the LUI.

  PS: if you know a better way, please feel free to improve it.

--------------------------------------------------------------------------------
2. Tunables
--------------------------------------------------------------------------------
  [A] LUI — constants at the top of ui_mp\t6\zombie\zombiehealthbars.lua:
      BARW / BARH         bar width / height (60 / 6)
      HEADZ               bar offset above the head (70)
      ICONW / ICONGAP     left icon size / gap to the bar (12 / 6)
      MaxDmg              damage-number pool size (16)
      DMGSTEPS            float-up frames (17, ~0.85s; bigger = slower)
      DMGRISE             total rise in pixels (30)
      DMGTOP              long-range start offset above the bar (6)
      DMGBODY             close-range (point-blank) start height - zombie body (30)
      DMGDISTREF          distance at which it reaches the long-range start (200)
      DMGSLOW             extra linger frames at close range (slower the closer) (18)
      NUMDVARS            number of batched dvars (8)

  [B] GSC — scripts\zh_healthbars.gsc:
      Show distance       near-show threshold 260; full-bright 100; aim-show cap 900
      Aim check           dot > 0.99
      Death drain window  600ms
      Batch size          zh_batch = 10 (zombies per dvar); zh_dvars = 8 (dvar count)


--------------------------------------------------------------------------------
3. Installation
--------------------------------------------------------------------------------
  Two install methods:

  Method 1: install onto an existing mod.
    %localappdata%\Plutonium\storage\t6\mods\<The mod folder you want>

  Method 2: install directly under
    %localappdata%\Plutonium\storage\t6
================================================================================
