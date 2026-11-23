-- Atlas+ RBC Helper
-- Standalone Bee Swarm Simulator utility using the Atlas+ GUI.

if _G.rbcHelperLoading then
	return
end
_G.rbcHelperLoading = true

local isTestHarness = _G.__RBC_HELPER_TEST__ == true

if not isTestHarness and (not getthreadidentity or getthreadidentity() < 8) then
	local starterGui = cloneref and cloneref(game:GetService("StarterGui")) or game:GetService("StarterGui")
	pcall(function()
		starterGui:SetCore("SendNotification", {
			Title = "Warning",
			Text = "Your executor is not supported.",
			Duration = 10,
		})
	end)
	_G.rbcHelperLoading = nil
	return
end

local function getService(serviceName)
	local service = game:GetService(serviceName)
	return cloneref and cloneref(service) or service
end

if not game:IsLoaded() then
	game.Loaded:Wait()
end

local Players = getService("Players")
local ReplicatedStorage = getService("ReplicatedStorage")
local RunService = getService("RunService")
local TweenService = getService("TweenService")
local UserInputService = getService("UserInputService")
local HttpService = getService("HttpService")
local StarterGui = getService("StarterGui")
local TextService = getService("TextService")

if not isTestHarness and game.PlaceId ~= 1537690962 then
	pcall(function()
		StarterGui:SetCore("SendNotification", {
			Title = "Warning",
			Text = "You're not in Bee Swarm Simulator.",
			Duration = 5,
		})
	end)
	_G.rbcHelperLoading = nil
	return
end

local localPlayer = Players.LocalPlayer or Players.PlayerAdded:Wait()

if not isTestHarness and localPlayer then
	local playerGui = localPlayer:FindFirstChildOfClass("PlayerGui") or localPlayer:WaitForChild("PlayerGui", 10)
	if playerGui then
		local lsg = playerGui:FindFirstChild("LoadingScreenGui")
		while lsg and lsg.Parent and lsg:FindFirstChild("LoadingMessage") and lsg.LoadingMessage.Visible do
			RunService.Heartbeat:Wait()
		end
	end
end

if _G.rbcHelper and type(_G.rbcHelper.Destroy) == "function" then
	pcall(_G.rbcHelper.Destroy)
end

local CONFIG_DIR = "rbc-helper"
local CONFIG_PATH = "rbc-helper/config.json"

local defaultCfg = {
	monitor = {
		enabled = true,
		notifyOnGoldCog = true,
	},
	movement = {
		walkspeedenabled = false,
		walkdynamic = false,
		walkspeed = 90,
		walkspeed2 = 1.5,
	},
	decorations = {
		hide = false,
	},
	flames = {
		enabled = false,
		refreshPriority = true,
		onlyRefreshReady = false,
		smartAutoDig = false,
		refreshAge = 3.0,
		maxRange = 30,
	},
	smiley = {
		enabled = true,
		beam = true,
		timer = true,
		fallbackDuration = 10,
	},
	misc = {
		mobiletoggle = false,
	},
}

local function deepCopy(source)
	local copy = {}
	for k, v in pairs(source) do
		copy[k] = type(v) == "table" and deepCopy(v) or v
	end
	return copy
end

local function mergeConfig(target, source)
	if type(source) ~= "table" then
		return
	end
	for k, v in pairs(target) do
		if type(v) == "table" and type(source[k]) == "table" then
			mergeConfig(v, source[k])
		elseif type(v) ~= "table" and type(source[k]) == type(v) then
			target[k] = source[k]
		end
	end
end

local cfg = deepCopy(defaultCfg)

local function loadConfig()
	if isfolder and isfile and readfile then
		pcall(function()
			if isfile(CONFIG_PATH) then
				local decoded = HttpService:JSONDecode(readfile(CONFIG_PATH))
				mergeConfig(cfg, decoded)
			end
		end)
	end
	cfg.movement.walkspeed = math.clamp(cfg.movement.walkspeed, 30, 90)
	cfg.movement.walkspeed2 = math.clamp(math.round(cfg.movement.walkspeed2 * 10) / 10, 1, 2)
	cfg.flames.refreshAge = math.clamp(math.round(cfg.flames.refreshAge * 10) / 10, 1.5, 4.5)
	cfg.flames.maxRange = math.clamp(math.floor(cfg.flames.maxRange), 15, 45)
	cfg.smiley.fallbackDuration = math.clamp(math.floor(cfg.smiley.fallbackDuration), 4, 20)
end

local function saveConfig()
	if not (writefile and HttpService) then
		return
	end
	pcall(function()
		if isfolder and makefolder and not isfolder(CONFIG_DIR) then
			makefolder(CONFIG_DIR)
		end
		writefile(CONFIG_PATH, HttpService:JSONEncode(cfg))
	end)
end

loadConfig()

-- Thread and connection lifecycle managers
local threads = { list = {}, closed = false }
local connections = { list = {} }

function threads:Add(id, callback)
	if self.closed then
		return nil
	end
	self:Cancel(id)
	local thread
	thread = coroutine.create(function()
		local ok, err = xpcall(callback, debug.traceback)
		if self.list[id] == thread then
			self.list[id] = nil
		end
		if not ok and err and not string.find(tostring(err), "thread cancelled", 1, true) then
			warn("[RBC Helper] " .. tostring(err))
		end
	end)
	self.list[id] = thread
	task.spawn(thread)
	return thread
end

function threads:Get(id)
	return self.list[id]
end

function threads:Cancel(id)
	local thread = self.list[id]
	if thread then
		self.list[id] = nil
		pcall(function()
			task.cancel(thread)
		end)
	end
end

function threads:CancelAll()
	self.closed = true
	for id in pairs(self.list) do
		self:Cancel(id)
	end
end

function connections:Add(id, conn)
	self:Cancel(id)
	self.list[id] = conn
	return conn
end

function connections:Get(id)
	return self.list[id]
end

function connections:Cancel(id)
	local conn = self.list[id]
	if conn then
		self.list[id] = nil
		pcall(function()
			conn:Disconnect()
		end)
	end
end

function connections:CancelAll()
	for id in pairs(self.list) do
		self:Cancel(id)
	end
end

-- Secure call helper (matches Atlas+ identity handling for ClientStatCache & LocalCollect)
local secureCall
do
	local function callWithIdentity(fn, ...)
		if setthreadidentity and getthreadidentity then
			local prev = getthreadidentity()
			setthreadidentity(5)
			local packed = table.pack(pcall(fn, ...))
			setthreadidentity(prev)
			if not packed[1] then
				error(packed[2], 0)
			end
			return table.unpack(packed, 2, packed.n)
		end
		return fn(...)
	end

	if newcclosure then
		secureCall = newcclosure(callWithIdentity)
	else
		secureCall = callWithIdentity
	end
end

local gameApi = {}
do
	local statMod = ReplicatedStorage:FindFirstChild("ClientStatCache")
	if statMod then
		local ok, mod = pcall(require, statMod)
		if ok and type(mod) == "table" and type(mod.Get) == "function" then
			gameApi.ClientStatCache = mod
		end
	end

	local collectors = ReplicatedStorage:FindFirstChild("Collectors")
	local localCollectMod = collectors and collectors:FindFirstChild("LocalCollect")
	if localCollectMod then
		local ok, mod = pcall(require, localCollectMod)
		if ok and type(mod) == "table" and type(mod.Run) == "function" then
			gameApi.LocalCollect = mod.Run
		end
	end

	local dupedAnimMod = ReplicatedStorage:FindFirstChild("DupedTokensAnimator")
	if dupedAnimMod then
		local ok, mod = pcall(require, dupedAnimMod)
		if ok and type(mod) == "table" then
			gameApi.DupedTokensAnimator = mod
		end
	end
end

function gameApi:Cache(...)
	if not self.ClientStatCache then
		return nil
	end
	local args = table.pack(...)
	local ok, result = pcall(function()
		return secureCall(self.ClientStatCache.Get, nil, table.unpack(args, 1, args.n))
	end)
	return ok and result or nil
end

local function getHumanoid()
	local char = localPlayer and localPlayer.Character
	return char and char:FindFirstChildOfClass("Humanoid") or nil
end

local function getRootPart()
	local char = localPlayer and localPlayer.Character
	return char and char:FindFirstChild("HumanoidRootPart") or nil
end

local function getServerTime()
	local serverTime = workspace:FindFirstChild("ServerTime")
	if serverTime then
		local okVal, val = pcall(function()
			return serverTime.Value
		end)
		if okVal and type(val) == "number" then
			return val
		end
	end
	local okNow, nowVal = pcall(function()
		return workspace:GetServerTimeNow()
	end)
	if okNow and type(nowVal) == "number" then
		return nowVal
	end
	return os.time()
end

-- Field resolver
local fieldRaycastParams, fieldRaycastFolder
local function getFieldAt(point)
	if typeof(point) ~= "Vector3" then
		return nil
	end
	local zones = workspace:FindFirstChild("FlowerZones")
	if not zones then
		return nil
	end
	if not fieldRaycastParams or fieldRaycastFolder ~= zones then
		local params = RaycastParams.new()
		params.FilterDescendantsInstances = { zones }
		params.FilterType = Enum.RaycastFilterType.Include
		fieldRaycastParams = params
		fieldRaycastFolder = zones
	end
	local ok, hit = pcall(function()
		return workspace:Raycast(point + Vector3.new(0, 8, 0), Vector3.new(0, -128, 0), fieldRaycastParams)
	end)
	if ok and hit and hit.Instance and hit.Instance.Parent == zones then
		return hit.Instance
	end
	for _, field in ipairs(zones:GetChildren()) do
		if field:IsA("BasePart") and field.CFrame then
			local offset = field.CFrame:PointToObjectSpace(point)
			if math.abs(offset.X) <= field.Size.X / 2 + 2 and math.abs(offset.Z) <= field.Size.Z / 2 + 2 then
				return field
			end
		end
	end
	return nil
end

local function getInstancePosition(inst)
	if not inst then
		return nil
	end
	local okPos, pos = pcall(function()
		return inst.Position
	end)
	if okPos and typeof(pos) == "Vector3" then
		return pos
	end
	if inst:IsA("Model") then
		local okPrim, prim = pcall(function()
			return inst.PrimaryPart
		end)
		if okPrim and prim then
			local okP, pPos = pcall(function()
				return prim.Position
			end)
			if okP and typeof(pPos) == "Vector3" then
				return pPos
			end
		end
		local okPivot, pivot = pcall(function()
			return inst:GetPivot()
		end)
		if okPivot and pivot then
			return pivot.Position
		end
	end
	return nil
end

-- Atlas+ WalkSpeed controller (capped at 90)
local walkSpeedController = {
	lastAppliedSpeed = nil,
	originalSpeed = nil,
	trackedHumanoid = nil,
}

function walkSpeedController:Step()
	if not cfg.movement.walkspeedenabled then
		return
	end
	local h = getHumanoid()
	if not h or not h.Parent or h.Health <= 0 then
		return
	end
	if self.trackedHumanoid ~= h then
		self.trackedHumanoid = h
		self.originalSpeed = h.WalkSpeed
		self.lastAppliedSpeed = nil
	end

	local maxCap = math.clamp(tonumber(cfg.movement.walkspeed) or 90, 30, 90)
	local targetSpeed = nil

	if not cfg.movement.walkdynamic then
		targetSpeed = maxCap
	else
		local modifiers = gameApi:Cache({ "ModifierCaches", "Value" })
		if type(modifiers) == "table" and type(modifiers.PlayerMovespeed) == "table" and type(modifiers.PlayerMovespeed._) == "number" then
			targetSpeed = math.min(maxCap, modifiers.PlayerMovespeed._ * (tonumber(cfg.movement.walkspeed2) or 1.5))
		end
	end

	if not targetSpeed then
		return
	end

	local currentSpeed = h.WalkSpeed
	local wasSetByUs = self.lastAppliedSpeed ~= nil and math.abs(currentSpeed - self.lastAppliedSpeed) < 0.05
	if currentSpeed < targetSpeed or (wasSetByUs and currentSpeed > targetSpeed) then
		h.WalkSpeed = targetSpeed
		self.lastAppliedSpeed = targetSpeed
	end
end

function walkSpeedController:Restore()
	local h = self.trackedHumanoid or getHumanoid()
	if h and h.Parent and self.lastAppliedSpeed ~= nil then
		local restoreTo = self.originalSpeed
		local modifiers = gameApi:Cache({ "ModifierCaches", "Value" })
		if type(modifiers) == "table" and type(modifiers.PlayerMovespeed) == "table" and type(modifiers.PlayerMovespeed._) == "number" then
			restoreTo = modifiers.PlayerMovespeed._
		end
		if type(restoreTo) == "number" and math.abs(h.WalkSpeed - self.lastAppliedSpeed) < 0.05 then
			h.WalkSpeed = restoreTo
		end
	end
	self.lastAppliedSpeed = nil
	self.originalSpeed = nil
	self.trackedHumanoid = nil
