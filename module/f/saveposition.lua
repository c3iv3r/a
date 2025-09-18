-- ===========================
-- SAVE POSITION FEATURE (Patched)
-- - Stable rejoin restore (no recapture at spawn)
-- - Safe CFrame serialization
-- - Delete Position
-- - Dual persistence: SaveManager (if present) or executor FS
-- - Same API: Init, Start, Stop, Cleanup + helpers
-- ===========================

local SavePositionFeature = {}
SavePositionFeature.__index = SavePositionFeature

-- ===== Logger =====
local logger = _G.Logger and _G.Logger.new("SavePosition") or {
    debug = function() end, info = function() end,
    warn  = function() end, error = function() end,
}

-- ===== Services =====
local Players     = game:GetService("Players")
local RunService  = game:GetService("RunService")
local HttpService = game:GetService("HttpService")
local LocalPlayer = Players.LocalPlayer

-- ===== Internal state =====
local isInitialized         = false
local isRunning             = false
local controls              = {}
local selectedName          = nil
local saveToggleEnabled     = false
local saveAnchorCFrame      = nil
local savedPositions        = {}    -- map: name -> CFrame

local charAddedConn, heartbeatConn
local suppressRecaptureUntil = 0    -- timestamp; while active, SetSaveToggle(true) tidak capture ulang

-- ===== Persistence Backends =====
local SAVE_KEY = "saveposition"     -- SaveManager key
local FS_PATH  = ".devlogic/saveposition.json"
local HAS_FS   = (typeof(writefile)=="function") and (typeof(readfile)=="function") and (typeof(isfile)=="function")
local HAS_SM   = (_G.SaveManager and _G.SaveManager.Get and _G.SaveManager.Set)

-- CFrame <-> table (12 angka) dengan urutan GetComponents()
local function cframeToArr(cf)
    local a,b,c,d,e,f,g,h,i,x,y,z = cf:GetComponents()
    return {a,b,c,d,e,f,g,h,i,x,y,z}
end
local function arrToCFrame(t)
    if type(t)~="table" or #t<12 then return nil end
    -- CFrame.new(x,y,z, r00,r01,r02, r10,r11,r12, r20,r21,r22)
    return CFrame.new(
        t[10], t[11], t[12],
        t[1], t[2], t[3],
        t[4], t[5], t[6],
        t[7], t[8], t[9]
    )
end

local function persist_write(obj)
    if HAS_SM then
        _G.SaveManager:Set(SAVE_KEY, obj) -- biarkan SaveManager nyimpan bareng config lain
        return
    end
    if not HAS_FS then return end
    pcall(function()
        writefile(FS_PATH, HttpService:JSONEncode(obj))
    end)
end

local function persist_read()
    if HAS_SM then
        local ok, data = pcall(function() return _G.SaveManager:Get(SAVE_KEY) end)
        return ok and data or nil
    end
    if not HAS_FS then return nil end
    local ok, data = pcall(function()
        if isfile(FS_PATH) then
            return HttpService:JSONDecode(readfile(FS_PATH))
        end
    end)
    return (ok and data) or nil
end

local function saveAll()
    local obj = {
        saveToggleEnabled = saveToggleEnabled,
        saveAnchorCFrame  = saveAnchorCFrame and cframeToArr(saveAnchorCFrame) or nil,
        selectedName      = selectedName,
        savedPositions    = {},
    }
    for name, cf in pairs(savedPositions) do
        obj.savedPositions[name] = cframeToArr(cf)
    end
    persist_write(obj)
end

local function loadAll()
    local data = persist_read()
    if not data then return end
    savedPositions = {}
    if type(data.savedPositions)=="table" then
        for name, arr in pairs(data.savedPositions) do
            local cf = arrToCFrame(arr)
            if cf then savedPositions[name] = cf end
        end
    end
    saveToggleEnabled = not not data.saveToggleEnabled
    saveAnchorCFrame  = data.saveAnchorCFrame and arrToCFrame(data.saveAnchorCFrame) or nil
    selectedName      = type(data.selectedName)=="string" and data.selectedName or nil
end

-- ===== Helpers =====
local function getHRP()
    local char = LocalPlayer.Character
    return char and char:FindFirstChild("HumanoidRootPart") or nil
end

local function ensureCharacterReady(timeout)
    timeout = timeout or 8
    local char = LocalPlayer.Character or LocalPlayer.CharacterAdded:Wait()
    local t0 = os.clock()
    while os.clock()-t0 < timeout do
        local hrp = char:FindFirstChild("HumanoidRootPart")
        local hum = char:FindFirstChildOfClass("Humanoid")
        if hrp and hum and hum.Health > 0 then return hrp end
        RunService.Heartbeat:Wait()
    end
    return getHRP()
end

local function hardTeleport(cf)
    local hrp = ensureCharacterReady(6)
    if not hrp then return false end
    local ok = pcall(function()
        local target = cf + Vector3.new(0,6,0)
        local hum = hrp.Parent and hrp.Parent:FindFirstChildOfClass("Humanoid")
        if hum then hum:ChangeState(Enum.HumanoidStateType.Physics) end
        hrp.AssemblyLinearVelocity  = Vector3.zero
        hrp.AssemblyAngularVelocity = Vector3.zero
        hrp.CFrame = target
        task.delay(0.15, function()
            if hum and hum.Health>0 then
                hum:ChangeState(Enum.HumanoidStateType.RunningNoPhysics)
                task.delay(0.05, function()
                    if hum and hum.Health>0 then hum:ChangeState(Enum.HumanoidStateType.Running) end
                end)
            end
        end)
    end)
    return ok
