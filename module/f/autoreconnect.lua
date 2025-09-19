-- ===========================
-- AUTO RECONNECT FEATURE
-- API: Init(guiControls?), Start(), Stop(), Cleanup()
-- Notes:
--  - Tidak menggunakan _G.WindUI:Notify (logger saja)
--  - Dirancang untuk diaktifkan/dimatikan via toggle GUI (Start/Stop)
--  - Rejoin flow: try same instance -> fallback same place
--  - Debounce & backoff supaya ga spam teleport
-- ===========================

local AutoReconnect = {}
AutoReconnect.__index = AutoReconnect

-- ========= Services =========
local Players         = game:GetService("Players")
local CoreGui         = game:GetService("CoreGui")
local TeleportService = game:GetService("TeleportService")
local RunService      = game:GetService("RunService")

local LocalPlayer = Players.LocalPlayer

-- ========= Logger ===========
local logger = _G.Logger and _G.Logger.new("AutoReconnect") or {
    debug = function() end,
    info  = function() end,
    warn  = function() end,
    error = function() end
}

-- ========= State ============
local isInitialized   = false
local isRunning       = false
local isTeleporting   = false      -- single-flight guard
local retryCount      = 0
local connections     = {}
local controls        = {}

-- default options (bisa dioverride via Init(opts))
local opts = {
    maxRetries     = 3,       -- berapa kali coba rejoin sebelum menyerah
    baseBackoffSec = 5,       -- detik awal backoff
    backoffFactor  = 3,       -- perkalian backoff (exponential)
    sameInstanceFirst = true, -- coba balik ke server yang sama dulu
    detectByPrompt = true,    -- hook ErrorPrompt / kick / lost connection
    detectByHeuristic = true, -- fallback watchdog sederhana
    heuristicTimeout = 30,    -- detik tanpa Heartbeat -> anggap DC (hati2 false positive)
    antiCheatKeywords = { "exploit", "cheat", "suspicious", "unauthorized" }, -- lower-case matching
    -- pola string DC umum (lower-case)
    dcKeywords = { "lost connection", "you were kicked", "disconnected", "error code" },
}

-- ========= Utils ============
local function clearConnections()
    for _, con in ipairs(connections) do
        pcall(function() con:Disconnect() end)
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

local function exponentialBackoff(n)
    -- n = 0,1,2,... (attempt index)
    return opts.baseBackoffSec * (opts.backoffFactor ^ math.max(0, n - 1))
end

local function safeConnect(signal, fn)
    local ok, con = pcall(function() return signal:Connect(fn) end)
    if ok and con then
        table.insert(connections, con)
        return con
    end
    return nil
end

-- ========= Teleport Strategy ============
local function tryTeleportSameInstance()
    -- Kembali ke jobId yang sama (kalau server masih hidup)
    local placeId = game.PlaceId
    local jobId   = game.JobId
    if not placeId or not jobId or jobId == "" then
        return false, "no_jobid"
    end
    logger.info("Teleport → same instance:", placeId, jobId)
    local ok, err = pcall(function()
        TeleportService:TeleportToPlaceInstance(placeId, jobId, LocalPlayer)
    end)
    return ok, err
end

local function tryTeleportSamePlace()
    local placeId = game.PlaceId
    if not placeId then
        return false, "no_placeid"
    end
    logger.info("Teleport → same place:", placeId)
    local ok, err = pcall(function()
        TeleportService:Teleport(placeId, LocalPlayer)
    end)
    return ok, err
end

local function planTeleport()
    if isTeleporting then
        logger.debug("Teleport already in progress, skip.")
        return
    end
    isTeleporting = true

    task.spawn(function()
        retryCount = 0

        -- policy anti-cheat (bisa di-inject saat parsing prompt)
        local function shouldAbortForAntiCheat()
            -- Hook ini bisa diisi dinamis dari deteksi prompt
            return false
        end

        while isRunning and retryCount <= opts.maxRetries do
            if shouldAbortForAntiCheat() then
                logger.warn("Detected anti-cheat pattern, aborting auto-reconnect.")
                break
            end

            local ok, err
            if opts.sameInstanceFirst then
                ok, err = tryTeleportSameInstance()
                if not ok then
                    logger.debug("Same instance failed:", err)
                    ok, err = tryTeleportSamePlace()
                end
            else
                ok, err = tryTeleportSamePlace()
            end

            if ok then
                logger.info("Teleport issued successfully.")
                return -- kalau berhasil invoke teleport, biarkan Roblox handle transisi
            end

            -- retry with backoff
            retryCount += 1
            if retryCount > opts.maxRetries then
                logger.error("Teleport failed; max retries reached. Last error:", err)
                break
            end

            local waitSec = exponentialBackoff(retryCount)
            logger.warn(string.format("Teleport failed (attempt %d). Backing off %.1fs. Err: %s",
                retryCount, waitSec, tostring(err)))
            task.wait(waitSec)
        end

        isTeleporting = false
    end)
