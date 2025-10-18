--- AutoSendTrade.lua - PATCHED Version with FishWatcher & EnchantStoneWatcher
local AutoSendTrade = {}
AutoSendTrade.__index = AutoSendTrade

local logger = _G.Logger and _G.Logger.new("AutoSendTrade") or {
    debug = function() end,
    info = function() end,
    warn = function() end,
    error = function() end
}

-- Services
local RS = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Players = game:GetService("Players")

-- Dependencies - UPDATED to use separate watchers
local FishWatcher = _G.FishWatcher or loadstring(game:HttpGet("https://raw.githubusercontent.com/your-repo/fish_watcher.lua"))()
local EnchantStoneWatcher = _G.EnchantStoneWatcher or loadstring(game:HttpGet("https://raw.githubusercontent.com/your-repo/enchantstone_watcher.lua"))()

-- State
local running = false
local hbConn = nil
local fishWatcher = nil
local itemWatcher = nil

-- Configuration
local selectedFishNames = {} -- set: { ["Fish Name"] = true }
local selectedItemNames = {} -- set: { ["Item Name"] = true }
local selectedPlayers = {} -- set: { [playerName] = true }
local TRADE_DELAY = 5.0

-- Tracking
local tradeQueue = {}
local pendingTrade = nil
local lastTradeTime = 0
local isProcessing = false
local totalTradesSent = 0

-- Remotes
local tradeRemote = nil
local textNotificationRemote = nil

-- Cache for fish names and item names
local fishNamesCache = {}
local itemNamesCache = {}
local inventoryCache = {} -- Cache for user inventory

-- === Helper Functions ===

-- Get fish names dari Items module
local function getFishNames()
    if next(fishNamesCache) then return fishNamesCache end
    
    local itemsModule = RS:FindFirstChild("Items")
    if not itemsModule then
        logger:warn("Items module not found")
        return {}
    end
    
    local fishNames = {}
    for _, item in pairs(itemsModule:GetChildren()) do
        if item:IsA("ModuleScript") then
            local success, moduleData = pcall(function()
                return require(item)
            end)
            
            if success and moduleData then
                if moduleData.Data and moduleData.Data.Type == "Fishes" then
                    if moduleData.Data.Name then
                        table.insert(fishNames, moduleData.Data.Name)
                    end
                end
            end
        end
    end
    
    table.sort(fishNames)
    fishNamesCache = fishNames
    return fishNames
end

-- Get enchant stones names dari Items module
local function getItemNames()
    if next(itemNamesCache) then return itemNamesCache end
    
    local itemsModule = RS:FindFirstChild("Items")
    if not itemsModule then
        logger:warn("Items module not found")
        return {}
    end
    
    local itemNames = {}
    for _, item in pairs(itemsModule:GetChildren()) do
        if item:IsA("ModuleScript") then
            local success, moduleData = pcall(function()
                return require(item)
            end)
            
            if success and moduleData then
                if moduleData.Data and moduleData.Data.Type == "EnchantStones" then
                    if moduleData.Data.Name then
                        table.insert(itemNames, moduleData.Data.Name)
                    end
                end
            end
        end
    end
    
    table.sort(itemNames)
    itemNamesCache = itemNames
    return itemNames
end

