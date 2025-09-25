--========================================================
-- Feature: AutoTeleportEvent v2 - Fixed Critical Errors
--========================================================

local AutoTeleportEvent = {}
AutoTeleportEvent.__index = AutoTeleportEvent

local logger = _G.Logger and _G.Logger.new("AutoTeleportEvent") or {
    debug = function() end,
    info = function() end,
    warn = function() end,
    error = function() end
}

local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService        = game:GetService("RunService")
local Workspace         = game:GetService("Workspace")

local LocalPlayer = Players.LocalPlayer

-- ===== State =====
local running          = false
local hbConn           = nil
local charConn         = nil
local propsConnections = {}     -- Multiple Props folders monitoring
local workspaceConn    = nil
local notificationConn = nil
local eventsFolder     = nil

local selectedPriorityList = {}      -- Array dengan urutan prioritas
local selectedSet          = {}      -- Set untuk quick lookup
local hoverHeight          = 15
local savedPosition        = nil
local currentTarget        = nil
local lastKnownActiveProps = {}
local notifiedEvents       = {}

-- Cache event names dari ReplicatedStorage.Events
local validEventNames = {}           -- Set berdasarkan moduleData.Name

-- ===== Utils =====
local function normName(s)
    s = string.lower(s or "")
    s = s:gsub("%W", "")
    return s
end

local function waitChild(parent, name, timeout)
    local t0 = os.clock()
    local obj = parent:FindFirstChild(name)
    while not obj and (os.clock() - t0) < (timeout or 5) do
        parent.ChildAdded:Wait()
        obj = parent:FindFirstChild(name)
    end
    return obj
end

local function ensureCharacter()
    local char = LocalPlayer.Character or LocalPlayer.CharacterAdded:Wait()
    local hrp  = char:FindFirstChild("HumanoidRootPart") or waitChild(char, "HumanoidRootPart", 5)
    local hum  = char:FindFirstChildOfClass("Humanoid")
    return char, hrp, hum
end

local function setCFrameSafely(hrp, targetPos, keepLookAt)
    local look = keepLookAt or (hrp.CFrame.LookVector + hrp.Position)
    hrp.AssemblyLinearVelocity = Vector3.new()
    hrp.AssemblyAngularVelocity = Vector3.new()
    hrp.CFrame = CFrame.lookAt(targetPos, Vector3.new(look.X, targetPos.Y, look.Z))
end

local function saveCurrentPosition()
    if savedPosition then return end
    local _, hrp = ensureCharacter()
    if hrp then
        savedPosition = hrp.CFrame
        logger:info("Position saved at:", tostring(savedPosition.Position))
    end
end

-- ===== Count table entries =====
local function countTable(t)
    local count = 0
    for _ in pairs(t) do
        count = count + 1
    end
    return count
end

-- ===== Index Events dari ReplicatedStorage.Events (FIXED) =====
local function indexEvents()
    table.clear(validEventNames)
    if not eventsFolder then 
        logger:warn("Events folder not found")
        return 
    end
    
    local eventCount = 0
    for _, child in ipairs(eventsFolder:GetChildren()) do
        if child:IsA("ModuleScript") then
            local ok, data = pcall(require, child)
            if ok and type(data) == "table" and data.Name and data.Coordinates then
                -- Simpan nama asli dari moduleData.Name
                validEventNames[normName(data.Name)] = data.Name
                eventCount = eventCount + 1
                logger:debug("Indexed event:", data.Name)
            end
        end
    end
    
    logger:info("Indexed", eventCount, "valid events")
end