end

function walkSpeedController:SetEnabled(enabled)
	threads:Cancel("walkspeed")
	if not enabled then
		self:Restore()
		return
	end
	self:Step()
	threads:Add("walkspeed", function()
		while cfg.movement.walkspeedenabled and not threads.closed do
			self:Step()
			task.wait(0.1)
		end
	end)
end

-- Feature A: Golden Cogmower Scanner
local function resolveMobPosition(mob)
	if not mob then
		return nil
	end
	local body = mob:FindFirstChild("Body")
	if body then
		local pos = getInstancePosition(body)
		if pos then
			return pos
		end
	end
	local firstPart = mob:FindFirstChildOfClass("BasePart")
	if firstPart then
		local pos = getInstancePosition(firstPart)
		if pos then
			return pos
		end
	end
	return getInstancePosition(mob)
end

local goldCogMonitor = {}

function goldCogMonitor:Scan()
	local found = {}
	local seen = {}

	local function checkContainer(container)
		if not container then
			return
		end
		for _, child in ipairs(container:GetChildren()) do
			if child.Name == "Gold Cogmower" and not seen[child] then
				seen[child] = true
				local pos = resolveMobPosition(child)
				local field = pos and getFieldAt(pos) or nil
				table.insert(found, {
					instance = child,
					pos = pos,
					fieldName = field and field.Name or "Unknown Field",
				})
			end
		end
	end

	checkContainer(workspace)
	checkContainer(workspace:FindFirstChild("Monsters"))
	return found
end

-- Feature C: Reversible Hide Decorations (exact targets from fullscript.txt)
local WORKSPACE_DECO_NAMES = {
	"Amulets",
	"Shell Amulets",
	"Stickbug Amulets",
	"BallArrowFolder",
	"BoostBalls",
	"Campsite",
	"ClassicMinigame",
	"Cubs",
	"Faces",
	"FieldDecos",
	"Frame",
	"Frogs",
	"Goo",
	"Paths",
	"Invisible Walls",
	"Leaderboards",
	"Territories",
	"TheGamesEvent",
	"TheGames_WideBanners",
	"Bee Bear Hive",
	"Noob Bear",
	"OnettNPC",
	"Pro Bear",
	"Top Bear",
	"BuckoAtHQ",
	"RileyAtHQ",
	"Honey",
	"Lion",
}

local HIVE_DECO_NAMES = {
	"HiveModels",
	"StickerCanvases",
}

local DECORATION_CHILD_NAMES = {
	"35ZoneCave",
	"BubbleWandChimney",
	"TreatBooth",
	"Coconut Field",
	"Pepper Patch",
	"Pine Tree",
	"SpiderCave",
	"Petal Shop",
	"JumpGames",
	"PEggMaze",
}

local decorationsController = {
	detached = {},
	detachedSet = {},
	savedPlatforms = {},
	hidden = false,
}

function decorationsController:Detach(inst)
	if not inst or self.detachedSet[inst] then
		return
	end
	local okParent, origParent = pcall(function()
		return inst.Parent
	end)
	if not okParent or not origParent then
		return
	end
	self.detachedSet[inst] = true
	table.insert(self.detached, { inst = inst, parent = origParent })
	pcall(function()
		inst.Parent = nil
	end)
end

function decorationsController:Hide()
	for _, name in ipairs(WORKSPACE_DECO_NAMES) do
		self:Detach(workspace:FindFirstChild(name))
	end

	local map = workspace:FindFirstChild("Map")
	if map then
		self:Detach(map:FindFirstChild("Fences"))
	end

	local hiveDeco = workspace:FindFirstChild("HiveDeco")
	if hiveDeco then
		for _, name in ipairs(HIVE_DECO_NAMES) do
			self:Detach(hiveDeco:FindFirstChild(name))
		end
	end

	local hivePlatforms = workspace:FindFirstChild("HivePlatforms")
	if hivePlatforms then
		for _, slot in ipairs(hivePlatforms:GetChildren()) do
			for _, item in ipairs(slot:GetChildren()) do
				if item.Name == "Platform" then
					if self.savedPlatforms[item] == nil then
						local okCol, origCol = pcall(function()
							return item.CanCollide
						end)
						if okCol then
							self.savedPlatforms[item] = origCol
						end
					end
					pcall(function()
						item.CanCollide = false
					end)
				elseif item.Name ~= "Hive" and item.Name ~= "PlayerRef" then
					self:Detach(item)
				end
			end
		end
	end

	local decorations = workspace:FindFirstChild("Decorations")
	if decorations then
		local misc = decorations:FindFirstChild("Misc")
		if misc then
			for _, child in ipairs(misc:GetChildren()) do
				local n = child.Name
				if string.find(n, "Blue Flower") or n == "Bamboo" or n == "Bush" or n == "Mushroom" then
					self:Detach(child)
				end
			end
		end

		for _, name in ipairs(DECORATION_CHILD_NAMES) do
			self:Detach(decorations:FindFirstChild(name))
		end

		for _, child in ipairs(decorations:GetChildren()) do
			local n = child.Name
			if string.find(n, "Dandelion") or string.find(n, "Clover") or string.find(n, "Rose") or string.find(n, "Sign") or string.find(n, "Glider") or n == "ShopWord" then
				self:Detach(child)
			end
		end
	end

	for _, child in ipairs(workspace:GetChildren()) do
		local okMatch, isBarrier = pcall(function()
			return child.ClassName == "Part" and child.CollisionGroup == "BoostBallBarrier"
		end)
		if okMatch and isBarrier then
			self:Detach(child)
		end
	end

	self.hidden = true
end

function decorationsController:Restore()
	for i = #self.detached, 1, -1 do
		local entry = self.detached[i]
		if entry.inst and entry.parent then
			pcall(function()
				entry.inst.Parent = entry.parent
			end)
		end
	end
	table.clear(self.detached)
	table.clear(self.detachedSet)

	for plat, origCol in pairs(self.savedPlatforms) do
		pcall(function()
			plat.CanCollide = origCol
		end)
	end
	table.clear(self.savedPlatforms)
	self.hidden = false
end

function decorationsController:SetEnabled(enabled)
	if enabled then
		self:Hide()
	else
		self:Restore()
	end
end

-- Feature D: Standalone BodyGyro Auto-Face Flames & Refresh
local flameController = {
	tracked = {},
	gyro = nil,
	stopDig = false,
	statusLabel = nil,
	lastStatusText = nil,
}

local function inspectFlame(flameObj, recordedSpawnTime, now)
	if not flameObj or not flameObj.Parent then
		return nil
	end
	local pos = getInstancePosition(flameObj)
	if not pos then
		return nil
	end
	local okValid, sizeVal = pcall(function()
		local pf = flameObj:FindFirstChild("PF")
		if not pf then
			return nil
		end
		local s = pf.Size.Keypoints[1].Value
		local g = pf.Color.Keypoints[1].Value.G
		if s <= 1.4 or g <= 0.2 then
			return nil
		end
		return s
	end)
	if not okValid or not sizeVal then
		return nil
	end

	local age
	if type(recordedSpawnTime) == "number" then
		age = math.max(0, now - recordedSpawnTime)
	else
		local estRem = 1 + math.clamp((sizeVal - 1.4) / 0.35, 0, 1) * 5
		age = math.max(0, 6 - estRem)
	end
	return pos, age
end

function flameController:SetStatusText(text)
	if self.lastStatusText == text then
		return
	end
	self.lastStatusText = text
	if self.statusLabel then
		self.statusLabel.Text = text
	end
end

function flameController:EnsureGyro(rootPart)
	if self.gyro and self.gyro.Parent ~= rootPart then
		pcall(function()
			self.gyro:Destroy()
		end)
		self.gyro = nil
	end
	if not self.gyro and rootPart then
		local okGyro, created = pcall(function()
			local g = Instance.new("BodyGyro")
			g.Name = "RbcFlameGyro"
			g.P = 12000
			g.D = 350
			g.MaxTorque = Vector3.new(0, 0, 0)
			g.Parent = rootPart
			return g
		end)
		if okGyro then
			self.gyro = created
		end
	end
	return self.gyro
end

function flameController:ReleaseGyro()
	if self.gyro then
		pcall(function()
			self.gyro.MaxTorque = Vector3.new(0, 0, 0)
			self.gyro:Destroy()
		end)
		self.gyro = nil
	end
end

function flameController:ZeroTorque()
	if self.gyro then
		pcall(function()
			self.gyro.MaxTorque = Vector3.new(0, 0, 0)
		end)
	end
end

function flameController:BindFolder(folder)
	connections:Cancel("flamesAdded")
	connections:Cancel("flamesRemoved")
	if not folder then
		table.clear(self.tracked)
		return
	end
	connections:Add("flamesAdded", folder.ChildAdded:Connect(function(child)
		self.tracked[child] = os.clock()
	end))
	connections:Add("flamesRemoved", folder.ChildRemoved:Connect(function(child)
		self.tracked[child] = nil
	end))
	for _, child in ipairs(folder:GetChildren()) do
		if self.tracked[child] == nil then
			self.tracked[child] = false
		end
	end
end

function flameController:SelectTarget(rootPos, field, now)
	if not rootPos or not field then
		return nil, false, "idle"
	end
	local maxRange = math.clamp(tonumber(cfg.flames.maxRange) or 30, 15, 45)
	local refreshAge = math.clamp(tonumber(cfg.flames.refreshAge) or 3.0, 1.5, 4.5)
	local hasFreshInRange = false
	local bestReady = nil
	local bestFallback = nil
	local stale = nil

	for flameObj, recordedTime in pairs(self.tracked) do
		if not flameObj or not flameObj.Parent then
			stale = stale or {}
			table.insert(stale, flameObj)
		else
			local pos, age = inspectFlame(flameObj, recordedTime, now)
			if pos then
				local dx = pos.X - rootPos.X
				local dz = pos.Z - rootPos.Z
				local dist = math.sqrt(dx * dx + dz * dz)
				if dist < maxRange and getFieldAt(pos) == field then
					if age < refreshAge then
						hasFreshInRange = true
					end
					if dist > 4 then
						if age >= refreshAge then
							if not bestReady or age > bestReady.age + 0.15 or (math.abs(age - bestReady.age) <= 0.15 and dist < bestReady.dist) then
								bestReady = { obj = flameObj, pos = pos, age = age, dist = dist }
							end
						end
						if not bestFallback or dist < bestFallback.dist then
							bestFallback = { obj = flameObj, pos = pos, age = age, dist = dist }
						end
					end
				end
			end
		end
	end

	if stale then
		for _, obj in ipairs(stale) do
			self.tracked[obj] = nil
		end
	end

	if cfg.flames.refreshPriority then
		if bestReady then
			return bestReady, false, "refresh"
		elseif cfg.flames.onlyRefreshReady then
			return nil, hasFreshInRange, "waiting"
		else
			return bestFallback, hasFreshInRange, bestFallback and "face" or "idle"
		end
	end
	return bestFallback, false, bestFallback and "face" or "idle"
end

function flameController:Step(now)
	if not cfg.flames.enabled then
		self:ReleaseGyro()
		self.stopDig = false
		self:SetStatusText("Target: Disabled")
		return
	end

	local rootPart = getRootPart()
	local hum = getHumanoid()
	if not rootPart or not hum or not hum.Parent or hum.Health <= 0 then
		self:ZeroTorque()
		self.stopDig = false
		self:SetStatusText("Target: Waiting for character")
		return
	end

	local rootPos = getInstancePosition(rootPart)
	local field = rootPos and getFieldAt(rootPos) or nil
	if not field then
		self:ZeroTorque()
		self.stopDig = false
		self:SetStatusText("Target: Not in a field")
		return
	end

	local currentClock = now or os.clock()
	local targetEntry, stopDig, modeLabel = self:SelectTarget(rootPos, field, currentClock)
	self.stopDig = stopDig

	if not targetEntry then
		self:ZeroTorque()
		self:SetStatusText(modeLabel == "waiting" and "Target: Holding for refresh" or ("Target: Idle in " .. field.Name))
		return
	end

	local dx = targetEntry.pos.X - rootPos.X
	local dz = targetEntry.pos.Z - rootPos.Z
	if dx * dx + dz * dz <= 0.01 then
		self:ZeroTorque()
		self:SetStatusText("Target: On flame")
		return
	end

	local gyro = self:EnsureGyro(rootPart)
	if gyro then
		local flatTarget = Vector3.new(targetEntry.pos.X, rootPos.Y, targetEntry.pos.Z)
		pcall(function()
			gyro.MaxTorque = Vector3.new(0, math.huge, 0)
			gyro.CFrame = CFrame.lookAt and CFrame.lookAt(rootPos, flatTarget) or CFrame.new(rootPos, flatTarget)
		end)
	end

	self:SetStatusText(string.format("Target: %s (%.1fs, %.0fst)", modeLabel == "refresh" and "Refreshing" or "Facing", targetEntry.age, targetEntry.dist))
