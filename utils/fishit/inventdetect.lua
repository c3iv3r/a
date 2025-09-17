-- inventory_watcher_v2.lua
-- Lintas kategori + aware equip & autosell threshold + DUMP HELPERS (typed)

local InventoryWatcher = {}
InventoryWatcher.__index = InventoryWatcher

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Replion     = require(ReplicatedStorage.Packages.Replion)
local Constants   = require(ReplicatedStorage.Shared.Constants)
local ItemUtility = require(ReplicatedStorage.Shared.ItemUtility)

-- Optional: StringLibrary buat format berat
local StringLib = nil
pcall(function() StringLib = require(ReplicatedStorage.Shared.StringLibrary) end)

-- Kategori yang diketahui oleh game (lihat InventoryController)
local KNOWN_KEYS = { "Items", "Fishes", "Potions", "Baits", "Fishing Rods" }

local function mkSignal()
    local ev = Instance.new("BindableEvent")
    return {
        Fire=function(_,...) ev:Fire(...) end,
        Connect=function(_,f) return ev.Event:Connect(f) end,
        Destroy=function(_) ev:Destroy() end
    }
end

function InventoryWatcher.new()
    local self = setmetatable({}, InventoryWatcher)
    self._data      = nil
    self._max       = Constants.MaxInventorySize or 0

    -- RAW snapshot (langsung dari path Replion)
    self._snap      = { Items={}, Fishes={}, Potions={}, Baits={}, ["Fishing Rods"]={} }

    -- Aggregat hasil klasifikasi (TYPED) untuk hitungan cepat
    self._byType    = { Items=0, Fishes=0, Potions=0, Baits=0, ["Fishing Rods"]=0 }

    self._equipped  = { itemsSet = {}, baitId = nil }
    self._changed   = mkSignal()  -- (total,max,free,byType)
    self._equipSig  = mkSignal()  -- (equippedSet, baitId)
    self._readySig  = mkSignal()
    self._ready     = false
    self._conns     = {}

    Replion.Client:AwaitReplion("Data", function(data)
        self._data = data
        self:_scanAndSubscribeAll()
        self:_subscribeEquip()
        self._ready = true
        self._readySig:Fire()
    end)

    return self
end

-- ===== Helpers =====
local function shallowCopyArray(t)
    local out = {}
    if type(t)=="table" then for i,v in ipairs(t) do out[i]=v end end
    return out
end

function InventoryWatcher:_get(path)
    local ok, res = pcall(function() return self._data and self._data:Get(path) end)
    return ok and res or nil
end

-- Amanin call ItemUtility:Method(...) (dot/colon)
local function IU(method, ...)
    local f = ItemUtility and ItemUtility[method]
    if type(f) == "function" then
        local ok, res = pcall(f, ItemUtility, ...)
        if ok then return res end
    end
    return nil
end

function InventoryWatcher:_resolveName(category, id)
    if not id then return "<?>"
    end
    if category == "Baits" then
        local d = IU("GetBaitData", id)
        if d and d.Data and d.Data.Name then return d.Data.Name end
    elseif category == "Potions" then
        local d = IU("GetPotionData", id)
        if d and d.Data and d.Data.Name then return d.Data.Name end
    elseif category == "Fishing Rods" then
        local d = IU("GetItemData", id)
        if d and d.Data and d.Data.Name then return d.Data.Name end
    end
    local d2 = IU("GetItemDataFromItemType", category, id)
    if d2 and d2.Data and d2.Data.Name then return d2.Data.Name end
    local d3 = IU("GetItemData", id)
    if d3 and d3.Data and d3.Data.Name then return d3.Data.Name end
    return tostring(id)
end

function InventoryWatcher:_fmtWeight(w)
    if not w then return nil end
    if StringLib and StringLib.AddWeight then
        local ok, txt = pcall(function() return StringLib:AddWeight(w) end)
        if ok and txt then return txt end
    end
    return tostring(w).."kg"
end

