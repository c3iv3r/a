-- inventory_watcher_v5_optimized.lua
-- SINGLETON watcher dengan optimasi anti-freeze: cached classification, aggressive batching, minimal GC

local InventoryWatcher = {}
InventoryWatcher.__index = InventoryWatcher

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Replion     = require(ReplicatedStorage.Packages.Replion)
local Constants   = require(ReplicatedStorage.Shared.Constants)
local ItemUtility = require(ReplicatedStorage.Shared.ItemUtility)

local _sharedInstance = nil

local StringLib = nil
pcall(function() StringLib = require(ReplicatedStorage.Shared.StringLibrary) end)

local KNOWN_KEYS = { "Items", "Potions", "Baits", "Fishing Rods", "Fishes" }

local function mkSignal()
    local ev = Instance.new("BindableEvent")
    return {
        Fire=function(_,...) ev:Fire(...) end,
        Connect=function(_,f) return ev.Event:Connect(f) end,
        Destroy=function(_) ev:Destroy() end
    }
end

local function shallowCopyArray(t)
    local out = {}
    if type(t)=="table" then for i,v in ipairs(t) do out[i]=v end end
    return out
end

local function IU(method, ...)
    local f = ItemUtility and ItemUtility[method]
    if type(f) == "function" then
        local ok, res = pcall(f, ItemUtility, ...)
        if ok then return res end
    end
    return nil
end

-- ===== CLASS =====
function InventoryWatcher._create()
    local self = setmetatable({}, InventoryWatcher)

    self._data   = nil
    self._max    = Constants.MaxInventorySize or 0
    self._total  = 0

    self._snap   = { Items={}, Potions={}, Baits={}, ["Fishing Rods"]={}, Fishes={} }
    self._idx    = { Items={}, Potions={}, Baits={}, ["Fishing Rods"]={} }

    -- CACHE: UUID -> category type untuk fast lookup tanpa ItemUtility call
    self._typeCache = {}

    self._byType = { Items=0, Fishes=0, Potions=0, Baits=0, ["Fishing Rods"]=0 }
    self._favoritedCounts = { Items=0, Fishes=0, Potions=0, Baits=0, ["Fishing Rods"]=0 }

    self._equipped = { itemsSet = {}, baitId = nil }

    self._changed  = mkSignal()
    self._equipSig = mkSignal()
    self._favSig   = mkSignal()
    self._readySig = mkSignal()

    self._ready   = false
    self._running = false
    self._conns   = {}

    -- Batching: aggregate multiple rapid changes
    self._pendingNotify = false
    self._notifyDebounce = 0.1  -- slightly longer untuk mengurangi spam
    self._batchQueue = 0  -- counter perubahan dalam batch

    Replion.Client:AwaitReplion("Data", function(data)
        self._data = data
        self:_scanAndSubscribeAll()
        self:_subscribeEquip()
        self._ready = true
        self._readySig:Fire()
    end)

    return self
end

function InventoryWatcher.getShared(_typeHint)
    if not _sharedInstance then
        _sharedInstance = InventoryWatcher._create()
        print("[InventoryWatcher] Created SHARED instance")
    end
    _sharedInstance._consumers = (_sharedInstance._consumers or 0) + 1
    return _sharedInstance
end

function InventoryWatcher.new()
    warn("[InventoryWatcher] DEPRECATED: Use InventoryWatcher.getShared() instead.")
    local inst = InventoryWatcher._create()
    inst._consumers = 1
    return inst
end

-- ===== HELPERS =====
local function getUUID(entry)
    return (entry and (entry.UUID or entry.Uuid or entry.uuid)) or nil
end

function InventoryWatcher:_isFavorited(entry)
    if not entry then return false end
    if entry.Favorited ~= nil then return entry.Favorited end
    if entry.favorited ~= nil then return entry.favorited end
    local m = entry.Metadata
    if m then
        if m.Favorited ~= nil then return m.Favorited end
        if m.favorited ~= nil then return m.favorited end
    end
    return false
end

-- OPTIMIZED: cache-aware classifier
function InventoryWatcher:_classifyEntry(hintKey, entry)
    if not entry then return "Items" end
    
    local uuid = getUUID(entry)
    if uuid and self._typeCache[uuid] then
        return self._typeCache[uuid]  -- INSTANT return dari cache
    end

    local typ = "Items"
    local meta = entry.Metadata
    if meta and meta.Weight ~= nil then
        typ = "Fishes"
    elseif hintKey == "Potions" then
        local d = IU("GetPotionData", entry.Id or entry.id)
        if d then typ = "Potions" end
    elseif hintKey == "Baits" then
        local d = IU("GetBaitData", entry.Id or entry.id)
        if d then typ = "Baits" end
    elseif hintKey == "Fishing Rods" then
        local d = IU("GetItemData", entry.Id or entry.id)
        if d and d.Data and d.Data.Type == "Fishing Rods" then typ = "Fishing Rods" end
    else
        local g = IU("GetItemData", entry.Id or entry.id)
        local t = g and g.Data and g.Data.Type
        if t == "Fishes" or t == "Potions" or t == "Baits" or t == "Fishing Rods" then
            typ = t
        end
    end

    if uuid then self._typeCache[uuid] = typ end  -- CACHE result
    return typ
