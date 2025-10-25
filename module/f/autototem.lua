-- ===========================
-- AUTO TOTEM FEATURE
-- File: autototem.lua
-- ===========================
-- AUTO TOTEM (single-select)
-- Lifecycle: :Init(), :Start(config?), :Stop(), :Cleanup()
-- Setters  : :SetSelectedTotem(nameOrUUID), :SetCheckInterval(number)
-- Helpers  : :GetAvailableTotems() -> array, :GetCooldownInfo(uuid) -> info
-- Note     : SetSelectedTotem accepts both totem name or UUID
-- ===========================

local AutoTotem = {}
AutoTotem.__index = AutoTotem

local logger = _G.Logger and _G.Logger.new("AutoTotem") or {
    debug = function() end,
    info = function() end,
    warn = function() end,
    error = function() end
}

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService        = game:GetService("RunService")

local TotemWatcher      = require(script.Parent.TotemWatcher)

-- Remotes
local NetPath, SpawnTotemEvent
local remotesReady      = false

-- State
local isRunning         = false
local totemWatcher      = nil
local connections       = {}

-- Config
local selectedTotemUUID = nil
local lastUsedTime      = {}  -- [uuid] = unixTime
local TOTEM_DURATION    = 3600 + 2  -- 1 jam + 2 detik buffer

-- Pacing
local checkInterval     = 5  -- seconds
local lastCheckAt       = 0

-- ========= helpers =========
local function initRemotes()
    return pcall(function()
        NetPath = ReplicatedStorage:WaitForChild("Packages", 5)
            :WaitForChild("_Index", 5)
            :WaitForChild("sleitnick_net@0.2.0", 5)
            :WaitForChild("net", 5)
        SpawnTotemEvent = NetPath:WaitForChild("RE/SpawnTotem", 5)
    end)
end

local function nowSec()
    return os.time()
end

local function isOnCooldown(uuid)
    local lastUsed = lastUsedTime[uuid]
    if not lastUsed then return false end
    return (nowSec() - lastUsed) < TOTEM_DURATION
end

local function getCooldownRemaining(uuid)
    if not isOnCooldown(uuid) then return 0 end
    local timeSinceUse = nowSec() - lastUsedTime[uuid]
    return math.max(0, TOTEM_DURATION - timeSinceUse)
end

local function formatCooldown(seconds)
    if seconds <= 0 then return "Ready" end
    
    local hours = math.floor(seconds / 3600)
    local minutes = math.floor((seconds % 3600) / 60)
    local secs = seconds % 60
    
    if hours > 0 then
        return string.format("%dh %dm %ds", hours, minutes, secs)
    elseif minutes > 0 then
        return string.format("%dm %ds", minutes, secs)
    else
        return string.format("%ds", secs)
    end
end

local function useTotem(uuid)
    if not SpawnTotemEvent then
        logger:warn("SpawnTotem event not found")
        return false
    end
    
    logger:info("Using totem: " .. tostring(uuid))
    
    local ok, err = pcall(function()
        SpawnTotemEvent:FireServer(uuid)
    end)
    
    if ok then
        lastUsedTime[uuid] = nowSec()
        logger:info("Totem used successfully, cooldown started")
    else
        logger:warn("Failed to use totem: " .. tostring(err))
    end
    
    return ok
end

-- ========= lifecycle =========
function AutoTotem:Init()
    -- Init TotemWatcher
    totemWatcher = TotemWatcher.getShared()
    if not totemWatcher then
        logger:warn("TotemWatcher not available")
        return false
    end
    
    -- Init remotes
    local ok = initRemotes()
    remotesReady = ok and true or false
    if not remotesReady then
        logger:warn("Remotes not ready")
        return false
    end
    
    logger:info("Initialized")
    return true
end