end

function flameController:SetEnabled(enabled)
	connections:Cancel("flameFace")
	if not enabled then
		self:ReleaseGyro()
		self.stopDig = false
		self:SetStatusText("Target: Disabled")
		return
	end
	local pf = workspace:FindFirstChild("PlayerFlames")
	if pf and not connections:Get("flamesAdded") then
		self:BindFolder(pf)
	elseif pf then
		for _, child in ipairs(pf:GetChildren()) do
			if self.tracked[child] == nil then
				self.tracked[child] = false
			end
		end
	end
	self:Step(os.clock())
	connections:Add("flameFace", RunService.Heartbeat:Connect(function()
		self:Step(os.clock())
	end))
end

local function syncSmartAutoDig()
	threads:Cancel("smartAutoDig")
	if not cfg.flames.smartAutoDig then
		return
	end
	threads:Add("smartAutoDig", function()
		while cfg.flames.smartAutoDig and not threads.closed do
			if not (cfg.flames.enabled and flameController.stopDig) and gameApi.LocalCollect then
				pcall(secureCall, gameApi.LocalCollect)
			end
			task.wait(0.1)
		end
	end)
end

-- Feature E: Digital Bee Smiley Duped Token 3D Highlight + Live Countdown Timer
local SMILEY_ICON_ID = "5877939956"
local SMILEY_RED_CUTOFF = 0.9
local SMILEY_FOLDER_NAME = "RbcHelperSmileyHighlights"

local SMILEY_GREEN = Color3.fromRGB(45, 240, 85)
local SMILEY_YELLOW = Color3.fromRGB(255, 225, 40)
local SMILEY_ORANGE = Color3.fromRGB(255, 115, 30)
local SMILEY_RED = Color3.fromRGB(255, 45, 55)

local function lerpColor(a, b, t)
	t = math.clamp(t, 0, 1)
	return Color3.new(a.R + (b.R - a.R) * t, a.G + (b.G - a.G) * t, a.B + (b.B - a.B) * t)
end

local function getSmileyTimerColor(remaining, totalDuration)
	if remaining < SMILEY_RED_CUTOFF then
		return SMILEY_RED, true
	end
	local effectiveTotal = math.max(totalDuration or 10, SMILEY_RED_CUTOFF + 1.0)
	local progress = math.clamp((remaining - SMILEY_RED_CUTOFF) / (effectiveTotal - SMILEY_RED_CUTOFF), 0, 1)
	if progress >= 0.5 then
		return lerpColor(SMILEY_YELLOW, SMILEY_GREEN, (progress - 0.5) * 2), false
	end
	return lerpColor(SMILEY_ORANGE, SMILEY_YELLOW, progress * 2), false
end

local function extractTokenIconId(token)
	if not token then
		return nil
	end
	local front = token:FindFirstChild("FrontDecal")
	if front and front.Texture then
		local id = string.match(tostring(front.Texture), "%d+")
		if id then
			return id
		end
	end
	local back = token:FindFirstChild("BackDecal")
	if back and back.Texture then
		local id = string.match(tostring(back.Texture), "%d+")
		if id then
			return id
		end
	end
	for _, child in ipairs(token:GetChildren()) do
		if child:IsA("Decal") and child.Texture then
			local id = string.match(tostring(child.Texture), "%d+")
			if id then
				return id
			end
		end
	end
	return nil
end

local smileyHighlighter = {
	active = {},
	pending = {},
	watchers = {},
	tokenTimestamps = {},
	spawnMetaQueue = {},
	rootFolder = nil,
}

function smileyHighlighter:InstallDupedSpawnTap()
	_G.__rbcHelperDupedSpawnSink = function(...)
		local first, second = ...
		local tokenData = (type(first) == "table" and first.Icon ~= nil and first)
			or (type(second) == "table" and second.Icon ~= nil and second)
		if type(tokenData) ~= "table" then
			return
		end
		if string.match(tostring(tokenData.Icon or ""), "%d+") ~= SMILEY_ICON_ID then
			return
		end
		local endTime = tonumber(tokenData.EndTime)
		local rem = endTime and (endTime - getServerTime()) or nil
		if rem and rem > 0.2 and rem < 120 then
			local now = os.clock()
			for i = #self.spawnMetaQueue, 1, -1 do
				if now - self.spawnMetaQueue[i].recordedAt > 3.0 then
					table.remove(self.spawnMetaQueue, i)
				end
			end
			table.insert(self.spawnMetaQueue, {
				pos = tokenData.Pos,
				duration = rem,
				endClock = now + rem,
				recordedAt = now,
			})
		end
	end

	local anim = gameApi.DupedTokensAnimator
	if anim and type(anim.Spawn) == "function" and not _G.__rbcHelperDupedSpawnHooked then
		if type(hookfunction) == "function" then
			local okHook = pcall(function()
				local origSpawn
				origSpawn = hookfunction(anim.Spawn, function(...)
					if _G.__rbcHelperDupedSpawnSink then
						pcall(_G.__rbcHelperDupedSpawnSink, ...)
					end
					return origSpawn(...)
				end)
			end)
			if okHook then
				_G.__rbcHelperDupedSpawnHooked = true
			end
		elseif isTestHarness then
			local origSpawn = anim.Spawn
			anim.Spawn = function(...)
				if _G.__rbcHelperDupedSpawnSink then
					pcall(_G.__rbcHelperDupedSpawnSink, ...)
				end
				return origSpawn(...)
			end
			_G.__rbcHelperDupedSpawnHooked = true
		end
	end
end

function smileyHighlighter:ConsumeSpawnMeta(pos, now)
	for i = #self.spawnMetaQueue, 1, -1 do
		if now - self.spawnMetaQueue[i].recordedAt > 3.0 then
			table.remove(self.spawnMetaQueue, i)
		end
	end
	if #self.spawnMetaQueue == 0 then
		return nil
	end
	local bestIdx = nil
	if typeof(pos) == "Vector3" then
		local bestDist = math.huge
		for i, meta in ipairs(self.spawnMetaQueue) do
			if typeof(meta.pos) == "Vector3" then
				local dx = meta.pos.X - pos.X
				local dz = meta.pos.Z - pos.Z
				local d = math.sqrt(dx * dx + dz * dz)
				if d <= 6 and d < bestDist then
					bestDist = d
					bestIdx = i
				end
			end
		end
	end
	if not bestIdx then
		for i, meta in ipairs(self.spawnMetaQueue) do
			if now - meta.recordedAt <= 1.5 then
				bestIdx = i
				break
			end
		end
	end
	if bestIdx then
		return table.remove(self.spawnMetaQueue, bestIdx)
	end
	return nil
end

function smileyHighlighter:GetRootFolder()
	if self.rootFolder and self.rootFolder.Parent then
		return self.rootFolder
	end
	local old = workspace:FindFirstChild(SMILEY_FOLDER_NAME)
	if old then
		pcall(function()
			old:Destroy()
		end)
	end
	local folder = Instance.new("Folder")
	folder.Name = SMILEY_FOLDER_NAME
	folder.Parent = workspace
	self.rootFolder = folder
	return folder
end

function smileyHighlighter:SyncTickConnection()
	if next(self.active) ~= nil then
		if not connections:Get("smileyTick") then
			local sig = RunService.RenderStepped or RunService.Heartbeat
			if sig then
				connections:Add("smileyTick", sig:Connect(function()
					self:UpdateAll(os.clock())
				end))
			end
		end
	else
		connections:Cancel("smileyTick")
	end
end

function smileyHighlighter:UpdateEntry(entry, now)
	if not entry then
		return
	end
	local pos = getInstancePosition(entry.token)
	if pos and entry.beamPart then
		pcall(function()
			entry.beamPart.CFrame = CFrame.new(pos.X, pos.Y - 4.5, pos.Z)
		end)
	end

	local remaining = math.max(0, entry.endClock - (now or os.clock()))
	local color, isRed = getSmileyTimerColor(remaining, entry.totalDuration)
	local enabled = cfg.smiley.enabled == true
	local showBeam = enabled and cfg.smiley.beam == true
	local showTimer = enabled and cfg.smiley.timer == true

	if entry.highlight then
		pcall(function()
			entry.highlight.FillColor = color
			entry.highlight.Enabled = enabled
		end)
	end
	if entry.selectionBox then
		pcall(function()
			entry.selectionBox.Color3 = color
			entry.selectionBox.SurfaceColor3 = color
			entry.selectionBox.Visible = enabled
		end)
	end
	if entry.beamPart then
		pcall(function()
			entry.beamPart.Color = color
			entry.beamPart.Transparency = showBeam and 0.45 or 1
		end)
	end
	if entry.beamAdornment then
		pcall(function()
			entry.beamAdornment.Color3 = color
			entry.beamAdornment.Visible = showBeam
		end)
	end
	if entry.billboard then
		pcall(function()
			entry.billboard.Enabled = showTimer
		end)
	end
	if entry.stroke then
		pcall(function()
			entry.stroke.Color = color
		end)
	end
	if entry.titleLabel then
		pcall(function()
			entry.titleLabel.Text = isRed and "TOO LATE" or "SMILEY DUPED"
			entry.titleLabel.TextColor3 = color
		end)
	end
	if entry.timerLabel then
		pcall(function()
			entry.timerLabel.Text = string.format("%.1fs", remaining)
			entry.timerLabel.TextColor3 = color
		end)
	end
end

function smileyHighlighter:Apply(token, spawnClock)
	if not token or not token.Parent or not cfg.smiley.enabled then
		return
	end
	local now = os.clock()
	if self.active[token] then
		self:UpdateEntry(self.active[token], now)
		return
	end

	local pos = getInstancePosition(token)
	local meta = self:ConsumeSpawnMeta(pos, now)
	local totalDuration, endClock, isFallback
	if meta then
		totalDuration = meta.duration
		endClock = meta.endClock
		isFallback = false
	else
		totalDuration = math.clamp(tonumber(cfg.smiley.fallbackDuration) or 10, 4, 20)
		endClock = spawnClock + totalDuration
		isFallback = true
	end

	local entryFolder = Instance.new("Folder")
	entryFolder.Name = "SmileyToken"
	entryFolder.Parent = self:GetRootFolder()

	local initialRem = math.max(0, endClock - now)
	local initColor, initRed = getSmileyTimerColor(initialRem, totalDuration)

	local highlight
	local okHl, createdHl = pcall(function()
		local hl = Instance.new("Highlight")
		hl.Name = "SmileyHighlight"
		hl.Adornee = token
		hl.FillColor = initColor
		hl.FillTransparency = 0.25
		hl.OutlineColor = Color3.fromRGB(255, 255, 255)
		hl.OutlineTransparency = 0
		hl.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
		hl.Enabled = cfg.smiley.enabled
		hl.Parent = entryFolder
		return hl
	end)
	if okHl then
		highlight = createdHl
	end

	local selectionBox
	local okBox, createdBox = pcall(function()
		local box = Instance.new("SelectionBox")
		box.Name = "SmileyBox"
		box.Adornee = token
		box.Color3 = initColor
		box.SurfaceColor3 = initColor
		box.SurfaceTransparency = 0.65
		box.LineThickness = 0.08
		box.Visible = cfg.smiley.enabled
		box.Parent = entryFolder
		return box
	end)
	if okBox then
		selectionBox = createdBox
	end

	local beamPart, beamAdornment
	local okBeam, createdBeam, createdAdorn = pcall(function()
		local part = Instance.new("Part")
		part.Name = "SmileyDropBeam"
		part.Anchored = true
		part.CanCollide = false
		part.CanTouch = false
		part.CanQuery = false
		part.CastShadow = false
		part.Material = Enum.Material.Neon
		part.Color = initColor
		part.Size = Vector3.new(0.45, 13, 0.45)
		part.Transparency = (cfg.smiley.enabled and cfg.smiley.beam) and 0.45 or 1
		if pos then
			part.CFrame = CFrame.new(pos.X, pos.Y - 4.5, pos.Z)
		end
		part.Parent = entryFolder

		local adorn = Instance.new("BoxHandleAdornment")
		adorn.Name = "SmileyDropBeamXRay"
		adorn.Adornee = part
		adorn.AlwaysOnTop = true
		adorn.ZIndex = 5
		adorn.Color3 = initColor
		adorn.Size = part.Size
		adorn.Transparency = 0.65
		adorn.Visible = cfg.smiley.enabled and cfg.smiley.beam
		adorn.Parent = part

		return part, adorn
	end)
	if okBeam then
		beamPart = createdBeam
		beamAdornment = createdAdorn
	end

	local billboard, stroke, titleLabel, timerLabel
	local okGui, cGui, cStroke, cTitle, cTimer = pcall(function()
		local gui = Instance.new("BillboardGui")
		gui.Name = "SmileyTimerGui"
		gui.Adornee = token
		gui.AlwaysOnTop = true
		gui.Size = UDim2.new(0, 116, 0, 42)
		gui.StudsOffsetWorldSpace = Vector3.new(0, 3.6, 0)
		gui.Enabled = cfg.smiley.enabled and cfg.smiley.timer
		gui.Parent = entryFolder

		local frame = Instance.new("Frame")
		frame.Name = "TagFrame"
		frame.BackgroundColor3 = Color3.fromRGB(16, 17, 20)
		frame.BackgroundTransparency = 0.12
		frame.BorderSizePixel = 0
		frame.Size = UDim2.new(1, 0, 1, 0)
		frame.Parent = gui

		local corner = Instance.new("UICorner")
		corner.CornerRadius = UDim.new(0, 5)
		corner.Parent = frame

		local uiStroke = Instance.new("UIStroke")
		uiStroke.Thickness = 2
		uiStroke.Color = initColor
		uiStroke.Parent = frame

		local tLbl = Instance.new("TextLabel")
		tLbl.Name = "TitleLabel"
		tLbl.BackgroundTransparency = 1
		tLbl.Font = Enum.Font.GothamBold
		tLbl.Position = UDim2.new(0, 4, 0, 2)
		tLbl.Size = UDim2.new(1, -8, 0, 14)
		tLbl.Text = initRed and "TOO LATE" or "SMILEY DUPED"
		tLbl.TextColor3 = initColor
		tLbl.TextSize = 10
		tLbl.Parent = frame

		local timeLbl = Instance.new("TextLabel")
		timeLbl.Name = "TimerLabel"
		timeLbl.BackgroundTransparency = 1
		timeLbl.Font = Enum.Font.GothamBold
		timeLbl.Position = UDim2.new(0, 4, 0, 16)
		timeLbl.Size = UDim2.new(1, -8, 0, 22)
		timeLbl.Text = string.format("%.1fs", initialRem)
		timeLbl.TextColor3 = initColor
		timeLbl.TextSize = 16
		timeLbl.Parent = frame

		return gui, uiStroke, tLbl, timeLbl
	end)
	if okGui then
		billboard = cGui
		stroke = cStroke
		titleLabel = cTitle
		timerLabel = cTimer
	end

	self.active[token] = {
		token = token,
		spawnClock = spawnClock,
		totalDuration = totalDuration,
		endClock = endClock,
		isFallback = isFallback,
		folder = entryFolder,
		highlight = highlight,
		selectionBox = selectionBox,
		beamPart = beamPart,
		beamAdornment = beamAdornment,
		billboard = billboard,
		stroke = stroke,
		titleLabel = titleLabel,
		timerLabel = timerLabel,
	}

	self:SyncTickConnection()