function InventoryWatcher:_classifyEntry(hintKey, entry)
    -- Hasil akhir: "Items" | "Fishes" | "Potions" | "Baits" | "Fishing Rods"
    if not entry then return "Items" end
    local id = entry.Id or entry.id

    if hintKey == "Potions" then
        local d = IU("GetPotionData", id)
        if d then return "Potions" end
    elseif hintKey == "Baits" then
        local d = IU("GetBaitData", id)
        if d then return "Baits" end
    elseif hintKey == "Fishing Rods" then
        local d = IU("GetItemData", id)
        if d and d.Data and d.Data.Type == "Fishing Rods" then return "Fishing Rods" end
    end

    -- Strong heuristic untuk ikan
    if entry.Metadata and entry.Metadata.Weight then return "Fishes" end

    -- Resolver per-type
    local df = IU("GetItemDataFromItemType", "Fishes", id)
    if df and df.Data and df.Data.Type == "Fishes" then return "Fishes" end
    local di = IU("GetItemDataFromItemType", "Items", id)
    if di and di.Data and di.Data.Type == "Items" then return "Items" end

    -- Generic fallback
    local g = IU("GetItemData", id)
    if g and g.Data and g.Data.Type then
        local typ = tostring(g.Data.Type)
        if typ == "Fishes" or typ == "Items" or typ == "Potions" or typ == "Baits" or typ == "Fishing Rods" then
            return typ
        end
    end

    -- fallback terakhir
    return "Items"
end

-- Kumpulkan typed snapshot on-the-fly untuk dump / public API typed
function InventoryWatcher:_collectTyped()
    local typed = { Items={}, Fishes={}, Potions={}, Baits={}, ["Fishing Rods"]={} }
    for _, key in ipairs(KNOWN_KEYS) do
        local arr = self._snap[key]
        for _, entry in ipairs(arr) do
            local typ = self:_classifyEntry(key, entry)
            table.insert(typed[typ], entry)
        end
    end
    return typed
end

function InventoryWatcher:_recount()
    local ok, total = pcall(function()
        return self._data and Constants:CountInventorySize(self._data) or 0
    end)
    self._total = ok and total or 0
    self._max   = Constants.MaxInventorySize or self._max or 0
end

function InventoryWatcher:_snapCategory(key)
    local arr = self:_get({"Inventory", key})
    if type(arr) == "table" then
        self._snap[key] = shallowCopyArray(arr)
    else
        self._snap[key] = {}
    end
end

function InventoryWatcher:_rebuildByType()
    for k in pairs(self._byType) do self._byType[k]=0 end
    for _, key in ipairs(KNOWN_KEYS) do
        local arr = self._snap[key]
        for _, entry in ipairs(arr) do
            local typ = self:_classifyEntry(key, entry)
            self._byType[typ] += 1
        end
    end
end

function InventoryWatcher:_notify()
    local free = math.max(0, (self._max or 0) - (self._total or 0))
    self._changed:Fire(self._total, self._max, free, self:getCountsByType())
end

function InventoryWatcher:_rescanAll()
    for _, key in ipairs(KNOWN_KEYS) do
        self:_snapCategory(key)
    end
    self:_recount()
    self:_rebuildByType()
    self:_notify()
end

function InventoryWatcher:_scanAndSubscribeAll()
    self:_rescanAll()

    for _,c in ipairs(self._conns) do pcall(function() c:Disconnect() end) end
    table.clear(self._conns)

    local function bindPath(key)
        local function onChange()
            self:_snapCategory(key)
            self:_recount()
            self:_rebuildByType()
            self:_notify()
        end
        table.insert(self._conns, self._data:OnChange({"Inventory", key}, onChange))
        table.insert(self._conns, self._data:OnArrayInsert({"Inventory", key}, onChange))
        table.insert(self._conns, self._data:OnArrayRemove({"Inventory", key}, onChange))
    end
    for _, key in ipairs(KNOWN_KEYS) do bindPath(key) end
end

function InventoryWatcher:_subscribeEquip()
    table.insert(self._conns, self._data:OnChange("EquippedItems", function(_, new)
        local set = {}
        if typeof(new)=="table" then for _,uuid in ipairs(new) do set[uuid]=true end end
        self._equipped.itemsSet = set
        self._equipSig:Fire(self._equipped.itemsSet, self._equipped.baitId)
    end))
    table.insert(self._conns, self._data:OnChange("EquippedBaitId", function(_, newId)
        self._equipped.baitId = newId
        self._equipSig:Fire(self._equipped.itemsSet, self._equipped.baitId)
    end))
end

