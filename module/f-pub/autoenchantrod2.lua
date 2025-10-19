--========================================================
-- autoenchantrodv2.lua (V2 - TRANSCENDED STONE VERSION - PATCHED)
--========================================================
-- Changes from V1:
--  - Uses RE/ActivateSecondEnchantingAltar instead of RE/ActivateEnchantingAltar
--  - Detects "Transcended Stone" (name) instead of "Enchant Stone"
--  - Type/Category tetap "EnchantStones" (sama seperti V1)
--  - PATCHED: Integrated with EnchantStoneWatcher
--========================================================

local logger = _G.Logger and _G.Logger.new("AutoEnchantRodV2") or {
    debug = function() end,
    info = function() end,
    warn = function() end,
    error = function() end
}

local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local LocalPlayer       = Players.LocalPlayer

-- ==== Remotes (pakai sleitnick_net) ====
local REMOTE_NAMES = {
    EquipItem               = "RE/EquipItem",
    EquipToolFromHotbar     = "RE/EquipToolFromHotbar",
    UnequipItem             = "RE/UnequipItem",
    ActivateEnchantingAltar = "RE/ActivateSecondEnchantingAltar",
    RollEnchant             = "RE/RollEnchant",
}

-- ==== Util: cari folder net sleitnick ====
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

-- ==== Map Enchants (Id <-> Name) ====
local function buildEnchantsIndex()
    local mapById, mapByName = {}, {}
    local enchFolder = ReplicatedStorage:FindFirstChild("Enchants")
    if enchFolder then
        for _, child in ipairs(enchFolder:GetChildren()) do
            if child:IsA("ModuleScript") then
                local ok, mod = pcall(require, child)
                if ok and type(mod) == "table" and mod.Data then
                    local id   = tonumber(mod.Data.Id)
                    local name = tostring(mod.Data.Name or child.Name)
                    if id then
                        mapById[id] = name
                        mapByName[name] = id
                    end
                end
            end
        end
    end
    return mapById, mapByName
end

-- ==== V2: Deteksi "Transcended Stone" di inventory (FALLBACK ONLY) ====
local function safeItemData(id)
    local ok, ItemUtility = pcall(function() return require(ReplicatedStorage.Shared.ItemUtility) end)
    if not ok or not ItemUtility then return nil end

    local d = nil
    if ItemUtility.GetItemDataFromItemType then
        local ok2, got = pcall(function() return ItemUtility:GetItemDataFromItemType("Items", id) end)
        if ok2 and got then d = got end
    end
    if not d and ItemUtility.GetItemData then
        local ok3, got = pcall(function() return ItemUtility:GetItemData(id) end)
        if ok3 and got then d = got end
    end
    return d and d.Data
end

local function isTranscendedStoneEntry(entry)
    if type(entry) ~= "table" then return false end
    local id    = entry.Id or entry.id
    local name  = nil
    local dtype = nil

    local data = safeItemData(id)
    if data then
        dtype = tostring(data.Type or data.Category or "")
        name  = tostring(data.Name or "")
    end

    if dtype and dtype:lower():find("enchant") and dtype:lower():find("stone") then
        if name and name:lower():find("transcended") then
            return true
        end
    end
    
    if name and name:lower():find("transcended") and name:lower():find("stone") then
        return true
    end

    if entry.Metadata and entry.Metadata.IsTranscendedStone then
        return true
    end

    return false
end

-- ==== HOTBAR DETECTION UTILITIES ====
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

local function analyzeHotbarSlot(stoneWatcher, watcher, replion, slotNum)
    local equippedItems = getHotbarData(replion)
    local slotIndex = slotNum
    
    if equippedItems[slotIndex] then
        local uuid = equippedItems[slotIndex]
        
        -- PRIORITAS 1: Check via stoneWatcher (paling akurat)
        if stoneWatcher then
            local stone = stoneWatcher:getStoneByUUID(uuid)
            if stone then
                local isTranscended = stone.name:lower():find("transcended") ~= nil
                return {
                    hasItem = true,
                    uuid = uuid,
                    isTranscendedStone = isTranscended,
                    entry = stone.entry
                }
            end
        end
        
        -- FALLBACK: Check manual via watcher
        local items = nil
        if watcher and watcher.getSnapshotTyped then
            items = watcher:getSnapshotTyped("Items")
        elseif watcher then
            items = watcher:getSnapshot("Items")
        end
        
        if items then
            for _, entry in ipairs(items) do
                local entryUuid = entry.UUID or entry.Uuid or entry.uuid
                if entryUuid == uuid then
                    local isTranscendedStone = isTranscendedStoneEntry(entry)
                    return {
                        hasItem = true,
                        uuid = uuid,
                        isTranscendedStone = isTranscendedStone,
                        entry = entry
                    }
                end
            end
        end
        
        return {
            hasItem = true,
            uuid = uuid,
            isTranscendedStone = false,
            entry = nil
        }
    end
    
    return {
        hasItem = false,
        uuid = nil,
        isTranscendedStone = false,
        entry = nil
    }
