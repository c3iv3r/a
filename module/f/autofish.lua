-- ===========================
-- AUTO FISH FEATURE - PROPER WINDUP HOOK
-- File: autofishv6_proper_hook.lua
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
local EquipTool, ChargeFishingRod, RequestFishing, FishingCompleted, FishObtainedNotification, FishingMinigameChanged

-- Items tables
local ItemsModule = nil
local originalItemsCache = {}

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
        FishingMinigameChanged = NetPath:WaitForChild("RE/FishingMinigameChanged", 5)
        
        return true
    end)
    
    return success
end

local function initializeItemsModule()
    local success = pcall(function()
        ItemsModule = require(ReplicatedStorage:WaitForChild("Items", 5))
        return true
    end)
    return success
end

-- Feature state
local isRunning = false
local currentMode = "Ultra"
local connection = nil
local biteConnection = nil
local fishObtainedConnection = nil
local controls = {}
local fishingInProgress = false
local lastFishTime = 0
local remotesInitialized = false
local itemsModuleInitialized = false

-- Spam and completion tracking
local spamActive = false
local completionCheckActive = false
local lastBackpackCount = 0
local fishCaughtFlag = false
local windupHookInstalled = false

-- Rod-specific configs
local FISHING_CONFIGS = {
    ["Ultra"] = {
        chargeTime = 0.5,
        waitBetween = 0,
        rodSlot = 1,
        spamDelay = 0.03,
        maxSpamTime = 15,
        skipMinigame = true,
        modifyWindup = true,
        windupOverride = NumberRange.new(0.3, 0.5),
        usePredictiveTiming = true,
        preSpamOffset = 0.1
    },
    ["Fast"] = {
        chargeTime = 1.0,
        waitBetween = 0,
        rodSlot = 1,
        spamDelay = 0.05,
        maxSpamTime = 20,
        skipMinigame = true,
        modifyWindup = false,
        usePredictiveTiming = true,
        preSpamOffset = 0.2
    },
    ["Legit"] = {
        chargeTime = 1.0,
        waitBetween = 0.5,
        rodSlot = 1,
        spamDelay = 0.1,
        maxSpamTime = 20,
        skipMinigame = false,
        minigameDuration = 3,
        modifyWindup = false,
        usePredictiveTiming = false
    }
}

-- ========================================
-- PROPER WINDUP HOOK - HOOK ITEMS TABLE
-- ========================================
function AutoFishFeature:InstallWindupHook()
    if not ItemsModule or windupHookInstalled then 
        return false 
    end
    
    local config = FISHING_CONFIGS[currentMode]
    if not config.modifyWindup then
        logger:info("Windup modification disabled for mode:", currentMode)
        return false
    end
    
    local success = pcall(function()
        logger:info("Installing DIRECT table hook on Items module...")
        
        local hookedCount = 0
        
        -- Hook setiap fishing rod di Items table
        for itemName, itemData in pairs(ItemsModule) do
            if itemData.Data and itemData.Data.Type == "Fishing Rods" then
                -- Cache original windup
                if not originalItemsCache[itemName] then
                    originalItemsCache[itemName] = {
                        Windup = itemData.Windup,
                        BobberAnimationDelay = itemData.BobberAnimationDelay,
                        catchAnimationDelay = itemData.catchAnimationDelay
                    }
                end
                
                -- Modify windup directly
                itemData.Windup = config.windupOverride
                
                -- Reduce animation delays
                if itemData.BobberAnimationDelay then
                    itemData.BobberAnimationDelay = 0.05
                end
                if itemData.catchAnimationDelay then
                    itemData.catchAnimationDelay = 0.05
                end
                
                hookedCount = hookedCount + 1
                
                logger:debug("Hooked rod:", itemName,
                    "Original:", originalItemsCache[itemName].Windup and tostring(originalItemsCache[itemName].Windup) or "nil",
                    "New:", tostring(itemData.Windup))
            end
        end
        
        windupHookInstalled = true
        logger:info("Direct table hook installed! Modified", hookedCount, "fishing rods")
    end)
    
    if not success then
        logger:error("Failed to install windup hook")
    end
    
    return success
end

-- Restore original windup values
function AutoFishFeature:RestoreWindup()
    if not ItemsModule or not windupHookInstalled then 
        return 
    end
    
    logger:info("Restoring original windup values...")
    
    for itemName, cachedData in pairs(originalItemsCache) do
        local itemData = ItemsModule[itemName]
        if itemData then
            itemData.Windup = cachedData.Windup
            itemData.BobberAnimationDelay = cachedData.BobberAnimationDelay
            itemData.catchAnimationDelay = cachedData.catchAnimationDelay
        end
    end
    
    windupHookInstalled = false
    logger:info("Windup restored")
