-- Anti-AFK (Hybrid: getconnections + IdledHook + RemoteEvent block)
-- File: Fish-It/antiafkFeature.lua
local antiafkFeature = {}
antiafkFeature.__index = antiafkFeature

local logger = _G.Logger and _G.Logger.new("AntiAfk") or {
    debug = function() end,
    info = function() end,
    warn = function() end,
    error = function() end
}

--// Services
local Players          = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

--// Short refs
local LocalPlayer = Players.LocalPlayer

--// State
local inited   = false
local running  = false
local idleConn = nil
local VirtualUser = nil
local usingGetConnections = false
local hookedNet = false

-- === lifecycle ===
function antiafkFeature:Init(guiControls)
	local ok, vu = pcall(function()
		return game:GetService("VirtualUser")
	end)
	if not ok or not vu then
		logger:warn("VirtualUser tidak tersedia.")
		return false
	end
	VirtualUser = vu
	inited = true
	return true
end

function antiafkFeature:Start(config)
	if running then return end
	if not inited then
		local ok = self:Init()
		if not ok then return end
	end
	running = true

	-- Metode 1: Hook ReconnectPlayer RemoteEvent (PRIORITAS TERTINGGI)
if not hookedNet then
	task.spawn(function()
		local ok = pcall(function()
			local reconnectRE = ReplicatedStorage
				:WaitForChild("Packages", 5)
				:WaitForChild("_Index", 5)
				:WaitForChild("sleitnick_net@0.2.0", 5)
				:WaitForChild("net", 5)
				:WaitForChild("RE/ReconnectPlayer", 5)
			
			reconnectRE.FireServer = function(...)
				logger:warn("Blocked ReconnectPlayer")
			end
			
			hookedNet = true
			logger:info("ReconnectPlayer hooked")
		end)
		
		if not ok then
			logger:warn("Gagal hook ReconnectPlayer")
		end
	end)
end

	-- Metode 2: getconnections (disable existing Idled connections)
	local GC = getconnections or get_signal_cons
	if GC then
		pcall(function()
			for i,v in pairs(GC(LocalPlayer.Idled)) do
				if v["Disable"] then
					v["Disable"](v)
					usingGetConnections = true
				elseif v["Disconnect"] then
					v["Disconnect"](v)
					usingGetConnections = true
				end
			end
		end)
		if usingGetConnections then
			logger:info("Anti-AFK getconnections aktif")
		end
	end

	-- Metode 3: Fallback ke Idled hook (prevent Roblox kick + simulate activity)
	if not idleConn then
		idleConn = LocalPlayer.Idled:Connect(function()
			if UserInputService:GetFocusedTextBox() then return end
			pcall(function()
				VirtualUser:CaptureController()
				VirtualUser:ClickButton2(Vector2.new())
			end)
		end)
		logger:info("Anti-AFK Idled hook aktif")
	end
	
	logger:info("Anti-AFK full protection aktif (3 layer)")
end

function antiafkFeature:Stop()
	if not running then return end
	running = false
	if idleConn then idleConn:Disconnect(); idleConn = nil end
	usingGetConnections = false
end

function antiafkFeature:Cleanup()
	self:Stop()
end

return antiafkFeature