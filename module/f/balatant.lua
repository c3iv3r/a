-- ===========================
-- AUTO FISH V6 - CAUGHT-BASED DETECTION
-- Patokan: leaderstats.Caught value change = fishing selesai
-- Pattern: BaitSpawned → ReplicateTextEffect (dalam configurable time) = normal
--          BaitSpawned tanpa ReplicateTextEffect = cancel
-- Safety Net: Caught ga naik dalam X detik = cancel + retry
-- Delay configurable dari GUI
-- ===========================

local AutoFishFeature = {}
AutoFishFeature.__index = AutoFishFeature

local logger = _G.Logger and _G.Logger.new("Balatant") or {
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
local EquipTool, ChargeFishingRod, RequestFishing, FishingCompleted, BaitSpawnedEvent, ReplicateTextEffect, CancelFishingInputs

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
local spamConnection = nil
local caughtConnection = nil
local baitSpawnedConnection = nil
local replicateTextConnection = nil
local safetyNetConnection = nil
local controls = {}
local fishingInProgress = false
local remotesInitialized = false
local cancelInProgress = false

-- Spam & Animation
local spamActive = false
local animationCancelEnabled = true

-- Caught tracking
local lastCaughtValue = 0
local lastCaughtTime = 0

-- Detection tracking
local waitingForReplicateText = false
local replicateTextReceived = false

-- Configurable delays
local WAIT_WINDOW = 0.6  -- Default 600ms
local SAFETY_TIMEOUT = 3  -- Default 3s
local safetyNetTriggered = false

-- Animation hooks
local originalPlayAnimation = nil

-- Rod configs
local FISHING_CONFIGS = {
    ["Fast"] = {
        chargeTime = 0.2,
        rodSlot = 1,
        spamDelay = 0.01,
        disableAllAnimations = true
    },
    ["Slow"] = {
        chargeTime = 1.0,
        rodSlot = 1,
        spamDelay = 0.1,
        disableAllAnimations = false
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
    self:InitializeCaughtTracking()

    logger:info("Initialized V6 - Caught-based detection + configurable delays")
    return true
end

function AutoFishFeature:InitializeCaughtTracking()
    local leaderstats = LocalPlayer:FindFirstChild("leaderstats")
    if leaderstats then
        local caught = leaderstats:FindFirstChild("Caught")
        if caught and caught:IsA("IntValue") then
            lastCaughtValue = caught.Value
            logger:info("Initial Caught value: " .. lastCaughtValue)
        end
    end
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

    replicateTextConnection = ReplicateTextEffect.OnClientEvent:Connect(function(data)
        if not isRunning then return end
        
        if not data or not data.TextData then 
            return 
        end
        
        if not LocalPlayer.Character or not LocalPlayer.Character:FindFirstChild("Head") then
            return
        end
        
        if data.TextData.AttachTo ~= LocalPlayer.Character.Head then
            return
        end
        
        logger:info("📝 ReplicateTextEffect received")
        
        if waitingForReplicateText then
            replicateTextReceived = true
            logger:info("✅ ReplicateTextEffect confirmed - NORMAL flow")
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

    baitSpawnedConnection = BaitSpawnedEvent.OnClientEvent:Connect(function(player, rodName, position)
        if not isRunning or cancelInProgress then return end
        
        if player ~= LocalPlayer then
            return
        end

        logger:info("🎯 BaitSpawned - Buffer 50ms kemudian wait " .. (WAIT_WINDOW * 1000) .. "ms...")

        spawn(function()
            -- Buffer time biar ReplicateTextEffect yg dateng bareng keburu masuk
            task.wait(0.05)
            
            if not isRunning or cancelInProgress then return end
            
            waitingForReplicateText = true
            local alreadyReceived = replicateTextReceived
            replicateTextReceived = false
            
            -- Kalo udah dapet sebelum wait, langsung pass
            if alreadyReceived then
                logger:info("✅ ReplicateTextEffect SUDAH diterima (race condition handled)")
                waitingForReplicateText = false
                return
            end
            
            task.wait(WAIT_WINDOW)
            
            if not isRunning or cancelInProgress then 
                waitingForReplicateText = false
                replicateTextReceived = false
                return 
            end
            
            waitingForReplicateText = false
            
            if replicateTextReceived then
                logger:info("✅ BaitSpawned + ReplicateTextEffect - NORMAL")
            else
                logger:info("🔄 BaitSpawned SENDIRIAN - CANCEL!")
                self:CancelAndRestart()
            end
            
            replicateTextReceived = false
        end)
    end)

    logger:info("BaitSpawned hook ready")
end

function AutoFishFeature:SetupCaughtListener()
    if caughtConnection then
        caughtConnection:Disconnect()
    end

    local leaderstats = LocalPlayer:FindFirstChild("leaderstats")
    if not leaderstats then
        logger:warn("leaderstats not found")
        return
    end

    local caught = leaderstats:FindFirstChild("Caught")
    if not caught or not caught:IsA("IntValue") then
        logger:warn("Caught stat not found")
        return
    end

    lastCaughtValue = caught.Value

    caughtConnection = caught:GetPropertyChangedSignal("Value"):Connect(function()
        local newValue = caught.Value
        
        if newValue > lastCaughtValue and isRunning and not cancelInProgress then
            logger:info("🎣 CAUGHT INCREASED! " .. lastCaughtValue .. " → " .. newValue)
            
            lastCaughtValue = newValue
            lastCaughtTime = tick()
            
            fishingInProgress = false
            waitingForReplicateText = false
            replicateTextReceived = false
            safetyNetTriggered = false
            
            task.wait(0.05)
            
            if isRunning and not cancelInProgress then
                self:ChargeAndCast()
            end
        end
    end)

    logger:info("Caught listener ready (current: " .. lastCaughtValue .. ")")
end

function AutoFishFeature:StartSafetyNet()
    if safetyNetConnection then
        safetyNetConnection:Disconnect()
    end

    lastCaughtTime = tick()

    safetyNetConnection = RunService.Heartbeat:Connect(function()
        if not isRunning or cancelInProgress or safetyNetTriggered then return end

        local currentTime = tick()
        local timeSinceCaught = currentTime - lastCaughtTime

        if timeSinceCaught >= SAFETY_TIMEOUT then
            safetyNetTriggered = true
            logger:warn("⚠️ SAFETY NET: Caught ga naik dalam " .. math.floor(timeSinceCaught) .. " detik!")
            self:SafetyNetCancel()
        end
    end)

    logger:info("🛡️ Safety Net active - timeout: " .. SAFETY_TIMEOUT .. "s")
end

function AutoFishFeature:StopSafetyNet()
    if safetyNetConnection then
        safetyNetConnection:Disconnect()
        safetyNetConnection = nil
    end
end

function AutoFishFeature:SafetyNetCancel()
    if not CancelFishingInputs or cancelInProgress then return end

    cancelInProgress = true
    logger:info("🛡️ Safety Net: Executing double cancel...")

    local success1 = pcall(function()
        return CancelFishingInputs:InvokeServer()
    end)
    
    task.wait(0.2)
    
    local success2 = pcall(function()
        return CancelFishingInputs:InvokeServer()
    end)

    if success1 or success2 then
        logger:info("✅ Safety Net: Cancelled")
        
        fishingInProgress = false
        waitingForReplicateText = false
        replicateTextReceived = false
        lastCaughtTime = tick()
        
        task.wait(0.2)

        if isRunning then
            cancelInProgress = false
            safetyNetTriggered = false
            self:ChargeAndCast()
        else
            cancelInProgress = false
        end
    else
        logger:error("❌ Safety Net: Failed to cancel")
        fishingInProgress = false
        cancelInProgress = false
        safetyNetTriggered = false
        lastCaughtTime = tick()
    end
end

function AutoFishFeature:CancelAndRestart()
    if not CancelFishingInputs or cancelInProgress then return end

    cancelInProgress = true
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

function AutoFishFeature:ChargeAndCast()
    if fishingInProgress or cancelInProgress then return end

    fishingInProgress = true
    local config = FISHING_CONFIGS[currentMode]

    logger:info("⚡ Charge > Cast")

    spawn(function()
        if not self:ChargeRod(config.chargeTime) then
            logger:warn("Charge failed")
            fishingInProgress = false
            return
        end

        task.wait(0.05)

        if not self:CastRod() then
            logger:warn("Cast failed")
            fishingInProgress = false
            return
        end

        logger:info("Cast done")
    end)
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
    waitingForReplicateText = false
    replicateTextReceived = false
    cancelInProgress = false
    safetyNetTriggered = false

    if config.waitWindow then
        WAIT_WINDOW = config.waitWindow
    end
    if config.safetyTimeout then
        SAFETY_TIMEOUT = config.safetyTimeout
    end

    local cfg = FISHING_CONFIGS[currentMode]
    animationCancelEnabled = cfg.disableAllAnimations

    logger:info("🚀 Started V6 - Mode: " .. currentMode)
    logger:info("📋 Wait Window: " .. (WAIT_WINDOW * 1000) .. "ms | Safety Timeout: " .. SAFETY_TIMEOUT .. "s")

    self:InitializeCaughtTracking()
    self:SetupReplicateTextHook()
    self:SetupBaitSpawnedHook()
    self:SetupCaughtListener()
    
    self:StartCompletionSpam(cfg.spamDelay)
    self:StartSafetyNet()

    spawn(function()
        if not self:EquipRod(cfg.rodSlot) then
            logger:error("Failed to equip rod")
            return
        end

        task.wait(0.2)

        lastCaughtTime = tick()
        self:ChargeAndCast()
    end)
end

function AutoFishFeature:Stop()
    if not isRunning then return end

    isRunning = false
    fishingInProgress = false
    spamActive = false
    animationCancelEnabled = false
    waitingForReplicateText = false
    replicateTextReceived = false
    cancelInProgress = false
    safetyNetTriggered = false

    self:StopSafetyNet()

    if spamConnection then
        spamConnection:Disconnect()
        spamConnection = nil
    end

    if caughtConnection then
        caughtConnection:Disconnect()
        caughtConnection = nil
    end

    if baitSpawnedConnection then
        baitSpawnedConnection:Disconnect()
        baitSpawnedConnection = nil
    end

    if replicateTextConnection then
        replicateTextConnection:Disconnect()
        replicateTextConnection = nil
    end

    logger:info("⛔ Stopped V6")
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
    logger:info("🔥 Starting FishingCompleted spam")

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

function AutoFishFeature:SetDelays(waitWindow, safetyTimeout)
    if waitWindow then
        WAIT_WINDOW = math.max(0.1, math.min(5, waitWindow))
        logger:info("Wait Window set to: " .. (WAIT_WINDOW * 1000) .. "ms")
    end
    
    if safetyTimeout then
        SAFETY_TIMEOUT = math.max(1, math.min(30, safetyTimeout))
        logger:info("Safety Timeout set to: " .. SAFETY_TIMEOUT .. "s")
    end
end

function AutoFishFeature:GetStatus()
    local timeSinceCaught = lastCaughtTime > 0 and (tick() - lastCaughtTime) or 0
    
    return {
        running = isRunning,
        mode = currentMode,
        inProgress = fishingInProgress,
        spamming = spamActive,
        remotesReady = remotesInitialized,
        caughtListenerReady = caughtConnection ~= nil,
        animDisabled = animationCancelEnabled,
        baitHookReady = baitSpawnedConnection ~= nil,
        replicateTextHookReady = replicateTextConnection ~= nil,
        waitingForReplicateText = waitingForReplicateText,
        cancelInProgress = cancelInProgress,
        safetyNetActive = safetyNetConnection ~= nil,
        safetyNetTriggered = safetyNetTriggered,
        lastCaughtValue = lastCaughtValue,
        waitWindow = WAIT_WINDOW,
        safetyTimeout = SAFETY_TIMEOUT,
        timeSinceCaught = math.floor(timeSinceCaught),
        timeRemaining = math.max(0, SAFETY_TIMEOUT - timeSinceCaught)
    }
end

function AutoFishFeature:SetMode(mode)
    if FISHING_CONFIGS[mode] then
        currentMode = mode
        local cfg = FISHING_CONFIGS[mode]
        animationCancelEnabled = cfg.disableAllAnimations

        logger:info("Mode: " .. mode)
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
        safetyNetActive = safetyNetConnection ~= nil
    }
end

function AutoFishFeature:Cleanup()
    logger:info("Cleaning up V6...")
    self:Stop()

    if originalPlayAnimation and AnimationController then
        AnimationController.PlayAnimation = originalPlayAnimation
        originalPlayAnimation = nil
    end

    controls = {}
    remotesInitialized = false
end

return AutoFishFeature