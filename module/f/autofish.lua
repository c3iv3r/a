-- ===========================
-- AUTO FISH FEATURE - OPTIMIZED STRIKE DETECTION
-- File: autofish_optimized.lua
-- ===========================

local AutoFishFeature = {}
AutoFishFeature.__index = AutoFishFeature

local logger = _G.Logger and _G.Logger.new("AutoFish") or {
    debug = function() end,
    info = function() end,
    warn = function() end,
    error = function() end
}

-- Services
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")  
local RunService = game:GetService("RunService")
local LocalPlayer = Players.LocalPlayer

-- Network setup
local NetPath = nil
local EquipTool, ChargeFishingRod, RequestFishing, FishingCompleted, FishObtainedNotification
local FishingMinigameChanged -- NEW: For instant bite detection

local function initializeRemotes()
    local success = pcall(function()
        NetPath = ReplicatedStorage:WaitForChild("Packages", 5)
            :WaitForChild("_Index", 5)
            :WaitForChild("sleitnick_net@0.2.0", 5)
            :WaitForChild("net", 5)
        
        EquipTool = NetPath:WaitForChild("RE/EquipToolFromHotbar", 5)
        ChargeFishingRod = NetPath:WaitForChild("RF/ChargeFishingRod", 5)
        RequestFishing = NetPath:WaitForChild("RF/RequestFishingMinigameStarted", 5)
        FishingCompleted = NetPath:WaitForChild("RE/FishingCompleted", 5)
        FishObtainedNotification = NetPath:WaitForChild("RE/ObtainedNewFishNotification", 5)
        
        -- NEW: Instant bite detection
        FishingMinigameChanged = NetPath:WaitForChild("RE/FishingMinigameChanged", 5)
        
        return true
    end)
    
    return success
end

-- Feature state
local isRunning = false
local currentMode = "Fast"
local connection = nil
local spamConnection = nil
local fishObtainedConnection = nil
local minigameChangedConnection = nil -- NEW
local controls = {}
local fishingInProgress = false
local lastFishTime = 0
local remotesInitialized = false

-- Spam and completion tracking
local spamActive = false
local completionCheckActive = false
local lastBackpackCount = 0
local fishCaughtFlag = false
local biteTriggerFlag = false -- NEW: Instant bite detection

-- Rod-specific configs
local FISHING_CONFIGS = {
    ["Fast"] = {
        chargeTime = 1.0,
        waitBetween = 0,
        rodSlot = 1,
        spamDelay = 0.03,      -- OPTIMIZED: 30ms (faster than game's 100ms check)
        burstSpamCount = 3,    -- NEW: Initial burst spam
        burstSpamDelay = 0.02, -- NEW: 20ms for burst
        maxSpamTime = 20,
        skipMinigame = true
    },
    ["Slow"] = {
        chargeTime = 1.0,
        waitBetween = 1,
        rodSlot = 1,
        spamDelay = 0.05,      -- OPTIMIZED: 50ms for slow mode
        burstSpamCount = 2,    -- NEW: Smaller burst for slow
        burstSpamDelay = 0.03, -- NEW: 30ms for burst
        maxSpamTime = 20,
        skipMinigame = false,
        minigameDuration = 5
    }
}

-- Initialize
function AutoFishFeature:Init(guiControls)
    controls = guiControls or {}
    remotesInitialized = initializeRemotes()
    
    if not remotesInitialized then
        logger:warn("Failed to initialize remotes")
        return false
    end
    
    -- Initialize backpack count for completion detection
    self:UpdateBackpackCount()
    
    logger:info("Initialized with OPTIMIZED strike detection")
    return true
end

-- Start fishing
function AutoFishFeature:Start(config)
    if isRunning then return end
    
    if not remotesInitialized then
        logger:warn("Cannot start - remotes not initialized")
        return
    end
    
    isRunning = true
    currentMode = config.mode or "Fast"
    fishingInProgress = false
    spamActive = false
    lastFishTime = 0
    fishCaughtFlag = false
    biteTriggerFlag = false
    
    logger:info("Started OPTIMIZED method - Mode:", currentMode)
    
    -- Setup listeners
    self:SetupFishObtainedListener()
    self:SetupBiteDetectionListener() -- NEW
    
    -- Main fishing loop
    connection = RunService.Heartbeat:Connect(function()
        if not isRunning then return end
        self:SpamFishingLoop()
    end)
end

-- Stop fishing
function AutoFishFeature:Stop()
    if not isRunning then return end
    
    isRunning = false
    fishingInProgress = false
    spamActive = false
    completionCheckActive = false
    fishCaughtFlag = false
    biteTriggerFlag = false
    
    if connection then
        connection:Disconnect()
        connection = nil
    end
    
    if spamConnection then
        spamConnection:Disconnect()
        spamConnection = nil
    end
    
    if fishObtainedConnection then
        fishObtainedConnection:Disconnect()
        fishObtainedConnection = nil
    end
    
    if minigameChangedConnection then
        minigameChangedConnection:Disconnect()
        minigameChangedConnection = nil
    end
    
    logger:info("Stopped OPTIMIZED method")
end

-- NEW: Setup instant bite detection listener
function AutoFishFeature:SetupBiteDetectionListener()
    if not FishingMinigameChanged then
        logger:warn("FishingMinigameChanged not available")
        return
    end
    
    -- Disconnect existing connection if any
    if minigameChangedConnection then
        minigameChangedConnection:Disconnect()
    end
    
    minigameChangedConnection = FishingMinigameChanged.OnClientEvent:Connect(function(eventType, ...)
        if not isRunning or not spamActive then return end
        
        -- Detect "Clicked" or "Activated" events (fish bite)
        if eventType == "Clicked" or eventType == "Activated" then
            logger:info("BITE DETECTED! Instant trigger:", eventType)
            biteTriggerFlag = true
            
            -- Immediate burst spam on bite detection
            spawn(function()
                for i = 1, 5 do
                    if not spamActive then break end
                    self:FireCompletion()
                    task.wait(0.02) -- Ultra-fast 20ms burst
                end
            end)
        end
    end)
    
    logger:info("Bite detection listener setup complete")
end

-- Setup fish obtained notification listener
function AutoFishFeature:SetupFishObtainedListener()
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
            logger:info("Fish obtained notification received!")
            fishCaughtFlag = true
            
            -- Stop current spam immediately
            if spamActive then
                spamActive = false
                completionCheckActive = false
            end
            
            -- Reset fishing state for next cycle (fast restart)
            spawn(function()
                task.wait(0.1) -- Small delay for stability
                fishingInProgress = false
                fishCaughtFlag = false
                biteTriggerFlag = false
                logger:info("Ready for next cycle (fast restart)")
            end)
        end
    end)
    
    logger:info("Fish obtained listener setup complete")
