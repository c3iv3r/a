-- ===========================
-- AUTO FISH V5 - ANIMATION CANCEL METHOD
-- Implementasi: Cancel animasi RodThrow untuk skip delay
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

-- Controllers
local AnimationController
local FishingController

-- Network setup
local NetPath = nil
local EquipTool, ChargeFishingRod, RequestFishing, FishingCompleted, FishObtainedNotification, BaitSpawnedEvent

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
        BaitSpawnedEvent = NetPath:WaitForChild("RE/BaitSpawned", 5)
        
        -- Load controllers
        AnimationController = require(ReplicatedStorage.Controllers.AnimationController)
        FishingController = require(ReplicatedStorage.Controllers.FishingController)

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
local baitSpawnedConnection = nil
local controls = {}
local fishingInProgress = false
local lastFishTime = 0
local remotesInitialized = false

-- Spam tracking
local spamActive = false
local completionCheckActive = false
local lastBackpackCount = 0
local fishCaughtFlag = false
local animationCancelEnabled = true

-- Animation hooks
local originalPlayAnimation = nil
local originalStopAnimation = nil

-- Rod configs
local FISHING_CONFIGS = {
    ["Fast"] = {
        chargeTime = 0.5,
        waitBetween = 0,
        rodSlot = 1,
        spamDelay = 0.05,
        maxSpamTime = 20,
        skipMinigame = true,
        cancelAnimations = true -- Cancel RodThrow animation
    },
    ["Slow"] = {
        chargeTime = 1.0,
        waitBetween = 1,
        rodSlot = 1,
        spamDelay = 0.1,
        maxSpamTime = 20,
        skipMinigame = false,
        minigameDuration = 5,
        cancelAnimations = false
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
    self:SetupAnimationHooks()

    logger:info("Initialized V5 - Animation Cancel Method")
    return true
end

-- Setup animation hooks untuk cancel animasi
function AutoFishFeature:SetupAnimationHooks()
    if not AnimationController then
        logger:warn("AnimationController not found")
        return
    end

    -- Hook PlayAnimation
    if not originalPlayAnimation then
        originalPlayAnimation = AnimationController.PlayAnimation
        
        AnimationController.PlayAnimation = function(self, animName)
            local track, trackObj = originalPlayAnimation(self, animName)
            
            -- Cancel animasi throw jika mode Fast
            if animationCancelEnabled then
                -- Cancel RodThrow (lempar)
                if animName == "RodThrow" then
                    logger:debug("Detected RodThrow - cancel after 0.1s")
                    
                    spawn(function()
                        task.wait(0.1)
                        if track then
                            track:Stop()
                            logger:debug("RodThrow cancelled")
                        end
                    end)
                end
                
                -- Cancel FishCaught (animasi dapat ikan)
                if animName == "FishCaught" then
                    logger:debug("Detected FishCaught - instant cancel")
                    
                    spawn(function()
                        task.wait(0.05) -- Delay minimal
                        if track then
                            track:Stop()
                            logger:debug("FishCaught cancelled")
                        end
                    end)
                end
                
                -- Cancel animasi failure
                if animName == "FishingFailure" then
                    logger:debug("Detected FishingFailure - instant cancel")
                    
                    spawn(function()
                        if track then
                            track:Stop()
                            logger:debug("FishingFailure cancelled")
                        end
                    end)
                end
            end
            
            return track, trackObj
        end
        
        logger:info("Animation hook installed")
    end

    -- Hook BaitSpawned untuk instant cancel
    self:SetupBaitSpawnedHook()
end

-- Setup hook untuk BaitSpawned event
function AutoFishFeature:SetupBaitSpawnedHook()
    if not BaitSpawnedEvent then
        logger:warn("BaitSpawnedEvent not available")
        return
    end

    if baitSpawnedConnection then
        baitSpawnedConnection:Disconnect()
    end

    baitSpawnedConnection = BaitSpawnedEvent.OnClientEvent:Connect(function(...)
        if isRunning and animationCancelEnabled then
            logger:debug("BaitSpawned - cancelling throw animations")
            
            -- Cancel semua animasi throw
            pcall(function()
                AnimationController:StopAnimation("RodThrow")
                AnimationController:StopAnimation("StartRodCharge")
                AnimationController:StopAnimation("LoopedRodCharge")
                AnimationController:DestroyActiveAnimationTracks({"EquipIdle"})
            end)
        end
    end)

    logger:info("BaitSpawned hook setup complete")
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
    
    -- Enable/disable animation cancel based on mode
    local cfg = FISHING_CONFIGS[currentMode]
    animationCancelEnabled = cfg.cancelAnimations

    logger:info("Started V5 - Mode:", currentMode, "| AnimCancel:", animationCancelEnabled)

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
    animationCancelEnabled = false

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

    if baitSpawnedConnection then
        baitSpawnedConnection:Disconnect()
        baitSpawnedConnection = nil
    end

    logger:info("Stopped V5")
end

-- Setup fish obtained listener
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
            logger:info("Fish obtained!")
            fishCaughtFlag = true

            if spamActive then
                spamActive = false
                completionCheckActive = false
            end

            spawn(function()
                task.wait(0.1)
                fishingInProgress = false
                fishCaughtFlag = false
                logger:info("Ready for next cycle")
            end)
        end
    end)

    logger:info("Fish obtained listener ready")
end

-- Main fishing loop
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

-- Execute fishing sequence
function AutoFishFeature:ExecuteSpamFishingSequence()
    local config = FISHING_CONFIGS[currentMode]

    -- Equip rod
    if not self:EquipRod(config.rodSlot) then
        return false
    end

    task.wait(0.1)

    -- Charge rod
    if not self:ChargeRod(config.chargeTime) then
        return false
    end

    -- Cast rod (animation akan di-cancel otomatis oleh hook)
    if not self:CastRod() then
        return false
    end

    -- Start spam
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
        return ChargeFishingRod:InvokeServer(math.huge)
    end)
    
    task.wait(chargeTime)
    return success
