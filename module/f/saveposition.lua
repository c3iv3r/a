-- module/features/SavePosition.lua
local SavePosition = {}
SavePosition.__index = SavePosition

local logger = _G.Logger and _G.Logger.new("SavePosition") or {
    debug = function() end,
    info = function() end,
    warn = function() end,
    error = function() end
}

-- services
local Players     = game:GetService("Players")
local HttpService = game:GetService("HttpService")
local LocalPlayer = Players.LocalPlayer

-- constants
local IDX = "SavePos_Data" -- key di SaveManager JSON (type = "Input")
local FALLBACK_FOLDER = "Noctis/FishIt" -- fallback kalau SaveManager belum siap

-- state
local _enabled   = false
local _savedCF   = nil
local _cons      = {}
local _controls  = {}

-- =============== SaveManager paths & JSON helpers ===============
local function getSMFolderAndSub()
    local sm = rawget(getfenv(), "SaveManager")
    local folder = FALLBACK_FOLDER
    local sub    = ""
    if type(sm) == "table" then
        if type(sm.Folder) == "string" and sm.Folder ~= "" then folder = sm.Folder end
        if type(sm.SubFolder) == "string" and sm.SubFolder ~= "" then sub = sm.SubFolder end
    end
    return folder, sub
end

local function paths_join(...)
    local parts = { ... }
    return table.concat(parts, "/")
end

local function getAutoloadName(folder, sub)
    -- baca autoload.txt langsung (tanpa perlu instance SaveManager)
    local auto = paths_join(folder, "settings", sub ~= "" and sub or "", "autoload.txt")
    if isfile(auto) then
        local ok, name = pcall(readfile, auto)
        if ok then
            name = tostring(name)
            if name ~= "" then return name end
        end
    end
    return "none"
end

local function getConfigPath(folder, sub, name)
    if name == "none" or not name or name == "" then return nil end
    local base = paths_join(folder, "settings")
    if sub ~= "" then base = paths_join(base, sub) end
    return paths_join(base, name .. ".json")
end

local function readConfigTable(path)
    if not path or not isfile(path) then return { objects = {} } end
    local ok, decoded = pcall(function() return HttpService:JSONDecode(readfile(path)) end)
    if ok and type(decoded) == "table" and type(decoded.objects) == "table" then
        return decoded
    end
    return { objects = {} }
end

local function writeConfigTable(path, tbl)
    local ok, s = pcall(function() return HttpService:JSONEncode(tbl or { objects = {} }) end)
    if ok and path then pcall(writefile, path, s) end
end

local function findInput(objects, idx)
    for i, o in ipairs(objects) do
        if o and o.type == "Input" and o.idx == idx then
            return i, o
        end
    end
    return nil, nil
end

local function readPayloadFromSM()
    local folder, sub = getSMFolderAndSub()
    local cfg         = getAutoloadName(folder, sub) -- "none" jika belum set
    local path        = getConfigPath(folder, sub, cfg)
    if not path then return nil end

    local tbl = readConfigTable(path)
    local _, obj = findInput(tbl.objects, IDX)
    if not obj or type(obj.text) ~= "string" or obj.text == "" then return nil end

    local ok, payload = pcall(function() return HttpService:JSONDecode(obj.text) end)
    if not ok or type(payload) ~= "table" then return nil end
    return payload
end

local function writePayloadToSM(payload)
    local folder, sub = getSMFolderAndSub()
    local cfg         = getAutoloadName(folder, sub)
    -- kalau belum ada autoload → kita tetap tulis ke file "default.json" supaya rejoin selanjutnya bisa kebaca
    if cfg == "none" then cfg = "default" end
    local path        = getConfigPath(folder, sub, cfg)

    local tbl = readConfigTable(path)
    local idx, obj = findInput(tbl.objects, IDX)
    local text = HttpService:JSONEncode(payload)

    if idx then
        obj.text = text
        tbl.objects[idx] = obj
    else
        table.insert(tbl.objects, { type = "Input", idx = IDX, text = text })
    end
    writeConfigTable(path, tbl)

    -- Daftarkan "virtual input" ke SaveManager.Library.Options supaya
    -- saat user klik Save di SaveManager, data kita tetap ikut terserialisasi.
    local sm = rawget(getfenv(), "SaveManager")
    if type(sm) == "table" and sm.Library and sm.Library.Options then
        if not sm.Library.Options[IDX] then
            sm.Library.Options[IDX] = {
                Type     = "Input",
                Value    = text,
                SetValue = function(self, v) self.Value = v end
            }
        else
            sm.Library.Options[IDX].Value = text
        end
    end