end

local function findBestHotbarSlot(stoneWatcher, watcher, replion)
    local availableSlots = {2, 3, 4, 5}
    
    for _, slot in ipairs(availableSlots) do
        local analysis = analyzeHotbarSlot(stoneWatcher, watcher, replion, slot)
        if not analysis.hasItem then
            return slot, "empty"
        end
    end
    
    for _, slot in ipairs(availableSlots) do
        local analysis = analyzeHotbarSlot(stoneWatcher, watcher, replion, slot)
        if analysis.hasItem and analysis.isTranscendedStone then
            return slot, "transcended_stone"
        end
    end
    
    for _, slot in ipairs(availableSlots) do
        local analysis = analyzeHotbarSlot(stoneWatcher, watcher, replion, slot)
        if analysis.hasItem and not analysis.isTranscendedStone then
            return slot, "needs_clear"
        end
    end
    
    return 3, "fallback"
end

-- ==== Feature Class ====
local Auto = {}
Auto.__index = Auto

function Auto.new(opts)
    opts = opts or {}

    local watcher = opts.watcher
    local stoneWatcher = opts.stoneWatcher
    
    if not watcher and opts.attemptAutoWatcher then
        local ok, Mod = pcall(function()
            return loadstring(game:HttpGet("https://raw.githubusercontent.com/c3iv3r/a/refs/heads/main/utils/fishit/itemwatcher.lua"))()
        end)
        if ok and Mod then
            watcher = Mod.getShared()
        end
    end
    
    -- NEW: Auto-create EnchantStoneWatcher if not provided
    if not stoneWatcher then
        local ok, StoneWatcherMod = pcall(function()
            return loadstring(game:HttpGet("https://raw.githubusercontent.com/c3iv3r/a/refs/heads/main/utils/fishit/enchantstonewatcher.lua"))()
        end)
        if ok and StoneWatcherMod then
            stoneWatcher = StoneWatcherMod.getShared()
            logger:debug("EnchantStoneWatcher auto-loaded")
        end
    end
    
    local replion = nil
    if not watcher or not watcher._replion then
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
        _watcher       = watcher,
        _stoneWatcher  = stoneWatcher,
        _replion       = replion or (watcher and watcher._replion),
        _enabled       = false,
        _running       = false,
        _delay         = tonumber(opts.rollDelay or 0.35),
        _timeout       = tonumber(opts.rollResultTimeout or 6.0),
        _targetsById   = {},
        _targetsByName = {},
        _mapId2Name    = {},
        _mapName2Id    = {},
        _evRoll        = Instance.new("BindableEvent"),
        _conRoll       = nil,
        _lastUsedSlot  = nil,
    }, Auto)

    self._mapId2Name, self._mapName2Id = buildEnchantsIndex()
    self:_attachRollListener()

    return self
end

-- ---- Public API ----

function Auto:setTargetsByNames(namesTbl)
    self._targetsById = {}
    self._targetsByName = {}
    for _, name in ipairs(namesTbl or {}) do
        local id = self._mapName2Id[name]
        if id then
            self._targetsById[id] = true
            self._targetsByName[name] = true
        else
             logger:warn("unknown enchant name:", name)
        end
    end
end

function Auto:setTargetsByIds(idsTbl)
    self._targetsById = {}
    self._targetsByName = {}
    for _, id in ipairs(idsTbl or {}) do
        id = tonumber(id)
        if id then
            self._targetsById[id] = true
            local nm = self._mapId2Name[id]
            if nm then self._targetsByName[nm] = true end
        end
    end
end

function Auto:setHotbarSlot(n)
    logger:debug("setHotbarSlot called but auto-selection is used instead")
end

function Auto:isEnabled() return self._enabled end

function Auto:start()
    if self._enabled then return end
    self._enabled = true
    task.spawn(function() self:_runLoop() end)
end

function Auto:stop()
    self._enabled = false
end

function Auto:destroy()
    self._enabled = false
    if self._conRoll then
        self._conRoll:Disconnect()
        self._conRoll = nil
    end
    if self._evRoll then
        self._evRoll:Destroy()
        self._evRoll = nil
    end
end

-- ---- Internals ----

function Auto:_attachRollListener()
    if self._conRoll then self._conRoll:Disconnect() end
    local re = getRemote(REMOTE_NAMES.RollEnchant)
    if not re or not re:IsA("RemoteEvent") then
        logger:warn("RollEnchant remote not found (will retry when run)")
        return
    end
    self._conRoll = re.OnClientEvent:Connect(function(...)
        local args = table.pack(...)
        local id = tonumber(args[2])
        if id then
            self._evRoll:Fire(id)
        end
    end)
