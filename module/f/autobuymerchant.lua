-- AutoBuyMerchant.lua
-- Auto-purchase items from Travelling Merchant with real-time stock monitoring
-- Interface: Init(), Start(), Stop(), Cleanup()

local AutoBuyMerchant = {}
AutoBuyMerchant.__index = AutoBuyMerchant

local logger = _G.Logger and _G.Logger.new("AutoBuyMerchant") or {
    debug = function() end,
    info = function() end,
    warn = function() end,
    error = function() end
}

--// Services
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

--// Safe module loading
local function safeRequire(modulePath)
    local ok, result = pcall(function()
        return require(modulePath)
    end)
    if ok then return result end
    logger:error("Failed to require:", modulePath, "-", result)
    return nil
end

--// Modules
local Replion = safeRequire(ReplicatedStorage.Packages.Replion)
local Net = safeRequire(ReplicatedStorage.Packages.Net)
local MarketItemData = safeRequire(ReplicatedStorage.Shared.MarketItemData)

--// InventoryWatcher
local InventoryWatcher = nil
local INVENTORY_WATCHER_URL = "https://raw.githubusercontent.com/c3iv3r/a/refs/heads/main/utils/fishit/inventdetect.lua"

--// Constants
local UPDATE_INTERVAL = 60 -- Check every 1 minute
local PURCHASE_COOLDOWN = 0.5 -- Delay between purchases

--// State
local inited = false
local running = false

-- === Constructor ===
function AutoBuyMerchant.new()
    local self = setmetatable({}, AutoBuyMerchant)
    
    self._targetItems = {} -- Selected item names from dropdown
    self._merchantReplion = nil
    self._inventoryWatcher = nil
    self._controls = nil
    
    self._lastUpdate = 0
    self._currentStock = {} -- Current merchant stock {id, ...}
    self._itemNameToId = {} -- Map: itemName -> itemId
    self._itemIdToData = {} -- Map: itemId -> itemData
    
    self._connections = {}
    self._updateConnection = nil
    self._purchaseRemote = Net:RemoteFunction("PurchaseMarketItem")
    
    return self
end

-- === Init (called once) ===
function AutoBuyMerchant:Init(guiControls)
    if inited then 
        logger:warn("Already initialized")
        return true 
    end
    
    self._controls = guiControls
    
    logger:info("Initializing...")
    
    -- Build item maps with error handling
    local buildOk, buildErr = pcall(function()
        self:_buildItemMaps()
    end)
    
    if not buildOk then
        logger:error("Failed to build item maps:", buildErr)
        return false
    end
    
    -- Load InventoryWatcher
    local invLoaded = self:_loadInventoryWatcher()
    if not invLoaded then
        logger:warn("InventoryWatcher failed to load (SingleCopy validation disabled)")
    end
    
    -- Wait for Merchant Replion (async)
    task.spawn(function()
        local ok, merchant = pcall(function()
            return Replion.Client:WaitReplion("Merchant")
        end)
        
        if not ok or not merchant then
            logger:error("Failed to load Merchant Replion:", merchant)
            return
        end
        
        self._merchantReplion = merchant
        logger:info("Merchant Replion loaded")
        
        -- Subscribe to stock changes
        self._merchantReplion:OnChange("Items", function(_, newItems)
            self:_onStockUpdate(newItems)
        end)
        
        -- Initial stock load
        local initialStock = self._merchantReplion:GetExpect("Items")
        if initialStock then
            self:_onStockUpdate(initialStock)
        end
    end)
    
    inited = true
    logger:info("Initialized successfully")
    return true
end

