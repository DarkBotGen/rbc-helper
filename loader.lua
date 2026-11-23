local http = game:GetService("HttpService")
local raw = "https://raw.githubusercontent.com/DarkBotGen/rbc-helper/"
if _G.rbcHelperLoading then return end

local ok, revision = pcall(function()
	local ref = http:JSONDecode(game:HttpGet("https://api.github.com/repos/DarkBotGen/rbc-helper/git/ref/heads/main"))
	local sha = ref and ref.object and ref.object.sha
	assert(type(sha) == "string" and #sha == 40 and sha:match("^[%da-f]+$"))
	return sha
end)

local fetched, source = false, nil
if ok then
	fetched, source = pcall(function()
		return game:HttpGet(raw .. revision .. "/rbc-helper.lua")
	end)
end
if not fetched then
	fetched, source = pcall(function()
		return game:HttpGet(raw .. "main/rbc-helper.lua")
	end)
end
if not fetched then
	error("RBC Helper download failed: " .. tostring(source), 0)
end

local run, err = loadstring(source)
if not run then
	error("RBC Helper compile failed: " .. tostring(err), 0)
end

local previous = _G.rbcHelper
local started, result = xpcall(run, debug.traceback)
if not started then
	local partial = _G.rbcHelper
	if partial and partial ~= previous and type(partial.Destroy) == "function" then
		pcall(function()
			partial:Destroy()
		end)
	end
	_G.rbcHelperLoading = nil
	error("RBC Helper startup failed: " .. tostring(result), 0)
end
return result
