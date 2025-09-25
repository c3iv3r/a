--========================================================
-- Feature: AutoTeleportEvent v2 (Fixed Priority System)
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
local propsAddedConn   = nil
local propsRemovedConn = nil
local workspaceConn    = nil
local notificationConn = nil
local eventsFolder     = nil

local selectedEvents    = {}             -- array of selected event names for priority
local selectedSet       = {}             -- set for quick lookup
local hoverHeight       = 15
local savedPosition     = nil
local currentTarget     = nil
local lastKnownActiveProps = {}
local notifiedEvents    = {}
local validEventNames   = {}             -- cache dari ReplicatedStorage.Events

-- ===== Utils =====
local function normName(s)
    return string.lower(tostring(s or "")):gsub("%W", "")
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

-- ===== Save Position =====
local function saveCurrentPosition()
    if savedPosition then return end
    local _, hrp = ensureCharacter()
    if hrp then
        savedPosition = hrp.CFrame
        logger:info("Position saved at:", tostring(savedPosition.Position))
    end
end

-- ===== Index Events dari ReplicatedStorage.Events =====
local function indexEvents()
    table.clear(validEventNames)
    if not eventsFolder then return end
    
    for _, event in pairs(eventsFolder:GetChildren()) do
        if event:IsA("ModuleScript") then
            local success, moduleData = pcall(function()
                return require(event)
            end)
            
            if success and moduleData and moduleData.Name then
                validEventNames[normName(moduleData.Name)] = moduleData.Name
                validEventNames[normName(event.Name)] = moduleData.Name
            end
        end
    end
    
    logger:info("Indexed", table.concat(validEventNames, ", "))
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
        logger:info("Found TextNotification RE")
        notificationConn = textNotificationRE.OnClientEvent:Connect(function(data)
            if type(data) == "table" and data.Type == "Event" and data.Text then
                local eventName = data.Text
                local eventKey = normName(eventName)
                
                notifiedEvents[eventKey] = {
                    name = eventName,
                    timestamp = os.clock()
                }
                
                -- Clean old notifications
                for key, info in pairs(notifiedEvents) do
                    if os.clock() - info.timestamp > 300 then
                        notifiedEvents[key] = nil
                    end
                end
                
                logger:info("Event notification:", eventName)
            end
        end)
    end
end

-- ===== Resolve Model Pivot =====
local function resolveModelPivotPos(model)
    local ok, cf = pcall(function() return model:GetPivot() end)
    if ok and typeof(cf) == "CFrame" then return cf.Position end
    local ok2, cf2 = pcall(function() return model.WorldPivot end)
    if ok2 and typeof(cf2) == "CFrame" then return cf2.Position end
    return nil
end

-- ===== Enhanced Event Detection =====
local function isEventModel(model)
    if not model:IsA("Model") then return false end
    
    local modelName = model.Name
    local modelKey = normName(modelName)
    
    -- 1. Check validEventNames dari ReplicatedStorage.Events
    if validEventNames[modelKey] then
        return true, validEventNames[modelKey], modelKey
    end
    
    -- 2. Check recent notifications
    for notifKey, notifInfo in pairs(notifiedEvents) do
        if modelKey == notifKey then
            return true, notifInfo.name, modelKey
        end
        
        if modelKey:find(notifKey, 1, true) or notifKey:find(modelKey, 1, true) then
            return true, notifInfo.name, modelKey
        end
        
        -- Special case: "Model" bisa jadi event apa saja yang baru
        if modelName == "Model" and os.clock() - notifInfo.timestamp < 30 then
            return true, notifInfo.name, modelKey
        end
    end
    
    -- 3. Common event patterns
    local eventPatterns = {
        "hunt", "boss", "raid", "event", "invasion", "attack", 
        "storm", "hole", "meteor", "comet", "shark", "worm", "admin"
    }
    
    for _, pattern in ipairs(eventPatterns) do
        if modelKey:find(pattern, 1, true) then
            return true, modelName, modelKey
        end
    end
    
    return false
end

