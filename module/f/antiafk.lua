-- Anti-AFK (AFKController Override Method)
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
local bypassMethod = "none"

-- === Helper Functions ===
local function tryOverrideAFKController()
    -- Method 1: Override AFKController module directly
    local success, err = pcall(function()
        local Controllers = ReplicatedStorage:WaitForChild("Controllers", 3)
        if not Controllers then return end
        
        local AFKController = Controllers:FindFirstChild("AFKController")
        if not AFKController or not AFKController:IsA("ModuleScript") then return end
        
        -- Try to require and neuter it
        local ok, module = pcall(require, AFKController)
        if ok and module then
            -- Override critical functions
            if module.SetTime then
                module.SetTime = function() end
                logger:debug("Overrode AFKController.SetTime")
            end
            
            if module.Start then
                local originalStart = module.Start
                module.Start = function(...)
                    -- Let it start, but neuter the timer check
                    originalStart(...)
                    -- Block the signal that fires RemoteEvent
                    pcall(function()
                        local Signal = require(ReplicatedStorage.Packages.Signal)
                        -- Find and block the AFK signal
                    end)
                end
                logger:debug("Overrode AFKController.Start")
            end
            
            bypassMethod = "module_override"
            return true
        end
    end)
    
    return success
end

local function tryBlockRemoteEvent()
    -- Method 2: Block ReconnectPlayer RemoteEvent
    local success = pcall(function()
        local Net = require(ReplicatedStorage.Packages.Net)
        local ReconnectEvent = Net:RemoteEvent("ReconnectPlayer")
        
        if ReconnectEvent and ReconnectEvent.FireServer then
            -- Neuter the FireServer function
            ReconnectEvent.FireServer = function()
                logger:debug("Blocked ReconnectPlayer FireServer attempt")
            end
            bypassMethod = "remote_block"
            return true
        end
    end)
    
    return success
end

local function tryGetConnections()
    -- Method 3: getconnections (original method)
    local GC = getconnections or get_signal_cons
    if not GC then return false end
    
    local success = pcall(function()
        for i,v in pairs(GC(LocalPlayer.Idled)) do
            if v["Disable"] then
                v["Disable"](v)
            elseif v["Disconnect"] then
                v["Disconnect"](v)
            end
        end
    end)
    
    if success then
        bypassMethod = "getconnections"
    end
    
    return success
end

local function setupIdledHook()
    -- Method 4: Fallback Idled hook
    if idleConn then return end
    
    idleConn = LocalPlayer.Idled:Connect(function()
        if UserInputService:GetFocusedTextBox() then return end
        pcall(function()
            VirtualUser:CaptureController()
            VirtualUser:ClickButton2(Vector2.new())
        end)
    end)
    
    bypassMethod = "idled_hook"
    return true
end

local function setupPeriodicReset()
    -- Method 5: Keep calling RemoveTime periodically
    task.spawn(function()
        while running do
            task.wait(300) -- Every 5 minutes (before 15 min threshold)
            
            pcall(function()
                local Controllers = ReplicatedStorage:WaitForChild("Controllers", 1)
                if not Controllers then return end
                
                local AFKController = Controllers:FindFirstChild("AFKController")
                if not AFKController then return end
                
                local ok, module = pcall(require, AFKController)
                if ok and module and module.RemoveTime then
                    module:RemoveTime("AntiAFK")
                    logger:debug("Reset AFK timer via RemoveTime")
                end
            end)
        end
    end)
end

-- === Lifecycle ===
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
    
    logger:info("Starting Anti-AFK with multiple bypass methods...")
    
    -- Try all methods (in order of effectiveness)
    local methods = {
        { name = "AFKController Override", func = tryOverrideAFKController },
        { name = "RemoteEvent Block", func = tryBlockRemoteEvent },
        { name = "getconnections", func = tryGetConnections },
        { name = "Idled Hook", func = setupIdledHook }
    }
    
    local successCount = 0
    for _, method in ipairs(methods) do
        local success = method.func()
        if success then
            logger:info("✓ " .. method.name .. " active")
            successCount = successCount + 1
        end
    end
    
    -- Always run periodic reset as extra safety
    setupPeriodicReset()
    logger:info("✓ Periodic Reset active")
    
    if successCount > 0 then
        logger:info(string.format("Anti-AFK active with %d method(s). Primary: %s", 
            successCount + 1, bypassMethod))
    else
        logger:warn("All bypass methods failed, relying on periodic reset only")
    end
end

function antiafkFeature:Stop()
    if not running then return end
    running = false
    if idleConn then 
        idleConn:Disconnect()
        idleConn = nil 
    end
    bypassMethod = "none"
    logger:info("Anti-AFK stopped")
end

function antiafkFeature:Cleanup()
    self:Stop()
end

function antiafkFeature:GetStatus()
    return {
        running = running,
        method = bypassMethod
    }
end

return antiafkFeature