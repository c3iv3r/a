-- module/f/saveposition.lua (v2.4 - standardized interface like AutoTeleportIsland)
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

-- Feature state (standardized)
local isInitialized = false
local controls      = {}
local _enabled      = false
local _savedCF      = nil
local _cons         = {}

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

-- ===== payload I/O with disabled check =====
local function findPayload()
    local folder, sub = getSMFolderAndSub()
    local base = join(folder, "settings", (sub ~= "" and sub or ""))
    local tried = {}

    local auto = autoloadName(folder, sub)
    local p1 = configPath(folder, sub, auto)
    if p1 then table.insert(tried, p1) end

    table.insert(tried, join(base, "default.json"))

    local lfs = (getfiles or listfiles)
    if lfs then
        local ok, files = pcall(lfs, base)
        if ok and type(files) == "table" then
            for _, f in ipairs(files) do
                if f:sub(-5) == ".json" then
                    local dup = false
                    for __, t in ipairs(tried) do if t == f then dup = true break end end
                    if not dup then table.insert(tried, f) end
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
                    -- SKIP jika enabled = false (ignore disabled payload)
                    if payload.enabled == false then
                        logger:debug("Skipping disabled payload from:", path)
                        goto continue
                    end
                    return payload, path
                end
            end
        end
        ::continue::
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

local function cleanupAllSaveData()
    local folder, sub = getSMFolderAndSub()
    local base = join(folder, "settings", (sub ~= "" and sub or ""))
    
    local filesToClean = {
        join(base, "default.json"),
        configPath(folder, sub, autoloadName(folder, sub))
    }
    
    local lfs = (getfiles or listfiles)
    if lfs then
        local ok, files = pcall(lfs, base)
        if ok and type(files) == "table" then
            for _, f in ipairs(files) do
                if f:sub(-5) == ".json" then
                    local duplicate = false
                    for _, existing in ipairs(filesToClean) do
                        if existing == f then duplicate = true break end
                    end
                    if not duplicate then table.insert(filesToClean, f) end
                end
            end
        end
    end
    
    local cleanedCount = 0
    for _, path in ipairs(filesToClean) do
        if path then
            local tbl = readJSON(path)
            if tbl and type(tbl.objects) == "table" then
                local idx = findInputObj(tbl.objects, IDX)
                if idx then
                    table.remove(tbl.objects, idx)
                    writeJSON(path, tbl)
                    cleanedCount = cleanedCount + 1
                    logger:debug("Cleaned SavePos data from:", path)
                end
            end
        end
    end
    
    local sm = rawget(getfenv(), "SaveManager")
    if type(sm) == "table" and sm.Library and sm.Library.Options and sm.Library.Options[IDX] then
        sm.Library.Options[IDX] = nil
    end
    
    logger:debug(string.format("Cleanup completed: %d files processed", cleanedCount))
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

-- ===== STANDARDIZED API (like AutoTeleportIsland) =====

-- Init / wiring from GUI (standardized interface)
function SavePosition:Init(guiControls)
    if isInitialized then
        logger:warn("Already initialized")
        return true
    end
    
    controls = guiControls or {}
    
    -- restore dari file (dengan disabled check)
    local payload = findPayload()
    if payload then
        _enabled = payload.enabled == true
        local p = payload.pos
        if p and p.x and p.y and p.z then _savedCF = CFrame.new(p.x, p.y, p.z) end
        logger:info("Restored from file: enabled=" .. tostring(_enabled))
    end

    bindCharacterAdded()

    -- rejoin: jangan buru-buru
    if _enabled and _savedCF then scheduleTeleport(5) end
    
    isInitialized = true
    logger:info("Initialized successfully")
    return true
end

-- Start feature (standardized interface)
function SavePosition:Start(config)
    if not isInitialized then
        logger:warn("Feature not initialized")
        return false
    end

    _enabled = true
    
    -- ALWAYS capture current position saat Start()
    if not captureNow() then
        logger:warn("Failed to capture current position")
        return false
    end

    savePayload({
        enabled = true,
        pos     = { x = _savedCF.X, y = _savedCF.Y, z = _savedCF.Z },
        t       = os.time()
    })

    bindCharacterAdded()
    scheduleTeleport(5)
    
    logger:info("Started: position captured and saved")
    
    -- Notification (standardized like AutoTeleportIsland)
    if _G.Noctis then
        _G.Noctis:Notify({
            Title = "Save Position",
            Description = "Position saved! Will teleport on rejoin/respawn",
            Duration = 3
        })
    end
    
    return true
end

-- Stop feature (standardized interface)
function SavePosition:Stop()
    if not isInitialized then
        logger:warn("Feature not initialized")
        return false
    end

    _enabled = false
    _savedCF = nil
    
    cleanupAllSaveData()
    
    logger:info("Stopped: position cleared and cleanup completed")
    
    -- Notification (standardized)
    if _G.Noctis then
        _G.Noctis:Notify({
            Title = "Save Position",
            Description = "Position cleared and disabled",
            Duration = 2
        })
    end
    
    return true
end

-- Get status (standardized interface)
function SavePosition:GetStatus()
    return {
        initialized = isInitialized,
        enabled     = _enabled,
        saved       = _savedCF and Vector3.new(_savedCF.X, _savedCF.Y, _savedCF.Z) or nil
    }
end

-- Cleanup (standardized interface)
function SavePosition:Cleanup()
    logger:info("Cleaning up...")
    for _, c in ipairs(_cons) do pcall(function() c:Disconnect() end) end
    _cons, controls = {}, {}
    isInitialized = false
    _enabled = false
    _savedCF = nil
end

-- Additional helper methods (optional)
function SavePosition:SaveHere()
    if not isInitialized then
        logger:warn("Feature not initialized")
        return false
    end
    
    if captureNow() then
        savePayload({
            enabled = _enabled,
            pos     = { x = _savedCF.X, y = _savedCF.Y, z = _savedCF.Z },
            t       = os.time()
        })
        logger:info("Manual save: current position captured")
        return true
    end
    return false
end

return SavePosition