end

-- Main spam-based fishing loop
function AutoFishFeature:SpamFishingLoop()
    if fishingInProgress or spamActive then return end
    
    local currentTime = tick()
    local config = FISHING_CONFIGS[currentMode]
    
    -- Wait between cycles
    if currentTime - lastFishTime < config.waitBetween then
        return
    end
    
    -- Start fishing sequence
    fishingInProgress = true
    lastFishTime = currentTime
    
    spawn(function()
        local success = self:ExecuteSpamFishingSequence()
        fishingInProgress = false
        
        if success then
            logger:info("SPAM cycle completed!")
        end
    end)
end

-- Execute spam-based fishing sequence
function AutoFishFeature:ExecuteSpamFishingSequence()
    local config = FISHING_CONFIGS[currentMode]
    
    -- Step 1: Equip rod
    if not self:EquipRod(config.rodSlot) then
        return false
    end
    
    task.wait(0.1)

    -- Step 2: Charge rod
    if not self:ChargeRod(config.chargeTime) then
        return false
    end
    
    -- Step 3: Cast rod
    if not self:CastRod() then
        return false
    end

    -- Step 4: Start completion spam with OPTIMIZED behavior
    self:StartCompletionSpam(config.spamDelay, config.maxSpamTime)
    
    return true
end

-- Equip rod
function AutoFishFeature:EquipRod(slot)
    if not EquipTool then return false end
    
    local success = pcall(function()
        EquipTool:FireServer(slot)
    end)
    
    return success
end

-- Charge rod
function AutoFishFeature:ChargeRod(chargeTime)
    if not ChargeFishingRod then return false end
    
    local success = pcall(function()
        local chargeValue = tick() + (chargeTime * 1000)
        return ChargeFishingRod:InvokeServer(chargeValue)
    end)
    
    return success
end

-- Cast rod
function AutoFishFeature:CastRod()
    if not RequestFishing then return false end
    
    local success = pcall(function()
        local x = -1.233184814453125
        local z = 0.9999120558411321
        return RequestFishing:InvokeServer(x, z)
    end)
    
    return success
end

