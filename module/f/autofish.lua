-- ===========================
-- AUTO FISH V5 - ANIMATION CANCEL METHOD [STABLE]
-- Pattern: BaitSpawned ke-1 cancel, ke-2-5 normal, ke-6 cancel, repeat
-- Spam FishingCompleted non-stop dari start sampai stop
-- Patokan mancing selesai: ObtainedNewFishNotification
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
local controls = {}
local fishingInProgress = false
local remotesInitialized = false

-- Spam tracking
local spamActive = false
local animationCancelEnabled = true

-- BaitSpawned counter sejak start
local baitSpawnedCount = 0

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
        cancelPattern = {1, 6, 11, 16, 21, 26}  -- BaitSpawned ke-1, 6, 11, 16... di-cancel
    },
    ["Slow"] = {
        chargeTime = 1.0,
        waitBetween = 1,
        rodSlot = 1,
        spamDelay = 0.1,
        disableAllAnimations = false,
        cancelPattern = {}  -- No cancel
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

    logger:info("Initialized V5 - BaitSpawned pattern mode")
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

    self:SetupBaitSpawnedHook()
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
        if not isRunning then return end
        
        -- Increment counter saat BaitSpawned muncul
        baitSpawnedCount = baitSpawnedCount + 1
        logger:info("🎯 BaitSpawned #" .. baitSpawnedCount)
        
        -- Cek apakah BaitSpawned ini perlu di-cancel (pattern: 1, 6, 11, 16...)
        local shouldCancel = false
        
        -- Pattern: 1, 6, 11, 16, 21... = setiap 5 bait, dimulai dari 1
        if baitSpawnedCount == 1 or (baitSpawnedCount > 1 and (baitSpawnedCount - 1) % 5 == 0) then
            shouldCancel = true
        end
        
        if shouldCancel then
            logger:info("🔄 CANCEL BaitSpawned #" .. baitSpawnedCount)
            
            spawn(function()
                task.wait(0.05)  -- Minimal delay
                self:CancelAndRestart()
            end)
        end
        -- Else: biarkan normal sampai ObtainedNewFishNotification
    end)

    logger:info("BaitSpawned hook ready")
end

function AutoFishFeature:CancelAndRestart()
    if not CancelFishingInputs then
        logger:warn("CancelFishingInputs not available")
        return
    end
    
    logger:info("Executing cancel...")
    
    local success = pcall(function()
        return CancelFishingInputs:InvokeServer()
    end)
    
    if success then
        logger:info("✅ Cancelled - restarting Charge > Cast")
        
        fishingInProgress = false
        task.wait(0.1)
        
        if isRunning then
            self:ChargeAndCast()
        end
    else
        logger:error("❌ Failed to cancel")
        fishingInProgress = false
    end
end

function AutoFishFeature:ChargeAndCast()
    if fishingInProgress then return end
    
    fishingInProgress = true
    local config = FISHING_CONFIGS[currentMode]
    
    logger:info("⚡ Charge > Cast")
    
    if not self:ChargeRod(config.chargeTime) then
        fishingInProgress = false
        return
    end
    
    if not self:CastRod() then
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
    baitSpawnedCount = 0  -- Reset counter
    
    local cfg = FISHING_CONFIGS[currentMode]
    animationCancelEnabled = cfg.disableAllAnimations

    logger:info("🚀 Started V5 - Mode:", currentMode)
    logger:info("📋 Pattern: BaitSpawned #1, #6, #11, #16... akan di-cancel")

    -- Start spam FishingCompleted IMMEDIATELY
    self:StartCompletionSpam(cfg.spamDelay)
    
    self:SetupFishObtainedListener()

    -- Initial equip + charge + cast
    spawn(function()
        if not self:EquipRod(cfg.rodSlot) then
            logger:error("Failed to equip rod")
            return
        end
        
        task.wait(0.2)
        
        -- Start first charge
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
        if isRunning then
            logger:info("🎣 FISH OBTAINED!")
            fishingInProgress = false
            
            spawn(function()
                task.wait(0.15)
                if isRunning then
                    self:ChargeAndCast()
                end
            end)
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
        baitSpawnedCount = baitSpawnedCount
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