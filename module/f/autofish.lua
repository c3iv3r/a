-- ===========================
-- AUTO FISH FEATURE - SPAM METHOD WITH SIGNAL TRIGGER
-- File: autofishv5_signal.lua
-- Flow: Equip > Charge > Cast > Fire Activated Signal > Spam Completion > Obtained > Repeat
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
local EquipTool, ChargeFishingRod, RequestFishing, FishingCompleted, FishObtainedNotification
local RE_FishingMinigameChanged -- ✅ NEW: Minigame signal

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
        RE_FishingMinigameChanged = NetPath:WaitForChild("RE/FishingMinigameChanged", 5) -- ✅ NEW
        
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
local controls = {}
local fishingInProgress = false
local lastFishTime = 0
local remotesInitialized = false

-- Spam and completion tracking
local spamActive = false
local completionCheckActive = false
local lastBackpackCount = 0
local fishCaughtFlag = false

-- Rod-specific configs
local FISHING_CONFIGS = {
    ["Fast"] = {
        chargeTime = 1.0,
        waitBetween = 0,
        rodSlot = 1,
        spamDelay = 0.05,      -- Spam every 50ms
        maxSpamTime = 20,       -- Stop spam after 20s
        skipMinigame = true,    -- Skip tap-tap animation
        signalDelay = 0.2       -- ✅ Delay sebelum fire signal
    },
    ["Slow"] = {
        chargeTime = 1.0,
        waitBetween = 1,
        rodSlot = 1,
        spamDelay = 0.1,
        maxSpamTime = 20,
        skipMinigame = false,  -- Play tap-tap animation
        minigameDuration = 5,  -- Duration before firing completion
        signalDelay = 0.3      -- ✅ Delay sebelum fire signal
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
    
    -- Verify signal remote
    if not RE_FishingMinigameChanged then
        logger:warn("RE/FishingMinigameChanged not found!")
        return false
    end
    
    -- Initialize backpack count for completion detection
    self:UpdateBackpackCount()
    
    logger:info("✅ Initialized with SIGNAL TRIGGER method")
    logger:info("✅ RE/FishingMinigameChanged ready")
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
    
    logger:info("🎣 Started AUTO FISH - Mode:", currentMode)
    logger:info("📋 Flow: Equip > Charge > Cast > Signal > Spam > Obtained > Repeat")
    
    -- Setup fish obtained listener
    self:SetupFishObtainedListener()
    
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
    
    logger:info("🛑 Stopped AUTO FISH")
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
            logger:info("🐟 Fish obtained notification received!")
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
                logger:info("✅ Ready for next cycle")
            end)
        end
    end)
    
    logger:info("✅ Fish obtained listener active")
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
            logger:info("✅ Fishing cycle completed!")
        else
            logger:warn("⚠️ Fishing cycle failed")
        end
    end)
end

-- Execute spam-based fishing sequence with signal
function AutoFishFeature:ExecuteSpamFishingSequence()
    local config = FISHING_CONFIGS[currentMode]
    
    -- Step 1: Equip rod
    logger:info("🎣 Step 1: Equipping rod...")
    if not self:EquipRod(config.rodSlot) then
        logger:warn("❌ Failed to equip rod")
        return false
    end
    task.wait(0.1)

    -- Step 2: Charge rod
    logger:info("⚡ Step 2: Charging rod...")
    if not self:ChargeRod(config.chargeTime) then
        logger:warn("❌ Failed to charge rod")
        return false
    end
    task.wait(0.1)
    
    -- Step 3: Cast rod (RequestFishingMinigameStarted)
    logger:info("🎯 Step 3: Casting rod...")
    if not self:CastRod() then
        logger:warn("❌ Failed to cast rod")
        return false
    end
    
    -- Wait for server to process cast
    task.wait(config.signalDelay)

    -- Step 4: Fire FishingMinigameChanged with "Activated" ✅ NEW
    logger:info("🔥 Step 4: Firing minigame 'Activated' signal...")
    if not self:FireMinigameActivated() then
        logger:warn("⚠️ Failed to fire signal (continuing anyway)")
        -- Don't return false, continue with spam
    end
    
    task.wait(0.1)

    -- Step 5: Start completion spam with mode-specific behavior
    logger:info("💨 Step 5: Starting completion spam...")
    self:StartCompletionSpam(config.spamDelay, config.maxSpamTime)
    
    return true