-- ===== Setup Event Notification Listener =====
local function setupEventNotificationListener()
    if notificationConn then notificationConn:Disconnect() end
    
    local textNotificationRE = nil
    local packagesFolder = ReplicatedStorage:FindFirstChild("Packages")
    
    if packagesFolder then
        local indexFolder = packagesFolder:FindFirstChild("_Index")
        if indexFolder then
            for _, child in ipairs(indexFolder:GetChildren()) do
                if child.Name:find("sleitnick_net") then
                    local netFolder = child:FindFirstChild("net")
                    if netFolder then
                        textNotificationRE = netFolder:FindFirstChild("RE/TextNotification")
                        if textNotificationRE then break end
                    end
                end
            end
        end
    end
    
    if textNotificationRE then
        logger:info("Setting up event notification listener")
        notificationConn = textNotificationRE.OnClientEvent:Connect(function(data)
            if type(data) == "table" and data.Type == "Event" and data.Text then
                local eventName = data.Text
                local eventKey = normName(eventName)
                
                logger:info("Event notification received:", eventName)
                
                notifiedEvents[eventKey] = {
                    name = eventName,
                    timestamp = os.clock()
                }
                
                -- Clean up old notifications
                for key, info in pairs(notifiedEvents) do
                    if os.clock() - info.timestamp > 300 then
                        notifiedEvents[key] = nil
                    end
                end
            end
        end)
    else
        logger:warn("Could not find TextNotification RE")
    end
end

-- ===== Resolve Model Pivot Position =====
local function resolveModelPivotPos(model)
    local ok, cf = pcall(function() return model:GetPivot() end)
    if ok and typeof(cf) == "CFrame" then return cf.Position end
    local ok2, cf2 = pcall(function() return model.WorldPivot end)
    if ok2 and typeof(cf2) == "CFrame" then return cf2.Position end
    return nil
end

-- ===== Enhanced Event Detection =====
local function isEventModel(model)
    if not model:IsA("Model") then return false, nil, nil end
    
    local modelName = model.Name
    local modelKey = normName(modelName)
    
    -- 1. Check terhadap ReplicatedStorage.Events (moduleData.Name)
    if validEventNames[modelKey] then
        return true, validEventNames[modelKey], modelKey
    end
    
    -- 2. Check terhadap recent notifications
    for notifKey, notifInfo in pairs(notifiedEvents) do
        if modelKey == notifKey then
            return true, notifInfo.name, modelKey
        end
        
        -- Fuzzy matching
        if modelKey:find(notifKey, 1, true) or notifKey:find(modelKey, 1, true) then
            return true, notifInfo.name, modelKey
        end
    end
    
    -- 3. Special case untuk "Model" name dengan recent notification
    if modelName == "Model" then
        -- Cari notification terbaru dalam 30 detik
        local recentNotif = nil
        local latestTime = 0
        for _, notifInfo in pairs(notifiedEvents) do
            if os.clock() - notifInfo.timestamp < 30 and notifInfo.timestamp > latestTime then
                recentNotif = notifInfo
                latestTime = notifInfo.timestamp
            end
        end
        if recentNotif then
            return true, recentNotif.name, normName(recentNotif.name)
        end
    end
    
    -- 4. Common event patterns sebagai fallback
    local eventPatterns = {
        "hunt", "boss", "raid", "event", "invasion", "attack", 
        "storm", "hole", "meteor", "comet", "shark", "worm", "admin",
        "ghost", "megalodon"
    }
    
    for _, pattern in ipairs(eventPatterns) do
        if modelKey:find(pattern, 1, true) then
            return true, modelName, modelKey
        end
    end
    
    return false, nil, nil
end

-- ===== Scan Active Events (FIXED - Support Multiple Props) =====
local function scanAllActiveEvents()
    local activeEventsList = {}

    local menu = Workspace:FindFirstChild("!!! MENU RINGS")
    if not menu then return activeEventsList end

    -- Scan SEMUA Props folders di dalam !!! MENU RINGS
    for _, child in ipairs(menu:GetChildren()) do
        if child.Name == "Props" and child:IsA("Model") then
            -- Scan direct children dari setiap Props folder
            for _, model in ipairs(child:GetChildren()) do
                if model:IsA("Model") then
                    local isEvent, eventName, eventKey = isEventModel(model)
                    if isEvent then
                        local pos = resolveModelPivotPos(model)
                        if pos then
                            table.insert(activeEventsList, {
                                model     = model,
                                name      = eventName,
                                nameKey   = eventKey,
                                pos       = pos,
                                propsParent = child, -- Reference ke Props folder
                            })
                            logger:debug("Found active event:", eventName, "in Props:", child:GetFullName())
                        end
                    end
                end
            end
        end
    end

    return activeEventsList