end

function smileyHighlighter:Remove(token)
	if not token then
		return
	end
	local entry = self.active[token]
	if entry then
		self.active[token] = nil
		if entry.folder then
			pcall(function()
				entry.folder:Destroy()
			end)
		end
	end
	self:SyncTickConnection()
end

function smileyHighlighter:UnwatchToken(token)
	local conns = self.watchers[token]
	if conns then
		self.watchers[token] = nil
		for _, conn in ipairs(conns) do
			pcall(function()
				conn:Disconnect()
			end)
		end
	end
	self.pending[token] = nil
	self.tokenTimestamps[token] = nil
	self:Remove(token)
end

function smileyHighlighter:Classify(token, spawnClock)
	if not token or not token.Parent then
		self:Remove(token)
		return true
	end
	local iconId = extractTokenIconId(token)
	if not iconId then
		return false
	end
	if iconId == SMILEY_ICON_ID and cfg.smiley.enabled then
		self:Apply(token, spawnClock)
	else
		self:Remove(token)
	end
	return true
end

function smileyHighlighter:WatchToken(token)
	if not token or self.watchers[token] then
		return
	end
	local spawnClock = self.tokenTimestamps[token]
	if not spawnClock then
		spawnClock = os.clock()
		self.tokenTimestamps[token] = spawnClock
	end

	local conns = {}
	self.watchers[token] = conns

	local function bindDecal(obj)
		if (obj:IsA("Decal") or obj:IsA("Texture")) and obj.GetPropertyChangedSignal then
			table.insert(conns, obj:GetPropertyChangedSignal("Texture"):Connect(function()
				if self:Classify(token, spawnClock) then
					self.pending[token] = nil
				end
			end))
		end
	end

	for _, desc in ipairs(token:GetDescendants()) do
		bindDecal(desc)
	end

	if token.DescendantAdded then
		table.insert(conns, token.DescendantAdded:Connect(function(desc)
			bindDecal(desc)
			if self:Classify(token, spawnClock) then
				self.pending[token] = nil
			end
		end))
	end

	if not self:Classify(token, spawnClock) then
		self.pending[token] = spawnClock
	end
end

function smileyHighlighter:BindDupedFolder(folder)
	connections:Cancel("dupedAdded")
	connections:Cancel("dupedRemoved")
	if not folder then
		self:ClearActiveOnly()
		return
	end
	connections:Add("dupedAdded", folder.ChildAdded:Connect(function(token)
		self:WatchToken(token)
	end))
	connections:Add("dupedRemoved", folder.ChildRemoved:Connect(function(token)
		self:UnwatchToken(token)
	end))
	for _, token in ipairs(folder:GetChildren()) do
		self:WatchToken(token)
	end
end

function smileyHighlighter:ClearActiveOnly()
	local existing = {}
	for token in pairs(self.active) do
		table.insert(existing, token)
	end
	for _, token in ipairs(existing) do
		self:Remove(token)
	end
end

function smileyHighlighter:ApplyFallbackDurationSetting()
	local dur = math.clamp(tonumber(cfg.smiley.fallbackDuration) or 10, 4, 20)
	local now = os.clock()
	for _, entry in pairs(self.active) do
		if entry.isFallback then
			entry.totalDuration = dur
			entry.endClock = entry.spawnClock + dur
			self:UpdateEntry(entry, now)
		end
	end
end

function smileyHighlighter:RefreshAll()
	if not cfg.smiley.enabled then
		self:ClearActiveOnly()
		return
	end
	local cam = workspace.CurrentCamera or workspace:FindFirstChild("Camera")
	local folder = cam and cam:FindFirstChild("DupedTokens") or nil
	if not folder then
		self:ClearActiveOnly()
		return
	end
	for _, token in ipairs(folder:GetChildren()) do
		local spawnClock = self.tokenTimestamps[token] or os.clock()
		self.tokenTimestamps[token] = spawnClock
		self:WatchToken(token)
		self:Classify(token, spawnClock)
	end
	self:UpdateAll(os.clock())
end

function smileyHighlighter:UpdateAll(now)
	local currentNow = now or os.clock()
	local stale = nil
	for token, entry in pairs(self.active) do
		if not token or not token.Parent then
			stale = stale or {}
			table.insert(stale, token)
		else
			self:UpdateEntry(entry, currentNow)
		end
	end
	if stale then
		for _, token in ipairs(stale) do
			self:UnwatchToken(token)
		end
	end
end

function smileyHighlighter:Maintain()
	local now = os.clock()
	local resolved = nil
	for token, spawnClock in pairs(self.pending) do
		if not token or not token.Parent or (now - spawnClock > 30) or self:Classify(token, spawnClock) then
			resolved = resolved or {}
			table.insert(resolved, token)
		end
	end
	if resolved then
		for _, token in ipairs(resolved) do
			self.pending[token] = nil
		end
	end

	for i = #self.spawnMetaQueue, 1, -1 do
		if now - self.spawnMetaQueue[i].recordedAt > 3.0 then
			table.remove(self.spawnMetaQueue, i)
		end
	end

	self:UpdateAll(now)
end

function smileyHighlighter:ClearAll()
	connections:Cancel("smileyTick")
	_G.__rbcHelperDupedSpawnSink = nil
	self:ClearActiveOnly()
	local watched = {}
	for token in pairs(self.watchers) do
		table.insert(watched, token)
	end
	for _, token in ipairs(watched) do
		self:UnwatchToken(token)
	end
	table.clear(self.pending)
	table.clear(self.tokenTimestamps)
	table.clear(self.spawnMetaQueue)
	if self.rootFolder then
		pcall(function()
			self.rootFolder:Destroy()
		end)
		self.rootFolder = nil
	end
	local stray = workspace:FindFirstChild(SMILEY_FOLDER_NAME)
	if stray then
		pcall(function()
			stray:Destroy()
		end)
	end
end

-- Atlas+ GUI Construction
local ScreenGui = Instance.new("ScreenGui")
ScreenGui.Name = "AtlasRbcHelper"
ScreenGui.ScreenInsets = Enum.ScreenInsets.None
ScreenGui.ResetOnSpawn = false
ScreenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
ScreenGui.Parent = gethui and gethui() or getService("CoreGui")

local ui = {}
local uiParts = {}
local controls = {}
local monitorState = {
	list = {},
	total = 0,
	notified = {},
}

local color_ = Color3.fromRGB(21, 22, 23)
local color_2 = Color3.fromRGB(30, 30, 30)
local color_3 = Color3.fromRGB(42, 42, 42)
local color_4 = Color3.fromRGB(52, 53, 56)
local color_5 = Color3.fromRGB(65, 67, 71)
local uicolor = _G.uicolor or Color3.fromRGB(41, 74, 122)
local goldColor = Color3.fromRGB(250, 204, 21)
local goldText = Color3.fromRGB(254, 240, 138)
local goldDot = Color3.fromRGB(253, 224, 71)

local viewportSize = Vector2.new(1280, 720)
pcall(function()
	if ScreenGui.AbsoluteSize and ScreenGui.AbsoluteSize.X > 0 then
		viewportSize = ScreenGui.AbsoluteSize
	elseif workspace.CurrentCamera and workspace.CurrentCamera.ViewportSize.X > 0 then
		viewportSize = workspace.CurrentCamera.ViewportSize
	end
end)
local isDesktop = _G.desktop ~= nil and _G.desktop or (viewportSize.X >= 850 and viewportSize.Y >= 500)

local minWindowSize = isDesktop and Vector2.new(640, 410) or Vector2.new(440, 300)
local windowSize = minWindowSize
local dragState = nil

connections:Add("drag", UserInputService.InputChanged:Connect(function(inputObj)
	if dragState and (inputObj.UserInputType == Enum.UserInputType.MouseMovement or inputObj.UserInputType == Enum.UserInputType.Touch) then
		for target, stateVal in pairs(dragState) do
			if stateVal == "resize" then
				local w = math.max(minWindowSize.X, inputObj.Position.X - target.AbsolutePosition.X)
				local h = math.max(minWindowSize.Y, inputObj.Position.Y - target.AbsolutePosition.Y)
				target.Size = UDim2.new(0, w, 0, h)
				windowSize = Vector2.new(w, h)
			elseif stateVal == "slider" then
				target(inputObj)
			else
				local startPos = stateVal[2]
				local delta = inputObj.Position - stateVal[1]
				target.Position = UDim2.new(startPos.X.Scale, startPos.X.Offset + delta.X, startPos.Y.Scale, startPos.Y.Offset + delta.Y)
			end
		end
	end
end))

connections:Add("stopdrag", UserInputService.InputEnded:Connect(function(inputObj)
	if inputObj.UserInputType == Enum.UserInputType.MouseButton1 or inputObj.UserInputType == Enum.UserInputType.Touch then
		dragState = nil
	end
end))

-- Main Atlas+ Window
local window = _G.background and Instance.new("ImageLabel") or Instance.new("Frame")
window.Name = "Window"
window.Active = true
window.BackgroundColor3 = color_
window.BorderSizePixel = 0
window.ClipsDescendants = true
window.Position = UDim2.new(0, 20, 0, 95)
window.Size = UDim2.new(0, windowSize.X, 0, windowSize.Y)
if _G.background then
	window.Image = _G.background
end
window.Parent = ScreenGui

local windowCorner = Instance.new("UICorner")
windowCorner.CornerRadius = UDim.new(0, 5)
windowCorner.Parent = window

