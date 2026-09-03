-- ============================================================================
--  ZombieHealthBars (LUI / t6)  --  COD17-style health bars above zombie heads
--
--  DATA FLOW (server -> client)
--    * GSC packs per-zombie data into dvar "zh_data" as:
--          "entityNum:ratio100:alpha100:name;..."  (semicolon per zombie, every ~0.1s)
--    * GSC pushes damage-number events into dvar "zh_dmg" as:
--          "entityNum:amount:seq:distance;..."  (retained ~0.3s; deduped by seq)
--    * This element polls both dvars every 100ms (LUI.UITimer), parses them, and
--      follows each zombie via setupEntityContainer(entityNum).
--    (dvar + UIExpression.DvarString is used because both luinotifyevent custom
--     names and the client-field budget are unavailable/exhausted in this game.)
-- ============================================================================

CoD.ZombieHealthBars = {}

CoD.ZombieHealthBars.Enabled   = true
CoD.ZombieHealthBars.BARW      = 60
CoD.ZombieHealthBars.BARH      = 6
CoD.ZombieHealthBars.HEADZ     = 70      -- px above the head (entity-container offset)
CoD.ZombieHealthBars.MAXALPHA  = 0.85
CoD.ZombieHealthBars.ICONW     = 12      -- square icon (red fill + black frame)
CoD.ZombieHealthBars.ICONGAP   = 6       -- gap between the icon and the bar
CoD.ZombieHealthBars.MaxDmg    = 16      -- damage-number pool size (concurrent popups)
CoD.ZombieHealthBars.DMGSTEPS  = 17      -- float frames (50ms each -> ~0.85s)
CoD.ZombieHealthBars.DMGRISE   = 30      -- total px the number rises
CoD.ZombieHealthBars.DMGTOP    = 6       -- px above the bar at LONG range
CoD.ZombieHealthBars.DMGBODY   = 30      -- start height at CLOSE range (zombie's body)
CoD.ZombieHealthBars.DMGDISTREF = 200    -- distance at which it reaches the above-head start
CoD.ZombieHealthBars.DMGSLOW   = 18      -- extra frames at CLOSE range (slower rise)
CoD.ZombieHealthBars.NUMDVARS  = 8       -- number of zh_data_# dvars (batched payload)

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
	local high = CoD.ZombieHealthBars.HEADZ + CoD.ZombieHealthBars.DMGTOP
	slot.startZ = CoD.ZombieHealthBars.DMGBODY + (high - CoD.ZombieHealthBars.DMGBODY) * t
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
			slot.startZ = slot.startZ or (CoD.ZombieHealthBars.HEADZ + CoD.ZombieHealthBars.DMGTOP)
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
			local e, r, a, nm = chunk:match("([^:]+):([^:]+):([^:]+):([^:]+)")
			if e then
				local entNum = tonumber(e) or 0
				local ratio100 = tonumber(r) or 100
				local alpha100 = tonumber(a) or 0
				if entNum > 0 then
					count = count + 1
					seen[entNum] = true

				local bar = self.bars[entNum]
				if not bar then
					bar = CoD.ZombieHealthBars.NewBar()
					self.bars[entNum] = bar
					self:addElement(bar)
				end

				bar:setupEntityContainer(entNum, 0, 0, CoD.ZombieHealthBars.HEADZ)

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

				local w = CoD.ZombieHealthBars.BARW * target
				if w < 1 then w = 1 end
				bar.fill:setLeftRight(false, false, (-CoD.ZombieHealthBars.BARW / 2), ((-CoD.ZombieHealthBars.BARW / 2) + w))

				if bar.ghost then
					local gw = CoD.ZombieHealthBars.BARW * bar.ghostRatio
					if gw < 1 then gw = 1 end
					bar.ghost:setLeftRight(false, false, (-CoD.ZombieHealthBars.BARW / 2), ((-CoD.ZombieHealthBars.BARW / 2) + gw))
				end

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
						-- tint the icon by entity type (red zombie / orange hound)
						if bar.icon then
							if nm == "HELLHOUND" then
								bar.icon:setRGB(1, 0.55, 0)
							else
								bar.icon:setRGB(1, 0, 0)
							end
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

	-- Bars no longer in the string (dead / too far): drain their fill to 0 over
	-- a few frames so they fade out instead of vanishing instantly.
	for entNum, bar in pairs(self.bars) do
		if not seen[entNum] then
			bar.curRatio = (bar.curRatio or 0) * 0.6          -- retreat 40% per poll
			local a = bar.curAlpha or 0                        -- keep current visibility

			local w = CoD.ZombieHealthBars.BARW * bar.curRatio
			if w < 1 then w = 1 end
			bar.fill:setLeftRight(false, false, (-CoD.ZombieHealthBars.BARW / 2), ((-CoD.ZombieHealthBars.BARW / 2) + w))

			if bar.ghost then
				bar.ghostRatio = (bar.ghostRatio or bar.curRatio)
				bar.ghostRatio = bar.ghostRatio + (bar.curRatio - bar.ghostRatio) * 0.3
				if bar.ghostRatio < bar.curRatio then bar.ghostRatio = bar.curRatio end
				local gw = CoD.ZombieHealthBars.BARW * bar.ghostRatio
				if gw < 1 then gw = 1 end
				bar.ghost:setLeftRight(false, false, (-CoD.ZombieHealthBars.BARW / 2), ((-CoD.ZombieHealthBars.BARW / 2) + gw))
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
		self.dmgSlots[i] = { root = root, num = num, shadow = shadow, life = 0, entNum = 0, used = false, startZ = (CoD.ZombieHealthBars.HEADZ + CoD.ZombieHealthBars.DMGTOP), steps = CoD.ZombieHealthBars.DMGSTEPS }
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

	-- expose the live widget so the HUD-root hook (if any) can reach it
	CoD.ZombieHealthBars.current = self

	return self
end