end

-- ===== Priority Matching System =====
local function isPriorityEvent(nameKey, displayName)
    if #selectedPriorityList == 0 then return false end
    
    local displayKey = normName(displayName)
    
    for _, priorityKey in ipairs(selectedPriorityList) do
        -- Exact match
        if nameKey == priorityKey or displayKey == priorityKey then
            return true
        end
        
        -- Contains match (both directions)
        if nameKey:find(priorityKey, 1, true) or priorityKey:find(nameKey, 1, true) then
            return true
        end
        
        if displayKey:find(priorityKey, 1, true) or priorityKey:find(displayKey, 1, true) then
            return true
        end
    end
    
    return false
end

local function getPriorityRank(nameKey, displayName)
    if #selectedPriorityList == 0 then return math.huge end
    
    local displayKey = normName(displayName)
    
    for i, priorityKey in ipairs(selectedPriorityList) do
        -- Check berbagai jenis matching
        if nameKey == priorityKey or displayKey == priorityKey then
            return i
        end
        
        if nameKey:find(priorityKey, 1, true) or priorityKey:find(nameKey, 1, true) then
            return i
        end
        
        if displayKey:find(priorityKey, 1, true) or priorityKey:find(displayKey, 1, true) then
            return i
        end
    end
    
    return math.huge
end

-- ===== Choose Best Event =====
local function chooseBestActiveEvent()
    local actives = scanAllActiveEvents()
    if #actives == 0 then return nil end

    -- Pisahkan priority events dan non-priority events
    local priorityEvents = {}
    local nonPriorityEvents = {}
    
    for _, event in ipairs(actives) do
        event.priorityRank = getPriorityRank(event.nameKey, event.name)
        
        if isPriorityEvent(event.nameKey, event.name) then
            table.insert(priorityEvents, event)
        else
            table.insert(nonPriorityEvents, event)
        end
    end
    
    -- Jika ada priority events, pilih yang tertinggi
    if #priorityEvents > 0 then
        table.sort(priorityEvents, function(a, b)
            if a.priorityRank ~= b.priorityRank then 
                return a.priorityRank < b.priorityRank 
            end
            return a.name < b.name -- Stable sort
        end)
        
        logger:info("Selecting priority event:", priorityEvents[1].name)
        return priorityEvents[1]
    end
    
    -- Jika user sudah set priorities tapi tidak ada yang aktif,
    -- dan ada non-priority events, pilih yang pertama
    if #selectedPriorityList > 0 and #nonPriorityEvents > 0 then
        table.sort(nonPriorityEvents, function(a, b) return a.name < b.name end)
        logger:info("No priority events active, selecting fallback:", nonPriorityEvents[1].name)
        return nonPriorityEvents[1]
    end
    
    -- Jika user tidak set priorities, pilih event manapun
    if #selectedPriorityList == 0 and #nonPriorityEvents > 0 then
        table.sort(nonPriorityEvents, function(a, b) return a.name < b.name end)
        logger:info("No priorities set, selecting first available:", nonPriorityEvents[1].name)
        return nonPriorityEvents[1]
    end
    
    return nil
end

-- ===== Teleport Functions =====
local function teleportToTarget(target)
    local _, hrp = ensureCharacter()
    if not hrp then return false, "NO_HRP" end
    
    saveCurrentPosition()
    
    local tpPos = target.pos + Vector3.new(0, hoverHeight, 0)
    setCFrameSafely(hrp, tpPos)
    logger:info("Teleported to:", target.name, "at", tostring(target.pos))
    return true
end

local function restoreToSavedPosition()
    if not savedPosition then 
        logger:info("No saved position to restore")
        return 
    end
    
    local _, hrp = ensureCharacter()
    if hrp then
        setCFrameSafely(hrp, savedPosition.Position, savedPosition.Position + savedPosition.LookVector)
        logger:info("Restored to saved position:", tostring(savedPosition.Position))
    end
end

