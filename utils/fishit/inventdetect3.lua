-- inventory_watcher_v4_singleton.lua
-- SINGLETON: Shared instance across all scripts to prevent lag
-- OPTIMIZED: Incremental updates (+1/-1) with start/stop support

local InventoryWatcher = {}
InventoryWatcher.__index = InventoryWatcher

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Replion     = require(ReplicatedStorage.Packages.Replion)
local Constants   = require(ReplicatedStorage.Shared.Constants)
local ItemUtility = require(ReplicatedStorage.Shared.ItemUtility)

-- SINGLETON: Shared instance
local _sharedInstance = nil

-- Optional: StringLibrary buat format berat
local StringLib = nil
pcall(function() StringLib = require(ReplicatedStorage.Shared.StringLibrary) end)

-- Kategori yang diketahui oleh game
local KNOWN_KEYS = { "Items", "Fishes", "Potions", "Baits", "Fishing Rods" }

local function mkSignal()
    local ev = Instance.new("BindableEvent")
    return {
        Fire=function(_,...) ev:Fire(...) end,
        Connect=function(_,f) return ev.Event:Connect(f) end,
        Destroy=function(_) ev:Destroy() end
    }
end

-- INTERNAL: Constructor (jangan panggil langsung)
function InventoryWatcher._create()
    local self = setmetatable({}, InventoryWatcher)
    self._data      = nil
    self._max       = Constants.MaxInventorySize or 0

    -- RAW snapshot (langsung dari path Replion)
    self._snap      = { Items={}, Fishes={}, Potions={}, Baits={}, ["Fishing Rods"]={} }

    -- Aggregat hasil klasifikasi (TYPED) untuk hitungan cepat
    self._byType    = { Items=0, Fishes=0, Potions=0, Baits=0, ["Fishing Rods"]=0 }
    
    -- Track favorited counts
    self._favoritedCounts = { Items=0, Fishes=0, Potions=0, Baits=0, ["Fishing Rods"]=0 }

    self._equipped  = { itemsSet = {}, baitId = nil }
    self._changed   = mkSignal()  -- (total,max,free,byType)
    self._equipSig  = mkSignal()  -- (equippedSet, baitId)
    self._favSig    = mkSignal()  -- (favoritedCounts)
    self._readySig  = mkSignal()
    self._ready     = false
    self._running   = false  -- Track if watcher is active
    self._conns     = {}
    
    -- Track active consumers (for auto cleanup)
    self._consumers = 0

    -- Debounce mechanism
    self._pendingNotify = false
    self._notifyDebounce = 0.05  -- 50ms debounce

    Replion.Client:AwaitReplion("Data", function(data)
        self._data = data
        self:_scanAndSubscribeAll()
        self:_subscribeEquip()
        self._ready = true
        self._readySig:Fire()
    end)

    return self
end

-- PUBLIC: Get shared instance (SINGLETON)
function InventoryWatcher.getShared()
    if not _sharedInstance then
        _sharedInstance = InventoryWatcher._create()
        print("[InventoryWatcher] Created SHARED instance")
    end
    _sharedInstance._consumers += 1
    print(("[InventoryWatcher] Active consumers: %d"):format(_sharedInstance._consumers))
    return _sharedInstance
end

-- LEGACY SUPPORT: new() tetap bisa dipake tapi kasih warning
function InventoryWatcher.new()
    warn("[InventoryWatcher] DEPRECATED: Use InventoryWatcher.getShared() instead to prevent lag!")
    warn("[InventoryWatcher] Creating separate instance (NOT recommended for production)")
    local instance = InventoryWatcher._create()
    instance._consumers = 1
    return instance
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

-- Check if entry is favorited
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

-- FULL REBUILD (only used on init or manual rescan)
function InventoryWatcher:_rebuildByType()
    for k in pairs(self._byType) do self._byType[k]=0 end
    for k in pairs(self._favoritedCounts) do self._favoritedCounts[k]=0 end
    
    for _, key in ipairs(KNOWN_KEYS) do
        local arr = self._snap[key]
        for _, entry in ipairs(arr) do
            local typ = self:_classifyEntry(key, entry)
            self._byType[typ] += 1
            
            if self:_isFavorited(entry) then
                self._favoritedCounts[typ] += 1
            end
        end
    end
