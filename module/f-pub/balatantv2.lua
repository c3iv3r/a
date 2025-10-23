-- ===========================
-- AUTO FISH V5 - ANIMATION CANCEL METHOD [STABLE + SAFETY NET]
-- Pattern: BaitSpawned → ReplicateTextEffect (dalam 100ms) = normal
--          BaitSpawned tanpa ReplicateTextEffect = cancel
-- Spam FishingCompleted non-stop dari start sampai stop
-- Patokan mancing selesai: ObtainedNewFishNotification
-- SAFETY NET: Kalo BaitSpawned ga muncul dalam 10 detik = CancelFishing + retry
-- Timer reset setiap BaitSpawned muncul (kayak AutoFixFishing)
-- NO ANIMATION HOOKS - Pure detection method
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

-- BaitSpawned counter sejak start
local baitSpawnedCount = 0

-- Tracking untuk deteksi ReplicateTextEffect setelah BaitSpawned
local waitingForReplicateText = false
local replicateTextReceived = false
local WAIT_WINDOW = 0.6

-- Safety Net tracking (kayak AutoFixFishing)
local lastBaitSpawnedTime = 0
local SAFETY_TIMEOUT = 3
local safetyNetTriggered = false

-- Rod configs
local FISHING_CONFIGS = {
    ["Fast"] = {
        chargeTime = 0.2,
        waitBetween = 0,
        rodSlot = 1,
        spamDelay = 0.01
    },
    ["Slow"] = {
        chargeTime = 1.0,
        waitBetween = 1,
        rodSlot = 1,
        spamDelay = 0.1
    }
}

function AutoFishFeature:Init(guiControls)
    controls = guiControls or {}
    remotesInitialized = initializeRemotes()

    if not remotesInitialized then
        logger:warn("Failed to initialize remotes")
        return false
    end

    self:SetupReplicateTextHook()
    self:SetupBaitSpawnedHook()

    logger:info("Initialized V5 - Smart BaitSpawned→ReplicateText detection + Safety Net")
    return true
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
        
        -- VALIDATE: Cek apakah ini punya LocalPlayer
        if not data or not data.TextData then 
            return 
        end
        
        -- CRITICAL CHECK: AttachTo harus Head LocalPlayer
        if not LocalPlayer.Character or not LocalPlayer.Character:FindFirstChild("Head") then
            return
        end
        
        if data.TextData.AttachTo ~= LocalPlayer.Character.Head then
            return -- Bukan punya kita, ignore!
        end
        
        logger:info("📝 ReplicateTextEffect received (LocalPlayer)")
        
        if waitingForReplicateText then
            replicateTextReceived = true
            logger:info("✅ ReplicateTextEffect confirmed - BIARKAN NORMAL")
        end
    end)

    logger:info("ReplicateTextEffect hook ready (LocalPlayer only)")
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
        
        -- CRITICAL CHECK: Player parameter HARUS LocalPlayer
        if player ~= LocalPlayer then
            return -- Bukan punya kita, ignore!
        end

        baitSpawnedCount = baitSpawnedCount + 1
        lastBaitSpawnedTime = tick()
        safetyNetTriggered = false
        
        logger:info("🎯 BaitSpawned #" .. baitSpawnedCount .. " (LocalPlayer) - Timer reset! Waiting for ReplicateTextEffect...")

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

    logger:info("BaitSpawned hook ready (LocalPlayer only)")
end

