-- ===========================
-- AUTO FISH V7 - FULL BYPASS
-- ===========================

local AutoFishFeature = {}
AutoFishFeature.__index = AutoFishFeature

local logger = _G.Logger and _G.Logger.new("AutoFish") or {
    debug = function() end, info = function() end,
    warn = function() end, error = function() end
}

-- Services
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")  
local RunService = game:GetService("RunService")
local LocalPlayer = Players.LocalPlayer

-- Network
local NetPath
local EquipTool, ChargeFishingRod, RequestFishing, FishingCompleted
local BaitSpawned, FishingMinigameChanged, FishObtainedNotification

-- Hooks
local hookInstalled = false
local originalMinigameData = {}

local function initializeRemotes()
    return pcall(function()
        NetPath = ReplicatedStorage:WaitForChild("Packages", 5)
            :WaitForChild("_Index", 5)
            :WaitForChild("sleitnick_net@0.2.0", 5)
            :WaitForChild("net", 5)
        
        EquipTool = NetPath:WaitForChild("RE/EquipToolFromHotbar", 5)
        ChargeFishingRod = NetPath:WaitForChild("RF/ChargeFishingRod", 5)
        RequestFishing = NetPath:WaitForChild("RF/RequestFishingMinigameStarted", 5)
        FishingCompleted = NetPath:WaitForChild("RE/FishingCompleted", 5)
        
        BaitSpawned = NetPath:FindFirstChild("RE/BaitSpawned")
        FishingMinigameChanged = NetPath:FindFirstChild("RE/FishingMinigameChanged")
        FishObtainedNotification = NetPath:WaitForChild("RE/ObtainedNewFishNotification", 5)
    end)
end

-- State
local isRunning = false
local currentMode = "Instant"
local connections = {}
local fishingState = {
    inProgress = false,
    minigameActive = false,
    baitSpawned = false,
    spamActive = false,
    lastFishTime = 0,
    fishCaught = false,
    currentUUID = nil
}

-- Config
local CONFIGS = {
    Instant = {
        rodSlot = 1,
        chargeTime = 1.0,
        waitBetween = 0.05,
        spamDelay = 0.015,
        spamAfterMinigame = 0,
        maxSpamTime = 15,
        useBypass = true,
        bypassStats = {
            FishingResilience = 0.01,
            FishStrength = 1,
            FishingClickPower = 1
        }
    },
    Fast = {
        rodSlot = 1,
        chargeTime = 1.0,
        waitBetween = 0.1,
        spamDelay = 0.03,
        spamAfterMinigame = 0.05,
        maxSpamTime = 15,
        useBypass = true,
        bypassStats = {
            FishingResilience = 0.5,
            FishStrength = 2,
            FishingClickPower = 0.8
        }
    },
    Legit = {
        rodSlot = 1,
        chargeTime = 1.0,
        waitBetween = 0.5,
        spamDelay = 0.1,
        spamAfterMinigame = 1.5,
        maxSpamTime = 20,
        useBypass = false,
        bypassStats = {}
    }
}

-- Init
function AutoFishFeature:Init()
    if not initializeRemotes() then
        logger:warn("Failed init remotes")
        return false
    end
    
    self:InstallHooks()
    self:SetupListeners()
    logger:info("Init complete - Full bypass ready")
    return true
end

-- Install hooks untuk bypass
function AutoFishFeature:InstallHooks()
    if hookInstalled then return end
    
    -- Hook FishingMinigameChanged untuk manipulate data
    if FishingMinigameChanged then
        local oldEvent = FishingMinigameChanged.OnClientEvent
        local newEvent = Instance.new("BindableEvent")
        
        -- Store original
        for i, connection in pairs(getconnections(oldEvent)) do
            if connection.Function then
                table.insert(originalMinigameData, connection.Function)
            end
        end
        
        -- Override
        FishingMinigameChanged.OnClientEvent = newEvent.Event
        
        oldEvent:Connect(function(action, data)
            if isRunning and data and CONFIGS[currentMode].useBypass then
                -- BYPASS: Manipulate minigame stats
                local bypass = CONFIGS[currentMode].bypassStats
                for key, value in pairs(bypass) do
                    data[key] = value
                end
                
                logger:info("Bypassed minigame stats:", action)
            end
            
            -- Fire to original handlers
            newEvent:Fire(action, data)
        end)
        
        hookInstalled = true
        logger:info("Hooks installed successfully")
    end
