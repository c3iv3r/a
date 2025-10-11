-- ===========================
-- AUTO FISH FEATURE - SPAM METHOD (FIXED) + NO ANIMATION
-- File: autofishv4_fixed.lua
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

-- Animation Controller
local AnimationController = nil
local animationsDisabled = false

-- Network setup
local NetPath = nil
local EquipTool, ChargeFishingRod, RequestFishing, FishingCompleted, FishObtainedNotification

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
        
        return true
    end)
    
    return success
end

local function initializeAnimationController()
    local success = pcall(function()
        AnimationController = require(ReplicatedStorage:WaitForChild("Controllers"):WaitForChild("AnimationController"))
        return true
    end)
    
    if success then
        logger:info("AnimationController loaded")
    else
        logger:warn("AnimationController not found")
    end
    
    return success
end

-- Feature state
local isRunning = false
local currentMode = "Fast"
local connection = nil
local spamConnection = nil
local fishObtainedConnection = nil
local controls = {}
local fishingInProgress = false
local lastFishTime = 0
local remotesInitialized = false

-- Spam and completion tracking
local spamActive = false
local completionCheckActive = false
local lastBackpackCount = 0
local fishCaughtFlag = false

-- Rod-specific configs
local FISHING_CONFIGS = {
    ["Fast"] = {
        chargeTime = 1.0,
        waitBetween = 0,
        rodSlot = 1,
        spamDelay = 0.05,
        maxSpamTime = 20,
        skipMinigame = true
    },
    ["Slow"] = {
        chargeTime = 1.0,
        waitBetween = 1,
        rodSlot = 1,
        spamDelay = 0.1,
        maxSpamTime = 20,
        skipMinigame = false,
        minigameDuration = 5
    }
}

-- Disable fishing animations
function AutoFishFeature:DisableFishingAnimations()
    if not AnimationController then return false end
    if animationsDisabled then return true end
    
    local success = pcall(function()
        -- Stop fishing animations specifically
        AnimationController:StopAnimation("THROW_LINE")
        AnimationController:StopAnimation("FLEX_THROW_LINE")
        
        animationsDisabled = true
        logger:info("Fishing animations disabled (THROW_LINE, FLEX_THROW_LINE)")
    end)
    
    return success
end

-- Re-enable fishing animations
function AutoFishFeature:EnableFishingAnimations()
    if not animationsDisabled then return true end
    
    -- Animations will play naturally on next fishing action
    animationsDisabled = false
    logger:info("Fishing animations re-enabled")
    return true
end

-- Initialize
function AutoFishFeature:Init(guiControls)
    controls = guiControls or {}
    remotesInitialized = initializeRemotes()
    initializeAnimationController()
    
    if not remotesInitialized then
        logger:warn("Failed to initialize remotes")
        return false
    end
    
    self:UpdateBackpackCount()
    
    logger:info("Initialized with SPAM method + NO ANIMATION - Fast & Slow modes")
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
    
    -- Disable animations when autofish starts
    self:DisableFishingAnimations()
    
    logger:info("Started SPAM method - Mode:", currentMode, "| Animations: DISABLED")
    
    self:SetupFishObtainedListener()
    
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
    
    -- Re-enable animations when autofish stops
    self:EnableFishingAnimations()
    
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
    
    logger:info("Stopped SPAM method | Animations: RE-ENABLED")
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
            
            if spamActive then
                spamActive = false
                completionCheckActive = false
            end
            
            spawn(function()
                task.wait(0.1)
                fishingInProgress = false
                fishCaughtFlag = false
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
    
    if currentTime - lastFishTime < config.waitBetween then
        return
    end
    
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
    
    if not self:EquipRod(config.rodSlot) then
        return false
    end
    
    task.wait(0.1)

    if not self:ChargeRod(config.chargeTime) then
        return false
    end
    
    if not self:CastRod() then
        return false
    end

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

-- Start spamming FishingCompleted with mode-specific behavior
function AutoFishFeature:StartCompletionSpam(delay, maxTime)
    if spamActive then return end
    
    spamActive = true
    completionCheckActive = true
    fishCaughtFlag = false
    local spamStartTime = tick()
    local config = FISHING_CONFIGS[currentMode]
    
    logger:info("Starting completion SPAM - Mode:", currentMode)
    
    self:UpdateBackpackCount()
    
    spawn(function()
        if currentMode == "Slow" and not config.skipMinigame then
            logger:info("Slow mode: Playing minigame animation for", config.minigameDuration, "seconds")
            task.wait(config.minigameDuration)
            
            if fishCaughtFlag or not isRunning or not spamActive then
                spamActive = false
                completionCheckActive = false
                return
            end
        end
        
        while spamActive and isRunning and (tick() - spamStartTime) < maxTime do
            self:FireCompletion()
            
            if fishCaughtFlag or self:CheckFishingCompleted() then
                logger:info("Fish caught detected!")
                break
            end
            
            task.wait(delay)
        end
        
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

-- Check if fishing completed successfully (fallback method)
function AutoFishFeature:CheckFishingCompleted()
    if fishCaughtFlag then
        return true
    end
    
    local currentCount = self:GetBackpackItemCount()
    if currentCount > lastBackpackCount then
        lastBackpackCount = currentCount
        return true
    end
    
    if LocalPlayer.Character then
        local tool = LocalPlayer.Character:FindFirstChildOfClass("Tool")
        if not tool then
            return false
        end
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
        remotesReady = remotesInitialized,
        listenerReady = fishObtainedConnection ~= nil,
        animationsDisabled = animationsDisabled
    }
end

-- Update mode
function AutoFishFeature:SetMode(mode)
    if FISHING_CONFIGS[mode] then
        currentMode = mode
        logger:info("Mode changed to:", mode)
        if mode == "Fast" then
            logger:info("  - Skip minigame: ON")
        elseif mode == "Slow" then  
            logger:info("  - Skip minigame: OFF (", FISHING_CONFIGS[mode].minigameDuration, "s animation)")
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
        fishCaughtFlag = fishCaughtFlag
    }
end

-- Cleanup
function AutoFishFeature:Cleanup()
    logger:info("Cleaning up SPAM method...")
    self:Stop()
    controls = {}
    remotesInitialized = false
    AnimationController = nil
end

return AutoFishFeature