-- config: { totemName = "Luck Totem", checkInterval = 5 }
-- atau    { totemUUID = "uuid-string", checkInterval = 5 }
function AutoTotem:Start(config)
    if isRunning then 
        logger:warn("Already running")
        return 
    end
    
    if not remotesReady then
        logger:warn("Start blocked: remotes not ready")
        return
    end
    
    if config then
        if type(config.checkInterval) == "number" then 
            self:SetCheckInterval(config.checkInterval) 
        end
        if type(config.totemName) == "string" then 
            self:SetSelectedTotem(config.totemName) 
        elseif type(config.totemUUID) == "string" then 
            self:SetSelectedTotem(config.totemUUID) 
        end
    end
    
    if not selectedTotemUUID then
        logger:warn("No totem selected")
        return
    end
    
    isRunning = true
    logger:info("Started")
    
    -- Listen untuk inventory changes (event-driven)
    local conn = totemWatcher:onTotemChanged(function()
        if selectedTotemUUID then
            -- Check immediately when inventory changes
            task.defer(function()
                if isRunning then
                    self:TryUseTotem()
                end
            end)
        end
    end)
    table.insert(connections, conn)
    
    -- Heartbeat check
    conn = RunService.Heartbeat:Connect(function()
        if not isRunning then return end
        
        local t = nowSec()
        if t - lastCheckAt < checkInterval then return end
        lastCheckAt = t
        
        self:TryUseTotem()
    end)
    table.insert(connections, conn)
    
    -- Immediate first check
    task.defer(function()
        self:TryUseTotem()
    end)
end

function AutoTotem:Stop()
    if not isRunning then return end
    
    isRunning = false
    logger:info("Stopped")
    
    -- Disconnect all connections
    for _, conn in ipairs(connections) do
        pcall(function() conn:Disconnect() end)
    end
    table.clear(connections)
end

function AutoTotem:Cleanup()
    self:Stop()
    selectedTotemUUID = nil
    table.clear(lastUsedTime)
    lastCheckAt = 0
    logger:info("Cleaned up")
end

-- ========= core logic =========
function AutoTotem:TryUseTotem()
    if not isRunning or not selectedTotemUUID then return end
    
    -- Check if totem exists in inventory (O(1) lookup)
    local totem = totemWatcher:getTotemByUUID(selectedTotemUUID)
    if not totem then
        return
    end
    
    -- Check cooldown
    if isOnCooldown(selectedTotemUUID) then
        return
    end
    
    -- Use totem
    useTotem(selectedTotemUUID)
end

-- ========= setters =========
function AutoTotem:SetSelectedTotem(nameOrUUID)
    if type(nameOrUUID) ~= "string" then return false end
    
    -- Try sebagai UUID dulu
    local totem = totemWatcher:getTotemByUUID(nameOrUUID)
    
    -- Kalau ga ketemu, coba cari by name
    if not totem then
        totem = totemWatcher:getTotemByName(nameOrUUID)
    end
    
    if not totem then
        logger:warn("Totem not found: " .. nameOrUUID)
        return false
    end
    
    selectedTotemUUID = totem.uuid
    logger:info("Selected totem: " .. totem.name .. " (" .. totem.uuid .. ")")
    
    -- Immediate check if running
    if isRunning then
        task.defer(function()
            self:TryUseTotem()
        end)
    end
    
    return true
end

function AutoTotem:SetCheckInterval(seconds)
    if type(seconds) ~= "number" then return false end
    -- clamp biar aman (1-60 detik)
    checkInterval = math.clamp(seconds, 1, 60)
    logger:info("Check interval set to: " .. checkInterval .. "s")
    return true
end

-- ========= helpers =========
function AutoTotem:GetAvailableTotems()
    local available = {}
    local allTotems = totemWatcher:getAllTotems()
    
    for _, totem in ipairs(allTotems) do
        table.insert(available, {
            name = totem.name,
            uuid = totem.uuid,
            favorited = totem.favorited,
            amount = totem.amount,
            lastUsed = lastUsedTime[totem.uuid],
            onCooldown = isOnCooldown(totem.uuid),
            cooldownRemaining = getCooldownRemaining(totem.uuid),
            cooldownFormatted = formatCooldown(getCooldownRemaining(totem.uuid))
        })
    end
    
    return available
end

function AutoTotem:GetCooldownInfo(uuid)
    if type(uuid) ~= "string" then return nil end
    
    return {
        onCooldown = isOnCooldown(uuid),
        remaining = getCooldownRemaining(uuid),
        formatted = formatCooldown(getCooldownRemaining(uuid)),
        lastUsed = lastUsedTime[uuid]
    }
end

return AutoTotem