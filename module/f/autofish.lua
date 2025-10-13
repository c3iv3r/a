-- ===========================
-- AUTO FISH FEATURE - OPTIMIZED WITH WINDUP BYPASS
-- File: autofishv5_windup_optimized.lua
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
local EquipTool, ChargeFishingRod, RequestFishing, FishingCompleted, FishObtainedNotification, FishingMinigameChanged

-- Utility modules
local ItemUtility = nil
local Replion = nil

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
        
        return true
    end)
    
    return success
end

local function initializeUtilities()
    local success = pcall(function()
        ItemUtility = require(ReplicatedStorage:WaitForChild("Shared", 5):WaitForChild("ItemUtility", 5))
        Replion = require(ReplicatedStorage:WaitForChild("Packages", 5):WaitForChild("Replion", 5))
        return true
    end)
    return success
end

-- Feature state
local isRunning = false
local currentMode = "Ultra"
local connection = nil
local biteConnection = nil
local fishObtainedConnection = nil
local controls = {}
local fishingInProgress = false
local lastFishTime = 0
local remotesInitialized = false
local utilitiesInitialized = false

-- Spam and completion tracking
local spamActive = false
local completionCheckActive = false
local lastBackpackCount = 0
local fishCaughtFlag = false
local windupHookInstalled = false

-- Rod-specific configs
local FISHING_CONFIGS = {
    ["Ultra"] = {
        chargeTime = 0.5,       -- Minimal charge
        waitBetween = 0,
        rodSlot = 1,
        spamDelay = 0.03,       -- Super fast spam
        maxSpamTime = 15,
        skipMinigame = true,
        modifyWindup = true,    -- Enable windup modification
        windupOverride = NumberRange.new(0.3, 0.5), -- Fast windup
        usePredictiveTiming = true,
        preSpamOffset = 0.1     -- Start spam 0.1s before predicted bite
    },
    ["Fast"] = {
        chargeTime = 1.0,
        waitBetween = 0,
        rodSlot = 1,
        spamDelay = 0.05,
        maxSpamTime = 20,
        skipMinigame = true,
        modifyWindup = false,   -- Don't modify (safer)
        usePredictiveTiming = true,
        preSpamOffset = 0.2
    },
    ["Slow"] = {
        chargeTime = 1.0,
        waitBetween = 1,
        rodSlot = 1,
        spamDelay = 0.1,
        maxSpamTime = 20,
        skipMinigame = false,
        minigameDuration = 5,
        modifyWindup = false,
        usePredictiveTiming = false
    }
}

-- Hook ItemUtility to modify rod stats
function AutoFishFeature:InstallWindupHook()
    if not ItemUtility or windupHookInstalled then 
        return false 
    end
    
    local config = FISHING_CONFIGS[currentMode]
    if not config.modifyWindup then
        logger:info("Windup modification disabled for mode:", currentMode)
        return false
    end
    
    local success = pcall(function()
        local originalGetItemData = ItemUtility.GetItemData
        
        ItemUtility.GetItemData = function(self, itemId)
            local itemData = originalGetItemData(self, itemId)
            
            -- Only modify fishing rods
            if itemData and itemData.Data and itemData.Data.Type == "Fishing Rods" then
                local originalWindup = itemData.Windup
                
                -- Override windup
                itemData.Windup = config.windupOverride
                
                -- Reduce animation delays
                if itemData.BobberAnimationDelay then
                    itemData.BobberAnimationDelay = 0.05
                end
                if itemData.catchAnimationDelay then
                    itemData.catchAnimationDelay = 0.05
                end
                
                logger:debug("Modified rod:", itemData.Data.Name, 
                    "Original Windup:", originalWindup and tostring(originalWindup) or "nil",
                    "New Windup:", tostring(itemData.Windup))
            end
            
            return itemData
        end
        
        windupHookInstalled = true
        logger:info("Windup hook installed! Override:", tostring(config.windupOverride))
    end)
    
    return success
end

-- Get equipped rod data
function AutoFishFeature:GetEquippedRodData()
    if not Replion or not ItemUtility then 
        return nil 
    end
    
    local success, result = pcall(function()
        local dataReplion = Replion.Client:FindReplion("Data")
        if not dataReplion then return nil end
        
        local equippedId = dataReplion:Get("EquippedId")
        if not equippedId or equippedId == "" then return nil end
        
        return ItemUtility:GetItemData(equippedId)
    end)
    
    return success and result or nil
end

