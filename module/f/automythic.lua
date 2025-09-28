-- ===========================
-- AUTO FISH V3 - STREAK-BASED RARE DETECTION
-- File: autofishv3.lua
-- ===========================

local AutoFishV3 = {}
AutoFishV3.__index = AutoFishV3

local logger = _G.Logger and _G.Logger.new("AutoFishV3") or {
    debug = function() end,
    info = function() end,
    warn = function() end,
    error = function() end
}

-- Load InventoryWatcher
local InventoryWatcher = _G.InventoryWatcher or loadstring(game:HttpGet("https://raw.githubusercontent.com/c3iv3r/a/refs/heads/main/utils/fishit/inventdetect.lua"))()

-- Services
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local LocalPlayer = Players.LocalPlayer

-- Network setup
local NetPath = nil
local EquipTool, ChargeFishingRod, RequestFishing, FishingCompleted, FishObtainedNotification, ReplicateTextEffect, CancelFishingInputs, EquipItem, EquipBait

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
        ReplicateTextEffect = NetPath:WaitForChild("RE/ReplicateTextEffect", 5)
        CancelFishingInputs = NetPath:WaitForChild("RF/CancelFishingInputs", 5)
        EquipItem = NetPath:WaitForChild("RE/EquipItem", 5)
        EquipBait = NetPath:WaitForChild("RE/EquipBait", 5)
        
        return true
    end)
    
    return success
end

-- Feature state
local isRunning = false
local connection = nil
local fishObtainedConnection = nil
local textEffectConnection = nil
local spamConnection = nil
local controls = {}
local fishingInProgress = false
local waitingForTextEffect = false
local spamActive = false
local fishCaughtFlag = false
local lastFishTime = 0
local remotesInitialized = false
local inventoryWatcher = nil
local starterRodUUID = nil

-- Streak and phase management
local rareStreak = 0
local targetRareStreak = 3
local currentPhase = "INITIAL" -- INITIAL, WAITING_FOR_MYTHIC_SECRET
local originalRod = nil
local originalBait = nil

-- Fish rarity colors
local FISH_COLORS = {
    Uncommon = {
        r = 0.76470589637756,
        g = 1,
        b = 0.33333334326744
    },
    Rare = {
        r = 0.33333334326744,
        g = 0.63529413938522,
        b = 1
    },
    Legendary = {
        r = 1,
        g = 0.72156864404678,
        b = 0.16470588743687
    },
    Mythic = {
        r = 1,
        g = 0.094117648899555,
        b = 0.094117648899555
    }
}

-- Fast mode config
local FAST_CONFIG = {
    chargeTime = 1.0,
    waitBetween = 0,
    rodSlot = 1,
    spamDelay = 0.05,
    maxSpamTime = 30,
    textEffectTimeout = 10
}

-- Initialize
function AutoFishV3:Init(guiControls)
    controls = guiControls or {}
    remotesInitialized = initializeRemotes()
    
    if not remotesInitialized then
        logger:warn("Failed to initialize remotes")
        return false
    end
    
    -- Initialize InventoryWatcher
    inventoryWatcher = InventoryWatcher.new()
    
    -- Wait for inventory to be ready and find starter rod
    inventoryWatcher:onReady(function()
        self:FindStarterRod()
    end)
    
    logger:info("Initialized AutoFish V3 - Streak-Based Rare Detection")
    return true
end

-- Find Starter Rod UUID from inventory
function AutoFishV3:FindStarterRod()
    if not inventoryWatcher then
        logger:warn("InventoryWatcher not available")
        return
    end
    
    local fishingRods = inventoryWatcher:getSnapshotTyped("Fishing Rods")
    
    for _, rod in ipairs(fishingRods) do
        local rodId = rod.Id or rod.id
        -- Assuming Starter Rod has ID = 1 (adjust if needed)
        if rodId == 1 or tostring(rodId) == "1" then
            starterRodUUID = rod.UUID or rod.Uuid or rod.uuid
            logger:info("Found Starter Rod UUID:", starterRodUUID)
            break
        end
    end
    
    if not starterRodUUID then
        logger:warn("Starter Rod not found in inventory")
    end
end

-- Cache original equipment
function AutoFishV3:CacheOriginalEquipment()
    -- This should be called to remember the original rod and bait before switching
    -- Implementation depends on how current equipment is tracked in the game
    -- For now, we'll store placeholder values that should be replaced with actual detection
    originalRod = {uuid = "ORIGINAL_ROD_UUID", category = "Fishing Rods"} -- Replace with actual detection
    originalBait = {id = "ORIGINAL_BAIT_ID"} -- Replace with actual detection
    
    logger:info("Cached original equipment - Rod:", originalRod, "Bait:", originalBait)