function AutoFishFeature:StartSafetyNet()
    if safetyNetConnection then
        safetyNetConnection:Disconnect()
    end

    lastBaitSpawnedTime = tick()

    safetyNetConnection = RunService.Heartbeat:Connect(function()
        if not isRunning or cancelInProgress or safetyNetTriggered then return end

        local currentTime = tick()
        local timeSinceLastBait = currentTime - lastBaitSpawnedTime

        if timeSinceLastBait >= SAFETY_TIMEOUT then
            safetyNetTriggered = true
            logger:warn("⚠️ SAFETY NET: BaitSpawned ga muncul dalam " .. math.floor(timeSinceLastBait) .. " detik!")
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
    lastBaitSpawnedTime = 0
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
        logger:info("✅ Safety Net: Cancelled (1:" .. tostring(success1) .. " 2:" .. tostring(success2) .. ")")
        
        fishingInProgress = false
        waitingForReplicateText = false
        replicateTextReceived = false
        
        -- RESET TIMER (kayak AutoFixFishing)
        lastBaitSpawnedTime = tick()
        
        task.wait(0.2)

        if isRunning then
            cancelInProgress = false
            safetyNetTriggered = false  -- RESET FLAG biar bisa trigger lagi nanti
            self:ChargeAndCast()
        else
            cancelInProgress = false
        end
    else
        logger:error("❌ Safety Net: Failed to cancel")
        fishingInProgress = false
        cancelInProgress = false
        safetyNetTriggered = false
        lastBaitSpawnedTime = tick()  -- RESET TIMER juga kalo fail
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

    if not self:ChargeRod(config.chargeTime) then
        logger:warn("Charge failed")
        fishingInProgress = false
        return
    end

    if not self:CastRod() then
        logger:warn("Cast failed")
        fishingInProgress = false
        return
    end

    logger:info("Cast done, waiting for BaitSpawned...")
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
    lastBaitSpawnedTime = 0
    safetyNetTriggered = false

    local cfg = FISHING_CONFIGS[currentMode]

    logger:info("🚀 Started V5 - Mode:", currentMode)
    logger:info("📋 Detection: BaitSpawned → wait 150ms → if no ReplicateTextEffect = cancel")
    logger:info("🛡️ Safety Net: " .. SAFETY_TIMEOUT .. "s timeout, reset setiap BaitSpawned")

    self:SetupReplicateTextHook()
    self:SetupBaitSpawnedHook()
    self:SetupFishObtainedListener()
    
    self:StartCompletionSpam(cfg.spamDelay)
    self:StartSafetyNet()

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
    baitSpawnedCount = 0
    waitingForReplicateText = false
    replicateTextReceived = false
    cancelInProgress = false
    lastBaitSpawnedTime = 0
    safetyNetTriggered = false

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
            
            fishingInProgress = false
            waitingForReplicateText = false
            replicateTextReceived = false
            safetyNetTriggered = false
            
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
    local timeSinceLastBait = lastBaitSpawnedTime > 0 and (tick() - lastBaitSpawnedTime) or 0
    
    return {
        running = isRunning,
        mode = currentMode,
        inProgress = fishingInProgress,
        spamming = spamActive,
        remotesReady = remotesInitialized,
        listenerReady = fishObtainedConnection ~= nil,
        baitHookReady = baitSpawnedConnection ~= nil,
        replicateTextHookReady = replicateTextConnection ~= nil,
        baitSpawnedCount = baitSpawnedCount,
        waitingForReplicateText = waitingForReplicateText,
        cancelInProgress = cancelInProgress,
        safetyNetActive = safetyNetConnection ~= nil,
        safetyNetTriggered = safetyNetTriggered,
        safetyTimeout = SAFETY_TIMEOUT,
        timeSinceLastBait = math.floor(timeSinceLastBait),
        timeRemaining = math.max(0, SAFETY_TIMEOUT - timeSinceLastBait)
    }
end

function AutoFishFeature:SetMode(mode)
    if FISHING_CONFIGS[mode] then
        currentMode = mode
        logger:info("Mode:", mode)
        return true
    end
    return false
end

function AutoFishFeature:GetAnimationInfo()
    return {
        baitHookReady = baitSpawnedConnection ~= nil,
        replicateTextHookReady = replicateTextConnection ~= nil,
        safetyNetActive = safetyNetConnection ~= nil
    }
end

function AutoFishFeature:Cleanup()
    logger:info("Cleaning up V5...")
    self:Stop()

    controls = {}
    remotesInitialized = false
end

return AutoFishFeature