-- Calculate predicted bite time based on windup
function AutoFishFeature:PredictBiteTime()
    local rodData = self:GetEquippedRodData()
    
    if not rodData or not rodData.Windup then
        logger:debug("No rod data, using default prediction: 2s")
        return 2.0 -- Default fallback
    end
    
    -- Calculate average windup
    local windupMin = rodData.Windup.Min
    local windupMax = rodData.Windup.Max
    local avgWindup = (windupMin + windupMax) / 2
    
    logger:debug("Predicted bite time:", avgWindup, "s (Range:", windupMin, "-", windupMax, ")")
    
    return avgWindup
end

-- Setup bite detection listener
function AutoFishFeature:SetupBiteListener()
    if not FishingMinigameChanged then
        logger:warn("FishingMinigameChanged not available")
        return
    end
    
    if biteConnection then
        biteConnection:Disconnect()
    end
    
    biteConnection = FishingMinigameChanged.OnClientEvent:Connect(function(eventType, data)
        if eventType == "Activated" and isRunning then
            logger:info("BITE DETECTED via event listener!")
            
            -- Immediately start spam if not already spamming
            if not spamActive then
                local config = FISHING_CONFIGS[currentMode]
                self:StartCompletionSpam(config.spamDelay, config.maxSpamTime, true)
            end
        end
    end)
    
    logger:info("Bite listener setup complete")
end

-- Initialize
function AutoFishFeature:Init(guiControls)
    controls = guiControls or {}
    remotesInitialized = initializeRemotes()
    utilitiesInitialized = initializeUtilities()
    
    if not remotesInitialized then
        logger:warn("Failed to initialize remotes")
        return false
    end
    
    if not utilitiesInitialized then
        logger:warn("Failed to initialize utilities (ItemUtility/Replion)")
        logger:info("Predictive timing will be disabled")
    end
    
    -- Initialize backpack count for completion detection
    self:UpdateBackpackCount()
    
    -- Setup listeners
    self:SetupBiteListener()
    
    logger:info("Initialized with WINDUP OPTIMIZATION")
    logger:info("Available modes: Ultra (modded), Fast, Slow")
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
    currentMode = config.mode or "Ultra"
    fishingInProgress = false
    spamActive = false
    lastFishTime = 0
    fishCaughtFlag = false
    
    -- Install windup hook if enabled for this mode
    local modeConfig = FISHING_CONFIGS[currentMode]
    if modeConfig.modifyWindup and utilitiesInitialized then
        self:InstallWindupHook()
    end
    
    logger:info("Started fishing - Mode:", currentMode)
    logger:info("Config:", 
        "ChargeTime:", modeConfig.chargeTime,
        "SpamDelay:", modeConfig.spamDelay,
        "Predictive:", modeConfig.usePredictiveTiming)
    
    -- Setup fish obtained listener
    self:SetupFishObtainedListener()
    
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
    
    if connection then
        connection:Disconnect()
        connection = nil
    end
    
    if biteConnection then
        biteConnection:Disconnect()
        biteConnection = nil
    end
    
    if fishObtainedConnection then
        fishObtainedConnection:Disconnect()
        fishObtainedConnection = nil
    end
    
    logger:info("Stopped fishing")
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
            logger:info("Fish obtained notification received!")
            fishCaughtFlag = true
            
            -- Stop current spam immediately
            if spamActive then
                spamActive = false
                completionCheckActive = false
            end
            
            -- Reset fishing state for next cycle (fast restart)
            spawn(function()
                task.wait(0.05) -- Reduced delay for faster cycling
                fishingInProgress = false
                fishCaughtFlag = false
                logger:info("Ready for next cycle")
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
        
        if not success then
            fishingInProgress = false
        end
    end)
end

-- Execute spam-based fishing sequence with predictive timing
function AutoFishFeature:ExecuteSpamFishingSequence()
    local config = FISHING_CONFIGS[currentMode]
    
    -- Step 1: Equip rod
    if not self:EquipRod(config.rodSlot) then
        logger:warn("Failed to equip rod")
        return false
    end
    
    task.wait(0.05) -- Minimal delay

    -- Step 2: Charge rod
    if not self:ChargeRod(config.chargeTime) then
        logger:warn("Failed to charge rod")
        return false
    end
    
    -- Step 3: Cast rod
    local castTime = tick()
    if not self:CastRod() then
        logger:warn("Failed to cast rod")
        return false
    end
    
    logger:info("Cast successful at", castTime)

    -- Step 4: Use predictive timing or immediate spam
    if config.usePredictiveTiming and utilitiesInitialized then
        -- Predict bite time and start spam slightly before
        local predictedBiteTime = self:PredictBiteTime()
        local waitTime = math.max(0, predictedBiteTime - config.preSpamOffset)
        
        logger:info("Waiting", waitTime, "s before starting spam (predicted bite at", predictedBiteTime, "s)")
        task.wait(waitTime)
        
        -- Start spam at predicted time
        self:StartCompletionSpam(config.spamDelay, config.maxSpamTime, false)
    else
        -- Immediate spam for non-predictive modes
        self:StartCompletionSpam(config.spamDelay, config.maxSpamTime, false)
    end
    
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