end

function Auto:_waitRollId(timeoutSec)
    timeoutSec = timeoutSec or self._timeout
    local gotId = nil
    local done = false
    local conn
    conn = self._evRoll.Event:Connect(function(id)
        gotId = id
        done = true
        if conn then conn:Disconnect() end
    end)
    local t0 = os.clock()
    while not done do
        task.wait(0.05)
        if os.clock() - t0 > timeoutSec then
            if conn then conn:Disconnect() end
            break
        end
    end
    return gotId
end

function Auto:_findOneTranscendedStoneUuid()
    -- PRIORITAS 1: Pakai stoneWatcher (paling efisien & akurat)
    if self._stoneWatcher then
        -- Cari "Transcended Stone" by name
        local stone = self._stoneWatcher:getStoneByName("Transcended Stone")
        if stone and stone.uuid then
            logger:debug("Found Transcended Stone via watcher:", stone.uuid)
            return stone.uuid
        end
        
        -- Fallback: cari stone yang namanya contains "transcended"
        local allStones = self._stoneWatcher:getAllStones()
        for _, s in ipairs(allStones) do
            if s.name:lower():find("transcended") then
                logger:debug("Found transcended stone (partial match):", s.uuid)
                return s.uuid
            end
        end
        
        logger:debug("No Transcended Stone found in stoneWatcher")
    end
    
    -- FALLBACK: Manual scan (kalau watcher ga ada/belum ready)
    if not self._watcher then return nil end
    local items = nil
    if self._watcher.getSnapshotTyped then
        items = self._watcher:getSnapshotTyped("Items")
    else
        items = self._watcher:getSnapshot("Items")
    end
    for _, entry in ipairs(items or {}) do
        if isTranscendedStoneEntry(entry) then
            local uuid = entry.UUID or entry.Uuid or entry.uuid
            if uuid then
                logger:debug("Found Transcended Stone via fallback scan:", uuid)
                return uuid
            end
        end
    end
    return nil
end

function Auto:_unequipFromSlot(slotNum)
    local analysis = analyzeHotbarSlot(self._stoneWatcher, self._watcher, self._replion, slotNum)
    if not analysis.hasItem or not analysis.uuid then
        return true
    end
    
    local reUnequip = getRemote(REMOTE_NAMES.UnequipItem)
    if not reUnequip then
        logger:warn("UnequipItem remote not found")
        return false
    end
    
    local ok = pcall(function()
        reUnequip:FireServer(analysis.uuid)
    end)
    if not ok then
        logger:warn("UnequipItem FireServer failed for slot", slotNum)
        return false
    end
    
    task.wait(0.2)
    logger:debug("Unequipped item from slot", slotNum)
    return true
end

function Auto:_equipStoneToSlot(uuid, slotNum)
    local analysis = analyzeHotbarSlot(self._stoneWatcher, self._watcher, self._replion, slotNum)
    
    if analysis.hasItem then
        if analysis.isTranscendedStone then
            logger:debug("Slot", slotNum, "already has transcended stone")
            self._lastUsedSlot = slotNum
            return true
        else
            logger:debug("Clearing non-transcended item from slot", slotNum)
            if not self:_unequipFromSlot(slotNum) then
                return false
            end
        end
    end
    
    local reEquipItem = getRemote(REMOTE_NAMES.EquipItem)
    if not reEquipItem then
        logger:warn("EquipItem remote not found")
        return false
    end
    
    local ok = pcall(function()
        reEquipItem:FireServer(uuid, "EnchantStones")
    end)
    if not ok then
        logger:warn("EquipItem FireServer failed")
        return false
    end
    
    self._lastUsedSlot = slotNum
    task.wait(0.2)
    return true
end

function Auto:_equipFromHotbar(slot)
    local reEquipHotbar = getRemote(REMOTE_NAMES.EquipToolFromHotbar)
    if not reEquipHotbar then
        logger:warn("EquipToolFromHotbar remote not found")
        return false
    end
    local ok = pcall(function()
        reEquipHotbar:FireServer(slot)
    end)
    if not ok then
        logger:warn("EquipToolFromHotbar failed for slot", slot)
        return false
    end
    task.wait(0.1)
    return true
end

function Auto:_activateAltar()
    local reActivate = getRemote(REMOTE_NAMES.ActivateEnchantingAltar)
    if not reActivate then
        logger:warn("ActivateSecondEnchantingAltar remote not found")
        return false
    end
    local ok = pcall(function()
        reActivate:FireServer()
    end)
    if not ok then
        logger:warn("ActivateSecondEnchantingAltar failed")
        return false
    end
    return true
end