end

-- Teleport to fishing location
function AutoFishV3:TeleportToFishingSpot()
    if not LocalPlayer.Character or not LocalPlayer.Character:FindFirstChild("HumanoidRootPart") then
        logger:warn("Character or HumanoidRootPart not found")
        return false
    end
    
    local success = pcall(function()
        LocalPlayer.Character.HumanoidRootPart.CFrame = CFrame.new(1028, 2, 5148)
    end)
    
    if success then
        logger:info("Teleported to fishing spot")
        return true
    else
        logger:warn("Failed to teleport")
        return false
    end
end

-- Equip Starter Rod to hotbar
function AutoFishV3:EquipStarterRod()
    if not EquipItem then
        logger:warn("EquipItem remote not available")
        return false
    end
    
    if not starterRodUUID then
        logger:warn("Starter Rod UUID not found")
        return false
    end
    
    local success = pcall(function()
        EquipItem:FireServer(starterRodUUID, "Fishing Rods")
    end)
    
    if success then
        logger:info("Equipped Starter Rod to hotbar")
        return true
    else
        logger:warn("Failed to equip Starter Rod")
        return false
    end
end

-- Equip Midnight Bait
function AutoFishV3:EquipMidnightBait()
    if not EquipBait then
        logger:warn("EquipBait remote not available")
        return false
    end
    
    local success = pcall(function()
        EquipBait:FireServer(3)
    end)
    
    if success then
        logger:info("Equipped Midnight Bait")
        return true
    else
        logger:warn("Failed to equip Midnight Bait")
        return false
    end
end

-- Restore original equipment
function AutoFishV3:RestoreOriginalEquipment()
    if not originalRod or not originalBait then
        logger:warn("Original equipment not cached")
        return false
    end
    
    local success = true
    
    -- Restore original rod
    if EquipItem and originalRod.uuid and originalRod.category then
        local rodSuccess = pcall(function()
            EquipItem:FireServer(originalRod.uuid, originalRod.category)
        end)
        if not rodSuccess then
            success = false
            logger:warn("Failed to restore original rod")
        else
            logger:info("Restored original rod")
        end
    end
    
    -- Restore original bait
    if EquipBait and originalBait.id then
        local baitSuccess = pcall(function()
            EquipBait:FireServer(originalBait.id)
        end)
        if not baitSuccess then
            success = false
            logger:warn("Failed to restore original bait")
        else
            logger:info("Restored original bait")
        end
    end
    
    return success
end

-- Start fishing
function AutoFishV3:Start(config)
    if isRunning then return end
    
    if not remotesInitialized then
        logger:warn("Cannot start - remotes not initialized")
        return
    end
    
    -- Cache original equipment before starting
    self:CacheOriginalEquipment()
    
    -- Ensure starter rod is found before starting
    if not starterRodUUID then
        self:FindStarterRod()
    end

    local teleported = self:TeleportToFishingSpot()
    if teleported then
        task.wait(0.5)
    end

    -- Reset phase and streak
    currentPhase = "INITIAL"
    rareStreak = 0
    
    isRunning = true
    fishingInProgress = false
    waitingForTextEffect = false
    spamActive = false
    fishCaughtFlag = false
    lastFishTime = 0
    
    logger:info("Started AutoFish V3 - Phase:", currentPhase, "Rare Streak:", rareStreak)
    
    self:SetupTextEffectListener()
    self:SetupFishObtainedListener()
    
    connection = RunService.Heartbeat:Connect(function()
        if not isRunning then return end
        self:FishingLoop()
    end)
end

-- Stop fishing
function AutoFishV3:Stop()
    if not isRunning then return end
    
    isRunning = false
    fishingInProgress = false
    waitingForTextEffect = false
    spamActive = false
    fishCaughtFlag = false
    
    if connection then
        connection:Disconnect()
        connection = nil
    end
    
    if fishObtainedConnection then
        fishObtainedConnection:Disconnect()
        fishObtainedConnection = nil
    end
    
    if textEffectConnection then
        textEffectConnection:Disconnect()
        textEffectConnection = nil
    end
    
    if spamConnection then
        spamConnection:Disconnect()
        spamConnection = nil
    end
    
    logger:info("Stopped AutoFish V3")
end

-- Setup text effect listener
function AutoFishV3:SetupTextEffectListener()
    if not ReplicateTextEffect then
        logger:warn("ReplicateTextEffect not available")
        return
    end
    
    if textEffectConnection then
        textEffectConnection:Disconnect()
    end
    
    textEffectConnection = ReplicateTextEffect.OnClientEvent:Connect(function(data)
        if not isRunning or not waitingForTextEffect then return end
        
        self:HandleTextEffect(data)
    end)
    
    logger:info("Text effect listener setup complete")