end

-- Cast rod
function AutoFishFeature:CastRod()
    if not RequestFishing then return false end

    local success = pcall(function()
        local y = -139.63
        local power = 0.9999120558411321
        return RequestFishing:InvokeServer(y, power)
    end)

    return success
end

-- Start completion spam
function AutoFishFeature:StartCompletionSpam(delay, maxTime)
    if spamActive then return end

    spamActive = true
    completionCheckActive = true
    fishCaughtFlag = false
    local spamStartTime = tick()
    local config = FISHING_CONFIGS[currentMode]

    logger:info("Starting spam - Mode:", currentMode)

    self:UpdateBackpackCount()

    spawn(function()
        -- Slow mode: Wait for animation
        if currentMode == "Slow" and not config.skipMinigame then
            logger:info("Slow mode: Animation", config.minigameDuration, "s")
            task.wait(config.minigameDuration)

            if fishCaughtFlag or not isRunning or not spamActive then
                spamActive = false
                completionCheckActive = false
                return
            end
        end

        -- Spam loop
        while spamActive and isRunning and (tick() - spamStartTime) < maxTime do
            self:FireCompletion()

            if fishCaughtFlag or self:CheckFishingCompleted() then
                logger:info("Fish caught!")
                break
            end

            task.wait(delay)
        end

        spamActive = false
        completionCheckActive = false

        if (tick() - spamStartTime) >= maxTime then
            logger:info("Timeout after", maxTime, "s")
        end
    end)
end

-- Fire completion
function AutoFishFeature:FireCompletion()
    if not FishingCompleted then return false end

    local success = pcall(function()
        FishingCompleted:FireServer()
    end)

    return success
end

-- Check fishing completed
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

-- Get backpack count
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
        animCancelEnabled = animationCancelEnabled,
        baitHookReady = baitSpawnedConnection ~= nil
    }
end

-- Set mode
function AutoFishFeature:SetMode(mode)
    if FISHING_CONFIGS[mode] then
        currentMode = mode
        local cfg = FISHING_CONFIGS[mode]
        animationCancelEnabled = cfg.cancelAnimations
        
        logger:info("Mode:", mode, "| AnimCancel:", animationCancelEnabled)
        return true
    end
    return false
end

-- Get animation info
function AutoFishFeature:GetAnimationInfo()
    return {
        hookInstalled = originalPlayAnimation ~= nil,
        cancelEnabled = animationCancelEnabled,
        baitHookReady = baitSpawnedConnection ~= nil
    }
end

-- Cleanup
function AutoFishFeature:Cleanup()
    logger:info("Cleaning up V5...")
    self:Stop()
    
    -- Restore original functions
    if originalPlayAnimation and AnimationController then
        AnimationController.PlayAnimation = originalPlayAnimation
        originalPlayAnimation = nil
    end
    
    controls = {}
    remotesInitialized = false
end

return AutoFishFeature