end

-- ========= Detection (prompts & watchdog) ============
local function hookErrorPrompts()
    -- RobloxPromptGui path sering berubah; kita pantau overlay children.
    local overlay = CoreGui:FindFirstChild("RobloxPromptGui", true)
    if overlay then
        overlay = overlay:FindFirstChild("promptOverlay", true) or overlay
    else
        overlay = CoreGui
    end

    if not overlay then
        logger.warn("Prompt overlay not found; prompt-based detection disabled.")
        return
    end

    safeConnect(overlay.ChildAdded, function(child)
        if not isRunning then return end
        -- Inspeksi descendant TextLabel yang biasanya memuat pesan
        task.defer(function()
            local msg = ""
            pcall(function()
                for _, d in ipairs(child:GetDescendants()) do
                    if d:IsA("TextLabel") or d:IsA("TextBox") then
                        msg ..= " " .. (d.Text or "")
                    end
                end
            end)

            if msg ~= "" then
                logger.debug("Prompt detected:", msg)

                -- anti-cheat?
                if lowerContains(msg, opts.antiCheatKeywords) then
                    logger.warn("Anti-cheat keyword detected in prompt; skipping reconnect.")
                    -- Tidak langsung planTeleport; biarkan user memutuskan.
                    return
                end

                -- lost connection / kicked?
                if lowerContains(msg, opts.dcKeywords) then
                    logger.info("Disconnect/kick detected via prompt → planning teleport.")
                    planTeleport()
                end
            end
        end)
    end)
end

local lastHeartbeat = os.clock()
local function hookHeartbeatWatchdog()
    if not opts.detectByHeuristic then return end

    safeConnect(RunService.Heartbeat, function()
        lastHeartbeat = os.clock()
    end)

    task.spawn(function()
        while isRunning do
            local dt = os.clock() - lastHeartbeat
            if dt > opts.heuristicTimeout then
                logger.warn(string.format("Heuristic timeout (%.1fs) → planning teleport.", dt))
                planTeleport()
                -- beri waktu sebelum cek lagi
                task.wait(opts.heuristicTimeout * 0.5)
            else
                task.wait(5)
            end
        end
    end)
end

local function hookTeleportFailures()
    safeConnect(TeleportService.TeleportInitFailed, function(player, teleResult, errorMessage)
        if not isRunning then return end
        logger.warn("TeleportInitFailed:", tostring(teleResult), tostring(errorMessage))
        -- Kalau teleport gagal saat proses, coba lagi dengan backoff
        planTeleport()
    end)
end

-- ========= Public API ============
function AutoReconnect:Init(guiControlsOrOpts)
    if isInitialized then
        logger.debug("Already initialized.")
        return true
    end

    if type(guiControlsOrOpts) == "table" then
        -- Bisa dilempar gui controls atau opts; kita terima dua2nya
        controls = guiControlsOrOpts
        -- Jika user sekalian kirim opsi, deteksi kunci yang cocok
        for k, v in pairs(guiControlsOrOpts) do
            if opts[k] ~= nil then
                opts[k] = v
            end
        end
    end

    isInitialized = true
    logger.info("AutoReconnect initialized.")
    return true
end

function AutoReconnect:Start()
    if not isInitialized then
        logger.warn("Start() called before Init(). Aborting.")
        return false
    end
    if isRunning then
        logger.debug("Already running.")
        return true
    end

    isRunning     = true
    isTeleporting = false
    retryCount    = 0
    lastHeartbeat = os.clock()

    -- hook signals
    clearConnections()
    if opts.detectByPrompt then
        hookErrorPrompts()
    end
    hookTeleportFailures()
    hookHeartbeatWatchdog()

    logger.info("AutoReconnect started.")
    return true
end

function AutoReconnect:Stop()
    if not isRunning then
        logger.debug("Already stopped.")
        return true
    end
    isRunning     = false
    isTeleporting = false
    clearConnections()
    logger.info("AutoReconnect stopped.")
    return true
end

function AutoReconnect:Cleanup()
    self:Stop()
    controls      = {}
    isInitialized = false
    logger.info("AutoReconnect cleaned up.")
end

return AutoReconnect
