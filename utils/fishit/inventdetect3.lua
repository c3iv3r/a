-- FishInventoryWatcher.lua
-- Singleton pattern untuk monitoring ONLY Fishes inventory
-- Menggunakan increment/decrement untuk tracking perubahan

local FishInventoryWatcher = {}
FishInventoryWatcher.__index = FishInventoryWatcher

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Replion     = require(ReplicatedStorage.Packages.Replion)
local Constants   = require(ReplicatedStorage.Shared.Constants)
local ItemUtility = require(ReplicatedStorage.Shared.ItemUtility)

-- Optional: StringLibrary untuk format berat
local StringLib = nil
pcall(function() StringLib = require(ReplicatedStorage.Shared.StringLibrary) end)

-- Singleton instance
local sharedInstance = nil

-- Signal helper
local function mkSignal()
    local ev = Instance.new("BindableEvent")
    return {
        Fire = function(_, ...) ev:Fire(...) end,
        Connect = function(_, f) return ev.Event:Connect(f) end,
        Destroy = function(_) ev:Destroy() end
    }
end

-- ===== Constructor (private) =====
local function createInstance()
    local self = setmetatable({}, FishInventoryWatcher)
    
    self._data = nil
    self._max = Constants.MaxInventorySize or 0
    
    -- Snapshot ikan (dari path {"Inventory", "Fishes"})
    self._fishes = {}  -- Array of fish entries
    
    -- Counts
    self._totalFish = 0
    self._favoritedFish = 0
    
    -- Signals
    self._changed = mkSignal()      -- (totalFish, favoritedFish)
    self._fishAdded = mkSignal()    -- (entry, newTotal)
    self._fishRemoved = mkSignal()  -- (entry, newTotal)
    self._favChanged = mkSignal()   -- (favoritedCount)
    self._readySig = mkSignal()
    
    self._ready = false
    self._conns = {}
    
    -- Initialize
    Replion.Client:AwaitReplion("Data", function(data)
        self._data = data
        self:_initializeFishes()
        self._ready = true
        self._readySig:Fire()
    end)
    
    return self
end

-- ===== Singleton Access =====
function FishInventoryWatcher.getShared()
    if not sharedInstance then
        sharedInstance = createInstance()
    end
    return sharedInstance
end

-- ===== Helpers =====
local function shallowCopyArray(t)
    local out = {}
    if type(t) == "table" then 
        for i, v in ipairs(t) do 
            out[i] = v 
        end 
    end
    return out
end

function FishInventoryWatcher:_get(path)
    local ok, res = pcall(function() 
        return self._data and self._data:Get(path) 
    end)
    return ok and res or nil
end

-- Safe ItemUtility call
local function IU(method, ...)
    local f = ItemUtility and ItemUtility[method]
    if type(f) == "function" then
        local ok, res = pcall(f, ItemUtility, ...)
        if ok then return res end
    end
    return nil
end

function FishInventoryWatcher:_resolveName(id)
    if not id then return "<?>" end
    
    local d = IU("GetItemDataFromItemType", "Fishes", id)
    if d and d.Data and d.Data.Name then 
        return d.Data.Name 
    end
    
    local d2 = IU("GetItemData", id)
    if d2 and d2.Data and d2.Data.Name then 
        return d2.Data.Name 
    end
    
    return tostring(id)
end

function FishInventoryWatcher:_fmtWeight(w)
    if not w then return nil end
    if StringLib and StringLib.AddWeight then
        local ok, txt = pcall(function() 
            return StringLib:AddWeight(w) 
        end)
        if ok and txt then return txt end
    end
    return tostring(w) .. "kg"
end

-- Check if fish entry is favorited
function FishInventoryWatcher:_isFavorited(entry)
    if not entry then return false end
    
    if entry.Favorited ~= nil then return entry.Favorited end
    if entry.favorited ~= nil then return entry.favorited end
    
    if entry.Metadata then
        if entry.Metadata.Favorited ~= nil then 
            return entry.Metadata.Favorited 
        end
        if entry.Metadata.favorited ~= nil then 
            return entry.Metadata.favorited 
        end
    end
    
    return false
