-- autosubmitsecret.lua (FINAL PATCHED)

local logger = _G.Logger and _G.Logger.new("AutoSubmitSecret") or {
    debug = function() end,
    info = function() end,
    warn = function() end,
    error = function() end
}

local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local LocalPlayer       = Players.LocalPlayer

local REMOTE_NAMES = {
    EquipItem               = "RE/EquipItem",
    EquipToolFromHotbar     = "RE/EquipToolFromHotbar",
    UnequipItem             = "RE/UnequipItem",
    CreateTranscendedStone  = "RF/CreateTranscendedStone",
}

local function findNetRoot()
    local Packages = ReplicatedStorage:FindFirstChild("Packages")
    if not Packages then return end
    local _Index = Packages:FindFirstChild("_Index")
    if not _Index then return end
    for _, pkg in ipairs(_Index:GetChildren()) do
        if pkg:IsA("Folder") and pkg.Name:match("^sleitnick_net@") then
            local net = pkg:FindFirstChild("net")
            if net then return net end
        end
    end
end

local function getRemote(name)
    local net = findNetRoot()
    if net then
        local r = net:FindFirstChild(name)
        if r then return r end
    end
    return ReplicatedStorage:FindFirstChild(name, true)
end

local function safeItemData(id)
    local ItemUtility = ReplicatedStorage.Shared.ItemUtility
    if not ItemUtility then return nil end
    
    local ok, mod = pcall(require, ItemUtility)
    if not ok or not mod then return nil end
    
    if mod.GetItemDataFromItemType then
        local ok2, data = pcall(function() 
            return mod:GetItemDataFromItemType("Fishes", id) 
        end)
        if ok2 and data and data.Data then return data.Data end
    end
    
    if mod.GetItemData then
        local ok3, data = pcall(function() 
            return mod:GetItemData(id) 
        end)
        if ok3 and data and data.Data then return data.Data end
    end
    
    return nil
end

local function isSecretFishData(fishData, targetName)
    if not fishData then return false end
    
    local isSecret = fishData.Type == "Fishes" and fishData.Tier == 7
    if not isSecret then return false end
    
    if targetName then
        local name = fishData.Name or ""
        return name == targetName
    end
    
    return true
end

local function getHotbarData(replion)
    if not replion or not replion.GetExpect then return {} end
    local ok, equippedItems = pcall(function() 
        return replion:GetExpect("EquippedItems") 
    end)
    if ok and type(equippedItems) == "table" then
        return equippedItems
    end
    return {}
end

local function analyzeHotbarSlot(watcher, replion, slotNum)
    local equippedItems = getHotbarData(replion)
    local slotIndex = slotNum
    
    if equippedItems[slotIndex] then
        local uuid = equippedItems[slotIndex]
        
        local fishData = nil
        if watcher and watcher.getFishByUUID then
            fishData = watcher:getFishByUUID(uuid)
        end
        
        return {
            hasItem = true,
            uuid = uuid,
            fishData = fishData
        }
    end
    
    return {
        hasItem = false,
        uuid = nil,
        fishData = nil
    }
end

local function findBestHotbarSlot(watcher, replion)
    local availableSlots = {2, 3, 4, 5}
    
    for _, slot in ipairs(availableSlots) do
        local analysis = analyzeHotbarSlot(watcher, replion, slot)
        if not analysis.hasItem then
            return slot, "empty"
        end
    end
    
    for _, slot in ipairs(availableSlots) do
        local analysis = analyzeHotbarSlot(watcher, replion, slot)
        if analysis.hasItem then
            return slot, "needs_clear"
        end
    end
    
    return 3, "fallback"
end

local AutoSubmit = {}
AutoSubmit.__index = AutoSubmit

function AutoSubmit.new(opts)
    opts = opts or {}
    
    local watcher = opts.watcher
    if not watcher and opts.attemptAutoWatcher then
        local ok, Mod = pcall(function()
            return loadstring(game:HttpGet("https://raw.githubusercontent.com/c3iv3r/a/refs/heads/main/utils/fishit/fishwatcher.lua"))()
        end)
        if ok and Mod then
            watcher = Mod.getShared()
        end
    end
    
    local replion = nil
    if not watcher or not watcher._data then
        local ok, Replion = pcall(function() 
            return require(ReplicatedStorage.Packages.Replion) 
        end)
        if ok and Replion then
            local ok2, data = pcall(function() 
                return Replion.Client:WaitReplion("Data") 
            end)
            if ok2 and data then
                replion = data
            end
        end
    end
    
    local self = setmetatable({
        _watcher     = watcher,
        _replion     = replion or (watcher and watcher._data),
        _enabled     = false,
        _running     = false,
        _targetName  = nil,
        _delay       = tonumber(opts.submitDelay or 0.5),
        _lastUsedSlot = nil,
        _submittedUUIDs = {},
    }, AutoSubmit)
    
    return self
end

function AutoSubmit:setTargetFishName(name)
    self._targetName = name
    logger:debug("Target fish set to:", name)
end

function AutoSubmit:isEnabled()
    return self._enabled
end

function AutoSubmit:start()
    if self._enabled then return end
    
    table.clear(self._submittedUUIDs)
    
    self._enabled = true
    task.spawn(function() self:_runLoop() end)
end

function AutoSubmit:stop()
    self._enabled = false
end

function AutoSubmit:destroy()
    self._enabled = false
    self._watcher = nil
    self._replion = nil
    table.clear(self._submittedUUIDs)
end

