--========================================================
-- AutoTeleportEvent v2 (Priority + Fallback) - Multi Props
-- API: Init(), Start({ selectedEvents?, hoverHeight? }), Stop(), Cleanup()
-- Extra: SetSelectedEvents(list|set), SetHoverHeight(n), Status()
--========================================================
local AutoTeleportEvent = {}
AutoTeleportEvent.__index = AutoTeleportEvent

-- logger (no-op fallback)
local logger = _G.Logger and _G.Logger.new and _G.Logger:new("AutoTeleportEventV2") or
    { debug = function() end,
      info = function() end,
      warn = function() end,
      error = function() end }

-- Services
local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService        = game:GetService("RunService")
local Workspace         = game:GetService("Workspace")
local LocalPlayer       = Players.LocalPlayer

-- ===== State =====
local running          = false
local hbConn           = nil
local charConn         = nil
local workspaceConn    = nil
local menuAddConn      = nil
local menuRemConn      = nil

local propsConns       = {}   -- [Folder Props] = {added=conn, removed=conn}
local lastKnownModels  = {}   -- [Model]=true
local notificationConn = nil

local eventsContainer  = nil  -- ReplicatedStorage.Events (ModuleScript that may have children)
local validEventNames  = {}   -- set of normalized names

local savedPosition    = nil  -- CFrame
local currentTarget    = nil  -- {model,name,nameKey,pos,rank,propsRef}
local hoverHeight      = 15

-- user selection (priority order)
local selectedPriority = {}   -- array of normalized names (1 = highest priority)
local selectedSet      = {}   -- set for quick check (optional)

-- ===== Utils =====
local function normName(s) s=string.lower(s or ""); return (s:gsub("%W","")) end

local function waitChild(p, n, t)
    local dl = os.clock()
    local c = p:FindFirstChild(n)
    while not c and os.clock()-dl < (t or 5) do
        p.ChildAdded:Wait()
        c = p:FindFirstChild(n)
    end
    return c
end

local function ensureCharacter()
    local ch = LocalPlayer.Character or LocalPlayer.CharacterAdded:Wait()
    local hrp = ch:FindFirstChild("HumanoidRootPart") or waitChild(ch, "HumanoidRootPart", 5)
    local hum = ch:FindFirstChildOfClass("Humanoid")
    return ch, hrp, hum
end

local function setCFrameSafely(hrp, pos, lookAt)
    local look = lookAt or (hrp.CFrame.LookVector + hrp.Position)
    hrp.AssemblyLinearVelocity  = Vector3.new()
    hrp.AssemblyAngularVelocity = Vector3.new()
    hrp.CFrame = CFrame.lookAt(pos, Vector3.new(look.X, pos.Y, look.Z))
end

local function savePosOnce()
    if savedPosition then return end
    local _, hrp = ensureCharacter()
    if hrp then savedPosition = hrp.CFrame end
end

local function restorePos()
    if not savedPosition then return end
    local _, hrp = ensureCharacter()
    if hrp then setCFrameSafely(hrp, savedPosition.Position, savedPosition.Position + hrp.CFrame.LookVector) end
end

local function modelPivot(model)
    local ok, cf = pcall(model.GetPivot, model)
    if ok and typeof(cf)=="CFrame" then return cf.Position end
    local ok2, cf2 = pcall(function() return model.WorldPivot end)
    if ok2 and typeof(cf2)=="CFrame" then return cf2.Position end
    return nil
end

-- ===== Index Events from ReplicatedStorage.Events =====
local function indexEvents()
    table.clear(validEventNames)
    if not eventsContainer then return end
    local function scan(node)
        for _, child in ipairs(node:GetChildren()) do
            if child:IsA("ModuleScript") then
                local ok, data = pcall(require, child)
                if ok and type(data)=="table" and data.Name then
                    validEventNames[normName(data.Name)] = true
                end
                validEventNames[normName(child.Name)] = true
            elseif child:IsA("Folder") then
                scan(child)
            end
        end
    end
    scan(eventsContainer)
end

-- ===== Optional: listen text notifications to help disambiguate "Model" =====
local notified = {} -- [normName] = {name,t}
local function setupNotificationListener()
    if notificationConn then notificationConn:Disconnect(); notificationConn=nil end
    local re
    local idx = ReplicatedStorage:FindFirstChild("Packages") and ReplicatedStorage.Packages:FindFirstChild("_Index")
    if idx then
        for _, p in ipairs(idx:GetChildren()) do
            if p.Name:find("sleitnick_net") then
                local net = p:FindFirstChild("net")
                if net then re = net:FindFirstChild("RE/TextNotification") end
            end
        end
    end
    if not re then return end
    notificationConn = re.OnClientEvent:Connect(function(data)
        if typeof(data)=="table" and data.Type=="Event" and data.Text then
            local key = normName(data.Text)
            notified[key] = {name=data.Text, t=os.clock()}
        end
    end)
end

