-- fish_watcher.lua (PATCHED - no more ghost after batch replace)
-- Core idea: reconcile on any structural change to remove stale UUIDs

local FishWatcher = {}
FishWatcher.__index = FishWatcher

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Replion     = require(ReplicatedStorage.Packages.Replion)
local Constants   = require(ReplicatedStorage.Shared.Constants)
local ItemUtility = require(ReplicatedStorage.Shared.ItemUtility)

local StringLib = nil
pcall(function() StringLib = require(ReplicatedStorage.Shared.StringLibrary) end)

local SharedInstance = nil

local CATEGORIES = {"Items", "Fishes"} -- both are scanned; keep as-is

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

function FishWatcher.new()
    local self = setmetatable({}, FishWatcher)
    self._data = nil

    self._fishesByUUID = {}

    self._totalFish = 0
    self._totalFavorited = 0
    self._totalShiny = 0
    self._totalMutant = 0

    self._fishChanged = mkSignal()
    self._favChanged  = mkSignal()
    self._readySig    = mkSignal()
    self._ready       = false
    self._conns       = {}

    Replion.Client:AwaitReplion("Data", function(data)
        self._data = data
        self:_initialScan()
        self:_subscribeFishes()
        self._ready = true
        self._readySig:Fire()
    end)

    return self
end

function FishWatcher.getShared()
    if not SharedInstance then
        SharedInstance = FishWatcher.new()
    end
    return SharedInstance
end

function FishWatcher:_get(path)
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

function FishWatcher:_resolveName(id)
    if not id then return "<?>" end
    local d = IU("GetItemDataFromItemType", "Fishes", id)
    if d and d.Data and d.Data.Name then return d.Data.Name end
    local d2 = IU("GetItemData", id)
    if d2 and d2.Data and d2.Data.Name then return d2.Data.Name end
    return tostring(id)
end

function FishWatcher:_fmtWeight(w)
    if not w then return nil end
    if StringLib and StringLib.AddWeight then
        local ok, txt = pcall(function() return StringLib:AddWeight(w) end)
        if ok and txt then return txt end
    end
    return tostring(w).."kg"
end

function FishWatcher:_isFavorited(entry)
    if not entry then return false end
    if entry.Favorited ~= nil then return entry.Favorited end
    if entry.favorited ~= nil then return entry.favorited end
    if entry.Metadata and entry.Metadata.Favorited ~= nil then return entry.Metadata.Favorited end
    if entry.Metadata and entry.Metadata.favorited ~= nil then return entry.Metadata.favorited end
    return false
end

function FishWatcher:_isFish(entry)
    if not entry then return false end
    if entry.Metadata and entry.Metadata.Weight then return true end
    local id = entry.Id or entry.id
    local d = IU("GetItemData", id)
    if d and d.Data and d.Data.Type == "Fishes" then return true end
    return false
end

function FishWatcher:_createFishData(entry)
    local metadata = entry.Metadata or {}
    return {
        entry     = entry,
        id        = entry.Id or entry.id,
        uuid      = entry.UUID or entry.Uuid or entry.uuid,
        metadata  = metadata,
        name      = self:_resolveName(entry.Id or entry.id),
        favorited = self:_isFavorited(entry),
        shiny     = metadata.Shiny == true,
        mutant    = (metadata.VariantId ~= nil or metadata.Mutation ~= nil)
    }
end

-- === Counters helpers
function FishWatcher:_resetTotals()
    self._totalFish, self._totalFavorited, self._totalShiny, self._totalMutant = 0,0,0,0
end
function FishWatcher:_bumpTotalsOnAdd(fd)
    self._totalFish += 1
    if fd.shiny   then self._totalShiny += 1 end
    if fd.mutant  then self._totalMutant += 1 end
    if fd.favorited then self._totalFavorited += 1 end
end
function FishWatcher:_bumpTotalsOnRemove(fd)
    self._totalFish -= 1
    if fd.shiny   then self._totalShiny -= 1 end
    if fd.mutant  then self._totalMutant -= 1 end
    if fd.favorited then self._totalFavorited -= 1 end
end

