--========================================================
-- autoenchantrodFeature.lua (IMPROVED VERSION)
--========================================================
-- Improvements:
--  - Direct UUID-based enchanting without hotbar equipping
--  - Simplified flow: Find EnchantStone UUID -> FireServer directly
--  - Removed EquipItem and EquipToolFromHotbar dependencies
--  - Maintained same frontend API compatibility
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
    -- Removed unused remotes
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

    local self = setmetatable({
        _watcher       = watcher,       -- disarankan inject watcher kamu
        _enabled       = false,
        _running       = false,
        -- Removed _slot since we no longer use hotbar
        _delay         = tonumber(opts.rollDelay or 0.35),
        _timeout       = tonumber(opts.rollResultTimeout or 6.0),
        _targetsById   = {},            -- set[int] = true
        _targetsByName = {},            -- set[name] = true (display)
        _mapId2Name    = {},
        _mapName2Id    = {},
        _evRoll        = Instance.new("BindableEvent"), -- signal untuk hasil roll (Id)
        _conRoll       = nil,
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

-- Legacy method kept for API compatibility (but no longer used)
function Auto:setHotbarSlot(n)
    -- Do nothing - hotbar slot no longer needed
    logger:debug("setHotbarSlot called but ignored (hotbar no longer used)")
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

-- ==== IMPROVED: Direct UUID-based altar activation ====
function Auto:_activateAltarWithUuid(uuid)
    local reActivate = getRemote(REMOTE_NAMES.ActivateEnchantingAltar)
    if not reActivate then
        logger:warn("ActivateEnchantingAltar remote not found")
        return false
    end
    
    -- Try different common patterns for UUID-based enchant altar activation
    local success = false
    local attempts = {
        -- Pattern 1: Direct UUID parameter
        function() reActivate:FireServer(uuid) end,
        -- Pattern 2: UUID with item type
        function() reActivate:FireServer(uuid, "Items") end,
        -- Pattern 3: UUID with enchant stone type
        function() reActivate:FireServer(uuid, "EnchantStones") end,
        -- Pattern 4: Table format with UUID
        function() reActivate:FireServer({UUID = uuid}) end,
        -- Pattern 5: Table format with item info
        function() reActivate:FireServer({UUID = uuid, Type = "Items"}) end,
        -- Pattern 6: Old format but with UUID instead of slot
        function() reActivate:FireServer("UseItem", uuid) end,
    }
    
    for i, attempt in ipairs(attempts) do
        local ok = pcall(attempt)
        if ok then
            logger:debug("ActivateEnchantingAltar succeeded with pattern", i)
            success = true
            break
        else
            logger:debug("ActivateEnchantingAltar pattern", i, "failed")
        end
    end
    
    if not success then
        logger:warn("All ActivateEnchantingAltar patterns failed")
        return false
    end
    
    return true
end

function Auto:_logStatus(msg)
    logger:info(("[autoenchantrod] %s"):format(msg))
end

function Auto:_runOnce()
    -- 1) ambil satu Enchant Stone UUID
    local uuid = self:_findOneEnchantStoneUuid()
    if not uuid then
        self:_logStatus("no Enchant Stone found in inventory.")
        return false, "no_stone"
    end

    -- 2) langsung aktifkan altar dengan UUID (tanpa equip ke hotbar)
    if not self:_activateAltarWithUuid(uuid) then
        return false, "altar_failed"
    end

    -- 3) tunggu hasil RollEnchant (Id)
    local id = self:_waitRollId(self._timeout)
    if not id then
        self:_logStatus("no roll result (timeout)")
        return false, "timeout"
    end
    local name = self._mapId2Name[id] or ("Id "..tostring(id))
    self:_logStatus(("rolled: %s (Id=%d)"):format(name, id))

    -- 4) cocokkan target
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
-- config.hotbarSlot   -> ignored (kept for API compatibility)
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