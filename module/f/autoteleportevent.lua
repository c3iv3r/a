--========================================================
-- Feature: AutoTeleportEvent v2 (Priority + Fallback)
-- API: Init(gui?), Start({ selectedEvents?, hoverHeight? }), Stop(), Cleanup()
-- Extra: SetSelectedEvents(list|set), SetHoverHeight(n), Status()
--========================================================

local AutoTeleportEvent = {}
AutoTeleportEvent.__index = AutoTeleportEvent

-- ===== Logger (safe no-op fallback) =====
local logger = _G.Logger and _G.Logger.new("AutoTeleportEventV2") or {
    debug = function() end, info = function() end, warn = function() end, error = function() end
}

-- ===== Services =====
local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService        = game:GetService("RunService")
local Workspace         = game:GetService("Workspace")

local LocalPlayer = Players.LocalPlayer

-- ===== State =====
local running            = false
local hbConn             = nil
local charConn           = nil
local propsAddedConn     = nil
local propsRemovedConn   = nil
local workspaceConn      = nil
local notificationConn   = nil

local eventsFolder       = nil               -- ReplicatedStorage.Events (ModuleScript tree)
local savedPosition      = nil               -- CFrame
local currentTarget      = nil               -- { model, name, nameKey, pos, propsName, rank }
local hoverHeight        = 15

-- pilihan user
local selectedPriorityList = {}              -- array (urutan = prioritas)
local selectedSet           = {}             -- dict untuk match cepat

-- cache & tracking
local validEventNameSet   = {}               -- normalised names dari ReplicatedStorage.Events
local lastKnownModels     = {}               -- [Instance]=true untuk deteksi lenyap
local notifiedEvents      = {}               -- [normName] = { name, t }

-- ===== Small utils =====
local function normName(s)
    s = string.lower(s or "")
    return (s:gsub("%W", ""))  -- buang non-alnum biar robust
end

local function waitChild(parent, name, timeout)
    local t0 = os.clock()
    local obj = parent:FindFirstChild(name)
    while not obj and (os.clock() - t0) < (timeout or 5) do
        parent.ChildAdded:Wait()
        obj = parent:FindFirstChild(name)
    end
    return obj
end

local function ensureCharacter()
    local char = LocalPlayer.Character or LocalPlayer.CharacterAdded:Wait()
    local hrp  = char:FindFirstChild("HumanoidRootPart") or waitChild(char, "HumanoidRootPart", 5)
    local hum  = char:FindFirstChildOfClass("Humanoid")
    return char, hrp, hum
end

local function setCFrameSafely(hrp, targetPos, lookAtPos)
    local look = lookAtPos or (hrp.CFrame.LookVector + hrp.Position)
    hrp.AssemblyLinearVelocity  = Vector3.new()
    hrp.AssemblyAngularVelocity = Vector3.new()
    hrp.CFrame = CFrame.lookAt(targetPos, Vector3.new(look.X, targetPos.Y, look.Z))
end

local function saveCurrentPositionOnce()
    if savedPosition then return end
    local _, hrp = ensureCharacter()
    if hrp then
        savedPosition = hrp.CFrame
        logger:info("[ATE] Saved pos @", tostring(savedPosition.Position))
    end
end

local function restoreSavedPosition()
    if not savedPosition then return end
    local _, hrp = ensureCharacter()
    if hrp then
        setCFrameSafely(hrp, savedPosition.Position, savedPosition.Position + savedPosition.LookVector)
        logger:info("[ATE] Restored pos @", tostring(savedPosition.Position))
    end
end

local function resolveModelPivotPos(model: Model): Vector3?
    local ok1, cf1 = pcall(function() return model:GetPivot() end)
    if ok1 and typeof(cf1) == "CFrame" then return cf1.Position end
    local ok2, cf2 = pcall(function() return model.WorldPivot end)
    if ok2 and typeof(cf2) == "CFrame" then return cf2.Position end
    return nil
end

