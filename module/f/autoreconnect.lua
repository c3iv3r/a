-- ===========================
-- AUTO RECONNECT FEATURE (Client)
-- API: Init(opts?), Start(), Stop(), Cleanup()
-- No GUI notify; logger only
-- ===========================

local AutoReconnect = {}
AutoReconnect.__index = AutoReconnect

-- ===== Logger (fallback colon-compatible) =====
local _L = _G.Logger and _G.Logger.new and _G.Logger:new("AutoReconnect")
local logger = _L or {}
function logger:debug(...) end
function logger:info(...)  end
function logger:warn(...)  end
function logger:error(...) end

-- ===== Services =====
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
local runId         = 0  -- cancel token for arming/loops

local currentPlaceId = game.PlaceId
local currentJobId   = game.JobId or ""

-- opsi default (bisa dioverride lewat Init({ ... }))
local opts = {
    maxRetries         = 3,
    baseBackoffSec     = 5,
    backoffFactor      = 3,          -- 5s -> 15s -> 45s
    sameInstanceFirst  = true,       -- coba balik ke jobId yang sama dulu
    detectByPrompt     = true,
    heuristicWatchdog  = false,      -- matikan kalau gak perlu
    heuristicTimeout   = 30,         -- detik tanpa Heartbeat -> anggap DC
    dcKeywords         = { "lost connection", "you were kicked", "disconnected", "error code" }, -- lower-case
    antiCheatKeywords  = { "exploit"
, "cheat", "suspicious", "unauthorized" },                    -- lower-case
    armDelaySec        = 0.85,       -- short arming window to allow cancel before teleport
}, "cheat", "suspicious", "unauthorized" },                    -- lower-case
}

-- ===== Utils =====
local function addCon(con)
    if con then table.insert(connections, con) end
end

local function clearConnections()
    for _, c in ipairs(connections) do
        pcall(function() c:Disconnect() end)
    end
    connections = {}
end

local function lowerContains(str, keywords)
    local s = string.lower(tostring(str or ""))
    for _, key in ipairs(keywords) do
        if string.find(s, key, 1, true) then
            return true
        end
    end
    return false
end

local function backoffSeconds(n) -- n = attempt index (1..)
    if n <= 1 then return opts.baseBackoffSec end
    return opts.baseBackoffSec * (opts.backoffFactor ^ (n - 1))
end

local function sleepWithAbort(sec, token)
    local t0 = os.clock()
    while os.clock() - t0 < sec do
        if not isEnabled or token ~= runId then return false end
        task.wait(0.1)
    end
    return true
end


-- ===== Teleport attempts =====
local function tryTeleportSameInstance()
    if not currentPlaceId or not currentJobId or currentJobId == "" then
        return false, "no_jobid"
    end
    logger:info("Teleport → same instance:", currentPlaceId, currentJobId)
    local ok, err = pcall(function()
        TeleportService:TeleportToPlaceInstance(currentPlaceId, currentJobId, LocalPlayer)
    end)
    return ok, err
end

local function tryTeleportSamePlace()
    if not currentPlaceId then return false, "no_placeid" end
    logger:info("Teleport → same place:", currentPlaceId)
    local ok, err = pcall(function()
        TeleportService:Teleport(currentPlaceId, LocalPlayer)
    end)
    return ok, err
end

local function planTeleport()
    if not isEnabled then return end
    if isTeleporting then
        logger:debug("Teleport already in progress; skip.")
        return
    end
    isTeleporting = true
    retryCount = 0
    local myRun = runId

    task.spawn(function()
        -- Arming window: allow user to turn OFF before teleport actually fires
        local okArm = sleepWithAbort(opts.armDelaySec or 0.85, myRun)
        if not okArm then
            isTeleporting = false
            logger:debug("Teleport aborted during arming window.")
            return
        end

        while isEnabled and myRun == runId and retryCount <= opts.maxRetries do
            local ok, err
            if opts.sameInstanceFirst then
                ok, err = tryTeleportSameInstance()
                if not ok then
                    logger:debug("Same instance failed:", err)
                    ok, err = tryTeleportSamePlace()
                end
            else
                ok, err = tryTeleportSamePlace()
            end

            if ok then
                logger:info("Teleport issued successfully.")
                return -- biarkan Roblox handle transisi
            end

            retryCount += 1
            if retryCount > opts.maxRetries then
                logger:error("Teleport failed; max retries reached. Last error:", tostring(err))
                break
            end

            local waitSec = backoffSeconds(retryCount)
            logger:warn(string.format("Teleport failed (attempt %d). Backing off %.1fs. Err: %s",
                retryCount, waitSec, tostring(err)))
            if not sleepWithAbort(waitSec, myRun) then isTeleporting = false; return end
        end

        isTeleporting = false
    end)
