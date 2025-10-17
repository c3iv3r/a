-- InventoryMonitor.lua
-- Ultra-optimized singleton untuk monitoring inventory tanpa freeze
-- Usage: local inv = InventoryMonitor:getShared()

local InventoryMonitor = {}
InventoryMonitor.__index = InventoryMonitor

local RS = game:GetService("ReplicatedStorage")
local Replion = require(RS.Packages.Replion)
local Constants = require(RS.Shared.Constants)
local ItemUtility = require(RS.Shared.ItemUtility)

local _instance = nil

-- Config
local BATCH_DELAY = 0.15
local CACHE_SIZE_LIMIT = 5000

-- Mini signal
local function signal()
    local e = Instance.new("BindableEvent")
    return {
        Fire = function(_, ...) e:Fire(...) end,
        Connect = function(_, f) return e.Event:Connect(f) end,
        Wait = function(_) return e.Event:Wait() end,
        Destroy = function(_) e:Destroy() end
    }
end

-- UUID extractor
local function uuid(e)
    return e and (e.UUID or e.Uuid or e.uuid)
end

-- Fast shallow copy
local function copy(t)
    local o = {}
    if type(t) == "table" then
        for i, v in ipairs(t) do o[i] = v end
    end
    return o
end

-- Swap remove (O(1) array remove)
local function swapRm(t, i)
    local n = #t
    if i >= 1 and i <= n then
        if i ~= n then t[i] = t[n] end
        t[n] = nil
    end
end

function InventoryMonitor._new()
    local self = setmetatable({}, InventoryMonitor)
    
    self._data = nil
    self._ready = false
    self._active = false
    
    -- Snapshots
    self._items = {}
    self._potions = {}
    self._baits = {}
    self._rods = {}
    
    -- Index maps (UUID -> position)
    self._idxI = {}
    self._idxP = {}
    self._idxB = {}
    self._idxR = {}
    
    -- Classification cache
    self._cache = {}
    self._cacheSize = 0
    
    -- Counters
    self._total = 0
    self._max = Constants.MaxInventorySize or 4500
    self._counts = {Fishes=0, Items=0, Potions=0, Baits=0, ["Fishing Rods"]=0}
    self._favs = {Fishes=0, Items=0, Potions=0, Baits=0, ["Fishing Rods"]=0}
    
    -- Equipment
    self._equipped = {}
    self._baitId = nil
    
    -- Signals
    self.Changed = signal()
    self.EquipChanged = signal()
    self.FavChanged = signal()
    self.Ready = signal()
    
    -- Batching
    self._pending = false
    self._batchCount = 0
    
    -- Connections
    self._conns = {}
    
    -- Initialize
    Replion.Client:AwaitReplion("Data", function(data)
        self._data = data
        self:_init()
        self._ready = true
        self.Ready:Fire()
    end)
    
    return self
end

function InventoryMonitor:getShared()
    if not _instance then
        _instance = InventoryMonitor._new()
    end
    return _instance
end

-- Classify dengan cache
function InventoryMonitor:_classify(key, e)
    if not e then return "Items" end
    
    local id = uuid(e)
    if id and self._cache[id] then
        return self._cache[id]
    end
    
    local t = "Items"
    local m = e.Metadata
    
    if m and m.Weight then
        t = "Fishes"
    elseif key == "Potions" then
        t = "Potions"
    elseif key == "Baits" then
        t = "Baits"
    elseif key == "Fishing Rods" then
        t = "Fishing Rods"
    else
        -- Fallback ke ItemUtility
        local d = ItemUtility:GetItemData(e.Id or e.id)
        if d and d.Data then
            local dt = d.Data.Type
            if dt == "Fishes" or dt == "Potions" or dt == "Baits" or dt == "Fishing Rods" then
                t = dt
            end
        end
    end
    
    -- Cache dengan limit
    if id then
        if self._cacheSize >= CACHE_SIZE_LIMIT then
            -- Clear 20% cache jika penuh
            local c = 0
            for k in pairs(self._cache) do
                self._cache[k] = nil
                c = c + 1
                if c >= CACHE_SIZE_LIMIT * 0.2 then break end
            end
            self._cacheSize = CACHE_SIZE_LIMIT * 0.8
        end
        self._cache[id] = t
        self._cacheSize = self._cacheSize + 1
    end
    
    return t
end

-- Check favorited
function InventoryMonitor:_fav(e)
    if not e then return false end
    if e.Favorited then return true end
    if e.favorited then return true end
    local m = e.Metadata
    if m then
        if m.Favorited then return true end
        if m.favorited then return true end
    end
    return false
end