end

function InventoryWatcher:_resolveName(category, id)
    if not id then return "<?>" end
    if category == "Baits"   then local d = IU("GetBaitData", id)   if d and d.Data and d.Data.Name then return d.Data.Name end end
    if category == "Potions" then local d = IU("GetPotionData", id) if d and d.Data and d.Data.Name then return d.Data.Name end end
    if category == "Fishing Rods" or category == "Items" or category == "Fishes" then
        local d = IU("GetItemData", id); if d and d.Data and d.Data.Name then return d.Data.Name end
    end
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

function InventoryWatcher:_recount()
    local ok, total = pcall(function()
        return self._data and Constants:CountInventorySize(self._data) or 0
    end)
    self._total = ok and total or 0
    self._max   = Constants.MaxInventorySize or self._max or 0
end

function InventoryWatcher:_snapCategory(key)
    local ok, arr = pcall(function() return self._data and self._data:Get({"Inventory", key}) end)
    arr = ok and arr
    if type(arr) ~= "table" then arr = {} end
    self._snap[key] = shallowCopyArray(arr)

    local map = self._idx[key]; if map then for k in pairs(map) do map[k]=nil end end
    if map then
        for i, e in ipairs(self._snap[key]) do
            local u = getUUID(e); if u then map[u] = i end
        end
    end
end

function InventoryWatcher:_rebuildByType()
    for k in pairs(self._byType)          do self._byType[k]=0 end
    for k in pairs(self._favoritedCounts) do self._favoritedCounts[k]=0 end

    local function addCount(cat, entry)
        self._byType[cat] = (self._byType[cat] or 0) + 1
        if self:_isFavorited(entry) then
            self._favoritedCounts[cat] = (self._favoritedCounts[cat] or 0) + 1
        end
    end

    for _, e in ipairs(self._snap.Items) do
        addCount(self:_classifyEntry("Items", e), e)
    end
    for _, e in ipairs(self._snap["Fishing Rods"]) do addCount("Fishing Rods", e) end
    for _, e in ipairs(self._snap.Potions)        do addCount("Potions",      e) end
    for _, e in ipairs(self._snap.Baits)          do addCount("Baits",        e) end
end

-- OPTIMIZED: direct increment tanpa rebuild
function InventoryWatcher:_incrementEntry(hintKey, entry)
    local typ = self:_classifyEntry(hintKey, entry)
    self._byType[typ] = (self._byType[typ] or 0) + 1
    if self:_isFavorited(entry) then
        self._favoritedCounts[typ] = (self._favoritedCounts[typ] or 0) + 1
    end
    if typ == "Fishes" then
        self._total = (self._total or 0) + 1
    end
end

function InventoryWatcher:_decrementEntry(hintKey, entry)
    local typ = self:_classifyEntry(hintKey, entry)
    self._byType[typ] = math.max(0, (self._byType[typ] or 0) - 1)
    if self:_isFavorited(entry) then
        self._favoritedCounts[typ] = math.max(0, (self._favoritedCounts[typ] or 0) - 1)
    end
    if typ == "Fishes" then
        self._total = math.max(0, (self._total or 0) - 1)
    end
    
    -- Cleanup cache untuk entry yang dihapus
    local uuid = getUUID(entry)
    if uuid then self._typeCache[uuid] = nil end
end

-- OPTIMIZED: aggressive batching
function InventoryWatcher:_scheduleNotify()
    self._batchQueue = self._batchQueue + 1
    
    if self._pendingNotify then return end
    self._pendingNotify = true
    
    task.delay(self._notifyDebounce, function()
        if not self._running then return end
        self._pendingNotify = false
        
        -- Only fire jika ada changes dalam batch
        if self._batchQueue > 0 then
            self._batchQueue = 0
            local free = math.max(0, (self._max or 0) - (self._total or 0))
            self._changed:Fire(self._total, self._max, free, self:getCountsByType())
            self._favSig:Fire(self:getFavoritedCounts())
        end
    end)
end

function InventoryWatcher:_rescanAll()
    self:_snapCategory("Items")
    self:_snapCategory("Potions")
    self:_snapCategory("Baits")
    self:_snapCategory("Fishing Rods")

    self:_recount()
    self:_rebuildByType()
