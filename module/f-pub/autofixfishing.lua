-- ===========================
-- AUTO FIX FISHING FEATURE
-- File: autofixfishing.lua
-- ===========================

local AutoFixFishingFeature = {}
AutoFixFishingFeature.__index = AutoFixFishingFeature

local logger = _G.Logger and _G.Logger.new("AutoFixFishing") or {
    debug = function() end,
    info = function() end,
    warn = function() end,
    error = function() end
}

-- Services
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

-- Network setup
local NetPath = nil
local CancelFishingEvent, FishObtainedNotification

local function initializeRemotes()
    local success = pcall(function()
        NetPath = ReplicatedStorage:WaitForChild("Packages", 5)
            :WaitForChild("_Index", 5)
            :WaitForChild("sleitnick_net@0.2.0", 5)
            :WaitForChild("net", 5)

        CancelFishingEvent = NetPath:WaitForChild("RF/CancelFishingInputs", 5)
        FishObtainedNotification = NetPath:WaitForChild("RE/ObtainedNewFishNotification", 5)

        return true
    end)

    return success
end

-- Feature state
local isRunning = false
local connection = nil
local fishObtainedConnection = nil
local controls = {}
local remotesInitialized = false

-- Timer tracking
local lastFishObtainedTime = 0
local STUCK_TIMEOUT = 300 -- 5 minutes in seconds

-- Initialize
function AutoFixFishingFeature:Init(guiControls)
    controls = guiControls or {}
    remotesInitialized = initializeRemotes()

    if not remotesInitialized then
        logger:warn("Failed to initialize remotes")
        return false
    end

    logger:info("Initialized - Stuck fishing detection enabled")
    return true
end

-- Start monitoring
function AutoFixFishingFeature:Start()
    if isRunning then return end

    if not remotesInitialized then
        logger:warn("Cannot start - remotes not initialized")
        return
    end

    isRunning = true
    lastFishObtainedTime = tick()

    logger:info("Started monitoring - Timeout:", STUCK_TIMEOUT, "seconds")

    -- Setup fish obtained listener
    self:SetupFishObtainedListener()

    -- Main monitoring loop
    connection = RunService.Heartbeat:Connect(function()
        if not isRunning then return end
        self:CheckStuckFishing()
    end)
end

-- Stop monitoring
function AutoFixFishingFeature:Stop()
    if not isRunning then return end

    isRunning = false

    if connection then
        connection:Disconnect()
        connection = nil
    end

    if fishObtainedConnection then
        fishObtainedConnection:Disconnect()
        fishObtainedConnection = nil
    end

    logger:info("Stopped monitoring")
end

-- Setup fish obtained notification listener
function AutoFixFishingFeature:SetupFishObtainedListener()
    if not FishObtainedNotification then
        logger:warn("FishObtainedNotification not available")
        return
    end

    -- Disconnect existing connection if any
    if fishObtainedConnection then
        fishObtainedConnection:Disconnect()
    end

    fishObtainedConnection = FishObtainedNotification.OnClientEvent:Connect(function(...)
        if isRunning then
            logger:info("Fish obtained - Timer reset")
            lastFishObtainedTime = tick()
        end
    end)

    logger:info("Fish obtained listener setup complete")
end

-- Check if fishing is stuck
function AutoFixFishingFeature:CheckStuckFishing()
    local currentTime = tick()
    local timeSinceLastFish = currentTime - lastFishObtainedTime

    if timeSinceLastFish >= STUCK_TIMEOUT then
        logger:warn("Fishing stuck detected! No fish for", math.floor(timeSinceLastFish), "seconds")
        self:FixStuckFishing()
        lastFishObtainedTime = currentTime -- Reset timer after fix attempt
    end
end

-- Fix stuck fishing by canceling
function AutoFixFishingFeature:FixStuckFishing()
    if not CancelFishingEvent then
        logger:error("CancelFishingEvent not available")
        return false
    end

    local success = pcall(function()
        CancelFishingEvent:InvokeServer()
    end)

    if success then
        logger:info("Successfully cancelled stuck fishing")
    else
        logger:error("Failed to cancel fishing")
    end

    return success
end

-- Get status
function AutoFixFishingFeature:GetStatus()
    local timeSinceLastFish = tick() - lastFishObtainedTime

    return {
        running = isRunning,
        lastFishTime = lastFishObtainedTime,
        timeSinceLastFish = math.floor(timeSinceLastFish),
        timeoutThreshold = STUCK_TIMEOUT,
        timeRemaining = math.max(0, STUCK_TIMEOUT - timeSinceLastFish),
        remotesReady = remotesInitialized,
        listenerReady = fishObtainedConnection ~= nil
    }
end

-- Manual fix trigger
function AutoFixFishingFeature:ManualFix()
    logger:info("Manual fix triggered")
    local success = self:FixStuckFishing()
    if success then
        lastFishObtainedTime = tick()
    end
    return success
end

-- Update timeout (in seconds)
function AutoFixFishingFeature:SetTimeout(seconds)
    if seconds and seconds > 0 then
        STUCK_TIMEOUT = seconds
        logger:info("Timeout updated to:", seconds, "seconds")
        return true
    end
    return false
end

-- Cleanup
function AutoFixFishingFeature:Cleanup()
    logger:info("Cleaning up...")
    self:Stop()
    controls = {}
    remotesInitialized = false
end

return AutoFixFishingFeature