end

-- =============== Character/Teleport helpers =====================
local function waitForHRP(timeout)
    local deadline = tick() + (timeout or 10)
    repeat
        local char = LocalPlayer.Character
        if char then
            local hrp = char:FindFirstChild("HumanoidRootPart")
            local hum = char:FindFirstChildOfClass("Humanoid")
            if hrp and hum then return hrp end
        end
        task.wait(0.1)
    until tick() > deadline
    return nil
end

local function hardTeleport(cf)
    local hrp = waitForHRP(8)
    if not hrp then return end
    pcall(function()
        hrp.CFrame = cf + Vector3.new(0, 6, 0) -- offset anti-nyemplung
    end)
end

local function bindCharacterAdded()
    for _, c in ipairs(_cons) do pcall(function() c:Disconnect() end) end
    _cons = {}
    table.insert(_cons, LocalPlayer.CharacterAdded:Connect(function()
        task.defer(function()
            if _enabled and _savedCF then hardTeleport(_savedCF) end
        end)
    end))
end

-- =========================== API ===============================
local function captureNow()
    local hrp = waitForHRP(3)
    if not hrp then return false end
    _savedCF = hrp.CFrame
    return true
end

function SavePosition:Init(a, b)
    -- dukung :Init(controls) atau :Init(self, controls)
    _controls = (type(a) == "table" and a ~= self and a) or b or {}

    -- 1) restore dari SaveManager JSON (autoload)
    local payload = readPayloadFromSM()
    if payload then
        _enabled = payload.enabled == true
        if payload.pos and payload.pos.x and payload.pos.y and payload.pos.z then
            _savedCF = CFrame.new(payload.pos.x, payload.pos.y, payload.pos.z)
        end
    end

    -- 2) pasang hook respawn + coba teleport sekali saat init (untuk rejoin)
    bindCharacterAdded()
    if _enabled and _savedCF then task.defer(function() hardTeleport(_savedCF) end) end

    return true
end

function SavePosition:Start()
    _enabled = true
    captureNow() -- simpan posisi saat toggle dinyalakan
    writePayloadToSM({
        enabled = true,
        pos     = _savedCF and { x = _savedCF.X, y = _savedCF.Y, z = _savedCF.Z } or nil,
        placeId = game.PlaceId,
        t       = os.time()
    })
    bindCharacterAdded()
    return true
end

function SavePosition:Stop()
    _enabled = false
    writePayloadToSM({
        enabled = false,
        pos     = _savedCF and { x = _savedCF.X, y = _savedCF.Y, z = _savedCF.Z } or nil,
        placeId = game.PlaceId,
        t       = os.time()
    })
    return true
end

function SavePosition:Cleanup()
    for _, c in ipairs(_cons) do pcall(function() c:Disconnect() end) end
    _cons, _controls = {}, {}
end

function SavePosition:GetStatus()
    return {
        enabled = _enabled,
        saved   = _savedCF and Vector3.new(_savedCF.X, _savedCF.Y, _savedCF.Z) or nil
    }
end

function SavePosition:SaveHere()
    if captureNow() then
        writePayloadToSM({
            enabled = _enabled,
            pos     = { x = _savedCF.X, y = _savedCF.Y, z = _savedCF.Z },
            placeId = game.PlaceId,
            t       = os.time()
        })
        return true
    end
    return false
end

return SavePosition
