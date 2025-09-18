-- ===========================
-- SAVE POSITION FEATURE
-- Matches AutoTeleportIsland-style API (Init, Start, Stop, Cleanup)
-- Hard teleport (Y offset = +6), logger-compatible, GUI-wireable.
-- Supports session persistence via writefile/readfile if available.
-- Optional auto-restore on join/respawn when Save Position toggle is ON.
-- ===========================

local SavePositionFeature = {}
SavePositionFeature.__index = SavePositionFeature

-- ===== Logger (same pattern as AutoTeleportIsland) =====
local logger = _G.Logger and _G.Logger.new("SavePosition") or {
    debug = function() end,
    info  = function() end,
    warn  = function() end,
    error = function() end,
}

-- ===== Services =====
local Players       = game:GetService("Players")
local RunService    = game:GetService("RunService")
local LocalPlayer   = Players.LocalPlayer
local Workspace     = game:GetService("Workspace")

-- ===== Internal state =====
local isInitialized         = false
local isRunning             = false
local controls              = {}           -- GUI control refs if needed
local savedPositions        = {}           -- map name -> CFrame
local selectedName          = nil          -- current selected key in dropdown
local saveToggleEnabled     = false        -- Save Position toggle state
local saveAnchorCFrame      = nil          -- anchor cf captured by toggle
local charAddedConn         = nil
local heartbeatConn         = nil

-- ===== Persistence (optional) =====
local CAN_FS = (typeof(writefile) == "function") and (typeof(readfile) == "function") and (typeof(isfile) == "function")
local SAVE_PATH = ".devlogic/saveposition.json"

local function cframeToTable(cf)
    local a,b,c,d,e,f,g,h,i,x,y,z = cf:GetComponents()
    return {a,b,c,d,e,f,g,h,i,x,y,z}
end

local function tableToCFrame(t)
    if type(t) ~= "table" or #t < 12 then return nil end
    return CFrame.new(
        t[10], t[11], t[12],
        t[1], t[2], t[3],
        t[4], t[5], t[6],
        t[7], t[8], t[9]
    )
end

local function loadPersisted()
    if not CAN_FS then return end
    local ok, data = pcall(function()
        if isfile(SAVE_PATH) then
            return game.HttpService:JSONDecode(readfile(SAVE_PATH))
        end
    end)
    if not ok or not data then return end

    -- savedPositions
    if type(data.savedPositions) == "table" then
        for name, arr in pairs(data.savedPositions) do
            local cf = tableToCFrame(arr)
            if cf then savedPositions[name] = cf end
        end
    end
    -- anchor + toggle
    if data.saveToggleEnabled and type(data.saveAnchorCFrame) == "table" then
        saveToggleEnabled = true
        saveAnchorCFrame  = tableToCFrame(data.saveAnchorCFrame)
    end
    if type(data.selectedName) == "string" then
        selectedName = data.selectedName
    end
    logger:info("Loaded persisted save positions (", tostring(next(savedPositions) ~= nil), ")")
end

local function persist()
    if not CAN_FS then return end
    local obj = {
        savedPositions    = {},
        saveToggleEnabled = saveToggleEnabled or false,
        saveAnchorCFrame  = saveAnchorCFrame and cframeToTable(saveAnchorCFrame) or nil,
        selectedName      = selectedName
    }
    for name, cf in pairs(savedPositions) do
        obj.savedPositions[name] = cframeToTable(cf)
    end
    pcall(function()
        -- ensure folder-ish path is ok in your executor; if not, flatten name
        writefile(SAVE_PATH, game.HttpService:JSONEncode(obj))
    end)
end

-- ===== Utilities =====
local function getHRP()
    local char = LocalPlayer.Character
    if not char then return nil end
    return char:FindFirstChild("HumanoidRootPart")
end