-- Start spamming FishingCompleted
function AutoFishFeature:StartCompletionSpam(delay, maxTime, fromBiteEvent)
    if spamActive then 
        logger:debug("Spam already active, ignoring duplicate call")
        return 
    end
    
    spamActive = true
    completionCheckActive = true
    fishCaughtFlag = false
    local spamStartTime = tick()
    local config = FISHING_CONFIGS[currentMode]
    
    if fromBiteEvent then
        logger:info("Starting IMMEDIATE spam (bite event triggered)")
    else
        logger:info("Starting PREDICTIVE spam - Mode:", currentMode)
    end
    
    -- Update backpack count before spam
    self:UpdateBackpackCount()
    
    spawn(function()
        -- Slow mode: Wait for minigame animation
        if currentMode == "Slow" and not config.skipMinigame then
            logger:info("Slow mode: Playing minigame animation for", config.minigameDuration, "seconds")
            task.wait(config.minigameDuration)
            
            if fishCaughtFlag or not isRunning or not spamActive then
                spamActive = false
                completionCheckActive = false
                return
            end
        end
        
        -- Spam loop
        local spamCount = 0
        while spamActive and isRunning and (tick() - spamStartTime) < maxTime do
            -- Fire completion
            self:FireCompletion()
            spamCount = spamCount + 1
            
            -- Check if fishing completed
            if fishCaughtFlag or self:CheckFishingCompleted() then
                logger:info("Fish caught after", spamCount, "spam attempts in", 
                    string.format("%.2f", tick() - spamStartTime), "seconds")
                break
            end
            
            task.wait(delay)
        end
        
        -- Stop spam
        spamActive = false
        completionCheckActive = false
        fishingInProgress = false
        
        if (tick() - spamStartTime) >= maxTime then
            logger:warn("Spam timeout after", maxTime, "seconds")
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

-- Check if fishing completed successfully (fallback method)
function AutoFishFeature:CheckFishingCompleted()
    -- Primary: notification listener flag
    if fishCaughtFlag then
        return true
    end
    
    -- Fallback: backpack item count increase
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
    local rodData = self:GetEquippedRodData()
    local windupInfo = "N/A"
    
    if rodData and rodData.Windup then
        windupInfo = string.format("%.2f-%.2fs", rodData.Windup.Min, rodData.Windup.Max)
    end
    
    return {
        running = isRunning,
        mode = currentMode,
        inProgress = fishingInProgress,
        spamming = spamActive,
        lastCatch = lastFishTime,
        backpackCount = lastBackpackCount,
        fishCaughtFlag = fishCaughtFlag,
        remotesReady = remotesInitialized,
        utilitiesReady = utilitiesInitialized,
        windupHook = windupHookInstalled,
        currentWindup = windupInfo,
        listenerReady = fishObtainedConnection ~= nil,
        biteListenerReady = biteConnection ~= nil
    }
end

-- Update mode
function AutoFishFeature:SetMode(mode)
    if FISHING_CONFIGS[mode] then
        local wasRunning = isRunning
        
        if wasRunning then
            self:Stop()
        end
        
        currentMode = mode
        windupHookInstalled = false -- Reset hook for new mode
        
        logger:info("Mode changed to:", mode)
        
        local config = FISHING_CONFIGS[mode]
        if config.modifyWindup then
            logger:info("  - Windup modification: ENABLED")
            logger:info("  - Override:", tostring(config.windupOverride))
        else
            logger:info("  - Windup modification: DISABLED (using natural rod stats)")
        end
        
        if config.usePredictiveTiming then
            logger:info("  - Predictive timing: ENABLED")
        end
        
        if wasRunning then
            self:Start({mode = mode})
        end
        
        return true
    end
    return false
end

-- Get detailed debug info
function AutoFishFeature:GetDebugInfo()
    return {
        status = self:GetStatus(),
        config = FISHING_CONFIGS[currentMode],
        rodData = self:GetEquippedRodData(),
        predictedBiteTime = self:PredictBiteTime()
    }
end

-- Cleanup
function AutoFishFeature:Cleanup()
    logger:info("Cleaning up...")
    self:Stop()
    controls = {}
    remotesInitialized = false
    utilitiesInitialized = false
    windupHookInstalled = false
end

return AutoFishFeature