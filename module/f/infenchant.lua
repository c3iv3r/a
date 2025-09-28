-- AutoInfEnchant Module - COMPLETE FIXED VERSION
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
    debug = function(self, ...) print("[DEBUG]", ...) end,
    info = function(self, ...) print("[INFO]", ...) end,
    warn = function(self, ...) print("[WARN]", ...) end,
    error = function(self, ...) print("[ERROR]", ...) end
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

-- Exact Color Values untuk rarity detection (berdasarkan contoh data)
local RARE_COLOR = {R = 0.33333334326744, G = 0.63529413938522, B = 1.0}
local UNCOMMON_COLOR = {R = 0.76470589637756, G = 1.0, B = 0.33333334326744}

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
local waitingForBite = false
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
    waitingForBite = false

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

-- FIXED: Setup rarity detection listener dengan proper filtering dan debugging
function AutoInfEnchant:SetupRarityListener()
    rarityListener = ReplicateTextEffect.OnClientEvent:Connect(function(data)
        -- DEBUG: Log semua ReplicateTextEffect events
        logger:info("=== ReplicateTextEffect Event Received ===")
        logger:info("Running:", isRunning, "WaitingForBite:", waitingForBite)
        
        if data then
            logger:info("Container:", data.Container and tostring(data.Container) or "nil")
            logger:info("Channel:", data.Channel or "nil")
            logger:info("UUID:", data.UUID or "nil")
            
            if data.TextData then
                logger:info("TextData.AttachTo:", data.TextData.AttachTo and tostring(data.TextData.AttachTo) or "nil")
                logger:info("TextData.Text:", data.TextData.Text or "nil")
                logger:info("TextData.EffectType:", data.TextData.EffectType or "nil")
            end
        end
        
        -- Early return jika tidak running atau tidak waiting for bite
        if not isRunning or not waitingForBite then 
            logger:info("Skipping - not running or not waiting for bite")
            return 
        end

        -- Validate data structure
        if not data or not data.TextData then
            logger:warn("Invalid data structure - missing TextData")
            return
        end

        -- STRICT Filter: LocalPlayer only
        local playerHead = LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("Head")
        if not playerHead then
            logger:warn("LocalPlayer head not found")
            return
        end

        -- Filter 1: Container must be LocalPlayer's head
        if data.Container ~= playerHead then 
            logger:info("Skipping - Container not LocalPlayer head")
            return 
        end

        -- Filter 2: TextData.AttachTo must also be LocalPlayer's head
        if data.TextData.AttachTo ~= playerHead then
            logger:info("Skipping - AttachTo not LocalPlayer head")
            return
        end

        -- Filter 3: Must be Exclaim effect type
        if data.TextData.EffectType ~= "Exclaim" then
            logger:info("Skipping - Not Exclaim effect")
            return
        end

        -- Filter 4: Text must be "!" (fish bite indicator)
        if data.TextData.Text ~= "!" then
            logger:info("Skipping - Text not '!'")
            return
        end

        logger:info("✓ VALID LocalPlayer bite detected - processing rarity...")

        -- Handle ColorSequence properly
        local textColor = data.TextData.TextColor
        local rarity = nil

        if textColor and textColor.Keypoints and #textColor.Keypoints > 0 then
            local color = textColor.Keypoints[1].Value
            
            -- EXACT color matching berdasarkan contoh data
            local colorR = color.R
            local colorG = color.G  
            local colorB = color.B
            
            logger:info("Raw Color Values - R:", colorR, "G:", colorG, "B:", colorB)
            
            -- Check for Rare (Blue): 0.33333334326744, 0.63529413938522, 1
            if math.abs(colorR - 0.33333334326744) < 0.001 and 
               math.abs(colorG - 0.63529413938522) < 0.001 and 
               math.abs(colorB - 1.0) < 0.001 then
                rarity = "Rare"
            -- Check for Uncommon (Green): 0.76470589637756, 1, 0.33333334326744  
            elseif math.abs(colorR - 0.76470589637756) < 0.001 and
                   math.abs(colorG - 1.0) < 0.001 and
                   math.abs(colorB - 0.33333334326744) < 0.001 then
                rarity = "Uncommon"
            end
            
            logger:info("Detected Rarity:", rarity or "Unknown/Other")
        else
            logger:warn("Invalid ColorSequence structure")
        end

        -- DECISION LOGIC: Stop waiting dan make decision
        waitingForBite = false
        
        if rarity and (rarity == "Rare" or rarity == "Uncommon") then
            logger:info("🚫 Detected", rarity, "- CANCELING fishing")
            spawn(function()
                self:CancelFishing()
            end)
        else
            logger:info("✅ Detected", rarity or "Unknown", "- CONTINUING fishing (spam completion)")
            spawn(function()
                -- Small delay untuk ensure minigame ready
                task.wait(0.2)
                self:StartCompletionSpam()
            end)
        end
    end)

    logger:info("Rarity detection listener setup with enhanced debugging")
