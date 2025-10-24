-- Anti-AFK (Multi-Layer Bypass for AFKController)
-- File: Fish-It/antiafkFeature.lua
-- Supports: Roblox native AFK + custom AFKController bypass

local antiafkFeature = {}
antiafkFeature.__index = antiafkFeature

--// Logger Setup
local logger = _G.Logger and _G.Logger.new("AntiAFK") or {
    debug = function(self, msg) print("[AntiAFK][DEBUG]", msg) end,
    info = function(self, msg) print("[AntiAFK][INFO]", msg) end,
    warn = function(self, msg) warn("[AntiAFK][WARN]", msg) end,
    error = function(self, msg) warn("[AntiAFK][ERROR]", msg) end
}

--// Services
local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

--// References
local LocalPlayer = Players.LocalPlayer

--// State Variables
local inited = false
local running = false
local idleConn = nil
local periodicTask = nil
local VirtualUser = nil

--// Bypass Status Tracking
local bypassStatus = {
    moduleOverride = false,
    remoteBlock = false,
    getConnections = false,
    periodicReset = false,
    idledHook = false
}

--// ========================================
--// BYPASS METHOD 1: Module Override
--// ========================================
local function tryOverrideAFKController()
    local success = pcall(function()
        local Controllers = ReplicatedStorage:FindFirstChild("Controllers")
        if not Controllers then 
            logger:debug("Controllers folder not found")
            return 
        end
        
        local AFKController = Controllers:FindFirstChild("AFKController")
        if not AFKController or not AFKController:IsA("ModuleScript") then
            logger:debug("AFKController module not found")
            return
        end
        
        -- Wait a bit for module to be loaded
        task.wait(0.5)
        
        local ok, module = pcall(require, AFKController)
        if not ok or not module then
            logger:debug("Failed to require AFKController: " .. tostring(module))
            return
        end
        
        logger:debug("AFKController module loaded successfully")
        
        -- Override SetTime to do nothing
        if module.SetTime then
            module.SetTime = function(self, arg)
                logger:debug("Blocked SetTime call with arg: " .. tostring(arg))
            end
            logger:info("✓ Overrode AFKController.SetTime")
        end
        
        -- Override RemoveTime to always succeed
        if module.RemoveTime then
            local original = module.RemoveTime
            module.RemoveTime = function(self, reason)
                logger:debug("RemoveTime called: " .. tostring(reason))
                pcall(original, self, reason)
            end
            logger:info("✓ Overrode AFKController.RemoveTime")
        end
        
        -- Neuter Start function
        if module.Start then
            local originalStart = module.Start
            module.Start = function(self, ...)
                logger:debug("AFKController.Start intercepted")
                -- Let it initialize but neuter the timer
                pcall(originalStart, self, ...)
                
                -- Try to find and disable the signal
                task.spawn(function()
                    task.wait(1)
                    pcall(function()
                        if module.SetTime then
                            module.SetTime = function() end
                        end
                    end)
                end)
            end
            logger:info("✓ Overrode AFKController.Start")
        end
        
        bypassStatus.moduleOverride = true
    end)
    
    if not success then
        logger:debug("Module override attempt failed")
    end
    
    return bypassStatus.moduleOverride
end

--// ========================================
--// BYPASS METHOD 2: Block RemoteEvent
--// ========================================
local function tryBlockRemoteEvent()
    local success = pcall(function()
        -- Try to find and block the Net package
        local Packages = ReplicatedStorage:FindFirstChild("Packages")
        if not Packages then
            logger:debug("Packages folder not found")
            return
        end
        
        local NetModule = Packages:FindFirstChild("Net")
        if not NetModule then
            logger:debug("Net module not found")
            return
        end
        
        task.wait(0.5)
        
        local ok, Net = pcall(require, NetModule)
        if not ok or not Net then
            logger:debug("Failed to require Net module")
            return
        end
        
        -- Get RemoteEvent reference
        local ReconnectEvent = Net:RemoteEvent("ReconnectPlayer")
        
        if ReconnectEvent then
            -- Store original for logging
            local originalFire = ReconnectEvent.FireServer
            
            -- Neuter FireServer
            ReconnectEvent.FireServer = function(...)
                logger:warn("🛡️ Blocked ReconnectPlayer FireServer attempt!")
                -- Do nothing, preventing the kick
            end
            
            logger:info("✓ Blocked ReconnectPlayer RemoteEvent")
            bypassStatus.remoteBlock = true
        else
            logger:debug("ReconnectPlayer event not found")
        end
    end)
    
    if not success then
        logger:debug("RemoteEvent block attempt failed")
    end
    
    return bypassStatus.remoteBlock
