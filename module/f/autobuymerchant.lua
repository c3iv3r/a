-- Fish-It/AutoBuyMerchant.lua
-- AutoBuyMerchant Feature mengikuti Fish-It Feature Script Contract

local AutoBuyMerchant = {}
AutoBuyMerchant.__index = AutoBuyMerchant

local logger = _G.Logger and _G.Logger.new("AutoBuyMerchant") or {
    debug = function() end,
    info = function() end,
    warn = function() end,
    error = function() end
}

-- Services
local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- Constants
local INTER_PURCHASE_DELAY = 0.5
local INIT_RETRY_COUNT = 3
local INIT_RETRY_DELAY = 1

-- State variables
local running = false
local merchantReplion = nil
local marketItemData = nil
local purchaseMerchantRemote = nil
local guiControls = {}

local selectedItems = {}
local lastPurchaseTime = 0

-- ========== LIFECYCLE METHODS ==========

function AutoBuyMerchant:Init(gui)
    guiControls = gui or {}
    
    local success1, Replion = pcall(function()
        return require(ReplicatedStorage:WaitForChild("Packages", 5):WaitForChild("Replion", 5))
    end)
    
    local success2, marketData = pcall(function()
        return require(ReplicatedStorage:WaitForChild("Shared", 5):WaitForChild("MarketItemData", 5))
    end)
    
    local success3, remote = pcall(function()
        return require(ReplicatedStorage:WaitForChild("Packages", 5)
            :WaitForChild("_Index", 5)
            :WaitForChild("sleitnick_net@0.2.0", 5)
            :WaitForChild("net", 5)
            :WaitForChild("RF/PurchaseMarketItem", 5))
    end)
    
    if not success1 or not Replion then
        logger:warn("Failed to load Replion")
        return false
    end
    
    if not success2 or not marketData then
        logger:warn("Failed to load MarketItemData")
        return false
    end
    
    if not success3 or not remote then
        logger:warn("Failed to find PurchaseMarketItem remote")
        return false
    end
    
    -- Retry logic for Merchant Replion
    local retries = 0
    while retries < INIT_RETRY_COUNT do
        local success, result = pcall(function()
            return Replion.Client:WaitReplion("Merchant")
        end)
        
        if success and result then
            merchantReplion = result
            break
        end
        
        retries = retries + 1
        if retries < INIT_RETRY_COUNT then
            logger:warn("Merchant Replion not ready, retrying... (" .. retries .. "/" .. INIT_RETRY_COUNT .. ")")
            task.wait(INIT_RETRY_DELAY)
        end
    end
    
    if not merchantReplion then
        logger:error("Failed to initialize Merchant Replion after " .. INIT_RETRY_COUNT .. " attempts")
        return false
    end
    
    marketItemData = marketData
    purchaseMerchantRemote = remote
    
    logger:info("Initialized successfully")
    return true
end

function AutoBuyMerchant:Start(config)
    if not running then
        running = true
        
        if config then
            if config.itemList then
                self:SetSelectedItems(config.itemList)
            end
            if config.interDelay then
                INTER_PURCHASE_DELAY = math.max(0.1, config.interDelay)
            end
        end
    end
    
    -- Ensure Replion is initialized before proceeding
    if not merchantReplion then
        logger:warn("Merchant Replion not initialized, attempting to initialize...")
        local success, Replion = pcall(function()
            return require(ReplicatedStorage:WaitForChild("Packages"):WaitForChild("Replion"))
        end)
        
        if success and Replion then
            local success2, result = pcall(function()
                return Replion.Client:WaitReplion("Merchant")
            end)
            
            if success2 and result then
                merchantReplion = result
                logger:info("Merchant Replion initialized successfully")
            else
                logger:error("Failed to initialize Merchant Replion")
                self:Stop()
                return false
            end
        else
            logger:error("Failed to load Replion module")
            self:Stop()
            return false
        end
    end
    
    logger:info("Starting purchase process...")
    local success = self:PurchaseSelectedItems()
    
    self:Stop()
    return success
end

function AutoBuyMerchant:Stop()
    if not running then return end
    running = false
    logger:info("Stopped")
end

function AutoBuyMerchant:Cleanup()
    self:Stop()
    selectedItems = {}
    guiControls = {}
    lastPurchaseTime = 0
end

-- ========== SETTERS & ACTIONS ==========

