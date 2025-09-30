-- Auto Buy Merchant Feature (IMPROVED - Accept Names or IDs)
-- File: autobuymerchant.lua
local autobuymerchantFeature = {}
autobuymerchantFeature.__index = autobuymerchantFeature

local logger = _G.Logger and _G.Logger.new("AutoBuyMerchant") or {
    debug = function(_, ...) print("[AutoBuyMerchant]", ...) end,
    info = function(_, ...) print("[AutoBuyMerchant]", ...) end,
    warn = function(_, ...) warn("[AutoBuyMerchant]", ...) end,
    error = function(_, ...) error("[AutoBuyMerchant] " .. tostring(...)) end
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

-- Market lookup tables
local marketLookup = {} -- By ID
local marketLookupByName = {} -- By Identifier

-- === Helper Functions ===
local function createMarketLookup()
    local lookupById = {}
    local lookupByName = {}
    
    for _, item in ipairs(MarketItemData) do
        lookupById[item.Id] = item
        lookupByName[item.Identifier] = item
    end
    
    return lookupById, lookupByName
end

local function loadInventoryWatcher()
    -- Load InventoryWatcher via loadstring
    local inventWatcherUrl = "https://raw.githubusercontent.com/c3iv3r/a/refs/heads/main/utils/fishit/inventdetect.lua" -- Replace with actual URL
    
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
    if not config.targetItemIds or #config.targetItemIds == 0 then
        logger:debug("No target items selected - skipping all purchases")
        return false
    end
    
    -- Check if item is in target list
    local found = false
    for _, targetId in ipairs(config.targetItemIds) do
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
    if not config.targetItemIds or #config.targetItemIds == 0 then
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
    
    -- Create market lookups (both ID and Name)
    marketLookup, marketLookupByName = createMarketLookup()
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
    
    -- Default config
    config = {
        enabled = true,
        targetItemIds = {}, -- Internal: IDs array
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
    logger:info("Auto Buy Merchant started")
    
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
    table.clear(marketLookupByName)
    table.clear(purchaseQueue)
    
    inited = false
    purchasing = false
end

-- === Config Setters (IMPROVED - Accept Names or IDs) ===
function autobuymerchantFeature:SetEnabled(enabled)
    if config then
        config.enabled = enabled
        logger:info("Auto buy", enabled and "enabled" or "disabled")
    end
end

-- NEW: Smart setter that accepts both Names and IDs
function autobuymerchantFeature:SetTargetItems(items)
    if not config then return end
    
    local targetIds = {}
    
    if type(items) == "table" then
        for key, value in pairs(items) do
            local itemId = nil
            
            -- Check if it's a multi-select dropdown format (key=name, value=true/selected)
            if type(value) == "boolean" and value == true then
                -- Key is the name/identifier
                local marketItem = marketLookupByName[key]
                if marketItem then
                    itemId = marketItem.Id
                end
            -- Check if it's a simple array of names
            elseif type(key) == "number" and type(value) == "string" then
                -- Value is the name/identifier
                local marketItem = marketLookupByName[value]
                if marketItem then
                    itemId = marketItem.Id
                end
            -- Check if it's a simple array of IDs
            elseif type(key) == "number" and type(value) == "number" then
                -- Value is already an ID
                itemId = value
            -- Direct ID as key
            elseif type(key) == "number" and marketLookup[key] then
                itemId = key
            end
            
            -- Add to target list if valid
            if itemId and not table.find(targetIds, itemId) then
                table.insert(targetIds, itemId)
            end
        end
    end
    
    config.targetItemIds = targetIds
    
    -- Log selected items
    if #targetIds > 0 then
        logger:info("Target items set:", #targetIds, "items")
        for _, id in ipairs(targetIds) do
            local item = marketLookup[id]
            if item then
                logger:debug("-", item.Identifier, "(ID:", id .. ")")
            end
        end
    else
        logger:warn("No valid items selected!")
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

-- === Debug Functions ===
function autobuymerchantFeature:GetStatus()
    return {
        inited = inited,
        running = running,
        config = config,
        purchasing = purchasing,
        queueLength = #purchaseQueue,
        targetCount = config.targetItemIds and #config.targetItemIds or 0,
        merchantConnected = merchantReplion ~= nil,
        inventoryReady = inventoryWatcher and inventoryWatcher._ready or false
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
                canBuy = shouldBuyItem(itemId)
            })
        end
    end
    
    return stock
end

function autobuymerchantFeature:ForceCheckStock()
    if running and config.enabled then
        logger:info("Force checking merchant stock...")
        processMerchantStock()
    end
end

return autobuymerchantFeature
Updated Helper Functions (Simplified):
-- === Merchant Auto Buy Helpers ===
local MarketItemModule = game:GetService("ReplicatedStorage").Shared.MarketItemData

function Helpers.getMerchantItemNames()
    local names = {}
    local success, data = pcall(require, MarketItemModule)
    if success and data then
        for _, item in ipairs(data) do
            table.insert(names, item.Identifier)
        end
    end
    table.sort(names)
    return names
end

function Helpers.SetAutoMerchantEnabled(enabled)
    local feature = FeatureManager:Get("AutoBuyMerchant")
    if feature then
        local status = feature:GetStatus()
        
        -- Validate selection before enabling
        if enabled and status.targetCount == 0 then
            print("[Merchant] ⚠️ Please select at least 1 item before enabling!")
            return
        end
        
        if enabled then
            feature:Start()
        else
            feature:Stop()
        end
    end
end

-- NOW SIMPLIFIED - Just pass dropdown values directly!
function Helpers.SetMerchantTargetItems(selectedItems)
    local feature = FeatureManager:Get("AutoBuyMerchant")
    if feature then
        feature:SetTargetItems(selectedItems)
    end
end

function Helpers.SetMerchantBuyRobux(enabled)
    local feature = FeatureManager:Get("AutoBuyMerchant")
    if feature then
        feature:SetBuyRobuxItems(enabled)
    end
end

function Helpers.SetMerchantBuyCrates(enabled)
    local feature = FeatureManager:Get("AutoBuyMerchant")
    if feature then
        feature:SetBuyCrates(enabled)
    end
end

function Helpers.SetMerchantDelay(seconds)
    local feature = FeatureManager:Get("AutoBuyMerchant")
    if feature and feature.config then
        feature.config.delayBetweenPurchases = seconds
    end
end

function Helpers.GetMerchantStatus()
    local feature = FeatureManager:Get("AutoBuyMerchant")
    if feature then
        return feature:GetStatus()
    end
    return { running = false, queueLength = 0, targetCount = 0, merchantConnected = false }
end

function Helpers.ShowMerchantStock()
    local feature = FeatureManager:Get("AutoBuyMerchant")
    if feature then
        local stock = feature:GetCurrentStock()
        print("\n🏪 Current Merchant Stock:")
        for i, item in ipairs(stock) do
            local buyStatus = item.canBuy and "✅" or "❌"
            print(string.format("%s [%d] %s - %s %s", 
                buyStatus, item.id, item.name, 
                item.price or "Free", item.currency or ""))
        end
    end
end

function Helpers.ForceMerchantCheck()
    local feature = FeatureManager:Get("AutoBuyMerchant")
    if feature then
        feature:ForceCheckStock()
    end
end