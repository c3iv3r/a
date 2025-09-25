--========================================================
-- autoenchantrodFeature.lua (IMPROVED WITH SMART HOTBAR)
--========================================================
-- Improvements:
--  - Smart hotbar slot detection and management (slots 2-5)
--  - Auto-unequip non-enchant items from hotbar when needed
--  - Find available hotbar slot or clear one automatically
--  - Maintain original flow: EquipItem -> EquipToolFromHotbar -> ActivateAltar
--========================================================

local logger = _G.Logger and _G.Logger.new("AutoEnchantRod") or {
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
    ActivateEnchantingAltar = "RE/ActivateEnchantingAltar",
    RollEnchant             = "RE/RollEnchant", -- inbound
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
    -- fallback cari global
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

-- ==== Deteksi "Enchant Stone" di inventory ====
local function safeItemData(id)
    local ok, ItemUtility = pcall(function() return require(ReplicatedStorage.Shared.ItemUtility) end)
    if not ok or not ItemUtility then return nil end

    local d = nil
    -- coba resolusi paling akurat dulu
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

local function isEnchantStoneEntry(entry)
    if type(entry) ~= "table" then return false end
    local id    = entry.Id or entry.id
    local name  = nil
    local dtype = nil

    local data = safeItemData(id)
    if data then
        dtype = tostring(data.Type or data.Category or "")
        name  = tostring(data.Name or "")
    end

    -- heuristik aman:
    -- - type "EnchantStones" / "Enchant Stone(s)"
    -- - atau namanya mengandung "Enchant Stone"
    if dtype and dtype:lower():find("enchant") and dtype:lower():find("stone") then
        return true
    end
    if name and name:lower():find("enchant") and name:lower():find("stone") then
        return true
    end

    -- fallback: cek tag khusus pada entry (kalau server isi)
    if entry.Metadata and entry.Metadata.IsEnchantStone then
        return true
    end

    return false
end

-- ==== HOTBAR DETECTION UTILITIES ====
-- Get hotbar data from Replion (EquippedItems array)
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

-- Check if hotbar slot (2-5) has an item and get its UUID
local function analyzeHotbarSlot(watcher, replion, slotNum)
    local equippedItems = getHotbarData(replion)
    local slotIndex = slotNum  -- slots 1-5 map to array indices 1-5
    
    if equippedItems[slotIndex] then
        local uuid = equippedItems[slotIndex]
        
        -- Get item data from inventory to check if it's enchant stone
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
                    local isEnchantStone = isEnchantStoneEntry(entry)
                    return {
                        hasItem = true,
                        uuid = uuid,
                        isEnchantStone = isEnchantStone,
                        entry = entry
                    }
                end
            end
        end
        
        -- Item found in hotbar but not in inventory (shouldn't happen normally)
        return {
            hasItem = true,
            uuid = uuid,
            isEnchantStone = false,
            entry = nil
        }
    end
    
    return {
        hasItem = false,
        uuid = nil,
        isEnchantStone = false,
        entry = nil
    }
end

-- Find best available hotbar slot (2-5, slot 1 is reserved for fishing rods)
local function findBestHotbarSlot(watcher, replion)
    local availableSlots = {2, 3, 4, 5}
    
    -- First pass: find empty slot
    for _, slot in ipairs(availableSlots) do
        local analysis = analyzeHotbarSlot(watcher, replion, slot)
        if not analysis.hasItem then
            return slot, "empty"
        end
    end
    
    -- Second pass: find slot with enchant stone (we can reuse)
    for _, slot in ipairs(availableSlots) do
        local analysis = analyzeHotbarSlot(watcher, replion, slot)
        if analysis.hasItem and analysis.isEnchantStone then
            return slot, "enchant_stone"
        end
    end
    
    -- Third pass: find slot to clear (has non-enchant item)
    for _, slot in ipairs(availableSlots) do
        local analysis = analyzeHotbarSlot(watcher, replion, slot)
        if analysis.hasItem and not analysis.isEnchantStone then
            return slot, "needs_clear"
        end
    end
    
    -- Fallback: use slot 3
    return 3, "fallback"
end

-- ==== Feature Class ====
local Auto = {}
Auto.__index = Auto

function Auto.new(opts)
    opts = opts or {}

    -- InventoryWatcher
    local watcher = opts.watcher
    if not watcher and opts.attemptAutoWatcher then
        -- coba ambil dari global / require loader kamu
        local ok, Mod = pcall(function()
            -- sesuaikan path kalau kamu punya file lokalnya
            return loadstring(game:HttpGet("https://raw.githubusercontent.com/c3iv3r/a/refs/heads/main/utils/fishit/inventdetect.lua"))()
        end)
        if ok and Mod then
            local w = Mod.new()
            watcher = w
        end
    end
    
    -- Try to access Replion directly for hotbar data
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
        _watcher       = watcher,       -- disarankan inject watcher kamu
        _replion       = replion or (watcher and watcher._replion), -- direct access to replion
        _enabled       = false,
        _running       = false,
        _delay         = tonumber(opts.rollDelay or 0.35),
        _timeout       = tonumber(opts.rollResultTimeout or 6.0),
        _targetsById   = {},            -- set[int] = true
        _targetsByName = {},            -- set[name] = true (display)
        _mapId2Name    = {},
        _mapName2Id    = {},
        _evRoll        = Instance.new("BindableEvent"), -- signal untuk hasil roll (Id)
        _conRoll       = nil,
        _lastUsedSlot  = nil,           -- track slot yang terakhir digunakan
    }, Auto)

    -- Enchant index
    self._mapId2Name, self._mapName2Id = buildEnchantsIndex()

    -- listen inbound RE/RollEnchant
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
    -- Kept for compatibility but not used - we auto-select best slot
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
        -- Arg #2 = Id enchant (sesuai file listener kamu)
        local args = table.pack(...)
        local id = tonumber(args[2]) -- hati‑hati: beberapa game pakai #1, disesuaikan kalau perlu
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