end

--// ========================================
--// BYPASS METHOD 3: getconnections
--// ========================================
local function tryGetConnections()
    local GC = getconnections or get_signal_cons
    if not GC then
        logger:debug("getconnections not available in executor")
        return false
    end
    
    local success = pcall(function()
        local connections = GC(LocalPlayer.Idled)
        local disabledCount = 0
        
        for i, conn in pairs(connections) do
            if conn.Disable then
                conn:Disable()
                disabledCount = disabledCount + 1
            elseif conn.Disconnect then
                conn:Disconnect()
                disabledCount = disabledCount + 1
            end
        end
        
        if disabledCount > 0 then
            logger:info("✓ Disabled " .. disabledCount .. " Idled connections via getconnections")
            bypassStatus.getConnections = true
        else
            logger:debug("No connections found to disable")
        end
    end)
    
    if not success then
        logger:debug("getconnections attempt failed")
    end
    
    return bypassStatus.getConnections
end

--// ========================================
--// BYPASS METHOD 4: Periodic Reset
--// ========================================
local function setupPeriodicReset()
    if periodicTask then return end
    
    periodicTask = task.spawn(function()
        while running do
            -- Wait 4 minutes (well before 15 min threshold)
            task.wait(240)
            
            -- Try to call RemoveTime on AFKController
            pcall(function()
                local Controllers = ReplicatedStorage:FindFirstChild("Controllers")
                if not Controllers then return end
                
                local AFKController = Controllers:FindFirstChild("AFKController")
                if not AFKController then return end
                
                local ok, module = pcall(require, AFKController)
                if ok and module and module.RemoveTime then
                    module:RemoveTime("PeriodicReset")
                    logger:debug("🔄 Reset AFK timer via RemoveTime()")
                end
            end)
            
            -- Also simulate activity via VirtualUser
            if VirtualUser then
                pcall(function()
                    VirtualUser:CaptureController()
                    VirtualUser:ClickButton2(Vector2.new())
                    logger:debug("🖱️ Simulated mouse click")
                end)
            end
        end
    end)
    
    bypassStatus.periodicReset = true
    logger:info("✓ Periodic reset active (every 4 minutes)")
    return true
end

--// ========================================
--// BYPASS METHOD 5: Idled Hook (Fallback)
--// ========================================
local function setupIdledHook()
    if idleConn then return end
    
    idleConn = LocalPlayer.Idled:Connect(function()
        -- Don't interfere if user is typing
        if UserInputService:GetFocusedTextBox() then return end
        
        pcall(function()
            VirtualUser:CaptureController()
            VirtualUser:ClickButton2(Vector2.new())
            logger:debug("🖱️ Idled hook triggered - simulated click")
        end)
    end)
    
    bypassStatus.idledHook = true
    logger:info("✓ Idled hook active (fallback method)")
    return true
end

--// ========================================
--// LIFECYCLE FUNCTIONS
--// ========================================

function antiafkFeature:Init(guiControls)
    if inited then return true end
    
    -- Get VirtualUser service
    local ok, vu = pcall(function()
        return game:GetService("VirtualUser")
    end)
    
    if not ok or not vu then
        logger:error("VirtualUser service tidak tersedia!")
        return false
    end
    
    VirtualUser = vu
    inited = true
    logger:info("Anti-AFK initialized")
    return true
end

