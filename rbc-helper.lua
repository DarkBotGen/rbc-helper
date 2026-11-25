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
local Lighting = getService("Lighting")

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
	perf = {
		lowGraphics = false,
		hideBees = false,
		filterParticles = false,
		hidePlayers = false,
		hideFlowers = false,
		hideBalloons = false,
	},
	flames = {
		enabled = false,
		shiftLockCompat = true,
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

	local localFxMod = ReplicatedStorage:FindFirstChild("LocalFX")
	if localFxMod then
		local ok, mod = pcall(require, localFxMod)
		if ok and type(mod) == "table" and type(mod.ClientRun) == "function" then
			gameApi.LocalFX = mod
		end
	end

	local eventsFolder = ReplicatedStorage:FindFirstChild("Events")
	local playerSettingsEv = eventsFolder and eventsFolder:FindFirstChild("PlayerSettingsEvent")
	if playerSettingsEv and playerSettingsEv.FireServer then
		gameApi.PlayerSettingsEvent = playerSettingsEv
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

local goldCogMonitor = {
	tracked = {},
	bound = false,
}

function goldCogMonitor:TrackIfMatch(inst)
	if inst and inst.Name == "Gold Cogmower" then
		self.tracked[inst] = self.tracked[inst] or {}
	end
end

function goldCogMonitor:Untrack(inst)
	if inst then
		self.tracked[inst] = nil
	end
end

function goldCogMonitor:BindContainer(container, tag)
	connections:Cancel("goldCogAdd:" .. tag)
	connections:Cancel("goldCogRem:" .. tag)
	if not container then
		return
	end
	for _, child in ipairs(container:GetChildren()) do
		if child.Name == "Gold Cogmower" then
			self.tracked[child] = self.tracked[child] or {}
		end
	end
	if container.ChildAdded then
		connections:Add("goldCogAdd:" .. tag, container.ChildAdded:Connect(function(child)
			self:TrackIfMatch(child)
		end))
	end
	if container.ChildRemoved then
		connections:Add("goldCogRem:" .. tag, container.ChildRemoved:Connect(function(child)
			self:Untrack(child)
		end))
	end
end

function goldCogMonitor:Init()
	self.bound = true
	self:BindContainer(workspace, "workspace")
	self:BindContainer(workspace:FindFirstChild("Monsters"), "monsters")
end

function goldCogMonitor:Clear()
	self.bound = false
	connections:Cancel("goldCogAdd:workspace")
	connections:Cancel("goldCogRem:workspace")
	connections:Cancel("goldCogAdd:monsters")
	connections:Cancel("goldCogRem:monsters")
	table.clear(self.tracked)
end

function goldCogMonitor:Scan()
	if not self.bound then
		self:Init()
	end
	local found = {}
	local stale = nil

	for child, rec in pairs(self.tracked) do
		local parent = child and child.Parent
		if not child or not parent or (parent ~= workspace and parent.Name ~= "Monsters") then
			stale = stale or {}
			table.insert(stale, child)
		else
			local pos = resolveMobPosition(child)
			local fieldName = rec.fieldName
			if pos and (not rec.lastPos or math.abs(pos.X - rec.lastPos.X) > 2 or math.abs(pos.Z - rec.lastPos.Z) > 2 or (rec.field and not rec.field.Parent)) then
				local field = getFieldAt(pos)
				rec.field = field
				rec.lastPos = pos
				fieldName = field and field.Name or "Unknown Field"
				rec.fieldName = fieldName
			end
			table.insert(found, {
				instance = child,
				pos = pos,
				fieldName = fieldName or "Unknown Field",
			})
		end
	end

	if stale then
		for _, obj in ipairs(stale) do
			self.tracked[obj] = nil
		end
	end

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

-- Reversible FPS Optimizer (No destructive :Destroy() on user world instances)
local BLOCKED_LOCAL_FX = {
	AquaWave = true,
	BeamShot = true,
	BeesmasLightsFallingStar = true,
	BubbleBloatCollect = true,
	CCRocket = true,
	CCRocketCrosshairs = true,
	CCRocketCrosshairsOld = true,
	DiamondDrain = true,
	EggShield = true,
	FallingCoal = true,
	FallingSnowflake = true,
	FieldRectPulses = true,
	GoldenRake = true,
	GummyStar = true,
	Gummyball = true,
	HoneyHammer = true,
	MechsquitoShot = true,
	MythicMeteor = true,
	OrbExplode = true,
	PartyPopper = true,
	PetalShuriken = true,
	PluckedPetal = true,
	PopStar = true,
	PorcelainDipperAbility = true,
	PuffshroomSporeThrow = true,
	RectPulse = true,
	RingPulse = true,
	SnowballThrow = true,
	SnowflakeBreeze = true,
	SpotlightBeam = true,
	StarSaw = true,
	StarShowerGuide = true,
	StickerTokenBeam = true,
	SweepArch = true,
	Triangulate = true,
	WaterRipple = true,
}

local LOW_GFX_SKIP_FOLDERS = {
	Collectibles = true,
	PlayerFlames = true,
	Particles = true,
	Happenings = true,
	PuffAssistantTokenHighlights = true,
	RbcHelperSmileyHighlights = true,
}

local function extractLocalFxName(arg1, arg2)
	if type(arg1) == "string" then
		return arg1
	end
	if type(arg2) == "string" then
		return arg2
	end
	return nil
end

local function isDescendantOf(inst, ancestor)
	local p = inst
	while p do
		if p == ancestor then
			return true
		end
		p = p.Parent
	end
	return false
end

local function isProtectedHighlightPart(inst)
	local p = inst and inst.Parent
	while p and p ~= workspace do
		if p.Name == "PuffAssistantTokenHighlights" or p.Name == "RbcHelperSmileyHighlights" then
			return true
		end
		p = p.Parent
	end
	local n = inst and inst.Name
	return n == "TokenBeacon" or n == "SmileyDropBeam" or n == "SmileyBeacon"
end

local fpsOptimizer = {
	savedLighting = nil,
	savedLightingIBL = nil,
	savedLightingEffects = {},
	savedAtmospheres = {},
	savedTerrain = nil,
	savedQualityLevel = nil,
	savedPollenPopUpSetting = nil,
	pollenPopUpChanged = false,
	savedPartVisuals = {},
	lowGfxActive = false,

	detachedBees = {},
	detachedBeeSet = {},
	hideBeesActive = false,

	savedParticles = {},
	filterParticlesActive = false,
	installedFxWrapper = nil,
	origFxClientRun = nil,

	savedPlayers = {},
	playerCharWatched = {},
	hidePlayersActive = false,

	detachedFlowers = nil,
	hideFlowersActive = false,

	detachedBalloons = nil,
	hideBalloonsActive = false,
}

function fpsOptimizer:ApplyLowGraphicsPart(desc)
	if not self.lowGfxActive or not desc or not desc.Parent or self.savedPartVisuals[desc] then
		return
	end
	if not desc:IsA("BasePart") or isProtectedHighlightPart(desc) then
		return
	end
	local char = localPlayer and localPlayer.Character
	if char and isDescendantOf(desc, char) then
		return
	end
	local okCheck, skip = pcall(function()
		local mat = desc.Material
		return mat == Enum.Material.Neon or mat == Enum.Material.ForceField or mat == Enum.Material.Glass
	end)
	if okCheck and skip then
		return
	end
	local okRead, origMat, origShadow, origRefl = pcall(function()
		return desc.Material, desc.CastShadow, desc.Reflectance
	end)
	if not okRead then
		return
	end
	self.savedPartVisuals[desc] = {
		Material = origMat,
		CastShadow = origShadow,
		Reflectance = origRefl,
	}
	pcall(function()
		desc.CastShadow = false
		desc.Reflectance = 0
		desc.Material = Enum.Material.SmoothPlastic
	end)
end

function fpsOptimizer:RestoreLowGraphics()
	self.lowGfxActive = false
	connections:Cancel("fpsLowGfxLighting")
	connections:Cancel("fpsLowGfxDescAdded")
	for inst, props in pairs(self.savedPartVisuals) do
		if inst and inst.Parent then
			pcall(function()
				inst.Material = props.Material
				inst.CastShadow = props.CastShadow
				inst.Reflectance = props.Reflectance
			end)
		end
	end
	table.clear(self.savedPartVisuals)

	if self.savedLighting and Lighting then
		local l = self.savedLighting
		self.savedLighting = nil
		pcall(function()
			Lighting.GlobalShadows = l.GlobalShadows
			Lighting.FogEnd = l.FogEnd
			Lighting.FogStart = l.FogStart
		end)
	end

	if self.savedLightingIBL and Lighting then
		local ibl = self.savedLightingIBL
		self.savedLightingIBL = nil
		if ibl.EnvironmentSpecularScale ~= nil then
			pcall(function()
				Lighting.EnvironmentSpecularScale = ibl.EnvironmentSpecularScale
			end)
		end
		if ibl.EnvironmentDiffuseScale ~= nil then
			pcall(function()
				Lighting.EnvironmentDiffuseScale = ibl.EnvironmentDiffuseScale
			end)
		end
		if ibl.ShadowSoftness ~= nil then
			pcall(function()
				Lighting.ShadowSoftness = ibl.ShadowSoftness
			end)
		end
	else
		self.savedLightingIBL = nil
	end

	for eff, origEnabled in pairs(self.savedLightingEffects) do
		if eff and eff.Parent then
			pcall(function()
				eff.Enabled = origEnabled
			end)
		end
	end
	table.clear(self.savedLightingEffects)

	for atmo, origDensity in pairs(self.savedAtmospheres) do
		if atmo and atmo.Parent then
			pcall(function()
				atmo.Density = origDensity
			end)
		end
	end
	table.clear(self.savedAtmospheres)

	if self.savedTerrain then
		local t = self.savedTerrain
		self.savedTerrain = nil
		local terrain = workspace:FindFirstChildOfClass("Terrain")
		if terrain then
			pcall(function()
				terrain.WaterWaveSize = t.WaterWaveSize
				terrain.WaterWaveSpeed = t.WaterWaveSpeed
				terrain.WaterReflectance = t.WaterReflectance
				terrain.WaterTransparency = t.WaterTransparency
				terrain.Decoration = t.Decoration
			end)
		end
	end

	if self.savedQualityLevel ~= nil and type(settings) == "function" then
		local origQ = self.savedQualityLevel
		self.savedQualityLevel = nil
		pcall(function()
			settings().Rendering.QualityLevel = origQ
		end)
	else
		self.savedQualityLevel = nil
	end

	if self.pollenPopUpChanged then
		local restoreVal = self.savedPollenPopUpSetting ~= false
		self.pollenPopUpChanged = false
		self.savedPollenPopUpSetting = nil
		if gameApi.PlayerSettingsEvent then
			pcall(secureCall, gameApi.PlayerSettingsEvent.FireServer, gameApi.PlayerSettingsEvent, "PollenPopUps", restoreVal)
		end
	end
end

function fpsOptimizer:SetLowGraphics(enabled)
	if not enabled then
		self:RestoreLowGraphics()
		return
	end
	if self.lowGfxActive then
		return
	end
	self.lowGfxActive = true

	if Lighting and not self.savedLighting then
		local okL, gs, fe, fs = pcall(function()
			return Lighting.GlobalShadows, Lighting.FogEnd, Lighting.FogStart
		end)
		if okL then
			self.savedLighting = { GlobalShadows = gs, FogEnd = fe, FogStart = fs }
		end
		pcall(function()
			Lighting.GlobalShadows = false
			Lighting.FogEnd = 1e9
			Lighting.FogStart = 1e9
		end)
		if not self.savedLightingIBL then
			local ibl = {}
			local okSpec, spec = pcall(function()
				return Lighting.EnvironmentSpecularScale
			end)
			if okSpec and type(spec) == "number" then
				ibl.EnvironmentSpecularScale = spec
				pcall(function()
					Lighting.EnvironmentSpecularScale = 0
				end)
			end
			local okDiff, diff = pcall(function()
				return Lighting.EnvironmentDiffuseScale
			end)
			if okDiff and type(diff) == "number" then
				ibl.EnvironmentDiffuseScale = diff
				pcall(function()
					Lighting.EnvironmentDiffuseScale = 0
				end)
			end
			local okSoft, soft = pcall(function()
				return Lighting.ShadowSoftness
			end)
			if okSoft and type(soft) == "number" then
				ibl.ShadowSoftness = soft
				pcall(function()
					Lighting.ShadowSoftness = 0
				end)
			end
			self.savedLightingIBL = ibl
		end
		for _, eff in ipairs(Lighting:GetChildren()) do
			if eff:IsA("PostEffect") then
				local okE, wasOn = pcall(function()
					return eff.Enabled
				end)
				if okE then
					self.savedLightingEffects[eff] = wasOn
					pcall(function()
						eff.Enabled = false
					end)
				end
			elseif eff:IsA("Atmosphere") then
				local okD, origD = pcall(function()
					return eff.Density
				end)
				if okD and type(origD) == "number" then
					self.savedAtmospheres[eff] = origD
					pcall(function()
						eff.Density = 0
					end)
				end
			end
		end
		if Lighting.Changed then
			connections:Cancel("fpsLowGfxLighting")
			connections:Add("fpsLowGfxLighting", Lighting.Changed:Connect(function()
				if not self.lowGfxActive then
					return
				end
				pcall(function()
					if Lighting.GlobalShadows ~= false then
						Lighting.GlobalShadows = false
					end
					if Lighting.FogEnd < 1e8 then
						Lighting.FogEnd = 1e9
					end
					if Lighting.FogStart < 1e8 then
						Lighting.FogStart = 1e9
					end
					if self.savedLightingIBL then
						if self.savedLightingIBL.EnvironmentSpecularScale ~= nil and Lighting.EnvironmentSpecularScale ~= 0 then
							Lighting.EnvironmentSpecularScale = 0
						end
						if self.savedLightingIBL.EnvironmentDiffuseScale ~= nil and Lighting.EnvironmentDiffuseScale ~= 0 then
							Lighting.EnvironmentDiffuseScale = 0
						end
					end
				end)
			end))
		end
	end

	local terrain = workspace:FindFirstChildOfClass("Terrain")
	if terrain and not self.savedTerrain then
		local okT, ws, wsp, wr, wt, dec = pcall(function()
			return terrain.WaterWaveSize, terrain.WaterWaveSpeed, terrain.WaterReflectance, terrain.WaterTransparency, terrain.Decoration
		end)
		if okT then
			self.savedTerrain = {
				WaterWaveSize = ws,
				WaterWaveSpeed = wsp,
				WaterReflectance = wr,
				WaterTransparency = wt,
				Decoration = dec,
			}
		end
		pcall(function()
			terrain.WaterWaveSize = 0
			terrain.WaterWaveSpeed = 0
			terrain.WaterReflectance = 0
			terrain.WaterTransparency = 0
			terrain.Decoration = false
		end)
	end

	if self.savedQualityLevel == nil and type(settings) == "function" then
		local okQ, qVal = pcall(function()
			local renderSettings = settings().Rendering
			local orig = renderSettings.QualityLevel
			renderSettings.QualityLevel = Enum.QualityLevel.Level01
			return orig
		end)
		if okQ then
			self.savedQualityLevel = qVal
		end
	end

	if not self.pollenPopUpChanged and gameApi.PlayerSettingsEvent then
		local curPopUp = gameApi:Cache({ "Settings", "PollenPopUps" })
		if curPopUp ~= false then
			self.savedPollenPopUpSetting = curPopUp == nil and true or curPopUp
			self.pollenPopUpChanged = true
			pcall(secureCall, gameApi.PlayerSettingsEvent.FireServer, gameApi.PlayerSettingsEvent, "PollenPopUps", false)
		end
	end

	for _, topChild in ipairs(workspace:GetChildren()) do
		if not LOW_GFX_SKIP_FOLDERS[topChild.Name] then
			if topChild:IsA("BasePart") then
				self:ApplyLowGraphicsPart(topChild)
			else
				for _, desc in ipairs(topChild:GetDescendants()) do
					if desc:IsA("BasePart") then
						self:ApplyLowGraphicsPart(desc)
					end
				end
			end
		end
	end

	connections:Cancel("fpsLowGfxDescAdded")
	if workspace.DescendantAdded then
		connections:Add("fpsLowGfxDescAdded", workspace.DescendantAdded:Connect(function(desc)
			if not self.lowGfxActive or not desc:IsA("BasePart") then
				return
			end
			local p = desc.Parent
			while p and p ~= workspace do
				if LOW_GFX_SKIP_FOLDERS[p.Name] then
					return
				end
				p = p.Parent
			end
			self:ApplyLowGraphicsPart(desc)
		end))
	end
end

function fpsOptimizer:DetachBee(bee)
	if not self.hideBeesActive or not bee or self.detachedBeeSet[bee] then
		return
	end
	local okParent, origParent = pcall(function()
		return bee.Parent
	end)
	if not okParent or not origParent then
		return
	end
	self.detachedBeeSet[bee] = true
	table.insert(self.detachedBees, { inst = bee, parent = origParent })
	pcall(function()
		bee.Parent = nil
	end)
end

function fpsOptimizer:RestoreBees()
	self.hideBeesActive = false
	connections:Cancel("fpsBeesAdded")
	for i = #self.detachedBees, 1, -1 do
		local entry = self.detachedBees[i]
		if entry.inst and entry.parent and entry.parent.Parent then
			pcall(function()
				entry.inst.Parent = entry.parent
			end)
		end
	end
	table.clear(self.detachedBees)
	table.clear(self.detachedBeeSet)
end

function fpsOptimizer:SetHideBees(enabled)
	if not enabled then
		self:RestoreBees()
		return
	end
	self.hideBeesActive = true
	local bees = workspace:FindFirstChild("Bees")
	if bees then
		for _, child in ipairs(bees:GetChildren()) do
			self:DetachBee(child)
		end
		if not connections:Get("fpsBeesAdded") then
			connections:Add("fpsBeesAdded", bees.ChildAdded:Connect(function(child)
				if task and task.defer then
					task.defer(function()
						if self.hideBeesActive then
							self:DetachBee(child)
						end
					end)
				else
					self:DetachBee(child)
				end
			end))
		end
	end
end

function fpsOptimizer:SyncParticlesInstance(inst)
	if not inst or not inst.Parent then
		return
	end
	if inst:IsA("ParticleEmitter") or inst:IsA("Trail") or inst:IsA("Beam") then
		if self.savedParticles[inst] == nil then
			local ok, wasOn = pcall(function()
				return inst.Enabled
			end)
			self.savedParticles[inst] = ok and wasOn or true
		end
		pcall(function()
			inst.Enabled = false
		end)
	end
end

function fpsOptimizer:RestoreParticles()
	self.filterParticlesActive = false
	_G.__rbcHelperLocalFxFilter = nil
	connections:Cancel("fpsParticlesDescAdded")
	connections:Cancel("fpsParticlesRemoved")
	for inst, origEnabled in pairs(self.savedParticles) do
		if inst and inst.Parent then
			pcall(function()
				inst.Enabled = origEnabled
			end)
		end
	end
	table.clear(self.savedParticles)
end

function fpsOptimizer:EnsureLocalFxHook()
	if not gameApi.LocalFX or type(gameApi.LocalFX.ClientRun) ~= "function" then
		return
	end
	if _G.__rbcHelperLocalFxHooked then
		return
	end
	if type(hookfunction) == "function" then
		local okHook = pcall(function()
			local origFn
			local hookFn = function(...)
				local filterFn = _G.__rbcHelperLocalFxFilter
				if filterFn then
					local okKeep, keep = pcall(filterFn, ...)
					if okKeep and keep == false then
						return nil
					end
				end
				return origFn(...)
			end
			if newcclosure then
				hookFn = newcclosure(hookFn)
			end
			origFn = hookfunction(gameApi.LocalFX.ClientRun, hookFn)
		end)
		if okHook then
			_G.__rbcHelperLocalFxHooked = true
			_G.__rbcHelperLocalFxHookMethod = "hookfunction"
			self.installedFxWrapper = true
			return
		end
	end
	if not _G.__rbcHelperLocalFxOrig then
		_G.__rbcHelperLocalFxOrig = gameApi.LocalFX.ClientRun
	end
	local origFn = _G.__rbcHelperLocalFxOrig
	local wrapper = function(...)
		local filterFn = _G.__rbcHelperLocalFxFilter
		if filterFn then
			local okKeep, keep = pcall(filterFn, ...)
			if okKeep and keep == false then
				return nil
			end
		end
		return origFn(...)
	end
	_G.__rbcHelperLocalFxHooked = wrapper
	_G.__rbcHelperLocalFxHookMethod = "table"
	gameApi.LocalFX.ClientRun = wrapper
	self.installedFxWrapper = wrapper
	self.origFxClientRun = origFn
end

function fpsOptimizer:UnhookLocalFx()
	_G.__rbcHelperLocalFxFilter = nil
	if _G.__rbcHelperLocalFxHookMethod == "table" then
		if gameApi.LocalFX and _G.__rbcHelperLocalFxOrig and gameApi.LocalFX.ClientRun == _G.__rbcHelperLocalFxHooked then
			gameApi.LocalFX.ClientRun = _G.__rbcHelperLocalFxOrig
		end
		_G.__rbcHelperLocalFxHooked = nil
		_G.__rbcHelperLocalFxOrig = nil
		_G.__rbcHelperLocalFxHookMethod = nil
	end
	self.installedFxWrapper = nil
	self.origFxClientRun = nil
end

function fpsOptimizer:ApplyParticlesFolder()
	local folder = workspace:FindFirstChild("Particles")
	if not folder then
		return
	end
	self:SyncParticlesInstance(folder)
	for _, desc in ipairs(folder:GetDescendants()) do
		self:SyncParticlesInstance(desc)
	end
	if not connections:Get("fpsParticlesDescAdded") and folder.DescendantAdded then
		connections:Add("fpsParticlesDescAdded", folder.DescendantAdded:Connect(function(desc)
			if self.filterParticlesActive then
				self:SyncParticlesInstance(desc)
			end
		end))
	end
	if not connections:Get("fpsParticlesRemoved") then
		connections:Add("fpsParticlesRemoved", folder.ChildRemoved:Connect(function(child)
			self.savedParticles[child] = nil
			for inst in pairs(self.savedParticles) do
				if not inst.Parent then
					self.savedParticles[inst] = nil
				end
			end
		end))
	end
end

function fpsOptimizer:SetFilterParticles(enabled)
	if not enabled then
		self:RestoreParticles()
		return
	end
	self.filterParticlesActive = true
	self:EnsureLocalFxHook()
	_G.__rbcHelperLocalFxFilter = function(arg1, arg2)
		local fxName = extractLocalFxName(arg1, arg2)
		if not fxName then
			return true
		end
		if BLOCKED_LOCAL_FX[fxName] then
			return false
		end
		return true
	end
	self:ApplyParticlesFolder()
end

function fpsOptimizer:HideCharacterVisuals(char)
	if not self.hidePlayersActive or not char or not char.Parent then
		return
	end
	local record = self.savedPlayers[char]
	if not record then
		record = {}
		self.savedPlayers[char] = record
	end
	local function hideInst(inst)
		if inst:IsA("BasePart") then
			if not record[inst] then
				local ok, origMod, origShadow = pcall(function()
					return inst.LocalTransparencyModifier, inst.CastShadow
				end)
				if ok then
					record[inst] = { LocalTransparencyModifier = origMod, CastShadow = origShadow }
				end
			end
			pcall(function()
				inst.LocalTransparencyModifier = 1
				inst.CastShadow = false
			end)
		elseif inst:IsA("Decal") or inst:IsA("Texture") then
			if not record[inst] then
				local ok, origT = pcall(function()
					return inst.Transparency
				end)
				if ok then
					record[inst] = { Transparency = origT }
				end
			end
			pcall(function()
				inst.Transparency = 1
			end)
		elseif inst:IsA("ParticleEmitter") or inst:IsA("Trail") or inst:IsA("Beam") or inst:IsA("BillboardGui") or inst:IsA("SurfaceGui") then
			if not record[inst] then
				local ok, origEn = pcall(function()
					return inst.Enabled
				end)
				if ok then
					record[inst] = { Enabled = origEn }
				end
			end
			pcall(function()
				inst.Enabled = false
			end)
		end
	end
	for _, desc in ipairs(char:GetDescendants()) do
		hideInst(desc)
	end
	local connKey = "fpsPlayerDesc:" .. tostring(char)
	if not connections:Get(connKey) and char.DescendantAdded then
		connections:Add(connKey, char.DescendantAdded:Connect(function(desc)
			if self.hidePlayersActive then
				hideInst(desc)
			end
		end))
	end
end

function fpsOptimizer:RestoreCharacterVisuals(char)
	connections:Cancel("fpsPlayerDesc:" .. tostring(char))
	local record = self.savedPlayers[char]
	if not record then
		return
	end
	self.savedPlayers[char] = nil
	if char and char.Parent then
		for inst, props in pairs(record) do
			if inst and inst.Parent then
				for prop, origVal in pairs(props) do
					pcall(function()
						inst[prop] = origVal
					end)
				end
			end
		end
	end
end

function fpsOptimizer:WatchOtherPlayer(player)
	if not player or player == localPlayer or self.playerCharWatched[player] then
		return
	end
	self.playerCharWatched[player] = true
	if player.Character then
		self:HideCharacterVisuals(player.Character)
	end
	if player.CharacterAdded then
		connections:Add("fpsPlayerCharAdded:" .. tostring(player), player.CharacterAdded:Connect(function(char)
			if self.hidePlayersActive then
				self:HideCharacterVisuals(char)
			end
		end))
	end
	if player.CharacterRemoving then
		connections:Add("fpsPlayerCharRem:" .. tostring(player), player.CharacterRemoving:Connect(function(char)
			self:RestoreCharacterVisuals(char)
		end))
	end
end

function fpsOptimizer:RestorePlayers()
	self.hidePlayersActive = false
	connections:Cancel("fpsPlayerAdded")
	connections:Cancel("fpsPlayerRemoving")
	for player in pairs(self.playerCharWatched) do
		connections:Cancel("fpsPlayerCharAdded:" .. tostring(player))
		connections:Cancel("fpsPlayerCharRem:" .. tostring(player))
	end
	table.clear(self.playerCharWatched)
	local chars = {}
	for char in pairs(self.savedPlayers) do
		table.insert(chars, char)
	end
	for _, char in ipairs(chars) do
		self:RestoreCharacterVisuals(char)
	end
end

function fpsOptimizer:SetHidePlayers(enabled)
	if not enabled then
		self:RestorePlayers()
		return
	end
	self.hidePlayersActive = true
	for _, player in ipairs(Players:GetPlayers()) do
		self:WatchOtherPlayer(player)
	end
	if not connections:Get("fpsPlayerAdded") and Players.PlayerAdded then
		connections:Add("fpsPlayerAdded", Players.PlayerAdded:Connect(function(player)
			if self.hidePlayersActive then
				self:WatchOtherPlayer(player)
			end
		end))
	end
	if not connections:Get("fpsPlayerRemoving") and Players.PlayerRemoving then
		connections:Add("fpsPlayerRemoving", Players.PlayerRemoving:Connect(function(player)
			connections:Cancel("fpsPlayerCharAdded:" .. tostring(player))
			connections:Cancel("fpsPlayerCharRem:" .. tostring(player))
			self.playerCharWatched[player] = nil
			if player.Character then
				self:RestoreCharacterVisuals(player.Character)
			end
		end))
	end
end

function fpsOptimizer:RestoreFlowers()
	self.hideFlowersActive = false
	local entry = self.detachedFlowers
	self.detachedFlowers = nil
	if entry and entry.inst and entry.parent then
		pcall(function()
			entry.inst.Parent = entry.parent
		end)
	end
end

function fpsOptimizer:SetHideFlowers(enabled)
	if not enabled then
		self:RestoreFlowers()
		return
	end
	self.hideFlowersActive = true
	local flowers = workspace:FindFirstChild("Flowers")
	if flowers and not self.detachedFlowers then
		local okParent, origParent = pcall(function()
			return flowers.Parent
		end)
		if okParent and origParent then
			self.detachedFlowers = { inst = flowers, parent = origParent }
			pcall(function()
				flowers.Parent = nil
			end)
		end
	end
end

function fpsOptimizer:RestoreBalloons()
	self.hideBalloonsActive = false
	local entry = self.detachedBalloons
	self.detachedBalloons = nil
	if entry and entry.inst and entry.parent and entry.parent.Parent then
		pcall(function()
			entry.inst.Parent = entry.parent
		end)
	end
end

function fpsOptimizer:SetHideBalloons(enabled)
	if not enabled then
		self:RestoreBalloons()
		return
	end
	self.hideBalloonsActive = true
	local balloons = workspace:FindFirstChild("Balloons")
	local fieldBalloons = balloons and balloons:FindFirstChild("FieldBalloons")
	if fieldBalloons and not self.detachedBalloons then
		local okParent, origParent = pcall(function()
			return fieldBalloons.Parent
		end)
		if okParent and origParent then
			self.detachedBalloons = { inst = fieldBalloons, parent = origParent }
			pcall(function()
				fieldBalloons.Parent = nil
			end)
		end
	end
end

function fpsOptimizer:RestoreAll()
	self:RestoreLowGraphics()
	self:RestoreBees()
	self:RestoreParticles()
	self:UnhookLocalFx()
	self:RestorePlayers()
	self:RestoreFlowers()
	self:RestoreBalloons()
end

-- Feature D: Standalone BodyGyro Auto-Face Flames & Refresh (Shift Lock compatible)
local FLAME_RENDER_STEP_NAME = "RbcHelperFlameFace"

local function isShiftLockActive()
	local ok, active = pcall(function()
		return UserInputService.MouseBehavior == Enum.MouseBehavior.LockCenter
			or UserInputService.MouseIcon == "rbxasset://textures/MouseLockedCursor.png"
	end)
	return ok and active == true
end

local function isClimbing(hum)
	if not hum then
		return false
	end
	local ok, state = pcall(function()
		return hum:GetState() == Enum.HumanoidStateType.Climbing
	end)
	return ok and state == true
end

local flameController = {
	tracked = {},
	gyro = nil,
	managedHumanoid = nil,
	savedAutoRotate = nil,
	renderBound = false,
	stopDig = false,
	statusLabel = nil,
	lastStatusText = nil,
	cachedField = nil,
	cachedFieldPos = nil,
	cachedFieldTime = 0,
	currentTarget = nil,
	lastScanTime = 0,
	cachedStopDig = false,
	cachedModeLabel = "idle",
}

function flameController:InvalidateTarget()
	self.currentTarget = nil
	self.lastScanTime = 0
end

function flameController:GetCachedField(rootPos, now)
	if self.cachedField and self.cachedField.Parent and self.cachedFieldPos and (now - self.cachedFieldTime) < 0.1 then
		local dx = rootPos.X - self.cachedFieldPos.X
		local dy = rootPos.Y - self.cachedFieldPos.Y
		local dz = rootPos.Z - self.cachedFieldPos.Z
		if dx * dx + dy * dy + dz * dz < 9 then
			return self.cachedField
		end
	end
	local field = getFieldAt(rootPos)
	self.cachedField = field
	self.cachedFieldPos = rootPos
	self.cachedFieldTime = now
	return field
end

function flameController:SuppressAutoRotate(hum)
	if not hum then
		return
	end
	if self.managedHumanoid and self.managedHumanoid ~= hum then
		self:RestoreAutoRotate()
	end
	if self.managedHumanoid ~= hum then
		local okRead, orig = pcall(function()
			return hum.AutoRotate
		end)
		self.savedAutoRotate = (okRead and type(orig) == "boolean") and orig or true
		self.managedHumanoid = hum
	end
	pcall(function()
		hum.AutoRotate = false
	end)
end

function flameController:RestoreAutoRotate()
	local hum = self.managedHumanoid
	local saved = self.savedAutoRotate
	self.managedHumanoid = nil
	self.savedAutoRotate = nil
	if hum and hum.Parent and saved ~= nil then
		pcall(function()
			hum.AutoRotate = saved
		end)
	end
end

function flameController:UnbindRenderStep()
	connections:Cancel("flameFace")
	if self.renderBound and RunService.UnbindFromRenderStep then
		pcall(function()
			RunService:UnbindFromRenderStep(FLAME_RENDER_STEP_NAME)
		end)
		self.renderBound = false
	end
end

local function inspectFlame(flameObj, record, now)
	if not flameObj or not flameObj.Parent then
		return nil
	end
	if type(record) ~= "table" then
		record = { spawnTime = record }
	end
	local pos = getInstancePosition(flameObj)
	if not pos then
		return nil
	end
	local pf = record.pf
	if not (pf and pf.Parent) then
		pf = flameObj:FindFirstChild("PF")
		record.pf = pf
	end
	if not pf then
		return nil
	end
	local okValid, sizeVal = pcall(function()
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

	if not record.fieldPos or math.abs(pos.X - record.fieldPos.X) > 2 or math.abs(pos.Z - record.fieldPos.Z) > 2 or (record.field and not record.field.Parent) then
		record.field = getFieldAt(pos)
		record.fieldPos = pos
	end

	local age
	if type(record.spawnTime) == "number" then
		age = math.max(0, now - record.spawnTime)
	else
		local estRem = 1 + math.clamp((sizeVal - 1.4) / 0.35, 0, 1) * 5
		age = math.max(0, 6 - estRem)
	end
	return pos, age, record.field
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
			g.P = 20000
			g.D = 400
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
	self:RestoreAutoRotate()
	if self.gyro then
		pcall(function()
			self.gyro.MaxTorque = Vector3.new(0, 0, 0)
			self.gyro:Destroy()
		end)
		self.gyro = nil
	end
end

function flameController:ZeroTorque()
	self:RestoreAutoRotate()
	if self.gyro then
		pcall(function()
			self.gyro.MaxTorque = Vector3.new(0, 0, 0)
		end)
	end
end

function flameController:BindFolder(folder)
	connections:Cancel("flamesAdded")
	connections:Cancel("flamesRemoved")
	self:InvalidateTarget()
	if not folder then
		table.clear(self.tracked)
		return
	end
	connections:Add("flamesAdded", folder.ChildAdded:Connect(function(child)
		self.tracked[child] = { spawnTime = os.clock() }
	end))
	connections:Add("flamesRemoved", folder.ChildRemoved:Connect(function(child)
		if self.currentTarget and self.currentTarget.obj == child then
			self:InvalidateTarget()
		end
		self.tracked[child] = nil
	end))
	for _, child in ipairs(folder:GetChildren()) do
		if self.tracked[child] == nil then
			self.tracked[child] = { spawnTime = false }
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

	for flameObj, record in pairs(self.tracked) do
		if not flameObj or not flameObj.Parent then
			stale = stale or {}
			table.insert(stale, flameObj)
		else
			if type(record) ~= "table" then
				record = { spawnTime = record }
				self.tracked[flameObj] = record
			end
			local pos, age, flameField = inspectFlame(flameObj, record, now)
			if pos then
				local dx = pos.X - rootPos.X
				local dz = pos.Z - rootPos.Z
				local dist = math.sqrt(dx * dx + dz * dz)
				if dist < maxRange and flameField == field then
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
		self:InvalidateTarget()
		self.stopDig = false
		self:SetStatusText("Target: Disabled")
		return
	end

	local rootPart = getRootPart()
	local hum = getHumanoid()
	if not rootPart or not hum or not hum.Parent or hum.Health <= 0 then
		self:ZeroTorque()
		self:InvalidateTarget()
		self.stopDig = false
		self:SetStatusText("Target: Waiting for character")
		return
	end

	local rootPos = getInstancePosition(rootPart)
	local currentClock = now or os.clock()
	local field = rootPos and self:GetCachedField(rootPos, currentClock) or nil
	if not field then
		self:ZeroTorque()
		self:InvalidateTarget()
		self.stopDig = false
		self:SetStatusText("Target: Not in a field")
		return
	end

	local targetEntry = self.currentTarget
	local stopDig = self.cachedStopDig
	local modeLabel = self.cachedModeLabel
	local useCached = false

	if targetEntry and targetEntry.obj and targetEntry.obj.Parent and (currentClock - self.lastScanTime) < 0.05 then
		local rec = self.tracked[targetEntry.obj]
		if rec then
			local pos, age, flameField = inspectFlame(targetEntry.obj, rec, currentClock)
			if pos and flameField == field then
				local maxRange = math.clamp(tonumber(cfg.flames.maxRange) or 30, 15, 45)
				local refreshAge = math.clamp(tonumber(cfg.flames.refreshAge) or 3.0, 1.5, 4.5)
				local dx = pos.X - rootPos.X
				local dz = pos.Z - rootPos.Z
				local dist = math.sqrt(dx * dx + dz * dz)
				if dist < maxRange and (not cfg.flames.onlyRefreshReady or not cfg.flames.refreshPriority or age >= refreshAge) then
					targetEntry.pos = pos
					targetEntry.age = age
					targetEntry.dist = dist
					useCached = true
				end
			end
		end
	end

	if not useCached then
		targetEntry, stopDig, modeLabel = self:SelectTarget(rootPos, field, currentClock)
		self.currentTarget = targetEntry
		self.cachedStopDig = stopDig
		self.cachedModeLabel = modeLabel
		self.lastScanTime = currentClock
	end

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

	if cfg.flames.shiftLockCompat then
		self:SuppressAutoRotate(hum)
	else
		self:RestoreAutoRotate()
	end

	local flatTarget = Vector3.new(targetEntry.pos.X, rootPos.Y, targetEntry.pos.Z)
	local lookCf = CFrame.lookAt and CFrame.lookAt(rootPos, flatTarget) or CFrame.new(rootPos, flatTarget)
	local gyro = self:EnsureGyro(rootPart)
	if gyro then
		pcall(function()
			gyro.MaxTorque = Vector3.new(0, math.huge, 0)
			gyro.CFrame = lookCf
		end)
	end
	if cfg.flames.shiftLockCompat and isShiftLockActive() and not isClimbing(hum) then
		pcall(function()
			rootPart.CFrame = lookCf
		end)
	end

	self:SetStatusText(string.format("Target: %s (%.1fs, %.0fst)", modeLabel == "refresh" and "Refreshing" or "Facing", targetEntry.age, targetEntry.dist))
end

function flameController:SetEnabled(enabled)
	self:UnbindRenderStep()
	self:InvalidateTarget()
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
				self.tracked[child] = { spawnTime = false }
			end
		end
	end
	self:Step(os.clock())
	if RunService.BindToRenderStep then
		local okPrio, camPrio = pcall(function()
			return Enum.RenderPriority.Camera.Value
		end)
		local priority = (okPrio and type(camPrio) == "number") and (camPrio + 1) or 201
		local okBind = pcall(function()
			RunService:BindToRenderStep(FLAME_RENDER_STEP_NAME, priority, function()
				self:Step(os.clock())
			end)
		end)
		if okBind then
			self.renderBound = true
			return
		end
	end
	local sig = RunService.RenderStepped or RunService.Heartbeat
	if sig then
		connections:Add("flameFace", sig:Connect(function()
			self:Step(os.clock())
		end))
	end
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

local function makeVerticalCylinderCFrame(x, y, z)
	if CFrame.Angles then
		local ok, cf = pcall(function()
			return CFrame.new(x, y, z) * CFrame.Angles(0, 0, math.rad(90))
		end)
		if ok and cf then
			return cf
		end
	end
	return CFrame.new(x, y, z)
end

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
					self:UpdateAll(os.clock(), false)
				end))
			end
		end
	else
		connections:Cancel("smileyTick")
	end