end

-- ===== Detection =====
local function hookPromptDetection()
    if not opts.detectByPrompt then return end

    -- Cari overlay; struktur bisa berubah-ubah, jadi fleksibel
    local container = CoreGui:FindFirstChild("RobloxPromptGui", true)
    if container then
        container = container:FindFirstChild("promptOverlay", true) or container
    else
        container = CoreGui
    end

    addCon(container.ChildAdded:Connect(function(child)
        if not isEnabled then return end

        -- Kumpulkan semua teks yang muncul di node prompt (label/textbox)
        task.defer(function()
            local msg = ""
            pcall(function()
                for _, d in ipairs(child:GetDescendants()) do
                    if d:IsA("TextLabel") or d:IsA("TextBox") then
                        local t = d.Text
                        if t and #t > 0 then
                            msg ..= " " .. t
                        end
                    end
                end
            end)

            if msg == "" then return end
            logger:debug("Prompt detected:", msg)

            -- Anti-cheat? Jangan auto-rejoin (hindari loop berbahaya)
            if lowerContains(msg, opts.antiCheatKeywords) then
                logger:warn("Anti-cheat keyword detected; skip auto-reconnect.")
                return
            end

            -- Lost connection / kicked?
            if lowerContains(msg, opts.dcKeywords) then
                logger:info("Disconnect/kick detected via prompt → planning teleport.")
                planTeleport()
            end
        end)
    end))
end

local function hookTeleportFailures()
    addCon(TeleportService.TeleportInitFailed:Connect(function(player, teleResult, errorMessage)
        if not isEnabled then return end
        if player ~= LocalPlayer then return end
        logger:warn("TeleportInitFailed:", tostring(teleResult), tostring(errorMessage))
        -- Coba lagi dengan backoff via planTeleport (single-flight guarded)
        planTeleport()
    end))
end

local function hookHeuristicWatchdog()
    if not opts.heuristicWatchdog then return end

    local lastBeat = os.clock()
    addCon(RunService.Heartbeat:Connect(function()
        lastBeat = os.clock()
    end))

    task.spawn(function()
        while isEnabled do
            local dt = os.clock() - lastBeat
            if dt > opts.heuristicTimeout then
                logger:warn(string.format("Heuristic timeout (%.1fs) → planning teleport.", dt))
                planTeleport()
                task.wait(math.max(5, opts.heuristicTimeout * 0.5))
            else
                task.wait(5)
            end
        end
    end)
end

-- ===== Public API =====
function AutoReconnect:Init(userOpts)
    if isInitialized then
        logger:debug("Init called again; updating opts.")
    end

    currentPlaceId = game.PlaceId
    currentJobId   = game.JobId or ""

    if type(userOpts) == "table" then
        for k, v in pairs(userOpts) do
            if opts[k] ~= nil then
                opts[k] = v
            end
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
    isEnabled = true
    isTeleporting = false
    runId = runId + 1 -- new token session
    retryCount = 0

    clearConnections()
    hookPromptDetection()
    hookTeleportFailures()
    hookHeuristicWatchdog()

    -- keep snapshot fresh (kalau jobId berubah karena server switch manual)
    addCon(Players.PlayerAdded:Connect(function(p)
        if p == LocalPlayer then
            currentPlaceId = game.PlaceId
            currentJobId   = game.JobId or ""
            logger:debug("Snapshot updated on PlayerAdded. JobId:", currentJobId)
        end
    end))

    logger:info("AutoReconnect started.")
    return true
end

function AutoReconnect:Stop()
    if not isEnabled then
        logger:debug("Already stopped.")
        return true
    end
    isEnabled = false
    isTeleporting = false
    runId = runId + 1 -- cancel token
    clearConnections()
    logger:info("AutoReconnect stopped.")
    return true
end

function AutoReconnect:Cleanup()
    self:Stop()
    isInitialized = false
    logger:info("Cleaned up.")
end

-- Opsional kompabilitas
function AutoReconnect:IsEnabled()
    return isEnabled
end

function AutoReconnect:GetPlaceInfo()
    return {
        placeId = game.PlaceId,
        jobId   = game.JobId,
        playerCount = #Players:GetPlayers()
    }
end

function AutoReconnect:GetStatus()
    return {
        initialized   = isInitialized,
        enabled       = isEnabled,
        placeId       = currentPlaceId,
        jobId         = currentJobId,
        retries       = retryCount,
        teleporting   = isTeleporting,
        conCount      = #connections,
    }
end

return AutoReconnect
