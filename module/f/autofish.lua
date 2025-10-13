-- ===========================
-- AUTO FISH FEATURE - AGGRESSIVE BAITSPAWNED METHOD
-- File: autofishv5_baitspawned.lua
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
        BaitSpawned = NetPath:WaitForChild("RE/BaitSpawned", 5)  -- NEW!
        
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
local baitSpawnedConnection = nil  -- NEW!
local controls = {}
local fishingInProgress = false
local lastFishTime = 0
local remotesInitialized = false

-- Spam and completion tracking
local spamActive = false
local completionCheckActive = false
local lastBackpackCount = 0
local fishCaughtFlag = false
local baitSpawnedFlag = false  -- NEW!

-- Statistics
local stats = {
    totalCasts = 0,
    totalFishCaught = 0,
    totalBaitSpawns = 0,
    avgCastAttempts = 0,
    fastestBait = 999,
    sessionStartTime = 0
}

-- Rod-specific configs
local FISHING_CONFIGS = {
    ["Fast"] = {
        chargeTime = 1.0,
        waitBetween = 0,
        rodSlot = 1,
        spamDelay = 0.05,           -- Spam completion every 50ms
        maxSpamTime = 20,            -- Stop spam after 20s
        skipMinigame = true,         -- Skip tap-tap animation
        -- Aggressive cast settings
        aggressiveCast = true,       -- Enable spam cast until bait
        castSpamDelay = 0.1,        -- Spam cast every 100ms
        castTimeout = 10,            -- Max 10s waiting for bait
        maxCastAttempts = 50         -- Max 50 cast attempts
    },
    ["Slow"] = {
        chargeTime = 1.0,
        waitBetween = 1,
        rodSlot = 1,
        spamDelay = 0.1,
        maxSpamTime = 20,
        skipMinigame = false,        -- Play tap-tap animation
        minigameDuration = 5,        -- Duration before firing completion
        -- Conservative cast settings
        aggressiveCast = false,      -- No spam cast
        castSpamDelay = 0.3,
        castTimeout = 5,
        maxCastAttempts = 10
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
    
    -- Initialize backpack count for completion detection
    self:UpdateBackpackCount()
    
    -- Reset stats
    stats.sessionStartTime = tick()
    
    logger:info("Initialized with AGGRESSIVE BAITSPAWNED method")
    logger:info("Fast mode: Spam cast until bait spawns")
    logger:info("Slow mode: Conservative cast with animation")
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
    spamActive = false
    lastFishTime = 0
    fishCaughtFlag = false
    baitSpawnedFlag = false
    
    logger:info("=== STARTED AGGRESSIVE BAITSPAWNED METHOD ===")
    logger:info("Mode:", currentMode)
    logger:info("Aggressive Cast:", FISHING_CONFIGS[currentMode].aggressiveCast and "ENABLED" or "DISABLED")
    
    -- Setup listeners
    self:SetupFishObtainedListener()
    self:SetupBaitSpawnedListener()  -- NEW!
    
    -- Main fishing loop
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
    baitSpawnedFlag = false
    
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
    
    -- Print stats
    logger:info("=== SESSION STATS ===")
    logger:info("Total Fish Caught:", stats.totalFishCaught)
    logger:info("Total Casts:", stats.totalCasts)
    logger:info("Total Bait Spawns:", stats.totalBaitSpawns)
    logger:info("Avg Cast Attempts:", string.format("%.2f", stats.avgCastAttempts))
    logger:info("Fastest Bait:", string.format("%.2f", stats.fastestBait), "seconds")
    local sessionTime = tick() - stats.sessionStartTime
    logger:info("Session Time:", string.format("%.1f", sessionTime), "seconds")
    if sessionTime > 0 then
        logger:info("Fish/Minute:", string.format("%.2f", stats.totalFishCaught / (sessionTime / 60)))
    end
    
    logger:info("Stopped AGGRESSIVE BAITSPAWNED method")
end

-- Setup BaitSpawned listener (NEW!)
function AutoFishFeature:SetupBaitSpawnedListener()
    if not BaitSpawned then
        logger:warn("BaitSpawned event not available")
        return
    end
    
    -- Disconnect existing connection
    if baitSpawnedConnection then
        baitSpawnedConnection:Disconnect()
    end
    
    baitSpawnedConnection = BaitSpawned.OnClientEvent:Connect(function(...)
        if isRunning then
            local args = {...}
            logger:info("🎣 BAIT SPAWNED! Cast confirmed by server")
            logger:debug("BaitSpawned args:", unpack(args))
            
            baitSpawnedFlag = true
            stats.totalBaitSpawns = stats.totalBaitSpawns + 1
        end
    end)
    
    logger:info("BaitSpawned listener setup complete ✓")
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
            logger:info("✅ Fish obtained notification received!")
            fishCaughtFlag = true
            stats.totalFishCaught = stats.totalFishCaught + 1
            
            -- Stop current spam immediately
            if spamActive then
                spamActive = false
                completionCheckActive = false
            end
            
            -- Reset fishing state for next cycle (fast restart)
            spawn(function()
                task.wait(0.1) -- Small delay for stability
                fishingInProgress = false
                fishCaughtFlag = false
                logger:info("Ready for next cycle (fast restart)")
            end)
        end
    end)
    
    logger:info("Fish obtained listener setup complete ✓")
end

-- Main spam-based fishing loop
function AutoFishFeature:SpamFishingLoop()
    if fishingInProgress or spamActive then return end
    
    local currentTime = tick()
    local config = FISHING_CONFIGS[currentMode]
    
    -- Wait between cycles
    if currentTime - lastFishTime < config.waitBetween then
        return
    end
    
    -- Start fishing sequence
    fishingInProgress = true
    lastFishTime = currentTime
    
    spawn(function()
        local success = self:ExecuteSpamFishingSequence()
        fishingInProgress = false
        
        if success then
            logger:info("SPAM cycle completed!")
        else
            logger:warn("SPAM cycle FAILED!")
        end
    end)
end

-- Execute spam-based fishing sequence (UPDATED!)
function AutoFishFeature:ExecuteSpamFishingSequence()
    local config = FISHING_CONFIGS[currentMode]
    
    -- Step 1: Equip rod
    if not self:EquipRod(config.rodSlot) then
        logger:error("Failed to equip rod")
        return false
    end
    
    task.wait(0.1)

    -- Step 2: Charge rod
    if not self:ChargeRod(config.chargeTime) then
        logger:error("Failed to charge rod")
        return false
    end
    
    -- Step 3: AGGRESSIVE CAST until BaitSpawned confirms (NEW!)
    local castSuccess = false
    if config.aggressiveCast then
        castSuccess = self:AggressiveCastUntilBait(config.castTimeout, config.castSpamDelay, config.maxCastAttempts)
    else
        castSuccess = self:ConservativeCastWithRetry(3, 0.3)
    end
    
    if not castSuccess then
        logger:error("❌ Cast failed - bait never spawned")
        return false
    end
    
    logger:info("🎯 BAIT CONFIRMED IN WATER! Starting completion spam NOW...")

    -- Step 4: Start completion spam IMMEDIATELY after bait confirmed
    self:StartCompletionSpam(config.spamDelay, config.maxSpamTime)
    
    return true
end

-- AGGRESSIVE CAST: Spam cast until BaitSpawned received (NEW!)
function AutoFishFeature:AggressiveCastUntilBait(timeout, spamDelay, maxAttempts)
    timeout = timeout or 10
    spamDelay = spamDelay or 0.1
    maxAttempts = maxAttempts or 50
    
    baitSpawnedFlag = false
    local castStartTime = tick()
    local castAttempts = 0
    local spamCastActive = true
    
    logger:info("🚀 AGGRESSIVE CAST MODE ACTIVATED!")
    logger:info("   Timeout:", timeout, "seconds")
    logger:info("   Spam delay:", spamDelay, "seconds")
    logger:info("   Max attempts:", maxAttempts)
    
    -- Spawn aggressive cast loop
    spawn(function()
        while spamCastActive and not baitSpawnedFlag and castAttempts < maxAttempts do
            if (tick() - castStartTime) >= timeout then
                break
            end
            
            castAttempts = castAttempts + 1
            stats.totalCasts = stats.totalCasts + 1
            
            local success = pcall(function()
                local x = -1.233184814453125
                local z = 0.9999120558411321
                RequestFishing:InvokeServer(x, z)
            end)
            
            if success then
                logger:debug("Cast attempt", castAttempts, "/", maxAttempts)
            else
                logger:warn("Cast invoke failed at attempt", castAttempts)
            end
            
            task.wait(spamDelay)
        end
        
        spamCastActive = false
    end)
    
    -- Wait for BaitSpawned confirmation
    local waitStart = tick()
    while not baitSpawnedFlag and (tick() - waitStart) < timeout do
        task.wait(0.05) -- Check every 50ms
    end
    
    -- Stop spam loop
    spamCastActive = false
    
    if baitSpawnedFlag then
        local castTime = tick() - castStartTime
        logger:info("✅ BAIT IN WATER!")
        logger:info("   Cast attempts:", castAttempts)
        logger:info("   Time taken:", string.format("%.2f", castTime), "seconds")
        
        -- Update stats
        if castTime < stats.fastestBait then
            stats.fastestBait = castTime
        end
        if stats.totalBaitSpawns > 0 then
            stats.avgCastAttempts = stats.totalCasts / stats.totalBaitSpawns
        end
        
        return true
    end
    
    -- Failed
    logger:error("❌ BAIT SPAWN TIMEOUT!")
    logger:error("   Attempts made:", castAttempts)
    logger:error("   Time elapsed:", string.format("%.2f", tick() - castStartTime), "seconds")
    return false
end

-- Conservative cast with retry (for Slow mode)
function AutoFishFeature:ConservativeCastWithRetry(maxRetries, retryDelay)
    maxRetries = maxRetries or 3
    retryDelay = retryDelay or 0.3
    
    baitSpawnedFlag = false
    
    logger:info("Conservative cast mode (", maxRetries, "retries)")
    
    for attempt = 1, maxRetries do
        logger:info("Cast attempt", attempt, "/", maxRetries)
        stats.totalCasts = stats.totalCasts + 1
        
        -- Cast rod
        local castSuccess = pcall(function()
            local x = -1.233184814453125
            local z = 0.9999120558411321
            RequestFishing:InvokeServer(x, z)
        end)
        
        if not castSuccess then
            logger:warn("Cast failed at attempt", attempt)
            task.wait(retryDelay)
            continue
        end
        
        -- Wait for BaitSpawned confirmation
        local waitStart = tick()
        local timeout = 3
        
        while not baitSpawnedFlag and (tick() - waitStart) < timeout do
            task.wait(0.05)
        end
        
        if baitSpawnedFlag then
            logger:info("✅ Cast confirmed after", attempt, "attempts")
            return true
        end
        
        logger:warn("No BaitSpawned confirmation, retrying...")
        task.wait(retryDelay)
    end
    
    logger:error("Failed to cast after", maxRetries, "attempts")
    return false
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
        local chargeValue = tick() + (chargeTime * 1000)
        return ChargeFishingRod:InvokeServer(chargeValue)
    end)
    
    return success