local function maintainHover()
    local _, hrp = ensureCharacter()
    if hrp and currentTarget then
        if not currentTarget.model or not currentTarget.model.Parent then
            logger:info("Current target no longer exists")
            currentTarget = nil
            return
        end
        
        local desired = currentTarget.pos + Vector3.new(0, hoverHeight, 0)
        if (hrp.Position - desired).Magnitude > 1.2 then
            setCFrameSafely(hrp, desired)
        else
            hrp.AssemblyLinearVelocity = Vector3.new()
            hrp.AssemblyAngularVelocity = Vector3.new()
        end
    end
end

-- ===== Main Loop =====
local function startLoop()
    if hbConn then hbConn:Disconnect() end
    local lastTick = 0
    hbConn = RunService.Heartbeat:Connect(function()
        if not running then return end
        local now = os.clock()
        
        maintainHover()
        
        if now - lastTick < 0.5 then -- Check setiap 0.5 detik
            return
        end
        lastTick = now

        local best = chooseBestActiveEvent()

        if not best then
            if currentTarget then
                logger:info("No valid events found, returning to saved position")
                currentTarget = nil
            end
            restoreToSavedPosition()
            return
        end

        -- Check apakah perlu ganti target
        if (not currentTarget) or (currentTarget.model ~= best.model) then
            logger:info("Switching to target:", best.name, "Priority rank:", best.priorityRank)
            teleportToTarget(best)
            currentTarget = best
        end
    end)
end

-- ===== Workspace Monitoring (FIXED - Monitor Multiple Props) =====
local function setupWorkspaceMonitoring()
    -- Clear existing connections
    for _, conn in pairs(propsConnections) do
        if conn then conn:Disconnect() end
    end
    table.clear(propsConnections)
    if workspaceConn then workspaceConn:Disconnect() end

    local function bindProps(props, propsId)
        if not props then return end
        
        local addedConn = props.ChildAdded:Connect(function(c)
            if c:IsA("Model") then 
                task.wait(0.1)
                logger:info("New event model added:", c.Name, "in", props:GetFullName())
            end
        end)
        
        local removedConn = props.ChildRemoved:Connect(function(c)
            if c:IsA("Model") then 
                logger:info("Event model removed:", c.Name, "from", props:GetFullName())
            end
        end)
        
        propsConnections[propsId .. "_added"] = addedConn
        propsConnections[propsId .. "_removed"] = removedConn
    end

    local menu = Workspace:FindFirstChild("!!! MENU RINGS")
    if menu then
        -- Bind semua Props folders yang sudah ada
        for i, child in ipairs(menu:GetChildren()) do
            if child.Name == "Props" and child:IsA("Model") then
                bindProps(child, "props_" .. i)
            end
        end
    end

    -- Monitor untuk Props folders baru
    workspaceConn = Workspace.ChildAdded:Connect(function(c)
        if c.Name == "!!! MENU RINGS" then
            task.wait(0.5) -- Wait for Props to be added
            for i, child in ipairs(c:GetChildren()) do
                if child.Name == "Props" and child:IsA("Model") then
                    bindProps(child, "props_new_" .. i)
                end
            end
        end
    end)
end

-- ===== Public Methods =====
function AutoTeleportEvent:Init(gui)
    eventsFolder = ReplicatedStorage:FindFirstChild("Events")
    if not eventsFolder then
        logger:warn("ReplicatedStorage.Events not found, waiting...")
        eventsFolder = waitChild(ReplicatedStorage, "Events", 5)
    end
    
    if eventsFolder then
        indexEvents()
    else
        logger:error("Failed to find ReplicatedStorage.Events")
    end
    
    setupEventNotificationListener()

    if charConn then charConn:Disconnect() end
    charConn = LocalPlayer.CharacterAdded:Connect(function()
        savedPosition = nil
        if running and currentTarget then
            task.defer(function()
                task.wait(0.5)
                if currentTarget then
                    teleportToTarget(currentTarget)
                end
            end)
        end
    end)

    setupWorkspaceMonitoring()
    
    logger:info("AutoTeleportEvent v2 initialized successfully")
    return true
end

