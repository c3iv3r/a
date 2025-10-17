-- inventory_watcher_v4_optimized.lua
-- Optimized: Singleton, Incremental updates, Fishes & Items only, NO REBUILD on changes

local InventoryWatcher = {}
InventoryWatcher.__index = InventoryWatcher

local _sharedInstance = nil

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Replion     = require(ReplicatedStorage.Packages.Replion)
local Constants   = require(ReplicatedStorage.Shared.Constants)
local ItemUtility = require(ReplicatedStorage.Shared.ItemUtility)

local StringLib = nil
pcall(function() StringLib = require(ReplicatedStorage.Shared.StringLibrary) end)

-- ONLY track Fishes and Items
local TRACKED_KEYS = { "Fishes", "Items" }

local function mkSignal()
    local ev = Instance.new("BindableEvent")
    return {
        Fire=function(_,...) ev:Fire(...) end,
        Connect=function(_,f) return ev.Event:Connect(f) end,
        Destroy=function(_) ev:Destroy() end
    }
end

-- Singleton accessor - MAIN ENTRY POINT
function InventoryWatcher.getShared()
    if not _sharedInstance then
        _sharedInstance = InventoryWatcher._new()
    end
    return _sharedInstance
end

function InventoryWatcher._new()
    local self = setmetatable({}, InventoryWatcher)
    self._data = nil
    self._max = Constants.MaxInventorySize or 0

    -- Storage dengan UUID lookup untuk O(1) access
    self._items = {}  -- [uuid] = entry
    self._fishes = {} -- [uuid] = entry
    
    -- Counters (incremental only)
    self._counts = { Items=0, Fishes=0 }
    self._favoritedCounts = { Items=0, Fishes=0 }
    
    self._total = 0
    self._equipped = { itemsSet = {}, baitId = nil }
    self._changed = mkSignal()
    self._equipSig = mkSignal()
    self._favSig = mkSignal()
    self._readySig = mkSignal()
    self._ready = false
    self._conns = {}

    Replion.Client:AwaitReplion("Data", function(data)
        self._data = data
        self:_initialBuild()  -- Build SEKALI di awal
        self:_setupIncrementalListeners()  -- Setup incremental listeners
        self._ready = true
        self._readySig:Fire()
    end)

    return self
end

-- ===== Helpers =====
local function IU(method, ...)
    local f = ItemUtility and ItemUtility[method]
    if type(f) == "function" then
        local ok, res = pcall(f, ItemUtility, ...)
        if ok then return res end
    end
    return nil
end

function InventoryWatcher:_get(path)
    local ok, res = pcall(function() return self._data and self._data:Get(path) end)
    return ok and res or nil
end

function InventoryWatcher:_isFavorited(entry)
    if not entry then return false end
    if entry.Favorited ~= nil then return entry.Favorited end
    if entry.favorited ~= nil then return entry.favorited end
    if entry.Metadata and entry.Metadata.Favorited ~= nil then return entry.Metadata.Favorited end
    if entry.Metadata and entry.Metadata.favorited ~= nil then return entry.Metadata.favorited end
    return false
end

function InventoryWatcher:_getUUID(entry)
    return entry.UUID or entry.Uuid or entry.uuid
end

function InventoryWatcher:_isFish(entry)
    if not entry then return false end
    -- Strong heuristic: weight = fish
    if entry.Metadata and entry.Metadata.Weight then return true end
    local id = entry.Id or entry.id
    local df = IU("GetItemDataFromItemType", "Fishes", id)
    if df and df.Data and df.Data.Type == "Fishes" then return true end
    return false
end

function InventoryWatcher:_resolveName(category, id)
    if not id then return "<?>" end
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

-- ===== INITIAL BUILD - Hanya SEKALI di awal =====
function InventoryWatcher:_initialBuild()
    self._items = {}
    self._fishes = {}
    self._counts = { Items=0, Fishes=0 }
    self._favoritedCounts = { Items=0, Fishes=0 }
    
    -- Scan Items
    local itemsArr = self:_get({"Inventory", "Items"}) or {}
    for _, entry in ipairs(itemsArr) do
        local uuid = self:_getUUID(entry)
        if uuid then
            -- Check if misplaced fish in Items category
            local isFish = self:_isFish(entry)
            if isFish then
                self._fishes[uuid] = entry
                self._counts.Fishes += 1
                if self:_isFavorited(entry) then
                    self._favoritedCounts.Fishes += 1
                end
            else
                self._items[uuid] = entry
                self._counts.Items += 1
                if self:_isFavorited(entry) then
                    self._favoritedCounts.Items += 1
                end
            end
        end
    end
    
    -- Scan Fishes
    local fishesArr = self:_get({"Inventory", "Fishes"}) or {}
    for _, entry in ipairs(fishesArr) do
        local uuid = self:_getUUID(entry)
        if uuid then
            self._fishes[uuid] = entry
            self._counts.Fishes += 1
            if self:_isFavorited(entry) then
                self._favoritedCounts.Fishes += 1
            end
        end
    end
    
    self:_recountTotal()
    print("[InventoryWatcher] Initial build complete - Items:", self._counts.Items, "Fishes:", self._counts.Fishes)