-- ===== Index events dari ReplicatedStorage.Events =====
local function indexEvents()
    table.clear(validEventNameSet)
    if not eventsFolder then return end

    local function scan(container)
        for _, child in ipairs(container:GetChildren()) do
            if child:IsA("ModuleScript") then
                -- Dari konfigurasi events: moduleData.Name biasa ada; fallback: nama modul
                local ok, data = pcall(require, child)
                if ok and type(data) == "table" and data.Name then
                    validEventNameSet[normName(data.Name)] = true
                end
                validEventNameSet[normName(child.Name)] = true
            elseif child:IsA("Folder") then
                scan(child)
            end
        end
    end

    scan(eventsFolder)
    logger:debug("[ATE] Indexed Events:", tostring(#eventsFolder:GetChildren()))
end

-- ===== Notifikasi Event (membantu nama 'Model' & fuzzy) =====
-- Catatan: EventController sisi klien memakai Replion "Events" dan memanggil handler OnEventAdded/Removed
--          saat event masuk/keluar; kita manfaatkan notifikasi UI (RE/TextNotification) sebagai hint. 3 4 5
local function setupEventNotificationListener()
    if notificationConn then notificationConn:Disconnect() end

    local textNotificationRE
    local packages = ReplicatedStorage:FindFirstChild("Packages")
    if packages then
        local idx = packages:FindFirstChild("_Index")
        if idx then
            for _, child in ipairs(idx:GetChildren()) do
                if child.Name:find("sleitnick_net") then
                    local net = child:FindFirstChild("net")
                    if net then
                        textNotificationRE = net:FindFirstChild("RE/TextNotification")
                        if textNotificationRE then break end
                    end
                end
            end
        end
    end

    if not textNotificationRE then
        logger:warn("[ATE] TextNotification RE not found; continuing without it")
        return
    end

    notificationConn = textNotificationRE.OnClientEvent:Connect(function(data)
        if typeof(data) == "table" and data.Type == "Event" and data.Text then
            local nm = data.Text
            local key = normName(nm)
            notifiedEvents[key] = { name = nm, t = os.clock() }
            -- buang yang lama (>5 menit)
            for k, info in pairs(notifiedEvents) do
                if os.clock() - (info.t or 0) > 300 then notifiedEvents[k] = nil end
            end
            logger:info("[ATE] Event notice:", nm)
        end
    end)
end

-- ===== Cek apakah sebuah Model adalah Event =====
local function isEventModel(model: Instance)
    if not model or not model:IsA("Model") then return false end

    local rawName = model.Name
    local key     = normName(rawName)

    -- 1) Cocok dengan daftar Events resmi
    if validEventNameSet[key] then
        return true, rawName, key
    end

    -- 2) Hint dari notifikasi terbaru (bantu model "Model")
    for k, info in pairs(notifiedEvents) do
        if key == k or key:find(k, 1, true) or k:find(key, 1, true) then
            return true, info.name or rawName, key
        end
        if rawName == "Model" and os.clock() - (info.t or 0) < 30 then
            return true, info.name or rawName, key
        end
    end

    -- 3) Heuristik nama umum
    local patterns = { "hunt","boss","raid","event","invasion","attack","storm","hole","meteor","comet","shark","worm","admin","ghost" }
    for _, p in ipairs(patterns) do
        if key:find(p, 1, true) then
            return true, rawName, key
        end
    end

    return false
end

-- ===== Scan aktif di Workspace: !!! MENU RINGS/Props (DIRECT children only) =====
local function scanActiveEvents()
    local t = {}

    local menu  = Workspace:FindFirstChild("!!! MENU RINGS")
    if not menu then return t end
    local props = menu:FindFirstChild("Props")
    if not props then return t end

    for _, c in ipairs(props:GetChildren()) do
        if c:IsA("Model") then
            local ok, disp, key = isEventModel(c)
            if ok then
                local pos = resolveModelPivotPos(c)
                if pos then
                    table.insert(t, {
                        model     = c,
                        name      = disp,
                        nameKey   = normName(disp),
                        pos       = pos,
                        propsName = "Props",
                    })
                    lastKnownModels[c] = true
                end
            end
        end
    end

    -- bersihkan jejak model yang sudah hilang
    for inst in pairs(lastKnownModels) do
        if not inst.Parent then lastKnownModels[inst] = nil end
    end

    return t
end

-- ===== Matching & ranking =====
local function rankOf(nameKey, displayName)
    -- prioritas berbasis urutan dropdown user (1 = paling tinggi)
    if #selectedPriorityList == 0 then return math.huge end
    local displayKey = normName(displayName)
    for i, selKey in ipairs(selectedPriorityList) do
        if nameKey:find(selKey, 1, true) or selKey:find(nameKey, 1, true) then
            return i
        end
        if displayKey:find(selKey, 1, true) or selKey:find(displayKey, 1, true) then
            return i
        end
    end
    return math.huge
