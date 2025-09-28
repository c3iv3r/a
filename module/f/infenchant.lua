-- AutoInfEnchant Module - Rewritten & Fixed
local AutoInfEnchant = {}
AutoInfEnchant.__index = AutoInfEnchant

-- Services
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local LocalPlayer = Players.LocalPlayer

-- Logger
local logger = _G.Logger and _G.Logger.new("AutoInfEnchant") or {
    debug = function(self, ...) print("[DEBUG]", ...) end,
    info = function(self, ...) print("[INFO]", ...) end,
    warn = function(self, ...) print("[WARN]", ...) end,
    error = function(self, ...) print("[ERROR]", ...) end
}

-- Load InventoryWatcher
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

-- Rarity Color Mapping (RGB values to rarity name)
local RARITY_COLORS = {
    ["0.765,1,0.333"] = "Uncommon",
    ["0.333,0.635,1"] = "Rare",
    ["0.76470589637756,1,0.33333334326744"] = "Uncommon",
    ["0.33333334326744,0.63529413938522,1"] = "Rare"
}

-- Configuration
local CONFIG = {
    teleportLocation = CFrame.new(3247, -1302, 1376),
    midnightBaitId = 3,
    rodHotbarSlot = 1,
    chargeTime = 1.0,
    castPosition = {x = -1.233184814453125, z = 0.9999120558411321},
    spamDelay = 0.05,
    maxSpamTime = 30,
    cycleDelay = 1.5
}

-- State Variables
local isRunning = false
local isFishing = false
local isSpamming = false
local waitingForBite = false
local inventoryWatcher = nil
local starterRodUUID = nil
local lastCycleTime = 0

-- Connections
local textEffectConnection = nil
local fishObtainedConnection = nil
local mainLoopConnection = nil

-- Create new instance
function AutoInfEnchant.new()
    local self = setmetatable({}, AutoInfEnchant)
    return self
end

-- Initialize module
function AutoInfEnchant:Init()
    if not InventoryWatcher then
        logger:error("InventoryWatcher failed to load")
        return false
    end

    local success, err = pcall(function()
        inventoryWatcher = InventoryWatcher.new()
    end)

    if not success or not inventoryWatcher then
        logger:error("Failed to create InventoryWatcher:", err or "nil instance")
        return false
    end

    logger:info("AutoInfEnchant initialized successfully")
    return true
end

-- Start the auto enchant process
function AutoInfEnchant:Start()
    if isRunning then
        logger:warn("Already running")
        return false
    end

    if not inventoryWatcher then
        logger:error("InventoryWatcher not initialized")
        return false
    end

    inventoryWatcher:onReady(function()
        self:StartProcess()
    end)

    return true
end

-- Internal start process
function AutoInfEnchant:StartProcess()
    -- Step 1: Teleport
    if not self:Teleport() then
        logger:error("Teleport failed")
        return
    end

    -- Step 2: Find Starter Rod
    starterRodUUID = self:FindStarterRod()
    if not starterRodUUID then
        logger:error("Starter Rod not found")
        return
    end

    -- Step 3: Setup equipment
    if not self:SetupEquipment() then
        logger:error("Equipment setup failed")
        return
    end

    -- Step 4: Setup listeners
    self:SetupListeners()

    -- Step 5: Start main loop
    isRunning = true
    mainLoopConnection = RunService.Heartbeat:Connect(function()
        self:MainLoop()
    end)

    logger:info("AutoInfEnchant started successfully")
end

-- Stop the process
function AutoInfEnchant:Stop()
    if not isRunning then return end

    isRunning = false
    isFishing = false
    isSpamming = false
    waitingForBite = false

    -- Disconnect all connections
    if textEffectConnection then textEffectConnection:Disconnect() end
    if fishObtainedConnection then fishObtainedConnection:Disconnect() end
    if mainLoopConnection then mainLoopConnection:Disconnect() end

    logger:info("AutoInfEnchant stopped")
end

-- Teleport to fishing location
function AutoInfEnchant:Teleport()
    local success = pcall(function()
        LocalPlayer.Character.HumanoidRootPart.CFrame = CONFIG.teleportLocation
    end)

    if success then
        task.wait(1)
        logger:info("Teleported to fishing location")
    end

    return success
end

-- Find Starter Rod UUID
function AutoInfEnchant:FindStarterRod()
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

    return nil
end

-- Get item name helper
function AutoInfEnchant:GetItemName(itemId)
    if not itemId then return nil end
    if inventoryWatcher and inventoryWatcher._resolveName then
        return inventoryWatcher:_resolveName("Fishing Rods", itemId)
    end
    return tostring(itemId)
end

-- Setup equipment (rod + bait)
function AutoInfEnchant:SetupEquipment()
    -- Equip Midnight Bait
    local success1 = pcall(function()
        EquipBait:FireServer(CONFIG.midnightBaitId)
    end)

    task.wait(0.5)

    -- Equip Starter Rod to hotbar
    local success2 = pcall(function()
        EquipItem:FireServer(starterRodUUID, "Fishing Rods")
    end)

    task.wait(0.5)

    -- Equip tool from hotbar
    local success3 = pcall(function()
        EquipTool:FireServer(CONFIG.rodHotbarSlot)
    end)

    if success1 and success2 and success3 then
        logger:info("Equipment setup complete")
        return true
    else
        logger:error("Equipment setup failed")
        return false
    end
