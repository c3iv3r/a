-- Auto Buy Merchant Feature (Fixed Version)
-- File: autobuymerchant.lua
local autobuymerchantFeature = {}
autobuymerchantFeature.__index = autobuymerchantFeature

local logger = _G.Logger and _G.Logger.new("AutoBuyMerchant") or {
    debug = function() end,
    info = function() end,
    warn = function() end,
    error = function() end
}

--// Services
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

--// Short refs
local LocalPlayer = Players.LocalPlayer

--// Modules
local Replion = require(ReplicatedStorage.Packages.Replion)
local MarketItemData = require(ReplicatedStorage.Shared.MarketItemData)

--// Remote (Direct path)
local PurchaseRemote = ReplicatedStorage.Packages._Index["sleitnick_net@0.2.0"].net["RF/PurchaseMarketItem"]

--// State
local inited = false
local running = false
local config = {}

-- Market & Inventory trackers
local merchantReplion = nil
local inventoryWatcher = nil
local connections = {}

-- Purchase state
local purchasing = false
local purchaseQueue = {}

-- Market lookup table
local marketLookup = {}

-- === Helper Functions ===
local function createMarketLookup()
    local lookup = {}
    for _, item in ipairs(MarketItemData) do
        lookup[item.Id] = item
    end
    return lookup
end

local function loadInventoryWatcher()
    -- Load InventoryWatcher via loadstring
    local inventWatcherUrl = "https://raw.githubusercontent.com/c3iv3r/a/refs/heads/main/utils/fishit/inventdetect.lua"

    local success, result = pcall(function()
        return loadstring(game:HttpGet(inventWatcherUrl))()
    end)

    if success then
        return result.new()
    else
        logger:error("Failed to load InventoryWatcher:", result)
        return nil
    end
end

local function hasItemInInventory(marketItem)
    if not inventoryWatcher then return false end

    local itemType = marketItem.Type
    local identifier = marketItem.Identifier

    if itemType == "Baits" then
        local baits = inventoryWatcher:getSnapshotTyped("Baits")
        for _, bait in ipairs(baits) do
            local name = inventoryWatcher:_resolveName("Baits", bait.Id)
            if name == identifier then
                return true
            end
        end
    elseif itemType == "Fishing Rods" then
        local rods = inventoryWatcher:getSnapshotTyped("Fishing Rods")
        for _, rod in ipairs(rods) do
            local name = inventoryWatcher:_resolveName("Fishing Rods", rod.Id)
            if name == identifier then
                return true
            end
        end
    elseif itemType == "Totems" then
        local items = inventoryWatcher:getSnapshotTyped("Items")
        for _, item in ipairs(items) do
            local name = inventoryWatcher:_resolveName("Items", item.Id)
            if name == identifier then
                return true
            end
        end
    end

    return false
end

local function canAffordItem(marketItem)
    if not inventoryWatcher or not inventoryWatcher._data then return false end

    local price = marketItem.Price
    local currency = marketItem.Currency

    if not price or currency == "Robux" then return false end

    local currencyPath
    if currency == "Coins" then
        currencyPath = "Coins"
    else
        return false -- Unknown currency
    end

    local currentAmount = inventoryWatcher._data:Get(currencyPath) or 0
    return currentAmount >= price
end

local function purchaseItem(itemId)
    if purchasing then
        logger:warn("Already purchasing, queueing item", itemId)
        table.insert(purchaseQueue, itemId)
        return
    end

    purchasing = true

    spawn(function()
        local success, result = pcall(function()
            return PurchaseRemote:InvokeServer(itemId)
        end)

        if success and result then
            logger:info("Successfully purchased item ID:", itemId)
        else
            logger:warn("Failed to purchase item ID:", itemId, "Error:", result)
        end

        purchasing = false

        -- Process queue
        if #purchaseQueue > 0 then
            local nextItem = table.remove(purchaseQueue, 1)
            task.wait(1) -- Small delay between purchases
            purchaseItem(nextItem)
        end
    end)