-- Recount total dari Constants
function InventoryMonitor:_recount()
    local ok, n = pcall(function()
        return self._data and Constants:CountInventorySize(self._data) or 0
    end)
    self._total = ok and n or 0
end

-- Snapshot category
function InventoryMonitor:_snap(key, arr, idx)
    local ok, d = pcall(function()
        return self._data:Get({"Inventory", key})
    end)
    
    d = ok and d or {}
    if type(d) ~= "table" then d = {} end
    
    -- Clear & refill
    table.clear(arr)
    table.clear(idx)
    
    for i, e in ipairs(d) do
        arr[i] = e
        local id = uuid(e)
        if id then idx[id] = i end
    end
end

-- Full rebuild counts
function InventoryMonitor:_rebuild()
    for k in pairs(self._counts) do self._counts[k] = 0 end
    for k in pairs(self._favs) do self._favs[k] = 0 end
    
    local function add(t, e)
        self._counts[t] = self._counts[t] + 1
        if self:_fav(e) then
            self._favs[t] = self._favs[t] + 1
        end
    end
    
    for _, e in ipairs(self._items) do
        add(self:_classify("Items", e), e)
    end
    for _, e in ipairs(self._rods) do add("Fishing Rods", e) end
    for _, e in ipairs(self._potions) do add("Potions", e) end
    for _, e in ipairs(self._baits) do add("Baits", e) end
end

-- Incremental add
function InventoryMonitor:_add(key, e)
    local t = self:_classify(key, e)
    self._counts[t] = self._counts[t] + 1
    if self:_fav(e) then
        self._favs[t] = self._favs[t] + 1
    end
    if t == "Fishes" then
        self._total = self._total + 1
    end
end

-- Incremental remove
function InventoryMonitor:_remove(key, e)
    local t = self:_classify(key, e)
    self._counts[t] = math.max(0, self._counts[t] - 1)
    if self:_fav(e) then
        self._favs[t] = math.max(0, self._favs[t] - 1)
    end
    if t == "Fishes" then
        self._total = math.max(0, self._total - 1)
    end
    
    -- Cleanup cache
    local id = uuid(e)
    if id and self._cache[id] then
        self._cache[id] = nil
        self._cacheSize = math.max(0, self._cacheSize - 1)
    end
end

-- Batched notification
function InventoryMonitor:_notify()
    self._batchCount = self._batchCount + 1
    
    if self._pending then return end
    self._pending = true
    
    task.delay(BATCH_DELAY, function()
        if not self._active then return end
        
        self._pending = false
        
        if self._batchCount > 0 then
            self._batchCount = 0
            
            local free = math.max(0, self._max - self._total)
            self.Changed:Fire(self._total, self._max, free, self._counts)
            self.FavChanged:Fire(self._favs)
        end
    end)
end

