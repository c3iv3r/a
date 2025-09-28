-- AutoInfEnchant Module
-- Auto fishing untuk farm enchant stones dengan rarity detection
local AutoInfEnchant = {}
AutoInfEnchant.__index = AutoInfEnchant

-- Services
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local HttpService = game:GetService("HttpService")
local LocalPlayer = Players.LocalPlayer

-- Logger setup
local logger = _G.Logger and _G.Logger.new("AutoInfEnchant") or {
    debug = function() end,
    info = function() end,
    warn = function() end,
    error = function() end
}

-- Load InventoryWatcher via loadstring with global cache
local InventoryWatcher = _G.InventoryWatcher or loadstring(game:HttpGet("https://raw.githubusercontent.com/c3iv3r/a/refs/heads/main/utils/fishit/inventdetect.lua"))()
_G.InventoryWatcher = InventoryWatcher

-- Network Remotes
local NetPath = ReplicatedStorage.Packages._Index["sleitnick_net@0.2.0"].net
local ReplicateTextEffect = NetPath["RE/ReplicateTextEffect"]
local CancelFishingInputs = NetPath["RF/CancelFishingInputs"]
local EquipItem = NetPath["RE/EquipItem"]
local EquipBait = NetPath["RE/EquipBait"]
local EquipTool = NetPath["RE/EquipToolFromHotbar"]
local ChargeFishingRod = NetPath["RF/ChargeFishingRod"]
local RequestFishing = NetPath["RF/RequestFishingMinigameStarted"]
local FishingCompleted = NetPath["RE/FishingCompleted"]
local ObtainedNewFishNotification = NetPath["RE/ObtainedNewFishNotification"]

-- Rarity Color Mapping
local RARITY_COLORS = {
    ["0.765_1.000_0.333"] = "Uncommon",  -- Hijau terang
    ["0.333_0.635_1.000"] = "Rare"      -- Biru
}

-- Configuration
local CONFIG = {
    teleportLocation = CFrame.new(3247, -1302, 1376),
    midnightBaitId = 3,
    rodHotbarSlot = 1,
    chargeTime = 1.0,
    castPosition = {x = -1.233184814453125, z = 0.9999120558411321},
    spamDelay = 0.05,
    maxSpamTime = 20
}

-- State
local isRunning = false
local fishingInProgress = false
local spamActive = false
local rarityListener = nil
local fishObtainedListener = nil
local mainLoop = nil
local starterRodUUID = nil
local inventoryWatcher = nil

-- Initialize
function AutoInfEnchant:Init()
    -- Check if InventoryWatcher is loaded
    if not InventoryWatcher then
        logger:error("Failed to load InventoryWatcher")
        return false
    end
    
    -- Create InventoryWatcher instance  
    local success, err = pcall(function()
        inventoryWatcher = InventoryWatcher.new()
    end)
    
    if not success then
        logger:error("Failed to create InventoryWatcher instance:", err)
        return false
    end
    
    if not inventoryWatcher then
        logger:error("InventoryWatcher instance is nil")
        return false
    end
    
    logger:info("AutoInfEnchant initialized successfully")
    return true
end

-- Start AutoInfEnchant
function AutoInfEnchant:Start()
    if isRunning then 
        logger:warn("Already running")
        return false 
    end

    -- Wait for InventoryWatcher to be ready
    if inventoryWatcher then
        inventoryWatcher:onReady(function()
            self:StartFishingProcess()
        end)
    else
        logger:error("InventoryWatcher not initialized")
        return false
    end
    
    return true
end

-- Internal start process after InventoryWatcher is ready
function AutoInfEnchant:StartFishingProcess()
    -- Step 1: Teleport
    if not self:Teleport() then
        logger:error("Teleport failed")
        return false
    end

    -- Step 2: Find Starter Rod UUID
    starterRodUUID = self:FindStarterRodUUID()
    if not starterRodUUID then
        logger:error("Starter Rod not found in inventory")
        return false
    end

    -- Step 3: Setup equipment
    if not self:SetupEquipment() then
        logger:error("Equipment setup failed")
        return false
    end

    -- Step 4: Setup listeners
    self:SetupRarityListener()
    self:SetupFishObtainedListener()

    isRunning = true
    logger:info("AutoInfEnchant started")

    -- Step 5: Start main fishing loop
    mainLoop = RunService.Heartbeat:Connect(function()
        self:MainFishingLoop()
    end)
end

