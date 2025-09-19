-- ===========================
-- AUTO RECONNECT FEATURE (Client) - FIXED VERSION
-- Fixes for executor force close issue:
-- 1) Proper connection cleanup with nil references
-- 2) Aggressive task cancellation mechanism  
-- 3) Service reference cleanup
-- 4) Race condition prevention
-- 5) Memory leak prevention
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

-- ===== Services (will be cleaned up properly) =====
local Players         = game:GetService("Players")
local TeleportService = game:GetService("TeleportService")
local CoreGui         = game:GetService("CoreGui")
local RunService      = game:GetService("RunService")

local LocalPlayer = Players.LocalPlayer

-- ===== State =====
local isInitialized = false
local isEnabled     = false
local connections   = {}
local spawnedTasks  = {}  -- NEW: track spawned tasks for cleanup
local isTeleporting = false
local retryCount    = 0
local runId         = 0

local currentPlaceId = game.PlaceId
local currentJobId   = game.JobId or ""

-- Container references for cleanup
local promptContainer = nil
local heuristicTask   = nil

local opts = {
    maxRetries         = 3,
    baseBackoffSec     = 5,
    backoffFactor      = 3,
    sameInstanceFirst  = true,
    detectByPrompt     = true,
    heuristicWatchdog  = false,
    heuristicTimeout   = 30,
    armDelaySec        = 0.85,

    dcKeywords = {
        "lost connection",
        "you were kicked", 
        "disconnected",
        "error code",
        "koneksi terputus",
        "anda dikeluarkan",
        "terputus",
        "kode kesalahan",
    },

    antiCheatKeywords = {
        "exploit",
        "cheat", 
        "suspicious",
        "unauthorized",
        "kecurangan",
        "curang",
        "mencurigakan", 
        "tidak sah",
    },
}

-- ===== Utils =====
local function addCon(con)
    if con then 
        table.insert(connections, con)
    end
    return con
end