end

local function shouldBuyItem(itemId)
    local marketItem = marketLookup[itemId]
    if not marketItem then
        logger:warn("Unknown market item ID:", itemId)
        return false
    end
    
    -- CRITICAL: Must have target items selected
    if not config.targetItems or #config.targetItems == 0 then
        logger:debug("No target items selected - skipping all purchases")
        return false
    end
    
    -- Check if item is in target list
    local found = false
    for _, targetId in ipairs(config.targetItems) do
        if targetId == itemId then
            found = true
            break
        end
    end
    if not found then
        return false
    end
    
    -- Skip Robux items if not enabled
    if marketItem.Currency == "Robux" and not config.buyRobuxItems then
        return false
    end
    
    -- Skip crates if not enabled
    if marketItem.SkinCrate and not config.buyCrates then
        return false
    end
    
    -- Check SingleCopy items
    if marketItem.SingleCopy then
        if hasItemInInventory(marketItem) then
            logger:debug("Already own", marketItem.Identifier, "- skipping")
            return false
        end
    end
    
    -- Check affordability
    if not canAffordItem(marketItem) then
        logger:debug("Cannot afford", marketItem.Identifier, "- skipping")
        return false
    end
    
    return true
end

local function processMerchantStock()
    if not merchantReplion then return end
    
    -- Check if any items are selected
    if not config.targetItems or #config.targetItems == 0 then
        logger:warn("No items selected! Please select at least 1 item from dropdown.")
        return
    end
    
    local items = merchantReplion:Get("Items")
    if not items or type(items) ~= "table" then return end
    
    logger:info("Processing merchant stock:", #items, "items")
    
    local purchaseCount = 0
    for _, itemId in ipairs(items) do
        if shouldBuyItem(itemId) then
            local marketItem = marketLookup[itemId]
            logger:info("Purchasing:", marketItem.Identifier, "for", marketItem.Price, marketItem.Currency)
            purchaseItem(itemId)
            purchaseCount = purchaseCount + 1
            
            if config.delayBetweenPurchases then
                task.wait(config.delayBetweenPurchases)
            end
        end
    end
    
    if purchaseCount == 0 then
        logger:info("No items to purchase (either not in stock, already owned, or can't afford)")
    end
end

-- === Main Functions ===
function autobuymerchantFeature:Init(guiControls)
    if inited then return true end

    logger:info("Initializing Auto Buy Merchant...")

    -- Create market lookup
    marketLookup = createMarketLookup()
    logger:debug("Created market lookup with", #MarketItemData, "items")

    -- Load inventory watcher
    inventoryWatcher = loadInventoryWatcher()
    if not inventoryWatcher then
        logger:error("Failed to initialize InventoryWatcher")
        return false
    end

    -- Wait for inventory to be ready
    inventoryWatcher:onReady(function()
        logger:info("InventoryWatcher ready")
    end)

    -- Wait for merchant replion
    spawn(function()
        merchantReplion = Replion.Client:WaitReplion("Merchant")
        logger:info("Connected to Merchant Replion")

        if running then
            self:_setupMerchantWatching()
        end
    end)

    inited = true
    return true
end

function autobuymerchantFeature:Start(userConfig)
    if running then return end
    if not inited then
        local ok = self:Init()
        if not ok then return end
    end

    -- Default config - FIXED: targetItems starts empty (no auto-buy all)
    config = {
        enabled = true,
        targetItems = {}, -- MUST be populated by user selection
        buyRobuxItems = false,
        buyCrates = false,
        delayBetweenPurchases = 1, -- seconds
        checkInterval = 5 -- seconds
    }

    -- Merge user config
    if userConfig then
        for k, v in pairs(userConfig) do
            config[k] = v
        end
    end

    running = true
    logger:info("Auto Buy Merchant started with config:", config)

    if merchantReplion then
        self:_setupMerchantWatching()
    end
end

function autobuymerchantFeature:_setupMerchantWatching()
    if not merchantReplion then return end

    -- Listen for stock changes
    table.insert(connections, merchantReplion:OnChange("Items", function()
        if not running or not config.enabled then return end

        logger:info("Merchant stock updated!")
        task.wait(0.5) -- Small delay to ensure data is updated
        processMerchantStock()
    end))

    -- Initial stock check
    task.defer(function()
        if running and config.enabled then
            processMerchantStock()
        end
    end)
end

function autobuymerchantFeature:Stop()
    if not running then return end

    running = false
    config.enabled = false

    -- Disconnect all connections
    for _, conn in ipairs(connections) do
        pcall(function() conn:Disconnect() end)
    end
    table.clear(connections)

    logger:info("Auto Buy Merchant stopped")
end

function autobuymerchantFeature:Cleanup()
    self:Stop()

    if inventoryWatcher then
        inventoryWatcher:destroy()
        inventoryWatcher = nil
    end

    merchantReplion = nil
    table.clear(marketLookup)
    table.clear(purchaseQueue)

    inited = false
    purchasing = false
end

-- === Config Setters ===
function autobuymerchantFeature:SetEnabled(enabled)
    if config then
        config.enabled = enabled
        logger:info("Auto buy", enabled and "enabled" or "disabled")
    end
end

function autobuymerchantFeature:ConvertNamesToIds(itemNames)
    if not itemNames or type(itemNames) ~= "table" then
        logger:warn("ConvertNamesToIds: itemNames must be a table")
        return {}
    end
    
    local ids = {}
    for _, name in ipairs(itemNames) do
        for _, marketItem in ipairs(MarketItemData) do
            if marketItem.Identifier == name then
                table.insert(ids, marketItem.Id)
                break
            end
        end
    end
    
    logger:debug("Converted", #itemNames, "names to", #ids, "IDs")
    return ids
end

function autobuymerchantFeature:ConvertIdsToNames(itemIds)
    if not itemIds or type(itemIds) ~= "table" then
        logger:warn("ConvertIdsToNames: itemIds must be a table")
        return {}
    end
    
    local names = {}
    for _, id in ipairs(itemIds) do
        local marketItem = marketLookup[id]
        if marketItem then
            table.insert(names, marketItem.Identifier)
        end
    end
    
    logger:debug("Converted", #itemIds, "IDs to", #names, "names")
    return names
end

function autobuymerchantFeature:GetAllMarketItemNames(category)
    local names = {}
    
    for _, marketItem in ipairs(MarketItemData) do
        if not category or marketItem.Type == category then
            table.insert(names, marketItem.Identifier)
        end
    end
    
    table.sort(names)
    return names
end

function autobuymerchantFeature:SetTargetItems(itemIds)
    if config then
        config.targetItems = itemIds or {}
        logger:info("Target items set:", #config.targetItems, "items")
        
        -- Log selected items for debugging
        if #config.targetItems > 0 then
            for _, itemId in ipairs(config.targetItems) do
                local marketItem = marketLookup[itemId]
                if marketItem then
                    logger:debug("Target item:", marketItem.Identifier, "(ID:", itemId, ")")
                end
            end
        else
            logger:info("No target items selected - auto-buy disabled")
        end
    end
end

function autobuymerchantFeature:SetBuyRobuxItems(enabled)
    if config then
        config.buyRobuxItems = enabled
        logger:info("Buy Robux items:", enabled)
    end
end

function autobuymerchantFeature:SetBuyCrates(enabled)
    if config then
        config.buyCrates = enabled
        logger:info("Buy crates:", enabled)
    end
end

-- === GUI Helper Functions ===

-- Get all available items for dropdown population
function autobuymerchantFeature:GetAllMarketItems()
    local items = {}
    
    for _, marketItem in ipairs(MarketItemData) do
        table.insert(items, {
            id = marketItem.Id,
            name = marketItem.Identifier,
            type = marketItem.Type,
            price = marketItem.Price,
            currency = marketItem.Currency,
            displayName = marketItem.Identifier .. " (" .. tostring(marketItem.Price) .. " " .. marketItem.Currency .. ")"
        })
    end
    
    -- Sort by type then by name
    table.sort(items, function(a, b)
        if a.type ~= b.type then
            return a.type < b.type
        end
        return a.name < b.name
    end)
    
    return items
end

-- Get items filtered by category for dropdown
function autobuymerchantFeature:GetMarketItemsByCategory(category)
    local items = {}
    
    for _, marketItem in ipairs(MarketItemData) do
        if not category or marketItem.Type == category then
            table.insert(items, {
                id = marketItem.Id,
                name = marketItem.Identifier,
                type = marketItem.Type,
                price = marketItem.Price,
                currency = marketItem.Currency,
                displayName = marketItem.Identifier .. " (" .. tostring(marketItem.Price) .. " " .. marketItem.Currency .. ")"
            })
        end
    end
    
    -- Sort by name
    table.sort(items, function(a, b)
        return a.name < b.name
    end)
    
    return items
end

-- Get available categories for category filter
function autobuymerchantFeature:GetMarketCategories()
    local categories = {}
    local seen = {}
    
    for _, marketItem in ipairs(MarketItemData) do
        local category = marketItem.Type
        if category and not seen[category] then
            seen[category] = true
            table.insert(categories, category)
        end
    end
    
    table.sort(categories)
    return categories
end

-- Helper function to populate dropdown with proper formatting
function autobuymerchantFeature:PopulateDropdown(dropdownElement, category)
    if not dropdownElement then 
        logger:error("Dropdown element is nil")
        return 
    end
    
    -- Clear existing items
    dropdownElement:Clear()
    
    -- Get items based on category filter
    local items = category and self:GetMarketItemsByCategory(category) or self:GetAllMarketItems()
    
    -- Add items to dropdown
    for _, item in ipairs(items) do
        dropdownElement:Add({
            Name = item.displayName,
            Value = item.id
        })
    end
    
    logger:info("Populated dropdown with", #items, "items", category and ("in category: " .. category) or "")
    
    return items
end

-- Validate if selected items are valid
function autobuymerchantFeature:ValidateTargetItems(itemIds)
    if not itemIds or type(itemIds) ~= "table" then
        return false, "Target items must be a table"
    end
    
    if #itemIds == 0 then
        return false, "At least one item must be selected"
    end
    
    for i, itemId in ipairs(itemIds) do
        if not marketLookup[itemId] then
            return false, "Invalid item ID at position " .. i .. ": " .. tostring(itemId)
        end
    end
    
    return true, "Valid"
end

-- === Debug Functions ===
function autobuymerchantFeature:GetStatus()
    return {
        inited = inited,
        running = running,
        config = config,
        purchasing = purchasing,
        queueLength = #purchaseQueue,
        merchantConnected = merchantReplion ~= nil,
        inventoryReady = inventoryWatcher and inventoryWatcher._ready or false,
        targetItemsCount = config.targetItems and #config.targetItems or 0
    }
end

function autobuymerchantFeature:GetCurrentStock()
    if not merchantReplion then return {} end

    local items = merchantReplion:Get("Items") or {}
    local stock = {}

    for _, itemId in ipairs(items) do
        local marketItem = marketLookup[itemId]
        if marketItem then
            table.insert(stock, {
                id = itemId,
                name = marketItem.Identifier,
                price = marketItem.Price,
                currency = marketItem.Currency,
                canBuy = shouldBuyItem(itemId),
                isTargeted = config.targetItems and table.find(config.targetItems, itemId) ~= nil or false
            })
        end
    end

    return stock
end

function autobuymerchantFeature:ForceCheckStock()
    if running and config.enabled then
        logger:info("Force checking merchant stock...")
        processMerchantStock()
    else
        logger:warn("Cannot check stock - feature not running or disabled")
    end
end

return autobuymerchantFeature