end

local function swapRemove(t, idx)
    local n = #t
    if idx < 1 or idx > n then return end
    if idx ~= n then
        t[idx] = t[n]
    end
    t[n] = nil
end

function InventoryWatcher:_scanAndSubscribeAll()
    self:_rescanAll()

    for _,c in ipairs(self._conns) do pcall(function() c:Disconnect() end) end
    table.clear(self._conns)

    local function bindPath(key)
        if key == "Fishes" then return end

        local function onInsert(_, newEntry)
            table.insert(self._snap[key], newEntry)
            local u = getUUID(newEntry)
            if u then self._idx[key][u] = #self._snap[key] end

            if self._running then
                self:_incrementEntry(key, newEntry)
                self:_scheduleNotify()
            end
        end

        local function onRemove(_, removedEntry)
            local u = getUUID(removedEntry)
            local idx = (u and self._idx[key][u]) or nil
            local saved
            if idx then
                saved = self._snap[key][idx]
                local lastU
                if #self._snap[key] > 0 then
                    local last = self._snap[key][#self._snap[key]]
                    lastU = getUUID(last)
                end
                swapRemove(self._snap[key], idx)
                if u then self._idx[key][u] = nil end
                if lastU and idx then
                    if idx <= #self._snap[key] then
                        self._idx[key][lastU] = idx
                    end
                end
            else
                for i,e in ipairs(self._snap[key]) do
                    local eu = getUUID(e)
                    if u and eu == u then saved = e; idx = i; break end
                end
                if idx then
                    swapRemove(self._snap[key], idx)
                    if u then self._idx[key][u] = nil end
                end
            end

            if self._running and (saved or removedEntry) then
                self:_decrementEntry(key, saved or removedEntry)
                self:_scheduleNotify()
            end
        end

        local function onFullChange()
            self:_snapCategory(key)
            if self._running then
                self:_recount()
                self:_rebuildByType()
                self:_scheduleNotify()
            end
        end

        table.insert(self._conns, self._data:OnChange({"Inventory", key}, onFullChange))
        table.insert(self._conns, self._data:OnArrayInsert({"Inventory", key}, onInsert))
        table.insert(self._conns, self._data:OnArrayRemove({"Inventory", key}, onRemove))
    end

    for _, key in ipairs(KNOWN_KEYS) do bindPath(key) end

    self._running = true
    local free = math.max(0, (self._max or 0) - (self._total or 0))
    self._changed:Fire(self._total, self._max, free, self:getCountsByType())
    self._favSig:Fire(self:getFavoritedCounts())
end

function InventoryWatcher:_subscribeEquip()
    table.insert(self._conns, self._data:OnChange("EquippedItems", function(_, new)
        local set = {}
        if typeof(new)=="table" then for _,uuid in ipairs(new) do set[uuid]=true end end
        self._equipped.itemsSet = set
        if self._running then self._equipSig:Fire(self._equipped.itemsSet, self._equipped.baitId) end
    end))

    table.insert(self._conns, self._data:OnChange("EquippedBaitId", function(_, newId)
        self._equipped.baitId = newId
        if self._running then self._equipSig:Fire(self._equipped.itemsSet, self._equipped.baitId) end
    end))
end

-- ===== LIFECYCLE =====
function InventoryWatcher:start()
    if self._running then return end
    self._running = true
    self:_recount()
    self:_rebuildByType()
    local free = math.max(0, (self._max or 0) - (self._total or 0))
    self._changed:Fire(self._total, self._max, free, self:getCountsByType())
    self._favSig:Fire(self:getFavoritedCounts())
    print("[InventoryWatcher] Started tracking")
end

function InventoryWatcher:stop()
    if not self._running then return end
    self._running = false
    self._pendingNotify = false
    print("[InventoryWatcher] Stopped tracking")
end

-- ===== PUBLIC API =====
function InventoryWatcher:onReady(cb)
    if self._ready then task.defer(cb); return {Disconnect=function() end} end
    return self._readySig:Connect(cb)
end

function InventoryWatcher:onChanged(cb)       return self._changed:Connect(cb)   end
function InventoryWatcher:onEquipChanged(cb)  return self._equipSig:Connect(cb)  end
function InventoryWatcher:onFavoritedChanged(cb) return self._favSig:Connect(cb) end

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
    local out = {}
    if typeName == "Fishes" then
        for _, e in ipairs(self._snap.Items) do
            if self:_classifyEntry("Items", e) == "Fishes" and self:_isFavorited(e) then
                table.insert(out, e)
            end
        end
    else
        for _, e in ipairs(self._snap[typeName or "Items"]) do
            if self:_isFavorited(e) then table.insert(out, e) end
        end
    end
    return out
end

function InventoryWatcher:getSnapshotRaw(typeName)
    if typeName then
        if typeName == "Fishes" then
            return self:getSnapshotTyped("Fishes")
        end
        return shallowCopyArray(self._snap[typeName] or {})
    else
        local out = {}
        for k,arr in pairs(self._snap) do
            if k == "Fishes" then
                out[k] = self:getSnapshotTyped("Fishes")
            else
                out[k] = shallowCopyArray(arr)
            end
        end
        return out
    end
end

function InventoryWatcher:getSnapshotTyped(typeName)
    if typeName then
        if typeName == "Fishes" then
            local list = {}
            for _, e in ipairs(self._snap.Items) do
                if self:_classifyEntry("Items", e) == "Fishes" then table.insert(list, e) end
            end
            return list
        else
            return shallowCopyArray(self._snap[typeName] or {})
        end
    else
        local out = {
            Items = shallowCopyArray(self._snap.Items),
            Potions = shallowCopyArray(self._snap.Potions),
            Baits = shallowCopyArray(self._snap.Baits),
            ["Fishing Rods"] = shallowCopyArray(self._snap["Fishing Rods"]),
            Fishes = {}
        }
        for _, e in ipairs(self._snap.Items) do
            if self:_classifyEntry("Items", e) == "Fishes" then table.insert(out.Fishes, e) end
        end
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

function InventoryWatcher:forceRescan()
    print("[InventoryWatcher] Force rescanning...")
    self:_rescanAll()
    if self._running then
        local free = math.max(0, (self._max or 0) - (self._total or 0))
        self._changed:Fire(self._total, self._max, free, self:getCountsByType())
        self._favSig:Fire(self:getFavoritedCounts())
    end
end

function InventoryWatcher:clearCache()
    table.clear(self._typeCache)
    print("[InventoryWatcher] Classification cache cleared")
end

function InventoryWatcher:release()
    self._consumers = math.max(0, (self._consumers or 0) - 1)
    if self._consumers == 0 then
        warn("[InventoryWatcher] No active consumers")
    end
end

function InventoryWatcher:dumpCategory(category, limit)
    limit = tonumber(limit) or 200
    local arr = self:getSnapshotTyped(category)
    print(("-- %s (%d) --"):format(category, #arr))
    for i, entry in ipairs(arr) do
        if i > limit then print(("... truncated at %d"):format(limit)) break end
        local id   = entry.Id or entry.id
        local uuid = getUUID(entry)
        local name = self:_resolveName(category, id)
        local fav  = self:_isFavorited(entry) and "★" or ""
        if category == "Fishes" then
            local m = entry.Metadata or {}
            local w  = self:_fmtWeight(m.Weight)
            local v  = m.VariantId or m.Mutation or m.Variant
            local sh = (m.Shiny == true) and "✦" or ""
            print(i, name, uuid or "-", w or "-", v or "-", sh, fav)
        else
            print(i, name, uuid or "-", fav)
        end
    end
end

function InventoryWatcher:dumpFavorited(category, limit)
    limit = tonumber(limit) or 200
    local cats = category and {category} or {"Fishes","Items","Potions","Baits","Fishing Rods"}
    for _, cat in ipairs(cats) do
        local list = self:getFavoritedItems(cat)
        if #list > 0 then
            print(("-- FAVORITED %s (%d) --"):format(cat, #list))
            for i, entry in ipairs(list) do
                if i > limit then print(("... truncated at %d"):format(limit)) break end
                local id   = entry.Id or entry.id
                local uuid = getUUID(entry)
                local name = self:_resolveName(cat, id)
                if cat == "Fishes" then
                    local m = entry.Metadata or {}
                    print(i, name, uuid or "-", self:_fmtWeight(m.Weight) or "-")
                else
                    print(i, name, uuid or "-")
                end
            end
        end
    end
end

function InventoryWatcher:dumpAll(limit)
    self:dumpCategory("Fishes", limit)
    self:dumpCategory("Items", limit)
    self:dumpCategory("Potions", limit)
    self:dumpCategory("Baits", limit)
    self:dumpCategory("Fishing Rods", limit)
end

function InventoryWatcher:destroy()
    self:stop()
    for _,c in ipairs(self._conns) do pcall(function() c:Disconnect() end) end
    table.clear(self._conns)
    table.clear(self._typeCache)
    self._changed:Destroy(); self._equipSig:Destroy(); self._favSig:Destroy(); self._readySig:Destroy()
    if _sharedInstance == self then _sharedInstance = nil end
end

return InventoryWatcher