-- FIXED: Proper connection cleanup with nil references
local function clearConnections()
    logger:debug("Clearing", #connections, "connections...")
    
    for i, c in ipairs(connections) do
        if c and c.Connected then
            pcall(function() c:Disconnect() end)
        end
        connections[i] = nil  -- CRITICAL: nil the reference
    end
    
    -- Clear the array completely
    for i = #connections, 1, -1 do
        connections[i] = nil
    end
    
    logger:debug("Connections cleared.")
end

-- FIXED: Track and cleanup spawned tasks
local function addTask(task)
    if task then
        table.insert(spawnedTasks, task)
    end
    return task
end

local function clearTasks()
    logger:debug("Clearing", #spawnedTasks, "spawned tasks...")
    
    for i, task in ipairs(spawnedTasks) do
        if task and typeof(task) == "thread" then
            pcall(function() 
                task:Cancel()  -- Try to cancel if supported
            end)
        end
        spawnedTasks[i] = nil
    end
    
    -- Clear array
    for i = #spawnedTasks, 1, -1 do
        spawnedTasks[i] = nil
    end
    
    logger:debug("Tasks cleared.")
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

local function backoffSeconds(n)
    if n <= 1 then return opts.baseBackoffSec end
    return opts.baseBackoffSec * (opts.backoffFactor ^ (n - 1))
end

-- FIXED: More aggressive abort checking
local function sleepWithAbort(sec, token)
    local t0 = os.clock()
    local checkInterval = 0.05  -- More frequent checking
    
    while os.clock() - t0 < sec do
        if not isEnabled or token ~= runId then 
            logger:debug("Sleep aborted - enabled:", isEnabled, "token match:", token == runId)
            return false 
        end
        task.wait(checkInterval)
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

-- FIXED: Better teleport task management
local function planTeleport()
    if not isEnabled then 
        logger:debug("planTeleport called but not enabled")
        return 
    end
    if isTeleporting then
        logger:debug("Teleport already in progress; skip.")
        return
    end
    
    isTeleporting = true
    retryCount = 0
    local myRun = runId

    local teleportTask = task.spawn(function()
        logger:debug("Starting teleport task with runId:", myRun)
        
        -- Arming window with better abort checking
        local okArm = sleepWithAbort(opts.armDelaySec or 0.85, myRun)
        if not okArm then
            isTeleporting = false
            logger:debug("Teleport aborted during arming window.")
            return
        end

        while isEnabled and myRun == runId and retryCount <= opts.maxRetries do
            -- Double check we're still valid
            if not isEnabled or myRun ~= runId then
                logger:debug("Teleport loop aborted - runId changed")
                break
            end
            
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
                return
            end

            retryCount += 1
            if retryCount > opts.maxRetries then
                logger:error("Teleport failed; max retries reached. Last error:", tostring(err))
                break
            end

            local waitSec = backoffSeconds(retryCount)
            logger:warn(string.format("Teleport failed (attempt %d). Backing off %.1fs. Err: %s",
                retryCount, waitSec, tostring(err)))
            
            if not sleepWithAbort(waitSec, myRun) then 
                logger:debug("Teleport backoff aborted")
                break 
            end
        end

        isTeleporting = false
        logger:debug("Teleport task ended")
    end)
    
    addTask(teleportTask)
end

-- ===== Detection (FIXED) =====
local function hookPromptDetection()
    if not opts.detectByPrompt then return end

    -- Store container reference for cleanup
    promptContainer = CoreGui:FindFirstChild("RobloxPromptGui", true)
    if promptContainer then
        promptContainer = promptContainer:FindFirstChild("promptOverlay", true) or promptContainer
    else
        promptContainer = CoreGui
    end

    -- FIXED: Better connection management
    local connection = promptContainer.DescendantAdded:Connect(function(desc)
        if not isEnabled or runId == 0 then return end
        if not (desc:IsA("TextLabel") or desc:IsA("TextBox")) then return end

        local t = desc.Text
        if not (t and #t > 0) then return end

        local msg = string.lower(t)
        logger:debug("Prompt detected:", t)

        if lowerContains(msg, opts.antiCheatKeywords) then
            logger:warn("Anti-cheat keyword detected; skip auto-reconnect.")
            return
        end

        if lowerContains(msg, opts.dcKeywords) then
            logger:info("Disconnect/kick detected via prompt → planning teleport.")
            planTeleport()
        end
    end)
    
    addCon(connection)
end

local function hookTeleportFailures()
    local connection = TeleportService.TeleportInitFailed:Connect(function(player, teleResult, errorMessage)
        if not isEnabled or runId == 0 then return end
        if player ~= LocalPlayer then return end
        logger:warn("TeleportInitFailed:", tostring(teleResult), tostring(errorMessage))
        planTeleport()
    end)
    
    addCon(connection)
end

-- FIXED: Proper heuristic watchdog with cleanup
local function hookHeuristicWatchdog()
    if not opts.heuristicWatchdog then return end

    local lastBeat = os.clock()
    local myRunId = runId
    
    -- Heartbeat connection
    local heartbeatCon = RunService.Heartbeat:Connect(function()
        lastBeat = os.clock()
    end)
    addCon(heartbeatCon)

    -- Watchdog task with proper cancellation
    heuristicTask = task.spawn(function()
        logger:debug("Starting heuristic watchdog task")
        
        while isEnabled and runId == myRunId do
            local dt = os.clock() - lastBeat
            
            if dt > opts.heuristicTimeout then
                if isEnabled and runId == myRunId then  -- Double check
                    logger:warn(string.format("Heuristic timeout (%.1fs) → planning teleport.", dt))
                    planTeleport()
                end
                -- Wait before checking again
                if not sleepWithAbort(math.max(5, opts.heuristicTimeout * 0.5), myRunId) then
                    break
                end
            else
                if not sleepWithAbort(5, myRunId) then
                    break
                end
            end
        end
        
        logger:debug("Heuristic watchdog task ended")
        heuristicTask = nil
    end)
    
    addTask(heuristicTask)
end

-- ===== Public API (FIXED) =====
function AutoReconnect:Init(userOpts)
    if isInitialized then
        logger:debug("Init called again; updating opts and cleaning up.")
        self:Stop()  -- Clean up existing state
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
    
    -- Clean up any existing state first
    self:Stop()
    
    isEnabled = true
    isTeleporting = false
    runId = runId + 1
    retryCount = 0

    logger:debug("Starting with runId:", runId)

    hookPromptDetection()
    hookTeleportFailures() 
    hookHeuristicWatchdog()

    -- Player connection for jobId updates
    local playerCon = Players.PlayerAdded:Connect(function(p)
        if p == LocalPlayer then
            currentPlaceId = game.PlaceId
            currentJobId   = game.JobId or ""
            logger:debug("Snapshot updated on PlayerAdded. JobId:", currentJobId)
        end
    end)
    addCon(playerCon)

    logger:info("AutoReconnect started.")
    return true
end

-- FIXED: Comprehensive cleanup
function AutoReconnect:Stop()
    if not isEnabled then
        logger:debug("Already stopped.")
        return true
    end
    
    logger:debug("Stopping AutoReconnect...")
    
    isEnabled = false
    isTeleporting = false
    runId = runId + 1  -- Cancel all running tasks
    
    -- Clear all connections with proper cleanup
    clearConnections()
    
    -- Clear all spawned tasks
    clearTasks()
    
    -- Reset state variables
    retryCount = 0
    
    -- Clean up references
    promptContainer = nil
    heuristicTask = nil
    
    -- Force garbage collection hint
    if _G.gcinfo then
        local beforeGC = _G.gcinfo()
        collectgarbage("collect")
        local afterGC = _G.gcinfo()
        logger:debug(string.format("GC: %.1f KB -> %.1f KB (freed %.1f KB)", 
            beforeGC, afterGC, beforeGC - afterGC))
    end
    
    logger:info("AutoReconnect stopped and cleaned up.")
    return true
end

function AutoReconnect:Cleanup()
    self:Stop()
    isInitialized = false
    
    -- Additional cleanup
    connections = {}
    spawnedTasks = {}
    
    logger:info("Full cleanup completed.")
end

-- Optional compatibility methods
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
        taskCount     = #spawnedTasks,
        runId         = runId,
    }
end

-- NEW: Force emergency cleanup method
function AutoReconnect:EmergencyCleanup()
    logger:warn("Emergency cleanup initiated!")
    
    isEnabled = false
    isInitialized = false
    isTeleporting = false
    runId = runId + 10  -- Big jump to cancel everything
    
    -- Aggressive cleanup
    clearConnections()
    clearTasks()
    
    -- Reset everything
    connections = {}
    spawnedTasks = {}
    promptContainer = nil
    heuristicTask = nil
    retryCount = 0
    
    collectgarbage("collect")
    logger:warn("Emergency cleanup completed!")
    return true
end

return AutoReconnect