end

-- Setup fish obtained listener
function AutoFishV3:SetupFishObtainedListener()
    if not FishObtainedNotification then
        logger:warn("FishObtainedNotification not available")
        return
    end
    
    if fishObtainedConnection then
        fishObtainedConnection:Disconnect()
    end
    
    fishObtainedConnection = FishObtainedNotification.OnClientEvent:Connect(function(...)
        if isRunning then
            logger:info("Fish obtained notification received!")
            fishCaughtFlag = true
            
            if spamActive then
                spamActive = false
            end
            
            -- Handle phase transition after catching Mythic/Secret
            if currentPhase == "WAITING_FOR_MYTHIC_SECRET" then
                logger:info("Mythic/Secret caught! Restoring original equipment...")
                spawn(function()
                    task.wait(0.5)
                    self:RestoreOriginalEquipment()
                    currentPhase = "INITIAL"
                    rareStreak = 0
                    logger:info("Returned to INITIAL phase")
                end)
            end
            
            spawn(function()
                task.wait(0.1)
                fishingInProgress = false
                waitingForTextEffect = false
                fishCaughtFlag = false
                logger:info("Ready for next cycle")
            end)
        end
    end)
    
    logger:info("Fish obtained listener setup complete")
end

-- Handle text effect
function AutoFishV3:HandleTextEffect(data)
    if not data or not data.TextData then return end
    
    -- Check if effect is attached to our character
    if not LocalPlayer.Character or not LocalPlayer.Character.Head then return end
    if data.TextData.AttachTo ~= LocalPlayer.Character.Head then return end
    
    -- Check text color for rarity
    local textColor = data.TextData.TextColor
    if not textColor or not textColor.Keypoints then return end
    
    local keypoint = textColor.Keypoints[1]
    if not keypoint then return end
    
    local color = keypoint.Value
    local rarity = self:GetFishRarity(color)
    
    if currentPhase == "INITIAL" then
        self:HandleInitialPhase(rarity)
    elseif currentPhase == "WAITING_FOR_MYTHIC_SECRET" then
        self:HandleMythicSecretPhase(rarity)
    end
    
    waitingForTextEffect = false
end

-- Handle initial phase logic
function AutoFishV3:HandleInitialPhase(rarity)
    if rarity == "Rare" then
        rareStreak = rareStreak + 1
        logger:info("Rare detected! Streak:", rareStreak, "/", targetRareStreak, "- Canceling")
        self:CancelFishing()
        
        if rareStreak >= targetRareStreak then
            logger:info("Rare streak completed! Switching to Starter Rod and Midnight Bait...")
            spawn(function()
                task.wait(1)
                self:EquipStarterRod()
                task.wait(0.1)
                self:EquipMidnightBait()
                currentPhase = "WAITING_FOR_MYTHIC_SECRET"
                logger:info("Phase changed to WAITING_FOR_MYTHIC_SECRET")
            end)
        end
    else
        if rareStreak > 0 then
            logger:info("Streak broken! Non-rare fish detected. Resetting streak and spamming completion")
            rareStreak = 0
        else
            logger:info("Common/Uncommon fish - spamming completion")
        end
        self:StartCompletionSpam()
    end
end

-- Handle mythic/secret waiting phase logic
function AutoFishV3:HandleMythicSecretPhase(rarity)
    if rarity == "Mythic" or rarity == "Secret" then
        logger:info(rarity, "detected! Spamming completion to catch it...")
        self:StartCompletionSpam()
    elseif rarity == "Legendary" or rarity == "Rare" then
        logger:info(rarity, "detected - canceling to wait for Mythic/Secret")
        self:CancelFishing()
    else
        logger:info("Common/Uncommon fish - spamming completion")
        self:StartCompletionSpam()
    end
end

-- Get fish rarity from color
function AutoFishV3:GetFishRarity(color)
    local threshold = 0.01
    
    -- Check all rarity colors
    for rarity, rarityColor in pairs(FISH_COLORS) do
        if math.abs(color.R - rarityColor.r) < threshold and
           math.abs(color.G - rarityColor.g) < threshold and
           math.abs(color.B - rarityColor.b) < threshold then
            return rarity
        end
    end
    
    -- Check for Secret (same as Mythic color for now, but could be different)
    -- If Secret has different color, add it to FISH_COLORS table
    
    return nil -- Common fish
end