-- Stop AutoInfEnchant
function AutoInfEnchant:Stop()
    if not isRunning then return end

    isRunning = false
    fishingInProgress = false
    spamActive = false

    -- Disconnect listeners
    if rarityListener then rarityListener:Disconnect() end
    if fishObtainedListener then fishObtainedListener:Disconnect() end
    if mainLoop then mainLoop:Disconnect() end

    rarityListener = nil
    fishObtainedListener = nil
    mainLoop = nil

    logger:info("AutoInfEnchant stopped")
end

-- Teleport to location
function AutoInfEnchant:Teleport()
    local success = pcall(function()
        LocalPlayer.Character.HumanoidRootPart.CFrame = CONFIG.teleportLocation
    end)
    
    if success then
        task.wait(1) -- Wait for teleport to complete
        logger:info("Teleported to fishing location")
    end
    
    return success
end

-- Find Starter Rod UUID from inventory
function AutoInfEnchant:FindStarterRodUUID()
    if not inventoryWatcher then
        logger:error("InventoryWatcher not available")
        return nil
    end

    local rods = inventoryWatcher:getSnapshotTyped("Fishing Rods")
    
    for _, rod in ipairs(rods) do
        local rodName = self:GetItemName(rod.Id or rod.id)
        if rodName and string.lower(rodName):find("starter") then
            local uuid = rod.UUID or rod.Uuid or rod.uuid
            if uuid then
                logger:info("Found Starter Rod:", rodName, "UUID:", uuid)
                return uuid
            end
        end
    end
    
    logger:warn("Starter Rod not found")
    return nil
end

-- Get item name helper
function AutoInfEnchant:GetItemName(itemId)
    if not itemId then return nil end
    
    -- Use InventoryWatcher's resolve name method if available
    if inventoryWatcher and inventoryWatcher._resolveName then
        return inventoryWatcher:_resolveName("Fishing Rods", itemId)
    end
    
    return tostring(itemId)
end

-- Setup equipment (rod + bait)
function AutoInfEnchant:SetupEquipment()
    local success = true

    -- Equip Midnight Bait
    local baitSuccess = pcall(function()
        EquipBait:FireServer(CONFIG.midnightBaitId)
    end)
    
    if not baitSuccess then
        logger:error("Failed to equip Midnight Bait")
        success = false
    else
        logger:info("Midnight Bait equipped")
    end

    task.wait(0.5)

    -- Equip Starter Rod to hotbar
    local rodSuccess = pcall(function()
        EquipItem:FireServer(starterRodUUID, "Fishing Rods")
    end)
    
    if not rodSuccess then
        logger:error("Failed to equip Starter Rod")
        success = false
    else
        logger:info("Starter Rod equipped to hotbar")
    end

    task.wait(0.5)

    -- Equip tool from hotbar
    local toolSuccess = pcall(function()
        EquipTool:FireServer(CONFIG.rodHotbarSlot)
    end)
    
    if not toolSuccess then
        logger:error("Failed to equip tool from hotbar")
        success = false
    else
        logger:info("Tool equipped from hotbar slot", CONFIG.rodHotbarSlot)
    end

    return success
end

-- Setup rarity detection listener
function AutoInfEnchant:SetupRarityListener()
    rarityListener = ReplicateTextEffect.OnClientEvent:Connect(function(data)
        if not isRunning or not spamActive then return end
        
        -- Filter untuk LocalPlayer saja
        if data.Container ~= LocalPlayer.Character.Head then return end
        
        if data.TextData and data.TextData.EffectType == "Exclaim" then
            local color = data.TextData.TextColor.Keypoints[1].Value
            local colorKey = string.format("%.3f_%.3f_%.3f", color.R, color.G, color.B)
            local rarity = RARITY_COLORS[colorKey]
            
            if rarity then
                logger:info("Detected rarity:", rarity, "Color:", colorKey)
                
                if rarity == "Uncommon" or rarity == "Rare" then
                    -- Cancel fishing for unwanted rarity
                    logger:info("Canceling fishing for", rarity)
                    self:CancelFishing()
                else
                    logger:info("Continuing fishing for", rarity)
                end
            else
                -- Unknown rarity - assume Common, continue fishing
                logger:info("Unknown rarity detected, continuing. Color:", colorKey)
            end
        end
    end)
    
    logger:info("Rarity detection listener setup")
end

