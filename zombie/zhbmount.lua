-- ============================================================================
--  ZombieHealthBars MOUNT SHIM  (ui_mp/t6/zombie/zhbmount.lua)
--
--  WHY THIS EXISTS
--  LUI has exactly ONE entry file: ui_mp/t6/hud.lua. If two mods both ship that
--  file, Plutonium keeps only one (mod priority overwrites the other, whole file,
--  silently) and the loser stops working entirely. Stock hud.lua also defines all
--  its helpers as GLOBAL functions, so if both files get executed, whichever
--  defines HUD_FirstSnapshot_Zombie LAST overwrites the other one's version.
--
--  This shim avoids both problems: it does NOT redefine anything wholesale, it
--  WRAPS the already-defined function and chains to the previous implementation,
--  so the other mod keeps running unchanged.
--
--  INSTALL (one line, in the OTHER mod's hud.lua, at the very END of the file):
--      require("T6.Zombie.ZHBMount")
--  ...and DO NOT install this mod's ui_mp/t6/hud.lua at all.
--
--  NOTES
--  - Placed after DisableGlobals() it is still fine: it only ASSIGNS an existing
--    global (HUD_FirstSnapshot_Zombie) and adds fields to CoD.* / the widget, it
--    creates no brand-new global name.
--  - Wrapped in pcall so a failure here can never break the host mod's HUD.
--  - The widget itself needs no change; it is the same zombiehealthbars.lua.
-- ============================================================================

if CoD.ZombieHealthBarsMount then
	return
end
CoD.ZombieHealthBarsMount = true

-- Attach our widget to the HUD root. Safe to call on every first_snapshot.
local function zhBarsAttach(HUDWidget)
	if not CoD.isZombie or not HUDWidget then
		return
	end
	-- HUD_FirstSnapshot does removeAllChildren(), which already tore our widget
	-- down; drop the stale handle before rebuilding so we never stack duplicates.
	if HUDWidget.zhBarsWidget then
		pcall(function() HUDWidget.zhBarsWidget:close() end)
		HUDWidget.zhBarsWidget = nil
	end
	pcall(function()
		require("T6.Zombie.ZombieHealthBars")
		if LUI.createMenu.ZombieHealthBars then
			HUDWidget.zhBarsWidget = LUI.createMenu.ZombieHealthBars(HUDWidget.controller)
			HUDWidget:addElement(HUDWidget.zhBarsWidget)
		end
	end)
end

local installed = false

-- Preferred hook point: the zombie-only branch, already present in stock hud.lua.
if type(HUD_FirstSnapshot_Zombie) == "function" then
	local prev = HUD_FirstSnapshot_Zombie
	HUD_FirstSnapshot_Zombie = function(HUDWidget, ClientInstance)
		prev(HUDWidget, ClientInstance)          -- host mod runs first, untouched
		zhBarsAttach(HUDWidget)
	end
	installed = true
end

-- Fallback for hosts that replaced hud.lua so thoroughly that the zombie helper
-- no longer exists: wrap the shared entry point instead.
if not installed and type(HUD_FirstSnapshot) == "function" then
	local prev = HUD_FirstSnapshot
	HUD_FirstSnapshot = function(HUDWidget, ClientInstance)
		prev(HUDWidget, ClientInstance)
		zhBarsAttach(HUDWidget)
	end
	installed = true
end

-- If neither exists yet (require ran too early), retry once on the next frame via
-- the per-frame dispatcher rather than failing silently.
if not installed then
	local LUI_update = LUI.GlobalCallbacks.Main
	if LUI_update then
		LUI.GlobalCallbacks.Main = function(dt)
			if type(HUD_FirstSnapshot_Zombie) == "function" then
				LUI.GlobalCallbacks.Main = LUI_update
				local prev = HUD_FirstSnapshot_Zombie
				HUD_FirstSnapshot_Zombie = function(HUDWidget, ClientInstance)
					prev(HUDWidget, ClientInstance)
					zhBarsAttach(HUDWidget)
				end
			end
			return LUI_update(dt)
		end
	end
end