-- Cancel fishing
function AutoFishV3:CancelFishing()
    if not CancelFishingInputs then
        logger:warn("CancelFishingInputs not available")
        return
    end
    
    local success = pcall(function()
        CancelFishingInputs:InvokeServer()
    end)
    
    if success then
        logger:info("Fishing cancelled successfully")
    else
        logger:warn("Failed to cancel fishing")
    end
    
    -- Reset state for next cycle
    spawn(function()
        task.wait(0.5)
        fishingInProgress = false
        waitingForTextEffect = false
    end)
end

-- Main fishing loop
function AutoFishV3:FishingLoop()
    if fishingInProgress or waitingForTextEffect or spamActive then return end
    
    local currentTime = tick()
    
    if currentTime - lastFishTime < FAST_CONFIG.waitBetween then
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
function AutoFishV3:ExecuteFishingSequence()
    -- Step 1: Equip rod
    if not self:EquipRod(FAST_CONFIG.rodSlot) then
        return false
    end
    
    task.wait(0.1)
    
    -- Step 2: Charge rod
    if not self:ChargeRod(FAST_CONFIG.chargeTime) then
        return false
    end
    
    -- Step 3: Cast rod
    if not self:CastRod() then
        return false
    end
    
    -- Step 4: Wait for text effect
    waitingForTextEffect = true
    logger:info("Waiting for text effect... Phase:", currentPhase, "Rare Streak:", rareStreak)
    
    -- Timeout for text effect
    spawn(function()
        task.wait(FAST_CONFIG.textEffectTimeout)
        if waitingForTextEffect then
            logger:warn("Text effect timeout - starting spam anyway")
            waitingForTextEffect = false
            self:StartCompletionSpam()
        end
    end)
    
    return true
end

-- Start spamming completion
function AutoFishV3:StartCompletionSpam()
    if spamActive then return end
    
    spamActive = true
    fishCaughtFlag = false
    local spamStartTime = tick()
    
    logger:info("Starting completion spam")
    
    spawn(function()
        while spamActive and isRunning and (tick() - spamStartTime) < FAST_CONFIG.maxSpamTime do
            self:FireCompletion()
            
            if fishCaughtFlag then
                logger:info("Fish caught detected!")
                break
            end
            
            task.wait(FAST_CONFIG.spamDelay)
        end
        
        spamActive = false
        
        if (tick() - spamStartTime) >= FAST_CONFIG.maxSpamTime then
            logger:info("Spam timeout after", FAST_CONFIG.maxSpamTime, "seconds")
            fishingInProgress = false
        end
    end)
end

-- Equip rod
function AutoFishV3:EquipRod(slot)
    if not EquipTool then return false end
    
    local success = pcall(function()
        EquipTool:FireServer(slot)
    end)
    
    return success
end

-- Charge rod
function AutoFishV3:ChargeRod(chargeTime)
    if not ChargeFishingRod then return false end
    
    local success = pcall(function()
        local chargeValue = tick() + (chargeTime * 1000)
        return ChargeFishingRod:InvokeServer(chargeValue)
    end)
    
    return success
end

-- Cast rod
function AutoFishV3:CastRod()
    if not RequestFishing then return false end
    
    local success = pcall(function()
        local x = -1.233184814453125
        local z = 0.9999120558411321
        return RequestFishing:InvokeServer(x, z)
    end)
    
    return success
end

-- Fire completion
function AutoFishV3:FireCompletion()
    if not FishingCompleted then return false end
    
    local success = pcall(function()
        FishingCompleted:FireServer()
    end)
    
    return success
end

-- Get status
function AutoFishV3:GetStatus()
    return {
        running = isRunning,
        inProgress = fishingInProgress,
        waitingForEffect = waitingForTextEffect,
        spamming = spamActive,
        lastCatch = lastFishTime,
        fishCaughtFlag = fishCaughtFlag,
        remotesReady = remotesInitialized,
        textEffectListenerReady = textEffectConnection ~= nil,
        fishObtainedListenerReady = fishObtainedConnection ~= nil,
        inventoryReady = inventoryWatcher ~= nil,
        starterRodFound = starterRodUUID ~= nil,
        currentPhase = currentPhase,
        rareStreak = rareStreak,
        targetRareStreak = targetRareStreak,
        originalEquipmentCached = originalRod ~= nil and originalBait ~= nil
    }
end

-- Cleanup
function AutoFishV3:Cleanup()
    logger:info("Cleaning up AutoFish V3...")
    self:Stop()
    if inventoryWatcher then
        inventoryWatcher:destroy()
        inventoryWatcher = nil
    end
    controls = {}
    remotesInitialized = false
    starterRodUUID = nil
    originalRod = nil
    originalBait = nil
    rareStreak = 0
    currentPhase = "INITIAL"
end

return AutoFishV3