end

-- Equip rod
function AutoFishFeature:EquipRod(slot)
    if not EquipTool then return false end
    
    local success = pcall(function()
        EquipTool:FireServer(slot)
    end)
    
    if success then
        logger:info("  ✓ Rod equipped")
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
    
    if success then
        logger:info("  ✓ Rod charged")
    end
    
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
    
    if success then
        logger:info("  ✓ Rod casted to server")
    end
    
    return success
end

-- ✅ NEW: Fire FishingMinigameChanged with "Activated" action
function AutoFishFeature:FireMinigameActivated()
    if not RE_FishingMinigameChanged then return false end
    
    local success = pcall(function()
        -- Fire dengan "Activated" action saja
        -- Data kosong {} - biarkan server yang isi sisanya
        firesignal(RE_FishingMinigameChanged.OnClientEvent, "Activated", {})
    end)
    
    if success then
        logger:info("  ✓ Minigame 'Activated' signal fired")
    else
        logger:warn("  ✗ Failed to fire signal")
    end
    
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
    
    logger:info("  💨 Spam started - Mode:", currentMode)
    
    -- Update backpack count before spam
    self:UpdateBackpackCount()
    
    spawn(function()
        -- Mode-specific behavior
        if currentMode == "Slow" and not config.skipMinigame then
            -- Slow mode: Wait for minigame animation
            logger:info("  ⏳ Slow mode: Playing animation for", config.minigameDuration, "s")
            task.wait(config.minigameDuration)
            
            -- Check if fish was already caught during animation
            if fishCaughtFlag or not isRunning or not spamActive then
                spamActive = false
                completionCheckActive = false
                return
            end
        end
        
        local spamCount = 0
        
        -- Start spamming (for both modes, but Slow starts after minigame delay)
        while spamActive and isRunning and (tick() - spamStartTime) < maxTime do
            -- Fire completion
            local fired = self:FireCompletion()
            if fired then
                spamCount = spamCount + 1
            end
            
            -- Check if fishing completed using notification listener OR backpack method
            if fishCaughtFlag or self:CheckFishingCompleted() then
                logger:info("  ✓ Fish caught! (", spamCount, "attempts)")
                break
            end
            
            task.wait(delay)
        end
        
        -- Stop spam
        spamActive = false
        completionCheckActive = false
        
        if (tick() - spamStartTime) >= maxTime then
            logger:warn("  ⏱️ Spam timeout after", maxTime, "seconds (", spamCount, "attempts)")
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
        remotesReady = remotesInitialized,
        listenerReady = fishObtainedConnection ~= nil,
        signalReady = RE_FishingMinigameChanged ~= nil -- ✅ NEW
    }
end

-- Update mode
function AutoFishFeature:SetMode(mode)
    if FISHING_CONFIGS[mode] then
        currentMode = mode
        logger:info("Mode changed to:", mode)
        if mode == "Fast" then
            logger:info("  - Skip minigame: ON")
            logger:info("  - Signal delay:", FISHING_CONFIGS[mode].signalDelay, "s")
        elseif mode == "Slow" then  
            logger:info("  - Skip minigame: OFF (", FISHING_CONFIGS[mode].minigameDuration, "s animation)")
            logger:info("  - Signal delay:", FISHING_CONFIGS[mode].signalDelay, "s")
        end
        return true
    end
    return false
end

-- Get notification listener info for debugging
function AutoFishFeature:GetNotificationInfo()
    return {
        hasNotificationRemote = FishObtainedNotification ~= nil,
        listenerConnected = fishObtainedConnection ~= nil,
        fishCaughtFlag = fishCaughtFlag,
        hasSignalRemote = RE_FishingMinigameChanged ~= nil -- ✅ NEW
    }
end

-- Cleanup
function AutoFishFeature:Cleanup()
    logger:info("Cleaning up AUTO FISH...")
    self:Stop()
    controls = {}
    remotesInitialized = false
end

return AutoFishFeature