end

-- Get equipped rod data (read from hooked table)
function AutoFishFeature:GetEquippedRodData()
    if not ItemsModule then 
        return nil 
    end
    
    local success, result = pcall(function()
        local Replion = require(ReplicatedStorage.Packages.Replion)
        local dataReplion = Replion.Client:FindReplion("Data")
        if not dataReplion then return nil end
        
        local equippedId = dataReplion:Get("EquippedId")
        if not equippedId or equippedId == "" then return nil end
        
        -- Get inventory item
        local inventory = dataReplion:Get("Inventory")
        if not inventory then return nil end
        
        local equippedItem = nil
        for _, item in pairs(inventory) do
            if item.UUID == equippedId then
                equippedItem = item
                break
            end
        end
        
        if not equippedItem then return nil end
        
        -- Get item data from Items table (now hooked!)
        return ItemsModule[equippedItem.Id]
    end)
    
    return success and result or nil
end

-- Calculate predicted bite time
function AutoFishFeature:PredictBiteTime()
    local rodData = self:GetEquippedRodData()
    
    if not rodData or not rodData.Windup then
        logger:debug("No rod data, using default: 2s")
        return 2.0
    end
    
    local windupMin = rodData.Windup.Min
    local windupMax = rodData.Windup.Max
    local avgWindup = (windupMin + windupMax) / 2
    
    logger:debug("Predicted bite:", avgWindup, "s (", windupMin, "-", windupMax, ")")
    
    return avgWindup
end

-- Setup bite detection listener
function AutoFishFeature:SetupBiteListener()
    if not FishingMinigameChanged then
        logger:warn("FishingMinigameChanged not available")
        return
    end
    
    if biteConnection then
        biteConnection:Disconnect()
    end
    
    biteConnection = FishingMinigameChanged.OnClientEvent:Connect(function(eventType, data)
        if eventType == "Activated" and isRunning then
            logger:info("🎣 BITE DETECTED!")
            
            if not spamActive then
                local config = FISHING_CONFIGS[currentMode]
                self:StartCompletionSpam(config.spamDelay, config.maxSpamTime, true)
            end
        end
    end)
    
    logger:info("Bite listener ready")
end

-- Initialize
function AutoFishFeature:Init(guiControls)
    controls = guiControls or {}
    remotesInitialized = initializeRemotes()
    itemsModuleInitialized = initializeItemsModule()
    
    if not remotesInitialized then
        logger:warn("Failed to initialize remotes")
        return false
    end
    
    if not itemsModuleInitialized then
        logger:warn("Failed to initialize Items module")
        logger:info("Windup modification will be disabled")
    end
    
    self:UpdateBackpackCount()
    self:SetupBiteListener()
    
    logger:info("✅ Initialized - Direct Items table hook method")
    logger:info("Modes: Ultra (0.3-0.5s windup), Fast (natural), Legit (safe)")
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
    currentMode = config.mode or "Ultra"
    fishingInProgress = false
    spamActive = false
    lastFishTime = 0
    fishCaughtFlag = false
    
    -- Install windup hook
    local modeConfig = FISHING_CONFIGS[currentMode]
    if modeConfig.modifyWindup and itemsModuleInitialized then
        self:InstallWindupHook()
    end
    
    logger:info("🚀 Started -", currentMode, "mode")
    logger:info("Charge:", modeConfig.chargeTime, "| Spam:", modeConfig.spamDelay, "| Predictive:", modeConfig.usePredictiveTiming)
    
    self:SetupFishObtainedListener()
    
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
    
    if biteConnection then
        biteConnection:Disconnect()
        biteConnection = nil
    end
    
    if fishObtainedConnection then
        fishObtainedConnection:Disconnect()
        fishObtainedConnection = nil
    end
    
    -- Restore original windup
    self:RestoreWindup()
    
    logger:info("⏹️ Stopped")
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
            
            if spamActive then
                spamActive = false
                completionCheckActive = false
            end
            
            spawn(function()
                task.wait(0.05)
                fishingInProgress = false
                fishCaughtFlag = false
            end)
        end
    end)
end

-- Main fishing loop
function AutoFishFeature:SpamFishingLoop()
    if fishingInProgress or spamActive then return end
    
    local currentTime = tick()
    local config = FISHING_CONFIGS[currentMode]
    
    if currentTime - lastFishTime < config.waitBetween then
        return
    end
    
    fishingInProgress = true
    lastFishTime = currentTime
    
    spawn(function()
        local success = self:ExecuteSpamFishingSequence()
        if not success then
            fishingInProgress = false
        end
    end)
end

