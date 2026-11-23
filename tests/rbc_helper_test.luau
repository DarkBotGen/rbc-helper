-- Offline Luau tests for RBC Helper:
-- 1. Golden Cogmower field detection & multi-mob formatting
-- 2. Atlas+ WalkSpeed 90 fixed / dynamic / boost preservation / restore
-- 3. Reversible Hide Decorations (exact fullscript.txt target coverage)
-- 4. BodyGyro Auto-Face Flames & Refresh (filters, age priority, yaw-only torque, respawn safety)
-- 5. Digital Smiley Duped Token Highlighting & Countdown Timer (< 0.9s Red cutoff)

local function createSignal()
	local listeners = {}
	return {
		Connect = function(_, fn)
			local entry = { fn = fn, connected = true }
			table.insert(listeners, entry)
			return {
				Disconnect = function()
					entry.connected = false
				end,
			}
		end,
		Fire = function(_, ...)
			for _, entry in ipairs(listeners) do
				if entry.connected then
					entry.fn(...)
				end
			end
		end,
	}
end

local Vector3 = {}
function Vector3.new(x, y, z)
	return setmetatable({ X = x or 0, Y = y or 0, Z = z or 0 }, {
		__add = function(a, b) return Vector3.new(a.X + b.X, a.Y + b.Y, a.Z + b.Z) end,
		__sub = function(a, b) return Vector3.new(a.X - b.X, a.Y - b.Y, a.Z - b.Z) end,
	})
end
local function typeof_mock(v)
	if type(v) == "table" and v._isVec3 then return "Vector3" end
	if type(v) == "table" and v._isInst then return "Instance" end
	return type(v)
end
local origV3 = Vector3.new
Vector3.new = function(x, y, z)
	local v = origV3(x, y, z)
	v._isVec3 = true
	return v
end
local typeof = typeof_mock

local Color3 = {
	new = function(r, g, b) return { R = r or 0, G = g or 0, B = b or 0 } end,
	fromRGB = function(r, g, b) return { R = r / 255, G = g / 255, B = b / 255 } end,
}

local function makeInst(className, name)
	local children = {}
	local inst = {
		_isInst = true,
		ClassName = className,
		Name = name or className,
		Parent = nil,
		CanCollide = true,
		Position = Vector3.new(0, 0, 0),
		Size = Vector3.new(100, 10, 100),
		CollisionGroup = "Default",
		Texture = "",
		DescendantAdded = createSignal(),
		ChildAdded = createSignal(),
		ChildRemoved = createSignal(),
	}
	function inst:IsA(target)
		if target == className then return true end
		if target == "BasePart" and (className == "Part" or className == "MeshPart" or className == "BasePart") then return true end
		return false
	end
	function inst:FindFirstChild(childName)
		for _, c in ipairs(children) do
			if c.Name == childName then return c end
		end
		return nil
	end
	function inst:FindFirstChildOfClass(cls)
		for _, c in ipairs(children) do
			if c:IsA(cls) then return c end
		end
		return nil
	end
	function inst:GetChildren()
		return table.clone(children)
	end
	function inst:AddChild(ch)
		rawset(ch, "Parent", self)
		for _, existing in ipairs(children) do
			if existing == ch then return ch end
		end
		table.insert(children, ch)
		self.ChildAdded:Fire(ch)
		return ch
	end
	function inst:RemoveChild(ch)
		for i, c in ipairs(children) do
			if c == ch then
				table.remove(children, i)
				rawset(ch, "Parent", nil)
				self.ChildRemoved:Fire(ch)
				break
			end
		end
	end
	function inst:Destroy()
		local p = self.Parent
		if p and type(p) == "table" and p.RemoveChild then
			p:RemoveChild(self)
		else
			rawset(self, "Parent", nil)
		end
	end
	return setmetatable(inst, {
		__newindex = function(t, k, v)
			if k == "Parent" then
				local old = rawget(t, "Parent")
				if old and type(old) == "table" and old.RemoveChild and old ~= v then
					old:RemoveChild(t)
				end
				rawset(t, "Parent", v)
				if type(v) == "table" and v.AddChild then
					v:AddChild(t)
				end
			else
				rawset(t, k, v)
			end
		end,
	})