end

function smileyHighlighter:UpdateEntry(entry, now, force)
	if not entry then
		return
	end
	local currentNow = now or os.clock()
	local remaining = math.max(0, entry.endClock - currentNow)
	local isRedNow = remaining < 0.9
	local enabled = cfg.smiley.enabled == true
	local showBeam = enabled and cfg.smiley.beam == true
	local showTimer = enabled and cfg.smiley.timer == true

	if not force
		and entry.lastVisualUpdate ~= nil
		and (currentNow - entry.lastVisualUpdate) < 0.05
		and entry.lastIsRed == isRedNow
		and entry.lastEnabled == enabled
		and entry.lastShowBeam == showBeam
		and entry.lastShowTimer == showTimer then
		return
	end

	entry.lastVisualUpdate = currentNow
	local pos = getInstancePosition(entry.token)
	if pos and entry.beamPart then
		local last = entry.lastPos
		if not last or (pos.X - last.X) ^ 2 + (pos.Y - last.Y) ^ 2 + (pos.Z - last.Z) ^ 2 >= 0.0025 then
			entry.lastPos = pos
			pcall(function()
				entry.beamPart.CFrame = makeVerticalCylinderCFrame(pos.X, pos.Y - 4.5, pos.Z)
			end)
		end
	end

	local color, isRed = getSmileyTimerColor(remaining, entry.totalDuration)
	local timerText = string.format("%.1fs", remaining)
	local titleText = isRed and "TOO LATE" or "SMILEY DUPED"
	local barRatio = math.clamp(remaining / math.max(0.01, entry.totalDuration or 10), 0, 1)

	local colorChanged = force or not entry.lastColor or math.abs(entry.lastColor.R - color.R) > 0.002 or math.abs(entry.lastColor.G - color.G) > 0.002 or math.abs(entry.lastColor.B - color.B) > 0.002
	local enabledChanged = force or entry.lastEnabled ~= enabled
	local beamChanged = force or entry.lastShowBeam ~= showBeam
	local timerVisChanged = force or entry.lastShowTimer ~= showTimer
	local titleChanged = force or entry.lastTitleText ~= titleText
	local timerTextChanged = force or entry.lastTimerText ~= timerText
	local barChanged = force or not entry.lastBarRatio or math.abs(barRatio - entry.lastBarRatio) >= 0.01

	entry.lastIsRed = isRedNow
	entry.lastEnabled = enabled
	entry.lastShowBeam = showBeam
	entry.lastShowTimer = showTimer
	entry.lastColor = color
	entry.lastTitleText = titleText
	entry.lastTimerText = timerText
	if barChanged then
		entry.lastBarRatio = barRatio
	end

	if entry.highlight and (colorChanged or enabledChanged) then
		pcall(function()
			if colorChanged then
				entry.highlight.FillColor = color
			end
			if enabledChanged then
				entry.highlight.Enabled = enabled
			end
		end)
	end
	if entry.beamPart and (colorChanged or beamChanged) then
		pcall(function()
			if colorChanged then
				entry.beamPart.Color = color
			end
			if beamChanged then
				entry.beamPart.Transparency = showBeam and 0.32 or 1
			end
		end)
	end
	if entry.beamAdornment and (colorChanged or beamChanged) then
		pcall(function()
			if colorChanged then
				entry.beamAdornment.Color3 = color
			end
			if beamChanged then
				entry.beamAdornment.Visible = showBeam
			end
		end)
	end
	if entry.billboard and timerVisChanged then
		pcall(function()
			entry.billboard.Enabled = showTimer
		end)
	end
	if entry.stroke and colorChanged then
		pcall(function()
			entry.stroke.Color = color
		end)
	end
	if entry.titleLabel and (titleChanged or colorChanged) then
		pcall(function()
			if titleChanged then
				entry.titleLabel.Text = titleText
			end
			if colorChanged then
				entry.titleLabel.TextColor3 = color
			end
		end)
	end
	if entry.timerLabel and (timerTextChanged or colorChanged) then
		pcall(function()
			if timerTextChanged then
				entry.timerLabel.Text = timerText
			end
			if colorChanged then
				entry.timerLabel.TextColor3 = color
			end
		end)
	end
	if entry.barFill and (barChanged or colorChanged) then
		pcall(function()
			if barChanged then
				entry.barFill.Size = UDim2.new(barRatio, 0, 1, 0)
			end
			if colorChanged then
				entry.barFill.BackgroundColor3 = color
			end
		end)
	end