function Auto:_findOneEnchantStoneUuid()
    if not self._watcher then return nil end
    -- pakai typed snapshot agar robust (Items typed)
    local items = nil
    if self._watcher.getSnapshotTyped then
        items = self._watcher:getSnapshotTyped("Items")
    else
        items = self._watcher:getSnapshot("Items")
    end
    for _, entry in ipairs(items or {}) do
        if isEnchantStoneEntry(entry) then
            local uuid = entry.UUID or entry.Uuid or entry.uuid
            if uuid then return uuid end
        end
    end
    return nil
end

function Auto:_unequipFromSlot(slotNum)
    local analysis = analyzeHotbarSlot(self._watcher, self._replion, slotNum)
    if not analysis.hasItem or not analysis.uuid then
        return true -- nothing to unequip
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
    
    task.wait(0.2) -- wait for unequip to complete
    logger:debug("Unequipped item from slot", slotNum)
    return true
end

function Auto:_equipStoneToSlot(uuid, slotNum)
    -- First, ensure slot is available
    local analysis = analyzeHotbarSlot(self._watcher, self._replion, slotNum)
    
    if analysis.hasItem then
        if analysis.isEnchantStone then
            -- Slot already has enchant stone, we can use it
            logger:debug("Slot", slotNum, "already has enchant stone")
            self._lastUsedSlot = slotNum
            return true
        else
            -- Clear the slot first
            logger:debug("Clearing non-enchant item from slot", slotNum)
            if not self:_unequipFromSlot(slotNum) then
                return false
            end
        end
    end
    
    -- Equip enchant stone to inventory/hotbar
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
        logger:warn("ActivateEnchantingAltar remote not found")
        return false
    end
    local ok = pcall(function()
        reActivate:FireServer()
    end)
    if not ok then
        logger:warn("ActivateEnchantingAltar failed")
        return false
    end
    return true
end

function Auto:_logStatus(msg)
    logger:info(("[autoenchantrod] %s"):format(msg))
end

function Auto:_runOnce()
    -- 1) ambil satu Enchant Stone
    local uuid = self:_findOneEnchantStoneUuid()
    if not uuid then
        self:_logStatus("no Enchant Stone found in inventory.")
        return false, "no_stone"
    end

    -- 2) find best hotbar slot
    local slot, reason = findBestHotbarSlot(self._watcher, self._replion)
    logger:debug("Selected slot", slot, "reason:", reason)
    
    -- 3) equip enchant stone to selected slot
    if not self:_equipStoneToSlot(uuid, slot) then
        return false, "equip_item_failed"
    end

    -- 4) pilih dari hotbar
    if not self:_equipFromHotbar(slot) then
        return false, "equip_hotbar_failed"
    end

    -- 5) aktifkan altar
    if not self:_activateAltar() then
        return false, "altar_failed"
    end

    -- 6) tunggu hasil RollEnchant (Id)
    local id = self:_waitRollId(self._timeout)
    if not id then
        self:_logStatus("no roll result (timeout)")
        return false, "timeout"
    end
    local name = self._mapId2Name[id] or ("Id "..tostring(id))
    self:_logStatus(("rolled: %s (Id=%d)"):format(name, id))

    -- 7) cocokkan target
    if self._targetsById[id] then
        self:_logStatus(("MATCH target: %s — stopping."):format(name))
        return true, "matched"
    end
    return false, "not_matched"