-- OPTIMIZED: Start spamming with burst and bite detection
function AutoFishFeature:StartCompletionSpam(delay, maxTime)
    if spamActive then return end
    
    spamActive = true
    completionCheckActive = true
    fishCaughtFlag = false
    biteTriggerFlag = false
    local spamStartTime = tick()
    local config = FISHING_CONFIGS[currentMode]
    
    logger:info("Starting OPTIMIZED completion SPAM - Mode:", currentMode)
    
    -- Update backpack count before spam
    self:UpdateBackpackCount()
    
    spawn(function()
        -- NEW: Initial BURST SPAM to trigger minigame faster
        logger:info("Initial burst spam (", config.burstSpamCount, "x @", config.burstSpamDelay * 1000, "ms)")
        for i = 1, config.burstSpamCount do
            if not spamActive then break end
            self:FireCompletion()
            task.wait(config.burstSpamDelay)
        end
        
        -- Mode-specific behavior
        if currentMode == "Slow" and not config.skipMinigame then
            -- Slow mode: Wait for minigame animation
            logger:info("Slow mode: Playing minigame animation for", config.minigameDuration, "seconds")
            task.wait(config.minigameDuration)
            
            -- Check if fish was already caught during animation
            if fishCaughtFlag or not isRunning or not spamActive then
                spamActive = false
                completionCheckActive = false
                return
            end
        end
        
        -- Start main spamming loop with bite detection
        while spamActive and isRunning and (tick() - spamStartTime) < maxTime do
            -- Fire completion
            self:FireCompletion()
            
            -- Check if fishing completed (notification OR backpack OR bite trigger)
            if fishCaughtFlag or self:CheckFishingCompleted() then
                logger:info("Fish caught detected!")
                break
            end
            
            -- OPTIMIZED: Use faster delay if bite detected
            local currentDelay = delay
            if biteTriggerFlag then
                currentDelay = 0.02 -- Ultra-fast 20ms when bite detected
            end
            
            task.wait(currentDelay)
        end
        
        -- Stop spam
        spamActive = false
        completionCheckActive = false
        
        if (tick() - spamStartTime) >= maxTime then
            logger:info("SPAM timeout after", maxTime, "seconds")
        end
    end)
end

-- Fire FishingCompleted
function AutoFishFeature:FireCompletion()
    if not FishingCompleted then return false end
    
    local success = pcall(function()
        FishingCompleted:FireServer()
    end)
    
    return success
end

-- Check if fishing completed successfully
function AutoFishFeature:CheckFishingCompleted()
    -- Primary method: notification listener flag
    if fishCaughtFlag then
        return true
    end
    
    -- Secondary method: bite trigger flag
    if biteTriggerFlag then
        -- Don't return true immediately, just use it to speed up spam
        -- Actual completion still needs notification or backpack check
    end
    
    -- Fallback method: Check backpack item count increase
    local currentCount = self:GetBackpackItemCount()
    if currentCount > lastBackpackCount then
        lastBackpackCount = currentCount
        return true
    end
    
    return false
end

-- Update backpack count
function AutoFishFeature:UpdateBackpackCount()
    lastBackpackCount = self:GetBackpackItemCount()
end

-- Get current backpack item count
function AutoFishFeature:GetBackpackItemCount()
    local count = 0
    
    if LocalPlayer.Backpack then
        count = count + #LocalPlayer.Backpack:GetChildren()
    end
    
    if LocalPlayer.Character then
        for _, child in pairs(LocalPlayer.Character:GetChildren()) do
            if child:IsA("Tool") then
                count = count + 1
            end
        end
    end
    
    return count
end

-- Get status
function AutoFishFeature:GetStatus()
    return {
        running = isRunning,
        mode = currentMode,
        inProgress = fishingInProgress,
        spamming = spamActive,
        lastCatch = lastFishTime,
        backpackCount = lastBackpackCount,
        fishCaughtFlag = fishCaughtFlag,
        biteTriggerFlag = biteTriggerFlag, -- NEW
        remotesReady = remotesInitialized,
        listenerReady = fishObtainedConnection ~= nil,
        biteListenerReady = minigameChangedConnection ~= nil -- NEW
    }
end

-- Update mode
function AutoFishFeature:SetMode(mode)
    if FISHING_CONFIGS[mode] then
        currentMode = mode
        logger:info("Mode changed to:", mode)
        if mode == "Fast" then
            logger:info("  - Skip minigame: ON, Burst spam: 3x @20ms")
        elseif mode == "Slow" then  
            logger:info("  - Skip minigame: OFF (", FISHING_CONFIGS[mode].minigameDuration, "s animation), Burst spam: 2x @30ms")
        end
        return true
    end
    return false
end

-- Get notification listener info for debugging
function AutoFishFeature:GetNotificationInfo()
    return {
        hasNotificationRemote = FishObtainedNotification ~= nil,
        listenerConnected = fishObtainedConnection ~= nil,
        hasBiteRemote = FishingMinigameChanged ~= nil, -- NEW
        biteListenerConnected = minigameChangedConnection ~= nil, -- NEW
        fishCaughtFlag = fishCaughtFlag,
        biteTriggerFlag = biteTriggerFlag -- NEW
    }
end

-- Cleanup
function AutoFishFeature:Cleanup()
    logger:info("Cleaning up OPTIMIZED method...")
    self:Stop()
    controls = {}
    remotesInitialized = false
end

return AutoFishFeature