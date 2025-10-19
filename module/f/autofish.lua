
-- ===========================
-- AUTO FISH V5 - ANIMATION CANCEL METHOD [PATCHED]
-- Fix: CancelFishingInputs setiap cast 1, 6, 11, 16, dst (interval 5)
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
local EquipTool, ChargeFishingRod, RequestFishing, FishingCompleted, FishObtainedNotification, BaitSpawnedEvent, ReplicateTextEffect, CancelFishingInputs

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
        ReplicateTextEffect = NetPath:WaitForChild("RE/ReplicateTextEffect", 5)
        CancelFishingInputs = NetPath:WaitForChild("RF/CancelFishingInputs", 5)
        
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
local textEffectConnection = nil
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
local baitSpawnedFlag = false
local textEffectReceived = false

-- Cast counter untuk reset (mulai dari 0, cast pertama = 1)
local castCount = 0

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
        disableAllAnimations = true,
        resetInterval = 5,
        instantSpam = false
    },
    ["Slow"] = {
        chargeTime = 1.0,
        waitBetween = 1,
        rodSlot = 1,
        spamDelay = 0.1,
        maxSpamTime = 20,
        skipMinigame = false,
        minigameDuration = 5,
        disableAllAnimations = false,
        resetInterval = 0,
        instantSpam = false
    }
}

function AutoFishFeature:Init(guiControls)
    controls = guiControls or {}
    remotesInitialized = initializeRemotes()

    if not remotesInitialized then
        logger:warn("Failed to initialize remotes")
        return false
    end

    self:UpdateBackpackCount()
    self:SetupAnimationHooks()

    logger:info("Initialized V5 - Pattern: 1,6,11,16...")
    return true
end

function AutoFishFeature:SetupAnimationHooks()
    if not AnimationController then
        logger:warn("AnimationController not found")
        return
    end

    if not originalPlayAnimation then
        originalPlayAnimation = AnimationController.PlayAnimation
        
        AnimationController.PlayAnimation = function(self, animName)
            if animationCancelEnabled then
                local fishingAnims = {
                    "RodThrow",
                    "StartRodCharge",
                    "LoopedRodCharge",
                    "FishCaught",
                    "FishingFailure",
                    "EasyFishReel",
                    "EasyFishReelStart",
                    "ReelingIdle",
                    "EquipIdle"
                }
                
                for _, animCheck in ipairs(fishingAnims) do
                    if animName == animCheck or animName:find(animCheck) then
                        logger:debug("Blocked animation:", animName)
                        return {
                            Play = function() end,
                            Stop = function() end,
                            Destroy = function() end,
                            Ended = {
                                Connect = function() end,
                                Once = function() end
                            }
                        }, nil
                    end
                end
            end
            
            return originalPlayAnimation(self, animName)
        end
        
        logger:info("Animation disable hook installed")
    end

    self:SetupBaitSpawnedHook()
    self:SetupTextEffectListener()
end

function AutoFishFeature:SetupBaitSpawnedHook()
    if not BaitSpawnedEvent then
        logger:warn("BaitSpawnedEvent not available")
        return
    end

    if baitSpawnedConnection then
        baitSpawnedConnection:Disconnect()
    end

    baitSpawnedConnection = BaitSpawnedEvent.OnClientEvent:Connect(function(...)
        if isRunning then
            castCount = castCount + 1
            logger:debug("BaitSpawned - Cast #" .. castCount)
            baitSpawnedFlag = true
            textEffectReceived = false
            
            local config = FISHING_CONFIGS[currentMode]
            
            -- Check: cast 1, 6, 11, 16, 21... (castCount % 5 == 1)
            if config.resetInterval > 0 and (castCount % config.resetInterval == 1) then
                logger:info("🔄 RESET at cast #" .. castCount)
                
                spawn(function()
                    task.wait(0.1)
                    self:CancelAndRestartFromCharge()
                end)
                return
            end
            
            -- Normal flow: wait TextEffect
            logger:debug("Normal flow - waiting for TextEffect")
        end
    end)

    logger:info("BaitSpawned hook ready")
end

function AutoFishFeature:SetupTextEffectListener()
    if not ReplicateTextEffect then
        logger:warn("ReplicateTextEffect not available")
        return
    end
    
    if textEffectConnection then
        textEffectConnection:Disconnect()
    end
    
    textEffectConnection = ReplicateTextEffect.OnClientEvent:Connect(function(data)
        if not isRunning then return end
        
        if not data or not data.TextData then return end
        if not LocalPlayer.Character or not LocalPlayer.Character.Head then return end
        if data.TextData.AttachTo ~= LocalPlayer.Character.Head then return end
        
        logger:info("TextEffect received!")
        textEffectReceived = true
        
        if not spamActive then
            spawn(function()
                local config = FISHING_CONFIGS[currentMode]
                self:StartCompletionSpam(config.spamDelay, config.maxSpamTime)
            end)
        end
    end)
    
    logger:info("TextEffect listener ready")