end

-- ===== Public API =====
function SavePositionFeature:Init(guiControls)
    if isInitialized then return true end
    controls = guiControls or {}
    loadAll()

    -- KUNCI UTAMA: pada rejoin, JANGAN rekam anchor baru.
    -- Teleport balik ke anchor yang tersimpan setelah karakter siap.
    if saveToggleEnabled and saveAnchorCFrame then
        suppressRecaptureUntil = os.clock() + 3.5   -- cegah recapture dari auto-load/toggle
        task.spawn(function()
            ensureCharacterReady(6)
            task.wait(0.75) -- beri waktu map/GUI autoload settle
            hardTeleport(saveAnchorCFrame)
        end)
    end

    isInitialized = true
    logger:info("SavePosition Init; toggle=", saveToggleEnabled, " selected=", selectedName)
    return true
end

function SavePositionFeature:Start()
    if isRunning then return true end
    isRunning = true

    if charAddedConn then charAddedConn:Disconnect() end
    charAddedConn = LocalPlayer.CharacterAdded:Connect(function()
        if saveToggleEnabled and saveAnchorCFrame then
            suppressRecaptureUntil = os.clock() + 3.5
            task.defer(function()
                ensureCharacterReady(6)
                task.wait(0.5)
                hardTeleport(saveAnchorCFrame)
            end)
        end
    end)

    if heartbeatConn then heartbeatConn:Disconnect() end
    heartbeatConn = RunService.Heartbeat:Connect(function()
        if not saveToggleEnabled or not saveAnchorCFrame then return end
        local hrp = getHRP(); if not hrp then return end
        local p, a = hrp.Position, saveAnchorCFrame.Position
        local dist = (p - a).Magnitude
        if dist > 120 or p.Y < a.Y - 40 then
            hardTeleport(saveAnchorCFrame)
        end
    end)

    logger:info("SavePosition Started")
    return true
end

function SavePositionFeature:Stop()
    if not isRunning then return true end
    isRunning = false
    if charAddedConn then charAddedConn:Disconnect(); charAddedConn=nil end
    if heartbeatConn then heartbeatConn:Disconnect(); heartbeatConn=nil end
    logger:info("SavePosition Stopped")
    return true
end

function SavePositionFeature:Cleanup()
    self:Stop()
    controls = {}
    isInitialized = false
    logger:info("SavePosition Cleanup done")
end

-- ===== GUI helpers =====
function SavePositionFeature:GetSavedList()
    local list = {}
    for k in pairs(savedPositions) do table.insert(list,k) end
    table.sort(list)
    return list
end

function SavePositionFeature:SetSelected(name)
    if type(name)=="table" then name = name.Value or name[1] end
    if type(name)=="string" and savedPositions[name] then
        selectedName = name
        saveAll()
        return true
    end
    return false
end

function SavePositionFeature:AddPosition(name)
    if type(name)~="string" or name=="" then
        logger:warn("AddPosition: empty name")
        return false
    end
    local hrp = getHRP(); if not hrp then return false end
    savedPositions[name] = hrp.CFrame
    selectedName = name
    saveAll()
    if _G.WindUI then _G.WindUI:Notify({Title="Position Added", Content=("Saved '%s'"):format(name), Icon="bookmark-plus", Duration=2}) end
    return true
end

function SavePositionFeature:RemovePosition(name)
    name = name or selectedName
    if not name or not savedPositions[name] then return false end
    savedPositions[name] = nil
    if selectedName == name then selectedName = nil end
    saveAll()
    if _G.WindUI then _G.WindUI:Notify({Title="Position Deleted", Content=("Removed '%s'"):format(name), Icon="trash-2", Duration=2}) end
    return true
end

function SavePositionFeature:Teleport(name)
    local key = name or selectedName
    if not key then
        if _G.WindUI then _G.WindUI:Notify({Title="Teleport Failed", Content="Select a saved position first.", Icon="alert-triangle", Duration=3}) end
        return false
    end
    local cf = savedPositions[key]; if not cf then return false end
    local ok = hardTeleport(cf)
    if ok then
        if _G.WindUI then _G.WindUI:Notify({Title="Teleport Success", Content=("Teleported to '%s'"):format(key), Icon="map-pin", Duration=2}) end
    else
        if _G.WindUI then _G.WindUI:Notify({Title="Teleport Failed", Content=("Could not teleport to '%s'"):format(key), Icon="x", Duration=3}) end
    end
    return ok
end

-- IMPORTANT: preserveAnchor (no recapture) untuk dipakai saat auto-load/config apply
-- ex: SetSaveToggle(true, {preserveAnchor = true})
function SavePositionFeature:SetSaveToggle(state, opts)
    opts = opts or {}
    local now = os.clock()
    saveToggleEnabled = not not state
    if saveToggleEnabled then
        if opts.preserveAnchor or now < suppressRecaptureUntil then
            -- jangan capture ulang
        else
            local hrp = getHRP()
            if not hrp then return false end
            saveAnchorCFrame = hrp.CFrame
        end
    else
        saveAnchorCFrame = nil
    end
    saveAll()
    return true
end

-- Dipanggil setelah Obsidian/Noctis "auto load config" selesai,
-- supaya kita pastikan restore tanpa recapture.
function SavePositionFeature:OnConfigApplied()
    if saveToggleEnabled and saveAnchorCFrame then
        suppressRecaptureUntil = os.clock() + 1.5
        task.spawn(function()
            ensureCharacterReady(6)
            task.wait(0.25)
            hardTeleport(saveAnchorCFrame)
        end)
    end
end

return SavePositionFeature