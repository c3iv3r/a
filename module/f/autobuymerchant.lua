-- Auto Buy Merchant Feature (IMPROVED - Accept Names or IDs)
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
local HttpService = game:GetService("HttpService")

--// Direct paths
local LocalPlayer = Players.LocalPlayer
local Replion = require(ReplicatedStorage.Packages.Replion)
local MarketItemData = require(ReplicatedStorage.Shared.MarketItemData)
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
local marketLookup = {}
local marketLookupByName = {}

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
    local inventWatcherUrl = "https://raw.githubusercontent.com/c3iv3r/a/refs/heads/main/utils/fishit/inventdetect.lua"

    local success, module = pcall(function()
        local code = game:HttpGet(inventWatcherUrl)
        local loadedFunc = loadstring(code)
        if not loadedFunc then
            error("loadstring failed")
        end
        return loadedFunc()
    end)

    if success and module and module.new then
        return module.new()
    else
        logger:error("Failed to load InventoryWatcher:", module)
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
        return false
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

        if #purchaseQueue > 0 then
            local nextItem = table.remove(purchaseQueue, 1)
            task.wait(1)
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

    if not config.targetItemIds or #config.targetItemIds == 0 then
        logger:debug("No target items selected - skipping all purchases")
        return false
    end

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

    if marketItem.Currency == "Robux" and not config.buyRobuxItems then
        return false
    end

    if marketItem.SkinCrate and not config.buyCrates then
        return false
    end

    if marketItem.SingleCopy then
        if hasItemInInventory(marketItem) then
            logger:debug("Already own", marketItem.Identifier, "- skipping")
            return false
        end
    end

    if not canAffordItem(marketItem) then
        logger:debug("Cannot afford", marketItem.Identifier, "- skipping")
        return false
    end

    return true
end

local function processMerchantStock()
    if not merchantReplion then return end

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
    if self.inited then return true end

    logger:info("Initializing Auto Buy Merchant...")

    marketLookup, marketLookupByName = createMarketLookup()
    logger:debug("Created market lookup with", #MarketItemData, "items")

    inventoryWatcher = loadInventoryWatcher()
    if not inventoryWatcher then
        logger:error("Failed to initialize InventoryWatcher")
        return false
    end

    inventoryWatcher:onReady(function()
        logger:info("InventoryWatcher ready")
    end)

    spawn(function()
        merchantReplion = Replion.Client:WaitReplion("Merchant")
        logger:info("Connected to Merchant Replion")

        if running then
            self:_setupMerchantWatching()
        end
    end)

    self.inited = true
    self.__controls = guiControls
    return true
end

function autobuymerchantFeature:Start(userConfig)
    if running then return end
    if not inited then
        local ok = self:Init()
        if not ok then return end
    end
    
    config = {
        enabled = true,
        targetItemIds = {},
        buyRobuxItems = false,
        buyCrates = false,
        delayBetweenPurchases = 1,
        checkInterval = 5
    }

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

    table.insert(connections, merchantReplion:OnChange("Items", function()
        if not running or not config.enabled then return end

        logger:info("Merchant stock updated!")
        task.wait(0.5)
        processMerchantStock()
    end))

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

-- === Config Setters ===
function autobuymerchantFeature:SetEnabled(enabled)
    if config then
        config.enabled = enabled
        logger:info("Auto buy", enabled and "enabled" or "disabled")
    end
end

function autobuymerchantFeature:SetTargetItems(items)
    if not config then return end
    
    -- CRITICAL: Ensure lookup tables exist
    if not next(marketLookupByName) then
        logger:warn("Market lookup not ready, initializing...")
        marketLookup, marketLookupByName = createMarketLookup()
    end

    local targetIds = {}

    if type(items) == "table" then
        for key, value in pairs(items) do
            local itemId = nil

            if type(value) == "boolean" and value == true then
                local marketItem = marketLookupByName[key]
                if marketItem then
                    itemId = marketItem.Id
                else
                    logger:warn("Item not found:", key)
                end
            elseif type(key) == "number" and type(value) == "string" then
                local marketItem = marketLookupByName[value]
                if marketItem then
                    itemId = marketItem.Id
                else
                    logger:warn("Item not found:", value)
                end
            elseif type(key) == "number" and type(value) == "number" then
                itemId = value
            elseif type(key) == "number" and marketLookup[key] then
                itemId = key
            end

            if itemId and not table.find(targetIds, itemId) then
                table.insert(targetIds, itemId)
            end
        end
    end

    config.targetItemIds = targetIds

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