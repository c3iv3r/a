-- ===========================
-- AUTO FISH FEATURE V3 - UpdateAutoFishingState Method
-- File: autofishv3.lua
-- ===========================

local AutoFishFeature = {}
AutoFishFeature.__index = AutoFishFeature

local logger = _G.Logger and _G.Logger.new("AutoFishV3") or {
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
local EquipTool, ChargeFishingRod, RequestFishing, FishingCompleted, FishObtainedNotification, UpdateAutoFishingState, BaitSpawned

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
        UpdateAutoFishingState = NetPath:WaitForChild("RF/UpdateAutoFishingState", 5)
        BaitSpawned = NetPath:WaitForChild("RE/BaitSpawned", 5)
        
        return true
    end)
    
    return success
end

-- Feature state
local isRunning = false
local fishObtainedConnection = nil
local baitSpawnedConnection = nil
local controls = {}
local remotesInitialized = false

-- Spam and completion tracking
local spamActive = false
local fishCaughtFlag = false
local baitSpawnedFlag = false

-- Fast mode config only
local FISHING_CONFIG = {
    chargeTime = 1.0,
    rodSlot = 1,
    spamDelay = 0.05,      -- Spam every 50ms
    maxSpamTime = 20       -- Stop spam after 20s
}

-- Initialize
function AutoFishFeature:Init(guiControls)
    controls = guiControls or {}
    remotesInitialized = initializeRemotes()
    
    if not remotesInitialized then
        logger:warn("Failed to initialize remotes")
        return false
    end
    
    logger:info("Initialized V3 - UpdateAutoFishingState method")
    return true
end

-- Start fishing
function AutoFishFeature:Start()
    if isRunning then return end
    
    if not remotesInitialized then
        logger:warn("Cannot start - remotes not initialized")
        return
    end
    
    isRunning = true
    spamActive = false
    fishCaughtFlag = false
    baitSpawnedFlag = false
    
    logger:info("Starting V3 AutoFish...")
    
    -- Setup fish obtained listener FIRST
    self:SetupFishObtainedListener()
    self:SetupBaitSpawnedListener()
    
    -- Execute fishing sequence once
    spawn(function()
        -- Step 1: Equip rod ONCE at start
        if not self:EquipRod(FISHING_CONFIG.rodSlot) then
            logger:warn("Failed to equip rod")
            self:Stop()
            return
        end
        
        task.wait(0.2) -- Wait for rod to equip
        
        -- Step 2: Enable auto fishing state
        if not self:SetAutoFishingState(true) then
            logger:warn("Failed to enable auto fishing state")
            self:Stop()
            return
        end
        
        logger:info("Auto fishing state enabled")
        
        -- Step 3: Wait for BaitSpawned before starting spam
        logger:info("Waiting for bait to spawn...")
        self:WaitForBaitSpawned(10) -- 5 second timeout
        
        if not baitSpawnedFlag then
            logger:warn("Bait never spawned - aborting")
            self:Stop()
            return
        end
        
        logger:info("✅ Bait confirmed spawned!")
        
        -- Step 4: Start completion spam until fish caught
        self:StartCompletionSpam(FISHING_CONFIG.spamDelay, FISHING_CONFIG.maxSpamTime)
    end)
end

-- Stop fishing
function AutoFishFeature:Stop()
    if not isRunning then return end
    
    isRunning = false
    spamActive = false
    fishCaughtFlag = false
    baitSpawnedFlag = false
    
    -- Disable auto fishing state
    self:SetAutoFishingState(false)
    
    if fishObtainedConnection then
        fishObtainedConnection:Disconnect()
        fishObtainedConnection = nil
    end
    
    if baitSpawnedConnection then
        baitSpawnedConnection:Disconnect()
        baitSpawnedConnection = nil
    end
    
    logger:info("Stopped V3 AutoFish - auto fishing state disabled")
end

-- Set auto fishing state via RF/UpdateAutoFishingState
function AutoFishFeature:SetAutoFishingState(enabled)
    if not UpdateAutoFishingState then return false end
    
    local success = pcall(function()
        UpdateAutoFishingState:InvokeServer(enabled)
    end)
    
    if success then
        logger:info("UpdateAutoFishingState set to:", enabled)
    else
        logger:warn("Failed to update auto fishing state")
    end
    
    return success
end

