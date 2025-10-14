-- ===========================
-- AUTO FISH FEATURE - INSTANT BITE ON BAIT SPAWN
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
local FishingMinigameChanged, BaitSpawned -- NEW: BaitSpawned for instant trigger

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
        FishingMinigameChanged = NetPath:WaitForChild("RE/FishingMinigameChanged", 5)
        
        -- CRITICAL: BaitSpawned event for instant trigger
        BaitSpawned = NetPath:WaitForChild("RE/BaitSpawned", 5)
        
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
local minigameChangedConnection = nil
local baitSpawnedConnection = nil -- NEW: Critical for instant bite
local controls = {}
local fishingInProgress = false
local lastFishTime = 0
local remotesInitialized = false

-- Spam and completion tracking
local spamActive = false
local completionCheckActive = false
local lastBackpackCount = 0
local fishCaughtFlag = false
local biteTriggerFlag = false
local baitInWaterFlag = false -- NEW: Instant trigger on bait spawn

-- Rod-specific configs
local FISHING_CONFIGS = {
    ["Fast"] = {
        chargeTime = 1.0,
        waitBetween = 0,
        rodSlot = 1,
        spamDelay = 0.03,           -- 30ms normal spam
        instantSpamDelay = 0.015,   -- NEW: 15ms ultra-fast on bait spawn
        burstSpamCount = 5,         -- NEW: Increased burst
        burstSpamDelay = 0.015,     -- NEW: 15ms ultra-fast burst
        maxSpamTime = 20,
        skipMinigame = true,
        instantTrigger = true       -- NEW: Trigger immediately on bait spawn
    },
    ["Slow"] = {
        chargeTime = 1.0,
        waitBetween = 1,
        rodSlot = 1,
        spamDelay = 0.05,
        instantSpamDelay = 0.02,    -- NEW: 20ms on bait spawn
        burstSpamCount = 3,
        burstSpamDelay = 0.02,
        maxSpamTime = 20,
        skipMinigame = false,
        minigameDuration = 5,
        instantTrigger = false      -- NEW: Slow mode respects animation
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
    
    self:UpdateBackpackCount()
    
    logger:info("Initialized with INSTANT BITE on BaitSpawned")
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
    baitInWaterFlag = false
    
    logger:info("Started INSTANT BITE method - Mode:", currentMode)
    
    -- Setup all listeners
    self:SetupFishObtainedListener()
    self:SetupBiteDetectionListener()
    self:SetupBaitSpawnedListener() -- NEW: Critical for instant trigger
    
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
    baitInWaterFlag = false
    
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
    
    if baitSpawnedConnection then
        baitSpawnedConnection:Disconnect()
        baitSpawnedConnection = nil
    end
    
    logger:info("Stopped INSTANT BITE method")
end

-- CRITICAL: Setup BaitSpawned listener for instant trigger
function AutoFishFeature:SetupBaitSpawnedListener()
    if not BaitSpawned then
        logger:warn("BaitSpawned not available - instant trigger disabled")
        return
    end
    
    if baitSpawnedConnection then
        baitSpawnedConnection:Disconnect()
    end
    
    baitSpawnedConnection = BaitSpawned.OnClientEvent:Connect(function(...)
        if not isRunning or not spamActive then return end
        
        logger:info("🎣 BAIT IN WATER! Instant trigger activated")
        baitInWaterFlag = true
        
        local config = FISHING_CONFIGS[currentMode]
        
        -- INSTANT TRIGGER: Fire completion immediately when bait spawns
        if config.instantTrigger then
            logger:info("⚡ INSTANT SPAM activated!")
            spawn(function()
                -- Ultra-aggressive burst spam
                for i = 1, 10 do -- 10x rapid fire
                    if not spamActive then break end
                    self:FireCompletion()
                    task.wait(config.instantSpamDelay) -- 15ms ultra-fast
                end
                logger:info("Instant burst complete")
            end)
        end
    end)
    
    logger:info("BaitSpawned listener setup - INSTANT TRIGGER ready")
end

-- Setup instant bite detection listener
function AutoFishFeature:SetupBiteDetectionListener()
    if not FishingMinigameChanged then
        logger:warn("FishingMinigameChanged not available")
        return
    end
    
    if minigameChangedConnection then
        minigameChangedConnection:Disconnect()
    end
    
    minigameChangedConnection = FishingMinigameChanged.OnClientEvent:Connect(function(eventType, ...)
        if not isRunning or not spamActive then return end
        
        if eventType == "Clicked" or eventType == "Activated" then
            logger:info("🐟 BITE DETECTED:", eventType)
            biteTriggerFlag = true
            
            -- Additional burst on bite
            spawn(function()
                for i = 1, 5 do
                    if not spamActive then break end
                    self:FireCompletion()
                    task.wait(0.02)
                end
            end)
        end
    end)
    
    logger:info("Bite detection listener setup")
end

-- Setup fish obtained notification listener
function AutoFishFeature:SetupFishObtainedListener()
    if not FishObtainedNotification then
        logger:warn("FishObtainedNotification not available")
        return
    end
    
    if fishObtainedConnection then
        fishObtainedConnection:Disconnect()
    end
    
    fishObtainedConnection = FishObtainedNotification.OnClientEvent:Connect(function(...)
        if isRunning then
            logger:info("✅ Fish obtained!")
            fishCaughtFlag = true
            
            if spamActive then
                spamActive = false
                completionCheckActive = false
            end
            
            spawn(function()
                task.wait(0.1)
                fishingInProgress = false
                fishCaughtFlag = false
                biteTriggerFlag = false
                baitInWaterFlag = false
                logger:info("Ready for next cycle")
            end)
        end
    end)
    
    logger:info("Fish obtained listener setup")
end

-- Main spam-based fishing loop
function AutoFishFeature:SpamFishingLoop()
    if fishingInProgress or spamActive then return end
    
    local currentTime = tick()
    local config = FISHING_CONFIGS[currentMode]
    
    if currentTime - lastFishTime < config.waitBetween then
        return
    end
    
    fishingInProgress = true
    lastFishTime = currentTime
    
    spawn(function()
        local success = self:ExecuteSpamFishingSequence()
        fishingInProgress = false
        
        if success then
            logger:info("Cycle completed")
        end
    end)
end

-- Execute spam-based fishing sequence
function AutoFishFeature:ExecuteSpamFishingSequence()
    local config = FISHING_CONFIGS[currentMode]
    
    -- Reset flags
    baitInWaterFlag = false
    biteTriggerFlag = false
    
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

    -- Step 4: Start completion spam (BaitSpawned will trigger instant spam)
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

-- OPTIMIZED: Spam with instant trigger on BaitSpawned
function AutoFishFeature:StartCompletionSpam(delay, maxTime)
    if spamActive then return end
    
    spamActive = true
    completionCheckActive = true
    fishCaughtFlag = false
    biteTriggerFlag = false
    baitInWaterFlag = false
    local spamStartTime = tick()
    local config = FISHING_CONFIGS[currentMode]
    
    logger:info("Starting completion spam - Waiting for BAIT SPAWN...")
    
    self:UpdateBackpackCount()
    
    spawn(function()
        -- Initial burst spam
        logger:info("Initial burst:", config.burstSpamCount, "x @", config.burstSpamDelay * 1000, "ms")
        for i = 1, config.burstSpamCount do
            if not spamActive then break end
            self:FireCompletion()
            task.wait(config.burstSpamDelay)
        end
        
        -- Slow mode animation delay
        if currentMode == "Slow" and not config.skipMinigame then
            logger:info("Slow mode: Animation delay", config.minigameDuration, "s")
            task.wait(config.minigameDuration)
            
            if fishCaughtFlag or not isRunning or not spamActive then
                spamActive = false
                completionCheckActive = false
                return
            end
        end
        
        -- Main spam loop with dynamic speed based on bait/bite status
        while spamActive and isRunning and (tick() - spamStartTime) < maxTime do
            self:FireCompletion()
            
            -- Check completion
            if fishCaughtFlag or self:CheckFishingCompleted() then
                logger:info("Fish caught!")
                break
            end
            
            -- DYNAMIC DELAY: Ultra-fast if bait in water or bite detected
            local currentDelay = delay
            if baitInWaterFlag and config.instantTrigger then
                currentDelay = config.instantSpamDelay -- 15ms ultra-fast
            elseif biteTriggerFlag then
                currentDelay = 0.02 -- 20ms fast
            end
            
            task.wait(currentDelay)
        end
        
        spamActive = false
        completionCheckActive = false
        
        if (tick() - spamStartTime) >= maxTime then
            logger:info("Timeout after", maxTime, "s")
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

-- Check if fishing completed
function AutoFishFeature:CheckFishingCompleted()
    if fishCaughtFlag then
        return true
    end
    
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

-- Get backpack item count
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
        biteTriggerFlag = biteTriggerFlag,
        baitInWaterFlag = baitInWaterFlag, -- NEW
        remotesReady = remotesInitialized,
        listenerReady = fishObtainedConnection ~= nil,
        biteListenerReady = minigameChangedConnection ~= nil,
        baitSpawnListenerReady = baitSpawnedConnection ~= nil -- NEW
    }
end

-- Update mode
function AutoFishFeature:SetMode(mode)
    if FISHING_CONFIGS[mode] then
        currentMode = mode
        logger:info("Mode changed to:", mode)
        local config = FISHING_CONFIGS[mode]
        if mode == "Fast" then
            logger:info("  - Instant trigger: ON")
            logger:info("  - Ultra-fast spam: 15ms on bait spawn")
            logger:info("  - Burst: 5x @15ms")
        elseif mode == "Slow" then  
            logger:info("  - Instant trigger: OFF")
            logger:info("  - Animation:", config.minigameDuration, "s")
            logger:info("  - Burst: 3x @20ms")
        end
        return true
    end
    return false
end

-- Get notification listener info
function AutoFishFeature:GetNotificationInfo()
    return {
        hasNotificationRemote = FishObtainedNotification ~= nil,
        listenerConnected = fishObtainedConnection ~= nil,
        hasBiteRemote = FishingMinigameChanged ~= nil,
        biteListenerConnected = minigameChangedConnection ~= nil,
        hasBaitSpawnedRemote = BaitSpawned ~= nil, -- NEW
        baitSpawnListenerConnected = baitSpawnedConnection ~= nil, -- NEW
        fishCaughtFlag = fishCaughtFlag,
        biteTriggerFlag = biteTriggerFlag,
        baitInWaterFlag = baitInWaterFlag -- NEW
    }
end

-- Cleanup
function AutoFishFeature:Cleanup()
    logger:info("Cleaning up...")
    self:Stop()
    controls = {}
    remotesInitialized = false
end

return AutoFishFeature