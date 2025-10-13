-- ===========================
-- AUTO FISH FEATURE - SPAM METHOD (FIXED WITH BAITSPAWNED + MINIGAME CHANGED)
-- File: autofishv2_patched.lua
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
local EquipTool, ChargeFishingRod, RequestFishing, FishingCompleted, FishObtainedNotification, BaitSpawned, FishingMinigameChanged

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
        FishingMinigameChanged = NetPath:WaitForChild("RE/FishingMinigameChanged", 5)  -- NEW!
        
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
local minigameActivatedFlag = false  -- NEW FLAG!

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
        skipMinigame = true,
        minigameActivationDelay = 0.1  -- Wait 300ms after bait before firing Activated
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
        minigameDuration = 5,
        minigameActivationDelay = 0.1
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
    
    logger:info("Initialized with SPAM method + BaitSpawned + MinigameChanged - Fast & Slow modes")
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
    minigameActivatedFlag = false  -- Reset flag
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
    minigameActivatedFlag = false
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
                
                -- Set flag regardless of castingRod state
                baitSpawnedFlag = true
                
                -- Stop casting if active
                if castingRod then
                    castingRod = false
                end
                
                -- NEW: Fire FishingMinigameChanged after delay
                spawn(function()
                    local config = FISHING_CONFIGS[currentMode]
                    task.wait(config.minigameActivationDelay)
                    
                    if isRunning and baitSpawnedFlag then
                        self:FireMinigameActivated()
                    end
                end)
            end
        end
    end)
    
    logger:info("Bait spawned listener setup complete")
end