-- ===== Scan Active Events =====
local function scanActiveEvents()
    local activeEvents = {}
    
    local menu = Workspace:FindFirstChild("!!! MENU RINGS")
    if not menu then return activeEvents end
    
    -- Scan setiap Props folder yang ada di menu
    for _, child in ipairs(menu:GetChildren()) do
        if child:IsA("Model") and child.Name ~= "Props" then
            -- Ini adalah event model langsung (Shark Hunt, Megalodon Hunt, etc)
            local isEvent, eventName, eventKey = isEventModel(child)
            if isEvent then
                local pos = resolveModelPivotPos(child)
                if pos then
                    table.insert(activeEvents, {
                        model = child,
                        name = eventName,
                        nameKey = eventKey,
                        pos = pos,
                        propsName = child.Name
                    })
                end
            end
        elseif child.Name == "Props" and child:IsA("Folder") then
            -- Scan Props folder juga untuk backward compatibility
            for _, model in ipairs(child:GetChildren()) do
                if model:IsA("Model") then
                    local isEvent, eventName, eventKey = isEventModel(model)
                    if isEvent then
                        local pos = resolveModelPivotPos(model)
                        if pos then
                            table.insert(activeEvents, {
                                model = model,
                                name = eventName,
                                nameKey = eventKey,
                                pos = pos,
                                propsName = "Props"
                            })
                        end
                    end
                end
            end
        end
    end
    
    return activeEvents
end

-- ===== Priority Matching System =====
local function getEventPriority(event)
    if #selectedEvents == 0 then
        return 1 -- Jika tidak ada yang dipilih, semua event priority sama
    end
    
    -- Check exact match dengan selected events (by name or key)
    for i, selectedName in ipairs(selectedEvents) do
        local selectedKey = normName(selectedName)
        
        if event.nameKey == selectedKey or 
           normName(event.name) == selectedKey or
           event.nameKey:find(selectedKey, 1, true) or
           selectedKey:find(event.nameKey, 1, true) then
            return i -- Priority berdasarkan index (lower = higher priority)
        end
    end
    
    return math.huge -- Tidak diprioritaskan, tapi masih bisa dipilih
end

local function chooseBestEvent()
    local activeEvents = scanActiveEvents()
    if #activeEvents == 0 then return nil end
    
    -- Jika ada selected events, prioritaskan yang dipilih
    local priorityEvents = {}
    local otherEvents = {}
    
    for _, event in ipairs(activeEvents) do
        local priority = getEventPriority(event)
        event.priority = priority
        
        if priority < math.huge then
            table.insert(priorityEvents, event)
        else
            table.insert(otherEvents, event)
        end
    end
    
    -- Sort priority events by priority index
    table.sort(priorityEvents, function(a, b)
        if a.priority ~= b.priority then
            return a.priority < b.priority
        end
        return a.name < b.name
    end)
    
    -- Jika ada priority events, ambil yang pertama
    if #priorityEvents > 0 then
        return priorityEvents[1]
    end
    
    -- Jika tidak ada yang selected ATAU tidak ada selected events, ambil event apa saja
    if #selectedEvents == 0 and #otherEvents > 0 then
        table.sort(otherEvents, function(a, b) return a.name < b.name end)
        return otherEvents[1]
    end
    
    -- Jika ada selected events tapi tidak cocok, teleport ke event lain yang tersedia
    if #selectedEvents > 0 and #otherEvents > 0 then
        table.sort(otherEvents, function(a, b) return a.name < b.name end)
        return otherEvents[1]
    end
    
    return nil
end

-- ===== Teleport Functions =====
local function teleportToTarget(target)
    local _, hrp = ensureCharacter()
    if not hrp then return false end
    
    saveCurrentPosition()
    
    local tpPos = target.pos + Vector3.new(0, hoverHeight, 0)
    setCFrameSafely(hrp, tpPos)
    logger:info("Teleported to:", target.name, "at", tostring(target.pos))
    return true
end

local function restoreToSavedPosition()
    if not savedPosition then return end
    
    local _, hrp = ensureCharacter()
    if hrp then
        setCFrameSafely(hrp, savedPosition.Position, savedPosition.Position + savedPosition.LookVector)
        logger:info("Restored to saved position")
    end
end

local function maintainHover()
    local _, hrp = ensureCharacter()
    if hrp and currentTarget then
        if not currentTarget.model or not currentTarget.model.Parent then
            currentTarget = nil
            return
        end
        
        local desired = currentTarget.pos + Vector3.new(0, hoverHeight, 0)
        if (hrp.Position - desired).Magnitude > 0.5 then
            setCFrameSafely(hrp, desired)
        end
        
        -- Always stop movement to keep character still
        hrp.AssemblyLinearVelocity = Vector3.new()
        hrp.AssemblyAngularVelocity = Vector3.new()
        
        -- Anchor character to prevent any movement
        if hrp.AssemblyLinearVelocity.Magnitude > 0.1 or hrp.AssemblyAngularVelocity.Magnitude > 0.1 then
            hrp.CFrame = CFrame.lookAt(desired, desired + hrp.CFrame.LookVector)
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
        
        if now - lastTick < 0.3 then return end
        lastTick = now
        
        local bestEvent = chooseBestEvent()
        
        if not bestEvent then
            if currentTarget then
                logger:info("No events available, returning to saved position")
                currentTarget = nil
            end
            restoreToSavedPosition()
            return
        end
        
        -- Switch target jika berbeda atau lebih priority
        local shouldSwitch = false
        
        if not currentTarget then
            shouldSwitch = true
        elseif currentTarget.model ~= bestEvent.model then
            shouldSwitch = true
        elseif currentTarget.priority and bestEvent.priority and bestEvent.priority < currentTarget.priority then
            shouldSwitch = true
        end
        
        if shouldSwitch then
            logger:info("Switching to:", bestEvent.name, "priority:", bestEvent.priority)
            teleportToTarget(bestEvent)
            currentTarget = bestEvent
        end
    end)