end

-- Setup event listeners
function AutoInfEnchant:SetupListeners()
    -- Text effect listener (for bite detection)
    textEffectConnection = ReplicateTextEffect.OnClientEvent:Connect(function(data)
        if not isRunning or not waitingForBite then return end

        -- Filter: Must be LocalPlayer's head
        if not data.Container or data.Container ~= LocalPlayer.Character.Head then
            return
        end

        -- Filter: Must be Exclaim effect with "!" text
        if not data.TextData or data.TextData.EffectType ~= "Exclaim" or data.TextData.Text ~= "!" then
            return
        end

        -- Filter: Must be attached to LocalPlayer's head
        if not data.TextData.AttachTo or data.TextData.AttachTo ~= LocalPlayer.Character.Head then
            return
        end

        local rarity = self:GetRarityFromColor(data.TextData.TextColor)
        logger:info("Fish bite detected! Rarity:", rarity or "Unknown")

        waitingForBite = false
        isFishing = false

        if rarity == "Uncommon" or rarity == "Rare" then
            -- Cancel for Uncommon/Rare
            logger:info("Canceling for", rarity)
            spawn(function()
                self:CancelFishing()
            end)
        else
            -- Spam completion for others
            logger:info("Spamming completion for", rarity or "Unknown")
            spawn(function()
                self:SpamCompletion()
            end)
        end
    end)

    -- Fish obtained listener
    fishObtainedConnection = ObtainedNewFishNotification.OnClientEvent:Connect(function()
        if not isRunning then return end

        logger:info("Fish obtained!")
        isSpamming = false
        isFishing = false
        lastCycleTime = tick()
    end)

    logger:info("Event listeners setup complete")
end

-- Get rarity from color
function AutoInfEnchant:GetRarityFromColor(textColor)
    if not textColor or not textColor.Keypoints or #textColor.Keypoints == 0 then
        return nil
    end

    local color = textColor.Keypoints[1].Value
    local colorKey1 = string.format("%.3f,%.0f,%.3f", color.R, color.G, color.B)
    local colorKey2 = string.format("%g,%g,%g", color.R, color.G, color.B)

    return RARITY_COLORS[colorKey1] or RARITY_COLORS[colorKey2]
end

-- Main loop
function AutoInfEnchant:MainLoop()
    if isFishing or isSpamming or waitingForBite then return end

    local currentTime = tick()
    if currentTime - lastCycleTime < CONFIG.cycleDelay then
        return
    end

    -- Start new fishing cycle
    spawn(function()
        self:StartFishing()
    end)
end

-- Start fishing sequence
function AutoInfEnchant:StartFishing()
    if isFishing or waitingForBite then return end
    
    isFishing = true
    logger:info("Starting fishing cycle")

    -- Equip tool
    pcall(function()
        EquipTool:FireServer(CONFIG.rodHotbarSlot)
    end)
    task.wait(0.3)

    -- Charge rod
    pcall(function()
        local chargeValue = tick() + (CONFIG.chargeTime * 1000)
        ChargeFishingRod:InvokeServer(chargeValue)
    end)
    task.wait(0.3)

    -- Cast rod
    local success = pcall(function()
        return RequestFishing:InvokeServer(CONFIG.castPosition.x, CONFIG.castPosition.z)
    end)

    if success then
        isFishing = false
        waitingForBite = true
        logger:info("Rod casted, waiting for bite...")
        
        -- Timeout for bite detection
        spawn(function()
            task.wait(CONFIG.maxSpamTime)
            if waitingForBite then
                logger:warn("Bite timeout, restarting cycle")
                waitingForBite = false
                lastCycleTime = tick()
            end
        end)
    else
        logger:error("Failed to cast rod")
        isFishing = false
        lastCycleTime = tick()
    end
end

-- Cancel fishing
function AutoInfEnchant:CancelFishing()
    task.wait(0.5) -- Small delay before cancel
    
    local success = pcall(function()
        return CancelFishingInputs:InvokeServer()
    end)

    if success then
        logger:info("Fishing canceled successfully")
    else
        logger:error("Failed to cancel fishing")
    end

    waitingForBite = false
    isFishing = false
    lastCycleTime = tick()
end

-- Spam completion
function AutoInfEnchant:SpamCompletion()
    if isSpamming then return end
    
    isSpamming = true
    local spamStartTime = tick()

    while isSpamming and isRunning and (tick() - spamStartTime) < CONFIG.maxSpamTime do
        pcall(function()
            FishingCompleted:FireServer()
        end)
        task.wait(CONFIG.spamDelay)
    end

    -- Timeout fallback
    if isSpamming then
        logger:warn("Spam timeout, restarting cycle")
        isSpamming = false
        isFishing = false
        lastCycleTime = tick()
    end
end

-- Get status
function AutoInfEnchant:GetStatus()
    return {
        running = isRunning,
        fishing = isFishing,
        spamming = isSpamming,
        waitingForBite = waitingForBite,
        starterRodFound = starterRodUUID ~= nil
    }
end

-- Cleanup
function AutoInfEnchant:Cleanup()
    self:Stop()
    inventoryWatcher = nil
    starterRodUUID = nil
end

return AutoInfEnchant