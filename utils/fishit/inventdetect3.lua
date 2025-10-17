-- inventory_watcher_patched.lua
-- v4: Patched for performance. Uses incremental updates instead of full rebuilds.
-- Adds onItemAdded signal for event-driven processing.

local InventoryWatcher = {}
InventoryWatcher.__index = InventoryWatcher

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Replion     = require(ReplicatedStorage.Packages.Replion)
local Constants   = require(ReplicatedStorage.Shared.Constants)
local ItemUtility = require(ReplicatedStorage.Shared.ItemUtility)

local StringLib = nil
pcall(function() StringLib = require(ReplicatedStorage.Shared.StringLibrary) end)

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

    self._snap      = { Items={}, Fishes={}, Potions={}, Baits={}, ["Fishing Rods"]={} }
    self._byType    = { Items=0, Fishes=0, Potions=0, Baits=0, ["Fishing Rods"]=0 }
    self._favoritedCounts = { Items=0, Fishes=0, Potions=0, Baits=0, ["Fishing Rods"]=0 }

    self._equipped  = { itemsSet = {}, baitId = nil }
    self._changed   = mkSignal()
    self._equipSig  = mkSignal()
    self._favSig    = mkSignal()
    self._readySig  = mkSignal()
    self._itemAddedSig = mkSignal() -- NEW: For event-driven logic
    self._itemRemovedSig = mkSignal() -- NEW: For event-driven logic
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

local function IU(method, ...)
    local f = ItemUtility and ItemUtility[method]
    if type(f) == "function" then
        local ok, res = pcall(f, ItemUtility, ...)
        if ok then return res end
    end
    return nil
end

function InventoryWatcher:_resolveName(category, id)
    if not id then return "<?>" end
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

function InventoryWatcher:_isFavorited(entry)
    if not entry then return false end
    if entry.Favorited ~= nil then return entry.Favorited end
    if entry.favorited ~= nil then return entry.favorited end
    if entry.Metadata and entry.Metadata.Favorited ~= nil then return entry.Metadata.Favorited end
    if entry.Metadata and entry.Metadata.favorited ~= nil then return entry.Metadata.favorited end
    return false
end

function InventoryWatcher:_classifyEntry(hintKey, entry)
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

    if entry.Metadata and entry.Metadata.Weight then return "Fishes" end

    local df = IU("GetItemDataFromItemType", "Fishes", id)
    if df and df.Data and df.Data.Type == "Fishes" then return "Fishes" end
    local di = IU("GetItemDataFromItemType", "Items", id)
    if di and di.Data and di.Data.Type == "Items" then return "Items" end

    local g = IU("GetItemData", id)
    if g and g.Data and g.Data.Type then
        local typ = tostring(g.Data.Type)
        if typ == "Fishes" or typ == "Items" or typ == "Potions" or typ == "Baits" or typ == "Fishing Rods" then
            return typ
        end
    end
    return "Items"
end

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

-- OPTIMIZED: This is now only called ONCE at the start.
function InventoryWatcher:_rebuildByType()
    for k in pairs(self._byType) do self._byType[k]=0 end
    for k in pairs(self._favoritedCounts) do self._favoritedCounts[k]=0 end
    
    for _, key in ipairs(KNOWN_KEYS) do
        local arr = self._snap[key]
        for _, entry in ipairs(arr) do
            local typ = self:_classifyEntry(key, entry)
            self._byType[typ] = (self._byType[typ] or 0) + 1
            
            if self:_isFavorited(entry) then
                self._favoritedCounts[typ] = (self._favoritedCounts[typ] or 0) + 1
            end
        end
    end
end

function InventoryWatcher:_notify()
    local free = math.max(0, (self._max or 0) - (self._total or 0))
    self._changed:Fire(self._total, self._max, free, self:getCountsByType())
    self._favSig:Fire(self:getFavoritedCounts())
end

-- OPTIMIZED: This is the initial full scan.
function InventoryWatcher:_rescanAll()
    for _, key in ipairs(KNOWN_KEYS) do
        self:_snapCategory(key)
    end
    self:_recount()
    self:_rebuildByType()
    self:_notify()