-- === Initial load
function FishWatcher:_initialScan()
    table.clear(self._fishesByUUID)
    self:_resetTotals()

    for _, key in ipairs(CATEGORIES) do
        local arr = self:_get({"Inventory", key})
        if type(arr) == "table" then
            for _, entry in ipairs(arr) do
                if self:_isFish(entry) then
                    local fd   = self:_createFishData(entry)
                    local uuid = fd.uuid
                    if uuid and not self._fishesByUUID[uuid] then
                        self._fishesByUUID[uuid] = fd
                        self:_bumpTotalsOnAdd(fd)
                    end
                end
            end
        end
    end
end

-- === Incremental ops
function FishWatcher:_addFish(entry)
    if not self:_isFish(entry) then return end
    local fd = self:_createFishData(entry)
    local uuid = fd.uuid
    if not uuid or self._fishesByUUID[uuid] then return end
    self._fishesByUUID[uuid] = fd
    self:_bumpTotalsOnAdd(fd)
end

function FishWatcher:_removeFish(uuid)
    local fd = self._fishesByUUID[uuid]
    if not fd then return end
    self:_bumpTotalsOnRemove(fd)
    self._fishesByUUID[uuid] = nil
end

function FishWatcher:_updateFish(entry)
    if not self:_isFish(entry) then return end
    local uuid = entry.UUID or entry.Uuid or entry.uuid
    if not uuid then return end
    local old = self._fishesByUUID[uuid]
    if not old then
        self:_addFish(entry)
        return
    end
    local newd = self:_createFishData(entry)
    if old.favorited ~= newd.favorited then
        if newd.favorited then self._totalFavorited += 1 else self._totalFavorited -= 1 end
    end
    if old.shiny ~= newd.shiny then
        if newd.shiny then self._totalShiny += 1 else self._totalShiny -= 1 end
    end
    if old.mutant ~= newd.mutant then
        if newd.mutant then self._totalMutant += 1 else self._totalMutant -= 1 end
    end
    self._fishesByUUID[uuid] = newd
end

-- === RECONCILE: handles batch replace / Sell All
function FishWatcher:_reconcileFromState()
    -- 1) collect current-present UUIDs from state
    local present = {} :: { [string]: any }
    for _, key in ipairs(CATEGORIES) do
        local arr = self:_get({"Inventory", key})
        if type(arr) == "table" then
            for _, entry in ipairs(arr) do
                if self:_isFish(entry) then
                    local uuid = entry.UUID or entry.Uuid or entry.uuid
                    if uuid then present[uuid] = entry end
                end
            end
        end
    end

    -- 2) add/update present ones
    for uuid, entry in pairs(present) do
        if self._fishesByUUID[uuid] then
            self:_updateFish(entry)
        else
            self:_addFish(entry)
        end
    end

    -- 3) remove anything not present anymore (fixes "ghosts")
    local toRemove = {}
    for uuid,_ in pairs(self._fishesByUUID) do
        if not present[uuid] then table.insert(toRemove, uuid) end
    end
    for _,uuid in ipairs(toRemove) do
        self:_removeFish(uuid)
    end
end

function FishWatcher:_notify()
    self._fishChanged:Fire(self._totalFish, self._totalShiny, self._totalMutant)
    self._favChanged:Fire(self._totalFavorited)
end

function FishWatcher:_subscribeFishes()
    -- clear old
    for _,c in ipairs(self._conns) do pcall(function() c:Disconnect() end) end
    table.clear(self._conns)

    -- fine-grained array events (good for single adds/removes)
    for _, key in ipairs(CATEGORIES) do
        table.insert(self._conns, self._data:OnArrayInsert({"Inventory", key}, function(_, entry)
            if self:_isFish(entry) then
                self:_addFish(entry)
                self:_notify()
            end
        end))

        table.insert(self._conns, self._data:OnArrayRemove({"Inventory", key}, function(_, entryOrIndex)
            -- Some Replion impls pass index only; reconcile will catch either way
            local uuid = (type(entryOrIndex)=="table" and (entryOrIndex.UUID or entryOrIndex.Uuid or entryOrIndex.uuid)) or nil
            if uuid then
                self:_removeFish(uuid)
                self:_notify()
            else
                -- no UUID? do a cheap reconcile to be safe
                self:_reconcileFromState()
                self:_notify()
            end
        end))

        -- Any structural change (bulk replace / metadata mass update) → reconcile
        table.insert(self._conns, self._data:OnChange({"Inventory", key}, function()
            self:_reconcileFromState()
            self:_notify()
        end))
    end

    -- Bonus safety net: listen to whole Inventory node (batch replaces often land here)
    table.insert(self._conns, self._data:OnChange({"Inventory"}, function()
        self:_reconcileFromState()
        self:_notify()
    end))