function antiafkFeature:Start(config)
    if running then 
        logger:warn("Anti-AFK already running")
        return 
    end
    
    if not inited then
        local ok = self:Init()
        if not ok then 
            logger:error("Failed to initialize Anti-AFK")
            return 
        end
    end
    
    running = true
    logger:info("========================================")
    logger:info("Starting Anti-AFK with multi-layer bypass...")
    logger:info("========================================")
    
    -- Reset status
    for k, v in pairs(bypassStatus) do
        bypassStatus[k] = false
    end
    
    -- Try all bypass methods
    local methods = {
        { name = "Module Override", func = tryOverrideAFKController, critical = true },
        { name = "RemoteEvent Block", func = tryBlockRemoteEvent, critical = true },
        { name = "getconnections", func = tryGetConnections, critical = false },
        { name = "Periodic Reset", func = setupPeriodicReset, critical = true },
        { name = "Idled Hook", func = setupIdledHook, critical = false }
    }
    
    local successCount = 0
    local criticalSuccess = 0
    
    for _, method in ipairs(methods) do
        local success = method.func()
        if success then
            successCount = successCount + 1
            if method.critical then
                criticalSuccess = criticalSuccess + 1
            end
        else
            local prefix = method.critical and "⚠️" or "ℹ️"
            logger:warn(prefix .. " " .. method.name .. " failed")
        end
    end
    
    -- Status Report
    logger:info("========================================")
    logger:info("Anti-AFK Status Report:")
    logger:info("----------------------------------------")
    logger:info("Module Override:   " .. (bypassStatus.moduleOverride and "✅ ACTIVE" or "❌ FAILED"))
    logger:info("RemoteEvent Block: " .. (bypassStatus.remoteBlock and "✅ ACTIVE" or "❌ FAILED"))
    logger:info("getconnections:    " .. (bypassStatus.getConnections and "✅ ACTIVE" or "⚠️ NOT AVAILABLE"))
    logger:info("Periodic Reset:    " .. (bypassStatus.periodicReset and "✅ ACTIVE" or "❌ FAILED"))
    logger:info("Idled Hook:        " .. (bypassStatus.idledHook and "✅ ACTIVE" or "❌ FAILED"))
    logger:info("========================================")
    
    -- Safety Assessment
    if criticalSuccess >= 2 then
        logger:info("✅ Anti-AFK protection: STRONG")
        logger:info("   You are protected from both Roblox and AFKController kicks")
    elseif criticalSuccess >= 1 then
        logger:warn("⚠️ Anti-AFK protection: MODERATE")
        logger:warn("   Some bypass methods failed. Monitor for kicks.")
    else
        logger:error("❌ Anti-AFK protection: WEAK")
        logger:error("   Critical methods failed. High risk of kick!")
    end
    
    logger:info("========================================")
    logger:info(string.format("✓ %d/%d methods active", successCount, #methods))
end

function antiafkFeature:Stop()
    if not running then return end
    
    running = false
    
    -- Cleanup connections
    if idleConn then 
        idleConn:Disconnect()
        idleConn = nil 
    end
    
    -- Cancel periodic task
    if periodicTask then
        task.cancel(periodicTask)
        periodicTask = nil
    end
    
    -- Reset status
    for k, v in pairs(bypassStatus) do
        bypassStatus[k] = false
    end
    
    logger:info("Anti-AFK stopped")
end

function antiafkFeature:Cleanup()
    self:Stop()
end

function antiafkFeature:GetStatus()
    return {
        running = running,
        initialized = inited,
        bypasses = bypassStatus,
        protection = (bypassStatus.moduleOverride or bypassStatus.remoteBlock) and 
                     bypassStatus.periodicReset and "STRONG" or "WEAK"
    }
end

function antiafkFeature:ForceReset()
    if not running then return end
    
    logger:info("🔄 Manual AFK reset triggered")
    
    pcall(function()
        local Controllers = ReplicatedStorage:FindFirstChild("Controllers")
        if Controllers then
            local AFKController = Controllers:FindFirstChild("AFKController")
            if AFKController then
                local ok, module = pcall(require, AFKController)
                if ok and module and module.RemoveTime then
                    module:RemoveTime("ManualReset")
                    logger:info("✓ Manually reset AFK timer")
                end
            end
        end
    end)
end

return antiafkFeature