-- Setup fish obtained listener
function AutoInfEnchant:SetupFishObtainedListener()
    fishObtainedListener = ObtainedNewFishNotification.OnClientEvent:Connect(function(...)
        if not isRunning then return end
        
        logger:info("Fish caught successfully!")
        spamActive = false
        fishingInProgress = false
        
        -- Small delay before next cycle
        task.wait(0.5)
    end)
    
    logger:info("Fish obtained listener setup")
end

-- Main fishing loop - mimic AutoFish structure
function AutoInfEnchant:MainFishingLoop()
    if fishingInProgress or spamActive then return end
    
    local currentTime = tick()
    
    -- Small delay between cycles untuk stability
    if currentTime - (self.lastFishTime or 0) < 0.5 then
        return
    end
    
    -- Start fishing sequence
    fishingInProgress = true
    self.lastFishTime = currentTime
    
    spawn(function()
        local success = self:ExecuteFishingSequence()
        if not success then
            logger:warn("Fishing sequence failed, retrying...")
            task.wait(2)
        end
        fishingInProgress = false
    end)
end

-- Execute complete fishing sequence - step by step approach
function AutoInfEnchant:ExecuteFishingSequence()
    -- Step 1: Equip tool first (critical for fishing to work)
    if not self:EquipToolFromHotbar() then 
        logger:error("Failed to equip tool from hotbar")
        return false 
    end
    
    task.wait(0.2)

    -- Step 2: Charge rod
    if not self:ChargeRod() then 
        logger:error("Failed to charge rod")
        return false 
    end
    
    task.wait(0.2)
    
    -- Step 3: Cast rod
    if not self:CastRod() then 
        logger:error("Failed to cast rod")
        return false 
    end
    
    task.wait(0.2)
    
    -- Step 4: Start completion spam (will be interrupted by rarity listener)
    self:StartCompletionSpam()
    
    return true
end

-- Equip tool from hotbar (critical step yang missing)
function AutoInfEnchant:EquipToolFromHotbar()
    local success = pcall(function()
        EquipTool:FireServer(CONFIG.rodHotbarSlot)
    end)
    
    if success then
        logger:info("Tool equipped from hotbar slot", CONFIG.rodHotbarSlot)
    else
        logger:error("Failed to equip tool from hotbar")
    end
    
    return success
end

-- Charge fishing rod
function AutoInfEnchant:ChargeRod()
    local success = pcall(function()
        local chargeValue = tick() + (CONFIG.chargeTime * 1000)
        return ChargeFishingRod:InvokeServer(chargeValue)
    end)
    
    if success then
        logger:info("Rod charged")
    end
    
    return success
end

-- Cast fishing rod
function AutoInfEnchant:CastRod()
    local success = pcall(function()
        return RequestFishing:InvokeServer(CONFIG.castPosition.x, CONFIG.castPosition.z)
    end)
    
    if success then
        logger:info("Rod casted")
    end
    
    return success
end

-- Start spamming FishingCompleted - mimic AutoFish approach
function AutoInfEnchant:StartCompletionSpam()
    if spamActive then return end
    
    spamActive = true
    local spamStartTime = tick()
    
    logger:info("Starting completion spam")
    
    spawn(function()
        while spamActive and isRunning and (tick() - spamStartTime) < CONFIG.maxSpamTime do
            -- Fire completion
            pcall(function()
                FishingCompleted:FireServer()
            end)
            
            task.wait(CONFIG.spamDelay)
        end
        
        -- Timeout fallback
        if spamActive and (tick() - spamStartTime) >= CONFIG.maxSpamTime then
            logger:warn("Completion spam timeout")
            spamActive = false
            fishingInProgress = false
        end
    end)
end

-- Cancel fishing (for unwanted rarity)
function AutoInfEnchant:CancelFishing()
    spamActive = false
    
    local success = pcall(function()
        CancelFishingInputs:InvokeServer()
    end)
    
    if success then
        logger:info("Fishing canceled successfully")
    else
        logger:error("Failed to cancel fishing")
    end
    
    -- Reset state for next cycle
    fishingInProgress = false
    task.wait(1) -- Wait before next attempt
end

-- Get status
function AutoInfEnchant:GetStatus()
    return {
        running = isRunning,
        fishingInProgress = fishingInProgress,
        spamming = spamActive,
        starterRodFound = starterRodUUID ~= nil,
        listenersReady = rarityListener ~= nil and fishObtainedListener ~= nil
    }
end

-- Cleanup
function AutoInfEnchant:Cleanup()
    self:Stop()
    inventoryWatcher = nil
    starterRodUUID = nil
    logger:info("AutoInfEnchant cleaned up")
end

return AutoInfEnchant