end

function FishWatcher:onReady(cb)
    if self._ready then task.defer(cb); return {Disconnect=function() end} end
    return self._readySig:Connect(cb)
end

function FishWatcher:onFishChanged(cb)
    return self._fishChanged:Connect(cb)
end

function FishWatcher:onFavoritedChanged(cb)
    return self._favChanged:Connect(cb)
end

function FishWatcher:getAllFishes()
    local fishes = {}
    for _, fish in pairs(self._fishesByUUID) do
        table.insert(fishes, fish)
    end
    return fishes
end

function FishWatcher:getFavoritedFishes()
    local favorited = {}
    for _, fish in pairs(self._fishesByUUID) do
        if fish.favorited then
            table.insert(favorited, fish)
        end
    end
    return favorited
end

function FishWatcher:getFishesByWeight(minWeight, maxWeight)
    local filtered = {}
    for _, fish in pairs(self._fishesByUUID) do
        local w = fish.metadata.Weight
        if w then
            if (not minWeight or w >= minWeight) and (not maxWeight or w <= maxWeight) then
                table.insert(filtered, fish)
            end
        end
    end
    return filtered
end

function FishWatcher:getShinyFishes()
    local shinies = {}
    for _, fish in pairs(self._fishesByUUID) do
        if fish.shiny then
            table.insert(shinies, fish)
        end
    end
    return shinies
end

function FishWatcher:getMutantFishes()
    local mutants = {}
    for _, fish in pairs(self._fishesByUUID) do
        if fish.mutant then
            table.insert(mutants, fish)
        end
    end
    return mutants
end

function FishWatcher:getTotals()
    return self._totalFish, self._totalFavorited, self._totalShiny, self._totalMutant
end

function FishWatcher:isFavoritedByUUID(uuid)
    if not uuid then return false end
    local fish = self._fishesByUUID[uuid]
    return fish and fish.favorited or false
end

function FishWatcher:getFishByUUID(uuid)
    return self._fishesByUUID[uuid]
end

function FishWatcher:forceRefresh()
    self:_reconcileFromState()
    self:_notify()
end

function FishWatcher:dumpFishes(limit)
    limit = tonumber(limit) or 200
    print(("-- FISHES (%d total, %d favorited, %d shiny, %d mutant) --"):format(
        self._totalFish, self._totalFavorited, self._totalShiny, self._totalMutant
    ))

    local fishes = self:getAllFishes()
    for i, fish in ipairs(fishes) do
        if i > limit then
            print(("... truncated at %d"):format(limit))
            break
        end

        local w = self:_fmtWeight(fish.metadata.Weight)
        local v = fish.metadata.VariantId or fish.metadata.Mutation or "-"
        local sh = fish.shiny and "✦" or ""
        local fav = fish.favorited and "★" or ""

        print(i, fish.name, fish.uuid or "-", w or "-", v, sh, fav)
    end
end

function FishWatcher:dumpFavorited(limit)
    limit = tonumber(limit) or 200
    local favorited = self:getFavoritedFishes()
    print(("-- FAVORITED FISHES (%d) --"):format(#favorited))

    for i, fish in ipairs(favorited) do
        if i > limit then
            print(("... truncated at %d"):format(limit))
            break
        end

        local w = self:_fmtWeight(fish.metadata.Weight)
        local v = fish.metadata.VariantId or fish.metadata.Mutation or "-"
        local sh = fish.shiny and "✦" or ""

        print(i, fish.name, fish.uuid or "-", w or "-", v, sh)
    end
end

function FishWatcher:destroy()
    for _,c in ipairs(self._conns) do pcall(function() c:Disconnect() end) end
    table.clear(self._conns)
    self._fishChanged:Destroy()
    self._favChanged:Destroy()
    self._readySig:Destroy()
    if SharedInstance == self then
        SharedInstance = nil
    end
end

return FishWatcher
