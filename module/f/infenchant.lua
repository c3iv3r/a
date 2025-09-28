-- ===========================
-- AUTO FISH V2 - SMART FISH DETECTION
-- File: autofishv2.lua
-- ===========================

local AutoFishV2 = {}
AutoFishV2.__index = AutoFishV2

local logger = _G.Logger and _G.Logger.new("AutoFishV2") or {
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
local EquipTool, ChargeFishingRod, RequestFishing, FishingCompleted, FishObtainedNotification, ReplicateTextEffect, CancelFishingInputs

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
        ReplicateTextEffect = NetPath:WaitForChild("RE/ReplicateTextEffect", 5)
        CancelFishingInputs = NetPath:WaitForChild("RF/CancelFishingInputs", 5)
        
        return true
    end)
    
    return success
end

-- Feature state
local isRunning = false
local connection = nil
local fishObtainedConnection = nil
local textEffectConnection = nil
local spamConnection = nil
local controls = {}
local fishingInProgress = false
local waitingForTextEffect = false
local spamActive = false
local fishCaughtFlag = false
local lastFishTime = 0
local remotesInitialized = false

-- Fish rarity colors
local FISH_COLORS = {
    Uncommon = {
        r = 0.76470589637756,
        g = 1,
        b = 0.33333334326744
    },
    Rare = {
        r = 0.33333334326744,
        g = 0.63529413938522,
        b = 1
    }
}

-- Fast mode config
local FAST_CONFIG = {
    chargeTime = 1.0,
    waitBetween = 0,
    rodSlot = 1,
    spamDelay = 0.05,
    maxSpamTime = 30,
    textEffectTimeout = 10
}

-- Initialize
function AutoFishV2:Init(guiControls)
    controls = guiControls or {}
    remotesInitialized = initializeRemotes()
    
    if not remotesInitialized then
        logger:warn("Failed to initialize remotes")
        return false
    end
    
    logger:info("Initialized AutoFish V2 - Smart Fish Detection")
    return true
end

-- Start fishing
function AutoFishV2:Start(config)
    if isRunning then return end
    
    if not remotesInitialized then
        logger:warn("Cannot start - remotes not initialized")
        return
    end
    
    isRunning = true
    fishingInProgress = false
    waitingForTextEffect = false
    spamActive = false
    fishCaughtFlag = false
    lastFishTime = 0
    
    logger:info("Started AutoFish V2 - Smart Detection Mode")
    
    self:SetupTextEffectListener()
    self:SetupFishObtainedListener()
    
    connection = RunService.Heartbeat:Connect(function()
        if not isRunning then return end
        self:FishingLoop()
    end)
end

-- Stop fishing
function AutoFishV2:Stop()
    if not isRunning then return end
    
    isRunning = false
    fishingInProgress = false
    waitingForTextEffect = false
    spamActive = false
    fishCaughtFlag = false
    
    if connection then
        connection:Disconnect()
        connection = nil
    end
    
    if fishObtainedConnection then
        fishObtainedConnection:Disconnect()
        fishObtainedConnection = nil
    end
    
    if textEffectConnection then
        textEffectConnection:Disconnect()
        textEffectConnection = nil
    end
    
    if spamConnection then
        spamConnection:Disconnect()
        spamConnection = nil
    end
    
    logger:info("Stopped AutoFish V2")
end

-- Setup text effect listener
function AutoFishV2:SetupTextEffectListener()
    if not ReplicateTextEffect then
        logger:warn("ReplicateTextEffect not available")
        return
    end
    
    if textEffectConnection then
        textEffectConnection:Disconnect()
    end
    
    textEffectConnection = ReplicateTextEffect.OnClientEvent:Connect(function(data)
        if not isRunning or not waitingForTextEffect then return end
        
        self:HandleTextEffect(data)
    end)
    
    logger:info("Text effect listener setup complete")
end

-- Setup fish obtained listener
function AutoFishV2:SetupFishObtainedListener()
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
            
            if spamActive then
                spamActive = false
            end
            
            spawn(function()
                task.wait(0.1)
                fishingInProgress = false
                waitingForTextEffect = false
                fishCaughtFlag = false
                logger:info("Ready for next cycle")
            end)
        end
    end)
    
    logger:info("Fish obtained listener setup complete")
end

-- Handle text effect
function AutoFishV2:HandleTextEffect(data)
    if not data or not data.TextData then return end
    
    -- Check if effect is attached to our character
    if not LocalPlayer.Character or not LocalPlayer.Character.Head then return end
    if data.TextData.AttachTo ~= LocalPlayer.Character.Head then return end
    
    -- Check text color for rarity
    local textColor = data.TextData.TextColor
    if not textColor or not textColor.Keypoints then return end
    
    local keypoint = textColor.Keypoints[1]
    if not keypoint then return end
    
    local color = keypoint.Value
    local rarity = self:GetFishRarity(color)
    
    if rarity then
        logger:info("Detected", rarity, "fish - canceling fishing")
        self:CancelFishing()
    else
        logger:info("Common fish detected - starting spam")
        self:StartCompletionSpam()
    end
    
    waitingForTextEffect = false
end