-- ===== Public API =====
function InventoryWatcher:onReady(cb)
    if self._ready then task.defer(cb); return {Disconnect=function() end} end
    return self._readySig:Connect(cb)
end

function InventoryWatcher:onChanged(cb)  -- cb(total, max, free, byType)
    return self._changed:Connect(cb)
end

function InventoryWatcher:onEquipChanged(cb) -- cb(equippedSet, baitId)
    return self._equipSig:Connect(cb)
end

function InventoryWatcher:getCountsByType()
    local t = {}
    for k,v in pairs(self._byType) do t[k]=v end
    return t
end

-- RAW snapshot (langsung dari path Replion) – untuk debugging path asli
function InventoryWatcher:getSnapshotRaw(typeName)
    if typeName then
        return shallowCopyArray(self._snap[typeName] or {})
    else
        local out = {}
        for k,arr in pairs(self._snap) do out[k]=shallowCopyArray(arr) end
        return out
    end
end

-- TYPED snapshot (hasil klasifikasi) – inilah yang cocok dengan count kamu
function InventoryWatcher:getSnapshotTyped(typeName)
    local typed = self:_collectTyped()
    if typeName then
        return shallowCopyArray(typed[typeName] or {})
    else
        local out = {}
        for k,arr in pairs(typed) do out[k]=shallowCopyArray(arr) end
        return out
    end
end

function InventoryWatcher:isEquipped(uuid) return self._equipped.itemsSet[uuid] == true end
function InventoryWatcher:getEquippedBaitId() return self._equipped.baitId end

function InventoryWatcher:getTotals()
    local free = math.max(0,(self._max or 0)-(self._total or 0))
    return self._total or 0, self._max or 0, free
end

function InventoryWatcher:getAutoSellThreshold()
    local ok, val = pcall(function() return self._data:Get("AutoSellThreshold") end)
    return ok and val or nil
end

-- ===== Dump Helpers =====
-- Default: TYPED agar sinkron dengan counter
function InventoryWatcher:dumpCategory(category, limit)
    limit = tonumber(limit) or 200
    if not table.find(KNOWN_KEYS, category) then
        warn("[InventoryWatcher] dumpCategory: kategori tidak dikenal ->", tostring(category))
        return
    end
    local arr = self:getSnapshotTyped(category)
    print(("-- %s (%d) --"):format(category, #arr))
    for i, entry in ipairs(arr) do
        if i > limit then
            print(("... truncated at %d"):format(limit))
            break
        end
        local id    = entry.Id or entry.id
        local uuid  = entry.UUID or entry.Uuid or entry.uuid
        local meta  = entry.Metadata or {}
        local name  = self:_resolveName(category, id)

        if category == "Fishes" then
            local w  = self:_fmtWeight(meta.Weight)
            local v  = meta.VariantId or meta.Mutation or meta.Variant
            local sh = (meta.Shiny == true) and "★" or ""
            print(i, name, uuid or "-", w or "-", v or "-", sh)
        else
            print(i, name, uuid or "-")
        end
    end
end

-- Dump semua kategori (typed)
function InventoryWatcher:dumpAll(limit)
    for _, key in ipairs(KNOWN_KEYS) do
        self:dumpCategory(key, limit)
    end
end

-- Optional: lihat data mentah per path asli
function InventoryWatcher:dumpCategoryRaw(category, limit)
    limit = tonumber(limit) or 200
    if not table.find(KNOWN_KEYS, category) then
        warn("[InventoryWatcher] dumpCategoryRaw: kategori tidak dikenal ->", tostring(category))
        return
    end
    local arr = self:getSnapshotRaw(category)
    print(("-- RAW %s (%d) --"):format(category, #arr))
    for i, entry in ipairs(arr) do
        if i > limit then print(("... truncated at %d"):format(limit)) break end
        local id    = entry.Id or entry.id
        local uuid  = entry.UUID or entry.Uuid or entry.uuid
        local name  = self:_resolveName(category, id)
        print(i, name, uuid or "-")
    end
end

function InventoryWatcher:destroy()
    for _,c in ipairs(self._conns) do pcall(function() c:Disconnect() end) end
    table.clear(self._conns)
    self._changed:Destroy()
    self._equipSig:Destroy()
    self._readySig:Destroy()
end

return InventoryWatcher