end

local function chooseBestTarget()
    local actives = scanActiveEvents()
    if #actives == 0 then return nil end

    -- 1) Cari kandidat yang MATCH prioritas (jika user memilih)
    local pri = {}
    if #selectedPriorityList > 0 then
        for _, a in ipairs(actives) do
            a.rank = rankOf(a.nameKey, a.name)
            if a.rank ~= math.huge then
                table.insert(pri, a)
            end
        end
    end

    -- 2) Jika ada yang match prioritas → pilih rank terendah
    if #pri > 0 then
        table.sort(pri, function(a, b)
            if a.rank ~= b.rank then return a.rank < b.rank end
            return a.name < b.name
        end)
        return pri[1]
    end

    -- 3) Tidak ada yang match prioritas:
    --     FALLBACK: pilih event apa saja (agar user tetap teleport)
    --     Ketika prioritas muncul nanti, loop akan switch.
    for _, a in ipairs(actives) do a.rank = math.huge end
    table.sort(actives, function(a, b) return a.name < b.name end)
    return actives[1]
end

-- ===== Teleport & hover =====
local function teleportTo(target)
    local _, hrp = ensureCharacter()
    if not hrp then return false end
    saveCurrentPositionOnce()
    local tp = target.pos + Vector3.new(0, hoverHeight, 0)
    setCFrameSafely(hrp, tp)
    logger:info(("[ATE] TP → %s"):format(target.name))
    return true
end

local function maintainHover()
    if not currentTarget then return end
    local _, hrp = ensureCharacter()
    if not hrp then return end
    if not currentTarget.model or not currentTarget.model.Parent then
        currentTarget = nil
        return
    end
    -- refresh pos target (pivot bisa pindah)
    local p = resolveModelPivotPos(currentTarget.model)
    if p then currentTarget.pos = p end

    local desired = currentTarget.pos + Vector3.new(0, hoverHeight, 0)
    if (hrp.Position - desired).Magnitude > 1.25 then
        setCFrameSafely(hrp, desired)
    else
        hrp.AssemblyLinearVelocity  = Vector3.new()
        hrp.AssemblyAngularVelocity = Vector3.new()
    end
end

-- ===== Loop =====
local function startLoop()
    if hbConn then hbConn:Disconnect() end
    local lastMain = 0
    hbConn = RunService.Heartbeat:Connect(function()
        if not running then return end

        -- hover sering
        maintainHover()

        local now = os.clock()
        if now - lastMain < 0.30 then return end
        lastMain = now

        local best = chooseBestTarget()
        if not best then
            -- tak ada event aktif → pulang
            if currentTarget then currentTarget = nil end
            restoreSavedPosition()
            return
        end

        -- switch jika: belum punya target, beda model, atau prioritas lebih tinggi muncul
        local needSwitch = false
        if not currentTarget then
            needSwitch = true
        else
            if currentTarget.model ~= best.model then
                needSwitch = true
            elseif (currentTarget.rank or math.huge) > (best.rank or math.huge) then
                -- muncul kandidat yang lebih prioritas
                needSwitch = true
            end
        end

        if needSwitch then
            teleportTo(best)
            currentTarget = best
        end
    end)
end

-- ===== Workspace monitors (khusus path yang kamu sebut) =====
local function setupWorkspaceMonitoring()
    if propsAddedConn   then propsAddedConn:Disconnect();   propsAddedConn = nil end
    if propsRemovedConn then propsRemovedConn:Disconnect(); propsRemovedConn = nil end
    if workspaceConn    then workspaceConn:Disconnect();    workspaceConn = nil end

    local function bindProps(props)
        if not props then return end
        propsAddedConn = props.ChildAdded:Connect(function(c)
            if c:IsA("Model") then
                task.delay(0.1, function()
                    logger:debug("[ATE] Props added:", c.Name)
                end)
            end
        end)
        propsRemovedConn = props.ChildRemoved:Connect(function(c)
            if c:IsA("Model") then
                logger:debug("[ATE] Props removed:", c.Name)
                if currentTarget and currentTarget.model == c then
                    currentTarget = nil
                end
            end
        end)
    end

    local menu = Workspace:FindFirstChild("!!! MENU RINGS")
    bindProps(menu and menu:FindFirstChild("Props"))

    workspaceConn = Workspace.ChildAdded:Connect(function(c)
        if c.Name == "!!! MENU RINGS" then
            bindProps(c:WaitForChild("Props", 5))
        end
    end)