-- Shared Atlas+ UI Templates
do
	local bar = Instance.new("Frame")
	bar.Name = "Bar"
	bar.BackgroundColor3 = uicolor
	bar.BorderSizePixel = 0
	bar.Size = UDim2.new(1, 0, 0, 25)
	uiParts.bar = bar

	local barCorner = Instance.new("UICorner")
	barCorner.CornerRadius = UDim.new(0, 5)
	barCorner.Parent = bar

	local barTitle = Instance.new("TextLabel")
	barTitle.Name = "Title"
	barTitle.BackgroundTransparency = 1
	barTitle.Font = Enum.Font.GothamBold
	barTitle.TextColor3 = Color3.fromRGB(255, 255, 255)
	barTitle.TextSize = 14
	barTitle.TextXAlignment = Enum.TextXAlignment.Left
	barTitle.Position = UDim2.new(0, 10, 0, 0)
	barTitle.Size = UDim2.new(0.8, -10, 0, 25)
	barTitle.Parent = bar

	local barIndicator = Instance.new("ImageButton")
	barIndicator.Name = "Indicator"
	barIndicator.BackgroundTransparency = 1
	barIndicator.Image = "https://www.roblox.com/Thumbs/Asset.ashx?width=420&height=420&assetId=4731371541"
	barIndicator.Position = UDim2.new(1, -25, 0, 2.5)
	barIndicator.Rotation = 90
	barIndicator.Size = UDim2.new(0, 20, 0, 20)
	barIndicator.Parent = bar

	local barBottom = Instance.new("Frame")
	barBottom.Name = "Frame"
	barBottom.BackgroundColor3 = uicolor
	barBottom.BorderSizePixel = 0
	barBottom.Position = UDim2.new(0, 0, 0.85, 0)
	barBottom.Size = UDim2.new(1, 0, 0, 4)
	barBottom.Parent = bar

	local tabBtn = Instance.new("TextButton")
	tabBtn.AutoButtonColor = false
	tabBtn.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
	tabBtn.BackgroundTransparency = 0.96
	tabBtn.Font = Enum.Font.GothamBold
	tabBtn.TextColor3 = Color3.fromRGB(237, 237, 237)
	tabBtn.TextSize = 11.5
	tabBtn.TextXAlignment = Enum.TextXAlignment.Left
	tabBtn.Size = UDim2.new(1, 0, 0, 23)
	uiParts.tabbutton = tabBtn

	local tabCorner = Instance.new("UICorner")
	tabCorner.CornerRadius = UDim.new(0, 4)
	tabCorner.Parent = tabBtn

	local tabIcon = Instance.new("ImageLabel")
	tabIcon.Name = "TabIcon"
	tabIcon.BackgroundTransparency = 1
	tabIcon.Position = UDim2.new(0, 5, 0, 5)
	tabIcon.Size = UDim2.new(0, 12, 0, 12)
	tabIcon.Parent = tabBtn

	local tabContainer = Instance.new("Frame")
	tabContainer.BackgroundTransparency = 1
	tabContainer.BorderSizePixel = 0
	tabContainer.Size = UDim2.new(1, -5, 1, 0)
	uiParts.tab = tabContainer

	local tabLayout = Instance.new("UIListLayout")
	tabLayout.SortOrder = Enum.SortOrder.LayoutOrder
	tabLayout.Padding = UDim.new(0, 5)
	tabLayout.Parent = tabContainer

	local folder = Instance.new("Frame")
	folder.Name = "Folder"
	folder.BackgroundTransparency = 1
	folder.BorderSizePixel = 0
	folder.Size = UDim2.new(1, 0, 0, 23)
	uiParts.folder = folder

	local folderBtn = Instance.new("TextButton")
	folderBtn.Name = "TextButton"
	folderBtn.AutoButtonColor = false
	folderBtn.BackgroundColor3 = color_3
	folderBtn.BorderSizePixel = 0
	folderBtn.Font = Enum.Font.GothamBold
	folderBtn.TextColor3 = Color3.new(0.784314, 0.784314, 0.784314)
	folderBtn.TextSize = 13
	folderBtn.TextXAlignment = Enum.TextXAlignment.Left
	folderBtn.Size = UDim2.new(1, 0, 0, 23)
	folderBtn.Parent = folder

	local folderCorner = Instance.new("UICorner")
	folderCorner.Name = "UICorner"
	folderCorner.CornerRadius = UDim.new(0, 4)
	folderCorner.Parent = folderBtn

	local folderIndicator = Instance.new("ImageLabel")
	folderIndicator.Name = "Indicator"
	folderIndicator.BackgroundTransparency = 1
	folderIndicator.Image = "https://www.roblox.com/Thumbs/Asset.ashx?width=420&height=420&assetId=4731371541"
	folderIndicator.Position = UDim2.new(1, -25, 0, 1)
	folderIndicator.Rotation = 180
	folderIndicator.Size = UDim2.new(0, 20, 0, 20)
	folderIndicator.Parent = folderBtn

	local folderBox = Instance.new("Frame")
	folderBox.Name = "Box"
	folderBox.BackgroundTransparency = 1
	folderBox.BorderSizePixel = 0
	folderBox.ClipsDescendants = true
	folderBox.Position = UDim2.new(0, 0, 0, 21)
	folderBox.Size = UDim2.new(1, 0, 1, -21)
	folderBox.Parent = folder

	local boxCorner = Instance.new("UICorner")
	boxCorner.Name = "UICorner"
	boxCorner.CornerRadius = UDim.new(0, 4)
	boxCorner.Parent = folderBox

	local boxLayout = Instance.new("UIListLayout")
	boxLayout.SortOrder = Enum.SortOrder.LayoutOrder
	boxLayout.Padding = UDim.new(0, 4)
	boxLayout.Parent = folderBox

	local boxPadding = Instance.new("UIPadding")
	boxPadding.Name = "UIPadding"
	boxPadding.PaddingTop = UDim.new(0, 12)
	boxPadding.PaddingLeft = UDim.new(0, 10)
	boxPadding.Parent = folderBox

	local folderBridge = Instance.new("Frame")
	folderBridge.Name = "Frame"
	folderBridge.BackgroundColor3 = color_3
	folderBridge.BorderSizePixel = 0
	folderBridge.Position = UDim2.new(0, 0, 0, 18)
	folderBridge.Size = UDim2.new(1, 0, 0, 5)
	folderBridge.Visible = false
	folderBridge.Parent = folder

	local btnTemplate = Instance.new("TextButton")
	btnTemplate.Name = "Button"
	btnTemplate.AutoButtonColor = false
	btnTemplate.BackgroundColor3 = uicolor
	btnTemplate.BorderSizePixel = 0
	btnTemplate.ClipsDescendants = true
	btnTemplate.Font = Enum.Font.GothamBold
	btnTemplate.TextColor3 = Color3.new(1, 1, 1)
	btnTemplate.TextSize = 13
	btnTemplate.Size = UDim2.new(0, 130, 0, 20)
	uiParts.button = btnTemplate

	local btnCorner = Instance.new("UICorner")
	btnCorner.Name = "UICorner"
	btnCorner.CornerRadius = UDim.new(0, 4)
	btnCorner.Parent = btnTemplate

	local labelTemplate = Instance.new("TextLabel")
	labelTemplate.Name = "Label"
	labelTemplate.BackgroundTransparency = 1
	labelTemplate.Font = Enum.Font.GothamSemibold
	labelTemplate.TextColor3 = Color3.new(1, 1, 1)
	labelTemplate.TextSize = 12
	labelTemplate.TextXAlignment = Enum.TextXAlignment.Left
	labelTemplate.TextTruncate = Enum.TextTruncate.AtEnd
	uiParts.label = labelTemplate

	local switchTemplate = Instance.new("Frame")
	switchTemplate.Name = "Switch"
	switchTemplate.BackgroundTransparency = 1
	switchTemplate.BorderSizePixel = 0
	switchTemplate.Size = UDim2.new(1, -20, 0, 20)
	uiParts.switch = switchTemplate

	local switchBtn = Instance.new("TextButton")
	switchBtn.Name = "Switch"
	switchBtn.AutoButtonColor = false
	switchBtn.BackgroundColor3 = uicolor
	switchBtn.BackgroundTransparency = 0.4
	switchBtn.BorderSizePixel = 0
	switchBtn.Font = Enum.Font.SourceSans
	switchBtn.Text = ""
	switchBtn.TextColor3 = Color3.new(1, 1, 1)
	switchBtn.TextSize = 18
	switchBtn.Size = UDim2.new(0, 20, 0, 20)
	switchBtn.Parent = switchTemplate

	local switchCorner = Instance.new("UICorner")
	switchCorner.Name = "UICorner"
	switchCorner.CornerRadius = UDim.new(0, 4)
	switchCorner.Parent = switchBtn

	local switchTitle = Instance.new("TextLabel")
	switchTitle.Name = "Title"
	switchTitle.BackgroundTransparency = 1
	switchTitle.Position = UDim2.new(1.2, 0, 0, 0)
	switchTitle.Size = UDim2.new(0, 180, 0, 20)
	switchTitle.Font = Enum.Font.GothamSemibold
	switchTitle.TextColor3 = Color3.new(0.784314, 0.784314, 0.784314)
	switchTitle.TextSize = 13
	switchTitle.TextXAlignment = Enum.TextXAlignment.Left
	switchTitle.Parent = switchBtn

	local sliderTemplate = Instance.new("Frame")
	sliderTemplate.Name = "Slider"
	sliderTemplate.BackgroundColor3 = color_4
	sliderTemplate.BorderSizePixel = 0
	sliderTemplate.Size = UDim2.new(1, -15, 0, 20)
	uiParts.slider = sliderTemplate

	local sliderCorner = Instance.new("UICorner")
	sliderCorner.Name = "UICorner"
	sliderCorner.CornerRadius = UDim.new(0, 4)
	sliderCorner.Parent = sliderTemplate

	local sliderHitbox = Instance.new("TextButton")
	sliderHitbox.Name = "Button"
	sliderHitbox.BackgroundTransparency = 1
	sliderHitbox.Text = ""
	sliderHitbox.Size = UDim2.new(1, 0, 1, 0)
	sliderHitbox.ZIndex = 2
	sliderHitbox.Parent = sliderTemplate

	local sliderIndicator = Instance.new("Frame")
	sliderIndicator.Name = "Indicator"
	sliderIndicator.BackgroundColor3 = color_5
	sliderIndicator.BorderSizePixel = 0
	sliderIndicator.Size = UDim2.new(0, 0, 0, 20)
	sliderIndicator.Parent = sliderTemplate

	local indicatorCorner = Instance.new("UICorner")
	indicatorCorner.Name = "UICorner"
	indicatorCorner.CornerRadius = UDim.new(0, 4)
	indicatorCorner.Parent = sliderIndicator

	local sliderTitle = Instance.new("TextLabel")
	sliderTitle.Name = "Title"
	sliderTitle.BackgroundTransparency = 1
	sliderTitle.Font = Enum.Font.GothamBold
	sliderTitle.TextColor3 = Color3.new(0.784314, 0.784314, 0.784314)
	sliderTitle.TextSize = 13
	sliderTitle.TextXAlignment = Enum.TextXAlignment.Center
	sliderTitle.Position = UDim2.new(0.5, 0, 0.5, -10)
	sliderTitle.Size = UDim2.new(0, 0, 0, 20)
	sliderTitle.ZIndex = 3
	sliderTitle.Parent = sliderTemplate

	local sliderValue = Instance.new("TextLabel")
	sliderValue.Name = "Value"
	sliderValue.BackgroundTransparency = 1
	sliderValue.Font = Enum.Font.GothamBold
	sliderValue.Text = "0"
	sliderValue.TextColor3 = Color3.new(0.784314, 0.784314, 0.784314)
	sliderValue.TextSize = 13
	sliderValue.Position = UDim2.new(1, -45, 0.5, -10)
	sliderValue.Size = UDim2.new(0, 40, 0, 20)
	sliderValue.TextXAlignment = Enum.TextXAlignment.Right
	sliderValue.ZIndex = 3
	sliderValue.Parent = sliderTemplate
end

-- Top bar for main window
local windowVisible = true
do
	local bar = uiParts.bar:Clone()
	local indicator = bar.Indicator
	bar.Title.Text = "Atlas+ RBC Helper"
	bar.Parent = window

	bar.InputBegan:Connect(function(inputObj)
		if inputObj.UserInputType == Enum.UserInputType.MouseButton1 or inputObj.UserInputType == Enum.UserInputType.Touch then
			if not dragState then
				dragState = {}
			end
			dragState[window] = { inputObj.Position, window.Position }
		end
	end)

	indicator.MouseButton1Click:Connect(function()
		windowVisible = not windowVisible
		bar.Frame.Visible = windowVisible
		TweenService:Create(window, TweenInfo.new(0.1, Enum.EasingStyle.Linear, Enum.EasingDirection.In), {
			Size = windowVisible and UDim2.new(0, windowSize.X, 0, windowSize.Y) or UDim2.new(0, windowSize.X, 0, 25),
		}):Play()
		TweenService:Create(indicator, TweenInfo.new(0.1, Enum.EasingStyle.Linear, Enum.EasingDirection.In), {
			Rotation = windowVisible and 90 or 180,
		}):Play()
	end)
end

-- Mobile Toggle Button
local mobileBtn = Instance.new("ImageButton")
mobileBtn.Name = "Button"
mobileBtn.BackgroundTransparency = 1
mobileBtn.Image = "rbxasset://textures/ui/TopBar/iconBase.png"
mobileBtn.Position = UDim2.new(0.5, -22, 0, 56)
mobileBtn.Size = UDim2.new(0, 44, 0, 44)
mobileBtn.Visible = cfg.misc.mobiletoggle
mobileBtn.Parent = ScreenGui

local mobileCorner = Instance.new("UICorner")
mobileCorner.CornerRadius = UDim.new(0, 6)
mobileCorner.Parent = mobileBtn

