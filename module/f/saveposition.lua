-- module/f/saveposition.lua
-- Interface: Init(controls), Start(opts?), Stop(), Cleanup(), GetStatus()
-- No WindUI dependency. Uses SaveManager folder layout if available.

local SavePosition = {}
SavePosition.__index = SavePosition

-- services
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local LocalPlayer = Players.LocalPlayer

-- state
local _enabled = false
local _savedCF  = nil
local _cons = {}
local _controls = {}
local _logger = _G.Logger and _G.Logger.new("SavePosition") or {
    info = function() end, 
    warn = function()end,
    debug = function()end
}

-- ===== file IO helpers (follow SaveManager paths) =====
local function has(x) return x ~= nil end

local function getFolderAndConfig()
    local folder = "Noctis/Fishit"
    local sub    = ""
    local cfg    = "default"

    local sm = rawget(getfenv(), "SaveManager")
    if type(sm) == "table" then
        if has(sm.Folder) then folder = tostring(sm.Folder) end
        if has(sm.SubFolder) then sub = tostring(sm.SubFolder) end
        if type(sm.GetAutoloadConfig) == "function" then
            local ok, name = pcall(function() return sm:GetAutoloadConfig() end)
            if ok and name and name ~= "" and name ~= "none" then
                cfg = tostring(name)
            end
        end
    end
    return folder, sub, cfg
end

local function ensureFolders()
    local folder, sub = getFolderAndConfig()
    local base = folder .. "/settings"
    if sub ~= "" then base = base .. "/" .. sub end
    pcall(function()
        if not isfolder(folder) then makefolder(folder) end
        if not isfolder(folder .. "/settings") then makefolder(folder .. "/settings") end
        if sub ~= "" and not isfolder(base) then makefolder(base) end
    end)
    return base
end

local function getDataPath()
    local base = ensureFolders()
    local _, _, cfg = getFolderAndConfig()
    return string.format("%s/%s.savepos.json", base, cfg)
end

local function saveState()
    local path = getDataPath()
    local payload = {
        enabled = _enabled and true or false,
        placeId = game.PlaceId,
        pos = (_savedCF and {x=_savedCF.X, y=_savedCF.Y, z=_savedCF.Z}) or nil,
        t = os.time()
    }
    local ok, encoded = pcall(function() return game:GetService("HttpService"):JSONEncode(payload) end)
    if ok then pcall(writefile, path, encoded) end
end

local function loadState()
    local path = getDataPath()
    if not isfile(path) then return false, nil end
    local ok, decoded = pcall(function()
        local s = readfile(path)
        return game:GetService("HttpService"):JSONDecode(s)
    end)
    if not ok or type(decoded) ~= "table" then return false, nil end

    local enabled = decoded.enabled == true
    local cf = nil
    if decoded.pos and decoded.pos.x and decoded.pos.y and decoded.pos.z then
        cf = CFrame.new(decoded.pos.x, decoded.pos.y, decoded.pos.z)
    end
    return enabled, cf
end

-- ===== core =====
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

local function doTeleport()
    if not _enabled or not _savedCF then return end
    local hrp = waitForHRP(8)
    if not hrp then
        _logger:warn("HRP not ready; skip teleport")
        return
    end
    pcall(function()
        hrp.CFrame = _savedCF + Vector3.new(0, 6, 0) -- lift a bit to avoid falling
    end)
end

local function bindCharacterAdded()
    -- clear old
    for _, c in ipairs(_cons) do pcall(function() c:Disconnect() end) end
    _cons = {}
    _cons[#_cons+1] = LocalPlayer.CharacterAdded:Connect(function()
        -- slight defer so accessories/terrain load first
        task.defer(function()
            if _enabled then doTeleport() end
        end)
    end)
end

function SavePosition:_captureCurrent()
    local hrp = waitForHRP(3)
    if not hrp then
        _logger:warn("Can't capture position: HRP missing")
        return false
    end
    _savedCF = hrp.CFrame
    _logger:info(("Saved position @ (%.1f, %.1f, %.1f)"):format(_savedCF.X, _savedCF.Y, _savedCF.Z))
    return true
end

-- ====== API ======
function SavePosition:Init(guiControls)
    _controls = guiControls or {}
    -- restore from disk ASAP (so rejoin works even sebelum SaveManager load UI)
    local en, cf = loadState()
    _enabled = en or false
    _savedCF = cf
    bindCharacterAdded()
    if _enabled and _savedCF then
        -- if already in-game, also try once
        task.defer(doTeleport)
    end
    return true
end

function SavePosition:Start(opts)
    _enabled = true
    -- when user toggles ON, we SAVE current position NOW
    if self:_captureCurrent() then
        saveState()
    else
        -- if failed capture, still persist enabled=true; will try next spawn
        saveState()
    end
    bindCharacterAdded()
    return true
end

function SavePosition:Stop()
    _enabled = false
    saveState()
    -- keep saved CF (biar bisa dipakai lagi kalau ON), tapi tidak auto-tele saat respawn
    return true
end

function SavePosition:Cleanup()
    for _, c in ipairs(_cons) do pcall(function() c:Disconnect() end) end
    _cons = {}
    _controls = {}
end

function SavePosition:GetStatus()
    return {
        enabled = _enabled,
        saved = _savedCF and Vector3.new(_savedCF.X, _savedCF.Y, _savedCF.Z) or nil
    }
end

-- optional utility: manual re-save at current spot
function SavePosition:SaveHere()
    if self:_captureCurrent() then
        saveState()
        return true
    end
    return false
end

return SavePosition