end

-- Setup listeners
function AutoFishFeature:SetupListeners()
    -- Listen FishingMinigameChanged
    if FishingMinigameChanged then
        connections.minigameChanged = FishingMinigameChanged.OnClientEvent:Connect(function(action, data)
            if not isRunning then return end
            
            if action == "Activated" or action == "Clicked" then
                fishingState.minigameActive = true
                fishingState.currentUUID = data and data.UUID
                
                logger:info("Minigame:", action)
                
                -- Start spam after delay
                local config = CONFIGS[currentMode]
                task.wait(config.spamAfterMinigame)
                
                if not fishingState.spamActive and not fishingState.fishCaught then
                    self:StartSpam()
                end
            end
        end)
    end
    
    -- Listen BaitSpawned (fallback trigger)
    if BaitSpawned then
        connections.baitSpawned = BaitSpawned.OnClientEvent:Connect(function()
            if not isRunning then return end
            fishingState.baitSpawned = true
            logger:info("Bait spawned")
            
            -- Fallback: start spam kalo belum mulai
            if not fishingState.spamActive and not fishingState.fishCaught then
                local config = CONFIGS[currentMode]
                task.wait(config.spamAfterMinigame)
                self:StartSpam()
            end
        end)
    end
    
    -- Listen FishObtained
    if FishObtainedNotification then
        connections.fishObtained = FishObtainedNotification.OnClientEvent:Connect(function(fishData)
            if not isRunning then return end
            
            local fishName = fishData and fishData.Name or "Unknown"
            logger:info("Fish caught:", fishName)
            
            fishingState.fishCaught = true
            fishingState.spamActive = false
            
            -- Reset untuk cycle baru
            task.wait(0.08)
            self:ResetState()
        end)
    end
    
    logger:info("Listeners ready")
end

-- Start
function AutoFishFeature:Start(config)
    if isRunning then return end
    if not NetPath then
        logger:warn("Remotes not ready")
        return
    end
    
    isRunning = true
    currentMode = config.mode or "Instant"
    self:ResetState()
    
    local cfg = CONFIGS[currentMode]
    logger:info("Started:", currentMode)
    logger:info("  Bypass:", cfg.useBypass and "ON" or "OFF")
    logger:info("  Spam delay:", cfg.spamDelay * 1000, "ms")
    
    connections.mainLoop = RunService.Heartbeat:Connect(function()
        if not isRunning then return end
        self:MainLoop()
    end)
end

-- Stop
function AutoFishFeature:Stop()
    if not isRunning then return end
    
    isRunning = false
    
    for _, conn in pairs(connections) do
        if conn then conn:Disconnect() end
    end
    connections = {}
    
    self:ResetState()
    logger:info("Stopped")
end

-- Reset state
function AutoFishFeature:ResetState()
    fishingState.inProgress = false
    fishingState.minigameActive = false
    fishingState.baitSpawned = false
    fishingState.spamActive = false
    fishingState.fishCaught = false
    fishingState.currentUUID = nil
end

-- Main loop
function AutoFishFeature:MainLoop()
    if fishingState.inProgress then return end
    
    local config = CONFIGS[currentMode]
    local now = tick()
    
    if now - fishingState.lastFishTime < config.waitBetween then
        return
    end
    
    fishingState.inProgress = true
    fishingState.lastFishTime = now
    
    task.spawn(function()
        self:ExecuteFishingCycle()
    end)
end

-- Execute fishing cycle
function AutoFishFeature:ExecuteFishingCycle()
    local config = CONFIGS[currentMode]
    
    -- 1. Equip
    local equipped = self:EquipRod(config.rodSlot)
    if not equipped then
        logger:warn("Failed to equip rod")
        fishingState.inProgress = false
        return
    end
    task.wait(0.1)
    
    -- 2. Charge
    local charged = self:ChargeRod(config.chargeTime)
    if not charged then
        logger:warn("Failed to charge rod")
        fishingState.inProgress = false
        return
    end
    
    -- 3. Cast
    local casted = self:CastRod()
    if not casted then
        logger:warn("Failed to cast rod")
        fishingState.inProgress = false
        return
    end
    
    logger:info("Cast successful - waiting for events...")
end