end

-- FIXED: Setup fish obtained listener dengan proper state reset
function AutoInfEnchant:SetupFishObtainedListener()
    fishObtainedListener = ObtainedNewFishNotification.OnClientEvent:Connect(function(...)
        if not isRunning then return end

        logger:info("Fish caught successfully!")

        -- Complete state reset setelah fish obtained
        spamActive = false
        waitingForBite = false
        fishingInProgress = false

        -- Delay sebelum next cycle
        spawn(function()
            task.wait(2.5) -- Slightly longer delay
            logger:info("Fish obtained - ready for next fishing cycle")
        end)
    end)

    logger:info("Fish obtained listener setup with proper state reset")
end

-- FIXED: Main fishing loop dengan better state checking
function AutoInfEnchant:MainFishingLoop()
    -- Comprehensive state checking
    if fishingInProgress or spamActive or waitingForBite then 
        return 
    end

    local currentTime = tick()

    -- Increased delay between cycles untuk stability
    if currentTime - (self.lastFishTime or 0) < 3.0 then
        return
    end

    -- Start new fishing sequence
    fishingInProgress = true
    self.lastFishTime = currentTime

    logger:info("=== Starting new fishing cycle ===")

    spawn(function()
        local success = self:ExecuteFishingSequence()
        if not success then
            logger:error("Fishing sequence failed - resetting states")
            fishingInProgress = false
            waitingForBite = false
            spamActive = false
            task.wait(3) -- Longer wait on failure
        end
    end)
end

-- FIXED: Execute fishing sequence dengan better error handling
function AutoInfEnchant:ExecuteFishingSequence()
    -- Step 1: Equip tool
    if not self:EquipToolFromHotbar() then 
        logger:error("Failed to equip tool from hotbar")
        return false 
    end
    task.wait(0.3)

    -- Step 2: Charge rod
    if not self:ChargeRod() then 
        logger:error("Failed to charge rod")
        return false 
    end
    task.wait(0.3)

    -- Step 3: Cast rod
    if not self:CastRod() then 
        logger:error("Failed to cast rod")
        return false 
    end
    task.wait(0.5) -- Slightly longer wait after cast

    -- Step 4: Wait for bite detection
    waitingForBite = true
    logger:info("Waiting for fish bite (ReplicateTextEffect)...")

    -- Timeout fallback dengan better cleanup
    spawn(function()
        task.wait(CONFIG.maxSpamTime + 5) -- Extra timeout buffer
        if waitingForBite then
            logger:warn("Bite detection timeout - resetting all states")
            waitingForBite = false
            fishingInProgress = false
            spamActive = false
            task.wait(2)
        end
    end)

    return true
end

-- Equip tool from hotbar
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

-- FIXED: Completion spam dengan proper state management
function AutoInfEnchant:StartCompletionSpam()
    if spamActive then 
        logger:warn("Completion spam already active")
        return 
    end

    spamActive = true
    local spamStartTime = tick()

    logger:info("Starting completion spam until fish obtained")

    spawn(function()
        while spamActive and isRunning and (tick() - spamStartTime) < CONFIG.maxSpamTime do
            local success = pcall(function()
                FishingCompleted:FireServer()
            end)

            if not success then
                logger:warn("Failed to fire FishingCompleted")
            end

            task.wait(CONFIG.spamDelay)
        end

        -- Timeout fallback
        if spamActive and (tick() - spamStartTime) >= CONFIG.maxSpamTime then
            logger:warn("Completion spam timeout - forcing reset")
            spamActive = false
            fishingInProgress = false
            waitingForBite = false
            
            -- Force next cycle after timeout
            task.wait(2)
        end
    end)
end

-- FIXED: Cancel fishing dengan proper state reset
function AutoInfEnchant:CancelFishing()
    spamActive = false
    waitingForBite = false

    logger:info("Preparing to cancel fishing for Rare/Uncommon...")

    -- Keep original 0.5s wait sebelum cancel
    task.wait(0.5)

    local success = pcall(function()
        return CancelFishingInputs:InvokeServer()
    end)

    if success then
        logger:info("Fishing canceled successfully (Rare/Uncommon)")
    else
        logger:error("Failed to cancel fishing")
    end

    -- Complete state reset
    fishingInProgress = false
    spamActive = false
    waitingForBite = false

    -- Wait before next cycle
    task.wait(2)
    logger:info("Cancel completed - ready for next fishing cycle")
end

-- FIXED: Enhanced status reporting
function AutoInfEnchant:GetStatus()
    return {
        running = isRunning,
        fishingInProgress = fishingInProgress,
        spamming = spamActive,
        waitingForBite = waitingForBite,
        starterRodFound = starterRodUUID ~= nil,
        listenersReady = rarityListener ~= nil and fishObtainedListener ~= nil,
        lastFishTime = self.lastFishTime or 0,
        timeSinceLastFish = tick() - (self.lastFishTime or 0)
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