function AutoTeleportEvent:Start(config)
    if running then return true end
    running = true

    if config then
        if type(config.hoverHeight) == "number" then
            hoverHeight = math.clamp(config.hoverHeight, 5, 100)
        end
        if config.selectedEvents then
            self:SetSelectedEvents(config.selectedEvents)
        end
    end

    currentTarget = nil
    savedPosition = nil
    table.clear(lastKnownActiveProps)
    
    if #selectedPriorityList > 0 then
        logger:info("Starting with priority events:", table.concat(selectedPriorityList, ", "))
    else
        logger:info("Starting with no event priorities (will teleport to any available event)")
    end
    
    local best = chooseBestActiveEvent()
    if best then
        teleportToTarget(best)
        currentTarget = best
        logger:info("Initial target found:", best.name)
    else
        logger:info("No initial target found")
    end

    startLoop()
    logger:info("AutoTeleportEvent v2 started successfully")
    return true
end

function AutoTeleportEvent:Stop()
    if not running then return true end
    running = false
    
    if hbConn then hbConn:Disconnect(); hbConn = nil end

    if savedPosition then
        restoreToSavedPosition()
    end
    
    currentTarget = nil
    table.clear(lastKnownActiveProps)
    logger:info("AutoTeleportEvent v2 stopped and position restored")
    return true
end

function AutoTeleportEvent:Cleanup()
    self:Stop()
    if charConn then charConn:Disconnect(); charConn = nil end
    
    for _, conn in pairs(propsConnections) do
        if conn then conn:Disconnect() end
    end
    table.clear(propsConnections)
    
    if workspaceConn    then workspaceConn:Disconnect();    workspaceConn = nil end
    if notificationConn then notificationConn:Disconnect(); notificationConn = nil end
    
    eventsFolder = nil
    table.clear(validEventNames)
    table.clear(selectedPriorityList)
    table.clear(selectedSet)
    table.clear(lastKnownActiveProps)
    table.clear(notifiedEvents)
    savedPosition = nil
    currentTarget = nil
    
    logger:info("AutoTeleportEvent v2 cleanup completed")
    return true
end

function AutoTeleportEvent:SetSelectedEvents(selected)
    table.clear(selectedPriorityList)
    table.clear(selectedSet)

    if type(selected) == "table" then
        if #selected > 0 then
            -- Array format - maintain priority order
            for _, eventName in ipairs(selected) do
                local key = normName(eventName)
                table.insert(selectedPriorityList, key)
                selectedSet[key] = true
            end
            logger:info("Priority events set:", table.concat(selectedPriorityList, ", "))
        else
            -- Dictionary format
            for eventName, isEnabled in pairs(selected) do
                if isEnabled then
                    local key = normName(eventName)
                    table.insert(selectedPriorityList, key)
                    selectedSet[key] = true
                end
            end
            if #selectedPriorityList > 0 then
                logger:info("Priority events set:", table.concat(selectedPriorityList, ", "))
            end
        end
    end
    
    return true
end

function AutoTeleportEvent:SetHoverHeight(h)
    if type(h) == "number" then
        hoverHeight = math.clamp(h, 5, 100)
        if running and currentTarget then
            local _, hrp = ensureCharacter()
            if hrp then
                local desired = currentTarget.pos + Vector3.new(0, hoverHeight, 0)
                setCFrameSafely(hrp, desired)
            end
        end
        return true
    end
    return false
end

function AutoTeleportEvent:Status()
    local activeEvents = scanAllActiveEvents()
    local activeNames = {}
    for _, event in ipairs(activeEvents) do
        table.insert(activeNames, event.name)
    end
    
    return {
        running         = running,
        hover           = hoverHeight,
        hasSavedPos     = savedPosition ~= nil,
        target          = currentTarget and currentTarget.name or nil,
        priorityEvents  = selectedPriorityList,
        activeEvents    = activeNames,
        notifications   = notifiedEvents,
        validEvents     = countTable(validEventNames)
    }
end

function AutoTeleportEvent.new()
    local self = setmetatable({}, AutoTeleportEvent)
    return self
end

return AutoTeleportEvent