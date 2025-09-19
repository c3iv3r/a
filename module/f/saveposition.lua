-- module/f/saveposition.lua  (v2.3 - strict autoload + forceCapture)
local SavePosition = {}
SavePosition.__index = SavePosition

local Players     = game:GetService("Players")
local HttpService = game:GetService("HttpService")
local LocalPlayer = Players.LocalPlayer

local IDX = "SavePos_Data"
local FALLBACK_FOLDER = "Noctis/FishIt"

local _enabled  = false
local _savedCF  = nil
local _cons     = {}
local _controls = {}

local function join(...) return table.concat({...}, "/") end

local function getSMFolderAndSub()
    local sm = rawget(getfenv(), "SaveManager")
    local folder, sub = FALLBACK_FOLDER, ""
    if type(sm) == "table" then
        if type(sm.Folder) == "string" and sm.Folder ~= "" then folder = sm.Folder end
        if type(sm.SubFolder) == "string" and sm.SubFolder ~= "" then sub = sm.SubFolder end
    end
    return folder, sub
end

local function autoloadName(folder, sub)
    local path = join(folder, "settings", (sub ~= "" and sub or ""), "autoload.txt")
    if isfile and isfile(path) then
        local ok, name = pcall(readfile, path)
        if ok and name and name ~= "" then return tostring(name) end
    end
    return "none"
end

local function configPath(folder, sub, name)
    if not name or name == "" or name == "none" then return nil end
    local base = join(folder, "settings")
    if sub ~= "" then base = join(base, sub) end
    return join(base, name .. ".json")
end

local function readJSON(path)
    if not path or not (isfile and isfile(path)) then return nil end
    local ok, data = pcall(function() return HttpService:JSONDecode(readfile(path)) end)
    return ok and data or nil
end

local function writeJSON(path, tbl)
    if not path or not tbl then return end
    local ok, s = pcall(function() return HttpService:JSONEncode(tbl) end)
    if ok then pcall(writefile, path, s) end
end

local function findInputObj(objects, idx)
    if type(objects) ~= "table" then return nil, nil end
    for i, o in ipairs(objects) do
        if type(o) == "table" and o.type == "Input" and o.idx == idx then
            return i, o
        end
    end
    return nil, nil
end

-- ===== STRICT PAYLOAD (kalau autoload ada → hanya baca file itu) =====
local function findPayload()
    local folder, sub = getSMFolderAndSub()
    local auto = autoloadName(folder, sub)

    if auto ~= "none" then
        local path = configPath(folder, sub, auto)
        local tbl = readJSON(path)
        if tbl and type(tbl.objects) == "table" then
            local _, obj = findInputObj(tbl.objects, IDX)
            if obj and type(obj.text) == "string" and obj.text ~= "" then
                local ok, payload = pcall(function() return HttpService:JSONDecode(obj.text) end)
                if ok and type(payload) == "table" then
                    return payload, path
                end
            end
        end
        return nil, nil
    end

    -- kalau autoload belum diset → fallback ke default.json
    local base = join(folder, "settings", (sub ~= "" and sub or ""))
    local path = join(base, "default.json")
    local tbl  = readJSON(path)
    if tbl and type(tbl.objects) == "table" then
        local _, obj = findInputObj(tbl.objects, IDX)
        if obj and type(obj.text) == "string" and obj.text ~= "" then
            local ok, payload = pcall(function() return HttpService:JSONDecode(obj.text) end)
            if ok and type(payload) == "table" then
                return payload, path
            end
        end
    end
    return nil, nil
end

local function savePayload(payload)
    local folder, sub = getSMFolderAndSub()
    local name = autoloadName(folder, sub)
    if name == "none" then name = "default" end
    local path = configPath(folder, sub, name)

    local tbl = readJSON(path) or { objects = {} }
    if type(tbl.objects) ~= "table" then tbl.objects = {} end

    local idx, obj = findInputObj(tbl.objects, IDX)
    local text = HttpService:JSONEncode(payload)

    if idx then
        obj.text = text
        tbl.objects[idx] = obj
    else
        table.insert(tbl.objects, { type = "Input", idx = IDX, text = text })
    end
    writeJSON(path, tbl)

    local sm = rawget(getfenv(), "SaveManager")
    if type(sm) == "table" and sm.Library and sm.Library.Options then
        sm.Library.Options[IDX] = sm.Library.Options[IDX] or {
            Type = "Input",
            SetValue = function(self, v) self.Value = v end
        }
        sm.Library.Options[IDX].Value = text
    end