local function ensureCharacterReady(timeout)
    timeout = timeout or 8
    local char = LocalPlayer.Character or LocalPlayer.CharacterAdded:Wait()
    local t0 = os.clock()
    while (os.clock() - t0) < timeout do
        local hrp = char:FindFirstChild("HumanoidRootPart")
        local hum = char:FindFirstChildOfClass("Humanoid")
        if hrp and hum and hum.Health > 0 then
            return hrp
        end
        RunService.Heartbeat:Wait()
    end
    return getHRP()
end

-- Hard teleport with +Y offset, zero velocity (helps avoid “jatoh”)
function SavePositionFeature:TeleportToCFrame(cf)
    local hrp = ensureCharacterReady(6)
    if not hrp then
        logger:warn("HumanoidRootPart not ready")
        return false
    end

    local ok = pcall(function()
        local target = cf + Vector3.new(0, 6, 0)
        local char   = hrp.Parent
        local hum    = char and char:FindFirstChildOfClass("Humanoid")

        -- briefly set platform stand to avoid physics spikes
        if hum then hum:ChangeState(Enum.HumanoidStateType.Physics) end
        hrp.AssemblyLinearVelocity = Vector3.zero
        hrp.AssemblyAngularVelocity = Vector3.zero
        hrp.CFrame = target
        -- small wait, then re-enable normal state
        task.delay(0.15, function()
            if hum and hum.Health > 0 then
                hum:ChangeState(Enum.HumanoidStateType.RunningNoPhysics)
                task.delay(0.05, function()
                    if hum and hum.Health > 0 then
                        hum:ChangeState(Enum.HumanoidStateType.Running)
                    end
                end)
            end
        end)
    end)

    if not ok then
        logger:warn("Teleport pcall failed")
        return false
    end
    return true
end

-- ===== Public API =====

function SavePositionFeature:Init(guiControls)
    if isInitialized then return true end
    controls = guiControls or {}
    loadPersisted()

    -- Auto-restore on join if toggle was ON last time and we have anchor
    if saveToggleEnabled and saveAnchorCFrame then
        -- wait a bit for map to stream in then restore
        task.spawn(function()
            task.wait(1.0)
            self:TeleportToCFrame(saveAnchorCFrame)
        end)
    end

    isInitialized = true
    logger:info("Initialized SavePositionFeature")
    return true
end

-- Start/Stop can be used if you want a background guard-loop (optional).
-- Here we use it to keep player near anchor while toggle is ON (lightweight).
function SavePositionFeature:Start()
    if not isInitialized then
        logger:warn("Start called before Init")
        return false
    end
    if isRunning then return true end
    isRunning = true

    -- Re-teleport on respawn
    if charAddedConn then charAddedConn:Disconnect() end
    charAddedConn = LocalPlayer.CharacterAdded:Connect(function()
        if saveToggleEnabled and saveAnchorCFrame then
            task.defer(function()
                ensureCharacterReady(6)
                self:TeleportToCFrame(saveAnchorCFrame)
            end)
        end
    end)

    -- Gentle guard: if saveToggle ON and drift terlalu jauh/ke bawah, re-teleport
    if heartbeatConn then heartbeatConn:Disconnect() end
    heartbeatConn = RunService.Heartbeat:Connect(function()
        if not saveToggleEnabled or not saveAnchorCFrame then return end
        local hrp = getHRP()
        if not hrp then return end
        local pos = hrp.Position
        local anchorPos = saveAnchorCFrame.Position
        local dist = (pos - anchorPos).Magnitude
        -- If jatoh jauh (mis. jatuh void) atau terdorong jauh, tarik balik.
        if dist > 120 or pos.Y < (anchorPos.Y - 40) then
            self:TeleportToCFrame(saveAnchorCFrame)
        end
    end)

    logger:info("Started SavePositionFeature")
    return true
end

function SavePositionFeature:Stop()
    if not isRunning then return true end
    isRunning = false
    if charAddedConn then charAddedConn:Disconnect() charAddedConn = nil end
    if heartbeatConn then heartbeatConn:Disconnect() heartbeatConn = nil end
    logger:info("Stopped SavePositionFeature")
    return true
end