end

function InventoryWatcher:_recountTotal()
    local ok, total = pcall(function()
        return self._data and Constants:CountInventorySize(self._data) or 0
    end)
    self._total = ok and total or 0
    self._max = Constants.MaxInventorySize or self._max or 0
end

-- ===== INCREMENTAL UPDATES - NO REBUILD =====
function InventoryWatcher:_incrementalAdd(category, entry)
    if not entry then return end
    local uuid = self:_getUUID(entry)
    if not uuid then return end
    
    if category == "Items" then
        local isFish = self:_isFish(entry)
        if isFish then
            if not self._fishes[uuid] then
                self._fishes[uuid] = entry
                self._counts.Fishes += 1
                if self:_isFavorited(entry) then
                    self._favoritedCounts.Fishes += 1
                end
            end
        else
            if not self._items[uuid] then
                self._items[uuid] = entry
                self._counts.Items += 1
                if self:_isFavorited(entry) then
                    self._favoritedCounts.Items += 1
                end
            end
        end
    elseif category == "Fishes" then
        if not self._fishes[uuid] then
            self._fishes[uuid] = entry
            self._counts.Fishes += 1
            if self:_isFavorited(entry) then
                self._favoritedCounts.Fishes += 1
            end
        end
    end
end

function InventoryWatcher:_incrementalRemove(category, entry)
    if not entry then return end
    local uuid = self:_getUUID(entry)
    if not uuid then return end
    
    -- Check both storages
    if self._items[uuid] then
        if self:_isFavorited(self._items[uuid]) then
            self._favoritedCounts.Items -= 1
        end
        self._items[uuid] = nil
        self._counts.Items -= 1
    end
    
    if self._fishes[uuid] then
        if self:_isFavorited(self._fishes[uuid]) then
            self._favoritedCounts.Fishes -= 1
        end
        self._fishes[uuid] = nil
        self._counts.Fishes -= 1
    end
end

-- Update entry (e.g., favorited status changed) tanpa rebuild
function InventoryWatcher:_incrementalUpdate(uuid, newEntry)
    if not uuid or not newEntry then return end
    
    local oldEntry = self._items[uuid] or self._fishes[uuid]
    if not oldEntry then return end
    
    local wasFav = self:_isFavorited(oldEntry)
    local isNowFav = self:_isFavorited(newEntry)
    
    -- Update favorited count jika berubah
    if wasFav ~= isNowFav then
        local category = self._items[uuid] and "Items" or "Fishes"
        if isNowFav then
            self._favoritedCounts[category] += 1
        else
            self._favoritedCounts[category] -= 1
        end
    end
    
    -- Update entry reference
    if self._items[uuid] then
        self._items[uuid] = newEntry
    elseif self._fishes[uuid] then
        self._fishes[uuid] = newEntry
    end
end

function InventoryWatcher:_notify()
    local free = math.max(0, (self._max or 0) - (self._total or 0))
    self._changed:Fire(self._total, self._max, free, self:getCountsByType())
    self._favSig:Fire(self:getFavoritedCounts())
end

-- ===== SETUP INCREMENTAL LISTENERS =====
function InventoryWatcher:_setupIncrementalListeners()
    for _, category in ipairs(TRACKED_KEYS) do
        -- OnArrayInsert: HANYA increment, TIDAK rebuild
        table.insert(self._conns, self._data:OnArrayInsert({"Inventory", category}, function(_, index, entry)
            self:_incrementalAdd(category, entry)
            self:_recountTotal()
            self:_notify()
        end))
        
        -- OnArrayRemove: HANYA decrement, TIDAK rebuild
        table.insert(self._conns, self._data:OnArrayRemove({"Inventory", category}, function(_, index, entry)
            self:_incrementalRemove(category, entry)
            self:_recountTotal()
            self:_notify()
        end))
        
        -- OnChange: update individual entries (favorit, metadata, dll)
        table.insert(self._conns, self._data:OnChange({"Inventory", category}, function(_, newArr)
            if type(newArr) ~= "table" then return end
            -- Cek perubahan pada entries yang sudah ada
            for _, newEntry in ipairs(newArr) do
                local uuid = self:_getUUID(newEntry)
                if uuid then
                    self:_incrementalUpdate(uuid, newEntry)
                end
            end
            self:_notify()
        end))
    end
    
    -- Equipped items listener
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

