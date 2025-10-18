-- fish_watcher.lua (OPTIMIZED - No freeze, accurate tracking)
local FishWatcher = {}
FishWatcher.__index = FishWatcher

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Replion     = require(ReplicatedStorage.Packages.Replion)
local ItemUtility = require(ReplicatedStorage.Shared.ItemUtility)

local StringLib = nil
pcall(function() StringLib = require(ReplicatedStorage.Shared.StringLibrary) end)

local SharedInstance = nil

local function mkSignal()
    local ev = Instance.new("BindableEvent")
    return {
        Fire=function(_,...) ev:Fire(...) end,
        Connect=function(_,f) return ev.Event:Connect(f) end,
        Destroy=function(_) ev:Destroy() end
    }
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
    self._favChanged = mkSignal()
    self._readySig = mkSignal()
    self._ready = false
    self._conns = {}

    Replion.Client:AwaitReplion("Data", function(data)
        self._data = data
        self:_initialScan()
        self:_subscribeEvents()
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
    return entry.Favorited == true
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
        entry = entry,
        id = entry.Id or entry.id,
        uuid = entry.UUID or entry.Uuid or entry.uuid,
        metadata = metadata,
        name = self:_resolveName(entry.Id or entry.id),
        favorited = self:_isFavorited(entry),
        shiny = metadata.Shiny == true,
        mutant = (metadata.VariantId ~= nil or metadata.Mutation ~= nil)
    }
end

function FishWatcher:_initialScan()
    self._fishesByUUID = {}
    self._totalFish = 0
    self._totalFavorited = 0
    self._totalShiny = 0
    self._totalMutant = 0
    
    local categories = {"Items", "Fishes"}
    
    for _, key in ipairs(categories) do
        local arr = self:_get({"Inventory", key})
        if type(arr) == "table" then
            for _, entry in ipairs(arr) do
                if self:_isFish(entry) then
                    local fishData = self:_createFishData(entry)
                    local uuid = fishData.uuid
                    
                    if uuid then
                        self._fishesByUUID[uuid] = fishData
                        self._totalFish += 1
                        
                        if fishData.shiny then
                            self._totalShiny += 1
                        end
                        
                        if fishData.mutant then
                            self._totalMutant += 1
                        end
                        
                        if fishData.favorited then
                            self._totalFavorited += 1
                        end
                    end
                end
            end
        end
    end
end

function FishWatcher:_addFish(entry)
    if not self:_isFish(entry) then return end
    
    local fishData = self:_createFishData(entry)
    local uuid = fishData.uuid
    
    if not uuid or self._fishesByUUID[uuid] then return end
    
    self._fishesByUUID[uuid] = fishData
    self._totalFish += 1
    
    if fishData.shiny then
        self._totalShiny += 1
    end
    
    if fishData.mutant then
        self._totalMutant += 1
    end
    
    if fishData.favorited then
        self._totalFavorited += 1
    end
end

function FishWatcher:_removeFish(entry)
    local uuid = entry.UUID or entry.Uuid or entry.uuid
    if not uuid then return end
    
    local fishData = self._fishesByUUID[uuid]
    if not fishData then return end
    
    self._totalFish -= 1
    
    if fishData.shiny then
        self._totalShiny -= 1
    end
    
    if fishData.mutant then
        self._totalMutant -= 1
    end
    
    if fishData.favorited then
        self._totalFavorited -= 1
    end
    
    self._fishesByUUID[uuid] = nil
end

function FishWatcher:_updateFavorited(uuid, newFav)
    local fishData = self._fishesByUUID[uuid]
    if not fishData then return end
    
    local oldFav = fishData.favorited
    if oldFav == newFav then return end
    
    fishData.favorited = newFav
    
    if newFav then
        self._totalFavorited += 1
    else
        self._totalFavorited -= 1
    end
    
    -- ✅ Fire event AFTER update
    self._favChanged:Fire(self._totalFavorited)
end

function FishWatcher:_subscribeEvents()
    for _,c in ipairs(self._conns) do pcall(function() c:Disconnect() end) end
    table.clear(self._conns)
    
    local categories = {"Items", "Fishes"}
    
    -- ✅ Handle insert/remove dengan incremental update
    for _, key in ipairs(categories) do
        table.insert(self._conns, self._data:OnArrayInsert({"Inventory", key}, function(_, entry)
            if self:_isFish(entry) then
                self:_addFish(entry)
                self._fishChanged:Fire(self._totalFish, self._totalShiny, self._totalMutant)
            end
        end))
        
        table.insert(self._conns, self._data:OnArrayRemove({"Inventory", key}, function(_, entry)
            if self:_isFish(entry) then
                self:_removeFish(entry)
                self._fishChanged:Fire(self._totalFish, self._totalShiny, self._totalMutant)
            end
        end))
    end
    
    -- ✅ CRITICAL: OnChange untuk detect favorited changes
    -- Mirip InventoryWatcher tapi HANYA check favorited field
    for _, key in ipairs(categories) do
        table.insert(self._conns, self._data:OnChange({"Inventory", key}, function(newArr, oldArr)
            if type(newArr) ~= "table" or type(oldArr) ~= "table" then return end
            
            -- OPTIMIZED: Hanya scan entry yang UUID-nya kita track
            local maxLen = math.max(#newArr, #oldArr)
            for i = 1, maxLen do
                local newEntry = newArr[i]
                local oldEntry = oldArr[i]
                
                -- Skip jika bukan fish atau insert/remove (sudah di-handle di atas)
                if not newEntry or not oldEntry then continue end
                if not self:_isFish(newEntry) then continue end
                
                local uuid = newEntry.UUID or newEntry.Uuid or newEntry.uuid
                if not uuid then continue end
                
                -- Skip jika UUID ini tidak ada di tracking kita (bukan fish yang kita monitor)
                if not self._fishesByUUID[uuid] then continue end
                
                -- Check perubahan Favorited field
                local newFav = self:_isFavorited(newEntry)
                local oldFav = self:_isFavorited(oldEntry)
                
                if newFav ~= oldFav then
                    self:_updateFavorited(uuid, newFav)
                end
            end
        end))
    end
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