-- ===== Identify Event Model (DIRECT child of Props only) =====
local function isEventModel(m)
    if not (m and m:IsA("Model")) then return false end
    local raw = m.Name
    local key = normName(raw)
    if validEventNames[key] then return true, raw, key end

    for k,inf in pairs(notified) do
        if key==k or key:find(k,1,true) or k:find(key,1,true) then
            return true, inf.name or raw, key
        end
        if raw=="Model" and os.clock()-(inf.t or 0)<30 then
            return true, inf.name or raw, key
        end
    end

    local pats={"hunt","boss","raid","event","invasion","attack","storm","hole","meteor","comet","shark","worm","admin","ghost","megalodon"}
    for _,p in ipairs(pats) do if key:find(p,1,true) then return true, raw, key end end
    return false
end

-- ===== Bind/Unbind Props folders =====
local function unbindAllProps()
    for props,conns in pairs(propsConns) do
        if conns.added then conns.added:Disconnect() end
        if conns.removed then conns.removed:Disconnect() end
        propsConns[props] = nil
    end
end

local function bindPropsFolder(props)
    if not (props and props:IsA("Folder") and props.Name=="Props") then return end
    if propsConns[props] then return end
    local added = props.ChildAdded:Connect(function(c)
        if c:IsA("Model") then
            lastKnownModels[c] = true
        end
    end)
    local removed = props.ChildRemoved:Connect(function(c)
        if c:IsA("Model") then
            lastKnownModels[c] = nil
            if currentTarget and currentTarget.model==c then currentTarget=nil end
        end
    end)
    propsConns[props] = {added=added, removed=removed}
end

local function setupWorkspaceMonitoring()
    if workspaceConn then workspaceConn:Disconnect(); workspaceConn=nil end
    if menuAddConn   then menuAddConn:Disconnect();   menuAddConn=nil end
    if menuRemConn   then menuRemConn:Disconnect();   menuRemConn=nil end

    unbindAllProps()

    local menu = Workspace:FindFirstChild("!!! MENU RINGS")
    if menu then
        for _,child in ipairs(menu:GetChildren()) do
            if child:IsA("Folder") and child.Name=="Props" then bindPropsFolder(child) end
        end
        menuAddConn = menu.ChildAdded:Connect(function(sub)
            if sub:IsA("Folder") and sub.Name=="Props" then bindPropsFolder(sub) end
        end)
        menuRemConn = menu.ChildRemoved:Connect(function(sub)
            if sub:IsA("Folder") and sub.Name=="Props" then
                local c = propsConns[sub]
                if c then
                    if c.added then c.added:Disconnect() end
                    if c.removed then c.removed:Disconnect() end
                end
                propsConns[sub]=nil
            end
        end)
    end

    workspaceConn = Workspace.ChildAdded:Connect(function(c)
        if c.Name=="!!! MENU RINGS" then
            task.defer(function()
                for _,sub in ipairs(c:GetChildren()) do
                    if sub:IsA("Folder") and sub.Name=="Props" then bindPropsFolder(sub) end
                end
                c.ChildAdded:Connect(function(sub)
                    if sub:IsA("Folder") and sub.Name=="Props" then bindPropsFolder(sub) end
                end)
                c.ChildRemoved:Connect(function(sub)
                    if sub:IsA("Folder") and sub.Name=="Props" then
                        local cc = propsConns[sub]
                        if cc then
                            if cc.added then cc.added:Disconnect() end
                            if cc.removed then cc.removed:Disconnect() end
                        end
                        propsConns[sub]=nil
                    end
                end)
            end)
        end
    end)
end

-- ===== Scan ACTIVE events (DIRECT children of ANY Props) =====
local function scanActiveEvents()
    local t = {}
    local menu = Workspace:FindFirstChild("!!! MENU RINGS")
    if not menu then return t end

    for _, folder in ipairs(menu:GetChildren()) do
        if folder:IsA("Folder") and folder.Name=="Props" then
            bindPropsFolder(folder)
            for _, c in ipairs(folder:GetChildren()) do
                if c:IsA("Model") then
                    local ok, disp, key = isEventModel(c)
                    if ok then
                        local pos = modelPivot(c)
                        if pos then
                            table.insert(t, {
                                model=c, name=disp, nameKey=normName(disp),
                                pos=pos, propsRef=folder
                            })
                            lastKnownModels[c] = true
                        end
                    end
                end
            end
        end
    end

    for inst in pairs(lastKnownModels) do
        if not inst.Parent then lastKnownModels[inst] = nil end
    end
    return t
end

-- ===== Ranking & choice =====
local function rankOf(nameKey, displayName)
    if #selectedPriority==0 then return math.huge end
    local dispKey = normName(displayName)
    for i,sel in ipairs(selectedPriority) do
        if nameKey:find(sel,1,true) or sel:find(nameKey,1,true) then return i end
        if dispKey:find(sel,1,true) or sel:find(dispKey,1,true) then return i end
    end
    return math.huge
end

local function chooseBestTarget()
    local actives = scanActiveEvents()
    if #actives==0 then return nil end

    local pri = {}
    if #selectedPriority>0 then
        for _,a in ipairs(actives) do
            a.rank = rankOf(a.nameKey, a.name)
            if a.rank ~= math.huge then table.insert(pri, a) end
        end
    end

    if #pri>0 then
        table.sort(pri, function(a,b)
            if a.rank~=b.rank then return a.rank<b.rank end
            return a.name<b.name
        end)
        return pri[1]
    end

    for _,a in ipairs(actives) do a.rank = math.huge end
    table.sort(actives, function(a,b) return a.name<b.name end)
    return actives[1]