end

function smileyHighlighter:Apply(token, spawnClock)
	if not token or not token.Parent or not cfg.smiley.enabled then
		return
	end
	local now = os.clock()
	if self.active[token] then
		self:UpdateEntry(self.active[token], now, true)
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
	local initRatio = math.clamp(initialRem / math.max(0.01, totalDuration), 0, 1)

	local highlight
	local okHl, createdHl = pcall(function()
		local hl = Instance.new("Highlight")
		hl.Name = "SmileyHighlight"
		hl.Adornee = token
		hl.FillColor = initColor
		hl.FillTransparency = 0.58
		hl.OutlineColor = Color3.fromRGB(255, 255, 255)
		hl.OutlineTransparency = 0.05
		hl.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
		hl.Enabled = cfg.smiley.enabled
		hl.Parent = entryFolder
		return hl
	end)
	if okHl then
		highlight = createdHl
	end

	local beamPart, beamAdornment
	local okBeam, createdBeam, createdAdorn = pcall(function()
		local part = Instance.new("Part")
		part.Name = "SmileyDropBeam"
		part.Shape = Enum.PartType.Cylinder
		part.Anchored = true
		part.CanCollide = false
		part.CanTouch = false
		part.CanQuery = false
		part.CastShadow = false
		part.Material = Enum.Material.Neon
		part.Color = initColor
		part.Size = Vector3.new(13, 0.24, 0.24)
		part.Transparency = (cfg.smiley.enabled and cfg.smiley.beam) and 0.32 or 1
		if pos then
			part.CFrame = makeVerticalCylinderCFrame(pos.X, pos.Y - 4.5, pos.Z)
		end
		part.Parent = entryFolder

		local adorn = Instance.new("CylinderHandleAdornment")
		adorn.Name = "SmileyDropBeamXRay"
		adorn.Adornee = part
		adorn.AlwaysOnTop = true
		adorn.ZIndex = 5
		adorn.Color3 = initColor
		adorn.Radius = 0.09
		adorn.Height = 13
		adorn.Transparency = 0.68
		adorn.Visible = cfg.smiley.enabled and cfg.smiley.beam
		if CFrame.Angles then
			pcall(function()
				adorn.CFrame = CFrame.Angles(0, math.rad(90), 0)
			end)
		end
		adorn.Parent = part

		return part, adorn
	end)
	if okBeam then
		beamPart = createdBeam
		beamAdornment = createdAdorn
	end

	local billboard, stroke, titleLabel, timerLabel, barFill
	local okGui, cGui, cStroke, cTitle, cTimer, cBarFill = pcall(function()
		local gui = Instance.new("BillboardGui")
		gui.Name = "SmileyTimerGui"
		gui.Adornee = token
		gui.AlwaysOnTop = true
		gui.LightInfluence = 0
		gui.MaxDistance = 260
		gui.Size = UDim2.new(0, 108, 0, 44)
		gui.StudsOffsetWorldSpace = Vector3.new(0, 3.4, 0)
		gui.Enabled = cfg.smiley.enabled and cfg.smiley.timer
		gui.Parent = entryFolder

		local frame = Instance.new("Frame")
		frame.Name = "TagFrame"
		frame.BackgroundColor3 = Color3.fromRGB(13, 15, 20)
		frame.BackgroundTransparency = 0.14
		frame.BorderSizePixel = 0
		frame.ClipsDescendants = true
		frame.Size = UDim2.new(1, 0, 1, 0)
		frame.Parent = gui

		local corner = Instance.new("UICorner")
		corner.CornerRadius = UDim.new(0, 6)
		corner.Parent = frame

		local uiStroke = Instance.new("UIStroke")
		uiStroke.Thickness = 1.3
		uiStroke.Color = initColor
		uiStroke.Transparency = 0.2
		uiStroke.Parent = frame

		local tLbl = Instance.new("TextLabel")
		tLbl.Name = "TitleLabel"
		tLbl.BackgroundTransparency = 1
		tLbl.Font = Enum.Font.GothamBold
		tLbl.Position = UDim2.new(0, 4, 0, 2)
		tLbl.Size = UDim2.new(1, -8, 0, 13)
		tLbl.Text = initRed and "TOO LATE" or "SMILEY DUPED"
		tLbl.TextColor3 = initColor
		tLbl.TextSize = 9.5
		tLbl.Parent = frame

		local timeLbl = Instance.new("TextLabel")
		timeLbl.Name = "TimerLabel"
		timeLbl.BackgroundTransparency = 1
		timeLbl.Font = Enum.Font.GothamBold
		timeLbl.Position = UDim2.new(0, 4, 0, 14)
		timeLbl.Size = UDim2.new(1, -8, 0, 22)
		timeLbl.Text = string.format("%.1fs", initialRem)
		timeLbl.TextColor3 = initColor
		timeLbl.TextSize = 15
		timeLbl.Parent = frame

		local track = Instance.new("Frame")
		track.Name = "ProgressTrack"
		track.BackgroundColor3 = Color3.fromRGB(30, 34, 45)
		track.BorderSizePixel = 0
		track.Position = UDim2.new(0, 0, 1, -3)
		track.Size = UDim2.new(1, 0, 0, 3)
		track.Parent = frame

		local fill = Instance.new("Frame")
		fill.Name = "ProgressFill"
		fill.BackgroundColor3 = initColor
		fill.BorderSizePixel = 0
		fill.Size = UDim2.new(initRatio, 0, 1, 0)
		fill.Parent = track

		return gui, uiStroke, tLbl, timeLbl, fill
	end)
	if okGui then
		billboard = cGui
		stroke = cStroke
		titleLabel = cTitle
		timerLabel = cTimer
		barFill = cBarFill
	end

	self.active[token] = {
		token = token,
		spawnClock = spawnClock,
		totalDuration = totalDuration,
		endClock = endClock,
		isFallback = isFallback,
		folder = entryFolder,
		highlight = highlight,
		beamPart = beamPart,
		beamAdornment = beamAdornment,
		billboard = billboard,
		stroke = stroke,
		titleLabel = titleLabel,
		timerLabel = timerLabel,
		barFill = barFill,
		lastBarRatio = initRatio,
		lastPos = pos,
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
			self:UpdateEntry(entry, now, true)
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
	self:UpdateAll(os.clock(), true)
end

function smileyHighlighter:UpdateAll(now, force)
	local currentNow = now or os.clock()
	local stale = nil
	for token, entry in pairs(self.active) do
		if not token or not token.Parent then
			stale = stale or {}
			table.insert(stale, token)
		else
			self:UpdateEntry(entry, currentNow, force)
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

	self:UpdateAll(now, false)
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

local color_ = Color3.fromRGB(16, 18, 24)
local color_2 = Color3.fromRGB(22, 25, 33)
local color_3 = Color3.fromRGB(30, 34, 45)
local color_4 = Color3.fromRGB(38, 43, 56)
local color_5 = Color3.fromRGB(58, 66, 86)
local uicolor = _G.uicolor or Color3.fromRGB(59, 130, 246)
local TWEEN_FAST = TweenInfo.new(0.12, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
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
windowCorner.CornerRadius = UDim.new(0, 8)
windowCorner.Parent = window

local windowStroke = Instance.new("UIStroke")
windowStroke.Thickness = 1
windowStroke.Color = Color3.fromRGB(54, 62, 82)
windowStroke.Transparency = 0.35
windowStroke.Parent = window

-- Shared Atlas+ UI Templates
do
	local bar = Instance.new("Frame")
	bar.Name = "Bar"
	bar.BackgroundColor3 = uicolor
	bar.BorderSizePixel = 0
	bar.Size = UDim2.new(1, 0, 0, 25)
	uiParts.bar = bar

	local barCorner = Instance.new("UICorner")
	barCorner.CornerRadius = UDim.new(0, 8)
	barCorner.Parent = bar

	local barTitle = Instance.new("TextLabel")
	barTitle.Name = "Title"
	barTitle.BackgroundTransparency = 1
	barTitle.Font = Enum.Font.GothamBold
	barTitle.TextColor3 = Color3.fromRGB(255, 255, 255)
	barTitle.TextSize = 13.5
	barTitle.TextXAlignment = Enum.TextXAlignment.Left
	barTitle.Position = UDim2.new(0, 10, 0, 0)
	barTitle.Size = UDim2.new(0.8, -10, 0, 25)
	barTitle.Parent = bar

	local barIndicator = Instance.new("TextButton")
	barIndicator.Name = "Indicator"
	barIndicator.AutoButtonColor = false
	barIndicator.BackgroundTransparency = 1
	barIndicator.Font = Enum.Font.GothamBold
	barIndicator.Text = "▾"
	barIndicator.TextColor3 = Color3.new(1, 1, 1)
	barIndicator.TextSize = 14
	barIndicator.Position = UDim2.new(1, -26, 0, 2)
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
	tabCorner.CornerRadius = UDim.new(0, 5)
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
	folderBtn.TextColor3 = Color3.fromRGB(228, 232, 240)
	folderBtn.TextSize = 12.5
	folderBtn.TextXAlignment = Enum.TextXAlignment.Left
	folderBtn.Size = UDim2.new(1, 0, 0, 23)
	folderBtn.Parent = folder

	local folderCorner = Instance.new("UICorner")
	folderCorner.Name = "UICorner"
	folderCorner.CornerRadius = UDim.new(0, 5)
	folderCorner.Parent = folderBtn

	local folderIndicator = Instance.new("TextLabel")
	folderIndicator.Name = "Indicator"
	folderIndicator.BackgroundTransparency = 1
	folderIndicator.Font = Enum.Font.GothamBold
	folderIndicator.Text = "▸"
	folderIndicator.TextColor3 = Color3.fromRGB(180, 190, 210)
	folderIndicator.TextSize = 12
	folderIndicator.Position = UDim2.new(1, -24, 0, 1)
	folderIndicator.Size = UDim2.new(0, 20, 0, 20)
	folderIndicator.Parent = folderBtn

	local folderBox = Instance.new("Frame")
	folderBox.Name = "Box"
	folderBox.BackgroundColor3 = color_2
	folderBox.BackgroundTransparency = 1
	folderBox.BorderSizePixel = 0
	folderBox.ClipsDescendants = true
	folderBox.Position = UDim2.new(0, 0, 0, 21)
	folderBox.Size = UDim2.new(1, 0, 1, -21)
	folderBox.Parent = folder

	local boxCorner = Instance.new("UICorner")
	boxCorner.Name = "UICorner"
	boxCorner.CornerRadius = UDim.new(0, 5)
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
	btnTemplate.TextSize = 12.5
	btnTemplate.Size = UDim2.new(0, 130, 0, 20)
	uiParts.button = btnTemplate

	local btnCorner = Instance.new("UICorner")
	btnCorner.Name = "UICorner"
	btnCorner.CornerRadius = UDim.new(0, 5)
	btnCorner.Parent = btnTemplate

	local labelTemplate = Instance.new("TextLabel")
	labelTemplate.Name = "Label"
	labelTemplate.BackgroundTransparency = 1
	labelTemplate.Font = Enum.Font.GothamSemibold
	labelTemplate.TextColor3 = Color3.fromRGB(225, 230, 240)
	labelTemplate.TextSize = 12
	labelTemplate.TextXAlignment = Enum.TextXAlignment.Left
	labelTemplate.TextTruncate = Enum.TextTruncate.AtEnd
	uiParts.label = labelTemplate

	local switchTemplate = Instance.new("TextButton")
	switchTemplate.Name = "Switch"
	switchTemplate.AutoButtonColor = false
	switchTemplate.BackgroundTransparency = 1
	switchTemplate.BorderSizePixel = 0
	switchTemplate.Text = ""
	switchTemplate.Size = UDim2.new(1, -20, 0, 20)
	uiParts.switch = switchTemplate

	local switchTrack = Instance.new("Frame")
	switchTrack.Name = "Switch"
	switchTrack.BackgroundColor3 = color_4
	switchTrack.BackgroundTransparency = 0
	switchTrack.BorderSizePixel = 0
	switchTrack.Position = UDim2.new(0, 0, 0.5, -8)
	switchTrack.Size = UDim2.new(0, 32, 0, 16)
	switchTrack.Parent = switchTemplate

	local switchCorner = Instance.new("UICorner")
	switchCorner.Name = "UICorner"
	switchCorner.CornerRadius = UDim.new(1, 0)
	switchCorner.Parent = switchTrack

	local switchKnob = Instance.new("Frame")
	switchKnob.Name = "Knob"
	switchKnob.BackgroundColor3 = Color3.fromRGB(235, 240, 248)
	switchKnob.BorderSizePixel = 0
	switchKnob.Position = UDim2.new(0, 2, 0.5, -6)
	switchKnob.Size = UDim2.new(0, 12, 0, 12)
	switchKnob.Parent = switchTrack

	local knobCorner = Instance.new("UICorner")
	knobCorner.Name = "UICorner"
	knobCorner.CornerRadius = UDim.new(1, 0)
	knobCorner.Parent = switchKnob

	local switchTitle = Instance.new("TextLabel")
	switchTitle.Name = "Title"
	switchTitle.BackgroundTransparency = 1
	switchTitle.Position = UDim2.new(0, 42, 0, 0)
	switchTitle.Size = UDim2.new(1, -42, 0, 20)
	switchTitle.Font = Enum.Font.GothamSemibold
	switchTitle.TextColor3 = Color3.fromRGB(205, 212, 224)
	switchTitle.TextSize = 12.5
	switchTitle.TextXAlignment = Enum.TextXAlignment.Left
	switchTitle.TextTruncate = Enum.TextTruncate.AtEnd
	switchTitle.Parent = switchTemplate

	local sliderTemplate = Instance.new("Frame")
	sliderTemplate.Name = "Slider"
	sliderTemplate.BackgroundColor3 = color_4
	sliderTemplate.BorderSizePixel = 0
	sliderTemplate.ClipsDescendants = true
	sliderTemplate.Size = UDim2.new(1, -15, 0, 20)
	uiParts.slider = sliderTemplate

	local sliderCorner = Instance.new("UICorner")
	sliderCorner.Name = "UICorner"
	sliderCorner.CornerRadius = UDim.new(0, 5)
	sliderCorner.Parent = sliderTemplate

	local sliderStroke = Instance.new("UIStroke")
	sliderStroke.Thickness = 1
	sliderStroke.Color = color_5
	sliderStroke.Transparency = 0.35
	sliderStroke.Parent = sliderTemplate

	local sliderHitbox = Instance.new("TextButton")
	sliderHitbox.Name = "Button"
	sliderHitbox.BackgroundTransparency = 1
	sliderHitbox.Text = ""
	sliderHitbox.Size = UDim2.new(1, 0, 1, 0)
	sliderHitbox.ZIndex = 2
	sliderHitbox.Parent = sliderTemplate

	local sliderIndicator = Instance.new("Frame")
	sliderIndicator.Name = "Indicator"
	sliderIndicator.BackgroundColor3 = uicolor
	sliderIndicator.BackgroundTransparency = 0.18
	sliderIndicator.BorderSizePixel = 0
	sliderIndicator.Size = UDim2.new(0, 0, 1, 0)
	sliderIndicator.Parent = sliderTemplate

	local indicatorCorner = Instance.new("UICorner")
	indicatorCorner.Name = "UICorner"
	indicatorCorner.CornerRadius = UDim.new(0, 5)
	indicatorCorner.Parent = sliderIndicator

	local sliderTitle = Instance.new("TextLabel")
	sliderTitle.Name = "Title"
	sliderTitle.BackgroundTransparency = 1
	sliderTitle.Font = Enum.Font.GothamBold
	sliderTitle.TextColor3 = Color3.fromRGB(232, 236, 244)
	sliderTitle.TextSize = 12.5
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
	sliderValue.TextColor3 = Color3.fromRGB(232, 236, 244)
	sliderValue.TextSize = 12.5
	sliderValue.Position = UDim2.new(1, -45, 0.5, -10)
	sliderValue.Size = UDim2.new(0, 40, 0, 20)
	sliderValue.TextXAlignment = Enum.TextXAlignment.Right
	sliderValue.ZIndex = 3
	sliderValue.Parent = sliderTemplate
end

-- Top bar for main window
local tabButtonsHolder = nil
local activeTabFrame = nil
local activeTabFrame2 = nil
local activeTabButton = nil
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
		indicator.Text = windowVisible and "▾" or "▸"
		TweenService:Create(window, TWEEN_FAST, {
			Size = windowVisible and UDim2.new(0, windowSize.X, 0, windowSize.Y) or UDim2.new(0, windowSize.X, 0, 25),
		}):Play()
		tabButtonsHolder.Visible = windowVisible
		if activeTabFrame then
			activeTabFrame.Visible = windowVisible
		end
		if activeTabFrame2 then
			activeTabFrame2.Visible = windowVisible
		end
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
tabButtonsHolder = Instance.new("Frame")
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

activeTabFrame = nil
activeTabFrame2 = nil
activeTabButton = nil
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
	local toast = Instance.new("Frame")
	toast.Name = "Tooltip"
	toast.BackgroundColor3 = Color3.fromRGB(16, 18, 24)
	toast.BackgroundTransparency = 0.06
	toast.BorderSizePixel = 0
	toast.ClipsDescendants = true
	toast.AnchorPoint = Vector2.new(1, 1)
	toast.Position = UDim2.new(1, -8, 1, -8)
	toast.Size = UDim2.new(0, newlineCount == 2 and 272 or 262, 0, newlineCount == 2 and 78 or 58)
	toast.Parent = ScreenGui

	local toastCorner = Instance.new("UICorner")
	toastCorner.CornerRadius = UDim.new(0, 7)
	toastCorner.Parent = toast

	local toastStroke = Instance.new("UIStroke")
	toastStroke.Thickness = 1.2
	toastStroke.Color = uicolor
	toastStroke.Transparency = 0.25
	toastStroke.Parent = toast

	local toastAccent = Instance.new("Frame")
	toastAccent.Name = "Accent"
	toastAccent.BackgroundColor3 = uicolor
	toastAccent.BorderSizePixel = 0
	toastAccent.Size = UDim2.new(0, 3, 1, 0)
	toastAccent.Parent = toast

	local tTitle = Instance.new("TextLabel")
	tTitle.Name = "Title"
	tTitle.BackgroundTransparency = 1
	tTitle.Font = Enum.Font.GothamBold
	tTitle.Text = tostring(title)
	tTitle.TextColor3 = Color3.new(1, 1, 1)
	tTitle.TextSize = 13.5
	tTitle.TextXAlignment = Enum.TextXAlignment.Left
	tTitle.Position = UDim2.new(0, 14, 0, newlineCount > 0 and 8 or 9)
	tTitle.Size = UDim2.new(1, -22, 0, 19)
	tTitle.Parent = toast

	local tDesc = Instance.new("TextLabel")
	tDesc.Name = "Description"
	tDesc.BackgroundTransparency = 1
	tDesc.Font = Enum.Font.GothamSemibold
	tDesc.Text = tostring(description)
	tDesc.TextColor3 = Color3.fromRGB(205, 212, 224)
	tDesc.TextSize = 12.5
	tDesc.TextXAlignment = Enum.TextXAlignment.Left
	tDesc.TextTruncate = Enum.TextTruncate.AtEnd
	tDesc.Position = UDim2.new(0, 14, 0, newlineCount == 2 and 37 or 29)
	tDesc.Size = UDim2.new(1, -22, 0, 19)
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
			TweenService:Create(tabBtn, TWEEN_FAST, { BackgroundTransparency = 0.93 }):Play()
		end
	end)

	tabBtn.MouseLeave:Connect(function()
		if activeTabButton ~= tabBtn then
			TweenService:Create(tabBtn, TWEEN_FAST, { BackgroundTransparency = 0.96 }):Play()
		end
	end)

	tabBtn.MouseButton1Click:Connect(function()
		if activeTabFrame and activeTabButton ~= tabBtn then
			activeTabFrame.Parent = nil
			if activeTabFrame2 then
				activeTabFrame2.Parent = nil
			end
			TweenService:Create(activeTabButton, TWEEN_FAST, { BackgroundTransparency = 0.96 }):Play()
			TweenService:Create(tabBtn, TWEEN_FAST, { BackgroundTransparency = 0.85 }):Play()
			scrollLeft.Visible = windowVisible
			scrollLeft.Parent = window
			activeTabButton = tabBtn
			activeTabFrame = scrollLeft
			activeTabFrame2 = scrollRight
			if scrollRight then
				scrollRight.Visible = windowVisible
				scrollRight.Parent = window
			end
		end
	end)

	if startActive then
		tabBtn.BackgroundTransparency = 0.85
		scrollLeft.Visible = windowVisible
		scrollLeft.Parent = window
		activeTabButton = tabBtn
		activeTabFrame = scrollLeft
		if scrollRight then
			scrollRight.Visible = windowVisible
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
			local track = row.Switch
			local knob = track.Knob
			local titleLabel = row.Title
			titleLabel.Text = text
			row.Parent = box

			local function renderSwitch(state, instant)
				local targetColor = state and uicolor or color_4
				local targetPos = state and UDim2.new(0, 18, 0.5, -6) or UDim2.new(0, 2, 0.5, -6)
				local targetTitleColor = state and Color3.fromRGB(235, 240, 248) or Color3.fromRGB(205, 212, 224)
				titleLabel.TextColor3 = targetTitleColor
				if instant then
					track.BackgroundColor3 = targetColor
					knob.Position = targetPos
				else
					TweenService:Create(track, TWEEN_FAST, { BackgroundColor3 = targetColor }):Play()
					TweenService:Create(knob, TWEEN_FAST, { Position = targetPos }):Play()
				end
			end

			local isOn = false
			local configTable = (configSource and type(configSource) == "string" and cfg[configSource]) or configSource
			if configTable and configTable[configKey] then
				isOn = true
				renderSwitch(true, true)
				if callback then
					callback(true)
				end
			else
				renderSwitch(false, true)
			end

			row.MouseButton1Click:Connect(function()
				isOn = not isOn
				renderSwitch(isOn, false)
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
				renderSwitch(isOn, true)
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
				local fillRatio = (maxValue > minValue) and math.clamp((val - minValue) / (maxValue - minValue), 0, 1) or 0
				indicator.Size = UDim2.new(fillRatio, 0, 1, 0)
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
				local val = formatSliderVal(tonumber(newValue) or minValue)
				local fillRatio = (maxValue > minValue) and math.clamp((val - minValue) / (maxValue - minValue), 0, 1) or 0
				indicator.Size = UDim2.new(fillRatio, 0, 1, 0)
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
			box.BackgroundTransparency = openState and 0.25 or 1
			box.ClipsDescendants = not openState
			isOpen = openState
			headerBtn.Indicator.Text = openState and "▾" or "▸"
			TweenService:Create(folderFrame, TWEEN_FAST, {
				Size = openState and UDim2.new(1, 0, 0, measuredHeight) or UDim2.new(1, 0, 0, 23),
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
				folderFrame.Size = isOpen and UDim2.new(1, 0, 0, measuredHeight) or UDim2.new(1, 0, 0, 23)
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
monitorFrame.Size = UDim2.new(0, 440, 0, 34)
monitorFrame.ZIndex = 10
monitorFrame.Visible = cfg.monitor.enabled
monitorFrame.Parent = ScreenGui

local monitorCorner = Instance.new("UICorner")
monitorCorner.CornerRadius = UDim.new(0, 8)
monitorCorner.Parent = monitorFrame

local monitorStroke = Instance.new("UIStroke")
monitorStroke.Thickness = 1.2
monitorStroke.Color = uicolor
monitorStroke.Transparency = 0.2
monitorStroke.Parent = monitorFrame

local monitorAccent = Instance.new("Frame")
monitorAccent.Name = "Accent"
monitorAccent.BackgroundColor3 = uicolor
monitorAccent.BorderSizePixel = 0
monitorAccent.Size = UDim2.new(1, 0, 0, 2)
monitorAccent.ZIndex = 11
monitorAccent.Parent = monitorFrame

local monitorDotHalo = Instance.new("Frame")
monitorDotHalo.Name = "DotHalo"
monitorDotHalo.BackgroundColor3 = Color3.fromRGB(115, 130, 155)
monitorDotHalo.BackgroundTransparency = 0.72
monitorDotHalo.BorderSizePixel = 0
monitorDotHalo.Position = UDim2.new(0, 10, 0.5, -6)
monitorDotHalo.Size = UDim2.new(0, 14, 0, 14)
monitorDotHalo.ZIndex = 11
monitorDotHalo.Parent = monitorFrame

local monitorDotHaloCorner = Instance.new("UICorner")
monitorDotHaloCorner.CornerRadius = UDim.new(1, 0)
monitorDotHaloCorner.Parent = monitorDotHalo

local monitorDot = Instance.new("Frame")
monitorDot.Name = "Dot"
monitorDot.BackgroundColor3 = Color3.fromRGB(115, 130, 155)
monitorDot.BorderSizePixel = 0
monitorDot.Position = UDim2.new(0, 13, 0.5, -3)
monitorDot.Size = UDim2.new(0, 8, 0, 8)
monitorDot.ZIndex = 12
monitorDot.Parent = monitorFrame

local monitorDotCorner = Instance.new("UICorner")
monitorDotCorner.CornerRadius = UDim.new(1, 0)
monitorDotCorner.Parent = monitorDot

local monitorMainText = Instance.new("TextLabel")
monitorMainText.Name = "StatusText"
monitorMainText.BackgroundTransparency = 1
monitorMainText.Font = Enum.Font.GothamBold
monitorMainText.Text = "GOLDEN COGMOWER  |  None on map"
monitorMainText.TextColor3 = Color3.fromRGB(220, 226, 236)
monitorMainText.TextSize = 12.5
monitorMainText.TextXAlignment = Enum.TextXAlignment.Left
monitorMainText.TextTruncate = Enum.TextTruncate.AtEnd
monitorMainText.Position = UDim2.new(0, 32, 0, 2)
monitorMainText.Size = UDim2.new(1, -122, 1, -2)
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
monitorBadge.Size = UDim2.new(0, 74, 0, 20)
monitorBadge.ZIndex = 11
monitorBadge.Parent = monitorFrame

local monitorBadgeCorner = Instance.new("UICorner")
monitorBadgeCorner.CornerRadius = UDim.new(1, 0)
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

controls.lowGraphics = worldFolder.AddSwitch("Low Graphics / Anti-Lag", function(enabled)
	fpsOptimizer:SetLowGraphics(enabled)
end, "perf", "lowGraphics")

controls.hideBees = worldFolder.AddSwitch("Hide Bees", function(enabled)
	fpsOptimizer:SetHideBees(enabled)
end, "perf", "hideBees")

controls.filterParticles = worldFolder.AddSwitch("Filter Particles (Keep Key FX)", function(enabled)
	fpsOptimizer:SetFilterParticles(enabled)
end, "perf", "filterParticles")

controls.hidePlayers = worldFolder.AddSwitch("Hide Other Players", function(enabled)
	fpsOptimizer:SetHidePlayers(enabled)
end, "perf", "hidePlayers")

controls.hideFlowers = worldFolder.AddSwitch("Hide Flowers", function(enabled)
	fpsOptimizer:SetHideFlowers(enabled)
end, "perf", "hideFlowers")

controls.hideBalloons = worldFolder.AddSwitch("Hide Field Balloons", function(enabled)
	fpsOptimizer:SetHideBalloons(enabled)
end, "perf", "hideBalloons")

worldFolder.Toggle(true, true)

-- Right Column: Auto Face Flames (BodyGyro), Digital Smiley Tokens
local flameFolder = helperTab.AddFolder("Auto Face Flames (BodyGyro)", true)
local flameStatusLabel = flameFolder.AddLabel("Target: Disabled")
flameController.statusLabel = flameStatusLabel

controls.flamesEnabled = flameFolder.AddSwitch("Enable Flame Auto-Face", function(enabled)
	flameController:SetEnabled(enabled)
end, "flames", "enabled")

controls.flamesShiftLockCompat = flameFolder.AddSwitch("Shift Lock Compatible", nil, "flames", "shiftLockCompat")
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
	controls.lowGraphics.Set(cfg.perf.lowGraphics)
	controls.hideBees.Set(cfg.perf.hideBees)
	controls.filterParticles.Set(cfg.perf.filterParticles)
	controls.hidePlayers.Set(cfg.perf.hidePlayers)
	controls.hideFlowers.Set(cfg.perf.hideFlowers)
	controls.hideBalloons.Set(cfg.perf.hideBalloons)
	controls.flamesEnabled.Set(cfg.flames.enabled)
	controls.flamesShiftLockCompat.Set(cfg.flames.shiftLockCompat)
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
	goldCogMonitor:BindContainer(folder, "monsters")
	if not folder then
		return
	end
	connections:Add("monstersAdded", folder.ChildAdded:Connect(function(child)
		if child.Name == "Gold Cogmower" then
			goldCogMonitor:TrackIfMatch(child)
			if stepMonitor then
				stepMonitor(true)
			end
		end
	end))
	connections:Add("monstersRemoved", folder.ChildRemoved:Connect(function(child)
		if child.Name == "Gold Cogmower" then
			goldCogMonitor:Untrack(child)
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
goldCogMonitor:Init()
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
	if child.Name == "Gold Cogmower" then
		goldCogMonitor:TrackIfMatch(child)
		if stepMonitor then
			stepMonitor(true)
		end
	elseif child.Name == "Monsters" then
		bindMonstersFolder(child)
		if stepMonitor then
			stepMonitor(true)
		end
	elseif child.Name == "PlayerFlames" then
		flameController:BindFolder(child)
	elseif child.Name == "Bees" and cfg.perf.hideBees then
		fpsOptimizer:SetHideBees(true)
	elseif child.Name == "Particles" and cfg.perf.filterParticles then
		fpsOptimizer:ApplyParticlesFolder()
	elseif child.Name == "Flowers" and cfg.perf.hideFlowers then
		if task and task.defer then
			task.defer(function()
				if cfg.perf.hideFlowers then
					fpsOptimizer:SetHideFlowers(true)
				end
			end)
		else
			fpsOptimizer:SetHideFlowers(true)
		end
	elseif child.Name == "Balloons" and cfg.perf.hideBalloons then
		if task and task.defer then
			task.defer(function()
				if cfg.perf.hideBalloons then
					fpsOptimizer:SetHideBalloons(true)
				end
			end)
		else
			fpsOptimizer:SetHideBalloons(true)
		end
	elseif child.Name == "Camera" and not workspace.CurrentCamera then
		bindCameraDupedTokens(child)
	end
end))

connections:Add("workspaceRemoved", workspace.ChildRemoved:Connect(function(child)
	if child.Name == "Gold Cogmower" then
		goldCogMonitor:Untrack(child)
		monitorState.notified[child] = nil
		if stepMonitor then
			stepMonitor(true)
		end
	elseif child.Name == "Monsters" then
		bindMonstersFolder(nil)
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

	local countText = "Active Golden Cogmowers: " .. #list
	if monitorState.lastCountText ~= countText then
		monitorState.lastCountText = countText
		goldCountLabel.Text = countText
	end

	local hudText
	local badgeText
	local statusText
	local hasGold = #list > 0

	if hasGold then
		badgeText = #list == 1 and "GOLD!" or ("GOLD x" .. #list)
		if #list == 1 then
			local g = list[1]
			hudText = string.format("GOLDEN COGMOWER: %s", g.fieldName)
			statusText = "Status: GOLD COGMOWER in " .. g.fieldName
		else
			local fieldNames = {}
			for _, g in ipairs(list) do
				table.insert(fieldNames, g.fieldName)
			end
			local joined = table.concat(fieldNames, ", ")
			hudText = string.format("GOLDEN COGMOWERS (%d): %s", #list, joined)
			statusText = string.format("Status: %d GOLD COGMOWERS (%s)", #list, joined)
		end
	else
		badgeText = "Gold: 0"
		hudText = "GOLDEN COGMOWER  |  None on map"
		statusText = "Status: No Golden Cogmower on map"
	end

	if monitorState.lastHasGold ~= hasGold then
		monitorState.lastHasGold = hasGold
		if hasGold then
			monitorStroke.Color = goldColor
			monitorAccent.BackgroundColor3 = goldColor
			monitorDotHalo.BackgroundColor3 = goldDot
			monitorDot.BackgroundColor3 = goldDot
			monitorMainText.TextColor3 = goldText
			monitorBadge.BackgroundColor3 = goldColor
			monitorBadge.TextColor3 = Color3.fromRGB(24, 24, 27)
			monitorStatusLabel.TextColor3 = goldText
		else
			monitorStroke.Color = uicolor
			monitorAccent.BackgroundColor3 = uicolor
			monitorDotHalo.BackgroundColor3 = Color3.fromRGB(115, 130, 155)
			monitorDot.BackgroundColor3 = Color3.fromRGB(115, 130, 155)
			monitorMainText.TextColor3 = Color3.fromRGB(220, 226, 236)
			monitorBadge.BackgroundColor3 = color_4
			monitorBadge.TextColor3 = Color3.fromRGB(220, 225, 235)
			monitorStatusLabel.TextColor3 = Color3.fromRGB(225, 230, 240)
		end
	end

	if monitorState.lastBadgeText ~= badgeText then
		monitorState.lastBadgeText = badgeText
		monitorBadge.Text = badgeText
	end
	if monitorState.lastStatusText ~= statusText then
		monitorState.lastStatusText = statusText
		monitorStatusLabel.Text = statusText
	end
	if monitorState.lastHudText ~= hudText then
		monitorState.lastHudText = hudText
		monitorMainText.Text = hudText
		local targetWidth = 440
		local okSize, measured = pcall(function()
			return TextService:GetTextSize(hudText, 12.5, Enum.Font.GothamBold, Vector2.new(1000, 34))
		end)
		if okSize and measured then
			targetWidth = math.clamp(measured.X + 135, 440, 680)
		end
		monitorFrame.Size = UDim2.new(0, targetWidth, 0, 34)
	end

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
	fpsOptimizer:RestoreAll()
	goldCogMonitor:Clear()
	flameController:UnbindRenderStep()
	flameController:ReleaseGyro()
	flameController:InvalidateTarget()
	table.clear(flameController.tracked)
	flameController.cachedField = nil
	flameController.cachedFieldPos = nil
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
	api.fpsOptimizer = fpsOptimizer
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
