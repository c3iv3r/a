-- AutoReconnect_Cancelable.lua
-- Drop-in pengganti AutoReconnect v1: tambah session/cancel guard supaya aman saat toggle OFF.

local AutoReconnect = {}
AutoReconnect.__index = AutoReconnect

local _L = _G.Logger and _G.Logger.new and _G.Logger:new("AutoReconnect")
local logger = _L or {}
function logger:debug(...) end
function logger:info(...)  end
function logger:warn(...)  end
function logger:error(...) end

local Players         = game:GetService("Players")
local TeleportService = game:GetService("TeleportService")
local CoreGui         = game:GetService("CoreGui")
local RunService      = game:GetService("RunService")

local LocalPlayer = Players.LocalPlayer

-- ===== State =====
local isInitialized = false
local isEnabled     = false
local connections   = {}
local isTeleporting = false
local retryCount    = 0

local currentPlaceId = game.PlaceId
local currentJobId   = game.JobId or ""

-- Session/cancel guard
local sessionId = 0  -- akan di-increment setiap Start()/Stop()
local function addCon(con) if con then table.insert(connections, con) end end
local function clearConnections()
    for _, c in ipairs(connections) do pcall(function() c:Disconnect() end) end
    connections = {}
end

-- opsi default
local opts = {
    maxRetries         = 3,
    baseBackoffSec     = 5,
    backoffFactor      = 3,
    sameInstanceFirst  = true,
    detectByPrompt     = true,
    heuristicWatchdog  = false,
    heuristicTimeout   = 30,
    dcKeywords         = { "lost connection", "you were kicked", "disconnected", "error code" },
    antiCheatKeywords  = { "exploit", "cheat", "suspicious", "unauthorized" },
}

local function lowerContains(str, keywords)
    local s = string.lower(tostring(str or ""))
    for _, key in ipairs(keywords) do
        if string.find(s, key, 1, true) then return true end
    end
    return false
end

local function backoffSeconds(n)
    if n <= 1 then return opts.baseBackoffSec end
    return opts.baseBackoffSec * (opts.backoffFactor ^ (n - 1))
end

-- Guarded Teleport helpers (cek session + enabled sebelum eksekusi)
local function guardedTeleport(mySession, fn, label)
    if (not isEnabled) or (mySession ~= sessionId) then return false, "canceled" end
    local ok, err = pcall(fn)
    if ok then
        logger:info("Teleport issued (" .. (label or "?") .. ").")
    else
        logger:warn("Teleport failed (" .. (label or "?") .. "): " .. tostring(err))
    end
    return ok, err
end

local function tryTeleportSameInstance(mySession)
    if not currentPlaceId or not currentJobId or currentJobId == "" then
        return false, "no_jobid"
    end
    logger:info("Teleport → same instance:", currentPlaceId, currentJobId)
    return guardedTeleport(mySession, function()
        TeleportService:TeleportToPlaceInstance(currentPlaceId, currentJobId, LocalPlayer)
    end, "same-instance")
end

local function tryTeleportSamePlace(mySession)
    if not currentPlaceId then return false, "no_placeid" end
    logger:info("Teleport → same place:", currentPlaceId)
    return guardedTeleport(mySession, function()
        TeleportService:Teleport(currentPlaceId, LocalPlayer)
    end, "same-place")
end

local function planTeleport(mySession)
    if (not isEnabled) or (mySession ~= sessionId) then return end
    if isTeleporting then
        logger:debug("Teleport already in progress; skip.")
        return
    end
    isTeleporting = true
    retryCount = 0

    task.spawn(function()
        -- loop akan otomatis batal jika session berubah atau disabled
        while isEnabled and (mySession == sessionId) and retryCount <= opts.maxRetries do
            local ok, err
            if opts.sameInstanceFirst then
                ok, err = tryTeleportSameInstance(mySession)
                if (not ok) and isEnabled and (mySession == sessionId) then
                    logger:debug("Same instance failed:", err)
                    ok, err = tryTeleportSamePlace(mySession)
                end
            else
                ok, err = tryTeleportSamePlace(mySession)
            end

            if ok then
                -- Beri kontrol ke engine; jangan lanjut loop
                break
            end

            retryCount += 1
            if retryCount > opts.maxRetries then
                logger:error("Teleport failed; max retries reached. Last error: " .. tostring(err))
                break
            end

            local waitSec = backoffSeconds(retryCount)
            logger:warn(string.format("Teleport failed (attempt %d). Backing off %.1fs. Err: %s",
                retryCount, waitSec, tostring(err)))
            local t0 = os.clock()
            while isEnabled and (mySession == sessionId) and (os.clock() - t0) < waitSec do
                task.wait(0.1)
            end
            if (not isEnabled) or (mySession ~= sessionId) then break end
        end
        isTeleporting = false
    end)