end

-- ===== Setup Monitoring =====
local function setupWorkspaceMonitoring()
    if propsAddedConn then propsAddedConn:Disconnect() end
    if propsRemovedConn then propsRemovedConn:Disconnect() end
    if workspaceConn then workspaceConn:Disconnect() end
    
    local function bindMenuRings(menu)
        if not menu then return end
        
        -- Monitor direct children of menu (event models)
        propsAddedConn = menu.ChildAdded:Connect(function(c)
            if c:IsA("Model") then
                task.wait(0.1)
                logger:info("New event model:", c.Name)
            end
        end)
        propsRemovedConn = menu.ChildRemoved:Connect(function(c)
            if c:IsA("Model") then
                logger:info("Event model removed:", c.Name)
            end
        end)
        
        -- Also monitor Props folder if exists
        local props = menu:FindFirstChild("Props")
        if props then
            props.ChildAdded:Connect(function(c)
                if c:IsA("Model") then
                    task.wait(0.1)
                    logger:info("New event model in Props:", c.Name)
                end
            end)
            props.ChildRemoved:Connect(function(c)
                if c:IsA("Model") then
                    logger:info("Event model removed from Props:", c.Name)
                end
            end)
        end
    end
    
    local menu = Workspace:FindFirstChild("!!! MENU RINGS")
    bindMenuRings(menu)
    
    workspaceConn = Workspace.ChildAdded:Connect(function(c)
        if c.Name == "!!! MENU RINGS" then
            bindMenuRings(c)
        end
    end)
end

-- ===== Public Methods =====
function AutoTeleportEvent:Init(gui)
    eventsFolder = ReplicatedStorage:FindFirstChild("Events") or waitChild(ReplicatedStorage, "Events", 5)
    indexEvents()
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
    logger:info("Initialized successfully")
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
    
    logger:info("Starting with selected events:", table.concat(selectedEvents, ", "))
    
    local bestEvent = chooseBestEvent()
    if bestEvent then
        teleportToTarget(bestEvent)
        currentTarget = bestEvent
        logger:info("Initial target:", bestEvent.name)
    end
    
    startLoop()
    logger:info("Started successfully")
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
    logger:info("Stopped")
    return true
end

function AutoTeleportEvent:Cleanup()
    self:Stop()
    if charConn then charConn:Disconnect(); charConn = nil end
    if propsAddedConn then propsAddedConn:Disconnect(); propsAddedConn = nil end
    if propsRemovedConn then propsRemovedConn:Disconnect(); propsRemovedConn = nil end
    if workspaceConn then workspaceConn:Disconnect(); workspaceConn = nil end
    if notificationConn then notificationConn:Disconnect(); notificationConn = nil end
    
    eventsFolder = nil
    table.clear(validEventNames)
    table.clear(selectedEvents)
    table.clear(selectedSet)
    table.clear(lastKnownActiveProps)
    table.clear(notifiedEvents)
    savedPosition = nil
    currentTarget = nil
    
    logger:info("Cleanup completed")
    return true
end

function AutoTeleportEvent:SetSelectedEvents(events)
    table.clear(selectedEvents)
    table.clear(selectedSet)
    
    if type(events) == "table" then
        for _, eventName in ipairs(events) do
            table.insert(selectedEvents, tostring(eventName))
            selectedSet[normName(eventName)] = true
        end
        logger:info("Selected events updated:", table.concat(selectedEvents, ", "))
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
    return {
        running = running,
        hover = hoverHeight,
        hasSavedPos = savedPosition ~= nil,
        target = currentTarget and currentTarget.name or nil,
        selectedEvents = selectedEvents,
        activeEvents = scanActiveEvents()
    }
end

function AutoTeleportEvent.new()
    return setmetatable({}, AutoTeleportEvent)
end

return AutoTeleportEvent