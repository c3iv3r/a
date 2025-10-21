-- ===========================
-- AUTO FISH V5 - ANIMATION CANCEL METHOD [STABLE + SAFETY NET]
-- Pattern: BaitSpawned → ReplicateTextEffect (dalam 100ms) = normal
--          BaitSpawned tanpa ReplicateTextEffect = cancel
-- Spam FishingCompleted non-stop dari start sampai stop
-- Patokan mancing selesai: ObtainedNewFishNotification
-- SAFETY NET: Kalo BaitSpawned ga muncul dalam 10 detik = CancelFishing + retry
-- ===========================

local AutoFishFeature = {}
AutoFishFeature.__index = AutoFishFeature

local logger = _G.Logger and _G.Logger.new("BALATANT") or {
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
local replicateTextConnection = nil
local safetyNetConnection = nil
local controls = {}
local fishingInProgress = false
local remotesInitialized = false
local cancelInProgress = false

-- Spam tracking
local spamActive = false
local animationCancelEnabled = true

-- BaitSpawned counter sejak start
local baitSpawnedCount = 0

-- Tracking untuk deteksi ReplicateTextEffect setelah BaitSpawned
local waitingForReplicateText = false
local replicateTextReceived = false
local WAIT_WINDOW = 0.6

-- Safety Net tracking
local lastCastTime = 0
local SAFETY_TIMEOUT = 5
local safetyNetActive = false

-- Animation hooks
local originalPlayAnimation = nil

-- Rod configs
local FISHING_CONFIGS = {
    ["Fast"] = {
        chargeTime = 0.5,
        waitBetween = 0,
        rodSlot = 1,
        spamDelay = 0.05,
        disableAllAnimations = true,
        maxRetries = 3
    },
    ["Slow"] = {
        chargeTime = 1.0,
        waitBetween = 1,
        rodSlot = 1,
        spamDelay = 0.1,
        disableAllAnimations = false,
        maxRetries = 3
    }
}

function AutoFishFeature:Init(guiControls)
    controls = guiControls or {}
    remotesInitialized = initializeRemotes()

    if not remotesInitialized then
        logger:warn("Failed to initialize remotes")
        return false
    end

    self:SetupAnimationHooks()

    logger:info("Initialized V5 - Smart BaitSpawned→ReplicateText detection + Safety Net")
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

    self:SetupReplicateTextHook()
    self:SetupBaitSpawnedHook()
end

function AutoFishFeature:SetupReplicateTextHook()
    if not ReplicateTextEffect then
        logger:warn("ReplicateTextEffect not available")
        return
    end

    if replicateTextConnection then
        replicateTextConnection:Disconnect()
    end

    replicateTextConnection = ReplicateTextEffect.OnClientEvent:Connect(function(...)
        if not isRunning then return end
        
        logger:info("📝 ReplicateTextEffect received")
        
        if waitingForReplicateText then
            replicateTextReceived = true
            logger:info("✅ ReplicateTextEffect confirmed - BIARKAN NORMAL")
        end
    end)

    logger:info("ReplicateTextEffect hook ready")
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
        if not isRunning or cancelInProgress then return end

        baitSpawnedCount = baitSpawnedCount + 1
        safetyNetActive = false
        
        logger:info("🎯 BaitSpawned #" .. baitSpawnedCount .. " - Waiting for ReplicateTextEffect...")

        waitingForReplicateText = true
        replicateTextReceived = false

        spawn(function()
            task.wait(WAIT_WINDOW)
            
            if not isRunning or cancelInProgress then 
                waitingForReplicateText = false
                replicateTextReceived = false
                return 
            end
            
            waitingForReplicateText = false
            
            if replicateTextReceived then
                logger:info("✅ BaitSpawned + ReplicateTextEffect - NORMAL flow")
            else
                logger:info("🔄 BaitSpawned SENDIRIAN - CANCEL!")
                self:CancelAndRestart()
            end
            
            replicateTextReceived = false
        end)
    end)

    logger:info("BaitSpawned hook ready")
end

function AutoFishFeature:StartSafetyNet()
    if safetyNetConnection then
        safetyNetConnection:Disconnect()
    end

    safetyNetActive = true
    lastCastTime = tick()

    safetyNetConnection = RunService.Heartbeat:Connect(function()
        if not isRunning or not safetyNetActive or cancelInProgress then return end

        local elapsed = tick() - lastCastTime

        if elapsed >= SAFETY_TIMEOUT then
            logger:warn("⚠️ SAFETY NET: BaitSpawned ga muncul dalam " .. SAFETY_TIMEOUT .. " detik!")
            safetyNetActive = false
            self:SafetyNetCancel()
        end
    end)

    logger:info("🛡️ Safety Net active - timeout: " .. SAFETY_TIMEOUT .. "s")
end

function AutoFishFeature:StopSafetyNet()
    safetyNetActive = false
    if safetyNetConnection then
        safetyNetConnection:Disconnect()
        safetyNetConnection = nil
    end
end

function AutoFishFeature:SafetyNetCancel()
    if not CancelFishingInputs or cancelInProgress then return end

    cancelInProgress = true
    logger:info("🛡️ Safety Net: Executing cancel...")

    local success = pcall(function()
        return CancelFishingInputs:InvokeServer()
    end)

    if success then
        logger:info("✅ Safety Net: Cancelled")
        
        fishingInProgress = false
        waitingForReplicateText = false
        replicateTextReceived = false
        
        task.wait(0.15)

        if isRunning then
            cancelInProgress = false
            self:ChargeAndCast()
        else
            cancelInProgress = false
        end
    else
        logger:error("❌ Safety Net: Failed to cancel")
        fishingInProgress = false
        cancelInProgress = false
    end
