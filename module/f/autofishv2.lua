-- ===========================
-- AUTO FISH FEATURE - SPAM METHOD (FIXED WITH BAITSPAWNED)
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
        BaitSpawned = NetPath:WaitForChild("RE/BaitSpawned", 5)
        
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
local lastFishTime = 0
local remotesInitialized = false

-- Spam and completion tracking
local spamActive = false
local completionCheckActive = false
local lastBackpackCount = 0
local fishCaughtFlag = false
local baitSpawnedFlag = false
local castingRod = false

-- Rod-specific configs
local FISHING_CONFIGS = {
    ["Fast"] = {
        chargeTime = 1.0,
        chargeAttempts = 3,        -- Invoke charge 3x to ensure it works
        waitBetween = 0,
        rodSlot = 1,
        castSpamDelay = 0.05,      -- Spam cast every 50ms
        maxCastTime = 5,           -- Max time to spam cast before timeout
        completionSpamDelay = 0.05, -- Spam completion every 50ms
        maxCompletionTime = 8,     -- Stop completion spam after 8s
        skipMinigame = true        -- Skip tap-tap animation
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
        skipMinigame = false,      -- Play tap-tap animation
        minigameDuration = 5       -- Duration before firing completion
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
    
    logger:info("Initialized with SPAM method + BaitSpawned confirmation - Fast & Slow modes")
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
    castingRod = false
    
    logger:info("Started SPAM method - Mode:", currentMode)
    
    -- Setup listeners
    self:SetupFishObtainedListener()
    self:SetupBaitSpawnedListener()
    
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
    castingRod = false
    
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
    
    logger:info("Stopped SPAM method")
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
                logger:info("🎣 Bait spawned! Rod:", rodName or "Unknown", "Casting:", castingRod)
                
                -- Set flag regardless of castingRod state (prevent race condition)
                baitSpawnedFlag = true
                
                -- Stop casting if active
                if castingRod then
                    castingRod = false
                end
            end
        end
    end)
    
    logger:info("Bait spawned listener setup complete")
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
            logger:info("Fish obtained notification received!")
            fishCaughtFlag = true
            
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
    
    logger:info("Fish obtained listener setup complete")
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
        end
    end)
end

-- Execute spam-based fishing sequence
function AutoFishFeature:ExecuteSpamFishingSequence()
    local config = FISHING_CONFIGS[currentMode]
    
    -- Step 1: Equip rod (DOUBLE FIRE with better spacing)
    logger:info("Step 1: Equipping rod (2x)...")
    if not self:EquipRod(config.rodSlot) then
        logger:warn("Failed to equip rod (1st attempt)")
        return false
    end
    task.wait(0.1) -- Longer delay between equips
    if not self:EquipRod(config.rodSlot) then
        logger:warn("Failed to equip rod (2nd attempt)")
        return false
    end
    
    task.wait(0.25) -- Longer wait for equip to fully register

    -- Step 2: Charge rod (MULTIPLE ATTEMPTS)
    logger:info("Step 2: Charging rod...")
    if not self:ChargeRod(config.chargeTime, config.chargeAttempts) then
        logger:warn("Failed to charge rod - all attempts failed")
        return false
    end
    
    task.wait(0.2) -- Longer wait for charge to complete

    -- Step 3: Cast rod with spam until BaitSpawned
    logger:info("Step 3: Casting rod...")
    if not self:CastRodWithSpam(config.castSpamDelay, config.maxCastTime) then
        logger:warn("Failed to cast rod - bait never spawned")
        return false
    end

    -- Step 4: Verify bait spawned before continuing
    if not baitSpawnedFlag then
        logger:warn("Bait flag not set after cast - aborting cycle")
        return false
    end
    
    logger:info("✅ Bait confirmed in water!")
    
    -- Step 5: LONGER delay before starting completion spam (critical for stability)
    task.wait(0.5) -- Give server time to fully register bait
    
    -- Step 6: Final verification before completion spam
    if not isRunning then
        logger:warn("Stopped during bait delay")
        return false
    end
    
    if not baitSpawnedFlag then
        logger:warn("Bait flag lost during delay - aborting")
        return false
    end

    -- Step 7: Start completion spam with mode-specific behavior
    logger:info("Step 4: Starting completion spam...")
    self:StartCompletionSpam(config.completionSpamDelay, config.maxCompletionTime)
    
    return true
end

-- Equip rod
function AutoFishFeature:EquipRod(slot)
    if not EquipTool then return false end
    
    local success = pcall(function()
        EquipTool:FireServer(slot)
    end)
    
    return success
end

-- Charge rod (with multiple attempts)
function AutoFishFeature:ChargeRod(chargeTime, attempts)
    if not ChargeFishingRod then return false end
    
    attempts = attempts or 1
    local successCount = 0
    
    logger:info("Charging rod", attempts, "times...")
    
    for i = 1, attempts do
        local success = pcall(function()
            local chargeValue = tick() + (chargeTime * 1000)
            ChargeFishingRod:InvokeServer(chargeValue)
        end)
        
        if success then
            successCount = successCount + 1
        else
            logger:warn("Charge attempt", i, "failed")
        end
        
        -- Small delay between charges (slightly longer for reliability)
        if i < attempts then
            task.wait(0.08)
        end
    end
    
    logger:info("Charge completed:", successCount, "/", attempts, "successful")
    
    -- Require at least 2 successful charges for reliability
    if successCount >= 2 then
        return true
    elseif successCount > 0 then
        logger:warn("Only", successCount, "charge(s) succeeded - may be unstable")
        return true
    else
        logger:error("All charge attempts failed!")
        return false
    end