end

-- Start spamming FishingCompleted with mode-specific behavior
function AutoFishFeature:StartCompletionSpam(delay, maxTime)
    if spamActive then return end
    
    spamActive = true
    completionCheckActive = true
    fishCaughtFlag = false
    local spamStartTime = tick()
    local config = FISHING_CONFIGS[currentMode]
    
    logger:info("Starting completion SPAM - Mode:", currentMode)
    
    -- Update backpack count before spam
    self:UpdateBackpackCount()
    
    spawn(function()
        -- Mode-specific behavior
        if currentMode == "Slow" and not config.skipMinigame then
            -- Slow mode: Wait for minigame animation
            logger:info("Slow mode: Playing minigame animation for", config.minigameDuration, "seconds")
            task.wait(config.minigameDuration)
            
            -- Check if fish was already caught during animation
            if fishCaughtFlag or not isRunning or not spamActive then
                spamActive = false
                completionCheckActive = false
                return
            end
        end
        
        -- Start spamming (for both modes, but Slow starts after minigame delay)
        local spamCount = 0
        while spamActive and isRunning and (tick() - spamStartTime) < maxTime do
            -- Fire completion
            local fired = self:FireCompletion()
            if fired then
                spamCount = spamCount + 1
            end
            
            -- Check if fishing completed using notification listener OR backpack method
            if fishCaughtFlag or self:CheckFishingCompleted() then
                logger:info("Fish caught detected! (", spamCount, "completion attempts)")
                break
            end
            
            task.wait(delay)
        end
        
        -- Stop spam
        spamActive = false
        completionCheckActive = false
        
        if (tick() - spamStartTime) >= maxTime then
            logger:warn("SPAM timeout after", maxTime, "seconds (", spamCount, "attempts)")
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

-- Check if fishing completed successfully (fallback method)
function AutoFishFeature:CheckFishingCompleted()
    -- Primary method: notification listener flag
    if fishCaughtFlag then
        return true
    end
    
    -- Fallback method: Check backpack item count increase
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

-- Get current backpack item count
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
        baitSpawnedFlag = baitSpawnedFlag,  -- NEW!
        remotesReady = remotesInitialized,
        listenerReady = fishObtainedConnection ~= nil,
        baitListenerReady = baitSpawnedConnection ~= nil,  -- NEW!
        stats = stats  -- NEW!
    }