end

function AutoFishFeature:CancelAndRestartFromCharge()
    if not CancelFishingInputs then
        logger:warn("CancelFishingInputs not available")
        return
    end
    
    logger:info("Executing cancel & restart...")
    
    spamActive = false
    completionCheckActive = false
    
    local success = pcall(function()
        return CancelFishingInputs:InvokeServer()
    end)
    
    if success then
        logger:info("Cancelled - restarting from charge")
        
        baitSpawnedFlag = false
        textEffectReceived = false
        fishingInProgress = false
        
        task.wait(0.2)
        
        if isRunning then
            fishingInProgress = true
            
            spawn(function()
                local config = FISHING_CONFIGS[currentMode]
                
                if not self:ChargeRod(config.chargeTime) then
                    fishingInProgress = false
                    return
                end
                
                if not self:CastRod() then
                    fishingInProgress = false
                    return
                end
                
                baitSpawnedFlag = false
                textEffectReceived = false
                
                logger:info("Restart complete")
                fishingInProgress = false
            end)
        end
    else
        logger:error("Failed to cancel")
    end
end

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
    baitSpawnedFlag = false
    textEffectReceived = false
    castCount = 0
    
    local cfg = FISHING_CONFIGS[currentMode]
    animationCancelEnabled = cfg.disableAllAnimations

    logger:info("Started V5 - Mode:", currentMode)
    logger:info("  - Reset Pattern: 1, 6, 11, 16...")

    self:SetupFishObtainedListener()

    connection = RunService.Heartbeat:Connect(function()
        if not isRunning then return end
        self:SpamFishingLoop()
    end)
end

function AutoFishFeature:Stop()
    if not isRunning then return end

    isRunning = false
    fishingInProgress = false
    spamActive = false
    completionCheckActive = false
    fishCaughtFlag = false
    animationCancelEnabled = false
    baitSpawnedFlag = false
    textEffectReceived = false
    castCount = 0

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
    
    if textEffectConnection then
        textEffectConnection:Disconnect()
        textEffectConnection = nil
    end

    logger:info("Stopped V5")
end

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
    
    baitSpawnedFlag = false
    textEffectReceived = false

    logger:info("Cast executed - waiting for BaitSpawned")

    return true
end

function AutoFishFeature:EquipRod(slot)
    if not EquipTool then return false end

    local success = pcall(function()
        EquipTool:FireServer(slot)
    end)

    return success
end

function AutoFishFeature:ChargeRod(chargeTime)
    if not ChargeFishingRod then return false end
    
    local success = pcall(function()
        return ChargeFishingRod:InvokeServer(math.huge)
    end)
    
    task.wait(chargeTime)
    return success
end

function AutoFishFeature:CastRod()
    if not RequestFishing then return false end

    local success = pcall(function()
        local y = -139.63
        local power = 0.9999120558411321
        return RequestFishing:InvokeServer(y, power)
    end)

    return success
end

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
        if currentMode == "Slow" and not config.skipMinigame then
            logger:info("Slow mode: Animation", config.minigameDuration, "s")
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

function AutoFishFeature:FireCompletion()
    if not FishingCompleted then return false end

    local success = pcall(function()
        FishingCompleted:FireServer()
    end)

    return success
end

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

function AutoFishFeature:UpdateBackpackCount()
    lastBackpackCount = self:GetBackpackItemCount()
end

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
        animDisabled = animationCancelEnabled,
        baitHookReady = baitSpawnedConnection ~= nil,
        textEffectReady = textEffectConnection ~= nil,
        baitSpawned = baitSpawnedFlag,
        textEffectReceived = textEffectReceived,
        castCount = castCount
    }
end

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

function AutoFishFeature:GetAnimationInfo()
    return {
        hookInstalled = originalPlayAnimation ~= nil,
        cancelEnabled = animationCancelEnabled,
        baitHookReady = baitSpawnedConnection ~= nil
    }
end

function AutoFishFeature:Cleanup()
    logger:info("Cleaning up V5...")
    self:Stop()
    
    if originalPlayAnimation and AnimationController then
        AnimationController.PlayAnimation = originalPlayAnimation
        originalPlayAnimation = nil
    end
    
    controls = {}
    remotesInitialized = false
end

return AutoFishFeature