end

function Auto:_runLoop()
    if self._running then return end
    self._running = true

    -- pastikan listener terpasang
    self:_attachRollListener()

    while self._enabled do
        -- safety: cek target
        local hasTarget = false
        for _ in pairs(self._targetsById) do hasTarget = true break end
        if not hasTarget then
            self:_logStatus("no targets set — idle. Call setTargetsByNames/Ids first.")
            break
        end

        -- safety: cek watcher ready
        if self._watcher and self._watcher.onReady then
            -- tunggu sekali saja di awal
            local ready = true
            if not self._watcher._ready then
                ready = false
                local done = false
                local conn = self._watcher:onReady(function() done = true end)
                local t0 = os.clock()
                while not done and self._enabled do
                    task.wait(0.05)
                    if os.clock()-t0 > 5 then break end
                end
                if conn and conn.Disconnect then conn:Disconnect() end
                ready = done
            end
            if not ready then
                self:_logStatus("watcher not ready — abort")
                break
            end
        end

        local ok, reason = self:_runOnce()
        if ok then
            -- ketemu target => stop otomatis
            self._enabled = false
            break
        else
            if reason == "no_stone" then
                self:_logStatus("stop: habis Enchant Stone.")
                self._enabled = false
                break
            end
            -- retry kecil
            task.wait(self._delay)
        end
    end

    self._running = false
end

-- ==== Feature wrapper ====
-- Maintained same frontend API for compatibility

local AutoEnchantRodFeature = {}
AutoEnchantRodFeature.__index = AutoEnchantRodFeature

-- Initialize the feature. Accepts optional controls table (unused here).
function AutoEnchantRodFeature:Init(controls)
    -- Attempt to use an injected watcher from controls (if provided)
    local watcher = nil
    if controls and controls.watcher then
        watcher = controls.watcher
    end
    -- Create underlying Auto instance.
    -- If no watcher is provided we allow Auto to auto create one via attemptAutoWatcher = true.
    self._auto = Auto.new({
        watcher = watcher,
        attemptAutoWatcher = watcher == nil
    })
    return true
end

-- Return a list of all available enchant names.
function AutoEnchantRodFeature:GetEnchantNames()
    local names = {}
    if not self._auto then return names end
    for name, _ in pairs(self._auto._mapName2Id) do
        table.insert(names, name)
    end
    table.sort(names)
    return names
end

-- Set desired enchant targets by their names.
function AutoEnchantRodFeature:SetDesiredByNames(names)
    if self._auto then
        self._auto:setTargetsByNames(names)
    end
end

-- Alternate setter: set desired enchant targets by their ids.
function AutoEnchantRodFeature:SetDesiredByIds(ids)
    if self._auto then
        self._auto:setTargetsByIds(ids)
    end
end

-- Start auto enchant logic using provided config.
-- config.delay        -> number: delay between rolls
-- config.enchantNames -> table of enchant names to target
-- config.hotbarSlot   -> ignored (auto-selection used)
function AutoEnchantRodFeature:Start(config)
    if not self._auto then return end
    config = config or {}
    -- update delay if provided
    if config.delay then
        local d = tonumber(config.delay)
        if d then
            self._auto._delay = d
        end
    end
    -- set targets by names
    if config.enchantNames then
        self:SetDesiredByNames(config.enchantNames)
    end
    -- hotbarSlot is ignored but kept for compatibility
    if config.hotbarSlot then
        self._auto:setHotbarSlot(config.hotbarSlot)
    end
    -- start the automation
    self._auto:start()
end

-- Stop the automation gracefully.
function AutoEnchantRodFeature:Stop()
    if self._auto then
        self._auto:stop()
    end
end

-- Cleanup resources and destroy the underlying Auto instance.
function AutoEnchantRodFeature:Cleanup()
    if self._auto then
        self._auto:destroy()
        self._auto = nil
    end
end


return AutoEnchantRodFeature