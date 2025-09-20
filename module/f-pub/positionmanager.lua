-- module/f/positionmanager.lua (v1.0 - Custom Position Manager)
local PositionManager = {}
PositionManager.__index = PositionManager

local logger = _G.Logger and _G.Logger.new("PositionManager") or {
    debug = function() end,
    info = function() end,
    warn = function() end,
    error = function() end
}

local Players = game:GetService("Players")
local HttpService = game:GetService("HttpService")
local LocalPlayer = Players.LocalPlayer

-- kunci untuk JSON SaveManager
local IDX = "CustomPositions_Data"
local FALLBACK_FOLDER = "Noctis/FishIt"

-- state
local _positions = {} -- {positionName = {x, y, z, r00, r01, ...}, ...}
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

-- ===== CFrame helpers =====
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

local function deserializeCFrame(data)
    if not data or not data.x then return nil end
    return CFrame.new(
        data.x, data.y, data.z,
        data.r00, data.r01, data.r02,
        data.r10, data.r11, data.r12,
        data.r20, data.r21, data.r22
    )
end

-- ===== payload I/O =====
local function loadPositions()
    local folder, sub = getSMFolderAndSub()
    local base = join(folder, "settings", (sub ~= "" and sub or ""))
    local tried = {}

    -- prioritas: autoload.json -> default.json -> scan files
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
                local ok, positions = pcall(function() return HttpService:JSONDecode(obj.text) end)
                if ok and type(positions) == "table" then
                    return positions
                end
            end
        end
    end
    return {}
end

local function savePositions(positions)
    local folder, sub = getSMFolderAndSub()
    local name = autoloadName(folder, sub)
    if name == "none" then name = "default" end
    local path = configPath(folder, sub, name)

    local tbl = readJSON(path) or { objects = {} }
    if type(tbl.objects) ~= "table" then tbl.objects = {} end

    local idx, obj = findInputObj(tbl.objects, IDX)
    local text = HttpService:JSONEncode(positions)

    if idx then
        obj.text = text
        tbl.objects[idx] = obj
    else
        table.insert(tbl.objects, { type = "Input", idx = IDX, text = text })
    end
    writeJSON(path, tbl)

    -- register virtual input ke SaveManager
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

local function teleportToCFrame(cf)
    local hrp = waitHRP(5)
    if not hrp or not cf then return false end
    pcall(function()
        hrp.CFrame = cf + Vector3.new(0, 3, 0)
    end)
    return true
end

-- ===== API =====
function PositionManager:Init(a, b)
    _controls = (type(a) == "table" and a ~= self and a) or b or {}
    
    -- load positions dari file
    _positions = loadPositions()
    
    -- update dropdown dengan positions yang tersimpan
    self:RefreshDropdown()
    
    return true
end

function PositionManager:AddPosition(name)
    if not name or name == "" or name == "Position Name" then 
        return false, "Invalid name"
    end
    
    local hrp = waitHRP(3)
    if not hrp then 
        return false, "Character not found"
    end
    
    -- serialize current position
    local cfData = serializeCFrame(hrp.CFrame)
    if not cfData then
        return false, "Failed to get position"
    end
    
    _positions[name] = cfData
    savePositions(_positions)
    
    self:RefreshDropdown()
    
    logger:info(string.format("Added position '%s' at %.1f, %.1f, %.1f", 
        name, cfData.x, cfData.y, cfData.z))
    
    return true
end

function PositionManager:DeletePosition(name)
    if not name or not _positions[name] then
        return false, "Position not found"
    end
    
    _positions[name] = nil
    savePositions(_positions)
    
    self:RefreshDropdown()
    
    logger:info(string.format("Deleted position '%s'", name))
    
    return true
end

function PositionManager:TeleportToPosition(name)
    if not name or not _positions[name] then
        return false, "Position not found"
    end
    
    local cfData = _positions[name]
    local cf = deserializeCFrame(cfData)
    
    if not cf then
        return false, "Invalid position data"
    end
    
    local success = teleportToCFrame(cf)
    
    if success then
        logger:info(string.format("Teleported to position '%s'", name))
    else
        logger:warn(string.format("Failed to teleport to position '%s'", name))
    end
    
    return success
end

function PositionManager:GetPositionsList()
    local list = {}
    for name, _ in pairs(_positions) do
        table.insert(list, name)
    end
    table.sort(list)
    return list
end

function PositionManager:RefreshDropdown()
    local list = self:GetPositionsList()
    
    if #list == 0 then
        list = {"No Positions"}
    end
    
    -- update dropdown jika ada controls
    if _controls.dropdown and _controls.dropdown.SetValues then
        _controls.dropdown:SetValues(list)
    end
    
    return list
end

function PositionManager:GetStatus()
    local count = 0
    for _ in pairs(_positions) do count = count + 1 end
    
    return {
        totalPositions = count,
        positions = self:GetPositionsList()
    }
end

return PositionManager