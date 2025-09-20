-- module/f/saveposition.lua  (v2.4 - PATCHED: No default.json + Safe toggle behavior)
local SavePosition = {}
SavePosition.__index = SavePosition

local logger = _G.Logger and _G.Logger.new("SavePosition") or {
    debug = function() end,
    info = function() end,
    warn = function() end,
    error = function() end
}

local Players     = game:GetService("Players")
local HttpService = game:GetService("HttpService")
local LocalPlayer = Players.LocalPlayer

-- kunci "virtual Input" di JSON SaveManager
local IDX = "SavePos_Data"
-- samain ke SaveManager:SetFolder(...) lu; fallback aman kalau SM belum ready
local FALLBACK_FOLDER = "Noctis/FishIt"

-- state
local _enabled  = false
local _savedCF  = nil
local _cons     = {}
local _controls = {}

-- ===== path helpers =====
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

local function findInputObj(objects, idx)
    if type(objects) ~= "table" then return nil, nil end
    for i, o in ipairs(objects) do
        if type(o) == "table" and o.type == "Input" and o.idx == idx then
            return i, o
        end
    end
    return nil, nil
end

-- ===== PATCHED: Only read from SaveManager configs, no default.json =====
local function findPayload()
    local folder, sub = getSMFolderAndSub()
    local auto = autoloadName(folder, sub)
    
    -- PATCH: Only look for saved configs, ignore if no autoload
    if auto == "none" then 
        return nil, nil  -- No autoload = no persistence
    end
    
    local path = configPath(folder, sub, auto)
    local tbl = readJSON(path)
    
    if tbl and type(tbl.objects) == "table" then
        local _, obj = findInputObj(tbl.objects, IDX)
        if obj and type(obj.text) == "string" and obj.text ~= "" then
            local ok, payload = pcall(function() 
                return HttpService:JSONDecode(obj.text) 
            end)
            if ok and type(payload) == "table" then
                return payload, path
            end
        end
    end
    return nil, nil
end

-- Helper function untuk serialize CFrame
local function serializeCFrame(cf)
    if not cf then return nil end
    local x, y, z, r00, r01, r02, r10, r11, r12, r20, r21, r22 = cf:GetComponents()
    return {
        x = x, y = y, z = z,
        r00 = r00, r01 = r01, r02 = r02,
        r10 = r10, r11 = r11, r12 = r12,
        r20 = r20, r21 = r21, r22 = r22
    }
end

-- Helper function untuk deserialize CFrame
local function deserializeCFrame(data)
    if not data or not data.x then return nil end
    return CFrame.new(
        data.x, data.y, data.z,
        data.r00, data.r01, data.r02,
        data.r10, data.r11, data.r12,
        data.r20, data.r21, data.r22
    )
end

-- ===== PATCHED: Only register to SaveManager, no file creation =====
local function savePayload(payload)
    -- ONLY register "virtual input" ke SaveManager, NO file creation
    local sm = rawget(getfenv(), "SaveManager")
    if type(sm) == "table" and sm.Library and sm.Library.Options then
        sm.Library.Options[IDX] = sm.Library.Options[IDX] or {
            Type = "Input",
            SetValue = function(self, v) self.Value = v end
        }
        sm.Library.Options[IDX].Value = HttpService:JSONEncode(payload)
    end
    
    -- PATCH: Remove all file creation logic - let SaveManager handle persistence
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
        hrp.CFrame = cf + Vector3.new(0, 6, 0) -- naik dikit biar nggak nyangkut
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
        scheduleTeleport(5) -- respawn: tunggu 5 detik
    end))
end

-- ===== core =====
local function captureNow()
    local hrp = waitHRP(3)
    if not hrp then return false end
    _savedCF = hrp.CFrame
    return true
end

-- ===== API =====
-- ===== PATCHED: Safe Init() - only restore from saved configs =====
function SavePosition:Init(a, b)
    _controls = (type(a) == "table" and a ~= self and a) or b or {}

    -- PATCH: Only restore if user has saved autoload config
    local payload = findPayload()
    if payload and payload.enabled == true then
        -- IMPROVED: Support both old format (pos) and new format (cframe)
        if payload.cframe then
            _savedCF = deserializeCFrame(payload.cframe)
        elseif payload.pos and payload.pos.x and payload.pos.y and payload.pos.z then
            -- Backward compatibility dengan format lama (position only)
            _savedCF = CFrame.new(payload.pos.x, payload.pos.y, payload.pos.z)
        end
        _enabled = true  -- Only enable if restored from saved config
    else
        -- PATCH: Default to disabled if no saved config
        _enabled = false
        _savedCF = nil
    end

    bindCharacterAdded()

    -- PATCH: Only schedule teleport if restored from saved config
    if _enabled and _savedCF then 
        scheduleTeleport(5) 
    end
    return true
end

-- ===== PATCHED: Clean Start() - no file creation =====
function SavePosition:Start()
    _enabled = true

    -- hanya capture kalau BELUM punya save lama
    if not _savedCF then
        captureNow()
    end

    -- PATCH: Only register to SaveManager, no file creation
    savePayload({
        enabled = true,
        cframe  = _savedCF and serializeCFrame(_savedCF) or nil,
        t       = os.time()
    })

    bindCharacterAdded()
    -- pastikan tetap teleport 5 detik (cover urutan eksekusi acak)
    scheduleTeleport(5)
    return true
end

-- ===== PATCHED: Clean Stop() - memory only =====
function SavePosition:Stop()
    _enabled = false
    _savedCF = nil  -- Clear position dari memory
    
    -- PATCH: Only register cleared state to SaveManager, no file creation
    savePayload({
        enabled = false,
        cframe  = nil,
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

-- ===== PATCHED: SaveHere() - memory only =====
function SavePosition:SaveHere()
    if captureNow() then
        -- PATCH: Only register to SaveManager, no file creation
        savePayload({
            enabled = _enabled,
            cframe  = serializeCFrame(_savedCF),
            t       = os.time()
        })
        return true
    end
    return false
end

return SavePosition