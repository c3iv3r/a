-- ===========================
-- AUTO FISH FEATURE - SPAM METHOD (with Bait/ReplicateText gating)
-- File: autofish.lua
-- ===========================

local AutoFishFeature = {}
AutoFishFeature.__index = AutoFishFeature

-- ===== Logger (safe fallback) =====
local logger = _G.Logger and _G.Logger.new and _G.Logger:new("AutoFish") or {
    debug = function() end, info = function() end, warn = function() end, error = function() end
}

-- ===== Services =====
local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService        = game:GetService("RunService")
local LocalPlayer       = Players.LocalPlayer

-- ===== Tunables =====
local COALESCE_WINDOW = 0.25 -- detik; “bareng” = kedua event terjadi dalam window ini
local RESTART_DELAY   = 0.05
local POST_CATCH_DELAY = 0.10

-- ===== Network =====
local NetPath
local EquipTool                    -- RE/EquipToolFromHotbar
local ChargeFishingRod             -- RF/ChargeFishingRod
local RequestFishing               -- RF/RequestFishingMinigameStarted
local FishingCompleted             -- RE/FishingCompleted
local FishObtainedNotification     -- RE/ObtainedNewFishNotification

-- Baru:
local ReplicateTextEffect          -- RE/ReplicateTextEffect
local BaitSpawned                  -- RE/BaitSpawned
local CancelFishingInputs          -- RF/CancelFishingInputs

local function initializeRemotes()
    local ok, err = pcall(function()
        NetPath = ReplicatedStorage:WaitForChild("Packages", 5)
            :WaitForChild("_Index", 5)
            :WaitForChild("sleitnick_net@0.2.0", 5)
            :WaitForChild("net", 5)

        EquipTool                = NetPath:WaitForChild("RE/EquipToolFromHotbar", 5)
        ChargeFishingRod         = NetPath:WaitForChild("RF/ChargeFishingRod", 5)
        RequestFishing           = NetPath:WaitForChild("RF/RequestFishingMinigameStarted", 5)
        FishingCompleted         = NetPath:WaitForChild("RE/FishingCompleted", 5)
        FishObtainedNotification = NetPath:WaitForChild("RE/ObtainedNewFishNotification", 5)

        -- New listeners & RF
        ReplicateTextEffect      = NetPath:WaitForChild("RE/ReplicateTextEffect", 5)
        BaitSpawned              = NetPath:WaitForChild("RE/BaitSpawned", 5)
        CancelFishingInputs      = NetPath:WaitForChild("RF/CancelFishingInputs", 5)
    end)
    if not ok then
        logger:warn("initializeRemotes failed:", err)
    end
    return ok
end

-- ===== State =====
local isRunning               = false
local currentMode             = "Fast"
local remotesInitialized      = false

local mainTickConn            = nil
local fishObtainedConn        = nil
local replicateTextConn       = nil
local baitSpawnedConn         = nil

local fishingInProgress       = false   -- kita sedang menjalankan satu siklus (equip->charge->cast)
local awaitingSignals         = false   -- setelah cast, menunggu pasangan event “bareng”
local spamActive              = false
local completionCheckActive   = false
local lastFishTime            = 0
local lastBackpackCount       = 0
local fishCaughtFlag          = false

-- Event coalescing timestamps
local lastReplicateTextAt     = -1
local lastBaitSpawnedAt       = -1

local controls = {}

-- ===== Config =====
local FISHING_CONFIGS = {
    ["Fast"] = {
        chargeTime  = 1.0,
        waitBetween = 0.0,
        rodSlot     = 1,
        spamDelay   = 0.05,
        maxSpamTime = 20,
        skipMinigame = true
    },
    ["Slow"] = {
        chargeTime  = 1.0,
        waitBetween = 1.0,
        rodSlot     = 1,
        spamDelay   = 0.10,
        maxSpamTime = 20,
        skipMinigame = false,
        minigameDuration = 5.0
    }
}

-- ===== Utils: Backpack count =====
function AutoFishFeature:GetBackpackItemCount()
    local count = 0
    if LocalPlayer.Backpack then
        count += #LocalPlayer.Backpack:GetChildren()
    end
    if LocalPlayer.Character then
        for _, ch in ipairs(LocalPlayer.Character:GetChildren()) do
            if ch:IsA("Tool") then count += 1 end
        end
    end
    return count
end

function AutoFishFeature:UpdateBackpackCount()
    lastBackpackCount = self:GetBackpackItemCount()
end

-- ===== Equip / Charge / Cast =====
function AutoFishFeature:EquipRod(slot)
    if not EquipTool then return false end
    return pcall(function() EquipTool:FireServer(slot) end)
