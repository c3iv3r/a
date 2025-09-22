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

-- ===== PATCHED: Fix autoload priority - ensure autoload config takes precedence =====
local function findPayload()
    local folder, sub = getSMFolderAndSub()
    local auto = autoloadName(folder, sub)

    -- PRIORITY 1: Check autoload config first (and ONLY if it has data)
    if auto ~= "none" then
        local path = configPath(folder, sub, auto)
        if path then
            local tbl = readJSON(path)
            if tbl and type(tbl.objects) == "table" then
                local _, obj = findInputObj(tbl.objects, IDX)
                if obj and type(obj.text) == "string" and obj.text ~= "" then
                    local ok, payload = pcall(function() return HttpService:JSONDecode(obj.text) end)
                    if ok and type(payload) == "table" then
                        -- DEBUG: Log which file was used
                        if logger and logger.info then
                            logger:info("SavePosition: Loaded from autoload config:", auto)
                        end
                        return payload, path
                    end
                end
            end
        end
    end

    -- PRIORITY 2: Fallback to default.json ONLY if no autoload or autoload has no data
    local base = join(folder, "settings", (sub ~= "" and sub or ""))
    local defaultPath = join(base, "default.json")
    local tbl = readJSON(defaultPath)
    if tbl and type(tbl.objects) == "table" then
        local _, obj = findInputObj(tbl.objects, IDX)
        if obj and type(obj.text) == "string" and obj.text ~= "" then
            local ok, payload = pcall(function() return HttpService:JSONDecode(obj.text) end)
            if ok and type(payload) == "table" then
                -- DEBUG: Log fallback usage
                if logger and logger.info then
                    logger:info("SavePosition: Fallback to default.json")
                end
                return payload, defaultPath
            end
        end
    end

    -- PRIORITY 3: Last resort - scan other .json files
    local tried = {}
    local lfs = (getfiles or listfiles)
    if lfs then
        local ok, files = pcall(lfs, base)
        if ok and type(files) == "table" then
            for _, f in ipairs(files) do
                if f:sub(-5) == ".json" and not f:find("default.json") then
                    local filename = f:match("([^/\\]+)$")
                    if filename ~= auto .. ".json" then  -- Skip already checked autoload
                        table.insert(tried, f)
                    end
                end
            end
        end
    end

    for _, path in ipairs(tried) do
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

-- ===== PATCHED: Smart savePayload - only create default.json when needed =====
local function savePayload(payload)
    -- ALWAYS register to SaveManager untuk session state
    local sm = rawget(getfenv(), "SaveManager")
    if type(sm) == "table" and sm.Library and sm.Library.Options then
        sm.Library.Options[IDX] = sm.Library.Options[IDX] or {
            Type = "Input",
            SetValue = function(self, v) self.Value = v end
        }
        sm.Library.Options[IDX].Value = HttpService:JSONEncode(payload)
    end

    -- SMART FILE CREATION: Only create files when necessary
    local folder, sub = getSMFolderAndSub()
    local auto = autoloadName(folder, sub)

    if auto ~= "none" then
        -- User has autoload config - inject into that config
        local path = configPath(folder, sub, auto)
        if path then
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
        end
    else
        -- No autoload config - create default.json for session persistence
        local name = "default"
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
-- ===== PATCHED: Smart Init() - respect user intent =====
function SavePosition:Init(a, b)
    _controls = (type(a) == "table" and a ~= self and a) or b or {}

    -- PATCH: Only restore from autoload configs, ignore default.json for fresh sessions
    local folder, sub = getSMFolderAndSub()
    local auto = autoloadName(folder, sub)

    if auto ~= "none" then
        -- User has autoload config - safe to restore
        local payload = findPayload()
        if payload and payload.enabled == true then
            if payload.cframe then
                _savedCF = deserializeCFrame(payload.cframe)
            elseif payload.pos and payload.pos.x and payload.pos.y and payload.pos.z then
                _savedCF = CFrame.new(payload.pos.x, payload.pos.y, payload.pos.z)
            end
            _enabled = true
        else
            _enabled = false
            _savedCF = nil
        end
    else
        -- No autoload config - start fresh, ignore any default.json
        _enabled = false
        _savedCF = nil
    end

    bindCharacterAdded()

    -- Only schedule teleport if restored from autoload config
    if _enabled and _savedCF then 
        scheduleTeleport(5) 
    end
    return true
end

-- ===== PATCHED: Start() with delayed SaveManager virtual input detection =====
function SavePosition:Start()
    _enabled = true

    -- PATCH: Function to check SaveManager virtual input
    local function checkVirtualInput()
        local sm = rawget(getfenv(), "SaveManager")
        if type(sm) == "table" and sm.Library and sm.Library.Options and sm.Library.Options[IDX] then
            local virtualInput = sm.Library.Options[IDX]
            if virtualInput and virtualInput.Value and virtualInput.Value ~= "" then
                local ok, payload = pcall(function() 
                    return HttpService:JSONDecode(virtualInput.Value) 
                end)
                if ok and type(payload) == "table" and payload.cframe then
                    _savedCF = deserializeCFrame(payload.cframe)
                    if logger and logger.info then
                        logger:info("SavePosition: Loaded from SaveManager virtual input (manual config load)")
                    end
                    return true
                end
            end
        end
        return false
    end

    -- Try immediate check first
    local foundVirtualData = checkVirtualInput()

    if not foundVirtualData then
        -- Wait a bit for SaveManager to finish loading (async)
        task.wait(0.1)
        foundVirtualData = checkVirtualInput()
    end

    if not foundVirtualData then
        -- Still no data, try one more time with longer delay
        task.wait(0.2)
        foundVirtualData = checkVirtualInput()
    end

    -- Fallback: capture current position if no saved data found
    if not foundVirtualData and not _savedCF then
        captureNow()
        if logger and logger.info then
            logger:info("SavePosition: Captured current position (fresh start)")
        end
    end

    -- Register current state to SaveManager
    savePayload({
        enabled = true,
        cframe  = _savedCF and serializeCFrame(_savedCF) or nil,
        t       = os.time()
    })

    bindCharacterAdded()
    scheduleTeleport(5)
    return true
end

-- ===== PATCHED: Clean Stop() - register to SaveManager + inject to config =====
function SavePosition:Stop()
    _enabled = false
    _savedCF = nil  -- Clear position dari memory

    -- PATCH: Register cleared state to SaveManager + inject to autoload config
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

-- ===== PATCHED: SaveHere() - register to SaveManager + inject to config =====
function SavePosition:SaveHere()
    if captureNow() then
        -- PATCH: Register to SaveManager + inject to autoload config
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