end

-- INCREMENTAL UPDATE - Add single entry (+1)
function InventoryWatcher:_incrementEntry(hintKey, entry)
    if not entry then return end
    local typ = self:_classifyEntry(hintKey, entry)
    self._byType[typ] = (self._byType[typ] or 0) + 1
    
    if self:_isFavorited(entry) then
        self._favoritedCounts[typ] = (self._favoritedCounts[typ] or 0) + 1
    end
end

-- INCREMENTAL UPDATE - Remove single entry (-1)
function InventoryWatcher:_decrementEntry(hintKey, entry)
    if not entry then return end
    local typ = self:_classifyEntry(hintKey, entry)
    self._byType[typ] = math.max(0, (self._byType[typ] or 0) - 1)
    
    if self:_isFavorited(entry) then
        self._favoritedCounts[typ] = math.max(0, (self._favoritedCounts[typ] or 0) - 1)
    end
end

-- Debounced notify
function InventoryWatcher:_scheduleNotify()
    if self._pendingNotify then return end
    self._pendingNotify = true
    
    task.delay(self._notifyDebounce, function()
        if not self._running then return end
        self._pendingNotify = false
        self:_notify()
    end)
end

function InventoryWatcher:_notify()
    local free = math.max(0, (self._max or 0) - (self._total or 0))
    self._changed:Fire(self._total, self._max, free, self:getCountsByType())
    self._favSig:Fire(self:getFavoritedCounts())
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
        -- OnChange: Full array changed (fallback ke rebuild)
        local function onFullChange()
            -- ALWAYS update snapshot, tapi notify cuma kalo running
            self:_snapCategory(key)
            self:_recount()
            
            if self._running then
                self:_rebuildByType()
                self:_scheduleNotify()
            end
        end
        
        -- OnArrayInsert: Item added (+1 increment)
        local function onInsert(_, newEntry)
            -- ALWAYS update snapshot
            table.insert(self._snap[key], newEntry)
            self:_recount()
            
            -- INCREMENTAL update cuma kalo running
            if self._running then
                self:_incrementEntry(key, newEntry)
                self:_scheduleNotify()
            end
        end
        
        -- OnArrayRemove: Item removed (-1 decrement)
        local function onRemove(_, removedEntry)
            -- ALWAYS update snapshot (find and remove)
            local uuid = removedEntry.UUID or removedEntry.Uuid or removedEntry.uuid
            if uuid then
                for i, entry in ipairs(self._snap[key]) do
                    local entryUUID = entry.UUID or entry.Uuid or entry.uuid
                    if entryUUID == uuid then
                        table.remove(self._snap[key], i)
                        break
                    end
                end
            end
            self:_recount()
            
            -- INCREMENTAL update cuma kalo running
            if self._running then
                self:_decrementEntry(key, removedEntry)
                self:_scheduleNotify()
            end
        end
        
        table.insert(self._conns, self._data:OnChange({"Inventory", key}, onFullChange))
        table.insert(self._conns, self._data:OnArrayInsert({"Inventory", key}, onInsert))
        table.insert(self._conns, self._data:OnArrayRemove({"Inventory", key}, onRemove))
    end
    
    for _, key in ipairs(KNOWN_KEYS) do bindPath(key) end
    self._running = true  -- Auto-start on init
end

function InventoryWatcher:_subscribeEquip()
    table.insert(self._conns, self._data:OnChange("EquippedItems", function(_, new)
        -- ALWAYS track equipped items
        local set = {}
        if typeof(new)=="table" then for _,uuid in ipairs(new) do set[uuid]=true end end
        self._equipped.itemsSet = set
        
        -- Only fire event if running
        if self._running then
            self._equipSig:Fire(self._equipped.itemsSet, self._equipped.baitId)
        end
    end))
    table.insert(self._conns, self._data:OnChange("EquippedBaitId", function(_, newId)
        -- ALWAYS track equipped bait
        self._equipped.baitId = newId
        
        -- Only fire event if running
        if self._running then
            self._equipSig:Fire(self._equipped.itemsSet, self._equipped.baitId)
        end
    end))
end

