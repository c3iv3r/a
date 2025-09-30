-- ===========================
-- AUTO BUY MERCHANT (Client)
-- API: Init(controls?), Start({targetItems?}), Stop(), Cleanup()
-- Also: SetTargetItems(listOfNames)
-- ===========================

local AutoBuyMerchant = {}
AutoBuyMerchant.__index = AutoBuyMerchant

-- ===== Logger (fallback colon-compatible) =====
local _L = _G.Logger and _G.Logger.new and _G.Logger:new("AutoBuyMerchant")
local logger = _L or {}
function logger:debug(...) end
function logger:info(...)  end
function logger:warn(...)  end
function logger:error(...) end

-- ===== Services & Requires =====
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players           = game:GetService("Players")

local Replion           = require(ReplicatedStorage.Packages.Replion)
local Net               = require(ReplicatedStorage.Packages.Net)
local ItemUtility       = require(ReplicatedStorage.Shared.ItemUtility)
local MarketItemData    = require(ReplicatedStorage.Shared.MarketItemData)

-- Pakai controller asli biar cek saldo + notif konsisten dengan game UI
local TMController      = require(ReplicatedStorage.Controllers.TravellingMerchantController)

-- RemoteFunction fallback (kalau tidak pakai controller)
local RF_Purchase = Net:RemoteFunction("PurchaseMarketItem")

-- URL InventDetect (InventoryWatcher) – ganti sesuai punyamu
local INVENT_URL = _G.InventoryWatcherUrl
    or "https://example.com/path/to/inventdetect.lua" -- TODO: set URL kamu

-- ===== Helpers =====
local function buildMarketMaps()
    local byId, byName = {}, {}
    for _, it in ipairs(MarketItemData) do
        byId[it.Id] = it
        byName[it.Identifier] = it.Id
    end
    return byId, byName
end

local function toSet(arr)
    local s = {}
    if typeof(arr) == "table" then
        for _, v in ipairs(arr) do if v ~= nil then s[tostring(v)] = true end end
    end
    return s
end

-- Resolve ItemData (Id, Name, Type) dari Type+Identifier
local function resolveItemData(itemType, identifier)
    local ok, data = pcall(function()
        return ItemUtility:GetItemDataFromItemType(itemType, identifier)
    end)
    if ok and data then
        local out = {
            id   = data.Id or (data.Data and data.Data.Id) or nil,
            name = data.Data and data.Data.Name or identifier,
            type = data.Data and data.Data.Type or itemType,
        }
        return out
    end
    return { id = nil, name = identifier, type = itemType }
end

-- ===== Core =====
function AutoBuyMerchant.new()
    local self = setmetatable({}, AutoBuyMerchant)

    self._controls     = nil
    self._enabled      = false
    self._loopThread   = nil
    self._busy         = false
    self._conns        = {}
    self._recent       = {}   -- throttle per itemId
    self._lastTick     = 0

    self._merchant     = nil  -- Replion("Merchant")
    self._data         = nil  -- Replion("Data")

    self._byId, self._byName = buildMarketMaps()
    self._targetSet    = {}   -- set of Identifier (string)
    self._availableSet = {}   -- set of itemId available di merchant

    self._invWatcher   = nil  -- InventoryWatcher instance (inventdetect)
    self._invReady     = false

    return self
end

-- Load InventoryWatcher via loadstring (fail-safe)
function AutoBuyMerchant:_ensureInvWatcher()
    if self._invWatcher ~= nil then return end
    local ok, ModuleOrClass = pcall(function()
        return loadstring(game:HttpGet(INVENT_URL))()
    end)
    if not ok or type(ModuleOrClass) ~= "table" or type(ModuleOrClass.new) ~= "function" then
        logger:warn("[AutoBuyMerchant] InventoryWatcher gagal dimuat; SingleCopy check akan dilewati. Detail:", tostring(ModuleOrClass))
        return
    end
    local inv = ModuleOrClass.new()
    self._invWatcher = inv
    inv:onReady(function()
        self._invReady = true
        logger:debug("[AutoBuyMerchant] InventoryWatcher ready")
    end)
end

function AutoBuyMerchant:SetTargetItems(listOfIdentifiers)
    self._targetSet = toSet(listOfIdentifiers or {})
    logger:debug("[AutoBuyMerchant] Target set ->", table.concat(listOfIdentifiers or {}, ", "))
end

function AutoBuyMerchant:Init(controls)
    self._controls = controls or {}

    -- Wait Replion objects
    self._merchant = Replion.Client:WaitReplion("Merchant")
    self._data     = Replion.Client:WaitReplion("Data")

    -- Subscribe stok real-time
    table.insert(self._conns, self._merchant:OnChange("Items", function(_, newArr)
        self:_refreshAvailable(newArr)
        -- Real-time trigger
        self:_checkAndBuy()
    end))

    -- Initial fill
    self:_refreshAvailable(self._merchant:Get("Items") or {})

    -- Prepare inv watcher (optional)
    self:_ensureInvWatcher()

    logger:info("[AutoBuyMerchant] Init done")
end

function AutoBuyMerchant:_refreshAvailable(arr)
    local s = {}
    for _, id in ipairs(arr or {}) do s[tonumber(id) or id] = true end
    self._availableSet = s
end