end

-- OPTIMIZED: Subscribes with incremental update logic.
function InventoryWatcher:_scanAndSubscribeAll()
    self:_rescanAll() -- Full scan once at the start

    for _,c in ipairs(self._conns) do pcall(function() c:Disconnect() end) end
    table.clear(self._conns)

    for _, key in ipairs(KNOWN_KEYS) do
        -- OnChange is still a full rescan, for safety on complex updates
        table.insert(self._conns, self._data:OnChange({"Inventory", key}, function()
            self:_rescanAll()
        end))

        -- OnArrayInsert: Incremental ADD
        table.insert(self._conns, self._data:OnArrayInsert({"Inventory", key}, function(index, value)
            table.insert(self._snap[key], index, value)
            self:_recount()
            local typ = self:_classifyEntry(key, value)
            self._byType[typ] = (self._byType[typ] or 0) + 1
            if self:_isFavorited(value) then
                self._favoritedCounts[typ] = (self._favoritedCounts[typ] or 0) + 1
            end
            self:_notify()
            self._itemAddedSig:Fire(value, typ) -- Fire specific signal
        end))

        -- OnArrayRemove: Incremental REMOVE
        table.insert(self._conns, self._data:OnArrayRemove({"Inventory", key}, function(index, value)
            table.remove(self._snap[key], index)
            self:_recount()
            local typ = self:_classifyEntry(key, value)
            self._byType[typ] = math.max(0, (self._byType[typ] or 1) - 1)
            if self:_isFavorited(value) then
                self._favoritedCounts[typ] = math.max(0, (self._favoritedCounts[typ] or 1) - 1)
            end
            self:_notify()
            self._itemRemovedSig:Fire(value, typ) -- Fire specific signal
        end))
    end
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

function InventoryWatcher:onChanged(cb)
    return self._changed:Connect(cb)
end

function InventoryWatcher:onEquipChanged(cb)
    return self._equipSig:Connect(cb)
end

function InventoryWatcher:onFavoritedChanged(cb)
    return self._favSig:Connect(cb)
end

-- NEW: API for event-driven logic
function InventoryWatcher:onItemAdded(cb) -- cb(itemEntry, itemType)
    return self._itemAddedSig:Connect(cb)
end

function InventoryWatcher:onItemRemoved(cb) -- cb(itemEntry, itemType)
    return self._itemRemovedSig:Connect(cb)
end

function InventoryWatcher:getCountsByType()
    local t = {}
    for k,v in pairs(self._byType) do t[k]=v end
    return t
end

function InventoryWatcher:getFavoritedCounts()
    local t = {}
    for k,v in pairs(self._favoritedCounts) do t[k]=v end
    return t
end

function InventoryWatcher:getFavoritedItems(typeName)
    local typed = self:_collectTyped()
    local items = typed[typeName] or {}
    local favorited = {}
    
    for _, entry in ipairs(items) do
        if self:_isFavorited(entry) then
            table.insert(favorited, entry)
        end
    end
    
    return favorited
end

function InventoryWatcher:isFavoritedByUUID(uuid)
    if not uuid then return false end
    
    for _, key in ipairs(KNOWN_KEYS) do
        local arr = self._snap[key]
        for _, entry in ipairs(arr) do
            local entryUUID = entry.UUID or entry.Uuid or entry.uuid
            if entryUUID == uuid then
                return self:_isFavorited(entry)
            end
        end
    end
    
    return false
end

function InventoryWatcher:getSnapshotRaw(typeName)
    if typeName then
        return shallowCopyArray(self._snap[typeName] or {})
    else
        local out = {}
        for k,arr in pairs(self._snap) do out[k]=shallowCopyArray(arr) end
        return out
    end
end

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

function InventoryWatcher:destroy()
    for _,c in ipairs(self._conns) do pcall(function() c:Disconnect() end) end
    table.clear(self._conns)
    self._changed:Destroy()
    self._equipSig:Destroy()
    self._favSig:Destroy()
    self._readySig:Destroy()
    self._itemAddedSig:Destroy()
    self._itemRemovedSig:Destroy()
end

return InventoryWatcher