end

-- Cast rod with spam until BaitSpawned
function AutoFishFeature:CastRodWithSpam(delay, maxTime)
    if not RequestFishing then return false end
    
    -- Reset flags BEFORE starting
    baitSpawnedFlag = false
    castingRod = true
    local castStartTime = tick()
    local castAttempts = 0
    
    logger:info("Starting cast spam until BaitSpawned...")
    
    -- Give listener a moment to be ready
    task.wait(0.05)
    
    -- Spam cast until bait spawns or timeout
    while castingRod and isRunning and (tick() - castStartTime) < maxTime do
        -- Check flag FIRST before casting again
        if baitSpawnedFlag then
            logger:info("Bait confirmed spawned! Cast successful after", string.format("%.2f", tick() - castStartTime), "seconds (", castAttempts, "attempts)")
            castingRod = false
            return true
        end
        
        -- Fire cast request
        castAttempts = castAttempts + 1
        local success = pcall(function()
            local x = -1.233184814453125
            local z = 0.9999120558411321
            RequestFishing:InvokeServer(x, z)
        end)
        
        if not success then
            logger:warn("Cast attempt", castAttempts, "failed, retrying...")
        end
        
        task.wait(delay)
    end
    
    -- Final check after loop (in case flag was set during last wait)
    if baitSpawnedFlag then
        logger:info("Bait spawned (detected after loop)! Cast successful")
        castingRod = false
        return true
    end
    
    -- Timeout
    logger:warn("Cast timeout after", maxTime, "seconds -", castAttempts, "attempts - bait never spawned")
    castingRod = false
    return false
end

-- Start spamming FishingCompleted with mode-specific behavior
function AutoFishFeature:StartCompletionSpam(delay, maxTime)
    if spamActive then 
        logger:warn("Completion spam already active - skipping")
        return 
    end
    
    -- Verify bait is spawned before starting
    if not baitSpawnedFlag then
        logger:warn("Cannot start completion spam - bait not spawned!")
        return
    end
    
    spamActive = true
    completionCheckActive = true
    fishCaughtFlag = false
    local spamStartTime = tick()
    local config = FISHING_CONFIGS[currentMode]
    local completionAttempts = 0
    local lastCheckTime = tick()
    
    logger:info("Starting completion SPAM - Mode:", currentMode, "BaitFlag:", baitSpawnedFlag)
    
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
                logger:info("Fish caught during animation delay")
                return
            end
        end
        
        -- Start spamming (for both modes, but Slow starts after minigame delay)
        while spamActive and isRunning and (tick() - spamStartTime) < maxTime do
            -- Check if fishing completed more frequently (every 0.2s)
            if tick() - lastCheckTime >= 0.2 then
                if fishCaughtFlag or self:CheckFishingCompleted() then
                    logger:info("✅ Fish caught detected! (", completionAttempts, "attempts in", string.format("%.2f", tick() - spamStartTime), "s)")
                    spamActive = false
                    completionCheckActive = false
                    return
                end
                lastCheckTime = tick()
            end
            
            -- Fire completion
            completionAttempts = completionAttempts + 1
            local fired = self:FireCompletion()
            
            if not fired then
                logger:warn("Completion fire failed on attempt", completionAttempts)
            end
            
            task.wait(delay)
        end
        
        -- Final check before timeout
        if fishCaughtFlag or self:CheckFishingCompleted() then
            logger:info("✅ Fish caught detected at final check!")
            spamActive = false
            completionCheckActive = false
            return
        end
        
        -- Stop spam
        spamActive = false
        completionCheckActive = false
        
        logger:warn("⏱️ Completion timeout after", string.format("%.2f", tick() - spamStartTime), "seconds (", completionAttempts, "attempts)")
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
    
    -- Method 3: Check character tool state
    if LocalPlayer.Character then
        local tool = LocalPlayer.Character:FindFirstChildOfClass("Tool")
        if not tool then
            -- Tool unequipped = fishing might be done
            return false -- Don't rely on this alone
        end
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
        casting = castingRod,
        baitSpawned = baitSpawnedFlag,
        lastCatch = lastFishTime,
        backpackCount = lastBackpackCount,
        fishCaughtFlag = fishCaughtFlag,
        remotesReady = remotesInitialized,
        listenerReady = fishObtainedConnection ~= nil,
        baitListenerReady = baitSpawnedConnection ~= nil
    }
end

-- Update mode
function AutoFishFeature:SetMode(mode)
    if FISHING_CONFIGS[mode] then
        currentMode = mode
        logger:info("Mode changed to:", mode)
        if mode == "Fast" then
            logger:info("  - Skip minigame: ON")
        elseif mode == "Slow" then  
            logger:info("  - Skip minigame: OFF (", FISHING_CONFIGS[mode].minigameDuration, "s animation)")
        end
        return true
    end
    return false
end

-- Get notification listener info for debugging
function AutoFishFeature:GetNotificationInfo()
    return {
        hasNotificationRemote = FishObtainedNotification ~= nil,
        hasBaitSpawnedRemote = BaitSpawned ~= nil,
        listenerConnected = fishObtainedConnection ~= nil,
        baitListenerConnected = baitSpawnedConnection ~= nil,
        fishCaughtFlag = fishCaughtFlag,
        baitSpawnedFlag = baitSpawnedFlag
    }
end

-- Cleanup
function AutoFishFeature:Cleanup()
    logger:info("Cleaning up SPAM method...")
    self:Stop()
    controls = {}
    remotesInitialized = false
end

return AutoFishFeature