-- Cek kepemilikan SingleCopy
function AutoBuyMerchant:_ownsSingleCopy(market)
    if not market or not market.SingleCopy then return false end
    if not self._invWatcher or not self._invReady then
        -- Jika inventory watcher belum siap, hati-hati: jangan spam beli
        logger:warn("[AutoBuyMerchant] SingleCopy item '%s' tapi InventoryWatcher belum siap; skip dulu", tostring(market.Identifier))
        return true
    end

    local resolved = resolveItemData(market.Type, market.Identifier)
    if not resolved.id then
        -- fallback: skema nama
        local snapAll = self._invWatcher:getSnapshotTyped() -- {Items={}, Fishes={}, ...}
        for category, list in pairs(snapAll) do
            for _, entry in ipairs(list) do
                local ok, name = pcall(function()
                    -- pakai resolver internal modul
                    return self._invWatcher:_resolveName(category, entry.Id or entry.id)
                end)
                if ok and name == market.Identifier then
                    return true
                end
            end
        end
        return false
    end

    -- cari by id di semua kategori
    local snapAll = self._invWatcher:getSnapshotTyped()
    for _, list in pairs(snapAll) do
        for _, entry in ipairs(list) do
            local eid = entry.Id or entry.id
            if eid == resolved.id then
                return true
            end
        end
    end
    return false
end

-- Throttle per item id (hindari double Invoke saat event change + loop)
function AutoBuyMerchant:_throttle(id, sec)
    local now = os.clock()
    local last = self._recent[id] or 0
    if now - last < (sec or 3) then return true end
    self._recent[id] = now
    return false
end

function AutoBuyMerchant:_purchase(id, market)
    if not id or not market then return end

    -- Skip Robux / SkinCrate
    if market.SkinCrate or market.Currency == "Robux" then
        logger:debug("[AutoBuyMerchant] Skip Robux/SkinCrate:", market.Identifier)
        return
    end

    -- SingleCopy guard
    if market.SingleCopy and self:_ownsSingleCopy(market) then
        logger:debug("[AutoBuyMerchant] Sudah punya (SingleCopy):", market.Identifier)
        return
    end

    -- Gunakan controller asli kalau tersedia; ini sudah cek saldo + notif
    if TMController and TMController.InitiatePurchase then
        local ok, err = pcall(function()
            TMController:InitiatePurchase(id, market)
        end)
        if not ok then
            logger:warn("[AutoBuyMerchant] InitiatePurchase error:", tostring(err))
        else
            logger:info("[AutoBuyMerchant] Purchase sent:", market.Identifier)
        end
        return
    end

    -- Fallback langsung RF
    local ok, res = pcall(function()
        return RF_Purchase:InvokeServer(id)
    end)
    if ok then
        logger:info("[AutoBuyMerchant] RF Purchase OK:", market.Identifier, res and "[server-ok]" or "")
    else
        logger:warn("[AutoBuyMerchant] RF Purchase ERR:", tostring(res))
    end
end

function AutoBuyMerchant:_checkAndBuy()
    if not self._enabled or self._busy then return end
    self._busy = true
    -- Jika tidak ada target, tidak lakukan apa-apa
    local hasTarget = next(self._targetSet) ~= nil
    if not hasTarget then
        self._busy = false
        return
    end

    -- Untuk setiap target name -> id, cek stok merchant
    for name,_ in pairs(self._targetSet) do
        local id = self._byName[name]
        local market = id and self._byId[id] or nil
        if id and market then
            if self._availableSet[id] then
                if not self:_throttle(id, 5) then
                    self:_purchase(id, market)
                    task.wait(0.15) -- kecil saja biar tidak tabrak
                end
            else
                logger:debug(("[AutoBuyMerchant] '%s' (id=%s) belum ada di stok"):format(name, tostring(id)))
            end
        else
            logger:warn("[AutoBuyMerchant] Nama tidak dikenali di MarketItemData:", tostring(name))
        end
    end

    self._busy = false
end

function AutoBuyMerchant:Start(opts)
    if self._enabled then return end
    self._enabled = true

    if opts and opts.targetItems then
        self:SetTargetItems(opts.targetItems)
    end

    -- Kick off sekali dan buat loop 60s
    self:_checkAndBuy()

    self._loopThread = task.spawn(function()
        while self._enabled do
            for _ = 1, 60 do
                if not self._enabled then return end
                task.wait(1)
            end
            self:_checkAndBuy()
        end
    end)

    logger:info("[AutoBuyMerchant] Start")
end

function AutoBuyMerchant:Stop()
    if not self._enabled then return end
    self._enabled = false
    if self._loopThread then
        pcall(function() task.cancel(self._loopThread) end)
        self._loopThread = nil
    end
    logger:info("[AutoBuyMerchant] Stop")
end

function AutoBuyMerchant:Cleanup()
    self:Stop()
    for _, c in ipairs(self._conns) do pcall(function() c:Disconnect() end) end
    table.clear(self._conns)
    if self._invWatcher and self._invWatcher.destroy then
        pcall(function() self._invWatcher:destroy() end)
    end
    self._invWatcher = nil
    logger:info("[AutoBuyMerchant] Cleanup")
end

-- optional sugar buat FeatureManager
function AutoBuyMerchant:SetOptions(opts)
    self._options = opts or {}
end

return AutoBuyMerchant