function SavePositionFeature:Cleanup()
    self:Stop()
    controls          = {}
    isInitialized     = false
    logger:info("Cleanup SavePositionFeature done")
end

-- ===== GUI-facing helpers =====

-- Called when dropdown selection changes (string, non-multi)
function SavePositionFeature:SetSelected(name)
    if type(name) == "string" and savedPositions[name] then
        selectedName = name
        persist()
        logger:info("Selected position:", name)
        return true
    end
    logger:warn("Invalid position name for selection:", tostring(name))
    return false
end

-- Called when user clicks Add button (requires input name to be set in GUI)
function SavePositionFeature:AddPosition(name)
    if type(name) ~= "string" or name == "" then
        logger:warn("AddPosition requires a non-empty name")
        return false
    end
    local hrp = getHRP()
    if not hrp then
        logger:warn("Cannot add position: HRP not found")
        return false
    end
    savedPositions[name] = hrp.CFrame
    selectedName = name
    persist()
    if _G.WindUI then
        _G.WindUI:Notify({
            Title = "Position Added",
            Content = ("Saved '%s'"):format(name),
            Icon = "bookmark-plus",
            Duration = 2
        })
    end
    logger:info("Position added:", name)
    return true
end

-- (Optional) remove position if you decide to wire a delete button later
function SavePositionFeature:RemovePosition(name)
    if savedPositions[name] then
        savedPositions[name] = nil
        if selectedName == name then selectedName = nil end
        persist()
        logger:info("Removed position:", name)
        return true
    end
    logger:warn("RemovePosition: not found:", tostring(name))
    return false
end

-- Teleport to selected (or specific) saved position
function SavePositionFeature:Teleport(name)
    local key = name or selectedName
    if not key then
        logger:warn("Teleport: no position selected")
        if _G.WindUI then
            _G.WindUI:Notify({
                Title = "Teleport Failed",
                Content = "Please select a saved position first.",
                Icon = "alert-triangle",
                Duration = 3
            })
        end
        return false
    end

    local cf = savedPositions[key]
    if not cf then
        logger:warn("Teleport: position not found:", key)
        return false
    end

    local ok = self:TeleportToCFrame(cf)
    if ok then
        if _G.WindUI then
            _G.WindUI:Notify({
                Title = "Teleport Success",
                Content = ("Teleported to '%s'"):format(key),
                Icon = "map-pin",
                Duration = 2
            })
        end
        logger:info("Teleported to:", key)
    else
        if _G.WindUI then
            _G.WindUI:Notify({
                Title = "Teleport Failed",
                Content = ("Could not teleport to '%s'"):format(key),
                Icon = "x",
                Duration = 3
            })
        end
        logger:warn("Teleport failed:", key)
    end
    return ok
end

-- Toggle Save Position: ON = capture current cf, persist, auto-restore
function SavePositionFeature:SetSaveToggle(state)
    saveToggleEnabled = not not state
    if saveToggleEnabled then
        local hrp = getHRP()
        if not hrp then
            logger:warn("SaveToggle ON but HRP not found")
            return false
        end
        saveAnchorCFrame = hrp.CFrame
        persist()
        -- immediate anchor snap (optional)
        self:TeleportToCFrame(saveAnchorCFrame)
        logger:info("Save Position enabled; anchor captured")
    else
        saveAnchorCFrame = nil
        persist()
        logger:info("Save Position disabled")
    end
    return true
end

-- For status panels / debug
function SavePositionFeature:GetStatus()
    local list = {}
    for name in pairs(savedPositions) do
        table.insert(list, name)
    end
    table.sort(list)
    return {
        initialized       = isInitialized,
        running           = isRunning,
        saveToggleEnabled = saveToggleEnabled,
        selectedName      = selectedName,
        count             = #list,
        names             = list
    }
end

-- For populating dropdown options
function SavePositionFeature:GetSavedList()
    local list = {}
    for name in pairs(savedPositions) do
        table.insert(list, name)
    end
    table.sort(list)
    return list
end

return SavePositionFeature