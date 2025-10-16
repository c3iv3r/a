-- ===========================
-- AUTO FISH FEATURE - SPAM METHOD (PATCHED V4)
-- File: autofishv4_patched_v4.lua
-- ===========================

local AutoFishFeature = {}
AutoFishFeature.__index = AutoFishFeature

local logger = _G.Logger and _G.Logger.new("FIHINSTA") or {
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
local EquipTool, ChargeFishingRod, RequestFishing, FishingCompleted, FishObtainedNotification, CancelFishingInputs, BaitSpawned

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
        CancelFishingInputs = NetPath:WaitForChild("RF/CancelFishingInputs", 5)
        BaitSpawned = NetPath:WaitForChild("RE/BaitSpawned", 5)
        
        return true
    end)
    
    return success
end

-- Feature state
local isRunning = false
local currentMode = "Fast"
local spamConnection = nil
local fishObtainedConnection = nil
local baitSpawnedConnection = nil
local controls = {}
local remotesInitialized = false
local rodEquipped = false
local waitingForFish = false
local fishReceived = false
local baitSpawned = false

-- Rod-specific configs
local FISHING_CONFIGS = {
    ["Fast"] = {
        chargeTime = 1.0,
        rodSlot = 1,
        spamDelay = 0.05,
        castDelay = 0.05,
        fishTimeout = 3.0
    },
    ["Slow"] = {
        chargeTime = 1.0,
        rodSlot = 1,
        spamDelay = 0.1,
        castDelay = 0.1,
        fishTimeout = 5.0
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
    
    logger:info("Initialized with BaitSpawned listener")
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
    rodEquipped = false
    waitingForFish = false
    fishReceived = false
    baitSpawned = false
    
    logger:info("Started continuous SPAM - Mode:", currentMode)
    
    -- Equip rod first
    self:EquipRod(FISHING_CONFIGS[currentMode].rodSlot)
    task.wait(0.1)
    rodEquipped = true
    
    -- Start continuous spam
    self:StartContinuousSpam()
    
    -- Setup listeners
    self:SetupBaitSpawnedListener()
    self:SetupFishObtainedListener()
end

-- Stop fishing
function AutoFishFeature:Stop()
    if not isRunning then return end
    
    isRunning = false
    rodEquipped = false
    waitingForFish = false
    fishReceived = false
    baitSpawned = false
    
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
    
    logger:info("Stopped continuous SPAM")
end

-- Start continuous spam (never stops until toggle off)
function AutoFishFeature:StartContinuousSpam()
    if spamConnection then return end
    
    local config = FISHING_CONFIGS[currentMode]
    
    spamConnection = RunService.Heartbeat:Connect(function()
        if not isRunning then return end
        
        pcall(function()
            FishingCompleted:FireServer()
        end)
        
        task.wait(config.spamDelay)
    end)
    
    logger:info("Continuous spam started")
end

-- Setup bait spawned listener
function AutoFishFeature:SetupBaitSpawnedListener()
    if not BaitSpawned then
        logger:warn("BaitSpawned not available")
        return
    end
    
    if baitSpawnedConnection then
        baitSpawnedConnection:Disconnect()
    end
    
    baitSpawnedConnection = BaitSpawned.OnClientEvent:Connect(function(player, rodSkin, position)
        if isRunning and player == LocalPlayer then
            logger:info("Bait spawned! Rod:", rodSkin, "Pos:", position)
            baitSpawned = true
            
            -- Fire cancel immediately
            pcall(function()
                CancelFishingInputs:InvokeServer()
            end)
            
            logger:info("CancelFishingInputs fired")
        end
    end)
    
    logger:info("BaitSpawned listener ready")
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
            logger:info("Fish obtained!")
            fishReceived = true
        end
    end)
    
    -- Start first cycle
    spawn(function()
        task.wait(0.1)
        self:ChargeAndCastWithRetry()
    end)
    
    logger:info("Fish obtained listener ready")
end

-- Charge and cast with retry logic
function AutoFishFeature:ChargeAndCastWithRetry()
    if not isRunning then return end
    
    local config = FISHING_CONFIGS[currentMode]
    
    while isRunning and not waitingForFish do
        waitingForFish = true
        fishReceived = false
        baitSpawned = false
        
        -- Charge first
        pcall(function()
            local chargeValue = tick() + (config.chargeTime * 1000)
            ChargeFishingRod:InvokeServer(chargeValue)
        end)
        
        logger:info("Charge fired")
        
        -- Small delay to prevent race condition
        task.wait(config.castDelay)
        
        -- Then cast
        pcall(function()
            local x = -1.233184814453125
            local z = 0.9999120558411321
            RequestFishing:InvokeServer(x, z)
        end)
        
        logger:info("Cast fired, waiting for BaitSpawned...")
        
        -- Wait for fish notification
        local startTime = tick()
        while not fishReceived and (tick() - startTime) < config.fishTimeout do
            task.wait(0.1)
        end
        
        if fishReceived then
            logger:info("Fish received, restarting cycle...")
            waitingForFish = false
            task.wait(0.05)
        else
            logger:warn("Fish not received, retrying...")
            waitingForFish = false
            task.wait(0.05)
        end
    end
end

-- Equip rod
function AutoFishFeature:EquipRod(slot)
    if not EquipTool then return false end
    
    local success = pcall(function()
        EquipTool:FireServer(slot)
    end)
    
    return success
end

-- Get status
function AutoFishFeature:GetStatus()
    return {
        running = isRunning,
        mode = currentMode,
        rodEquipped = rodEquipped,
        waitingForFish = waitingForFish,
        fishReceived = fishReceived,
        baitSpawned = baitSpawned,
        remotesReady = remotesInitialized,
        spamActive = spamConnection ~= nil,
        baitListenerActive = baitSpawnedConnection ~= nil
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
        logger:info("Mode changed to:", mode)
        
        if wasRunning then
            self:Start({mode = mode})
        end
        
        return true
    end
    return false
end

-- Cleanup
function AutoFishFeature:Cleanup()
    logger:info("Cleaning up...")
    self:Stop()
    controls = {}
    remotesInitialized = false
end

return AutoFishFeature