-- NEW FUNCTION: Fire FishingMinigameChanged with "Activated"
function AutoFishFeature:FireMinigameActivated()
    if not FishingMinigameChanged then
        logger:warn("FishingMinigameChanged not available")
        return false
    end
    
    local success = pcall(function()
        FishingMinigameChanged:FireServer("Activated")
    end)
    
    if success then
        logger:info("✅ Fired FishingMinigameChanged (Activated)")
        minigameActivatedFlag = true
        return true
    else
        logger:warn("❌ Failed to fire FishingMinigameChanged")
        return false
    end
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
            
            -- Reset fishing state for next cycle
            spawn(function()
                task.wait(0.1)
                fishingInProgress = false
                fishCaughtFlag = false
                baitSpawnedFlag = false
                minigameActivatedFlag = false  -- Reset minigame flag
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
    
    -- Step 1: Equip rod (DOUBLE FIRE)
    logger:info("Step 1: Equipping rod (2x)...")
    if not self:EquipRod(config.rodSlot) then
        logger:warn("Failed to equip rod (1st attempt)")
        return false
    end
    task.wait(0.1)
    if not self:EquipRod(config.rodSlot) then
        logger:warn("Failed to equip rod (2nd attempt)")
        return false
    end
    
    task.wait(0.25)

    -- Step 2: Charge rod
    logger:info("Step 2: Charging rod...")
    if not self:ChargeRod(config.chargeTime, config.chargeAttempts) then
        logger:warn("Failed to charge rod")
        return false
    end
    
    task.wait(0.1)

    -- Step 3: Cast rod with spam until BaitSpawned
    logger:info("Step 3: Casting rod...")
    if not self:CastRodWithSpam(config.castSpamDelay, config.maxCastTime) then
        logger:warn("Failed to cast rod - bait never spawned")
        return false
    end

    -- Step 4: Verify bait spawned
    if not baitSpawnedFlag then
        logger:warn("Bait flag not set after cast - aborting cycle")
        return false
    end
    
    logger:info("✅ Bait confirmed in water!")
    
    -- Step 5: Wait for MinigameActivated to be fired (automatic from listener)
    logger:info("Step 4: Waiting for MinigameActivated...")
    local waitStart = tick()
    while not minigameActivatedFlag and (tick() - waitStart) < 2 do
        task.wait(0.1)
    end
    
    if not minigameActivatedFlag then
        logger:warn("⚠️ MinigameActivated not confirmed, continuing anyway...")
    else
        logger:info("✅ MinigameActivated confirmed!")
    end
    
    -- Step 6: Additional delay for server sync
    task.wait(0.1)
    
    -- Step 7: Final verification
    if not isRunning or not baitSpawnedFlag then
        logger:warn("State changed during minigame activation - aborting")
        return false
    end

    -- Step 8: Start completion spam
    logger:info("Step 5: Starting completion spam...")
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
        
        if i < attempts then
            task.wait(0.08)
        end
    end
    
    logger:info("Charge completed:", successCount, "/", attempts, "successful")
    
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
    minigameActivatedFlag = false  -- Reset minigame flag too
    castingRod = true
    local castStartTime = tick()
    local castAttempts = 0
    
    logger:info("Starting cast spam until BaitSpawned...")
    
    task.wait(0.05)
    
    while castingRod and isRunning and (tick() - castStartTime) < maxTime do
        if baitSpawnedFlag then
            logger:info("Bait confirmed spawned! Cast successful after", string.format("%.2f", tick() - castStartTime), "seconds (", castAttempts, "attempts)")
            castingRod = false
            return true
        end
        
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
    
    if baitSpawnedFlag then
        logger:info("Bait spawned (detected after loop)! Cast successful")
        castingRod = false
        return true
    end
    
    logger:warn("Cast timeout after", maxTime, "seconds -", castAttempts, "attempts")
    castingRod = false
    return false
end

-- Start spamming FishingCompleted
function AutoFishFeature:StartCompletionSpam(delay, maxTime)
    if spamActive then 
        logger:warn("Completion spam already active - skipping")
        return 
    end
    
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
    
    logger:info("Starting completion SPAM - Mode:", currentMode, "BaitFlag:", baitSpawnedFlag, "MinigameFlag:", minigameActivatedFlag)
    
    self:UpdateBackpackCount()
    
    spawn(function()
        if currentMode == "Slow" and not config.skipMinigame then
            logger:info("Slow mode: Playing minigame animation for", config.minigameDuration, "seconds")
            task.wait(config.minigameDuration)
            
            if fishCaughtFlag or not isRunning or not spamActive then
                spamActive = false
                completionCheckActive = false
                logger:info("Fish caught during animation delay")
                return
            end
        end
        
        while spamActive and isRunning and (tick() - spamStartTime) < maxTime do
            if tick() - lastCheckTime >= 0.2 then
                if fishCaughtFlag or self:CheckFishingCompleted() then
                    logger:info("✅ Fish caught detected! (", completionAttempts, "attempts in", string.format("%.2f", tick() - spamStartTime), "s)")
                    spamActive = false
                    completionCheckActive = false
                    return
                end
                lastCheckTime = tick()
            end
            
            completionAttempts = completionAttempts + 1
            local fired = self:FireCompletion()
            
            if not fired then
                logger:warn("Completion fire failed on attempt", completionAttempts)
            end
            
            task.wait(delay)
        end
        
        if fishCaughtFlag or self:CheckFishingCompleted() then
            logger:info("✅ Fish caught detected at final check!")
            spamActive = false
            completionCheckActive = false
            return
        end
        
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

-- Check if fishing completed successfully
function AutoFishFeature:CheckFishingCompleted()
    if fishCaughtFlag then
        return true
    end
    
    local currentCount = self:GetBackpackItemCount()
    if currentCount > lastBackpackCount then
        lastBackpackCount = currentCount
        return true
    end
    
    if LocalPlayer.Character then
        local tool = LocalPlayer.Character:FindFirstChildOfClass("Tool")
        if not tool then
            return false
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
        minigameActivated = minigameActivatedFlag,  -- NEW!
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

-- Get notification listener info
function AutoFishFeature:GetNotificationInfo()
    return {
        hasNotificationRemote = FishObtainedNotification ~= nil,
        hasBaitSpawnedRemote = BaitSpawned ~= nil,
        hasMinigameChangedRemote = FishingMinigameChanged ~= nil,  -- NEW!
        listenerConnected = fishObtainedConnection ~= nil,
        baitListenerConnected = baitSpawnedConnection ~= nil,
        fishCaughtFlag = fishCaughtFlag,
        baitSpawnedFlag = baitSpawnedFlag,
        minigameActivatedFlag = minigameActivatedFlag  -- NEW!
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