local mobileIcon = Instance.new("ImageLabel")
mobileIcon.Name = "Image"
mobileIcon.BackgroundTransparency = 1
mobileIcon.Image = "rbxassetid://120901539385431"
mobileIcon.Position = UDim2.new(0, 8, 0, 8)
mobileIcon.Size = UDim2.new(0, 28, 0, 28)
mobileIcon.Parent = mobileBtn

mobileBtn.InputBegan:Connect(function(inputObj)
	if inputObj.UserInputType == Enum.UserInputType.MouseButton1 or inputObj.UserInputType == Enum.UserInputType.Touch then
		if not dragState then
			dragState = {}
		end
		dragState[mobileBtn] = { inputObj.Position, mobileBtn.Position }
	end
end)

mobileBtn.MouseButton1Click:Connect(function()
	window.Visible = not window.Visible
end)

-- Sidebar & Tab Area
local tabButtonsHolder = Instance.new("Frame")
tabButtonsHolder.Name = "TabButtons"
tabButtonsHolder.BackgroundColor3 = color_2
tabButtonsHolder.BackgroundTransparency = isDesktop and 0 or 1
tabButtonsHolder.BorderSizePixel = 0
tabButtonsHolder.Position = UDim2.new(0, 0, 0, 25)
tabButtonsHolder.Size = UDim2.new(0, 90, 1, -25)
tabButtonsHolder.Parent = window

if isDesktop then
	local sideCorner = Instance.new("UICorner")
	sideCorner.CornerRadius = UDim.new(0, 5)
	sideCorner.Parent = tabButtonsHolder
end
if _G.background then
	tabButtonsHolder.BackgroundTransparency = 0.5
end

local tabListScroll = Instance.new("ScrollingFrame")
tabListScroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
tabListScroll.BackgroundTransparency = 1
tabListScroll.BorderSizePixel = 0
tabListScroll.CanvasSize = UDim2.new()
tabListScroll.ScrollBarThickness = 0
tabListScroll.ScrollingDirection = Enum.ScrollingDirection.Y
tabListScroll.Position = UDim2.new(0, 5, 0, 5)
tabListScroll.Size = UDim2.new(1, -10, 1, -10)
tabListScroll.Parent = tabButtonsHolder

local tabListLayout = Instance.new("UIListLayout")
tabListLayout.SortOrder = Enum.SortOrder.LayoutOrder
tabListLayout.Padding = UDim.new(0, 4)
tabListLayout.Parent = tabListScroll

local resizeHandle = Instance.new("Frame")
resizeHandle.Name = "Resize"
resizeHandle.BackgroundTransparency = 1
resizeHandle.BorderSizePixel = 0
resizeHandle.Position = UDim2.new(1, -20, 1, -20)
resizeHandle.Size = UDim2.new(0, 20, 0, 20)
resizeHandle.ZIndex = 2
resizeHandle.Parent = window

resizeHandle.InputBegan:Connect(function(inputObj)
	if inputObj.UserInputType == Enum.UserInputType.MouseButton1 or inputObj.UserInputType == Enum.UserInputType.Touch then
		if not dragState then
			dragState = {}
		end
		dragState[window] = "resize"
	end
end)

local searchBoxFrame = Instance.new("Frame")
searchBoxFrame.Name = "SearchBox"
searchBoxFrame.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
searchBoxFrame.BackgroundTransparency = 0.96
searchBoxFrame.BorderSizePixel = 0
searchBoxFrame.Size = UDim2.new(1, 0, 0, 23)
searchBoxFrame.Parent = tabListScroll

local searchCorner = Instance.new("UICorner")
searchCorner.CornerRadius = UDim.new(0, 4)
searchCorner.Parent = searchBoxFrame

local searchBox = Instance.new("TextBox")
searchBox.BackgroundTransparency = 1
searchBox.Font = Enum.Font.GothamBold
searchBox.PlaceholderText = "Search"
searchBox.PlaceholderColor3 = Color3.fromRGB(237, 237, 237)
searchBox.Text = ""
searchBox.TextColor3 = Color3.fromRGB(237, 237, 237)
searchBox.TextSize = 11.5
searchBox.Position = UDim2.new(0, 18, 0, 0)
searchBox.Size = UDim2.new(1, -18, 0, 23)
searchBox.TextXAlignment = Enum.TextXAlignment.Left
searchBox.Parent = searchBoxFrame

local searchIcon = Instance.new("ImageLabel")
searchIcon.Name = "SearchIcon"
searchIcon.BackgroundTransparency = 1
searchIcon.Image = "rbxassetid://10734943674"
searchIcon.Position = UDim2.new(0, 5, 0, 5)
searchIcon.Size = UDim2.new(0, 12, 0, 12)
searchIcon.Parent = searchBoxFrame

local divider = Instance.new("Frame")
divider.Name = "Divider"
divider.BackgroundColor3 = Color3.fromRGB(56, 56, 56)
divider.BorderSizePixel = 0
divider.Size = UDim2.new(1, 0, 0, 2)
divider.Parent = tabListScroll

local activeTabFrame = nil
local activeTabFrame2 = nil
local activeTabButton = nil
local searchableItems = {}

searchBox.Changed:Connect(function()
	local q = string.lower(searchBox.Text)
	if #q > 0 then
		for _, child in ipairs(tabListScroll:GetChildren()) do
			if child:IsA("TextButton") then
				child.Visible = string.find(string.lower(child.Text), q, 1, true) ~= nil
			end
		end
		for _, entry in ipairs(searchableItems) do
			if string.find(string.lower(entry[1]), q, 1, true) then
				entry[2].Visible = true
			end
		end
	else
		for _, child in ipairs(tabListScroll:GetChildren()) do
			if child:IsA("TextButton") then
				child.Visible = true
			end
		end
	end
end)

ui.Notify = function(title, description)
	local existing = ScreenGui:FindFirstChild("Tooltip")
	if existing then
		existing:Destroy()
	end
	local _, newlineCount = string.gsub(tostring(description), "\n", " ")
	local toast = Instance.new("ImageLabel")
	toast.Name = "Tooltip"
	toast.BackgroundTransparency = 1
	toast.Image = "rbxassetid://11942813307"
	toast.ImageColor3 = Color3.fromRGB(1, 1, 1)
	toast.ImageTransparency = 0.25
	toast.ScaleType = Enum.ScaleType.Slice
	toast.SliceCenter = Rect.new(512, 512, 512, 512)
	toast.AnchorPoint = Vector2.new(1, 1)
	toast.Position = UDim2.new(1, -8, 1, -8)
	toast.Size = UDim2.new(0, newlineCount == 2 and 270 or 260, 0, newlineCount == 2 and 80 or 60)
	toast.Parent = ScreenGui

	local tTitle = Instance.new("TextLabel")
	tTitle.Name = "Title"
	tTitle.BackgroundTransparency = 1
	tTitle.Font = Enum.Font.GothamBold
	tTitle.Text = tostring(title)
	tTitle.TextColor3 = Color3.new(1, 1, 1)
	tTitle.TextSize = 14
	tTitle.TextXAlignment = Enum.TextXAlignment.Left
	tTitle.Position = UDim2.new(0, 14, 0, newlineCount > 0 and 8 or 10)
	tTitle.Size = UDim2.new(1, -24, 0, 20)
	tTitle.Parent = toast

	local tDesc = Instance.new("TextLabel")
	tDesc.Name = "Description"
	tDesc.BackgroundTransparency = 1
	tDesc.Font = Enum.Font.GothamSemibold
	tDesc.Text = tostring(description)
	tDesc.TextColor3 = Color3.fromRGB(220, 220, 225)
	tDesc.TextSize = 13
	tDesc.TextXAlignment = Enum.TextXAlignment.Left
	tDesc.TextTruncate = Enum.TextTruncate.AtEnd
	tDesc.Position = UDim2.new(0, 14, 0, newlineCount == 2 and 38 or 30)
	tDesc.Size = UDim2.new(1, -24, 0, 20)
	tDesc.Parent = toast

	threads:Add("Tooltip", function()
		task.wait(4)
		if toast and toast.Parent then
			toast:Destroy()
		end
	end)
end