end

function AutoFishFeature:ChargeRod(_chargeTime)
    if not ChargeFishingRod then return false end
    -- tetap gunakan pola kamu (nilai besar)
    return pcall(function()
        return ChargeFishingRod:InvokeServer(math.huge)
    end)
end

function AutoFishFeature:CastRod()
    if not RequestFishing then return false end
    return pcall(function()
        local x = -124.63
        local z = 0.9999120558411321
        return RequestFishing:InvokeServer(x, z)
    end)
end

-- ===== Completion =====
function AutoFishFeature:FireCompletion()
    if not FishingCompleted then return false end
    return pcall(function() FishingCompleted:FireServer() end)
end

function AutoFishFeature:CheckFishingCompleted()
    if fishCaughtFlag then return true end
    local cur = self:GetBackpackItemCount()
    if cur > lastBackpackCount then
        lastBackpackCount = cur
        return true
    end
    return false
end

-- ===== Listeners =====
function AutoFishFeature:SetupFishObtainedListener()
    if fishObtainedConn then fishObtainedConn:Disconnect() end
    if not FishObtainedNotification then
        logger:warn("FishObtainedNotification not available")
        return
    end
    fishObtainedConn = FishObtainedNotification.OnClientEvent:Connect(function()
        if not isRunning then return end
        fishCaughtFlag = true
        spamActive = false
        completionCheckActive = false

        task.spawn(function()
            task.wait(POST_CATCH_DELAY)
            fishingInProgress = false
            awaitingSignals = false
            fishCaughtFlag = false
        end)
    end)
end

-- New: gate spam by pairing BaitSpawned + ReplicateTextEffect
function AutoFishFeature:SetupSignalPairListeners()
    -- ReplicateTextEffect
    if replicateTextConn then replicateTextConn:Disconnect() end
    if ReplicateTextEffect then
        replicateTextConn = ReplicateTextEffect.OnClientEvent:Connect(function(...)
            lastReplicateTextAt = tick()
            if not isRunning then return end
            if awaitingSignals then
                -- cek apakah BaitSpawned terjadi “bareng”
                local dt = math.abs(lastReplicateTextAt - lastBaitSpawnedAt)
                if dt <= COALESCE_WINDOW then
                    -- bareng -> start spam
                    self:BeginSpamBySignal()
                end
            end
        end)
    else
        logger:warn("RE/ReplicateTextEffect not available")
    end

    -- BaitSpawned
    if baitSpawnedConn then baitSpawnedConn:Disconnect() end
    if BaitSpawned then
        baitSpawnedConn = BaitSpawned.OnClientEvent:Connect(function(...)
            lastBaitSpawnedAt = tick()
            if not isRunning then return end
            if awaitingSignals then
                local dt = math.abs(lastBaitSpawnedAt - lastReplicateTextAt)
                if dt <= COALESCE_WINDOW then
                    -- bareng -> start spam
                    self:BeginSpamBySignal()
                else
                    -- TIDAK bareng -> Cancel & restart from equip
                    self:CancelInputsAndRestart()
                end
            else
                -- Jika belum menunggu sinyal, abaikan (cast belum terjadi)
            end
        end)
    else
        logger:warn("RE/BaitSpawned not available")
    end
end

function AutoFishFeature:CancelInputsAndRestart()
    -- Matikan spam/cek completion berjalan
    spamActive = false
    completionCheckActive = false

    -- CancelFishingInputs
    if CancelFishingInputs then
        pcall(function()
            CancelFishingInputs:InvokeServer()
        end)
    else
        logger:warn("RF/CancelFishingInputs missing; cannot cancel inputs")
    end

    -- Reset state & restart dari equip
    awaitingSignals = false
    fishingInProgress = false

    task.delay(RESTART_DELAY, function()
        if not isRunning then return end
        -- Mulai ulang 1 siklus penuh (equip->charge->cast) yang baru
        self:StartOneCycle(true) -- force
    end)
end

function AutoFishFeature:BeginSpamBySignal()
    if spamActive then return end
    if not isRunning then return end

    awaitingSignals = false
    -- Mulai spam completion sesuai mode
    local cfg = FISHING_CONFIGS[currentMode]
    self:StartCompletionSpam(cfg.spamDelay, cfg.maxSpamTime, cfg)
end