function Auto:_logStatus(msg)
    logger:info(("[autoenchantrodv2] %s"):format(msg))
end

function Auto:_runOnce()
    local uuid = self:_findOneTranscendedStoneUuid()
    if not uuid then
        self:_logStatus("no Transcended Stone found in inventory.")
        return false, "no_stone"
    end

    local slot, reason = findBestHotbarSlot(self._stoneWatcher, self._watcher, self._replion)
    logger:debug("Selected slot", slot, "reason:", reason)
    
    if not self:_equipStoneToSlot(uuid, slot) then
        return false, "equip_item_failed"
    end

    if not self:_equipFromHotbar(slot) then
        return false, "equip_hotbar_failed"
    end

    if not self:_activateAltar() then
        return false, "altar_failed"
    end

    local id = self:_waitRollId(self._timeout)
    if not id then
        self:_logStatus("no roll result (timeout)")
        return false, "timeout"
    end
    local name = self._mapId2Name[id] or ("Id "..tostring(id))
    self:_logStatus(("rolled: %s (Id=%d)"):format(name, id))

    if self._targetsById[id] then
        self:_logStatus(("MATCH target: %s — stopping."):format(name))
        return true, "matched"
    end
    return false, "not_matched"
end

function Auto:_runLoop()
    if self._running then return end
    self._running = true

    self:_attachRollListener()

    while self._enabled do
        local hasTarget = false
        for _ in pairs(self._targetsById) do hasTarget = true break end
        if not hasTarget then
            self:_logStatus("no targets set — idle. Call setTargetsByNames/Ids first.")
            break
        end

        -- Wait for stoneWatcher ready
        if self._stoneWatcher and self._stoneWatcher.onReady then
            if not self._stoneWatcher._ready then
                local done = false
                local conn = self._stoneWatcher:onReady(function() done = true end)
                local t0 = os.clock()
                while not done and self._enabled do
                    task.wait(0.05)
                    if os.clock()-t0 > 5 then break end
                end
                if conn and conn.Disconnect then conn:Disconnect() end
                if not done then
                    self:_logStatus("stoneWatcher not ready — abort")
                    break
                end
            end
        end

        -- Wait for watcher ready
        if self._watcher and self._watcher.onReady then
            if not self._watcher._ready then
                local done = false
                local conn = self._watcher:onReady(function() done = true end)
                local t0 = os.clock()
                while not done and self._enabled do
                    task.wait(0.05)
                    if os.clock()-t0 > 5 then break end
                end
                if conn and conn.Disconnect then conn:Disconnect() end
                if not done then
                    self:_logStatus("watcher not ready — abort")
                    break
                end
            end
        end

        local ok, reason = self:_runOnce()
        if ok then
            self._enabled = false
            break
        else
            if reason == "no_stone" then
                self:_logStatus("stop: habis Transcended Stone.")
                self._enabled = false
                break
            end
            task.wait(self._delay)
        end
    end

    self._running = false
end

-- ==== Feature wrapper ====
local AutoEnchantRodV2Feature = {}
AutoEnchantRodV2Feature.__index = AutoEnchantRodV2Feature

function AutoEnchantRodV2Feature:Init(controls)
    local watcher = nil
    local stoneWatcher = nil
    
    if controls then
        watcher = controls.watcher
        stoneWatcher = controls.stoneWatcher
    end
    
    self._auto = Auto.new({
        watcher = watcher,
        stoneWatcher = stoneWatcher,
        attemptAutoWatcher = watcher == nil
    })
    return true
end

function AutoEnchantRodV2Feature:GetEnchantNames()
    local names = {}
    if not self._auto then return names end
    for name, _ in pairs(self._auto._mapName2Id) do
        table.insert(names, name)
    end
    table.sort(names)
    return names
end

function AutoEnchantRodV2Feature:SetDesiredByNames(names)
    if self._auto then
        self._auto:setTargetsByNames(names)
    end
end

function AutoEnchantRodV2Feature:SetDesiredByIds(ids)
    if self._auto then
        self._auto:setTargetsByIds(ids)
    end
end

function AutoEnchantRodV2Feature:Start(config)
    if not self._auto then return end
    config = config or {}
    if config.delay then
        local d = tonumber(config.delay)
        if d then
            self._auto._delay = d
        end
    end
    if config.enchantNames then
        self:SetDesiredByNames(config.enchantNames)
    end
    if config.hotbarSlot then
        self._auto:setHotbarSlot(config.hotbarSlot)
    end
    self._auto:start()
end

function AutoEnchantRodV2Feature:Stop()
    if self._auto then
        self._auto:stop()
    end
end

function AutoEnchantRodV2Feature:Cleanup()
    if self._auto then
        self._auto:destroy()
        self._auto = nil
    end
end

return AutoEnchantRodV2Feature