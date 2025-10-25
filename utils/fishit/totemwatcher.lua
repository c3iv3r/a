-- totem_watcher.lua
local TotemWatcher = {}
TotemWatcher.__index = TotemWatcher

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Replion = require(ReplicatedStorage.Packages.Replion)
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

function TotemWatcher.new()
    local self = setmetatable({}, TotemWatcher)
    self._data = nil
    
    self._totemsByUUID = {}
    
    self._totalTotems = 0
    self._totalFavorited = 0
    
    self._totemChanged = mkSignal()
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

function TotemWatcher.getShared()
    if not SharedInstance then
        SharedInstance = TotemWatcher.new()
    end
    return SharedInstance
end

function TotemWatcher:_get(path)
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

function TotemWatcher:_resolveName(id)
    if not id then return "<?>" end
    local d = IU("GetItemDataFromItemType", "Totems", id)
    if d and d.Data and d.Data.Name then return d.Data.Name end
    local d2 = IU("GetTotemsData", id)
    if d2 and d2.Data and d2.Data.Name then return d2.Data.Name end
    return tostring(id)
end

function TotemWatcher:_isFavorited(entry)
    if not entry then return false end
    return entry.Favorited == true
end

function TotemWatcher:_isTotem(entry)
    if not entry then return false end
    local id = entry.Id or entry.id
    local d = IU("GetItemDataFromItemType", "Totems", id)
    if d and d.Data then
        local dtype = tostring(d.Data.Type or "")
        if dtype:lower():find("totem") then
            return true
        end
    end
    local d2 = IU("GetTotemsData", id)
    if d2 and d2.Data then
        local dtype = tostring(d2.Data.Type or "")
        if dtype:lower():find("totem") then
            return true
        end
    end
    return false
end

function TotemWatcher:_createTotemData(entry)
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

function TotemWatcher:_initialScan()
    self._totemsByUUID = {}
    self._totalTotems = 0
    self._totalFavorited = 0
    
    local arr = self:_get({"Inventory", "Totems"})
    if type(arr) == "table" then
        for _, entry in ipairs(arr) do
            local totemData = self:_createTotemData(entry)
            local uuid = totemData.uuid
            
            if uuid then
                self._totemsByUUID[uuid] = totemData
                self._totalTotems += 1
                
                if totemData.favorited then
                    self._totalFavorited += 1
                end
            end
        end
    end
end

function TotemWatcher:_addTotem(entry)
    if not self:_isTotem(entry) then return end
    
    local totemData = self:_createTotemData(entry)
    local uuid = totemData.uuid
    
    if not uuid or self._totemsByUUID[uuid] then return end
    
    self._totemsByUUID[uuid] = totemData
    self._totalTotems += 1
    
    if totemData.favorited then
        self._totalFavorited += 1
    end
end

function TotemWatcher:_removeTotem(entry)
    local uuid = entry.UUID or entry.Uuid or entry.uuid
    if not uuid then return end
    
    local totemData = self._totemsByUUID[uuid]
    if not totemData then return end
    
    self._totalTotems -= 1
    
    if totemData.favorited then
        self._totalFavorited -= 1
    end
    
    self._totemsByUUID[uuid] = nil
end

function TotemWatcher:_updateFavorited(uuid, newFav)
    local totemData = self._totemsByUUID[uuid]
    if not totemData then return end
    
    local oldFav = totemData.favorited
    if oldFav == newFav then return end
    
    totemData.favorited = newFav
    
    if newFav then
        self._totalFavorited += 1
    else
        self._totalFavorited -= 1
    end
    
    self._favChanged:Fire(self._totalFavorited)
end