end

-- Verify if entry is actually a fish
function FishInventoryWatcher:_isFish(entry)
    if not entry then return false end
    local id = entry.Id or entry.id
    
    -- Strong heuristic: fish memiliki Weight di Metadata
    if entry.Metadata and entry.Metadata.Weight then 
        return true 
    end
    
    -- Verify via ItemUtility
    local d = IU("GetItemDataFromItemType", "Fishes", id)
    if d and d.Data and d.Data.Type == "Fishes" then 
        return true 
    end
    
    return false
end

-- Count favorited fishes
function FishInventoryWatcher:_countFavorited()
    local count = 0
    for _, fish in ipairs(self._fishes) do
        if self:_isFavorited(fish) then
            count += 1
        end
    end
    return count
end

-- ===== Initialization =====
function FishInventoryWatcher:_initializeFishes()
    -- Load initial snapshot
    local arr = self:_get({"Inventory", "Fishes"})
    if type(arr) == "table" then
        self._fishes = shallowCopyArray(arr)
    else
        self._fishes = {}
    end
    
    -- Count totals
    self._totalFish = #self._fishes
    self._favoritedFish = self:_countFavorited()
    
    -- Subscribe to changes
    self:_subscribeToChanges()
    
    -- Notify ready
    self._changed:Fire(self._totalFish, self._favoritedFish)
end

function FishInventoryWatcher:_subscribeToChanges()
    -- Clear existing connections
    for _, c in ipairs(self._conns) do 
        pcall(function() c:Disconnect() end) 
    end
    table.clear(self._conns)
    
    -- OnArrayInsert: Fish added
    table.insert(self._conns, self._data:OnArrayInsert({"Inventory", "Fishes"}, function(_, index, entry)
        if not self:_isFish(entry) then return end
        
        table.insert(self._fishes, index, entry)
        self._totalFish += 1
        
        if self:_isFavorited(entry) then
            self._favoritedFish += 1
        end
        
        self._fishAdded:Fire(entry, self._totalFish)
        self._changed:Fire(self._totalFish, self._favoritedFish)
        self._favChanged:Fire(self._favoritedFish)
    end))
    
    -- OnArrayRemove: Fish removed
    table.insert(self._conns, self._data:OnArrayRemove({"Inventory", "Fishes"}, function(_, index, oldEntry)
        if not self:_isFish(oldEntry) then return end
        
        local wasFavorited = self:_isFavorited(oldEntry)
        
        table.remove(self._fishes, index)
        self._totalFish -= 1
        
        if wasFavorited then
            self._favoritedFish -= 1
        end
        
        self._fishRemoved:Fire(oldEntry, self._totalFish)
        self._changed:Fire(self._totalFish, self._favoritedFish)
        self._favChanged:Fire(self._favoritedFish)
    end))
    
    -- OnChange: Full refresh (fallback)
    table.insert(self._conns, self._data:OnChange({"Inventory", "Fishes"}, function(_, newArr)
        if type(newArr) == "table" then
            self._fishes = shallowCopyArray(newArr)
        else
            self._fishes = {}
        end
        
        self._totalFish = #self._fishes
        self._favoritedFish = self:_countFavorited()
        
        self._changed:Fire(self._totalFish, self._favoritedFish)
        self._favChanged:Fire(self._favoritedFish)
    end))
end

-- ===== Public API =====
function FishInventoryWatcher:onReady(cb)
    if self._ready then 
        task.defer(cb)
        return { Disconnect = function() end } 
    end
    return self._readySig:Connect(cb)
end

-- Subscribe to any fish count change
function FishInventoryWatcher:onChanged(cb)  -- cb(totalFish, favoritedFish)
    return self._changed:Connect(cb)
end

-- Subscribe to fish added
function FishInventoryWatcher:onFishAdded(cb)  -- cb(entry, newTotal)
    return self._fishAdded:Connect(cb)
end

