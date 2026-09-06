-- ============================================================================
--  ZombieHealthBars (LUI / t6)  --  COD17-style health bars above zombie heads
--
--  DATA FLOW (server -> client)
--    * GSC packs per-zombie data into dvar "zh_data" as:
--          "entityNum:ratio100:alpha100:name;..."  (semicolon per zombie, every ~0.1s)
--    * GSC pushes damage-number events into dvar "zh_dmg" as:
--          "entityNum:amount:seq:distance;..."  (retained ~0.3s; deduped by seq)
--    * This element polls both dvars every 100ms (LUI.UITimer), parses them, and
--      follows each zombie's HEAD-BONE anchor entity via setupEntityContainer(entNum)
--      (the server linkto()s an invisible script_model to tag_eye / j_head).
--    (dvar + UIExpression.DvarString is used because both luinotifyevent custom
--     names and the client-field budget are unavailable/exhausted in this game.)
-- ============================================================================

CoD.ZombieHealthBars = {}

CoD.ZombieHealthBars.Enabled   = true
CoD.ZombieHealthBars.BARW      = 60
CoD.ZombieHealthBars.BARH      = 6
-- Head clearance is now a DISTANCE CURVE you can tune freely. Each row is
-- { distance in units, clearance in pixels }; values BETWEEN rows are linearly
-- interpolated, so the bar lifts smoothly with range instead of stepping at the
-- boundaries. Still SCREEN space (not world-vertical), so camera pitch can no
-- longer collapse the lift onto the zombie's head.
CoD.ZombieHealthBars.HEADZ_TABLE = {
	{ 50,   13 },
	{ 100,  16 },
	{ 150,  18 },
	{ 250,  21 },
	{ 500,  23 },
}
CoD.ZombieHealthBars.HEADZSCALE  = 1.0   -- global multiplier: shift the WHOLE curve up/down
CoD.ZombieHealthBars.MAXALPHA  = 0.85
CoD.ZombieHealthBars.ICONW     = 12      -- square icon (red fill + black frame)
CoD.ZombieHealthBars.ICONGAP   = 6       -- gap between the icon and the bar
-- Icon colour per actor label. The label itself is decided GSC-side from the
-- entity's animname, so supporting a new zombie kind = one else-if there plus
-- one row here. Values are RGB floats; ZOMBIE is the fallback for unknown keys.
CoD.ZombieHealthBars.ICON_TINT = {
	ZOMBIE    = { 1.00, 0.00, 0.00 },   -- red    (plain)
	HELLHOUND = { 1.00, 0.55, 0.00 },   -- orange
	CRAWLER   = { 0.70, 0.25, 1.00 },   -- violet (theater quad)
	MECH      = { 0.35, 0.85, 0.95 },   -- cyan   (Origins mech zombie)
	SHRIEKER  = { 0.55, 1.00, 0.35 },   -- green
	LEAPER    = { 1.00, 0.85, 0.20 },   -- yellow
	GHOST     = { 0.80, 0.80, 1.00 },   -- pale white-blue
	WARDEN    = { 1.00, 0.35, 0.35 },   -- salmon (MoD jailer / Brutus)
	ASTRO     = { 0.30, 0.60, 1.00 },   -- blue
	MONKEY    = { 0.80, 0.55, 0.25 },   -- brown
	ROBOT     = { 0.75, 0.75, 0.80 },   -- steel
	FLAME     = { 1.00, 0.45, 0.10 },   -- hot orange (temple napalm / fire zombie)
}
CoD.ZombieHealthBars.MaxDmg    = 16      -- damage-number pool size (concurrent popups)
CoD.ZombieHealthBars.DMGSTEPS  = 17      -- float frames (50ms each -> ~0.85s)
CoD.ZombieHealthBars.DMGRISE   = 30      -- total px the number rises
CoD.ZombieHealthBars.DMGTOP    = 6       -- px above the bar at LONG range
CoD.ZombieHealthBars.DMGBODY   = 30      -- start height at CLOSE range (zombie's body)
CoD.ZombieHealthBars.DMGDISTREF = 200    -- distance at which it reaches the above-head start
CoD.ZombieHealthBars.BARDISTREF = 300    -- distance at which the bar == its design size.
                                         -- k = BARDISTREF / dist, perspective-true shrink.
CoD.ZombieHealthBars.BARSCALEMAX = 1.2   -- ZOOM-IN cap ONLY: closer than BARDISTREF/BARSCALEMAX
                                         -- (=250 units) the bar stops growing. Shrinking far
                                         -- away stays UNcapped, so distance scaling is intact.
CoD.ZombieHealthBars.DMGSLOW   = 18      -- extra frames at CLOSE range (slower rise)
CoD.ZombieHealthBars.NUMDVARS  = 8       -- number of zh_data_# dvars (batched payload)
-- Kill notices (BOCW style): "+N Zombie Elimination" / "+N Zombie Critical Kill"
-- Two-phase motion: HOLD perfectly still, then leave with a short fade + rightward
-- slide. Nothing ever moves vertically, so a column of notices stays exactly in place.
CoD.ZombieHealthBars.MaxKill   = 5       -- concurrent notices on screen
CoD.ZombieHealthBars.KillHold  = 60      -- 50ms frames of STILL display -> 60 * 0.05 = 3.0s
CoD.ZombieHealthBars.KillFade  = 16      -- frames of fade-out AFTER the hold (~0.8s)
-- Position maths: LUI units are NOT screen pixels. At 16:9 the logical space is
-- 1280x720 (spectate.lua:16  CoD.SpectateHUD.ScreenWidth = 1280), so
--     1 unit = displayWidth / 1280   ->  1.3867 px on a 1775px-wide capture
-- Reference BOCW capture (1775x998): notice sits 190px right / 25px up from centre
--     190 / 1.3867 = 137 units      25 / 1.3861 = 18 units
CoD.ZombieHealthBars.KillX     = 137     -- units right of screen centre (the crosshair)
CoD.ZombieHealthBars.KillY     = -18     -- units above centre, negative = up; never changes
CoD.ZombieHealthBars.KillSlide = 10      -- units it slides RIGHT during the fade (~14px), kept small
CoD.ZombieHealthBars.KillStack = 18      -- px between lanes (sized for the Condensed font)
-- Queue behaviour: a new notice takes the TOP row and pushes every older one down a
-- lane. These two control how that shift looks.
CoD.ZombieHealthBars.KillMoveMs  = 200   -- ms to travel one lane (the group shift-down)
CoD.ZombieHealthBars.KillEjectMs = 300   -- ms the pushed-past-last notice fades while descending
CoD.ZombieHealthBars.KillH     = 20      -- text box height for the Condensed font
-- Score "pop-in": the "+100" part scales DOWN from big to normal while the words
-- just appear (matches the source game; see zhKillScale below for the mechanics).
CoD.ZombieHealthBars.KillNumW  = 64      -- box width reserved for the score text
CoD.ZombieHealthBars.KillPop   = 1.9     -- starting scale (1.9x, shrinks to 1.0)
CoD.ZombieHealthBars.KillPopMs = 260     -- ms of the pop, on a 25ms clock (40fps)
CoD.ZombieHealthBars.KillTick  = 25      -- ms per fast-clock tick (only runs while visible)
                                         -- font ladder (codbase.lua:112-118):
                                         -- ExtraSmall < Default(small) < Condensed(normal)
                                         --            < Big < Morris(extraBig)

-- Linear lookup into HEADZ_TABLE: interpolates BETWEEN rows (smooth, no visible
-- steps) and clamps to the first/last row outside the table. Add or rename rows
-- freely, just keep the distances ASCENDING or the interpolation folds back.
function CoD.ZombieHealthBars.HEADZAt(dist)
	local T = CoD.ZombieHealthBars.HEADZ_TABLE
	local S = CoD.ZombieHealthBars.HEADZSCALE or 1
	local n = #T
	if n == 0 then return 0 end
	if dist <= T[1][1] then return T[1][2] * S end
	if dist >= T[n][1] then return T[n][2] * S end
	for i = 2, n do
		local d1, z1 = T[i - 1][1], T[i - 1][2]
		local d2, z2 = T[i][1], T[i][2]
		if dist <= d2 then
			if d2 <= d1 then return z2 * S end
			local t = (dist - d1) / (d2 - d1)
			return (z1 + (z2 - z1) * t) * S
		end
	end
	return T[n][2] * S
end

-- Lay out (or re-lay-out) a whole bar at scale k, ALWAYS symmetric about the
-- anchor. We deliberately do NOT use setScale(): scaling an element also scales
-- its offsets from the parent, so shrinking slid the bar down through the floor.
function CoD.ZombieHealthBars.SizeBar(bar, k, ratio, ghostRatio)
	local C = CoD.ZombieHealthBars
	if not k or k <= 0 then k = 1 end
	if not ratio then ratio = 0 end
	if not ghostRatio or ghostRatio < ratio then ghostRatio = ratio end

	local halfW = (C.BARW * k) / 2
	local h = C.BARH * k

	bar:setLeftRight(false, false, -halfW, halfW)
	bar:setTopBottom(false, true, -h, 0)

	if bar.bg then
		bar.bg:setTopBottom(true, true, -2 * k, 2 * k)
	end

	local w = C.BARW * k * ratio
	if w < 1 then w = 1 end
	bar.fill:setLeftRight(false, false, -halfW, (-halfW + w))

	if bar.ghost then
		local gw = C.BARW * k * ghostRatio
		if gw < 1 then gw = 1 end
		bar.ghost:setLeftRight(false, false, -halfW, (-halfW + gw))
	end

	-- icon square: its size AND its gap to the bar scale together, so it stays glued
	if bar.iconFrame then
		local icW = C.ICONW * k
		local icGap = C.ICONGAP * k
		bar.iconFrame:setLeftRight(false, false, (-halfW - icGap - icW), (-halfW - icGap))
		bar.iconFrame:setTopBottom(false, true, -9 * k, 3 * k)
	end
	if bar.icon then
		local icW = C.ICONW * k
		local icGap = C.ICONGAP * k
		bar.icon:setLeftRight(false, false, (-halfW - icGap - icW + 1), (-halfW - icGap - 1))
		bar.icon:setTopBottom(false, true, -8 * k, 2 * k)
	end

	-- label box hugs the bar; glyphs stay fixed-size (fonts can't be scaled here),
	-- so the text box keeps its full width and only its origin/left edge follows k.
	if bar.name then
		bar.name:setLeftRight(false, false, (-halfW + 1), 200)
		bar.name:setTopBottom(false, true, 1 * k, 15 * k)
	end
	if bar.nameShadow then
		bar.nameShadow:setLeftRight(false, false, -halfW, 200)
		bar.nameShadow:setTopBottom(false, true, 2 * k, 16 * k)
	end
end

-- Create one bar (dark backing + red fill) that can follow an entity.
function CoD.ZombieHealthBars.NewBar()
	local bar = LUI.UIElement.new()
	bar:setAlpha(0)
	bar:setLeftRight(false, false, (-CoD.ZombieHealthBars.BARW / 2), (CoD.ZombieHealthBars.BARW / 2))
	bar:setTopBottom(false, true, (-CoD.ZombieHealthBars.BARH), 0)

	local bg = LUI.UIImage.new()
	bg:setLeftRight(true, true, -2, 2)      -- slightly larger than the bar -> black frame
	bg:setTopBottom(true, true, -2, 2)
	bg:setImage(RegisterMaterial("white"))
	bg:setRGB(0, 0, 0)
	bg:setAlpha(0.8)
	bar:addElement(bg)
	bar.bg = bg

	-- ghost: a white chunk that lags behind and shrinks after damage, giving a
	-- smooth "drain" transition (current health = red, recently lost = white).
	local ghost = LUI.UIImage.new()
	ghost:setLeftRight(false, false, (-CoD.ZombieHealthBars.BARW / 2), (CoD.ZombieHealthBars.BARW / 2))
	ghost:setTopBottom(true, true, 0, 0)
	ghost:setImage(RegisterMaterial("white"))
	ghost:setRGB(1, 1, 1)
	ghost:setAlpha(0.6)
	bar:addElement(ghost)
	bar.ghost = ghost

	local fill = LUI.UIImage.new()
	fill:setLeftRight(false, false, (-CoD.ZombieHealthBars.BARW / 2), (CoD.ZombieHealthBars.BARW / 2))
	fill:setTopBottom(true, true, 0, 0)
	fill:setImage(RegisterMaterial("white"))
	fill:setRGB(1, 0, 0)
	fill:setAlpha(1)
	bar:addElement(fill)
	bar.fill = fill

	-- Square icon to the LEFT of the bar: a dark frame + a red fill (same black
	-- frame / colored fill look as the bar). Vertically centred on the bar.
	local icW = CoD.ZombieHealthBars.ICONW
	local icGap = CoD.ZombieHealthBars.ICONGAP
	local barLeft = (-CoD.ZombieHealthBars.BARW / 2)

	local iconFrame = LUI.UIImage.new()
	iconFrame:setLeftRight(false, false, (barLeft - icGap - icW), (barLeft - icGap))
	iconFrame:setTopBottom(false, true, -9, 3)
	iconFrame:setImage(RegisterMaterial("white"))
	iconFrame:setRGB(0, 0, 0)
	iconFrame:setAlpha(0.8)
	bar:addElement(iconFrame)
	bar.iconFrame = iconFrame

	local iconFill = LUI.UIImage.new()
	iconFill:setLeftRight(false, false, (barLeft - icGap - icW + 1), (barLeft - icGap - 1))
	iconFill:setTopBottom(false, true, -8, 2)
	iconFill:setImage(RegisterMaterial("white"))
	iconFill:setRGB(1, 0, 0)
	iconFill:setAlpha(1)
	bar:addElement(iconFill)
	bar.icon = iconFill

	-- Name label below the bar ("ZOMBIE" / "HELLHOUND"). Drawn twice — a black
	-- copy offset by 1px under the white copy — as a cheap shadow so it stays
	-- readable over the world.
	local nameShadow = LUI.UIText.new()
	nameShadow:setLeftRight(false, false, (-CoD.ZombieHealthBars.BARW / 2), 200)
	nameShadow:setTopBottom(false, true, 2, 16)
	nameShadow:setFont(CoD.fonts.ExtraSmall)
	nameShadow:setRGB(0, 0, 0)
	nameShadow:setAlignment(LUI.Alignment.Left)
	nameShadow:setAlpha(0.7)
	bar:addElement(nameShadow)
	bar.nameShadow = nameShadow

	local name = LUI.UIText.new()
	name:setLeftRight(false, false, ((-CoD.ZombieHealthBars.BARW / 2) + 1), 200)
	name:setTopBottom(false, true, 1, 15)
	name:setFont(CoD.fonts.ExtraSmall)
	name:setRGB(1, 1, 1)
	name:setAlignment(LUI.Alignment.Left)
	name:setAlpha(0.9)
	bar:addElement(name)
	bar.name = name

	return bar
end

-- Spawn a floating damage number at an entity. Uses a bounded pool so many hits
-- can stack their own number; the oldest slot is reused when the pool is full.
-- dist (player->zombie) scales the START height: close = low (at the body, so
-- melee hits are visible), far = up above the bar.
function CoD.ZombieHealthBars.SpawnDmg(self, entNum, amount, dist)
	local slot
	for i, s in ipairs(self.dmgSlots) do
		if not s.used then
			slot = s
			break
		end
	end
	if not slot then
		local best = self.dmgSlots[1]
		for i, s in ipairs(self.dmgSlots) do
			if s.life < best.life then
				best = s
			end
		end
		slot = best
	end

	local d = tonumber(dist) or CoD.ZombieHealthBars.DMGDISTREF
	local t = d / CoD.ZombieHealthBars.DMGDISTREF
	if t > 1 then t = 1 end
	if t < 0 then t = 0 end
	-- The number's FIRST frame must sit EXACTLY on the hit point (the static anchor
	-- GSC parked at the hit), so NO above-head / above-body start offset is added.
	-- (dist still only feeds the rise SPEED below, never the initial height.)
	slot.startZ = 0
	-- closer = slower rise (add extra frames, same total rise distance)
	local slow = 1 - t
	slot.steps = CoD.ZombieHealthBars.DMGSTEPS + math.floor(slow * CoD.ZombieHealthBars.DMGSLOW)

	slot.used = true
	slot.entNum = entNum
	slot.life = slot.steps + 1
	slot.num:setText(tostring(amount))
	slot.shadow:setText(tostring(amount))
	slot.root:setupEntityContainer(entNum, 0, 0, slot.startZ)
	slot.root:setAlpha(1)
	slot.num:setRGB(1, 0.15, 0.15)   -- start red
	slot.num:setAlpha(0.95)
	slot.shadow:setAlpha(0.7)
end

-- Advance every active pool slot: rise, fade, and a red->white colour gradient.
function CoD.ZombieHealthBars.StepDmg(self)
	for i, slot in ipairs(self.dmgSlots) do
		if slot.used and slot.life > 0 then
			slot.life = slot.life - 1
			local steps = slot.steps or CoD.ZombieHealthBars.DMGSTEPS
			if steps < 1 then steps = 1 end
			local prog = 1 - (slot.life / steps)
			if prog < 0 then prog = 0 end
			if prog > 1 then prog = 1 end
			local rise = prog * CoD.ZombieHealthBars.DMGRISE
			slot.startZ = slot.startZ or 0
			-- slot.entNum is a STATIC anchor GSC parked at the hit spot, so anchoring
			-- to it each tick keeps the number pinned there (it never rides the zombie).
			-- The rise is done in SCREEN-Y so the number goes straight up in place.
			slot.root:setupEntityContainer(slot.entNum, 0, 0, slot.startZ)
			slot.num:setTopBottom(false, false, (-10 - rise), (10 - rise))
			slot.shadow:setTopBottom(false, false, (-9 - rise), (11 - rise))
			slot.num:setRGB(1, 0.15 + prog * 0.85, 0.15 + prog * 0.85)  -- red -> white
			slot.num:setAlpha((1 - prog) * 0.95)
			slot.shadow:setAlpha((1 - prog) * 0.7)
			if slot.life <= 0 then
				slot.used = false
				slot.root:setAlpha(0)
			end
		end
	end
end

-- The notice is split into two parts because they ENTER differently (read off a
-- slow-motion capture of the source game): the "+100" score SCALES DOWN from ~1.9x to
-- 1.0x over ~0.26s, while the words simply appear as before. Hence two sub-boxes.
local function zhKillEase(u)
	-- cubic ease-out: leaves quickly, settles softly, so the shrink never snaps into place
	local inv = 1 - u
	return 1 - inv * inv * inv
end

-- Placement. x is KillX plus an optional fade slide; y comes from slot.y — the notice's
-- CURRENT distance down the column, not its lane index — so the whole group can glide
-- when a newer kill pushes everybody down.
local function zhKillPlace(slot, slide)
	local K = CoD.ZombieHealthBars
	local x = K.KillX + (slide or 0)
	local y = K.KillY + (slot.y or 0)
	slot.root:setLeftRight(false, false, x, (x + K.KillNumW + 380))
	slot.root:setTopBottom(false, false, y, (y + K.KillH))
end

-- Score pop. setScale() scales about the ELEMENT CENTRE, so scaling where it sits would
-- drag the score's right edge back and forth and open a breathing gap before the words.
-- Recomputing the box every frame as centre = R - hw*s keeps that right edge pinned at R
-- (== the words' left edge): the number grows LEFTWARDS in place and the gap is constant.
local function zhKillScale(slot, s)
	local K = CoD.ZombieHealthBars
	local hw = K.KillNumW * 0.5
	local cx = K.KillNumW - hw * s
	slot.hitBox:setLeftRight(true, false, (cx - hw), (cx + hw))
	slot.hitBox:setScale(s)
end

-- The queue ORDER is what defines lanes, so targets must be re-derived after every
-- insert and every removal. Anything pushed past the last visible row is flagged once:
-- it keeps descending one row further out while it fades on its own short clock, which
-- is how a 6th notice leaves the screen without ever getting a still frame of its own.
local function zhKillTargets(self)
	local K = CoD.ZombieHealthBars
	for i, slot in ipairs(self.killQueue) do
		slot.ty = (i - 1) * K.KillStack
		if i > K.MaxKill then
			if not slot.out then
				slot.out = true
				slot.outMs = 0
			end
		elseif slot.out then
			-- a row opened up above it, so it is back inside the visible list
			slot.out = false
			slot.outMs = 0
		end
	end
end

local function zhKillDrop(self, slot)
	for i, s in ipairs(self.killQueue) do
		if s == slot then
			table.remove(self.killQueue, i)
			return
		end
	end
end

-- Spawn one kill notice. Unlike the damage numbers these do NOT follow an entity:
-- BOCW pins them to a fixed spot right of the crosshair, so they use plain screen
-- offsets from the full-screen parent (false,false = measured from its centre).
function CoD.ZombieHealthBars.SpawnKill(self, score, crit)
	local K = CoD.ZombieHealthBars
	local slot
	for i, s in ipairs(self.killSlots) do
		if not s.used then
			slot = s
			break
		end
	end
	if not slot then
		-- every notice in the pool is still on screen (a kill rate that outruns the
		-- eject animation). Reuse whoever is closest to leaving rather than lose the kill.
		local best = self.killSlots[1]
		for i, s in ipairs(self.killSlots) do
			if s.left < best.left then
				best = s
			end
		end
		slot = best
		zhKillDrop(self, slot)
	end

	slot.used = true
	slot.ms = 0
	slot.left = (K.KillHold + K.KillFade) * 50     -- ms alive: hold first, fade last
	slot.out = false
	slot.outMs = 0
	slot.y = 0                                     -- enters on the TOP row...
	slot.ty = 0                                    -- ...and only moves once pushed down
	table.insert(self.killQueue, 1, slot)          -- NEWEST FIRST: everybody else shifts down
	zhKillTargets(self)

	-- Title case matches the source game's own score feed ("Zombie Kill" / "Critical
	-- Kill"). Score and words are separate elements because they enter separately.
	local hitText = "+" .. tostring(score)
	local words
	if crit == 1 then
		words = " Zombie Critical Kill"
	else
		words = " Zombie Elimination"
	end
	slot.hit:setText(hitText)
	slot.hitShadow:setText(hitText)
	slot.text:setText(words)
	slot.textShadow:setText(words)
	if crit == 1 then
		slot.hit:setRGB(1, 0.62, 0.12)    -- critical: amber
		slot.text:setRGB(1, 0.62, 0.12)
	else
		slot.hit:setRGB(1, 1, 1)          -- normal: white
		slot.text:setRGB(1, 1, 1)
	end
	-- place AND size it before the first draw, so nothing flashes in at 1x
	zhKillPlace(slot, 0)
	zhKillScale(slot, K.KillPop)
	slot.root:setAlpha(1)

	-- the fast clock only exists while something is actually on screen
	if not self.killFastTimer then
		self.killFastTimer = LUI.UITimer.new(K.KillTick, "zh_killfast", false, self)
		self:addElement(self.killFastTimer)
	end
end

-- Advance every live notice on the fast clock. Three phases:
--   pop  (first KillPopMs)  : the score shrinks KillPop -> 1.0, eased; words are already shown
--   hold                     : absolutely nothing moves
--   fade (last KillFade*50) : everything dims while sliding a few units to the right
-- Notice ORDER *is* screen order: index 1 is the top row, so a new kill (inserted at the head
-- by SpawnKill) makes every older notice slide down one lane, and a notice leaving mid-list
-- glides the ones below it back up. Anything pushed past row MaxKill also runs the short eject
-- clock, so it fades while descending rather than ever standing still as a 6th line.
function CoD.ZombieHealthBars.StepKill(self)
	local K = CoD.ZombieHealthBars
	zhKillTargets(self)
	local step = K.KillStack * (K.KillTick / K.KillMoveMs)     -- lane units travelled per tick
	local holdMs = K.KillHold * 50
	local fadeMs = K.KillFade * 50
	local i = 1
	while i <= #self.killQueue do
		local slot = self.killQueue[i]
		slot.ms = slot.ms + K.KillTick
		slot.left = slot.left - K.KillTick
		if slot.left < 0 then
			slot.left = 0
		end

		-- glide toward the lane this notice currently sits at in the queue
		if slot.y < slot.ty then
			slot.y = slot.y + step
			if slot.y > slot.ty then
				slot.y = slot.ty
			end
		elseif slot.y > slot.ty then
			slot.y = slot.y - step
			if slot.y < slot.ty then
				slot.y = slot.ty
			end
		end

		-- the pop
		local u = slot.ms / K.KillPopMs
		if u > 1 then
			u = 1
		end
		zhKillScale(slot, 1 + (K.KillPop - 1) * (1 - zhKillEase(u)))

		-- end-of-life fade
		local prog = 0
		if slot.ms > holdMs then
			prog = (slot.ms - holdMs) / fadeMs
			if prog > 1 then
				prog = 1
			end
		end

		-- overflow: whichever clock bites first wins, so a notice that got pushed past
		-- the last visible row is on its way out long before it could stand there as a 6th line
		if slot.out then
			slot.outMs = slot.outMs + K.KillTick
			local ej = slot.outMs / K.KillEjectMs
			if ej > 1 then
				ej = 1
			end
			if ej > prog then
				prog = ej
			end
		end

		zhKillPlace(slot, prog * K.KillSlide)
		slot.hitBox:setAlpha(1 - prog)
		slot.textBox:setAlpha(1 - prog)

		if prog >= 1 then
			table.remove(self.killQueue, i)
			slot.used = false
			slot.root:setAlpha(0)
		else
			i = i + 1
		end
	end
	return #self.killQueue > 0
end

function CoD.ZombieHealthBars.GetBar(self, idx)
	local bar = self.bars[idx]
	if not bar then
		bar = CoD.ZombieHealthBars.NewBar()
		self.bars[idx] = bar
		self:addElement(bar)
	end
	return bar
end

-- Parse the dvar and update every bar (bars are keyed by entity number so each
-- zombie keeps its own bar even when the list order changes).
function CoD.ZombieHealthBars.Poll(self, event)
	if not CoD.ZombieHealthBars.Enabled then
		return
	end

	local seen = {}
	local count = 0
	-- The bar payload is batched across several client dvars "zh_data_0..N" so a
	-- single dvar doesn't get too long (which dropped the tail bars with many zombies).
	for di = 0, (CoD.ZombieHealthBars.NUMDVARS - 1) do
		local payload = UIExpression.DvarString(nil, ("zh_data_" .. di)) or ""
		for chunk in payload:gmatch("[^;]+") do
			local e, r, a, nm, dd = chunk:match("([^:]+):([^:]+):([^:]+):([^:]+):([^:]+)")
			if e then
				local entNum = tonumber(e) or 0
				local ratio100 = tonumber(r) or 100
				local alpha100 = tonumber(a) or 0
				local dist = tonumber(dd) or CoD.ZombieHealthBars.BARDISTREF
				if entNum > 0 then
					count = count + 1
					seen[entNum] = true

				local bar = self.bars[entNum]
				if not bar then
					bar = CoD.ZombieHealthBars.NewBar()
					self.bars[entNum] = bar
					self:addElement(bar)
				end

				-- ONE distance scale k drives BOTH the bar's size (SizeBar below) and its
				-- screen-space clearance, so the two stay in lock-step at every range.
				-- Perspective-true: shrinking is never capped; only zoom-in has a ceiling.
				-- The denominator floor is purely a divide-by-zero / clipping guard.
				local k = CoD.ZombieHealthBars.BARDISTREF / (dist > 8 and dist or 8)
				-- (Set BARSCALEMAX = nil to remove the zoom-in ceiling entirely.)
				if CoD.ZombieHealthBars.BARSCALEMAX and k > CoD.ZombieHealthBars.BARSCALEMAX then
					k = CoD.ZombieHealthBars.BARSCALEMAX
				end
				bar.curScale = k

				-- Clearance is applied in SCREEN space (screen-up is always screen-up),
				-- which is exactly what fixes the old bug: a WORLD-vertical lift collapses
				-- onto the zombie when the player looks DOWN at it from high ground and the
				-- bar hid its head.
				-- Clearance comes from HEADZ_TABLE (linearly interpolated, so no steps).
				-- Screen space, NOT world-vertical: a world-vertical lift collapses onto
				-- the zombie when the player looks DOWN at it from high ground.
				bar:setupEntityContainer(entNum, 0, 0, CoD.ZombieHealthBars.HEADZAt(dist))

				local target = ratio100 / 100
				if target > 1 then target = 1 end
				if target < 0 then target = 0 end

				-- red fill snaps to current health; the white ghost LAGS then
				-- drains toward it, giving a smooth transition.
				if bar.ghostRatio == nil then
					bar.ghostRatio = target
				elseif target >= bar.ghostRatio then
					bar.ghostRatio = target
				else
					bar.ghostRatio = bar.ghostRatio + (target - bar.ghostRatio) * 0.25
					if bar.ghostRatio < target then bar.ghostRatio = target end
				end

				-- full geometric relayout at this distance's scale (symmetric about anchor)
				CoD.ZombieHealthBars.SizeBar(bar, bar.curScale, target, bar.ghostRatio)

				local a = alpha100 / 100
				if a > 1 then a = 1 end
				if a < 0 then a = 0 end
				bar:setAlpha(a)
				if bar.bg then
					bar.bg:setAlpha(a * 0.8)     -- solid black backing
				end
				if bar.ghost then
					bar.ghost:setAlpha(a * 0.6)  -- white ghost chunk
				end
				bar.fill:setAlpha((a * 0.9))     -- bright red fill
				if bar.iconFrame then
					bar.iconFrame:setAlpha(a * 0.8)
				end
				if bar.icon then
					bar.icon:setAlpha(a * 0.9)
				end
				if bar.name then
					bar.name:setAlpha(a)
					if bar.nameText ~= nm then
						bar.name:setText(nm or "")
						bar.nameText = nm
						-- Icon colour is table-driven (ICON_TINT, keyed by the label the
						-- GSC sends). New actor kind = one row in that table, no branch.
						if bar.icon then
							local tint = CoD.ZombieHealthBars.ICON_TINT[nm]
							if not tint then
								tint = CoD.ZombieHealthBars.ICON_TINT.ZOMBIE
							end
							bar.icon:setRGB(tint[1], tint[2], tint[3])
						end
					end
				end
				if bar.nameShadow then
					bar.nameShadow:setAlpha(a * 0.7)
				end
				bar.curRatio = target           -- remember for the death drain
				bar.curAlpha = a
			end
		end
	end
	end

	-- Floating damage numbers come from a separate event dvar "entNum:amount:seq",
	-- NOT the health-bar array, so they also fire for a killing blow even after the
	-- zombie left the array. Dedupe by seq (events are re-sent for ~0.3s), then give
	-- each hit its OWN pool slot so lots of numbers can stack.
	local dmgPayload = UIExpression.DvarString(nil, "zh_dmg") or ""
	for chunk in dmgPayload:gmatch("[^;]+") do
		local e, a, s, d = chunk:match("([^:]+):([^:]+):([^:]+):([^:]+)")
		if e then
			local entNum = tonumber(e) or 0
			local amt = tonumber(a) or 0
			local seq = tonumber(s) or 0
			local dist = tonumber(d) or 0
			if entNum > 0 and seq > (self.lastDmgSeq or 0) then
				self.lastDmgSeq = seq
				CoD.ZombieHealthBars.SpawnDmg(self, entNum, amt, dist)
			end
		end
	end

	-- Kill notices arrive on their own dvar as "seq:score:crit". GSC re-sends each
	-- event for ~1.2s so a 0.1s poll can't miss it, hence dedupe on the per-player seq.
	local killPayload = UIExpression.DvarString(nil, "zh_kill") or ""
	for chunk in killPayload:gmatch("[^;]+") do
		local ks, ksc, kc = chunk:match("([^:]+):([^:]+):([^:]+)")
		if ks then
			local kseq = tonumber(ks) or 0
			local kscore = tonumber(ksc) or 0
			local kcrit = tonumber(kc) or 0
			if kseq > (self.lastKillSeq or 0) then
				self.lastKillSeq = kseq
				CoD.ZombieHealthBars.SpawnKill(self, kscore, kcrit)
			end
		end
	end

	-- Bars no longer in the string (dead / too far): drain their fill to 0 over
	-- a few frames so they fade out instead of vanishing instantly.
	for entNum, bar in pairs(self.bars) do
		if not seen[entNum] then
			bar.curRatio = (bar.curRatio or 0) * 0.6          -- retreat 40% per poll
			local a = bar.curAlpha or 0                        -- keep current visibility

			if bar.ghost then
				bar.ghostRatio = (bar.ghostRatio or bar.curRatio)
				bar.ghostRatio = bar.ghostRatio + (bar.curRatio - bar.ghostRatio) * 0.3
				if bar.ghostRatio < bar.curRatio then bar.ghostRatio = bar.curRatio end
			end
			-- keep this bar's last distance scale while it drains (no size pop)
			CoD.ZombieHealthBars.SizeBar(bar, bar.curScale or 1, bar.curRatio, bar.ghostRatio)

			if bar.ghost then
				bar.ghost:setAlpha(a * 0.6)
			end

			bar:setAlpha(a)
			if bar.bg then
				bar.bg:setAlpha(a * 0.8)
			end
			bar.fill:setAlpha((a * 0.9))
			if bar.iconFrame then
				bar.iconFrame:setAlpha(a * 0.8)
			end
			if bar.icon then
				bar.icon:setAlpha(a * 0.9)
			end
			if bar.name then
				bar.name:setAlpha(a)
			end
			if bar.nameShadow then
				bar.nameShadow:setAlpha(a * 0.7)
			end

			if bar.curRatio <= 0.02 then                      -- fully drained -> hide
				bar:setAlpha(0)
				if bar.bg then
					bar.bg:setAlpha(0)
				end
				if bar.ghost then
					bar.ghost:setAlpha(0)
				end
				if bar.fill then
					bar.fill:setAlpha(0)
				end
				if bar.iconFrame then
					bar.iconFrame:setAlpha(0)
				end
				if bar.icon then
					bar.icon:setAlpha(0)
				end
				if bar.name then
					bar.name:setAlpha(0)
				end
				if bar.nameShadow then
					bar.nameShadow:setAlpha(0)
				end
			end
		end
	end

end

-- The HUD element factory (called by the overridden hud.lua).
LUI.createMenu.ZombieHealthBars = function(controller)
	local self = LUI.UIElement.new()
	self:setLeftRight(true, true, 0, 0)
	self:setTopBottom(true, true, 0, 0)
	self.controller = controller
	self.bars = {}
	self.lastDmgSeq = 0

	-- Pre-create the damage-number pool: each slot is an entity-following container
	-- with a bold number + black shadow. Hidden until a hit claims it.
	self.dmgSlots = {}
	for i = 1, CoD.ZombieHealthBars.MaxDmg do
		local root = LUI.UIElement.new()
		root:setLeftRight(false, false, -40, 40)
		root:setTopBottom(false, false, -10, 10)
		root:setAlpha(0)
		local shadow = LUI.UIText.new()
		shadow:setLeftRight(false, false, -41, 41)
		shadow:setTopBottom(false, false, -9, 11)
		shadow:setFont(CoD.fonts.Bold)
		shadow:setRGB(0, 0, 0)
		shadow:setAlignment(LUI.Alignment.Center)
		shadow:setAlpha(0)
		root:addElement(shadow)
		local num = LUI.UIText.new()
		num:setLeftRight(false, false, -40, 40)
		num:setTopBottom(false, false, -10, 10)
		num:setFont(CoD.fonts.Bold)
		num:setRGB(1, 0, 0)
		num:setAlignment(LUI.Alignment.Center)
		num:setAlpha(0)
		root:addElement(num)
		self:addElement(root)
		self.dmgSlots[i] = { root = root, num = num, shadow = shadow, life = 0, entNum = 0, used = false, startZ = 0, steps = CoD.ZombieHealthBars.DMGSTEPS }
	end

	-- Kill-notice pool: fixed-position text pairs (a black copy 1px under the live
	-- copy, same trick as the zombie names). Inactive slots sit at alpha 0.
	self.killSlots = {}
	self.lastKillSeq = 0
	self.killQueue = {}        -- slot refs, ORDER = screen order, index 1 = top row
	-- MaxKill + 1: the notice that just got pushed PAST the last visible row still needs an
	-- element to play its descend-and-fade with, so the pool runs one deeper than the number
	-- of rows that can be shown at once.
	for i = 1, CoD.ZombieHealthBars.MaxKill + 1 do
		local kroot = LUI.UIElement.new()
		kroot:setLeftRight(false, false, CoD.ZombieHealthBars.KillX, (CoD.ZombieHealthBars.KillX + CoD.ZombieHealthBars.KillNumW + 380))
		kroot:setTopBottom(false, false, CoD.ZombieHealthBars.KillY, (CoD.ZombieHealthBars.KillY + CoD.ZombieHealthBars.KillH))
		kroot:setAlpha(0)

		-- score sub-box: the ONLY thing that gets scaled
		local hitBox = LUI.UIElement.new()
		hitBox:setLeftRight(true, false, 0, CoD.ZombieHealthBars.KillNumW)
		hitBox:setTopBottom(true, false, 0, CoD.ZombieHealthBars.KillH)
		kroot:addElement(hitBox)
		local hitShadow = LUI.UIText.new()
		hitShadow:setLeftRight(true, false, 1, CoD.ZombieHealthBars.KillNumW)
		hitShadow:setTopBottom(true, false, 1, CoD.ZombieHealthBars.KillH)
		hitShadow:setFont(CoD.fonts.Condensed)
		hitShadow:setRGB(0, 0, 0)
		hitShadow:setAlignment(LUI.Alignment.Right)
		hitShadow:setAlpha(0.6)
		hitBox:addElement(hitShadow)
		local hit = LUI.UIText.new()
		hit:setLeftRight(true, false, 0, CoD.ZombieHealthBars.KillNumW)
		hit:setTopBottom(true, false, 0, CoD.ZombieHealthBars.KillH)
		hit:setFont(CoD.fonts.Condensed)
		hit:setRGB(1, 1, 1)
		hit:setAlignment(LUI.Alignment.Right)
		hit:setAlpha(1)
		hitBox:addElement(hit)

		-- words sub-box: just appears, never scales
		local textBox = LUI.UIElement.new()
		textBox:setLeftRight(true, false, CoD.ZombieHealthBars.KillNumW, (CoD.ZombieHealthBars.KillNumW + 380))
		textBox:setTopBottom(true, false, 0, CoD.ZombieHealthBars.KillH)
		kroot:addElement(textBox)
		local txtShadow = LUI.UIText.new()
		txtShadow:setLeftRight(true, false, 1, 380)
		txtShadow:setTopBottom(true, false, 1, CoD.ZombieHealthBars.KillH)
		txtShadow:setFont(CoD.fonts.Condensed)
		txtShadow:setRGB(0, 0, 0)
		txtShadow:setAlignment(LUI.Alignment.Left)
		txtShadow:setAlpha(0.6)
		textBox:addElement(txtShadow)
		local txt = LUI.UIText.new()
		txt:setLeftRight(true, false, 0, 380)
		txt:setTopBottom(true, false, 0, CoD.ZombieHealthBars.KillH)
		txt:setFont(CoD.fonts.Condensed)
		txt:setRGB(1, 1, 1)
		txt:setAlignment(LUI.Alignment.Left)
		txt:setAlpha(1)
		textBox:addElement(txt)

		self:addElement(kroot)
		self.killSlots[i] = { root = kroot, hitBox = hitBox, textBox = textBox, hit = hit, hitShadow = hitShadow, text = txt, textShadow = txtShadow, ms = 0, left = 0, y = 0, ty = 0, out = false, outMs = 0, used = false }
	end

	-- Poll the dvar. LUI.UITimer is one-shot, so self-reschedule: close the old
	-- timer first (the stock HUD closes timers with :close() — :destroy() crashes),
	-- then add a fresh one. This polls every 100ms with no accumulation.
	self:registerEventHandler("zh_poll", function(this, ev)
		if this.pollTimer then
			this.pollTimer:close()
			this.pollTimer = nil
		end
		CoD.ZombieHealthBars.Poll(this)
		this.pollTimer = LUI.UITimer.new(100, "zh_poll", false, this)
		this:addElement(this.pollTimer)
	end)
	self.pollTimer = LUI.UITimer.new(100, "zh_poll", false, self)
	self:addElement(self.pollTimer)

	-- Faster timer (33ms) that advances the floating damage-number pool so the
	-- rise/fade is smooth. Same self-reschedule pattern (close the old — :destroy()
	-- crashes), never accumulates timers.
	self:registerEventHandler("zh_dmganim", function(this, ev)
		if this.dmgAnimTimer then
			this.dmgAnimTimer:close()
			this.dmgAnimTimer = nil
		end
		CoD.ZombieHealthBars.StepDmg(this)
		this.dmgAnimTimer = LUI.UITimer.new(50, "zh_dmganim", false, this)
		this:addElement(this.dmgAnimTimer)
	end)
	self.dmgAnimTimer = LUI.UITimer.new(50, "zh_dmganim", false, self)
	self:addElement(self.dmgAnimTimer)

	-- Fast clock for the kill notices ONLY: 25ms, so the score pop reads as a continuous
	-- shrink instead of a handful of visible jumps. It is NOT self-sustaining — StepKill
	-- returns false once every slot has expired, and the chain then stops rescheduling, so
	-- the notices cost nothing between kills. The next SpawnKill restarts it. Same
	-- close-the-old-timer shape as above (:destroy() crashes, :close() is what the stock HUD uses).
	self.killFastTimer = nil
	self:registerEventHandler("zh_killfast", function(this, ev)
		if this.killFastTimer then
			this.killFastTimer:close()
			this.killFastTimer = nil
		end
		if CoD.ZombieHealthBars.StepKill(this) then
			this.killFastTimer = LUI.UITimer.new(CoD.ZombieHealthBars.KillTick, "zh_killfast", false, this)
			this:addElement(this.killFastTimer)
		end
	end)

	-- expose the live widget so the HUD-root hook (if any) can reach it
	CoD.ZombieHealthBars.current = self

	return self
end