end

function AutoFishFeature:CancelAndRestart()
    if not CancelFishingInputs or cancelInProgress then return end

    cancelInProgress = true
    self:StopSafetyNet()
    
    logger:info("Executing cancel...")

    local success = pcall(function()
        return CancelFishingInputs:InvokeServer()
    end)

    if success then
        logger:info("✅ Cancelled")
        
        fishingInProgress = false
        waitingForReplicateText = false
        replicateTextReceived = false
        
        task.wait(0.15)

        if isRunning then
            cancelInProgress = false
            self:ChargeAndCast()
        else
            cancelInProgress = false
        end
    else
        logger:error("❌ Failed to cancel")
        fishingInProgress = false
        cancelInProgress = false
    end
end

function AutoFishFeature:ChargeAndCast(retryCount)
    if fishingInProgress or cancelInProgress then return end

    retryCount = retryCount or 0
    local config = FISHING_CONFIGS[currentMode]

    if retryCount >= config.maxRetries then
        logger:error("❌ Max retries reached (" .. config.maxRetries .. ")")
        fishingInProgress = false
        return
    end

    fishingInProgress = true

    if retryCount > 0 then
        logger:info("🔄 Retry #" .. retryCount)
    end

    logger:info("⚡ Charge > Cast")

    if not self:ChargeRod(config.chargeTime) then
        logger:warn("Charge failed, retrying...")
        fishingInProgress = false
        task.wait(0.3)
        self:ChargeAndCast(retryCount + 1)
        return
    end

    if not self:CastRod() then
        logger:warn("Cast failed, retrying...")
        fishingInProgress = false
        task.wait(0.3)
        self:ChargeAndCast(retryCount + 1)
        return
    end

    logger:info("Cast done, waiting for BaitSpawned...")
    self:StartSafetyNet()
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
    baitSpawnedCount = 0
    waitingForReplicateText = false
    replicateTextReceived = false
    cancelInProgress = false
    safetyNetActive = false

    local cfg = FISHING_CONFIGS[currentMode]
    animationCancelEnabled = cfg.disableAllAnimations

    logger:info("🚀 Started V5 - Mode:", currentMode)
    logger:info("📋 Detection: BaitSpawned → wait 150ms → if no ReplicateTextEffect = cancel")
    logger:info("🛡️ Safety Net: " .. SAFETY_TIMEOUT .. "s timeout for BaitSpawned")

    self:SetupReplicateTextHook()
    self:SetupBaitSpawnedHook()
    self:SetupFishObtainedListener()
    
    self:StartCompletionSpam(cfg.spamDelay)

    spawn(function()
        if not self:EquipRod(cfg.rodSlot) then
            logger:error("Failed to equip rod")
            return
        end

        task.wait(0.2)

        self:ChargeAndCast()
    end)
end

function AutoFishFeature:Stop()
    if not isRunning then return end

    isRunning = false
    fishingInProgress = false
    spamActive = false
    animationCancelEnabled = false
    baitSpawnedCount = 0
    waitingForReplicateText = false
    replicateTextReceived = false
    cancelInProgress = false
    safetyNetActive = false

    self:StopSafetyNet()

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

    if replicateTextConnection then
        replicateTextConnection:Disconnect()
        replicateTextConnection = nil
    end

    logger:info("⛔ Stopped V5")
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
        if isRunning and not cancelInProgress then
            logger:info("🎣 FISH OBTAINED!")
            
            self:StopSafetyNet()
            
            fishingInProgress = false
            waitingForReplicateText = false
            replicateTextReceived = false
            
            task.wait(0.1)
            
            if isRunning and not cancelInProgress then
                self:ChargeAndCast()
            end
        end
    end)

    logger:info("Fish obtained listener ready")
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

function AutoFishFeature:StartCompletionSpam(delay)
    if spamActive then return end

    spamActive = true
    logger:info("🔥 Starting NON-STOP FishingCompleted spam")

    spawn(function()
        while spamActive and isRunning do
            self:FireCompletion()
            task.wait(delay)
        end
        logger:info("Spam stopped")
    end)
end

function AutoFishFeature:FireCompletion()
    if not FishingCompleted then return false end

    pcall(function()
        FishingCompleted:FireServer()
    end)

    return true
end

function AutoFishFeature:GetStatus()
    return {
        running = isRunning,
        mode = currentMode,
        inProgress = fishingInProgress,
        spamming = spamActive,
        remotesReady = remotesInitialized,
        listenerReady = fishObtainedConnection ~= nil,
        animDisabled = animationCancelEnabled,
        baitHookReady = baitSpawnedConnection ~= nil,
        replicateTextHookReady = replicateTextConnection ~= nil,
        baitSpawnedCount = baitSpawnedCount,
        waitingForReplicateText = waitingForReplicateText,
        cancelInProgress = cancelInProgress,
        safetyNetActive = safetyNetActive,
        safetyTimeout = SAFETY_TIMEOUT
    }
end

function AutoFishFeature:SetMode(mode)
    if FISHING_CONFIGS[mode] then
        currentMode = mode
        local cfg = FISHING_CONFIGS[mode]
        animationCancelEnabled = cfg.disableAllAnimations

        logger:info("Mode:", mode)
        return true
    end
    return false
end

function AutoFishFeature:GetAnimationInfo()
    return {
        hookInstalled = originalPlayAnimation ~= nil,
        cancelEnabled = animationCancelEnabled,
        baitHookReady = baitSpawnedConnection ~= nil,
        replicateTextHookReady = replicateTextConnection ~= nil,
        safetyNetActive = safetyNetActive
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