-- ===== Spam Completion =====
function AutoFishFeature:StartCompletionSpam(delay, maxTime, cfg)
    if spamActive then return end
    spamActive = true
    completionCheckActive = true
    fishCaughtFlag = false
    local t0 = tick()

    -- Update baseline backpack
    self:UpdateBackpackCount()

    task.spawn(function()
        if currentMode == "Slow" and not cfg.skipMinigame then
            task.wait(cfg.minigameDuration)
            if fishCaughtFlag or not isRunning or not spamActive then
                spamActive = false
                completionCheckActive = false
                return
            end
        end

        while isRunning and spamActive and (tick() - t0) < maxTime do
            self:FireCompletion()
            if fishCaughtFlag or self:CheckFishingCompleted() then
                break
            end
            task.wait(delay)
        end

        spamActive = false
        completionCheckActive = false
    end)
end

-- ===== One cycle (equip->charge->cast then await signals) =====
function AutoFishFeature:StartOneCycle(force)
    if fishingInProgress and not force then return end
    fishingInProgress = true
    lastFishTime = tick()

    task.spawn(function()
        local cfg = FISHING_CONFIGS[currentMode]

        if not self:EquipRod(cfg.rodSlot) then
            fishingInProgress = false
            return
        end
        task.wait(0.10)

        if not self:ChargeRod(cfg.chargeTime) then
            fishingInProgress = false
            return
        end

        if not self:CastRod() then
            fishingInProgress = false
            return
        end

        -- Setelah cast: tunggu pasangan sinyal
        awaitingSignals = true
        -- Reset pasangan event window
        lastReplicateTextAt = -1
        lastBaitSpawnedAt   = -1
    end)
end

-- ===== Heartbeat main loop =====
function AutoFishFeature:SpamFishingLoop()
    if fishingInProgress or awaitingSignals or spamActive then return end
    local cfg = FISHING_CONFIGS[currentMode]
    if (tick() - lastFishTime) < cfg.waitBetween then return end
    self:StartOneCycle(false)
end

-- ===== API =====
function AutoFishFeature:Init(guiControls)
    controls = guiControls or {}
    remotesInitialized = initializeRemotes()
    if not remotesInitialized then
        logger:warn("Failed to initialize remotes")
        return false
    end
    self:UpdateBackpackCount()
    logger:info("Initialized AutoFish (event-gated spam)")
    return true
end

function AutoFishFeature:Start(config)
    if isRunning then return end
    if not remotesInitialized then
        logger:warn("Cannot start - remotes not initialized")
        return
    end
    isRunning   = true
    currentMode = (config and config.mode) or "Fast"

    fishingInProgress     = false
    awaitingSignals       = false
    spamActive            = false
    completionCheckActive = false
    fishCaughtFlag        = false
    lastFishTime          = 0

    self:SetupFishObtainedListener()
    self:SetupSignalPairListeners()

    mainTickConn = RunService.Heartbeat:Connect(function()
        if not isRunning then return end
        self:SpamFishingLoop()
    end)
end

function AutoFishFeature:Stop()
    if not isRunning then return end
    isRunning = false
    fishingInProgress     = false
    awaitingSignals       = false
    spamActive            = false
    completionCheckActive = false
    fishCaughtFlag        = false

    if mainTickConn      then mainTickConn:Disconnect()      mainTickConn = nil end
    if fishObtainedConn  then fishObtainedConn:Disconnect()  fishObtainedConn = nil end
    if replicateTextConn then replicateTextConn:Disconnect() replicateTextConn = nil end
    if baitSpawnedConn   then baitSpawnedConn:Disconnect()   baitSpawnedConn = nil end
end

function AutoFishFeature:Cleanup()
    self:Stop()
    controls = {}
    remotesInitialized = false
end

function AutoFishFeature:GetStatus()
    return {
        running           = isRunning,
        mode              = currentMode,
        inProgress        = fishingInProgress,
        awaitingSignals   = awaitingSignals,
        spamming          = spamActive,
        lastCatchTime     = lastFishTime,
        fishCaughtFlag    = fishCaughtFlag,
        backpackCount     = lastBackpackCount,
        remotesReady      = remotesInitialized,
        hasCancelRF       = CancelFishingInputs ~= nil,
        hasRepTxt         = ReplicateTextEffect ~= nil,
        hasBaitSpawned    = BaitSpawned ~= nil,
    }
end

function AutoFishFeature:SetMode(mode)
    if FISHING_CONFIGS[mode] then
        currentMode = mode
        return true
    end
    return false
end

function AutoFishFeature:GetNotificationInfo()
    return {
        hasNotificationRemote = FishObtainedNotification ~= nil,
        listenerConnected     = fishObtainedConn ~= nil,
        fishCaughtFlag        = fishCaughtFlag
    }
end

return AutoFishFeature
