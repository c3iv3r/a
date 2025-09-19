-- ===========================
-- AUTO RECONNECT FEATURE (Client)
-- ===========================

local AutoReconnect = {}
AutoReconnect.__index = AutoReconnect

-- Logger colon-compatible
local _L = _G.Logger and _G.Logger.new and _G.Logger:new("AutoReconnect")
local logger = _L or {}
function logger:debug(...) end
function logger:info(...)  end
function logger:warn(...)  end
function logger:error(...) end

-- Services
local Players         = game:GetService("Players")
local TeleportService = game:GetService("TeleportService")
local CoreGui         = game:GetService("CoreGui")
local RunService      = game:GetService("RunService")

local LocalPlayer = Players.LocalPlayer

-- State
local isInitialized = false
local isEnabled     = false
local connections   = {}
local isTeleporting = false
local retryCount    = 0
local runToken      = 0      -- <= tambah: epoch untuk cancel semua kerja lama

local currentPlaceId = game.PlaceId
local currentJobId   = game.JobId or ""

local opts = {
    maxRetries         = 3,
    baseBackoffSec     = 5,
    backoffFactor      = 3,
    sameInstanceFirst  = true,
    detectByPrompt     = true,
    heuristicWatchdog  = false,
    heuristicTimeout   = 30,
    dcKeywords         = { "lost connection", "you were kicked", "disconnected", "error code" }, -- fallback
    antiCheatKeywords  = { "exploit", "cheat", "suspicious", "unauthorized" },
}

-- Utils
local function addCon(c) if c then table.insert(connections, c) end end
local function clearConnections()
    for _, c in ipairs(connections) do pcall(function() c:Disconnect() end) end
    connections = {}
end
local function lowerContains(str, keys)
    local s = string.lower(tostring(str or ""))
    for _, k in ipairs(keys) do if string.find(s, k, 1, true) then return true end end
    return false
end
local function backoffSeconds(n)
    return (n <= 1) and opts.baseBackoffSec or (opts.baseBackoffSec * (opts.backoffFactor^(n-1)))
end

-- Teleport attempts
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

-- ==== CANCEL-SAFE planTeleport (respect runToken) ====
local function planTeleport()
    if not isEnabled then return end
    if isTeleporting then
        logger:debug("Teleport already in progress; skip.")
        return
    end
    isTeleporting = true
    retryCount = 0
    local myToken = runToken  -- snapshot epoch

    task.spawn(function()
        -- recheck sebelum mulai
        if not isEnabled or myToken ~= runToken then
            isTeleporting = false; return
        end

        while isEnabled and (myToken == runToken) and retryCount <= opts.maxRetries do
            local ok, err
            if opts.sameInstanceFirst then
                ok, err = tryTeleportSameInstance()
                if not ok then
                    logger:debug("Same instance failed:", err)
                    -- token/enable check sebelum fallback
                    if not isEnabled or myToken ~= runToken then break end
                    ok, err = tryTeleportSamePlace()
                end
            else
                ok, err = tryTeleportSamePlace()
            end

            if not isEnabled or myToken ~= runToken then
                -- toggled off while trying
                break
            end

            if ok then
                logger:info("Teleport issued successfully.")
                return -- engine will handle transition
            end

            retryCount += 1
            if retryCount > opts.maxRetries then
                logger:error("Teleport failed; max retries reached. Last error:", tostring(err))
                break
            end

            local waitSec = backoffSeconds(retryCount)
            logger:warn(string.format("Teleport failed (attempt %d). Backing off %.1fs. Err: %s",
                retryCount, waitSec, tostring(err)))

            -- backoff dengan checks berkala agar bisa dibatalkan cepat
            local t = 0
            while t < waitSec do
                if not isEnabled or myToken ~= runToken then
                    isTeleporting = false; return
                end
                task.wait(0.1); t += 0.1
            end
        end

        isTeleporting = false
    end)
end