-- UPDATED: Scan and cache inventory using new watchers
local function scanAndCacheInventory()
    if not fishWatcher or not fishWatcher._ready then
        logger:info("FishWatcher not ready, retrying in 1 second...")
        task.wait(1)
        return scanAndCacheInventory()
    end
    
    if not itemWatcher or not itemWatcher._ready then
        logger:info("EnchantStoneWatcher not ready, retrying in 1 second...")
        task.wait(1)
        return scanAndCacheInventory()
    end
    
    inventoryCache = {
        fishes = {},
        items = {}
    }
    
    -- Scan fishes using FishWatcher
    local allFishes = fishWatcher:getAllFishes()
    for _, fishData in ipairs(allFishes) do
        if fishData.uuid and not fishData.favorited then -- Skip favorited fish
            table.insert(inventoryCache.fishes, {
                uuid = fishData.uuid,
                name = fishData.name,
                id = fishData.id,
                metadata = fishData.metadata,
                entry = fishData.entry
            })
        end
    end
    
    -- Scan items using EnchantStoneWatcher
    local allStones = itemWatcher:getAllStones()
    for _, stoneData in ipairs(allStones) do
        if stoneData.uuid and not stoneData.favorited then -- Skip favorited stones
            table.insert(inventoryCache.items, {
                uuid = stoneData.uuid,
                name = stoneData.name,
                id = stoneData.id,
                entry = stoneData.entry
            })
        end
    end
    
    logger:info("Inventory cached:", #inventoryCache.fishes, "fishes,", #inventoryCache.items, "items")
end

local function findRemotes()
    local success1, remote1 = pcall(function()
        return RS:WaitForChild("Packages", 5)
                  :WaitForChild("_Index", 5)
                  :WaitForChild("sleitnick_net@0.2.0", 5)
                  :WaitForChild("net", 5)
                  :WaitForChild("RF/InitiateTrade", 5)
    end)
    
    if success1 and remote1 then
        tradeRemote = remote1
        logger:info("Trade remote found successfully")
    else
        logger:warn("Failed to find InitiateTrade remote")
        return false
    end
    
    -- Text notification remote (optional)
    pcall(function()
        textNotificationRemote = RS:WaitForChild("Packages", 5)
                                   :WaitForChild("_Index", 5)
                                   :WaitForChild("sleitnick_net@0.2.0", 5)
                                   :WaitForChild("net", 5)
                                   :WaitForChild("RE/TextNotification", 5)
        logger:info("Text notification remote found")
    end)
    
    return true
end

local function shouldTradeFish(fishEntry)
    if not fishEntry then return false end
    local fishName = fishEntry.name
    return selectedFishNames[fishName] == true
end

local function shouldTradeItem(itemEntry)
    if not itemEntry then return false end
    local itemName = itemEntry.name
    return selectedItemNames[itemName] == true
end

local function getRandomTargetPlayerId()
    local availablePlayers = {}
    
    for _, player in ipairs(Players:GetPlayers()) do
        if player ~= Players.LocalPlayer and selectedPlayers[player.Name] then
            table.insert(availablePlayers, player.UserId)
        end
    end
    
    if #availablePlayers > 0 then
        return availablePlayers[math.random(1, #availablePlayers)]
    end
    
    return nil
end

local function sendTradeRequest(playerId, uuid, itemName)
    if not tradeRemote or not uuid or not playerId then 
        logger:warn("Missing parameters:", "tradeRemote:", tradeRemote ~= nil, "uuid:", uuid, "playerId:", playerId)
        return false 
    end
    
    local success, result = pcall(function()
        return tradeRemote:InvokeServer(playerId, uuid)
    end)
    
    if success then
        logger:info("✅ Sent trade request:", itemName, "UUID:", uuid, "to player ID:", playerId)
        totalTradesSent = totalTradesSent + 1
        return true
    else
        logger:warn("❌ Failed to send trade request:", result)
        return false
    end
end

-- UPDATED: Scan using new watchers
local function scanForTradableItems()
    if not fishWatcher or not fishWatcher._ready or not itemWatcher or not itemWatcher._ready or isProcessing or pendingTrade then 
        return 
    end
    
    -- Check if we have targets
    local hasTargets = false
    for _ in pairs(selectedPlayers) do
        hasTargets = true
        break
    end
    if not hasTargets then return end
    
    -- Clear old queue
    tradeQueue = {}
    
    -- Refresh inventory cache
    scanAndCacheInventory()
    
    -- Scan cached fishes
    for _, fishEntry in ipairs(inventoryCache.fishes) do
        if fishEntry.uuid and not fishWatcher:isFavoritedByUUID(fishEntry.uuid) then
            if shouldTradeFish(fishEntry) then
                table.insert(tradeQueue, {
                    uuid = fishEntry.uuid,
                    name = fishEntry.name,
                    category = "Fishes",
                    metadata = fishEntry.metadata
                })
            end
        end
    end
    
    -- Scan cached items
    for _, itemEntry in ipairs(inventoryCache.items) do
        if itemEntry.uuid and not itemWatcher:isFavoritedByUUID(itemEntry.uuid) then
            if shouldTradeItem(itemEntry) then
                table.insert(tradeQueue, {
                    uuid = itemEntry.uuid,
                    name = itemEntry.name,
                    category = "Items"
                })
            end
        end
    end
    
    if #tradeQueue > 0 then
        logger:info("Found", #tradeQueue, "tradable items in queue")
    end
end

-- UPDATED: Verify item existence using new watchers
local function processTradeQueue()
    if not running or #tradeQueue == 0 or isProcessing or pendingTrade then 
        return 
    end
    
    local currentTime = tick()
    if currentTime - lastTradeTime < TRADE_DELAY then return end
    
    isProcessing = true
    
    -- Get next item
    local nextItem = table.remove(tradeQueue, 1)
    if not nextItem then
        isProcessing = false
        return
    end
    
    -- Double-check item still exists and not favorited using new watchers
    local itemExists = false
    if nextItem.category == "Fishes" then
        local fishData = fishWatcher:getFishByUUID(nextItem.uuid)
        if fishData and not fishData.favorited then
            itemExists = true
        end
    else
        local stoneData = itemWatcher:getStoneByUUID(nextItem.uuid)
        if stoneData and not stoneData.favorited then
            itemExists = true
        end
    end
    
    if not itemExists then
        logger:info("Item no longer available:", nextItem.name)
        isProcessing = false
        return
    end
    
    -- Send trade
    local targetPlayerId = getRandomTargetPlayerId()
    if targetPlayerId then
        local success = sendTradeRequest(targetPlayerId, nextItem.uuid, nextItem.name)
        
        if success then
            pendingTrade = {
                item = nextItem,
                timestamp = currentTime,
                targetPlayerId = targetPlayerId
            }
            lastTradeTime = currentTime
        end
    else
        logger:info("No target players available")
    end
    
    isProcessing = false
end

local function setupNotificationListener()
    if not textNotificationRemote then return end
    
    textNotificationRemote.OnClientEvent:Connect(function(data)
        if data and data.Text then
            if string.find(data.Text, "Trade completed") or 
               string.find(data.Text, "Trade cancelled") or
               string.find(data.Text, "Trade expired") or
               string.find(data.Text, "Trade declined") then
                -- Clear pending trade so we can send next one
                if pendingTrade then
                    logger:info("Trade finished:", data.Text, "- Item:", pendingTrade.item.name)
                    pendingTrade = nil
                end
            elseif string.find(data.Text, "Sent trade request") then
                logger:info("Trade request acknowledged by server")
            end
        end
    end)
end

local function mainLoop()
    if not running then return end
    
    scanForTradableItems()
    processTradeQueue()
end

-- === Interface Methods ===

function AutoSendTrade:Init(guiControls)
    logger:info("Initializing...")
    
    -- Find remotes
    if not findRemotes() then
        return false
    end
    
    -- UPDATED: Initialize separate watchers
    fishWatcher = FishWatcher.getShared()
    itemWatcher = EnchantStoneWatcher.getShared()
    
    -- Wait for both watchers to be ready
    fishWatcher:onReady(function()
        logger:info("FishWatcher ready")
        if itemWatcher._ready then
            scanAndCacheInventory()
        end
    end)
    
    itemWatcher:onReady(function()
        logger:info("EnchantStoneWatcher ready")
        if fishWatcher._ready then
            scanAndCacheInventory()
        end
    end)
    
    -- Setup notification listener
    setupNotificationListener()
    
    -- Populate GUI dropdown jika diberikan
    if guiControls then
        -- Fish dropdown
        if guiControls.itemDropdown then
            local fishNames = getFishNames()
            pcall(function()
                guiControls.itemDropdown:Reload(fishNames)
            end)
        end
        
        -- Items dropdown
        if guiControls.itemsDropdown then
            local itemNames = getItemNames()
            pcall(function()
                guiControls.itemsDropdown:Reload(itemNames)
            end)
        end
    end
    
    logger:info("Initialization complete")
    return true
end

function AutoSendTrade:Start(config)
    if running then 
        logger:info("Already running!")
        return 
    end
    
    -- Apply config if provided
    if config then
        if config.fishNames then
            self:SetSelectedFish(config.fishNames)
        end
        if config.itemNames then
            self:SetSelectedItems(config.itemNames)
        end
        if config.playerList then
            self:SetSelectedPlayers(config.playerList)
        end
        if config.tradeDelay then
            self:SetTradeDelay(config.tradeDelay)
        end
    end
    
    running = true
    isProcessing = false
    pendingTrade = nil
    totalTradesSent = 0
    
    -- Start main loop
    hbConn = RunService.Heartbeat:Connect(function()
        local success, err = pcall(mainLoop)
        if not success then
            logger:warn("Error in main loop:", err)
        end
    end)
    
    logger:info("Started with delay:", TRADE_DELAY, "seconds")
end

function AutoSendTrade:Stop()
    if not running then 
        logger:info("Not running!")
        return 
    end
    
    running = false
    isProcessing = false
    
    -- Disconnect heartbeat
    if hbConn then
        hbConn:Disconnect()
        hbConn = nil
    end
    
    -- Clear queues
    table.clear(tradeQueue)
    pendingTrade = nil
    
    logger:info("Stopped. Total trades sent:", totalTradesSent)
end

function AutoSendTrade:Cleanup()
    self:Stop()
    
    -- UPDATED: Clean up separate watchers (don't destroy shared instances)
    fishWatcher = nil
    itemWatcher = nil
    
    -- Clear all data
    table.clear(selectedFishNames)
    table.clear(selectedItemNames)
    table.clear(selectedPlayers)
    table.clear(tradeQueue)
    table.clear(fishNamesCache)
    table.clear(itemNamesCache)
    table.clear(inventoryCache)
    
    tradeRemote = nil
    textNotificationRemote = nil
    lastTradeTime = 0
    pendingTrade = nil
    totalTradesSent = 0
    
    logger:info("Cleaned up")
end

-- === Configuration Methods ===

function AutoSendTrade:SetSelectedFish(fishNames)
    if not fishNames then return false end
    
    table.clear(selectedFishNames)
    
    if type(fishNames) == "table" then
        if #fishNames > 0 then
            for _, fishName in ipairs(fishNames) do
                if type(fishName) == "string" then
                    selectedFishNames[fishName] = true
                end
            end
        else
            for fishName, enabled in pairs(fishNames) do
                if enabled and type(fishName) == "string" then
                    selectedFishNames[fishName] = true
                end
            end
        end
    end
    
    logger:info("Selected fish:", selectedFishNames)
    return true
end

function AutoSendTrade:SetSelectedItems(itemNames)
    if not itemNames then return false end
    
    table.clear(selectedItemNames)
    
    if type(itemNames) == "table" then
        if #itemNames > 0 then
            for _, itemName in ipairs(itemNames) do
                if type(itemName) == "string" then
                    selectedItemNames[itemName] = true
                end
            end
        else
            for itemName, enabled in pairs(itemNames) do
                if enabled and type(itemName) == "string" then
                    selectedItemNames[itemName] = true
                end
            end
        end
    end
    
    logger:info("Selected items:", selectedItemNames)
    return true
end

function AutoSendTrade:SetSelectedPlayers(playerNames)
    if not playerNames then return false end
    
    table.clear(selectedPlayers)
    
    if type(playerNames) == "table" then
        if #playerNames > 0 then
            for _, playerName in ipairs(playerNames) do
                if type(playerName) == "string" and playerName ~= "" then
                    selectedPlayers[playerName] = true
                end
            end
        else
            for playerName, enabled in pairs(playerNames) do
                if enabled and type(playerName) == "string" and playerName ~= "" then
                    selectedPlayers[playerName] = true
                end
            end
        end
    end
    
    logger:info("Selected players:", selectedPlayers)
    return true
end

function AutoSendTrade:SetTradeDelay(delay)
    if type(delay) == "number" and delay >= 1.0 then
        TRADE_DELAY = delay
        logger:info("Trade delay set to:", delay)
        return true
    end
    return false
end

-- === Getter Methods ===

function AutoSendTrade:GetAvailableFish()
    return getFishNames()
end

function AutoSendTrade:GetAvailableItems()
    return getItemNames()
end

-- UPDATED: Use new watchers for inventory
function AutoSendTrade:GetCachedFishInventory()
    local fishes = {}
    for _, fish in ipairs(inventoryCache.fishes or {}) do
        table.insert(fishes, {
            name = fish.name,
            uuid = fish.uuid,
            favorited = fishWatcher and fishWatcher:isFavoritedByUUID(fish.uuid) or false
        })
    end
    return fishes
end

function AutoSendTrade:GetCachedItemInventory()
    local items = {}
    for _, item in ipairs(inventoryCache.items or {}) do
        table.insert(items, {
            name = item.name,
            uuid = item.uuid,
            favorited = itemWatcher and itemWatcher:isFavoritedByUUID(item.uuid) or false
        })
    end
    return items
end

function AutoSendTrade:GetOnlinePlayers()
    local players = {}
    for _, player in ipairs(Players:GetPlayers()) do
        if player ~= Players.LocalPlayer then
            table.insert(players, player.Name)
        end
    end
    return players
end

function AutoSendTrade:GetSelectedFish()
    local selected = {}
    for fishName, enabled in pairs(selectedFishNames) do
        if enabled then
            table.insert(selected, fishName)
        end
    end
    return selected
end

function AutoSendTrade:GetSelectedItems()
    local selected = {}
    for itemName, enabled in pairs(selectedItemNames) do
        if enabled then
            table.insert(selected, itemName)
        end
    end
    return selected
end

function AutoSendTrade:GetSelectedPlayers()
    local selected = {}
    for playerName, enabled in pairs(selectedPlayers) do
        if enabled then
            table.insert(selected, playerName)
        end
    end
    return selected
end

function AutoSendTrade:GetStatus()
    return {
        isRunning = running,
        selectedFishCount = table.count(selectedFishNames),
        selectedItemCount = table.count(selectedItemNames),
        selectedPlayerCount = table.count(selectedPlayers),
        queueLength = #tradeQueue,
        hasPendingTrade = pendingTrade ~= nil,
        totalTradesSent = totalTradesSent,
        tradeDelay = TRADE_DELAY,
        isProcessing = isProcessing,
        inventoryCacheSize = (inventoryCache and (#inventoryCache.fishes + #inventoryCache.items)) or 0
    }
end

function AutoSendTrade:GetQueueSize()
    return #tradeQueue
end

function AutoSendTrade:IsRunning()
    return running
end

-- === Debug Methods ===

function AutoSendTrade:DumpStatus()
    local status = self:GetStatus()
    logger:info("=== AutoSendTrade Status ===")
    for k, v in pairs(status) do
        logger:info(k .. ":", v)
    end
    logger:info("Selected Fish:", self:GetSelectedFish())
    logger:info("Selected Items:", self:GetSelectedItems())
    logger:info("Selected Players:", self:GetSelectedPlayers())
    if pendingTrade then
        logger:info("Pending Trade:", pendingTrade.item.name, "to player", pendingTrade.targetPlayerId)
    end
end

function AutoSendTrade:DumpQueue()
    logger:info("=== Trade Queue ===")
    for i, item in ipairs(tradeQueue) do
        logger:info(i, item.name, item.category, item.uuid)
    end
    logger:info("Queue length:", #tradeQueue)
end

function AutoSendTrade:DumpInventoryCache()
    logger:info("=== Inventory Cache ===")
    logger:info("Fishes:", #(inventoryCache.fishes or {}))
    logger:info("Items:", #(inventoryCache.items or {}))
end

function AutoSendTrade:RefreshInventory()
    scanAndCacheInventory()
    return true
end

return AutoSendTrade