end

-- Update mode
function AutoFishFeature:SetMode(mode)
    if FISHING_CONFIGS[mode] then
        currentMode = mode
        logger:info("Mode changed to:", mode)
        local config = FISHING_CONFIGS[mode]
        if config.aggressiveCast then
            logger:info("  - Aggressive cast: ENABLED")
            logger:info("  - Cast spam delay:", config.castSpamDelay, "seconds")
            logger:info("  - Max attempts:", config.maxCastAttempts)
        else
            logger:info("  - Aggressive cast: DISABLED (conservative mode)")
        end
        if mode == "Fast" then
            logger:info("  - Skip minigame: ON")
        elseif mode == "Slow" then  
            logger:info("  - Skip minigame: OFF (", config.minigameDuration, "s animation)")
        end
        return true
    end
    return false
end

-- Get notification listener info for debugging
function AutoFishFeature:GetNotificationInfo()
    return {
        hasNotificationRemote = FishObtainedNotification ~= nil,
        hasBaitSpawnedRemote = BaitSpawned ~= nil,  -- NEW!
        listenerConnected = fishObtainedConnection ~= nil,
        baitListenerConnected = baitSpawnedConnection ~= nil,  -- NEW!
        fishCaughtFlag = fishCaughtFlag,
        baitSpawnedFlag = baitSpawnedFlag  -- NEW!
    }
end

-- Get statistics (NEW!)
function AutoFishFeature:GetStats()
    return {
        totalCasts = stats.totalCasts,
        totalFishCaught = stats.totalFishCaught,
        totalBaitSpawns = stats.totalBaitSpawns,
        avgCastAttempts = stats.avgCastAttempts,
        fastestBait = stats.fastestBait,
        sessionTime = tick() - stats.sessionStartTime,
        fishPerMinute = stats.totalFishCaught / ((tick() - stats.sessionStartTime) / 60)
    }
end

-- Reset statistics (NEW!)
function AutoFishFeature:ResetStats()
    stats = {
        totalCasts = 0,
        totalFishCaught = 0,
        totalBaitSpawns = 0,
        avgCastAttempts = 0,
        fastestBait = 999,
        sessionStartTime = tick()
    }
    logger:info("Statistics reset")
end

-- Cleanup
function AutoFishFeature:Cleanup()
    logger:info("Cleaning up AGGRESSIVE BAITSPAWNED method...")
    self:Stop()
    controls = {}
    remotesInitialized = false
end

return AutoFishFeature