-- === Start ===
function AutoBuyMerchant:Start(config)
    if running then
        logger:warn("Already running")
        return
    end
    
    if not inited then
        local ok = self:Init()
        if not ok then return end
    end
    
    config = config or {}
    
    -- Set target items from config
    if config.targetItems then
        self:SetTargetItems(config.targetItems)
    end
    
    -- Validate target items
    if #self._targetItems == 0 then
        logger:warn("Cannot start: No items selected in dropdown")
        if self._controls and self._controls.Toggle then
            task.defer(function()
                self._controls.Toggle:SetValue(false)
            end)
        end
        return
    end
    
    running = true
    self._lastUpdate = 0
    
    logger:info("===== STARTED =====")
    logger:info("Monitoring", #self._targetItems, "target items")
    
    -- Start update loop
    self:_startUpdateLoop()
    
    -- Immediate check (with small delay)
    task.spawn(function()
        task.wait(1)
        if running then
            self:_checkAndPurchase()
        end
    end)
end

-- === Stop ===
function AutoBuyMerchant:Stop()
    if not running then return end
    
    running = false
    self:_stopUpdateLoop()
    
    logger:info("===== STOPPED =====")
end

-- === Cleanup ===
function AutoBuyMerchant:Cleanup()
    self:Stop()
    
    -- Disconnect all connections
    for _, conn in ipairs(self._connections) do
        pcall(function() conn:Disconnect() end)
    end
    table.clear(self._connections)
    
    -- Destroy InventoryWatcher
    if self._inventoryWatcher and self._inventoryWatcher.destroy then
        pcall(function()
            self._inventoryWatcher:destroy()
        end)
    end
    
    -- Reset state
    self._merchantReplion = nil
    self._inventoryWatcher = nil
    self._targetItems = {}
    self._currentStock = {}
    
    inited = false
    logger:info("Cleanup complete")
end

-- === Private: Initialization Helpers ===
function AutoBuyMerchant:_buildItemMaps()
    -- Check if MarketItemData loaded
    if not MarketItemData then
        logger:error("MarketItemData is nil - cannot build maps")
        return
    end
    
    if type(MarketItemData) ~= "table" then
        logger:error("MarketItemData is not a table:", type(MarketItemData))
        return
    end
    
    local validItems = 0
    
    for i, itemData in ipairs(MarketItemData) do
        -- Skip invalid entries
        if type(itemData) ~= "table" then 
            logger:warn("Skipping invalid item data at index", i, "(not a table)")
            continue 
        end
        
        -- Validate Id
        local id = itemData.Id
        if not id or type(id) ~= "number" then
            logger:warn("Skipping item at index", i, "- invalid or missing Id")
            continue
        end
        
        -- Get name with strict validation
        local name = itemData.Identifier or itemData.DisplayName
        
        -- CRITICAL: Check if name is valid before using as key
        if not name or type(name) ~= "string" or name == "" then
            logger:warn("Skipping item Id", id, "at index", i, "- no valid Identifier/DisplayName")
            -- Still store in IdToData for reference
            if id then
                self._itemIdToData[id] = itemData
            end
            continue
        end
        
        -- Store mappings (name is guaranteed valid string here)
        self._itemNameToId[name] = id
        self._itemIdToData[id] = itemData
        validItems = validItems + 1
    end
    
    logger:info("Built item maps:", validItems, "valid items out of", #MarketItemData, "total")
    
    if validItems == 0 then
        logger:warn("No valid items found in MarketItemData!")
    end
end

function AutoBuyMerchant:_loadInventoryWatcher()
    local success, result = pcall(function()
        local code = game:HttpGet(INVENTORY_WATCHER_URL)
        if not code or code == "" then
            error("Empty response from URL")
        end
        
        local scriptFunc = loadstring(code)
        if not scriptFunc then
            error("Failed to loadstring")
        end
        
        InventoryWatcher = scriptFunc()
        if not InventoryWatcher then
            error("Script returned nil")
        end
        
        return true
    end)
    
    if not success then
        logger:error("Failed to load InventoryWatcher:", result)
        return false
    end
    
    -- Create instance
    success, result = pcall(function()
        self._inventoryWatcher = InventoryWatcher.new()
        return true
    end)
    
    if not success then
        logger:error("Failed to create InventoryWatcher instance:", result)
        return false
    end
    
    logger:info("InventoryWatcher loaded successfully")
    
    -- Wait for inventory to be ready
    if self._inventoryWatcher.onReady then
        self._inventoryWatcher:onReady(function()
            logger:info("InventoryWatcher ready")
        end)
    end
    
    return true
end

-- === Private: Stock Management ===
function AutoBuyMerchant:_onStockUpdate(stockIds)
    if not stockIds then return end
    
    self._currentStock = {}
    for _, id in ipairs(stockIds) do
        table.insert(self._currentStock, id)
    end
    
    logger:debug("Stock updated:", #self._currentStock, "items available")
    
    -- If enabled, check for purchases
    if running then
        self:_checkAndPurchase()
    end
end

-- === Private: Item Validation ===
function AutoBuyMerchant:_ownsItem(itemData)
    if not self._inventoryWatcher then return false end
    if not itemData.SingleCopy then return false end
    
    local itemType = itemData.Type
    local itemId = itemData.Identifier
    
    -- Get typed snapshot for the category
    local success, snapshot = pcall(function()
        return self._inventoryWatcher:getSnapshotTyped(itemType)
    end)
    
    if not success or not snapshot then return false end
    
    -- Check if player owns this item
    for _, entry in ipairs(snapshot) do
        local entryId = entry.Id or entry.id
        if entryId == itemId then
            return true
        end
    end
    
    return false
end

function AutoBuyMerchant:_canPurchase(itemId)
    local itemData = self._itemIdToData[itemId]
    if not itemData then return false, "Item data not found" end
    
    -- Check SingleCopy restriction
    if itemData.SingleCopy then
        if self:_ownsItem(itemData) then
            return false, "Already owned (SingleCopy)"
        end
    end
    
    -- Check if item has ProductId (Robux items)
    if itemData.ProductId then
        return false, "Robux item (skipped)"
    end
    
    -- Check if it's a skin crate
    if itemData.SkinCrate then
        return false, "Skin crate (skipped)"
    end
    
    return true, "OK"
end

-- === Private: Purchase Logic ===
function AutoBuyMerchant:_purchaseItem(itemId)
    local itemData = self._itemIdToData[itemId]
    if not itemData then
        logger:warn("Item data not found for ID:", itemId)
        return false
    end
    
    local canPurchase, reason = self:_canPurchase(itemId)
    if not canPurchase then
        logger:debug("Skipping", itemData.Identifier or itemId, "-", reason)
        return false
    end
    
    -- Attempt purchase
    logger:info("Purchasing:", itemData.Identifier or itemId, "- ID:", itemId)
    
    local success, result = pcall(function()
        return self._purchaseRemote:InvokeServer(itemId)
    end)
    
    if success then
        if result then
            logger:info("✓ Successfully purchased:", itemData.Identifier or itemId)
            return true
        else
            logger:warn("✗ Purchase failed (insufficient funds?):", itemData.Identifier or itemId)
            return false
        end
    else
        logger:error("✗ Purchase error:", result)
        return false
    end
end

function AutoBuyMerchant:_checkAndPurchase()
    if not running then return end
    if #self._targetItems == 0 then
        logger:debug("No items selected in dropdown")
        return
    end
    
    logger:debug("Checking for target items...")
    
    -- Convert target item names to IDs
    local targetIds = {}
    for _, itemName in ipairs(self._targetItems) do
        local itemId = self._itemNameToId[itemName]
        if itemId then
            table.insert(targetIds, itemId)
        else
            logger:warn("Item name not found:", itemName)
        end
    end
    
    if #targetIds == 0 then
        logger:debug("No valid target items")
        return
    end
    
    -- Check if any target items are in stock
    local purchasedCount = 0
    for _, targetId in ipairs(targetIds) do
        if table.find(self._currentStock, targetId) then
            local success = self:_purchaseItem(targetId)
            if success then
                purchasedCount = purchasedCount + 1
                task.wait(PURCHASE_COOLDOWN)
            end
        end
    end
    
    if purchasedCount > 0 then
        logger:info("Purchased", purchasedCount, "items")
    else
        logger:debug("No target items in stock")
    end
end

-- === Private: Update Loop ===
function AutoBuyMerchant:_startUpdateLoop()
    if self._updateConnection then return end
    
    logger:debug("Starting update loop (every", UPDATE_INTERVAL, "seconds)")
    
    self._updateConnection = RunService.Heartbeat:Connect(function()
        if not running then return end
        
        local now = tick()
        if now - self._lastUpdate >= UPDATE_INTERVAL then
            self._lastUpdate = now
            
            -- Force check merchant stock
            if self._merchantReplion then
                local ok, currentStock = pcall(function()
                    return self._merchantReplion:GetExpect("Items")
                end)
                
                if ok and currentStock then
                    self:_onStockUpdate(currentStock)
                end
            end
        end
    end)
end

function AutoBuyMerchant:_stopUpdateLoop()
    if self._updateConnection then
        self._updateConnection:Disconnect()
        self._updateConnection = nil
        logger:debug("Update loop stopped")
    end
end

-- === Public API ===
function AutoBuyMerchant:SetTargetItems(itemNames)
    self._targetItems = itemNames or {}
    logger:info("Target items set:", #self._targetItems, "items")
    
    for i, name in ipairs(self._targetItems) do
        logger:debug("  ", i, "-", name)
    end
end

function AutoBuyMerchant:GetCurrentStock()
    local stockInfo = {}
    for _, id in ipairs(self._currentStock) do
        local itemData = self._itemIdToData[id]
        if itemData then
            table.insert(stockInfo, {
                Id = id,
                Name = itemData.Identifier or itemData.DisplayName,
                Price = itemData.Price,
                Currency = itemData.Currency,
                SingleCopy = itemData.SingleCopy
            })
        end
    end
    return stockInfo
end

function AutoBuyMerchant:IsRunning()
    return running
end

function AutoBuyMerchant:GetStatus()
    return {
        initialized = inited,
        running = running,
        targetItems = #self._targetItems,
        currentStock = #self._currentStock,
        lastUpdate = self._lastUpdate,
        hasInventoryWatcher = self._inventoryWatcher ~= nil
    }
end

-- === Static Helper ===
function AutoBuyMerchant.GetMerchantItemNames()
    -- Check if MarketItemData available
    if not MarketItemData or type(MarketItemData) ~= "table" then
        logger:error("GetMerchantItemNames: MarketItemData not available")
        return {}
    end
    
    local names = {}
    
    for i, itemData in ipairs(MarketItemData) do
        -- Skip invalid entries
        if type(itemData) ~= "table" then continue end
        
        -- Get name with strict validation
        local name = itemData.Identifier or itemData.DisplayName
        
        -- CRITICAL: Only add valid string names
        if name and type(name) == "string" and name ~= "" then
            -- Exclude skin crates
            if not itemData.SkinCrate then
                table.insert(names, name)
            end
        end
    end
    
    table.sort(names)
    logger:debug("GetMerchantItemNames returned", #names, "items")
    return names
end

return AutoBuyMerchant