function AutoSubmit:_findOneSecretFishUuid()
    if not self._watcher then return nil end
    
    local allFishes = self._watcher:getAllFishes()
    
    for _, fishData in ipairs(allFishes) do
        local uuid = fishData.uuid
        
        if uuid and self._submittedUUIDs[uuid] then
            logger:debug("Skipping already submitted fish:", uuid)
            continue
        end
        
        local itemData = safeItemData(fishData.id)
        
        if itemData and isSecretFishData(itemData, self._targetName) then
            if fishData.favorited then
                logger:debug("Skipping favorited secret fish:", uuid)
                continue
            end
            
            return uuid, fishData
        end
    end
    
    return nil, nil
end

function AutoSubmit:_unequipFromSlot(slotNum)
    local analysis = analyzeHotbarSlot(self._watcher, self._replion, slotNum)
    if not analysis.hasItem or not analysis.uuid then
        return true
    end
    
    local reUnequip = getRemote(REMOTE_NAMES.UnequipItem)
    if not reUnequip then
        logger:warn("UnequipItem remote not found")
        return false
    end
    
    reUnequip:FireServer(analysis.uuid)
    task.wait(0.2)
    logger:debug("Unequipped item from slot", slotNum)
    return true
end

function AutoSubmit:_equipFishToSlot(uuid, slotNum)
    local analysis = analyzeHotbarSlot(self._watcher, self._replion, slotNum)
    
    if analysis.hasItem then
        logger:debug("Clearing slot", slotNum)
        if not self:_unequipFromSlot(slotNum) then
            return false
        end
    end
    
    local reEquipItem = getRemote(REMOTE_NAMES.EquipItem)
    if not reEquipItem then
        logger:warn("EquipItem remote not found")
        return false
    end
    
    reEquipItem:FireServer(uuid, "Fishes")
    self._lastUsedSlot = slotNum
    task.wait(0.2)
    return true
end

function AutoSubmit:_equipFromHotbar(slot)
    local reEquipHotbar = getRemote(REMOTE_NAMES.EquipToolFromHotbar)
    if not reEquipHotbar then
        logger:warn("EquipToolFromHotbar remote not found")
        return false
    end
    
    reEquipHotbar:FireServer(slot)
    task.wait(0.1)
    return true
end

function AutoSubmit:_createTranscendedStone()
    local rfCreate = getRemote(REMOTE_NAMES.CreateTranscendedStone)
    if not rfCreate then
        logger:warn("CreateTranscendedStone remote not found")
        return false
    end
    
    local ok, result = pcall(function()
        return rfCreate:InvokeServer()
    end)
    
    if not ok then
        logger:warn("CreateTranscendedStone failed:", result)
        return false
    end
    
    return true
end

function AutoSubmit:_logStatus(msg)
    logger:info(("[autosubmitsecret] %s"):format(msg))
end

function AutoSubmit:_runOnce()
    local uuid, fishData = self:_findOneSecretFishUuid()
    if not uuid then
        self:_logStatus("no secret fish found (name: " .. tostring(self._targetName) .. ")")
        return false, "no_fish"
    end
    
    local fishName = fishData.name or "Unknown"
    self:_logStatus("Found secret fish: " .. fishName .. " (UUID: " .. uuid .. ")")
    
    local slot, reason = findBestHotbarSlot(self._watcher, self._replion)
    logger:debug("Selected slot", slot, "reason:", reason)
    
    if not self:_equipFishToSlot(uuid, slot) then
        return false, "equip_item_failed"
    end
    
    if not self:_equipFromHotbar(slot) then
        return false, "equip_hotbar_failed"
    end
    
    if not self:_createTranscendedStone() then
        return false, "create_failed"
    end
    
    self._submittedUUIDs[uuid] = true
    
    self:_logStatus("Successfully submitted: " .. fishName)
    return true, "success"
end

function AutoSubmit:_runLoop()
    if self._running then return end
    self._running = true
    
    while self._enabled do
        if not self._targetName or self._targetName == "" then
            self:_logStatus("no target fish name set – idle")
            break
        end
        
        if self._watcher and self._watcher.onReady then
            if not self._watcher._ready then
                local ready = false
                local done = false
                local conn = self._watcher:onReady(function() done = true end)
                local t0 = os.clock()
                while not done and self._enabled do
                    task.wait(0.05)
                    if os.clock() - t0 > 5 then break end
                end
                if conn and conn.Disconnect then conn:Disconnect() end
                ready = done
                
                if not ready then
                    self:_logStatus("watcher not ready – abort")
                    break
                end
            end
        end
        
        local ok, reason = self:_runOnce()
        if ok then
            task.wait(self._delay)
        else
            if reason == "no_fish" then
                self:_logStatus("stop: no more secret fish available")
                self._enabled = false
                break
            end
            task.wait(self._delay)
        end
    end
    
    self._running = false
end

local AutoSubmitSecretFeature = {}
AutoSubmitSecretFeature.__index = AutoSubmitSecretFeature

function AutoSubmitSecretFeature:Init(controls)
    local watcher = nil
    if controls and controls.watcher then
        watcher = controls.watcher
    end
    
    self._auto = AutoSubmit.new({
        watcher = watcher,
        attemptAutoWatcher = watcher == nil
    })
    return true
end

function AutoSubmitSecretFeature:SetTargetFishName(name)
    if self._auto then
        self._auto:setTargetFishName(name)
    end
end

function AutoSubmitSecretFeature:Start(config)
    if not self._auto then return end
    config = config or {}
    
    if config.delay then
        local d = tonumber(config.delay)
        if d then
            self._auto._delay = d
        end
    end
    
    if config.fishName then
        self:SetTargetFishName(config.fishName)
    end
    
    self._auto:start()
end

function AutoSubmitSecretFeature:Stop()
    if self._auto then
        self._auto:stop()
    end
end

function AutoSubmitSecretFeature:Cleanup()
    if self._auto then
        self._auto:destroy()
        self._auto = nil
    end
end

return AutoSubmitSecretFeature