-- Get fish rarity from color
function AutoFishV2:GetFishRarity(color)
    local threshold = 0.01
    
    -- Check Uncommon
    local uncommonColor = FISH_COLORS.Uncommon
    if math.abs(color.R - uncommonColor.r) < threshold and
       math.abs(color.G - uncommonColor.g) < threshold and
       math.abs(color.B - uncommonColor.b) < threshold then
        return "Uncommon"
    end
    
    -- Check Rare
    local rareColor = FISH_COLORS.Rare
    if math.abs(color.R - rareColor.r) < threshold and
       math.abs(color.G - rareColor.g) < threshold and
       math.abs(color.B - rareColor.b) < threshold then
        return "Rare"
    end
    
    return nil
end

-- Cancel fishing
function AutoFishV2:CancelFishing()
    if not CancelFishingInputs then
        logger:warn("CancelFishingInputs not available")
        return
    end
    
    local success = pcall(function()
        CancelFishingInputs:InvokeServer()
    end)
    
    if success then
        logger:info("Fishing cancelled successfully")
    else
        logger:warn("Failed to cancel fishing")
    end
    
    -- Reset state for next cycle
    spawn(function()
        task.wait(0.5)
        fishingInProgress = false
        waitingForTextEffect = false
    end)
end

-- Main fishing loop
function AutoFishV2:FishingLoop()
    if fishingInProgress or waitingForTextEffect or spamActive then return end
    
    local currentTime = tick()
    
    if currentTime - lastFishTime < FAST_CONFIG.waitBetween then
        return
    end
    
    fishingInProgress = true
    lastFishTime = currentTime
    
    spawn(function()
        local success = self:ExecuteFishingSequence()
        if not success then
            fishingInProgress = false
        end
    end)
end

-- Execute fishing sequence
function AutoFishV2:ExecuteFishingSequence()
    -- Step 1: Equip rod
    if not self:EquipRod(FAST_CONFIG.rodSlot) then
        return false
    end
    
    task.wait(0.1)
    
    -- Step 2: Charge rod
    if not self:ChargeRod(FAST_CONFIG.chargeTime) then
        return false
    end
    
    -- Step 3: Cast rod
    if not self:CastRod() then
        return false
    end
    
    -- Step 4: Wait for text effect
    waitingForTextEffect = true
    logger:info("Waiting for text effect...")
    
    -- Timeout for text effect
    spawn(function()
        task.wait(FAST_CONFIG.textEffectTimeout)
        if waitingForTextEffect then
            logger:warn("Text effect timeout - starting spam anyway")
            waitingForTextEffect = false
            self:StartCompletionSpam()
        end
    end)
    
    return true
end

-- Start spamming completion
function AutoFishV2:StartCompletionSpam()
    if spamActive then return end
    
    spamActive = true
    fishCaughtFlag = false
    local spamStartTime = tick()
    
    logger:info("Starting completion spam")
    
    spawn(function()
        while spamActive and isRunning and (tick() - spamStartTime) < FAST_CONFIG.maxSpamTime do
            self:FireCompletion()
            
            if fishCaughtFlag then
                logger:info("Fish caught detected!")
                break
            end
            
            task.wait(FAST_CONFIG.spamDelay)
        end
        
        spamActive = false
        
        if (tick() - spamStartTime) >= FAST_CONFIG.maxSpamTime then
            logger:info("Spam timeout after", FAST_CONFIG.maxSpamTime, "seconds")
            fishingInProgress = false
        end
    end)
end

-- Equip rod
function AutoFishV2:EquipRod(slot)
    if not EquipTool then return false end
    
    local success = pcall(function()
        EquipTool:FireServer(slot)
    end)
    
    return success
end

-- Charge rod
function AutoFishV2:ChargeRod(chargeTime)
    if not ChargeFishingRod then return false end
    
    local success = pcall(function()
        local chargeValue = tick() + (chargeTime * 1000)
        return ChargeFishingRod:InvokeServer(chargeValue)
    end)
    
    return success
end

-- Cast rod
function AutoFishV2:CastRod()
    if not RequestFishing then return false end
    
    local success = pcall(function()
        local x = -1.233184814453125
        local z = 0.9999120558411321
        return RequestFishing:InvokeServer(x, z)
    end)
    
    return success
end

-- Fire completion
function AutoFishV2:FireCompletion()
    if not FishingCompleted then return false end
    
    local success = pcall(function()
        FishingCompleted:FireServer()
    end)
    
    return success
end

-- Get status
function AutoFishV2:GetStatus()
    return {
        running = isRunning,
        inProgress = fishingInProgress,
        waitingForEffect = waitingForTextEffect,
        spamming = spamActive,
        lastCatch = lastFishTime,
        fishCaughtFlag = fishCaughtFlag,
        remotesReady = remotesInitialized,
        textEffectListenerReady = textEffectConnection ~= nil,
        fishObtainedListenerReady = fishObtainedConnection ~= nil
    }
end

-- Cleanup
function AutoFishV2:Cleanup()
    logger:info("Cleaning up AutoFish V2...")
    self:Stop()
    controls = {}
    remotesInitialized = false
end

return AutoFishV2