-- ==== Prompt detection with strict filter ====
local function hookPromptDetection()
    if not opts.detectByPrompt then return end

    local container = CoreGui:FindFirstChild("RobloxPromptGui", true)
    if container then
        container = container:FindFirstChild("promptOverlay", true) or container
    else
        container = CoreGui
    end

    addCon(container.ChildAdded:Connect(function(child)
        if not isEnabled then return end
        local myToken = runToken

        -- Filter ketat: hanya bereaksi jika ada descendant bernama "ErrorPrompt"
        local hasErrorPrompt = false
        pcall(function()
            if child:FindFirstChild("ErrorPrompt", true) then
                hasErrorPrompt = true
            end
        end)
        if not hasErrorPrompt then
            return
        end

        -- Kumpulkan teks (optional; hanya untuk anti-cheat filter / logging)
        task.defer(function()
            if not isEnabled or myToken ~= runToken then return end

            local msg = ""
            pcall(function()
                for _, d in ipairs(child:GetDescendants()) do
                    if d:IsA("TextLabel") or d:IsA("TextBox") then
                        local t = d.Text
                        if t and #t > 0 then msg ..= " " .. t end
                    end
                end
            end)

            logger:debug("ErrorPrompt detected:", msg)

            if lowerContains(msg, opts.antiCheatKeywords) then
                logger:warn("Anti-cheat keyword present; skip auto-reconnect.")
                return
            end
            -- Bila kosong, tetap anggap DC karena ErrorPrompt muncul (lebih kuat daripada text)
            planTeleport()
        end)
    end))
end

local function hookTeleportFailures()
    addCon(TeleportService.TeleportInitFailed:Connect(function(player, teleResult, errorMessage)
        if not isEnabled or player ~= LocalPlayer then return end
        logger:warn("TeleportInitFailed:", tostring(teleResult), tostring(errorMessage))
        planTeleport()
    end))
end

local function hookHeuristicWatchdog()
    if not opts.heuristicWatchdog then return end
    local lastBeat = os.clock()
    addCon(RunService.Heartbeat:Connect(function() lastBeat = os.clock() end))
    task.spawn(function()
        local myToken = runToken
        while isEnabled and (myToken == runToken) do
            local dt = os.clock() - lastBeat
            if dt > opts.heuristicTimeout then
                logger:warn(string.format("Heuristic timeout (%.1fs) → planning teleport.", dt))
                planTeleport()
                -- beri jeda supaya gak spam
                for _=1,50 do
                    if not isEnabled or myToken ~= runToken then break end
                    task.wait(0.1)
                end
            else
                for _=1,50 do
                    if not isEnabled or myToken ~= runToken then break end
                    task.wait(0.1)
                end
            end
        end
    end)
end

-- Public API
function AutoReconnect:Init(userOpts)
    if isInitialized then logger:debug("Init again; update opts.") end
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
    if not isInitialized then logger:warn("Start() before Init()."); return false end
    if isEnabled then logger:debug("Already running."); return true end

    -- epoch baru untuk sesi ini
    runToken      += 1
    isEnabled     = true
    isTeleporting = false
    retryCount    = 0

    clearConnections()
    hookPromptDetection()
    hookTeleportFailures()
    hookHeuristicWatchdog()

    logger:info("AutoReconnect started. token=", runToken)
    return true
end

function AutoReconnect:Stop()
    if not isEnabled then logger:debug("Already stopped."); return true end

    -- Soft stop + kill-switch: bump token agar semua thread lama bubar
    isEnabled     = false
    isTeleporting = false
    runToken      += 1  -- **penting**: membatalkan semua planTeleport / loop yang sudah jalan

    -- Defer disconnect beberapa frame, agar keluar dari stack callback event
    task.defer(function()
        task.wait(0.05)
        local ok, err = pcall(function()
            for _, c in ipairs(connections) do pcall(function() c:Disconnect() end) end
            connections = {}
        end)
        if not ok then logger:warn("Deferred disconnects error:", err) end
    end)

    logger:info("AutoReconnect stopped (soft). token=", runToken)
    return true
end

function AutoReconnect:Cleanup()
    -- Hard stop
    isEnabled     = false
    isTeleporting = false
    runToken      += 1
    for _, c in ipairs(connections) do pcall(function() c:Disconnect() end) end
    connections = {}
    isInitialized = false
    logger:info("Cleaned up (hard). token=", runToken)
end

-- Optional helpers
function AutoReconnect:IsEnabled() return isEnabled end
function AutoReconnect:GetPlaceInfo()
    return { placeId = game.PlaceId, jobId = game.JobId, playerCount = #Players:GetPlayers() }
end
function AutoReconnect:GetStatus()
    return {
        initialized = isInitialized,
        enabled     = isEnabled,
        token       = runToken,
        placeId     = currentPlaceId,
        jobId       = currentJobId,
        retries     = retryCount,
        teleporting = isTeleporting,
        conCount    = #connections,
    }
end

return AutoReconnect
