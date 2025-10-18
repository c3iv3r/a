-- enchantstone_watcher.lua (PATCHED - No conflict with FishWatcher)
local EnchantStoneWatcher = {}
EnchantStoneWatcher.__index = EnchantStoneWatcher

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Replion     = require(ReplicatedStorage.Packages.Replion)
local ItemUtility = require(ReplicatedStorage.Shared.ItemUtility)

local SharedInstance = nil

local function mkSignal()
    local ev = Instance.new("BindableEvent")
    return {
        Fire=function(_,...) ev:Fire(...) end,
        Connect=function(_,f) return ev.Event:Connect(f) end,
        Destroy=function(_) ev:Destroy() end
    }
end

function EnchantStoneWatcher.new()
    local self = setmetatable({}, EnchantStoneWatcher)
    self._data = nil
    
    self._stonesByUUID = {}
    
    self._totalStones = 0
    self._totalFavorited = 0
    
    self._stoneChanged = mkSignal()
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

function EnchantStoneWatcher.getShared()
    if not SharedInstance then
        SharedInstance = EnchantStoneWatcher.new()
    end
    return SharedInstance
end

function EnchantStoneWatcher:_get(path)
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

function EnchantStoneWatcher:_resolveName(id)
    if not id then return "<?>" end
    local d = IU("GetItemDataFromItemType", "EnchantStones", id)
    if d and d.Data and d.Data.Name then return d.Data.Name end
    local d2 = IU("GetItemData", id)
    if d2 and d2.Data and d2.Data.Name then return d2.Data.Name end
    return tostring(id)
end

function EnchantStoneWatcher:_isFavorited(entry)
    if not entry then return false end
    return entry.Favorited == true
end

function EnchantStoneWatcher:_isEnchantStone(entry)
    if not entry then return false end
    local id = entry.Id or entry.id
    local d = IU("GetItemDataFromItemType", "EnchantStones", id)
    if d and d.Data then
        local dtype = tostring(d.Data.Type or "")
        if dtype:lower():find("enchant") and dtype:lower():find("stone") then
            return true
        end
    end
    local d2 = IU("GetItemData", id)
    if d2 and d2.Data then
        local dtype = tostring(d2.Data.Type or "")
        if dtype:lower():find("enchant") and dtype:lower():find("stone") then
            return true
        end
    end
    return false
end

function EnchantStoneWatcher:_createStoneData(entry)
    local metadata = entry.Metadata or {}
    return {
        entry = entry,
        id = entry.Id or entry.id,
        uuid = entry.UUID or entry.Uuid or entry.uuid,
        metadata = metadata,
        name = self:_resolveName(entry.Id or entry.id),
        favorited = self:_isFavorited(entry),
        amount = entry.Amount or 1
    }
end

function EnchantStoneWatcher:_initialScan()
    self._stonesByUUID = {}
    self._totalStones = 0
    self._totalFavorited = 0
    
    local arr = self:_get({"Inventory", "Items"})
    if type(arr) == "table" then
        for _, entry in ipairs(arr) do
            if self:_isEnchantStone(entry) then
                local stoneData = self:_createStoneData(entry)
                local uuid = stoneData.uuid
                
                if uuid then
                    self._stonesByUUID[uuid] = stoneData
                    self._totalStones += 1
                    
                    if stoneData.favorited then
                        self._totalFavorited += 1
                    end
                end
            end
        end
    end
end

function EnchantStoneWatcher:_addStone(entry)
    if not self:_isEnchantStone(entry) then return end
    
    local stoneData = self:_createStoneData(entry)
    local uuid = stoneData.uuid
    
    if not uuid or self._stonesByUUID[uuid] then return end
    
    self._stonesByUUID[uuid] = stoneData
    self._totalStones += 1
    
    if stoneData.favorited then
        self._totalFavorited += 1
    end
end

function EnchantStoneWatcher:_removeStone(entry)
    local uuid = entry.UUID or entry.Uuid or entry.uuid
    if not uuid then return end
    
    local stoneData = self._stonesByUUID[uuid]
    if not stoneData then return end
    
    self._totalStones -= 1
    
    if stoneData.favorited then
        self._totalFavorited -= 1
    end
    
    self._stonesByUUID[uuid] = nil
end

function EnchantStoneWatcher:_updateFavorited(uuid, newFav)
    local stoneData = self._stonesByUUID[uuid]
    if not stoneData then return end
    
    local oldFav = stoneData.favorited
    if oldFav == newFav then return end
    
    stoneData.favorited = newFav
    
    if newFav then
        self._totalFavorited += 1
    else
        self._totalFavorited -= 1
    end
    
    self._favChanged:Fire(self._totalFavorited)
end