end

-- ===== Public API =====
function AutoTeleportEvent:Init(gui)
    eventsFolder = ReplicatedStorage:FindFirstChild("Events") or waitChild(ReplicatedStorage, "Events", 5)
    indexEvents()
    setupEventNotificationListener()

    if charConn then charConn:Disconnect() end
    charConn = LocalPlayer.CharacterAdded:Connect(function()
        -- reset pos tersimpan per respawn; akan diset ulang saat TP pertama
        savedPosition = nil
        if running and currentTarget then
            task.defer(function()
                task.wait(0.5)
                if currentTarget then teleportTo(currentTarget) end
            end)
        end
    end)

    setupWorkspaceMonitoring()
    logger:info("[ATE] Init OK")
    return true
end

function AutoTeleportEvent:Start(cfg)
    if running then return true end
    running = true

    if cfg then
        if type(cfg.hoverHeight) == "number" then
            hoverHeight = math.clamp(cfg.hoverHeight, 5, 100)
        end
        if cfg.selectedEvents ~= nil then
            self:SetSelectedEvents(cfg.selectedEvents)
        end
    end

    currentTarget  = nil
    savedPosition  = nil
    table.clear(lastKnownModels)

    -- coba target awal
    local first = chooseBestTarget()
    if first then
        teleportTo(first)
        currentTarget = first
        logger:info("[ATE] Initial target:", first.name)
    else
        logger:info("[ATE] No initial event; waiting …")
    end

    startLoop()
    logger:info("[ATE] Started")
    return true
end

function AutoTeleportEvent:Stop()
    if not running then return true end
    running = false
    if hbConn then hbConn:Disconnect(); hbConn = nil end

    -- selalu balik kalau ada saved pos
    restoreSavedPosition()

    currentTarget = nil
    table.clear(lastKnownModels)
    logger:info("[ATE] Stopped")
    return true
end

function AutoTeleportEvent:Cleanup()
    self:Stop()
    if charConn         then charConn:Disconnect();         charConn = nil end
    if propsAddedConn   then propsAddedConn:Disconnect();   propsAddedConn = nil end
    if propsRemovedConn then propsRemovedConn:Disconnect(); propsRemovedConn = nil end
    if workspaceConn    then workspaceConn:Disconnect();    workspaceConn = nil end
    if notificationConn then notificationConn:Disconnect(); notificationConn = nil end

    eventsFolder = nil
    table.clear(validEventNameSet)
    table.clear(selectedPriorityList)
    table.clear(selectedSet)
    table.clear(lastKnownModels)
    table.clear(notifiedEvents)
    savedPosition = nil
    currentTarget = nil

    logger:info("[ATE] Cleanup done")
    return true
end

-- ===== Setters & Status =====
function AutoTeleportEvent:SetSelectedEvents(selected)
    table.clear(selectedPriorityList)
    table.clear(selectedSet)

    if type(selected) == "table" then
        if #selected > 0 then
            -- array berurutan = prioritas
            for _, v in ipairs(selected) do
                local k = normName(v)
                table.insert(selectedPriorityList, k)
                selectedSet[k] = true
            end
            logger:info("[ATE] Priority:", table.concat(selectedPriorityList, ", "))
        else
            -- dict/set: k=true
            for k, on in pairs(selected) do
                if on then selectedSet[normName(k)] = true end
            end
        end
    end
    return true
end

function AutoTeleportEvent:SetHoverHeight(n)
    if type(n) == "number" then
        hoverHeight = math.clamp(n, 5, 100)
        if running and currentTarget then
            local _, hrp = ensureCharacter()
            if hrp then
                local desired = currentTarget.pos + Vector3.new(0, hoverHeight, 0)
                setCFrameSafely(hrp, desired)
            end
        end
        return true
    end
    return false
end

function AutoTeleportEvent:Status()
    return {
        running     = running,
        hover       = hoverHeight,
        hasSavedPos = savedPosition ~= nil,
        target      = currentTarget and currentTarget.name or nil,
        priority    = selectedPriorityList,
        notices     = notifiedEvents,
    }
end

function AutoTeleportEvent.new()
    return setmetatable({}, AutoTeleportEvent)
end

return AutoTeleportEvent