end

-- ===== teleport helpers =====
local function waitHRP(timeout)
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

local function teleportCF(cf)
    local hrp = waitHRP(8)
    if not hrp or not cf then return end
    pcall(function()
        hrp.CFrame = cf + Vector3.new(0, 6, 0)
    end)
end

local function scheduleTeleport(delaySec)
    task.delay(delaySec or 5, function()
        if _enabled and _savedCF then teleportCF(_savedCF) end
    end)
end

local function bindCharacterAdded()
    for _, c in ipairs(_cons) do pcall(function() c:Disconnect() end) end
    _cons = {}
    table.insert(_cons, LocalPlayer.CharacterAdded:Connect(function()
        scheduleTeleport(5)
    end))
end

local function captureNow()
    local hrp = waitHRP(3)
    if not hrp then return false end
    _savedCF = hrp.CFrame
    return true
end

-- ===== API =====
function SavePosition:Init(a, b)
    _controls = (type(a) == "table" and a ~= self and a) or b or {}

    local payload = findPayload()
    if payload then
        _enabled = payload.enabled == true
        local p = payload.pos
        if p and p.x and p.y and p.z then _savedCF = CFrame.new(p.x, p.y, p.z) end
    end

    bindCharacterAdded()
    if _enabled and _savedCF then scheduleTeleport(5) end
    return true
end

-- Start(opts): opts bisa boolean (forceCapture) atau {forceCapture=true}
function SavePosition:Start(opts)
    local forceCapture = (type(opts) == "boolean" and opts)
                      or (type(opts) == "table" and opts.forceCapture) or false

    -- kalau user minta ganti posisi → paksa capture
    if forceCapture then
        captureNow()
    else
        -- defensive: kalau belum punya posisi, coba baca dari autoload dulu
        if not _savedCF then
            local payload = findPayload()
            if payload and payload.pos and payload.pos.x and payload.pos.y and payload.pos.z then
                _savedCF = CFrame.new(payload.pos.x, payload.pos.y, payload.pos.z)
            else
                -- tetap capture terakhir kalau kosong
                captureNow()
            end
        end
    end

    _enabled = true
    savePayload({
        enabled = true,
        pos     = _savedCF and { x = _savedCF.X, y = _savedCF.Y, z = _savedCF.Z } or nil,
        t       = os.time()
    })

    scheduleTeleport(5)
    return true
end

function SavePosition:Stop()
    _enabled = false
    -- JANGAN hapus pos di file; biarin user bisa ON lagi tanpa kehilangan anchor.
    savePayload({
        enabled = false,
        pos     = _savedCF and { x = _savedCF.X, y = _savedCF.Y, z = _savedCF.Z } or nil,
        t       = os.time()
    })
    return true
end

function SavePosition:Cleanup()
    for _, c in ipairs(_cons) do pcall(function() c:Disconnect() end) end
    _cons, _controls = {}, {}
end

function SavePosition:GetStatus()
    return { enabled = _enabled, saved = _savedCF and Vector3.new(_savedCF.X, _savedCF.Y, _savedCF.Z) or nil }
end

function SavePosition:SaveHere()
    if captureNow() then
        savePayload({
            enabled = _enabled,
            pos     = { x = _savedCF.X, y = _savedCF.Y, z = _savedCF.Z },
            t       = os.time()
        })
        return true
    end
    return false
end

-- Opsional: nonaktifkan SavePos_Data di default.json kalau autoload sudah ada
function SavePosition:DisableDefault()
    local folder, sub = getSMFolderAndSub()
    if autoloadName(folder, sub) == "none" then return end
    local base = join(folder, "settings", (sub ~= "" and sub or ""))
    local path = join(base, "default.json")
    local tbl = readJSON(path); if not tbl or type(tbl.objects) ~= "table" then return end
    local i, obj = findInputObj(tbl.objects, IDX)
    if i and obj then
        obj.text = HttpService:JSONEncode({ enabled = false })
        tbl.objects[i] = obj
        writeJSON(path, tbl)
    end
end

return SavePosition