-- Subscribe to path
function InventoryMonitor:_sub(key, arr, idx)
    local path = {"Inventory", key}
    
    -- Full change
    local c1 = self._data:OnChange(path, function()
        self:_snap(key, arr, idx)
        if self._active then
            self:_recount()
            self:_rebuild()
            self:_notify()
        end
    end)
    
    -- Insert
    local c2 = self._data:OnArrayInsert(path, function(_, e)
        table.insert(arr, e)
        local id = uuid(e)
        if id then idx[id] = #arr end
        
        if self._active then
            self:_add(key, e)
            self:_notify()
        end
    end)
    
    -- Remove
    local c3 = self._data:OnArrayRemove(path, function(_, e)
        local id = uuid(e)
        local i = id and idx[id]
        local saved = nil
        
        if i then
            saved = arr[i]
            local lastId = uuid(arr[#arr])
            swapRm(arr, i)
            if id then idx[id] = nil end
            if lastId and i <= #arr then
                idx[lastId] = i
            end
        else
            for j, v in ipairs(arr) do
                if uuid(v) == id then
                    saved = v
                    i = j
                    break
                end
            end
            if i then
                swapRm(arr, i)
                if id then idx[id] = nil end
            end
        end
        
        if self._active and (saved or e) then
            self:_remove(key, saved or e)
            self:_notify()
        end
    end)
    
    table.insert(self._conns, c1)
    table.insert(self._conns, c2)
    table.insert(self._conns, c3)
end

-- Initialize
function InventoryMonitor:_init()
    -- Snapshot all
    self:_snap("Items", self._items, self._idxI)
    self:_snap("Potions", self._potions, self._idxP)
    self:_snap("Baits", self._baits, self._idxB)
    self:_snap("Fishing Rods", self._rods, self._idxR)
    
    self:_recount()
    self:_rebuild()
    
    -- Subscribe
    self:_sub("Items", self._items, self._idxI)
    self:_sub("Potions", self._potions, self._idxP)
    self:_sub("Baits", self._baits, self._idxB)
    self:_sub("Fishing Rods", self._rods, self._idxR)
    
    -- Equipment
    local c1 = self._data:OnChange("EquippedItems", function(_, new)
        table.clear(self._equipped)
        if type(new) == "table" then
            for _, id in ipairs(new) do
                self._equipped[id] = true
            end
        end
        if self._active then
            self.EquipChanged:Fire(self._equipped, self._baitId)
        end
    end)
    
    local c2 = self._data:OnChange("EquippedBaitId", function(_, new)
        self._baitId = new
        if self._active then
            self.EquipChanged:Fire(self._equipped, self._baitId)
        end
    end)
    
    table.insert(self._conns, c1)
    table.insert(self._conns, c2)
end

-- Public API
function InventoryMonitor:start()
    if self._active then return end
    self._active = true
    
    self:_recount()
    self:_rebuild()
    
    local free = math.max(0, self._max - self._total)
    self.Changed:Fire(self._total, self._max, free, self._counts)
    self.FavChanged:Fire(self._favs)
end

function InventoryMonitor:stop()
    if not self._active then return end
    self._active = false
    self._pending = false
end

function InventoryMonitor:onReady(cb)
    if self._ready then
        task.defer(cb)
        return {Disconnect = function() end}
    end
    return self.Ready:Connect(cb)
end

function InventoryMonitor:getTotals()
    local free = math.max(0, self._max - self._total)
    return self._total, self._max, free
end

function InventoryMonitor:getCounts()
    local t = {}
    for k, v in pairs(self._counts) do t[k] = v end
    return t
end

function InventoryMonitor:getFavCounts()
    local t = {}
    for k, v in pairs(self._favs) do t[k] = v end
    return t
end

function InventoryMonitor:getSnapshot(typ)
    if typ == "Fishes" then
        local out = {}
        for _, e in ipairs(self._items) do
            if self:_classify("Items", e) == "Fishes" then
                table.insert(out, e)
            end
        end
        return out
    elseif typ == "Items" then
        return copy(self._items)
    elseif typ == "Potions" then
        return copy(self._potions)
    elseif typ == "Baits" then
        return copy(self._baits)
    elseif typ == "Fishing Rods" then
        return copy(self._rods)
    else
        return {
            Items = copy(self._items),
            Potions = copy(self._potions),
            Baits = copy(self._baits),
            ["Fishing Rods"] = copy(self._rods),
            Fishes = self:getSnapshot("Fishes")
        }
    end
end

function InventoryMonitor:getFavorited(typ)
    local out = {}
    
    if typ == "Fishes" then
        for _, e in ipairs(self._items) do
            if self:_classify("Items", e) == "Fishes" and self:_fav(e) then
                table.insert(out, e)
            end
        end
    elseif typ == "Items" then
        for _, e in ipairs(self._items) do
            if self:_fav(e) then table.insert(out, e) end
        end
    elseif typ == "Potions" then
        for _, e in ipairs(self._potions) do
            if self:_fav(e) then table.insert(out, e) end
        end
    elseif typ == "Baits" then
        for _, e in ipairs(self._baits) do
            if self:_fav(e) then table.insert(out, e) end
        end
    elseif typ == "Fishing Rods" then
        for _, e in ipairs(self._rods) do
            if self:_fav(e) then table.insert(out, e) end
        end
    end
    
    return out
end

function InventoryMonitor:isEquipped(id)
    return self._equipped[id] == true
end

function InventoryMonitor:getEquippedBait()
    return self._baitId
end

function InventoryMonitor:rescan()
    self:_snap("Items", self._items, self._idxI)
    self:_snap("Potions", self._potions, self._idxP)
    self:_snap("Baits", self._baits, self._idxB)
    self:_snap("Fishing Rods", self._rods, self._idxR)
    
    self:_recount()
    self:_rebuild()
    
    if self._active then
        local free = math.max(0, self._max - self._total)
        self.Changed:Fire(self._total, self._max, free, self._counts)
        self.FavChanged:Fire(self._favs)
    end
end

function InventoryMonitor:clearCache()
    table.clear(self._cache)
    self._cacheSize = 0
end

function InventoryMonitor:destroy()
    self:stop()
    for _, c in ipairs(self._conns) do
        pcall(function() c:Disconnect() end)
    end
    table.clear(self._conns)
    table.clear(self._cache)
    
    self.Changed:Destroy()
    self.EquipChanged:Destroy()
    self.FavChanged:Destroy()
    self.Ready:Destroy()
    
    if _instance == self then
        _instance = nil
    end
end

return InventoryMonitor