-- Equip rod
function AutoFishFeature:EquipRod(slot)
    if not EquipTool then return false end
    
    local success, err = pcall(function()
        EquipTool:FireServer(slot)
    end)
    
    if not success then
        logger:warn("Equip error:", err)
    end
    
    return success
end

-- Charge rod
function AutoFishFeature:ChargeRod(chargeTime)
    if not ChargeFishingRod then return false end
    
    local success, result = pcall(function()
        local val = tick() + (chargeTime * 1000)
        return ChargeFishingRod:InvokeServer(val)
    end)
    
    if not success then
        logger:warn("Charge error:", result)
    end
    
    return success
end

-- Cast rod
function AutoFishFeature:CastRod()
    if not RequestFishing then return false end
    
    local success, result = pcall(function()
        return RequestFishing:InvokeServer(-1.233184814453125, 0.9999120558411321)
    end)
    
    if not success then
        logger:warn("Cast error:", result)
        return false
    end
    
    return success
end

-- Start spam (CORE BYPASS)
function AutoFishFeature:StartSpam()
    if fishingState.spamActive then return end
    if fishingState.fishCaught then return end
    
    fishingState.spamActive = true
    local config = CONFIGS[currentMode]
    local startTime = tick()
    
    logger:info("Spam started")
    
    task.spawn(function()
        local spamCount = 0
        local lastLog = startTime
        
        while fishingState.spamActive and isRunning do
            -- Timeout
            if tick() - startTime > config.maxSpamTime then
                logger:warn("Spam timeout")
                break
            end
            
            -- Fish caught
            if fishingState.fishCaught then
                break
            end
            
            -- Fire completion
            local fired = self:FireCompletion()
            if fired then
                spamCount = spamCount + 1
            end
            
            -- Log every second
            if tick() - lastLog > 1 then
                logger:debug("Spamming...", spamCount, "requests sent")
                lastLog = tick()
            end
            
            task.wait(config.spamDelay)
        end
        
        logger:info("Spam stopped -", spamCount, "total requests")
        fishingState.spamActive = false
    end)
end

-- Fire completion
function AutoFishFeature:FireCompletion()
    if not FishingCompleted then return false end
    
    local success = pcall(function()
        FishingCompleted:FireServer()
    end)
    
    return success
end

-- Set mode
function AutoFishFeature:SetMode(mode)
    if not CONFIGS[mode] then
        logger:warn("Invalid mode:", mode)
        return false
    end
    
    local wasRunning = isRunning
    if wasRunning then
        self:Stop()
    end
    
    currentMode = mode
    local cfg = CONFIGS[mode]
    
    logger:info("Mode changed:", mode)
    logger:info("  Bypass:", cfg.useBypass and "ON" or "OFF")
    logger:info("  Spam delay:", cfg.spamDelay * 1000, "ms")
    logger:info("  Wait between:", cfg.waitBetween, "s")
    
    if wasRunning then
        task.wait(0.1)
        self:Start({mode = mode})
    end
    
    return true
end

-- Get status
function AutoFishFeature:GetStatus()
    return {
        running = isRunning,
        mode = currentMode,
        config = CONFIGS[currentMode],
        state = fishingState,
        hooks = {
            installed = hookInstalled
        },
        listeners = {
            minigameChanged = connections.minigameChanged ~= nil,
            baitSpawned = connections.baitSpawned ~= nil,
            fishObtained = connections.fishObtained ~= nil,
            mainLoop = connections.mainLoop ~= nil
        }
    }
end

-- Debug info
function AutoFishFeature:PrintStatus()
    local status = self:GetStatus()
    print("=== AUTO FISH STATUS ===")
    print("Running:", status.running)
    print("Mode:", status.mode)
    print("Bypass:", status.config.useBypass and "ON" or "OFF")
    print("State:")
    for k, v in pairs(status.state) do
        print("  ", k, "=", v)
    end
    print("Listeners:")
    for k, v in pairs(status.listeners) do
        print("  ", k, "=", v)
    end
    print("=======================")
end

-- Cleanup
function AutoFishFeature:Cleanup()
    logger:info("Cleaning up...")
    self:Stop()
    
    -- Clear hooks
    hookInstalled = false
    originalMinigameData = {}
    
    logger:info("Cleanup complete")
end

-- Export
_G.AutoFish = AutoFishFeature

return AutoFishFeature