-- Execute fishing sequence
function AutoFishFeature:ExecuteSpamFishingSequence()
    local config = FISHING_CONFIGS[currentMode]
    
    if not self:EquipRod(config.rodSlot) then
        logger:warn("❌ Equip failed")
        return false
    end
    
    task.wait(0.05)

    if not self:ChargeRod(config.chargeTime) then
        logger:warn("❌ Charge failed")
        return false
    end
    
    local castTime = tick()
    if not self:CastRod() then
        logger:warn("❌ Cast failed")
        return false
    end
    
    logger:info("🎣 Cast OK @", string.format("%.2f", castTime))

    -- Predictive timing or immediate spam
    if config.usePredictiveTiming and itemsModuleInitialized then
        local predictedBiteTime = self:PredictBiteTime()
        local waitTime = math.max(0, predictedBiteTime - config.preSpamOffset)
        
        logger:info("⏳ Waiting", string.format("%.2f", waitTime), "s (predicted:", string.format("%.2f", predictedBiteTime), "s)")
        task.wait(waitTime)
        
        self:StartCompletionSpam(config.spamDelay, config.maxSpamTime, false)
    else
        self:StartCompletionSpam(config.spamDelay, config.maxSpamTime, false)
    end
    
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
function AutoFishFeature:ChargeRod(chargeTime)
    if not ChargeFishingRod then return false end
    return pcall(function()
        local chargeValue = tick() + (chargeTime * 1000)
        return ChargeFishingRod:InvokeServer(chargeValue)
    end)
end

-- Cast rod
function AutoFishFeature:CastRod()
    if not RequestFishing then return false end
    return pcall(function()
        local x = -1.233184814453125
        local z = 0.9999120558411321
        return RequestFishing:InvokeServer(x, z)
    end)
end

-- Start completion spam
function AutoFishFeature:StartCompletionSpam(delay, maxTime, fromBiteEvent)
    if spamActive then 
        return 
    end
    
    spamActive = true
    completionCheckActive = true
    fishCaughtFlag = false
    local spamStartTime = tick()
    local config = FISHING_CONFIGS[currentMode]
    
    if fromBiteEvent then
        logger:info("⚡ INSTANT spam (bite event)")
    else
        logger:info("🔄 Predictive spam started")
    end
    
    self:UpdateBackpackCount()
    
    spawn(function()
        -- Legit mode: wait for minigame
        if currentMode == "Legit" and not config.skipMinigame then
            logger:info("Waiting", config.minigameDuration, "s (minigame)")
            task.wait(config.minigameDuration)
            
            if fishCaughtFlag or not isRunning or not spamActive then
                spamActive = false
                completionCheckActive = false
                return
            end
        end
        
        -- Spam loop
        local spamCount = 0
        while spamActive and isRunning and (tick() - spamStartTime) < maxTime do
            self:FireCompletion()
            spamCount = spamCount + 1
            
            if fishCaughtFlag or self:CheckFishingCompleted() then
                local elapsed = tick() - spamStartTime
                logger:info("✅ Caught! Attempts:", spamCount, "Time:", string.format("%.2f", elapsed), "s")
                break
            end
            
            task.wait(delay)
        end
        
        spamActive = false
        completionCheckActive = false
        fishingInProgress = false
        
        if (tick() - spamStartTime) >= maxTime then
            logger:warn("⏰ Timeout after", maxTime, "s")
        end
    end)
end

-- Fire completion
function AutoFishFeature:FireCompletion()
    if not FishingCompleted then return false end
    return pcall(function()
        FishingCompleted:FireServer()
    end)
end

-- Check if completed
function AutoFishFeature:CheckFishingCompleted()
    if fishCaughtFlag then
        return true
    end
    
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

-- Get backpack count
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
    local rodData = self:GetEquippedRodData()
    local windupInfo = "N/A"
    
    if rodData and rodData.Windup then
        windupInfo = string.format("%.2f-%.2fs", rodData.Windup.Min, rodData.Windup.Max)
    end
    
    return {
        running = isRunning,
        mode = currentMode,
        inProgress = fishingInProgress,
        spamming = spamActive,
        windupHook = windupHookInstalled,
        currentWindup = windupInfo,
        remotesReady = remotesInitialized,
        itemsReady = itemsModuleInitialized
    }
end

-- Set mode
function AutoFishFeature:SetMode(mode)
    if FISHING_CONFIGS[mode] then
        local wasRunning = isRunning
        
        if wasRunning then
            self:Stop()
        end
        
        currentMode = mode
        
        logger:info("Mode:", mode)
        
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
    originalItemsCache = {}
    remotesInitialized = false
    itemsModuleInitialized = false
end

return AutoFishFeature