function EnchantStoneWatcher:_subscribeEvents()
    for _,c in ipairs(self._conns) do pcall(function() c:Disconnect() end) end
    table.clear(self._conns)
    
    table.insert(self._conns, self._data:OnArrayInsert({"Inventory", "Items"}, function(_, entry)
        if self:_isEnchantStone(entry) then
            self:_addStone(entry)
            self._stoneChanged:Fire(self._totalStones)
        end
    end))
    
    table.insert(self._conns, self._data:OnArrayRemove({"Inventory", "Items"}, function(_, entry)
        if self:_isEnchantStone(entry) then
            self:_removeStone(entry)
            self._stoneChanged:Fire(self._totalStones)
        end
    end))
    
    table.insert(self._conns, self._data:OnChange({"Inventory", "Items"}, function(newArr, oldArr)
        if type(newArr) ~= "table" or type(oldArr) ~= "table" then return end
        
        local newUUIDs = {}
        local oldUUIDs = {}
        
        for _, entry in ipairs(newArr) do
            local uuid = entry.UUID or entry.Uuid or entry.uuid
            if uuid then newUUIDs[uuid] = entry end
        end
        
        for _, entry in ipairs(oldArr) do
            local uuid = entry.UUID or entry.Uuid or entry.uuid
            if uuid then oldUUIDs[uuid] = entry end
        end
        
        for uuid, oldEntry in pairs(oldUUIDs) do
            if not newUUIDs[uuid] and self._stonesByUUID[uuid] then
                self:_removeStone(oldEntry)
            end
        end
        
        for uuid, newEntry in pairs(newUUIDs) do
            if not oldUUIDs[uuid] and self:_isEnchantStone(newEntry) then
                self:_addStone(newEntry)
            end
        end
        
        for uuid, newEntry in pairs(newUUIDs) do
            local oldEntry = oldUUIDs[uuid]
            if oldEntry and self._stonesByUUID[uuid] then
                local newFav = self:_isFavorited(newEntry)
                local oldFav = self:_isFavorited(oldEntry)
                
                if newFav ~= oldFav then
                    self:_updateFavorited(uuid, newFav)
                end
            end
        end
        
        if next(oldUUIDs) ~= next(newUUIDs) or #newArr ~= #oldArr then
            self._stoneChanged:Fire(self._totalStones)
        end
    end))
end

function EnchantStoneWatcher:onReady(cb)
    if self._ready then task.defer(cb); return {Disconnect=function() end} end
    return self._readySig:Connect(cb)
end

function EnchantStoneWatcher:onStoneChanged(cb)
    return self._stoneChanged:Connect(cb)
end

function EnchantStoneWatcher:onFavoritedChanged(cb)
    return self._favChanged:Connect(cb)
end

function EnchantStoneWatcher:getAllStones()
    local stones = {}
    for _, stone in pairs(self._stonesByUUID) do
        table.insert(stones, stone)
    end
    return stones
end

function EnchantStoneWatcher:getFavoritedStones()
    local favorited = {}
    for _, stone in pairs(self._stonesByUUID) do
        if stone.favorited then
            table.insert(favorited, stone)
        end
    end
    return favorited
end

function EnchantStoneWatcher:getStonesByName(name)
    local filtered = {}
    for _, stone in pairs(self._stonesByUUID) do
        if stone.name:lower():find(name:lower()) then
            table.insert(filtered, stone)
        end
    end
    return filtered
end

function EnchantStoneWatcher:getStoneByName(name)
    for _, stone in pairs(self._stonesByUUID) do
        if stone.name:lower() == name:lower() then
            return stone
        end
    end
    return nil
end

function EnchantStoneWatcher:hasStone(name)
    return self:getStoneByName(name) ~= nil
end

function EnchantStoneWatcher:getTotals()
    return self._totalStones, self._totalFavorited
end

function EnchantStoneWatcher:isFavoritedByUUID(uuid)
    if not uuid then return false end
    local stone = self._stonesByUUID[uuid]
    return stone and stone.favorited or false
end

function EnchantStoneWatcher:getStoneByUUID(uuid)
    return self._stonesByUUID[uuid]
end

function EnchantStoneWatcher:dumpStones(limit)
    limit = tonumber(limit) or 200
    print(("-- ENCHANT STONES (%d total, %d favorited) --"):format(
        self._totalStones, self._totalFavorited
    ))
    
    local stones = self:getAllStones()
    for i, stone in ipairs(stones) do
        if i > limit then
            print(("... truncated at %d"):format(limit))
            break
        end
        
        local fav = stone.favorited and "★" or ""
        local amt = stone.amount > 1 and ("x"..stone.amount) or ""
        
        print(i, stone.name, stone.uuid or "-", amt, fav)
    end
end

function EnchantStoneWatcher:dumpFavorited(limit)
    limit = tonumber(limit) or 200
    local favorited = self:getFavoritedStones()
    print(("-- FAVORITED STONES (%d) --"):format(#favorited))
    
    for i, stone in ipairs(favorited) do
        if i > limit then
            print(("... truncated at %d"):format(limit))
            break
        end
        
        local amt = stone.amount > 1 and ("x"..stone.amount) or ""
        
        print(i, stone.name, stone.uuid or "-", amt)
    end
end

function EnchantStoneWatcher:destroy()
    for _,c in ipairs(self._conns) do pcall(function() c:Disconnect() end) end
    table.clear(self._conns)
    self._stoneChanged:Destroy()
    self._favChanged:Destroy()
    self._readySig:Destroy()
    if SharedInstance == self then
        SharedInstance = nil
    end
end

return EnchantStoneWatcher