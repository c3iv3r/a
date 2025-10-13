-- ===========================
-- AUTO FISH FEATURE - SPAM METHOD WITH TABLE.UNPACK + BAITSPAWNED
-- File: autofishv6_unpack_bait.lua
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

-- Network setup
local NetPath = nil
local EquipTool, ChargeFishingRod, RequestFishing, FishingCompleted, FishObtainedNotification, BaitSpawned

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
        BaitSpawned = NetPath:WaitForChild("RE/BaitSpawned", 5)
        
        return true
    end)
    
    return success
end

-- Feature state
local isRunning = false
local currentMode = "Fast"
local connection = nil
local fishObtainedConnection = nil
local baitSpawnedConnection = nil
local controls = {}
local fishingInProgress = false
local lastFishTime = 0
local remotesInitialized = false

-- Tracking flags
local fishCaughtFlag = false
local baitSpawnedFlag = false
local castingRod = false

-- NEW: Store fishing session data from InvokeServer
local pendingFishingData = nil
local currentFishingSession = nil

-- Rod-specific configs
local FISHING_CONFIGS = {
    ["Fast"] = {
        chargeTime = 1.0,
        chargeAttempts = 3,
        waitBetween = 0,
        rodSlot = 1,
        castSpamDelay = 0.05,
        maxCastTime = 5,
        completionSpamDelay = 0.05,
        maxCompletionTime = 8,
        skipMinigame = true
    },
    ["Slow"] = {
        chargeTime = 1.0,
        chargeAttempts = 3,
        waitBetween = 1,
        rodSlot = 1,
        castSpamDelay = 0.1,
        maxCastTime = 5,
        completionSpamDelay = 0.1,
        maxCompletionTime = 8,
        skipMinigame = false,
        minigameDuration = 5
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
    
    logger:info("Initialized with TABLE.UNPACK + BaitSpawned confirmation")
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
    lastFishTime = 0
    fishCaughtFlag = false
    baitSpawnedFlag = false
    castingRod = false
    pendingFishingData = nil
    currentFishingSession = nil
    
    logger:info("Started TABLE.UNPACK + BaitSpawned method - Mode:", currentMode)
    
    -- Setup listeners
    self:SetupFishObtainedListener()
    self:SetupBaitSpawnedListener()
    
    -- Main fishing loop
    connection = RunService.Heartbeat:Connect(function()
        if not isRunning then return end
        self:FishingLoop()
    end)
end

-- Stop fishing
function AutoFishFeature:Stop()
    if not isRunning then return end
    
    isRunning = false
    fishingInProgress = false
    fishCaughtFlag = false
    baitSpawnedFlag = false
    castingRod = false
    pendingFishingData = nil
    currentFishingSession = nil
    
    if connection then
        connection:Disconnect()
        connection = nil
    end
    
    if fishObtainedConnection then
        fishObtainedConnection:Disconnect()
        fishObtainedConnection = nil
    end
    
    if baitSpawnedConnection then
        baitSpawnedConnection:Disconnect()
        baitSpawnedConnection = nil
    end
    
    logger:info("Stopped fishing")
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
    
    baitSpawnedConnection = BaitSpawned.OnClientEvent:Connect(function(player, rodName, position)
        if player == LocalPlayer and isRunning then
            logger:info("🎣 Bait spawned! Rod:", rodName or "Unknown")
            
            -- Set flag
            baitSpawnedFlag = true
            
            -- Stop casting spam
            if castingRod then
                castingRod = false
            end
            
            -- IMPORTANT: Activate pending fishing data NOW
            if pendingFishingData then
                currentFishingSession = pendingFishingData
                pendingFishingData = nil
                
                logger:info("✅ Fishing session activated:")
                logger:info("  - Fish ID:", currentFishingSession.CaughtFish)
                logger:info("  - Area:", currentFishingSession.AreaName)
                logger:info("  - UUID:", currentFishingSession.UUID)
                logger:info("  - Strength:", currentFishingSession.FishStrength)
                if currentFishingSession.RollData then
                    logger:info("  - Base Luck:", currentFishingSession.RollData.BaseLuck)
                end
            else
                logger:warn("No pending fishing data to activate!")
            end
        end
    end)
    
    logger:info("Bait spawned listener ready")
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
            logger:info("🐟 Fish obtained!")
            fishCaughtFlag = true
            
            -- Log completed session
            if currentFishingSession then
                logger:info("Session completed - Fish ID:", currentFishingSession.CaughtFish)
            end
            
            -- Reset for next cycle
            spawn(function()
                task.wait(0.1)
                fishingInProgress = false
                fishCaughtFlag = false
                currentFishingSession = nil
                pendingFishingData = nil
                logger:info("Ready for next cycle")
            end)
        end
    end)
    
    logger:info("Fish obtained listener ready")
end

-- Main fishing loop
function AutoFishFeature:FishingLoop()
    if fishingInProgress then return end
    
    local currentTime = tick()
    local config = FISHING_CONFIGS[currentMode]
    
    if currentTime - lastFishTime < config.waitBetween then
        return
    end
    
    fishingInProgress = true
    lastFishTime = currentTime
    
    spawn(function()
        local success = self:ExecuteFishingSequence()
        if not success then
            fishingInProgress = false
        end
    end)
end

-- Execute fishing sequence
function AutoFishFeature:ExecuteFishingSequence()
    local config = FISHING_CONFIGS[currentMode]
    
    -- Step 1: Equip rod
    logger:info("Step 1: Equipping rod...")
    if not self:EquipRod(config.rodSlot) then
        logger:warn("Failed to equip rod")
        return false
    end
    task.wait(0.1)
    self:EquipRod(config.rodSlot) -- Double equip
    task.wait(0.25)

    -- Step 2: Charge rod
    logger:info("Step 2: Charging rod...")
    if not self:ChargeRod(config.chargeTime, config.chargeAttempts) then
        logger:warn("Failed to charge rod")
        return false
    end
    task.wait(0.2)

    -- Step 3: Cast with spam + table.unpack
    logger:info("Step 3: Casting with spam (unpack on success)...")
    if not self:CastWithSpamAndUnpack(config.castSpamDelay, config.maxCastTime) then
        logger:warn("Failed to cast - bait never spawned")
        return false
    end

    -- Step 4: Verify bait spawned
    if not baitSpawnedFlag then
        logger:warn("Bait flag not set - aborting")
        return false
    end
    
    -- Step 5: Verify fishing data was activated
    if not currentFishingSession then
        logger:warn("Fishing session not activated - aborting")
        return false
    end
    
    logger:info("✅ Bait confirmed + Session active!")
    task.wait(0.5)

    -- Step 6: Start completion spam
    logger:info("Step 4: Starting completion spam...")
    self:StartCompletionSpam(config.completionSpamDelay, config.maxCompletionTime)
    
    return true
end

-- Equip rod
function AutoFishFeature:EquipRod(slot)
    if not EquipTool then return false end
    return pcall(function()
        EquipTool:FireServer(slot)
    end)
end

-- Charge rod
function AutoFishFeature:ChargeRod(chargeTime, attempts)
    if not ChargeFishingRod then return false end
    
    local successCount = 0
    for i = 1, attempts do
        local success = pcall(function()
            local chargeValue = tick() + (chargeTime * 1000)
            ChargeFishingRod:InvokeServer(chargeValue)
        end)
        
        if success then
            successCount = successCount + 1
        end
        
        if i < attempts then
            task.wait(0.08)
        end
    end
    
    logger:info("Charged:", successCount, "/", attempts)
    return successCount >= 2
end

-- Cast with spam AND table.unpack on first success
function AutoFishFeature:CastWithSpamAndUnpack(delay, maxTime)
    if not RequestFishing then return false end
    
    -- Reset
    baitSpawnedFlag = false
    castingRod = true
    pendingFishingData = nil
    currentFishingSession = nil
    local castStartTime = tick()
    local castAttempts = 0
    local dataReceived = false
    
    logger:info("Casting spam started (will unpack on first success)...")
    task.wait(0.05)
    
    while castingRod and isRunning and (tick() - castStartTime) < maxTime do
        -- Check if bait spawned
        if baitSpawnedFlag then
            logger:info("✅ Bait spawned after", string.format("%.2f", tick() - castStartTime), "s (", castAttempts, "attempts)")
            castingRod = false
            return true
        end
        
        castAttempts = castAttempts + 1
        
        -- Fire cast with table.unpack (only if we haven't received data yet)
        if not dataReceived then
            local success, fishingSuccess, fishingData = pcall(function()
                local x = -1.233184814453125
                local z = 0.9999120558411321
                return table.unpack({ RequestFishing:InvokeServer(x, z) })
            end)
            
            if success and fishingSuccess and fishingData then
                -- Store as PENDING (will be activated by BaitSpawned listener)
                pendingFishingData = fishingData
                dataReceived = true
                logger:info("📦 Fishing data received (pending activation):")
                logger:info("  - Fish ID:", fishingData.CaughtFish)
                logger:info("  - UUID:", fishingData.UUID)
            elseif not success then
                logger:warn("Cast attempt", castAttempts, "failed")
            end
        else
            -- Data already received, just spam regular InvokeServer
            pcall(function()
                local x = -1.233184814453125
                local z = 0.9999120558411321
                RequestFishing:InvokeServer(x, z)
            end)
        end
        
        task.wait(delay)
    end
    
    -- Final check
    if baitSpawnedFlag then
        logger:info("✅ Bait spawned (final check)")
        castingRod = false
        return true
    end
    
    logger:warn("❌ Cast timeout -", castAttempts, "attempts")
    castingRod = false
    return false
end

-- Start completion spam
function AutoFishFeature:StartCompletionSpam(delay, maxTime)
    if not baitSpawnedFlag or not currentFishingSession then
        logger:warn("Cannot spam completion - prerequisites not met")
        return
    end
    
    fishCaughtFlag = false
    local spamStartTime = tick()
    local config = FISHING_CONFIGS[currentMode]
    local completionAttempts = 0
    
    logger:info("Completion spam started for Fish ID:", currentFishingSession.CaughtFish)
    
    spawn(function()
        -- Slow mode delay
        if currentMode == "Slow" and not config.skipMinigame then
            logger:info("Slow mode: animation", config.minigameDuration, "s")
            task.wait(config.minigameDuration)
            
            if fishCaughtFlag or not isRunning then
                return
            end
        end
        
        -- Spam loop
        while isRunning and (tick() - spamStartTime) < maxTime do
            if fishCaughtFlag then
                logger:info("✅ Fish caught! (", completionAttempts, "attempts)")
                return
            end
            
            completionAttempts = completionAttempts + 1
            pcall(function()
                FishingCompleted:FireServer()
            end)
            
            task.wait(delay)
        end
        
        logger:warn("⏱️ Completion timeout after", string.format("%.2f", tick() - spamStartTime), "s")
    end)
end

-- Get status
function AutoFishFeature:GetStatus()
    local status = {
        running = isRunning,
        mode = currentMode,
        inProgress = fishingInProgress,
        casting = castingRod,
        baitSpawned = baitSpawnedFlag,
        fishCaught = fishCaughtFlag,
        hasPendingData = pendingFishingData ~= nil,
        hasActiveSession = currentFishingSession ~= nil,
        remotesReady = remotesInitialized
    }
    
    if currentFishingSession then
        status.currentSession = {
            fishId = currentFishingSession.CaughtFish,
            uuid = currentFishingSession.UUID,
            area = currentFishingSession.AreaName,
            strength = currentFishingSession.FishStrength
        }
    end
    
    return status
end

-- Set mode
function AutoFishFeature:SetMode(mode)
    if FISHING_CONFIGS[mode] then
        currentMode = mode
        logger:info("Mode:", mode)
        return true
    end
    return false
end

-- Get current session
function AutoFishFeature:GetCurrentSession()
    return currentFishingSession
end

-- Cleanup
function AutoFishFeature:Cleanup()
    logger:info("Cleaning up...")
    self:Stop()
    controls = {}
    remotesInitialized = false
end

return AutoFishFeature