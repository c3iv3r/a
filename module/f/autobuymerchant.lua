-- Auto Buy Merchant
-- File: Fish-It/autoBuyMerchantFeature.lua
local autoBuyMerchantFeature = {}
autoBuyMerchantFeature.__index = autoBuyMerchantFeature

local logger = _G.Logger and _G.Logger.new("AutoBuyMerchant") or {
    debug = function() end,
    info = function() end,
    warn = function() end,
    error = function() end
}

--// Services
local ReplicatedStorage = game:GetService("ReplicatedStorage")

--// Modules
local TravelingMerchantController = nil
local MarketItemData = nil
local Replion = nil

--// State
local inited = false
local running = false
local merchantReplion = nil
local autoBuyConnection = nil
local remoteFunction = nil
local purchasedItems = {}
local selectedItems = {}
local itemNames = {}
local itemIdMap = {}

-- === lifecycle ===
function autoBuyMerchantFeature:Init(guiControls)
    local ok, err = pcall(function()
        TravelingMerchantController = require(ReplicatedStorage.Controllers.TravelingMerchantController)
        MarketItemData = require(ReplicatedStorage.Shared.MarketItemData)
        Replion = require(ReplicatedStorage.Packages.Replion)
        remoteFunction = ReplicatedStorage.Packages._Index["sleitnick_net@0.2.0"].net["RF/PurchaseMarketItem"]
    end)
    
    if not ok then
        logger:warn("Gagal load modules: " .. tostring(err))
        return false
    end
    
    -- Wait for merchant replion
    local success = pcall(function()
        merchantReplion = Replion.Client:WaitReplion("Merchant")
    end)
    
    if not success or not merchantReplion then
        logger:warn("Merchant Replion tidak tersedia")
        return false
    end
    
    -- Build item list
    for _, item in MarketItemData do
        if not item.SkinCrate then
            local displayName = item.DisplayName or item.Identifier
            table.insert(itemNames, displayName)
            itemIdMap[displayName] = item.Id
        end
    end
    
    inited = true
    return true
end

function autoBuyMerchantFeature:Start(config)
    if running then return end
    if not inited then
        local ok = self:Init()
        if not ok then return end
    end
    running = true
    
    purchasedItems = {}
    
    -- Immediate check
    self:_checkAndBuy()
    
    -- Listen for stock refresh
    if not autoBuyConnection then
        autoBuyConnection = merchantReplion:OnChange("Items", function()
            self:_checkAndBuy()
        end)
    end
end

function autoBuyMerchantFeature:Stop()
    if not running then return end
    running = false
    
    if autoBuyConnection then
        autoBuyConnection:Disconnect()
        autoBuyConnection = nil
    end
    
    purchasedItems = {}
end

function autoBuyMerchantFeature:Cleanup()
    self:Stop()
    table.clear(selectedItems)
    table.clear(purchasedItems)
end

-- === setters ===
function autoBuyMerchantFeature:SetSelectedItems(items)
    selectedItems = items or {}
end

function autoBuyMerchantFeature:GetItemNames()
    return itemNames
end

-- === internal ===
function autoBuyMerchantFeature:_checkAndBuy()
    if not running then return end
    
    local ok, currentStock = pcall(function()
        return merchantReplion:GetExpect("Items")
    end)
    
    if not ok or not currentStock then return end
    
    for _, itemId in currentStock do
        if purchasedItems[itemId] then continue end
        
        local marketData = TravelingMerchantController:GetMarketDataFromId(itemId)
        if not marketData then continue end
        
        local itemName = marketData.DisplayName or marketData.Identifier
        
        if table.find(selectedItems, itemName) then
            if marketData.SingleCopy and TravelingMerchantController:OwnsLocalItem(marketData) then
                continue
            end
            
            task.spawn(function()
                local success = pcall(function()
                    remoteFunction:InvokeServer(itemId)
                end)
                
                if success then
                    purchasedItems[itemId] = true
                    logger:info("Purchased: " .. itemName)
                end
            end)
        end
    end
end

return autoBuyMerchantFeature