-- ===== PUBLIC API =====
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

function InventoryWatcher:getCountsByType()
    return { 
        Items = self._counts.Items, 
        Fishes = self._counts.Fishes 
    }
end

function InventoryWatcher:getFavoritedCounts()
    return { 
        Items = self._favoritedCounts.Items, 
        Fishes = self._favoritedCounts.Fishes 
    }
end

function InventoryWatcher:getFavoritedItems(typeName)
    local storage = typeName == "Fishes" and self._fishes or self._items
    local favorited = {}
    
    for uuid, entry in pairs(storage) do
        if self:_isFavorited(entry) then
            table.insert(favorited, entry)
        end
    end
    
    return favorited
end

function InventoryWatcher:isFavoritedByUUID(uuid)
    if not uuid then return false end
    local entry = self._items[uuid] or self._fishes[uuid]
    return entry and self:_isFavorited(entry) or false
end

function InventoryWatcher:getSnapshot(typeName)
    local storage = typeName == "Fishes" and self._fishes or self._items
    local arr = {}
    for uuid, entry in pairs(storage) do
        table.insert(arr, entry)
    end
    return arr
end

function InventoryWatcher:isEquipped(uuid)
    return self._equipped.itemsSet[uuid] == true
end

function InventoryWatcher:getEquippedBaitId()
    return self._equipped.baitId
end

function InventoryWatcher:getTotals()
    local free = math.max(0,(self._max or 0)-(self._total or 0))
    return self._total or 0, self._max or 0, free
end

function InventoryWatcher:getAutoSellThreshold()
    local ok, val = pcall(function() return self._data:Get("AutoSellThreshold") end)
    return ok and val or nil
end

-- ===== DUMP HELPERS =====
function InventoryWatcher:dumpCategory(category, limit)
    limit = tonumber(limit) or 200
    local storage = category == "Fishes" and self._fishes or self._items
    local count = category == "Fishes" and self._counts.Fishes or self._counts.Items
    
    print(("-- %s (%d) --"):format(category, count))
    local i = 0
    for uuid, entry in pairs(storage) do
        i += 1
        if i > limit then
            print(("... truncated at %d"):format(limit))
            break
        end
        local id = entry.Id or entry.id
        local name = self:_resolveName(category, id)
        local fav = self:_isFavorited(entry) and "★" or ""
        
        if category == "Fishes" then
            local meta = entry.Metadata or {}
            local w = self:_fmtWeight(meta.Weight)
            local sh = (meta.Shiny == true) and "✦" or ""
            print(i, name, uuid or "-", w or "-", sh, fav)
        else
            print(i, name, uuid or "-", fav)
        end
    end
end

function InventoryWatcher:dumpFavorited(category, limit)
    limit = tonumber(limit) or 200
    local categories = category and {category} or {"Items", "Fishes"}
    
    for _, cat in ipairs(categories) do
        local favorited = self:getFavoritedItems(cat)
        if #favorited > 0 then
            print(("-- FAVORITED %s (%d) --"):format(cat, #favorited))
            for i, entry in ipairs(favorited) do
                if i > limit then
                    print(("... truncated at %d"):format(limit))
                    break
                end
                local id = entry.Id or entry.id
                local uuid = self:_getUUID(entry)
                local name = self:_resolveName(cat, id)
                
                if cat == "Fishes" then
                    local meta = entry.Metadata or {}
                    local w = self:_fmtWeight(meta.Weight)
                    print(i, name, uuid or "-", w or "-")
                else
                    print(i, name, uuid or "-")
                end
            end
        end
    end
end

function InventoryWatcher:dumpAll(limit)
    self:dumpCategory("Items", limit)
    self:dumpCategory("Fishes", limit)
end

function InventoryWatcher:destroy()
    for _,c in ipairs(self._conns) do pcall(function() c:Disconnect() end) end
    table.clear(self._conns)
    self._changed:Destroy()
    self._equipSig:Destroy()
    self._favSig:Destroy()
    self._readySig:Destroy()
    if _sharedInstance == self then
        _sharedInstance = nil
    end
end

return InventoryWatcher