-- Subscribe to fish removed
function FishInventoryWatcher:onFishRemoved(cb)  -- cb(entry, newTotal)
    return self._fishRemoved:Connect(cb)
end

-- Subscribe to favorited count change
function FishInventoryWatcher:onFavoritedChanged(cb)  -- cb(favoritedCount)
    return self._favChanged:Connect(cb)
end

-- Get current totals
function FishInventoryWatcher:getTotals()
    return self._totalFish, self._favoritedFish
end

function FishInventoryWatcher:getTotalFish()
    return self._totalFish
end

function FishInventoryWatcher:getFavoritedCount()
    return self._favoritedFish
end

-- Get snapshot
function FishInventoryWatcher:getSnapshot()
    return shallowCopyArray(self._fishes)
end

-- Get favorited fishes only
function FishInventoryWatcher:getFavoritedFishes()
    local favorited = {}
    for _, fish in ipairs(self._fishes) do
        if self:_isFavorited(fish) then
            table.insert(favorited, fish)
        end
    end
    return favorited
end

-- Check if specific fish is favorited by UUID
function FishInventoryWatcher:isFavoritedByUUID(uuid)
    if not uuid then return false end
    
    for _, fish in ipairs(self._fishes) do
        local entryUUID = fish.UUID or fish.Uuid or fish.uuid
        if entryUUID == uuid then
            return self:_isFavorited(fish)
        end
    end
    
    return false
end

-- Find fish by UUID
function FishInventoryWatcher:findFishByUUID(uuid)
    if not uuid then return nil end
    
    for _, fish in ipairs(self._fishes) do
        local entryUUID = fish.UUID or fish.Uuid or fish.uuid
        if entryUUID == uuid then
            return fish
        end
    end
    
    return nil
end

-- ===== Dump Helpers =====
function FishInventoryWatcher:dumpFishes(limit)
    limit = tonumber(limit) or 100
    
    print(("-- FISHES (%d total, %d favorited) --"):format(
        self._totalFish, 
        self._favoritedFish
    ))
    
    for i, fish in ipairs(self._fishes) do
        if i > limit then
            print(("... truncated at %d"):format(limit))
            break
        end
        
        local id = fish.Id or fish.id
        local uuid = fish.UUID or fish.Uuid or fish.uuid
        local meta = fish.Metadata or {}
        local name = self:_resolveName(id)
        local fav = self:_isFavorited(fish) and "★" or ""
        
        local w = self:_fmtWeight(meta.Weight)
        local v = meta.VariantId or meta.Mutation or meta.Variant
        local sh = (meta.Shiny == true) and "✦" or ""
        
        print(i, name, uuid or "-", w or "-", v or "-", sh, fav)
    end
end

function FishInventoryWatcher:dumpFavorited(limit)
    limit = tonumber(limit) or 100
    local favorited = self:getFavoritedFishes()
    
    print(("-- FAVORITED FISHES (%d) --"):format(#favorited))
    
    for i, fish in ipairs(favorited) do
        if i > limit then
            print(("... truncated at %d"):format(limit))
            break
        end
        
        local id = fish.Id or fish.id
        local uuid = fish.UUID or fish.Uuid or fish.uuid
        local meta = fish.Metadata or {}
        local name = self:_resolveName(id)
        
        local w = self:_fmtWeight(meta.Weight)
        local v = meta.VariantId or meta.Mutation or meta.Variant
        local sh = (meta.Shiny == true) and "✦" or ""
        
        print(i, name, uuid or "-", w or "-", v or "-", sh)
    end
end

-- ===== Cleanup =====
function FishInventoryWatcher:destroy()
    for _, c in ipairs(self._conns) do 
        pcall(function() c:Disconnect() end) 
    end
    table.clear(self._conns)
    
    self._changed:Destroy()
    self._fishAdded:Destroy()
    self._fishRemoved:Destroy()
    self._favChanged:Destroy()
    self._readySig:Destroy()
    
    if sharedInstance == self then
        sharedInstance = nil
    end
end

return FishInventoryWatcher