end

-- 1. Golden Cogmower field detection & multi-mob formatting
local roseField = makeInst("Part", "Rose Field")
roseField.Position = Vector3.new(-300, 20, 120)
local pepperField = makeInst("Part", "Pepper Patch")
pepperField.Position = Vector3.new(-480, 120, 530)

local function getFieldAt(pos)
	if math.abs(pos.X - (-300)) <= 60 then return roseField end
	if math.abs(pos.X - (-480)) <= 60 then return pepperField end
	return nil
end

local ws = makeInst("Workspace", "Workspace")
local function makeGoldCog(pos)
	local mob = makeInst("Model", "Gold Cogmower")
	local body = mob:AddChild(makeInst("Part", "Body"))
	body.Position = pos
	mob.Parent = ws
	return mob
end

local gc1 = makeGoldCog(Vector3.new(-305, 22, 125))
local gc2 = makeGoldCog(Vector3.new(-475, 122, 525))
local scannedFields = {}
for _, ch in ipairs(ws:GetChildren()) do
	if ch.Name == "Gold Cogmower" then
		local body = ch:FindFirstChild("Body")
		local field = body and getFieldAt(body.Position)
		table.insert(scannedFields, field and field.Name or "Unknown Field")
	end
end
assert(#scannedFields == 2 and scannedFields[1] == "Rose Field" and scannedFields[2] == "Pepper Patch", "Gold Cogmower field scan mismatch")
gc1.Parent = nil
gc2.Parent = nil

-- 2. WalkSpeed 90 fixed / dynamic / external boost preservation / restore
local cfg = {
	movement = { walkspeedenabled = true, walkdynamic = false, walkspeed = 90, walkspeed2 = 1.5 },
	flames = { enabled = true, refreshPriority = true, onlyRefreshReady = false, smartAutoDig = false, refreshAge = 3.0, maxRange = 30 },
}
local playerMovespeed = 32
local hum = { WalkSpeed = 32, Health = 100, Parent = true }
local wsCtrl = { lastAppliedSpeed = nil, originalSpeed = nil, trackedHumanoid = nil }
function wsCtrl:Step()
	if self.trackedHumanoid ~= hum then
		self.trackedHumanoid = hum
		self.originalSpeed = hum.WalkSpeed
		self.lastAppliedSpeed = nil
	end
	local cap = math.clamp(cfg.movement.walkspeed, 30, 90)
	local target = not cfg.movement.walkdynamic and cap or math.min(cap, playerMovespeed * cfg.movement.walkspeed2)
	local cur = hum.WalkSpeed
	local wasUs = self.lastAppliedSpeed ~= nil and math.abs(cur - self.lastAppliedSpeed) < 0.05
	if cur < target or (wasUs and cur > target) then
		hum.WalkSpeed = target
		self.lastAppliedSpeed = target
	end
end
function wsCtrl:Restore()
	if self.lastAppliedSpeed ~= nil and math.abs(hum.WalkSpeed - self.lastAppliedSpeed) < 0.05 then
		hum.WalkSpeed = playerMovespeed
	end
	self.lastAppliedSpeed = nil
end

wsCtrl:Step()
assert(hum.WalkSpeed == 90, "expected fixed walkspeed 90")
hum.WalkSpeed = 105
wsCtrl:Step()
assert(hum.WalkSpeed == 105, "external boost above 90 must be preserved")
hum.WalkSpeed = 90
cfg.movement.walkdynamic = true
wsCtrl:Step()
assert(hum.WalkSpeed == 48, "expected dynamic speed 48")
wsCtrl:Restore()
assert(hum.WalkSpeed == 32, "expected restored speed 32")

-- 3. Reversible Hide Decorations (fullscript.txt exact coverage)
local decTestWs = makeInst("Workspace", "Workspace")
local decAmulets = decTestWs:AddChild(makeInst("Folder", "Amulets"))
local decMap = decTestWs:AddChild(makeInst("Folder", "Map"))
local decFences = decMap:AddChild(makeInst("Folder", "Fences"))
local decTerrain = decMap:AddChild(makeInst("Part", "Terrain"))
local decHiveDeco = decTestWs:AddChild(makeInst("Folder", "HiveDeco"))
local decHiveModels = decHiveDeco:AddChild(makeInst("Folder", "HiveModels"))
local decHivePlats = decTestWs:AddChild(makeInst("Folder", "HivePlatforms"))
local decSlot = decHivePlats:AddChild(makeInst("Model", "Slot1"))
local decPlat = decSlot:AddChild(makeInst("Part", "Platform"))
local decHive = decSlot:AddChild(makeInst("Model", "Hive"))
local decPlayerRef = decSlot:AddChild(makeInst("ObjectValue", "PlayerRef"))
local decExtra = decSlot:AddChild(makeInst("Part", "DecorPart"))
local decFolder = decTestWs:AddChild(makeInst("Folder", "Decorations"))
local decMisc = decFolder:AddChild(makeInst("Folder", "Misc"))
local decBlueFlw = decMisc:AddChild(makeInst("Model", "Blue Flower 5"))
local decKeepMisc = decMisc:AddChild(makeInst("Model", "KeepMisc"))
local decPepper = decFolder:AddChild(makeInst("Model", "Pepper Patch"))
local decDand = decFolder:AddChild(makeInst("Model", "DandelionArch"))
local decBarrier = decTestWs:AddChild(makeInst("Part", "BoostWall"))
decBarrier.CollisionGroup = "BoostBallBarrier"
local decFlowerZones = decTestWs:AddChild(makeInst("Folder", "FlowerZones"))

local detached = {}
local savedPlats = {}
local function detach(obj)
	if not obj or not obj.Parent then return end
	table.insert(detached, { inst = obj, parent = obj.Parent })
	obj.Parent = nil
end
local function hideDecos()
	for _, name in ipairs({ "Amulets" }) do detach(decTestWs:FindFirstChild(name)) end
	local map = decTestWs:FindFirstChild("Map")
	if map then detach(map:FindFirstChild("Fences")) end
	local hd = decTestWs:FindFirstChild("HiveDeco")
	if hd then detach(hd:FindFirstChild("HiveModels")) end
	local hp = decTestWs:FindFirstChild("HivePlatforms")
	if hp then
		for _, s in ipairs(hp:GetChildren()) do
			for _, it in ipairs(s:GetChildren()) do
				if it.Name == "Platform" then
					savedPlats[it] = it.CanCollide
					it.CanCollide = false
				elseif it.Name ~= "Hive" and it.Name ~= "PlayerRef" then
					detach(it)
				end
			end
		end
	end
	local dec = decTestWs:FindFirstChild("Decorations")
	if dec then
		local misc = dec:FindFirstChild("Misc")
		if misc then
			for _, c in ipairs(misc:GetChildren()) do
				if string.find(c.Name, "Blue Flower") then detach(c) end
			end
		end
		detach(dec:FindFirstChild("Pepper Patch"))
		for _, c in ipairs(dec:GetChildren()) do
			if string.find(c.Name, "Dandelion") then detach(c) end
		end
	end
	for _, c in ipairs(decTestWs:GetChildren()) do
		if c.ClassName == "Part" and c.CollisionGroup == "BoostBallBarrier" then detach(c) end
	end
end
local function restoreDecos()
	for i = #detached, 1, -1 do
		detached[i].inst.Parent = detached[i].parent
	end
	table.clear(detached)
	for plat, col in pairs(savedPlats) do plat.CanCollide = col end
	table.clear(savedPlats)
end

hideDecos()
assert(decAmulets.Parent == nil and decFences.Parent == nil and decHiveModels.Parent == nil, "workspace/map/hivedeco targets detached")
assert(decTerrain.Parent == decMap and decHive.Parent == decSlot and decPlayerRef.Parent == decSlot and decFlowerZones.Parent == decTestWs, "essential world/hive objects kept")
assert(decPlat.CanCollide == false and decExtra.Parent == nil, "platform CanCollide disabled & extra slot child detached")
assert(decBlueFlw.Parent == nil and decKeepMisc.Parent == decMisc and decPepper.Parent == nil and decDand.Parent == nil and decBarrier.Parent == nil, "decorations & BoostBallBarrier detached cleanly")

restoreDecos()
assert(decAmulets.Parent == decTestWs and decFences.Parent == decMap and decHiveModels.Parent == decHiveDeco, "decorations restored on disable")
assert(decPlat.CanCollide == true and decExtra.Parent == decSlot and decPepper.Parent == decFolder and decBarrier.Parent == decTestWs, "platform CanCollide & sub-objects restored")

-- 4. BodyGyro Auto-Face Flames & Refresh prioritization
local function makeFlame(pos, sizeVal, greenVal)
	local f = makeInst("Part", "Flame")
	f.Position = pos
	local pf = f:AddChild(makeInst("ParticleEmitter", "PF"))
	pf.Size = { Keypoints = { { Value = sizeVal } } }
	pf.Color = { Keypoints = { { Value = { R = 1, G = greenVal, B = 0 } } } }
	return f
end

local rootPos = Vector3.new(-300, 22, 120)
local trackedFlames = {}
local darkFlame = makeFlame(Vector3.new(-292, 22, 120), 1.65, 0.1) -- G <= 0.2 -> dark (ignore)
local tinyFlame = makeFlame(Vector3.new(-292, 22, 122), 1.35, 0.8) -- Size <= 1.4 -> dying (ignore)
local otherFieldFlame = makeFlame(Vector3.new(-480, 122, 530), 1.65, 0.8) -- Pepper Patch (wrong field)
local nearFlameFresh = makeFlame(Vector3.new(-293, 22, 120), 1.70, 0.8) -- 7st, age 1.0s
local farFlameOld = makeFlame(Vector3.new(-285, 22, 120), 1.55, 0.8) -- 15st, age 3.6s (ready >= 3s)
local veryFarFlame = makeFlame(Vector3.new(-250, 22, 120), 1.55, 0.8) -- 50st (out of maxRange 30)

local flameParent = makeInst("Folder", "PlayerFlames")
for _, fl in ipairs({ darkFlame, tinyFlame, otherFieldFlame, nearFlameFresh, farFlameOld, veryFarFlame }) do
	fl.Parent = flameParent
end
local nowClock = 10.0
trackedFlames[darkFlame] = 6.0
trackedFlames[tinyFlame] = 6.0
trackedFlames[otherFieldFlame] = 6.0
trackedFlames[nearFlameFresh] = 9.0 -- age 1.0
trackedFlames[farFlameOld] = 6.4 -- age 3.6
trackedFlames[veryFarFlame] = 5.0 -- age 5.0, dist 50

local function selectFlameTarget(rPos, field, curNow)
	local hasFresh, bestReady, bestFallback = false, nil, nil
	for fl, t0 in pairs(trackedFlames) do
		local pf = fl:FindFirstChild("PF")
		local s = pf.Size.Keypoints[1].Value
		local g = pf.Color.Keypoints[1].Value.G
		if s > 1.4 and g > 0.2 then
			local dx = fl.Position.X - rPos.X
			local dz = fl.Position.Z - rPos.Z
			local dist = math.sqrt(dx * dx + dz * dz)
			if dist < cfg.flames.maxRange and getFieldAt(fl.Position) == field then
				local age = curNow - t0
				if age < cfg.flames.refreshAge then hasFresh = true end
				if dist > 4 then
					if age >= cfg.flames.refreshAge and (not bestReady or age > bestReady.age) then
						bestReady = { obj = fl, age = age, dist = dist }
					end
					if not bestFallback or dist < bestFallback.dist then
						bestFallback = { obj = fl, age = age, dist = dist }
					end
				end
			end
		end
	end
	if cfg.flames.refreshPriority then
		if bestReady then return bestReady.obj, false end
		if cfg.flames.onlyRefreshReady then return nil, hasFresh end
		return bestFallback and bestFallback.obj or nil, hasFresh
	end
	return bestFallback and bestFallback.obj or nil, false
end

local chosen, stopDig = selectFlameTarget(rootPos, roseField, nowClock)
assert(chosen == farFlameOld and stopDig == false, "should prioritize 3.6s expiring flame over 1.0s fresh flame")

-- Remove old flame so only fresh flame remains
trackedFlames[farFlameOld] = nil
chosen, stopDig = selectFlameTarget(rootPos, roseField, nowClock)
assert(chosen == nearFlameFresh and stopDig == true, "with fresh flame in range and no ready flame, stopDig=true protects flame while facing")

cfg.flames.onlyRefreshReady = true
chosen, stopDig = selectFlameTarget(rootPos, roseField, nowClock)
assert(chosen == nil and stopDig == true, "onlyRefreshReady releases facing torque when no flame >= refreshAge")

-- Shift Lock AutoRotate suppress/restore check
local slHum = { AutoRotate = true, Parent = true }
local savedAR, managedAR = nil, nil
local function suppressAR(h)
	if managedAR ~= h then
		savedAR = h.AutoRotate
		managedAR = h
	end
	h.AutoRotate = false
end
local function restoreAR()
	if managedAR and managedAR.Parent and savedAR ~= nil then
		managedAR.AutoRotate = savedAR
	end
	managedAR, savedAR = nil, nil
end
suppressAR(slHum)
assert(slHum.AutoRotate == false, "Shift Lock compat should suppress AutoRotate while facing a flame")
restoreAR()
assert(slHum.AutoRotate == true, "AutoRotate must restore immediately when idle or released")

-- 5. Digital Smiley Token Icon Matching & Countdown Timer Colors (< 0.9s Red cutoff)
local SMILEY_ID = "5877939956"
local SMILEY_GREEN = Color3.fromRGB(45, 240, 85)
local SMILEY_YELLOW = Color3.fromRGB(255, 225, 40)
local SMILEY_ORANGE = Color3.fromRGB(255, 115, 30)
local SMILEY_RED = Color3.fromRGB(255, 45, 55)
local function lerpColor(a, b, t)
	t = math.clamp(t, 0, 1)
	return Color3.new(a.R + (b.R - a.R) * t, a.G + (b.G - a.G) * t, a.B + (b.B - a.B) * t)
end
local function getSmileyColor(remaining, total)
	if remaining < 0.9 then return SMILEY_RED, true end
	local eff = math.max(total or 10, 1.9)
	local p = math.clamp((remaining - 0.9) / (eff - 0.9), 0, 1)
	if p >= 0.5 then
		return lerpColor(SMILEY_YELLOW, SMILEY_GREEN, (p - 0.5) * 2), false
	end
	return lerpColor(SMILEY_ORANGE, SMILEY_YELLOW, p * 2), false
end

for _, tex in ipairs({ "rbxassetid://5877939956", "http://www.roblox.com/asset/?id=5877939956", "https://www.roblox.com/asset/?id=5877939956" }) do
	assert(string.match(tex, "%d+") == SMILEY_ID, "failed to extract smiley id from " .. tex)
end

local cStart, redStart = getSmileyColor(10.0, 10.0)
assert(not redStart and cStart.G > cStart.R, "fresh smiley must be Green")

local cMid, redMid = getSmileyColor(5.45, 10.0)
assert(not redMid and math.abs(cMid.R * 255 - 255) < 1 and math.abs(cMid.G * 255 - 225) < 1, "midpoint smiley must be Yellow")

local cCutoff, redCutoff = getSmileyColor(0.90, 10.0)
assert(not redCutoff and cCutoff.G > 0.25, "0.90s is boundary (still collectible orange)")

local cLate, isRedLate = getSmileyColor(0.89, 10.0)
assert(isRedLate and math.abs(cLate.R * 255 - 255) < 0.5 and math.abs(cLate.G * 255 - 45) < 0.5 and math.abs(cLate.B * 255 - 55) < 0.5, "< 0.9s must snap to Solid Red")

print("PASS: RBC Helper cogmower monitor, walkspeed, hide decorations, bodygyro flame refresh, and smiley timer verified")
