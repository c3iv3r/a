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
        if player == LocalPlayer and isRunning and castingRod then
            logger:info("Bait spawned! Rod:", rodName or "Unknown", "Position:", tostring(position))
            baitSpawnedFlag = true
            castingRod = false -- Stop casting spam
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
    
    -- Step 1: Equip rod
    if not self:EquipRod(config.rodSlot) then
        return false
    end
    
    task.wait(0.1)

    -- Step 2: Charge rod
    if not self:ChargeRod(config.chargeTime) then
        return false
    end
    
    -- Step 3: Cast rod with spam until BaitSpawned
    if not self:CastRodWithSpam(config.castSpamDelay, config.maxCastTime) then
        return false
    end

    -- Step 4: Wait for bait to spawn (already handled in CastRodWithSpam)
    -- Step 5: Start completion spam with mode-specific behavior
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

-- Charge rod
function AutoFishFeature:ChargeRod(chargeTime)
    if not ChargeFishingRod then return false end
    
    local success = pcall(function()
        local chargeValue = tick() + (chargeTime * 1000)
        return ChargeFishingRod:InvokeServer(chargeValue)
    end)
    
    return success
end

-- Cast rod with spam until BaitSpawned
function AutoFishFeature:CastRodWithSpam(delay, maxTime)
    if not RequestFishing then return false end
    
    baitSpawnedFlag = false
    castingRod = true
    local castStartTime = tick()
    
    logger:info("Starting cast spam until BaitSpawned...")
    
    -- Spam cast until bait spawns or timeout
    while castingRod and isRunning and (tick() - castStartTime) < maxTime do
        -- Fire cast request
        local success = pcall(function()
            local x = -1.233184814453125
            local z = 0.9999120558411321
            RequestFishing:InvokeServer(x, z)
        end)
        
        if not success then
            logger:warn("Cast failed, retrying...")
        end
        
        -- Check if bait spawned
        if baitSpawnedFlag then
            logger:info("Bait confirmed spawned! Cast successful after", string.format("%.2f", tick() - castStartTime), "seconds")
            return true
        end
        
        task.wait(delay)
    end
    
    -- Timeout check
    if not baitSpawnedFlag then
        logger:warn("Cast timeout after", maxTime, "seconds - bait never spawned")
        castingRod = false
        return false
    end
    
    return true
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
        while spamActive and isRunning and (tick() - spamStartTime) < maxTime do
            -- Fire completion
            local fired = self:FireCompletion()
            
            -- Check if fishing completed using notification listener OR backpack method
            if fishCaughtFlag or self:CheckFishingCompleted() then
                logger:info("Fish caught detected!")
                break
            end
            
            task.wait(delay)
        end
        
        -- Stop spam
        spamActive = false
        completionCheckActive = false
        
        if (tick() - spamStartTime) >= maxTime then
            logger:info("SPAM timeout after", maxTime, "seconds")
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