-- ===== START/STOP METHODS =====
function InventoryWatcher:start()
    if self._running then return end
    self._running = true
    
    -- CRITICAL: Resync counter dengan snapshot setelah stop
    -- Karena snapshot tetap update walau watcher stopped
    self:_rebuildByType()
    self:_recount()
    
    print("[InventoryWatcher] Started tracking (resynced)")
    
    -- Fire initial state after resync
    self:_notify()
end

function InventoryWatcher:stop()
    if not self._running then return end
    self._running = false
    self._pendingNotify = false
    print("[InventoryWatcher] Stopped tracking")
end

function InventoryWatcher:isRunning()
    return self._running
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

function InventoryWatcher:onFavoritedChanged(cb) -- cb(favoritedCounts)
    return self._favSig:Connect(cb)
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

-- RAW snapshot (langsung dari path Replion)
function InventoryWatcher:getSnapshotRaw(typeName)
    if typeName then
        return shallowCopyArray(self._snap[typeName] or {})
    else
        local out = {}
        for k,arr in pairs(self._snap) do out[k]=shallowCopyArray(arr) end
        return out
    end
end

-- TYPED snapshot (hasil klasifikasi)
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

-- Manual rescan (if needed for debugging/sync issues)
function InventoryWatcher:forceRescan()
    print("[InventoryWatcher] Force rescanning inventory...")
    self:_rescanAll()
end

-- Release consumer (for proper cleanup tracking)
function InventoryWatcher:release()
    self._consumers = math.max(0, self._consumers - 1)
    print(("[InventoryWatcher] Released consumer. Remaining: %d"):format(self._consumers))
    
    -- Auto cleanup if no consumers (optional safety)
    if self._consumers == 0 then
        warn("[InventoryWatcher] No active consumers. Consider calling destroy() if done.")
    end
end

-- ===== Dump Helpers =====
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
        local fav   = self:_isFavorited(entry) and "★" or ""

        if category == "Fishes" then
            local w  = self:_fmtWeight(meta.Weight)
            local v  = meta.VariantId or meta.Mutation or meta.Variant
            local sh = (meta.Shiny == true) and "✦" or ""
            print(i, name, uuid or "-", w or "-", v or "-", sh, fav)
        else
            print(i, name, uuid or "-", fav)
        end
    end
end

function InventoryWatcher:dumpFavorited(category, limit)
    limit = tonumber(limit) or 200
    if category and not table.find(KNOWN_KEYS, category) then
        warn("[InventoryWatcher] dumpFavorited: kategori tidak dikenal ->", tostring(category))
        return
    end
    
    local categories = category and {category} or KNOWN_KEYS
    
    for _, cat in ipairs(categories) do
        local favorited = self:getFavoritedItems(cat)
        if #favorited > 0 then
            print(("-- FAVORITED %s (%d) --"):format(cat, #favorited))
            for i, entry in ipairs(favorited) do
                if i > limit then
                    print(("... truncated at %d"):format(limit))
                    break
                end
                local id    = entry.Id or entry.id
                local uuid  = entry.UUID or entry.Uuid or entry.uuid
                local name  = self:_resolveName(cat, id)
                
                if cat == "Fishes" then
                    local meta = entry.Metadata or {}
                    local w  = self:_fmtWeight(meta.Weight)
                    print(i, name, uuid or "-", w or "-")
                else
                    print(i, name, uuid or "-")
                end
            end
        end
    end
end

function InventoryWatcher:dumpAll(limit)
    for _, key in ipairs(KNOWN_KEYS) do
        self:dumpCategory(key, limit)
    end
end

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
        local fav   = self:_isFavorited(entry) and "★" or ""
        print(i, name, uuid or "-", fav)
    end
end

function InventoryWatcher:destroy()
    self:stop()
    
    -- Disconnect all listeners
    for _,c in ipairs(self._conns) do pcall(function() c:Disconnect() end) end
    table.clear(self._conns)
    
    -- Destroy signals
    self._changed:Destroy()
    self._equipSig:Destroy()
    self._favSig:Destroy()
    self._readySig:Destroy()
    
    -- Clear singleton if this is the shared instance
    if _sharedInstance == self then
        _sharedInstance = nil
        print("[InventoryWatcher] Destroyed SHARED instance")
    end
end

return InventoryWatcher