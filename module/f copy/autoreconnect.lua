-- ===========================
-- AUTO RECONNECT FEATURE (Client) - FIXED VERSION
-- API: Init(opts?), Start(), Stop(), Cleanup()
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
local GuiService      = game:GetService("GuiService")

local LocalPlayer = Players.LocalPlayer

-- ===== State =====
local isInitialized = false
local isEnabled     = false
local connections   = {}
local isTeleporting = false
local retryCount    = 0
local watchdogTask  = nil -- FIX: Track background task

local currentPlaceId = game.PlaceId
local currentJobId   = game.JobId or ""

-- opsi default
local opts = {
    maxRetries         = 2,          -- FIX: Reduced from 3
    baseBackoffSec     = 3,          -- FIX: Reduced from 5
    backoffFactor      = 2,          -- FIX: Reduced from 3
    sameInstanceFirst  = true,
    detectByPrompt     = true,
    detectByError      = true,       -- FIX: Added simple error detection
    heuristicWatchdog  = false,      -- FIX: Default false
    heuristicTimeout   = 20,         -- FIX: Reduced from 30
    dcKeywords         = { "lost connection", "you were kicked", "disconnected", "error code" },
    antiCheatKeywords  = { "exploit", "cheat", "suspicious", "unauthorized" },
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
    
    -- FIX: Properly clean up background task
    if watchdogTask then
        pcall(function() task.cancel(watchdogTask) end)
        watchdogTask = nil
    end
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
    if not isEnabled then return end -- FIX: Double check isEnabled
    if isTeleporting then
        logger:debug("Teleport already in progress; skip.")
        return
    end
    isTeleporting = true
    retryCount = 0

    task.spawn(function()
        while isEnabled and retryCount < opts.maxRetries do -- FIX: Use < instead of <=
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
                isTeleporting = false -- FIX: Reset flag on success
                return
            end

            retryCount += 1
            if retryCount >= opts.maxRetries then -- FIX: Use >= for consistency
                logger:error("Teleport failed; max retries reached. Last error:", tostring(err))
                break
            end

            local waitSec = backoffSeconds(retryCount)
            logger:warn(string.format("Teleport failed (attempt %d). Backing off %.1fs. Err: %s",
                retryCount, waitSec, tostring(err)))
            
            -- FIX: Check isEnabled during wait
            local waited = 0
            while waited < waitSec and isEnabled do
                task.wait(0.5)
                waited += 0.5
            end
        end

        isTeleporting = false
    end)
end

-- ===== Detection =====
local function hookErrorDetection()
    if not opts.detectByError then return end
    
    -- FIX: Simple error detection like the example you showed
    addCon(GuiService.ErrorMessageChanged:Connect(function(errorMessage)
        if not isEnabled then return end
        if errorMessage and errorMessage ~= "" then
            logger:info("Error detected via GuiService:", errorMessage)
            
            -- Check for anti-cheat keywords
            if lowerContains(errorMessage, opts.antiCheatKeywords) then
                logger:warn("Anti-cheat keyword detected; skip auto-reconnect.")
                return
            end
            
            -- Plan teleport for any error
            planTeleport()
        end
    end))
end

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

            if lowerContains(msg, opts.antiCheatKeywords) then
                logger:warn("Anti-cheat keyword detected; skip auto-reconnect.")
                return
            end

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
        planTeleport()
    end))
end

local function hookHeuristicWatchdog()
    if not opts.heuristicWatchdog then return end

    local lastBeat = os.clock()
    addCon(game:GetService("RunService").Heartbeat:Connect(function()
        if not isEnabled then return end -- FIX: Check isEnabled
        lastBeat = os.clock()
    end))

    -- FIX: Use proper task tracking
    watchdogTask = task.spawn(function()
        while isEnabled do
            local dt = os.clock() - lastBeat
            if dt > opts.heuristicTimeout and isEnabled then -- FIX: Double check isEnabled
                logger:warn(string.format("Heuristic timeout (%.1fs) → planning teleport.", dt))
                planTeleport()
                task.wait(math.max(5, opts.heuristicTimeout * 0.5))
            else
                task.wait(2) -- FIX: Shorter wait for more responsive shutdown
            end
        end
        watchdogTask = nil -- FIX: Clear reference when done
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
    retryCount = 0

    clearConnections() -- FIX: Clear any existing connections first
    
    hookErrorDetection()     -- FIX: Added simple error detection
    hookPromptDetection()
    hookTeleportFailures()
    hookHeuristicWatchdog()

    -- Keep snapshot fresh
    addCon(Players.PlayerAdded:Connect(function(p)
        if p == LocalPlayer and isEnabled then -- FIX: Check isEnabled
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
    
    -- FIX: Set flag first to stop all background operations
    isEnabled = false
    isTeleporting = false
    
    -- FIX: Wait a bit for background tasks to notice the flag change
    task.wait(0.1)
    
    clearConnections()
    logger:info("AutoReconnect stopped.")
    return true
end

function AutoReconnect:Cleanup()
    self:Stop()
    task.wait(0.2) -- FIX: Give more time for cleanup
    isInitialized = false
    logger:info("Cleaned up.")
end

-- Compatibility functions
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
        hasWatchdog   = watchdogTask ~= nil,
    }
end

return AutoReconnect