ui.AddTab = function(tabName, image, twoColumn, startActive)
	local tabBtn = uiParts.tabbutton:Clone()
	tabBtn.Name = "TabButton_" .. tabName
	tabBtn.Text = "        " .. tabName
	tabBtn.TabIcon.Image = image
	tabBtn.Parent = tabListScroll

	local scrollLeft = Instance.new("ScrollingFrame")
	scrollLeft.Name = "Tab"
	scrollLeft.AutomaticCanvasSize = Enum.AutomaticSize.Y
	scrollLeft.BackgroundTransparency = 1
	scrollLeft.BorderSizePixel = 0
	scrollLeft.CanvasSize = UDim2.new()
	scrollLeft.ScrollBarThickness = 5
	scrollLeft.ScrollBarImageTransparency = 1
	scrollLeft.ScrollingDirection = Enum.ScrollingDirection.Y
	scrollLeft.VerticalScrollBarInset = Enum.ScrollBarInset.None
	scrollLeft.Position = UDim2.new(0, 95, 0, 30)
	scrollLeft.Size = UDim2.new(1, -95, 1, -30)

	local padLeft = Instance.new("UIPadding")
	padLeft.PaddingBottom = UDim.new(0, 5)
	padLeft.Parent = scrollLeft

	local colLeft = uiParts.tab:Clone()
	colLeft.Parent = scrollLeft

	local scrollRight, colRight
	if isDesktop and twoColumn then
		scrollRight = Instance.new("ScrollingFrame")
		scrollRight.Name = "Tab2"
		scrollRight.AutomaticCanvasSize = Enum.AutomaticSize.Y
		scrollRight.BackgroundTransparency = 1
		scrollRight.BorderSizePixel = 0
		scrollRight.CanvasSize = UDim2.new()
		scrollRight.ScrollBarThickness = 5
		scrollRight.ScrollBarImageTransparency = 1
		scrollRight.ScrollingDirection = Enum.ScrollingDirection.Y
		scrollRight.VerticalScrollBarInset = Enum.ScrollBarInset.None
		scrollRight.Position = UDim2.new(0.5, 47.5, 0, 30)
		scrollLeft.Size = UDim2.new(0.5, -47.5, 1, -30)
		scrollRight.Size = scrollLeft.Size

		local padRight = Instance.new("UIPadding")
		padRight.PaddingBottom = UDim.new(0, 5)
		padRight.Parent = scrollRight

		colRight = uiParts.tab:Clone()
		colRight.Parent = scrollRight
	end

	tabBtn.MouseEnter:Connect(function()
		if activeTabButton ~= tabBtn then
			TweenService:Create(tabBtn, TweenInfo.new(0.15, Enum.EasingStyle.Linear, Enum.EasingDirection.In), { BackgroundTransparency = 0.93 }):Play()
		end
	end)

	tabBtn.MouseLeave:Connect(function()
		if activeTabButton ~= tabBtn then
			TweenService:Create(tabBtn, TweenInfo.new(0.15, Enum.EasingStyle.Linear, Enum.EasingDirection.In), { BackgroundTransparency = 0.96 }):Play()
		end
	end)

	tabBtn.MouseButton1Click:Connect(function()
		if activeTabFrame and activeTabButton ~= tabBtn then
			activeTabFrame.Parent = nil
			if activeTabFrame2 then
				activeTabFrame2.Parent = nil
			end
			TweenService:Create(activeTabButton, TweenInfo.new(0.15, Enum.EasingStyle.Linear, Enum.EasingDirection.In), { BackgroundTransparency = 0.96 }):Play()
			TweenService:Create(tabBtn, TweenInfo.new(0.15, Enum.EasingStyle.Linear, Enum.EasingDirection.In), { BackgroundTransparency = 0.85 }):Play()
			scrollLeft.Parent = window
			activeTabButton = tabBtn
			activeTabFrame = scrollLeft
			activeTabFrame2 = scrollRight
			if scrollRight then
				scrollRight.Parent = window
			end
		end
	end)

	if startActive then
		TweenService:Create(tabBtn, TweenInfo.new(0.15, Enum.EasingStyle.Linear, Enum.EasingDirection.In), { BackgroundTransparency = 0.85 }):Play()
		scrollLeft.Parent = window
		activeTabButton = tabBtn
		activeTabFrame = scrollLeft
		if scrollRight then
			scrollRight.Parent = window
			activeTabFrame2 = scrollRight
		end
	end

	local tabApi = {}
	tabApi.AddFolder = function(folderName, useRightColumn)
		local folderApi = {}
		local isOpen = false
		local measuredOnce = nil
		local folderFrame = uiParts.folder:Clone()
		local headerBtn = folderFrame.TextButton
		local box = folderFrame.Box

		if _G.background then
			folderFrame.BackgroundColor3 = color_2
			folderFrame.BackgroundTransparency = 0.4
			if _G.uicolor then
				folderFrame.Frame.BackgroundColor3 = _G.uicolor
				headerBtn.BackgroundColor3 = _G.uicolor
			end
		end

		headerBtn.Text = "   " .. folderName
		folderFrame.Parent = (isDesktop and useRightColumn and colRight) or colLeft

		folderApi.AddLabel = function(text)
			local lbl = uiParts.label:Clone()
			lbl.Text = text
			lbl.Size = UDim2.new(1, -10, 0, 17)
			lbl.Parent = box
			table.insert(searchableItems, { text, tabBtn })
			return lbl
		end

		folderApi.AddButton = function(text, callback, width)
			table.insert(searchableItems, { text, tabBtn })
			local btn = uiParts.button:Clone()
			if width then
				btn.Size = UDim2.new(0, width, 0, 20)
			end
			btn.Text = text
			btn.Parent = box
			btn.MouseButton1Click:Connect(function()
				if callback then
					callback()
				end
			end)
			return btn
		end

		folderApi.AddSwitch = function(text, callback, configSource, configKey)
			local switchApi = {}
			local row = uiParts.switch:Clone()
			local switch = row.Switch
			local titleLabel = switch.Title
			titleLabel.Text = text
			row.Parent = box

			local isOn = false
			local configTable = (configSource and type(configSource) == "string" and cfg[configSource]) or configSource
			if configTable and configTable[configKey] then
				isOn = true
				switch.Text = utf8.char(10003)
				if callback then
					callback(true)
				end
			end

			switch.MouseButton1Click:Connect(function()
				isOn = not isOn
				switch.Text = isOn and utf8.char(10003) or ""
				if configTable then
					configTable[configKey] = isOn
					saveConfig()
				end
				if callback then
					callback(isOn)
				end
			end)

			switchApi.Set = function(newState, skipCallback)
				isOn = newState == true
				switch.Text = isOn and utf8.char(10003) or ""
				if configTable then
					configTable[configKey] = isOn
					saveConfig()
				end
				if callback and not skipCallback then
					callback(isOn)
				end
			end

			switchApi.SetVisible = function(v)
				row.Visible = v
			end

			table.insert(searchableItems, { text, tabBtn })
			return switchApi
		end

		folderApi.AddSlider = function(sliderTitle, callback, minValue, maxValue, configSource, configKey, options)
			table.insert(searchableItems, { sliderTitle, tabBtn })
			local sliderApi = {}
			local sliderRow = uiParts.slider:Clone()
			sliderRow.Parent = box
			local hitbox = sliderRow.Button
			local indicator = sliderRow.Indicator
			local valueLabel = sliderRow.Value
			local left = options and options.Left
			local decimal = options and options.Decimal
			local configTable = (configSource and type(configSource) == "string" and cfg[configSource]) or configSource
			local titleLabel = sliderRow.Title
			titleLabel.Text = left and ("   " .. sliderTitle) or sliderTitle
			if left then
				titleLabel.TextXAlignment = Enum.TextXAlignment.Left
				titleLabel.Position = UDim2.new(0, 0, 0.5, -10)
			end

			local lastValue = nil
			local function formatSliderVal(raw)
				local clamped = math.clamp(raw, minValue, maxValue)
				return decimal and (math.round(clamped * 10) / 10) or math.floor(clamped)
			end

			local function updateFromInput(inputObj)
				local width = sliderRow.AbsoluteSize.X
				if width <= 0 then
					return
				end
				local px = math.clamp(inputObj.Position.X - sliderRow.AbsolutePosition.X, 0, width)
				local ratio = px / width
				local val = formatSliderVal(minValue + ratio * (maxValue - minValue))
				TweenService:Create(indicator, TweenInfo.new(0.08, Enum.EasingStyle.Linear, Enum.EasingDirection.In), {
					Size = UDim2.new(0, px, 0, 20),
				}):Play()
				valueLabel.Text = tostring(val)
				if configTable then
					configTable[configKey] = val
					saveConfig()
				end
				local prev = lastValue
				lastValue = val
				if callback and prev ~= val then
					callback(val)
				end
			end

			hitbox.InputBegan:Connect(function(inputObj)
				if inputObj.UserInputType == Enum.UserInputType.MouseButton1 or inputObj.UserInputType == Enum.UserInputType.Touch then
					if not dragState then
						dragState = {}
					end
					dragState[updateFromInput] = "slider"
					updateFromInput(inputObj)
				end
			end)

			sliderApi.Set = function(newValue, skipCallback)
				local colWidth = (isDesktop and twoColumn and (windowSize.X * 0.5 - 47 - 5 - 10 - 15)) or (windowSize.X - 95 - 5 - 10 - 15)
				colWidth = math.max(1, colWidth)
				local val = formatSliderVal(tonumber(newValue) or minValue)
				local fillRatio = (maxValue > minValue) and ((val - minValue) / (maxValue - minValue)) or 0
				TweenService:Create(indicator, TweenInfo.new(0.08, Enum.EasingStyle.Linear, Enum.EasingDirection.In), {
					Size = UDim2.new(0, fillRatio * colWidth, 0, 20),
				}):Play()
				valueLabel.Text = tostring(val)
				if configTable then
					configTable[configKey] = val
					saveConfig()
				end
				local prev = lastValue
				lastValue = val
				if callback and not skipCallback and prev ~= nil and prev ~= val then
					callback(val)
				end
			end

			sliderApi.SetVisible = function(v)
				sliderRow.Visible = v
			end

			sliderApi.SetTitle = function(newTitle)
				titleLabel.Text = left and ("   " .. newTitle) or newTitle
			end

			if configTable and configTable[configKey] ~= nil then
				sliderApi.Set(configTable[configKey], true)
			else
				sliderApi.Set(minValue, true)
			end

			return sliderApi
		end

		folderApi.Toggle = function(openState, desktopOnly)
			if desktopOnly and not isDesktop then
				return
			end
			local measuredHeight = 37
			for _, child in ipairs(box:GetChildren()) do
				if child.ClassName ~= "UIPadding" and child.ClassName ~= "UIListLayout" and child.ClassName ~= "UICorner" and child.Visible then
					measuredHeight += child.Size.Y.Offset + 4
				end
			end
			if not measuredOnce then
				measuredOnce = measuredHeight
			end
			folderFrame.Frame.Visible = openState
			box.BackgroundTransparency = openState and 0.96 or 1
			box.ClipsDescendants = not openState
			isOpen = openState
			TweenService:Create(folderFrame, TweenInfo.new(0.08, Enum.EasingStyle.Linear, Enum.EasingDirection.In), {
				Size = openState and UDim2.new(1, 0, 0, measuredHeight) or UDim2.new(1, 0, 0, 23),
			}):Play()
			TweenService:Create(headerBtn.Indicator, TweenInfo.new(0.08, Enum.EasingStyle.Linear, Enum.EasingDirection.In), {
				Rotation = openState and 90 or 180,
			}):Play()
		end

		folderApi.Refresh = function()
			if measuredOnce then
				local measuredHeight = 37
				for _, child in ipairs(box:GetChildren()) do
					if child.ClassName ~= "UIPadding" and child.ClassName ~= "UIListLayout" and child.ClassName ~= "UICorner" and child.Visible then
						measuredHeight += child.Size.Y.Offset + 4
					end
				end
				measuredOnce = measuredHeight
				TweenService:Create(folderFrame, TweenInfo.new(0, Enum.EasingStyle.Linear, Enum.EasingDirection.In), {
					Size = isOpen and UDim2.new(1, 0, 0, measuredHeight) or UDim2.new(1, 0, 0, 23),
				}):Play()
			end
		end

		headerBtn.MouseButton1Click:Connect(function()
			folderApi.Toggle(not isOpen)
		end)

		table.insert(searchableItems, { folderName, tabBtn })
		return folderApi
	end

	return tabApi
end

-- Top-of-Screen Golden Cogmower Monitor HUD
local monitorFrame = Instance.new("Frame")
monitorFrame.Name = "GoldCogMonitor"
monitorFrame.Active = true
monitorFrame.AnchorPoint = Vector2.new(0.5, 0)
monitorFrame.BackgroundColor3 = color_
monitorFrame.BackgroundTransparency = 0.06
monitorFrame.BorderSizePixel = 0
monitorFrame.ClipsDescendants = true
monitorFrame.Position = UDim2.new(0.5, 0, 0, 10)
monitorFrame.Size = UDim2.new(0, 440, 0, 38)
monitorFrame.ZIndex = 10
monitorFrame.Visible = cfg.monitor.enabled
monitorFrame.Parent = ScreenGui

local monitorCorner = Instance.new("UICorner")
monitorCorner.CornerRadius = UDim.new(0, 6)
monitorCorner.Parent = monitorFrame

local monitorStroke = Instance.new("UIStroke")
monitorStroke.Thickness = 1.5
monitorStroke.Color = uicolor
monitorStroke.Parent = monitorFrame

local monitorAccent = Instance.new("Frame")
monitorAccent.Name = "Accent"
monitorAccent.BackgroundColor3 = uicolor
monitorAccent.BorderSizePixel = 0
monitorAccent.Size = UDim2.new(1, 0, 0, 3)
monitorAccent.ZIndex = 11
monitorAccent.Parent = monitorFrame

local monitorDot = Instance.new("Frame")
monitorDot.Name = "Dot"
monitorDot.BackgroundColor3 = Color3.fromRGB(115, 130, 155)
monitorDot.BorderSizePixel = 0
monitorDot.Position = UDim2.new(0, 12, 0.5, -4)
monitorDot.Size = UDim2.new(0, 10, 0, 10)
monitorDot.ZIndex = 11
monitorDot.Parent = monitorFrame

local monitorDotCorner = Instance.new("UICorner")
monitorDotCorner.CornerRadius = UDim.new(1, 0)
monitorDotCorner.Parent = monitorDot

local monitorMainText = Instance.new("TextLabel")
monitorMainText.Name = "StatusText"
monitorMainText.BackgroundTransparency = 1
monitorMainText.Font = Enum.Font.GothamBold
monitorMainText.Text = "GOLDEN COGMOWER  |  None on map"
monitorMainText.TextColor3 = Color3.fromRGB(215, 220, 230)
monitorMainText.TextSize = 13
monitorMainText.TextXAlignment = Enum.TextXAlignment.Left
monitorMainText.TextTruncate = Enum.TextTruncate.AtEnd
monitorMainText.Position = UDim2.new(0, 30, 0, 3)
monitorMainText.Size = UDim2.new(1, -120, 1, -3)
monitorMainText.ZIndex = 11
monitorMainText.Parent = monitorFrame

local monitorBadge = Instance.new("TextLabel")
monitorBadge.Name = "Badge"
monitorBadge.BackgroundColor3 = color_4
monitorBadge.BorderSizePixel = 0
monitorBadge.Font = Enum.Font.GothamBold
monitorBadge.Text = "Gold: 0"
monitorBadge.TextColor3 = Color3.fromRGB(220, 225, 235)
monitorBadge.TextSize = 11
monitorBadge.AnchorPoint = Vector2.new(1, 0.5)
monitorBadge.Position = UDim2.new(1, -10, 0.5, 1)
monitorBadge.Size = UDim2.new(0, 74, 0, 22)
monitorBadge.ZIndex = 11
monitorBadge.Parent = monitorFrame

local monitorBadgeCorner = Instance.new("UICorner")
monitorBadgeCorner.CornerRadius = UDim.new(0, 4)
monitorBadgeCorner.Parent = monitorBadge

monitorFrame.InputBegan:Connect(function(inputObj)
	if inputObj.UserInputType == Enum.UserInputType.MouseButton1 or inputObj.UserInputType == Enum.UserInputType.Touch then
		if not dragState then
			dragState = {}
		end
		dragState[monitorFrame] = { inputObj.Position, monitorFrame.Position }
	end
end)

-- Tabs & Controls
local helperTab = ui.AddTab("Helper", "rbxassetid://10723415903", true, true)
local settingsTab = ui.AddTab("Settings", "rbxassetid://10734950309", false, false)

-- Left Column: Golden Cogmower Monitor, Movement, World / Performance
local monitorFolder = helperTab.AddFolder("Golden Cogmower Monitor")
local monitorStatusLabel = monitorFolder.AddLabel("Status: No Golden Cogmower on map")
local goldCountLabel = monitorFolder.AddLabel("Active Golden Cogmowers: 0")

controls.showMonitor = monitorFolder.AddSwitch("Show Top Cogmower HUD", function(enabled)
	monitorFrame.Visible = enabled
end, "monitor", "enabled")

controls.notifyGoldCog = monitorFolder.AddSwitch("Notify On Golden Cogmower", nil, "monitor", "notifyOnGoldCog")

monitorFolder.AddButton("Reset Monitor Position", function()
	monitorFrame.Position = UDim2.new(0.5, 0, 0, 10)
end, 165)

monitorFolder.Toggle(true, true)