-- Setup bait spawned listener
function AutoFishFeature:SetupBaitSpawnedListener()
    if not BaitSpawned then
        logger:warn("BaitSpawned not available")
        return
    end
    
    -- Disconnect existing connection if any
    if baitSpawnedConnection then
        baitSpawnedConnection:Disconnect()
    end
    
    baitSpawnedConnection = BaitSpawned.OnClientEvent:Connect(function(player, rodName, position)
        -- Only listen for LocalPlayer's bait
        if player == LocalPlayer then
            if isRunning then
                logger:info("🎣 Bait spawned! Rod:", rodName or "Unknown")
                baitSpawnedFlag = true
            end
        end
    end)
    
    logger:info("Bait spawned listener setup complete")
end

-- Wait for bait to spawn
function AutoFishFeature:WaitForBaitSpawned(timeout)
    local startTime = tick()
    baitSpawnedFlag = false
    
    while isRunning and not baitSpawnedFlag and (tick() - startTime) < timeout do
        task.wait(0.1)
    end
    
    return baitSpawnedFlag
end

-- Setup fish obtained notification listener
function AutoFishFeature:SetupFishObtainedListener()
    if not FishObtainedNotification then
        logger:warn("FishObtainedNotification not available")
        return
    end
    
    -- Disconnect existing connection if any
    if fishObtainedConnection then
        fishObtainedConnection:Disconnect()
    end
    
    fishObtainedConnection = FishObtainedNotification.OnClientEvent:Connect(function(...)
        if isRunning then
            logger:info("Fish caught! Starting new cycle...")
            fishCaughtFlag = true
            
            -- Stop current spam
            spamActive = false
            
            -- Start new cycle immediately
            task.wait(0.1)
            fishCaughtFlag = false
            
            spawn(function()
                if not isRunning then return end
                
                -- Wait for bait to spawn again
                logger:info("Waiting for bait to spawn...")
                baitSpawnedFlag = false
                self:WaitForBaitSpawned(5)
                
                if not baitSpawnedFlag then
                    logger:warn("Bait never spawned in new cycle")
                    return
                end
                
                logger:info("✅ Bait spawned! Starting spam...")
                
                -- Start spam again
                self:StartCompletionSpam(FISHING_CONFIG.spamDelay, FISHING_CONFIG.maxSpamTime)
            end)
        end
    end)
    
    logger:info("Fish obtained listener active")
end

-- Equip rod (only called once at start)
function AutoFishFeature:EquipRod(slot)
    if not EquipTool then return false end
    
    local success = pcall(function()
        EquipTool:FireServer(slot)
    end)
    
    if success then
        logger:info("Rod equipped in slot", slot)
    end
    
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

-- Start spamming FishingCompleted
function AutoFishFeature:StartCompletionSpam(delay, maxTime)
    if spamActive then return end
    
    -- Verify bait is spawned before starting
    if not baitSpawnedFlag then
        logger:warn("Cannot start completion spam - bait not spawned!")
        return
    end
    
    spamActive = true
    local spamStartTime = tick()
    
    logger:info("Starting completion spam...")
    
    spawn(function()
        -- Spam until fish caught
        while spamActive and isRunning and (tick() - spamStartTime) < maxTime do
            -- Fire completion
            self:FireCompletion()
            
            -- Check if fish caught via notification
            if fishCaughtFlag then
                logger:info("✅ Fish caught after", string.format("%.2f", tick() - spamStartTime), "seconds")
                break
            end
            
            task.wait(delay)
        end
        
        -- Stop spam
        spamActive = false
        
        if not fishCaughtFlag and (tick() - spamStartTime) >= maxTime then
            logger:warn("⏱️ Completion timeout after", maxTime, "seconds")
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

-- Get status
function AutoFishFeature:GetStatus()
    return {
        running = isRunning,
        mode = "Fast",
        spamming = spamActive,
        baitSpawned = baitSpawnedFlag,
        fishCaughtFlag = fishCaughtFlag,
        remotesReady = remotesInitialized,
        listenerReady = fishObtainedConnection ~= nil,
        baitListenerReady = baitSpawnedConnection ~= nil,
        autoFishingStateActive = isRunning
    }
end

-- Get notification listener info for debugging
function AutoFishFeature:GetNotificationInfo()
    return {
        hasNotificationRemote = FishObtainedNotification ~= nil,
        hasUpdateStateRemote = UpdateAutoFishingState ~= nil,
        hasBaitSpawnedRemote = BaitSpawned ~= nil,
        listenerConnected = fishObtainedConnection ~= nil,
        baitListenerConnected = baitSpawnedConnection ~= nil,
        fishCaughtFlag = fishCaughtFlag,
        baitSpawnedFlag = baitSpawnedFlag
    }
end

-- Cleanup
function AutoFishFeature:Cleanup()
    logger:info("Cleaning up V3...")
    self:Stop()
    controls = {}
    remotesInitialized = false
end

return AutoFishFeature