function AutoBuyMerchant:SetSelectedItems(itemList)
    if not itemList then return false end
    
    selectedItems = {}
    
    if type(itemList) == "table" then
        if #itemList > 0 then
            -- Array format
            for _, itemName in ipairs(itemList) do
                if type(itemName) == "string" then
                    table.insert(selectedItems, itemName)
                end
            end
        else
            -- Dictionary format
            for itemName, enabled in pairs(itemList) do
                if enabled and type(itemName) == "string" then
                    table.insert(selectedItems, itemName)
                end
            end
        end
    end
    
    logger:debug("Selected items: " .. #selectedItems)
    return true
end

function AutoBuyMerchant:PurchaseSelectedItems()
    if not running then
        logger:warn("Feature not started")
        return false
    end
    
    if #selectedItems == 0 then
        logger:warn("No items selected")
        return false
    end
    
    if not merchantReplion then
        logger:error("Merchant Replion not initialized")
        return false
    end
    
    local currentTime = tick()
    if currentTime - lastPurchaseTime < INTER_PURCHASE_DELAY then
        logger:warn("Purchase cooldown active")
        return false
    end
    
    -- Get current stock using GetExpect (confirmed from decompiled code)
    local success, currentStock = pcall(function()
        return merchantReplion:GetExpect("Items")
    end)
    
    if not success or not currentStock then
        logger:error("Failed to get merchant stock: " .. tostring(currentStock))
        return false
    end
    
    local purchasedCount = 0
    local notAvailableCount = 0
    local errorCount = 0
    
    for _, selectedName in ipairs(selectedItems) do
        if not running then break end
        
        local itemData = self:_getMarketDataByName(selectedName)
        
        if not itemData then
            logger:warn("Item data not found: " .. selectedName)
            errorCount = errorCount + 1
        elseif not self:_isItemInStock(itemData.Id, currentStock) then
            logger:warn("Item not in stock: " .. selectedName)
            notAvailableCount = notAvailableCount + 1
        else
            local success = self:_purchaseItem(itemData.Id, selectedName)
            if success then
                purchasedCount = purchasedCount + 1
                if purchasedCount > 0 then
                    task.wait(INTER_PURCHASE_DELAY)
                end
            else
                errorCount = errorCount + 1
            end
        end
    end
    
    lastPurchaseTime = currentTime
    
    local resultMsg = string.format("Purchase complete: %d bought, %d not in stock, %d errors", 
        purchasedCount, notAvailableCount, errorCount)
    logger:info(resultMsg)
    
    return purchasedCount > 0
end

-- ========== INTERNAL HELPER METHODS ==========

function AutoBuyMerchant:_getMarketDataByName(itemName)
    for _, marketData in ipairs(marketItemData) do
        if not marketData.SkinCrate then
            local name = marketData.Identifier or marketData.DisplayName
            if name == itemName then
                return marketData
            end
        end
    end
    return nil
end

function AutoBuyMerchant:_isItemInStock(itemId, currentStock)
    for _, stockId in ipairs(currentStock) do
        if stockId == itemId then
            return true
        end
    end
    return false
end

function AutoBuyMerchant:_purchaseItem(itemId, itemName)
    if not purchaseMerchantRemote then
        logger:warn("Purchase remote not available")
        return false
    end
    
    local success, result = pcall(function()
        return purchaseMerchantRemote:InvokeServer(itemId)
    end)
    
    if success and result then
        logger:info("Successfully purchased: " .. itemName .. " (ID: " .. itemId .. ")")
        return true
    else
        logger:warn("Failed to purchase " .. itemName .. ": " .. tostring(result))
        return false
    end
end

-- ========== UTILITY METHODS ==========

function AutoBuyMerchant:GetAvailableItems()
    if not merchantReplion then
        logger:warn("Merchant Replion not initialized")
        return {}
    end
    
    local success, currentStock = pcall(function()
        return merchantReplion:GetExpect("Items")
    end)
    
    if not success or not currentStock then
        logger:warn("Failed to get merchant stock")
        return {}
    end
    
    local availableItems = {}
    for _, itemId in ipairs(currentStock) do
        for _, marketData in ipairs(marketItemData) do
            if marketData.Id == itemId and not marketData.SkinCrate then
                local name = marketData.Identifier or marketData.DisplayName
                table.insert(availableItems, {
                    id = itemId,
                    name = name,
                    price = marketData.Price,
                    currency = marketData.Currency
                })
                break
            end
        end
    end
    
    return availableItems
end

function AutoBuyMerchant:IsInitialized()
    return merchantReplion ~= nil and marketItemData ~= nil and purchaseMerchantRemote ~= nil
end

return AutoBuyMerchant