function TotemWatcher:_subscribeEvents()
    for _,c in ipairs(self._conns) do pcall(function() c:Disconnect() end) end
    table.clear(self._conns)
    
    table.insert(self._conns, self._data:OnArrayInsert({"Inventory", "Items"}, function(_, entry)
        if self:_isTotem(entry) then
            self:_addTotem(entry)
            self._totemChanged:Fire(self._totalTotems)
        end
    end))
    
    table.insert(self._conns, self._data:OnArrayRemove({"Inventory", "Items"}, function(_, entry)
        if self:_isTotem(entry) then
            self:_removeTotem(entry)
            self._totemChanged:Fire(self._totalTotems)
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
            if not newUUIDs[uuid] and self._totemsByUUID[uuid] then
                self:_removeTotem(oldEntry)
            end
        end
        
        for uuid, newEntry in pairs(newUUIDs) do
            if not oldUUIDs[uuid] and self:_isTotem(newEntry) then
                self:_addTotem(newEntry)
            end
        end
        
        for uuid, newEntry in pairs(newUUIDs) do
            local oldEntry = oldUUIDs[uuid]
            if oldEntry and self._totemsByUUID[uuid] then
                local newFav = self:_isFavorited(newEntry)
                local oldFav = self:_isFavorited(oldEntry)
                
                if newFav ~= oldFav then
                    self:_updateFavorited(uuid, newFav)
                end
            end
        end
        
        if next(oldUUIDs) ~= next(newUUIDs) or #newArr ~= #oldArr then
            self._totemChanged:Fire(self._totalTotems)
        end
    end))
end

function TotemWatcher:onReady(cb)
    if self._ready then task.defer(cb); return {Disconnect=function() end} end
    return self._readySig:Connect(cb)
end

function TotemWatcher:onTotemChanged(cb)
    return self._totemChanged:Connect(cb)
end

function TotemWatcher:onFavoritedChanged(cb)
    return self._favChanged:Connect(cb)
end

function TotemWatcher:getAllTotems()
    local totems = {}
    for _, totem in pairs(self._totemsByUUID) do
        table.insert(totems, totem)
    end
    return totems
end

function TotemWatcher:getFavoritedTotems()
    local favorited = {}
    for _, totem in pairs(self._totemsByUUID) do
        if totem.favorited then
            table.insert(favorited, totem)
        end
    end
    return favorited
end

function TotemWatcher:getTotemsByName(name)
    local filtered = {}
    for _, totem in pairs(self._totemsByUUID) do
        if totem.name:lower():find(name:lower()) then
            table.insert(filtered, totem)
        end
    end
    return filtered
end

function TotemWatcher:getTotemByName(name)
    for _, totem in pairs(self._totemsByUUID) do
        if totem.name:lower() == name:lower() then
            return totem
        end
    end
    return nil
end

function TotemWatcher:hasTotem(name)
    return self:getTotemByName(name) ~= nil
end

function TotemWatcher:getTotals()
    return self._totalTotems, self._totalFavorited
end

function TotemWatcher:isFavoritedByUUID(uuid)
    if not uuid then return false end
    local totem = self._totemsByUUID[uuid]
    return totem and totem.favorited or false
end

function TotemWatcher:getTotemByUUID(uuid)
    return self._totemsByUUID[uuid]
end

function TotemWatcher:dumpTotems(limit)
    limit = tonumber(limit) or 200
    print(("-- TOTEMS (%d total, %d favorited) --"):format(
        self._totalTotems, self._totalFavorited
    ))
    
    local totems = self:getAllTotems()
    for i, totem in ipairs(totems) do
        if i > limit then
            print(("... truncated at %d"):format(limit))
            break
        end
        
        local fav = totem.favorited and "★" or ""
        local amt = totem.amount > 1 and ("x"..totem.amount) or ""
        
        print(i, totem.name, totem.uuid or "-", amt, fav)
    end
end

function TotemWatcher:dumpFavorited(limit)
    limit = tonumber(limit) or 200
    local favorited = self:getFavoritedTotems()
    print(("-- FAVORITED TOTEMS (%d) --"):format(#favorited))
    
    for i, totem in ipairs(favorited) do
        if i > limit then
            print(("... truncated at %d"):format(limit))
            break
        end
        
        local amt = totem.amount > 1 and ("x"..totem.amount) or ""
        
        print(i, totem.name, totem.uuid or "-", amt)
    end
end

function TotemWatcher:destroy()
    for _,c in ipairs(self._conns) do pcall(function() c:Disconnect() end) end
    table.clear(self._conns)
    self._totemChanged:Destroy()
    self._favChanged:Destroy()
    self._readySig:Destroy()
    if SharedInstance == self then
        SharedInstance = nil
    end
end

return TotemWatcher