end

-- ===== Detection =====
local function hookPromptDetection(mySession)
    if not opts.detectByPrompt then return end

    local container = CoreGui:FindFirstChild("RobloxPromptGui", true)
    if container then
        container = container:FindFirstChild("promptOverlay", true) or container
    else
        container = CoreGui
    end

    addCon(container.ChildAdded:Connect(function(child)
        if (not isEnabled) or (mySession ~= sessionId) then return end
        task.defer(function()
            if (not isEnabled) or (mySession ~= sessionId) then return end
            local msg = ""
            pcall(function()
                for _, d in ipairs(child:GetDescendants()) do
                    if d:IsA("TextLabel") or d:IsA("TextBox") then
                        local t = d.Text
                        if t and #t > 0 then msg ..= " " .. t end
                    end
                end
            end)
            if msg == "" then return end
            logger:debug("Prompt detected:", msg)

            if lowerContains(msg, opts.antiCheatKeywords) then
                logger:warn("Anti-cheat keyword detected; skip auto-reconnect.")
                return
            end
            if lowerContains(msg, opts.dcKeywords) then
                logger:info("Disconnect/kick detected via prompt → planning teleport.")
                planTeleport(mySession)
            end
        end)
    end))
end

local function hookTeleportFailures(mySession)
    addCon(TeleportService.TeleportInitFailed:Connect(function(player, teleResult, errorMessage)
        if (not isEnabled) or (mySession ~= sessionId) then return end
        if player ~= LocalPlayer then return end
        logger:warn("TeleportInitFailed:", tostring(teleResult), tostring(errorMessage))
        planTeleport(mySession)
    end))
end

local function hookHeuristicWatchdog(mySession)
    if not opts.heuristicWatchdog then return end
    local lastBeat = os.clock()
    addCon(RunService.Heartbeat:Connect(function()
        lastBeat = os.clock()
    end))
    task.spawn(function()
        while isEnabled and (mySession == sessionId) do
            local dt = os.clock() - lastBeat
            if dt > opts.heuristicTimeout then
                logger:warn(string.format("Heuristic timeout (%.1fs) → planning teleport.", dt))
                planTeleport(mySession)
                local cool = math.max(5, opts.heuristicTimeout * 0.5)
                local t0 = os.clock()
                while isEnabled and (mySession == sessionId) and (os.clock() - t0) < cool do
                    task.wait(0.1)
                end
            else
                task.wait(5)
            end
        end
    end)
end

-- ===== Public API =====
function AutoReconnect:Init(userOpts)
    if isInitialized then logger:debug("Init called again; updating opts.") end
    currentPlaceId = game.PlaceId
    currentJobId   = game.JobId or ""
    if type(userOpts) == "table" then
        for k, v in pairs(userOpts) do
            if opts[k] ~= nil then opts[k] = v end
        end
    end
    isInitialized = true
    logger:info("Initialized. PlaceId:", currentPlaceId, "JobId:", currentJobId)
    return true
end

function AutoReconnect:Start()
    if not isInitialized then
        logger:warn("Start() called before Init().")
        return false
    end
    if isEnabled then
        logger:debug("Already running.")
        return true
    end
    -- Start session
    sessionId += 1
    local mySession = sessionId

    isEnabled     = true
    isTeleporting = false
    retryCount    = 0

    clearConnections()
    hookPromptDetection(mySession)
    hookTeleportFailures(mySession)
    hookHeuristicWatchdog(mySession)

    -- keep snapshot fresh
    addCon(Players.PlayerAdded:Connect(function(p)
        if p == LocalPlayer then
            currentPlaceId = game.PlaceId
            currentJobId   = game.JobId or ""
            logger:debug("Snapshot updated on PlayerAdded. JobId:", currentJobId)
        end
    end))

    logger:info("AutoReconnect started. session=" .. tostring(mySession))
    return true
end

function AutoReconnect:Stop()
    if not isEnabled then
        logger:debug("Already stopped.")
        return true
    end
    -- Invalidate semua loop/attempt segera
    sessionId += 1
    isEnabled     = false
    isTeleporting = false
    clearConnections()
    logger:info("AutoReconnect stopped (session invalidated).")
    return true
end

function AutoReconnect:Cleanup()
    self:Stop()
    isInitialized = false
    logger:info("Cleaned up.")
end

function AutoReconnect:IsEnabled() return isEnabled end
function AutoReconnect:GetStatus()
    return {
        initialized = isInitialized,
        enabled = isEnabled,
        placeId = currentPlaceId,
        jobId = currentJobId,
        retries = retryCount,
        teleporting = isTeleporting,
        conCount = #connections,
        sessionId = sessionId,
    }
end

return AutoReconnect