local movementFolder = helperTab.AddFolder("Movement")
local walkSpeedSlider, multiplierSlider

controls.walkspeedenabled = movementFolder.AddSwitch("Enable Walk Speed", function(enabled)
	walkSpeedController:SetEnabled(enabled)
end, "movement", "walkspeedenabled")

controls.walkdynamic = movementFolder.AddSwitch("Dynamic Walk Speed", function(enabled)
	if walkSpeedSlider then
		walkSpeedSlider.SetTitle(enabled and "Maximum Walk Speed" or "Walk Speed")
	end
	if multiplierSlider then
		multiplierSlider.SetVisible(enabled)
	end
	movementFolder.Refresh()
	walkSpeedController:Step()
end, "movement", "walkdynamic")

walkSpeedSlider = movementFolder.AddSlider("Walk Speed", function()
	walkSpeedController:Step()
end, 30, 90, "movement", "walkspeed", { Left = true })

multiplierSlider = movementFolder.AddSlider("Walk Speed Multiplier", function()
	walkSpeedController:Step()
end, 1, 2, "movement", "walkspeed2", { Left = true, Decimal = true })

controls.walkspeed = walkSpeedSlider
controls.walkspeed2 = multiplierSlider

if walkSpeedSlider then
	walkSpeedSlider.SetTitle(cfg.movement.walkdynamic and "Maximum Walk Speed" or "Walk Speed")
end
if multiplierSlider then
	multiplierSlider.SetVisible(cfg.movement.walkdynamic)
end

movementFolder.Toggle(true, true)

local worldFolder = helperTab.AddFolder("World / Performance")

controls.hideDecorations = worldFolder.AddSwitch("Hide Decorations", function(enabled)
	decorationsController:SetEnabled(enabled)
end, "decorations", "hide")

worldFolder.Toggle(true, true)

-- Right Column: Auto Face Flames (BodyGyro), Digital Smiley Tokens
local flameFolder = helperTab.AddFolder("Auto Face Flames (BodyGyro)", true)
local flameStatusLabel = flameFolder.AddLabel("Target: Disabled")
flameController.statusLabel = flameStatusLabel

controls.flamesEnabled = flameFolder.AddSwitch("Enable Flame Auto-Face", function(enabled)
	flameController:SetEnabled(enabled)
end, "flames", "enabled")

controls.flamesRefreshPriority = flameFolder.AddSwitch("Prioritize Expiring Flames", nil, "flames", "refreshPriority")
controls.flamesOnlyReady = flameFolder.AddSwitch("Only Face When Ready", nil, "flames", "onlyRefreshReady")

controls.flamesSmartDig = flameFolder.AddSwitch("Smart Auto Dig (Refresh Sync)", function()
	syncSmartAutoDig()
end, "flames", "smartAutoDig")

controls.flamesRefreshAge = flameFolder.AddSlider("Refresh Age (secs)", nil, 1.5, 4.5, "flames", "refreshAge", { Left = true, Decimal = true })
controls.flamesMaxRange = flameFolder.AddSlider("Flame Range (studs)", nil, 15, 45, "flames", "maxRange", { Left = true })

flameFolder.Toggle(true, true)

local smileyFolder = helperTab.AddFolder("Digital Smiley Tokens", true)

local function onSmileyVisualsChanged()
	smileyHighlighter:RefreshAll()
end

controls.smileyEnabled = smileyFolder.AddSwitch("Highlight Smiley Duped Tokens", onSmileyVisualsChanged, "smiley", "enabled")
controls.smileyBeam = smileyFolder.AddSwitch("3D Ground Drop Beam", onSmileyVisualsChanged, "smiley", "beam")
controls.smileyTimer = smileyFolder.AddSwitch("Show Countdown Timer", onSmileyVisualsChanged, "smiley", "timer")
controls.smileyFallbackDuration = smileyFolder.AddSlider("Fallback Duration (s)", function()
	smileyHighlighter:ApplyFallbackDurationSetting()
end, 4, 20, "smiley", "fallbackDuration", { Left = true })
smileyFolder.AddLabel("Under 0.9s turns Red (1s activation)")

smileyFolder.Toggle(true, true)

-- Settings Tab
local settingsFolder = settingsTab.AddFolder("Helper")

controls.mobiletoggle = settingsFolder.AddSwitch("Mobile Toggle Button", function(enabled)
	mobileBtn.Visible = enabled
end, "misc", "mobiletoggle")

local cleanup -- forward declared

settingsFolder.AddButton("Reset All Settings", function()
	mergeConfig(cfg, deepCopy(defaultCfg))
	saveConfig()
	controls.showMonitor.Set(cfg.monitor.enabled)
	controls.notifyGoldCog.Set(cfg.monitor.notifyOnGoldCog)
	controls.walkspeedenabled.Set(cfg.movement.walkspeedenabled)
	controls.walkdynamic.Set(cfg.movement.walkdynamic)
	controls.walkspeed.Set(cfg.movement.walkspeed)
	controls.walkspeed2.Set(cfg.movement.walkspeed2)
	controls.hideDecorations.Set(cfg.decorations.hide)
	controls.flamesEnabled.Set(cfg.flames.enabled)
	controls.flamesRefreshPriority.Set(cfg.flames.refreshPriority)
	controls.flamesOnlyReady.Set(cfg.flames.onlyRefreshReady)
	controls.flamesSmartDig.Set(cfg.flames.smartAutoDig)
	controls.flamesRefreshAge.Set(cfg.flames.refreshAge)
	controls.flamesMaxRange.Set(cfg.flames.maxRange)
	controls.smileyEnabled.Set(cfg.smiley.enabled)
	controls.smileyBeam.Set(cfg.smiley.beam)
	controls.smileyTimer.Set(cfg.smiley.timer)
	controls.smileyFallbackDuration.Set(cfg.smiley.fallbackDuration)
	controls.mobiletoggle.Set(cfg.misc.mobiletoggle)
	ui.Notify("RBC Helper", "Settings reset to defaults")
end, 145)

settingsFolder.AddButton("Unload Helper", function()
	if cleanup then
		cleanup()
	end
end, 145)

settingsFolder.Toggle(true, true)

-- Runtime Watchers & Monitor Step
local stepMonitor -- forward declared

local function bindMonstersFolder(folder)
	connections:Cancel("monstersAdded")
	connections:Cancel("monstersRemoved")
	if not folder then
		return
	end
	connections:Add("monstersAdded", folder.ChildAdded:Connect(function(child)
		if child.Name == "Gold Cogmower" and stepMonitor then
			stepMonitor(true)
		end
	end))
	connections:Add("monstersRemoved", folder.ChildRemoved:Connect(function(child)
		if child.Name == "Gold Cogmower" then
			monitorState.notified[child] = nil
			if stepMonitor then
				stepMonitor(true)
			end
		end
	end))
end

local function bindCameraDupedTokens(cam)
	connections:Cancel("camChildAdded")
	if not cam then
		smileyHighlighter:BindDupedFolder(nil)
		return
	end
	smileyHighlighter:BindDupedFolder(cam:FindFirstChild("DupedTokens"))
	connections:Add("camChildAdded", cam.ChildAdded:Connect(function(child)
		if child.Name == "DupedTokens" then
			smileyHighlighter:BindDupedFolder(child)
		end
	end))
end

smileyHighlighter:InstallDupedSpawnTap()
bindMonstersFolder(workspace:FindFirstChild("Monsters"))
flameController:BindFolder(workspace:FindFirstChild("PlayerFlames"))
bindCameraDupedTokens(workspace.CurrentCamera or workspace:FindFirstChild("Camera"))

if workspace.GetPropertyChangedSignal then
	pcall(function()
		connections:Add("currentCameraChanged", workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(function()
			bindCameraDupedTokens(workspace.CurrentCamera or workspace:FindFirstChild("Camera"))
		end))
	end)
end

connections:Add("workspaceChildren", workspace.ChildAdded:Connect(function(child)
	if child.Name == "Gold Cogmower" and stepMonitor then
		stepMonitor(true)
	elseif child.Name == "Monsters" then
		bindMonstersFolder(child)
		if stepMonitor then
			stepMonitor(true)
		end
	elseif child.Name == "PlayerFlames" then
		flameController:BindFolder(child)
	elseif child.Name == "Camera" and not workspace.CurrentCamera then
		bindCameraDupedTokens(child)
	end
end))

connections:Add("workspaceRemoved", workspace.ChildRemoved:Connect(function(child)
	if child.Name == "Gold Cogmower" then
		monitorState.notified[child] = nil
		if stepMonitor then
			stepMonitor(true)
		end
	elseif child.Name == "PlayerFlames" then
		flameController:BindFolder(nil)
	end
end))

stepMonitor = function(skipMaintain)
	local list = goldCogMonitor:Scan()
	local liveMobs = {}
	for _, entry in ipairs(list) do
		liveMobs[entry.instance] = true
		if cfg.monitor.notifyOnGoldCog and not monitorState.notified[entry.instance] then
			monitorState.notified[entry.instance] = true
			ui.Notify("Golden Cogmower!", entry.fieldName)
		end
	end

	for mob in pairs(monitorState.notified) do
		if not liveMobs[mob] then
			monitorState.notified[mob] = nil
		end
	end

	monitorState.list = list
	monitorState.total = #list

	goldCountLabel.Text = "Active Golden Cogmowers: " .. #list

	local hudText
	if #list > 0 then
		monitorStroke.Color = goldColor
		monitorAccent.BackgroundColor3 = goldColor
		monitorDot.BackgroundColor3 = goldDot
		monitorMainText.TextColor3 = goldText
		monitorBadge.BackgroundColor3 = goldColor
		monitorBadge.TextColor3 = Color3.fromRGB(24, 24, 27)
		monitorBadge.Text = #list == 1 and "GOLD!" or ("GOLD x" .. #list)

		if #list == 1 then
			local g = list[1]
			hudText = string.format("GOLDEN COGMOWER: %s", g.fieldName)
			monitorStatusLabel.Text = "Status: GOLD COGMOWER in " .. g.fieldName
		else
			local fieldNames = {}
			for _, g in ipairs(list) do
				table.insert(fieldNames, g.fieldName)
			end
			local joined = table.concat(fieldNames, ", ")
			hudText = string.format("GOLDEN COGMOWERS (%d): %s", #list, joined)
			monitorStatusLabel.Text = string.format("Status: %d GOLD COGMOWERS (%s)", #list, joined)
		end
		monitorStatusLabel.TextColor3 = goldText
	else
		monitorStroke.Color = uicolor
		monitorAccent.BackgroundColor3 = uicolor
		monitorDot.BackgroundColor3 = Color3.fromRGB(115, 130, 155)
		monitorMainText.TextColor3 = Color3.fromRGB(215, 220, 230)
		monitorBadge.BackgroundColor3 = color_4
		monitorBadge.TextColor3 = Color3.fromRGB(220, 225, 235)
		monitorBadge.Text = "Gold: 0"
		hudText = "GOLDEN COGMOWER  |  None on map"
		monitorStatusLabel.Text = "Status: No Golden Cogmower on map"
		monitorStatusLabel.TextColor3 = Color3.new(1, 1, 1)
	end

	monitorMainText.Text = hudText
	local targetWidth = 440
	local okSize, measured = pcall(function()
		return TextService:GetTextSize(hudText, 13, Enum.Font.GothamBold, Vector2.new(1000, 38))
	end)
	if okSize and measured then
		targetWidth = math.clamp(measured.X + 135, 440, 680)
	end
	monitorFrame.Size = UDim2.new(0, targetWidth, 0, 38)

	if not skipMaintain then
		smileyHighlighter:Maintain()
	end
end

threads:Add("monitor", function()
	while not threads.closed do
		stepMonitor(false)
		task.wait(0.25)
	end
end)

local api
cleanup = function()
	threads:CancelAll()
	connections:CancelAll()
	walkSpeedController:Restore()
	decorationsController:Restore()
	flameController:ReleaseGyro()
	smileyHighlighter:ClearAll()
	if ScreenGui and ScreenGui.Parent then
		ScreenGui:Destroy()
	end
	if _G.rbcHelper == api then
		_G.rbcHelper = nil
	end
	if _G.rbcHelperLoading then
		_G.rbcHelperLoading = nil
	end
end

api = {
	gui = ScreenGui,
	cfg = cfg,
	controls = controls,
	Destroy = cleanup,
}

if isTestHarness then
	api.walkSpeedController = walkSpeedController
	api.goldCogMonitor = goldCogMonitor
	api.decorationsController = decorationsController
	api.flameController = flameController
	api.smileyHighlighter = smileyHighlighter
	api.monitorState = monitorState
	api.monitorFrame = monitorFrame
	api.monitorMainText = monitorMainText
	api.monitorBadge = monitorBadge
	api.stepMonitor = stepMonitor
	api.getSmileyTimerColor = getSmileyTimerColor
end

_G.rbcHelper = api
_G.rbcHelperLoading = nil

return api
