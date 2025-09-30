-- AutoBuyMerchant.lua
local AutoBuyMerchant = {}
AutoBuyMerchant.__index = AutoBuyMerchant

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local MarketItemData = require(ReplicatedStorage.Shared.MarketItemData)
local PurchaseEvent = ReplicatedStorage.Packages._Index["sleitnick_net@0.2.0"].net["RF/PurchaseMarketItem"]

local Replion = require(ReplicatedStorage.Packages.Replion)

function AutoBuyMerchant.new()
    local self = setmetatable({}, AutoBuyMerchant)
    
    self._running = false
    self._targetItems = {}
    self._controls = nil
    self._merchant = nil
    self._invWatcher = nil
    self._updateThread = nil
    self._processing = false
    
    return self
end

function AutoBuyMerchant:Init(controls)
    self._controls = controls
    
    local invWatcherCode = game:HttpGet("https://raw.githubusercontent.com/c3iv3r/a/refs/heads/main/utils/fishit/inventdetect.lua")
    local InventoryWatcher = loadstring(invWatcherCode)()
    self._invWatcher = InventoryWatcher.new()
    
    self._invWatcher:onReady(function()
        print("[AutoBuyMerchant] InventoryWatcher ready")
    end)
    
    Replion.Client:AwaitReplion("Merchant", function(merchant)
        self._merchant = merchant
        print("[AutoBuyMerchant] Merchant replion loaded")
    end)
end

function AutoBuyMerchant:SetTargetItems(items)
    self._targetItems = items or {}
end

function AutoBuyMerchant:_getItemByIdentifier(identifier)
    for _, item in ipairs(MarketItemData) do
        if item.Identifier == identifier then
            return item
        end
    end
    return nil
end

function AutoBuyMerchant:_isInStock(itemId)
    if not self._merchant then return false end
    
    local items = self._merchant:Get("Items")
    if not items then return false end
    
    for _, id in ipairs(items) do
        if id == itemId then
            return true
        end
    end
    return false
end

function AutoBuyMerchant:_ownsItem(itemData)
    if not itemData.SingleCopy then return false end
    if not self._invWatcher then return false end
    
    local category = itemData.Type
    local identifier = itemData.Identifier
    
    local snapshot = self._invWatcher:getSnapshotTyped(category)
    if not snapshot then return false end
    
    for _, entry in ipairs(snapshot) do
        local entryId = entry.Id or entry.id
        if entryId == identifier then
            return true
        end
    end
    
    return false
end

function AutoBuyMerchant:_tryPurchase(itemData)
    if self._processing then return end
    
    if not self:_isInStock(itemData.Id) then
        return
    end
    
    if itemData.SingleCopy and self:_ownsItem(itemData) then
        return
    end
    
    self._processing = true
    
    local success = pcall(function()
        PurchaseEvent:InvokeServer(itemData.Id)
    end)
    
    if success then
        print("[AutoBuyMerchant] Purchased:", itemData.Identifier)
    end
    
    task.wait(0.5)
    self._processing = false
end

function AutoBuyMerchant:_updateLoop()
    while self._running do
        for _, identifier in ipairs(self._targetItems) do
            if not self._running then break end
            
            local itemData = self:_getItemByIdentifier(identifier)
            if itemData then
                self:_tryPurchase(itemData)
            end
        end
        
        task.wait(60)
    end
end

function AutoBuyMerchant:Start(config)
    if self._running then return end
    
    if config and config.targetItems then
        self._targetItems = config.targetItems
    end
    
    if #self._targetItems == 0 then
        warn("[AutoBuyMerchant] No items selected")
        if self._controls and self._controls.Toggle then
            self._controls.Toggle:SetValue(false)
        end
        return
    end
    
    if not self._merchant then
        warn("[AutoBuyMerchant] Merchant not loaded")
        if self._controls and self._controls.Toggle then
            self._controls.Toggle:SetValue(false)
        end
        return
    end
    
    self._running = true
    print("[AutoBuyMerchant] Started")
    
    self._updateThread = task.spawn(function()
        self:_updateLoop()
    end)
end

function AutoBuyMerchant:Stop()
    if not self._running then return end
    
    self._running = false
    self._processing = false
    
    if self._updateThread then
        task.cancel(self._updateThread)
        self._updateThread = nil
    end
    
    print("[AutoBuyMerchant] Stopped")
end

function AutoBuyMerchant:Cleanup()
    self:Stop()
    
    if self._invWatcher and self._invWatcher.destroy then
        self._invWatcher:destroy()
        self._invWatcher = nil
    end
    
    self._merchant = nil
    self._controls = nil
    self._targetItems = {}
    
    print("[AutoBuyMerchant] Cleaned up")
end

return AutoBuyMerchant