end

-- ===== TP & Hover =====
local function teleportTo(target)
    local _, hrp = ensureCharacter()
    if not hrp then return false end
    savePosOnce()
    local tp = target.pos + Vector3.new(0, hoverHeight, 0)
    setCFrameSafely(hrp, tp)
    return true
end

local function maintainHover()
    if not currentTarget then return end
    local _, hrp = ensureCharacter(); if not hrp then return end
    if not currentTarget.model or not currentTarget.model.Parent then currentTarget=nil; return end
    local p = modelPivot(currentTarget.model); if p then currentTarget.pos = p end
    local desired = currentTarget.pos + Vector3.new(0, hoverHeight, 0)
    if (hrp.Position - desired).Magnitude > 1.25 then setCFrameSafely(hrp, desired) end
end

-- ===== Loop =====
local function startLoop()
    if hbConn then hbConn:Disconnect(); hbConn=nil end
    local last = 0
    hbConn = RunService.Heartbeat:Connect(function()
        if not running then return end
        maintainHover()

        local now = os.clock()
        if now-last < 0.30 then return end
        last = now

        local best = chooseBestTarget()
        if not best then
            if currentTarget then currentTarget=nil end
            restorePos()
            return
        end

        local switch =
            (not currentTarget) or
            (currentTarget.model ~= best.model) or
            ((currentTarget.rank or math.huge) > (best.rank or math.huge))

        if switch then
            teleportTo(best)
            currentTarget = best
        end
    end)
end

-- ===== Public API =====
function AutoTeleportEvent:Init()
    eventsContainer = ReplicatedStorage:FindFirstChild("Events") or waitChild(ReplicatedStorage, "Events", 5)
    indexEvents()
    setupNotificationListener()
    setupWorkspaceMonitoring()

    if charConn then charConn:Disconnect() end
    charConn = LocalPlayer.CharacterAdded:Connect(function()
        savedPosition = nil
        if running and currentTarget then
            task.defer(function()
                task.wait(0.5)
                if currentTarget then teleportTo(currentTarget) end
            end)
        end
    end)
    return true
end

function AutoTeleportEvent:Start(cfg)
    if running then return true end
    running = true

    if cfg then
        if type(cfg.hoverHeight)=="number" then hoverHeight = math.clamp(cfg.hoverHeight, 5, 100) end
        if cfg.selectedEvents~=nil then self:SetSelectedEvents(cfg.selectedEvents) end
    end

    currentTarget=nil; savedPosition=nil; table.clear(lastKnownModels)

    local first = chooseBestTarget()
    if first then teleportTo(first); currentTarget=first end

    startLoop()
    return true
end

function AutoTeleportEvent:Stop()
    if not running then return true end
    running = false
    if hbConn then hbConn:Disconnect(); hbConn=nil end
    restorePos()
    currentTarget=nil
    table.clear(lastKnownModels)
    return true
end

function AutoTeleportEvent:Cleanup()
    self:Stop()
    if charConn      then charConn:Disconnect();      charConn=nil end
    if workspaceConn then workspaceConn:Disconnect(); workspaceConn=nil end
    if menuAddConn   then menuAddConn:Disconnect();   menuAddConn=nil end
    if menuRemConn   then menuRemConn:Disconnect();   menuRemConn=nil end
    if notificationConn then notificationConn:Disconnect(); notificationConn=nil end
    unbindAllProps()
    eventsContainer=nil
    table.clear(validEventNames)
    table.clear(selectedPriority)
    table.clear(selectedSet)
    table.clear(lastKnownModels)
    table.clear(notified)
    savedPosition=nil
    currentTarget=nil
    return true
end

-- ===== Setters & Status =====
function AutoTeleportEvent:SetSelectedEvents(selected)
    table.clear(selectedPriority); table.clear(selectedSet)
    if type(selected)=="table" then
        if #selected>0 then
            for _,v in ipairs(selected) do
                local k = normName(v); table.insert(selectedPriority, k); selectedSet[k]=true
            end
        else
            for k,on in pairs(selected) do if on then selectedSet[normName(k)]=true end end
        end
    end
    return true
end

function AutoTeleportEvent:SetHoverHeight(n)
    if type(n)=="number" then
        hoverHeight = math.clamp(n,5,100)
        if running and currentTarget then
            local _,hrp=ensureCharacter()
            if hrp then setCFrameSafely(hrp, currentTarget.pos + Vector3.new(0, hoverHeight, 0)) end
        end
        return true
    end
    return false
end

function AutoTeleportEvent:Status()
    return {
        running=running, hover=hoverHeight, hasSavedPos=savedPosition~=nil,
        target=currentTarget and currentTarget.name or nil, priority=selectedPriority
    }
end

function AutoTeleportEvent.new()
    return setmetatable({}, AutoTeleportEvent)
end

return AutoTeleportEvent