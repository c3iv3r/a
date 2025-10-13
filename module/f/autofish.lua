-- ===========================
-- AUTO FISH V6 - BYPASS OPTIMIZED
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
        
        -- Event listeners
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
    fishCaught = false
}

-- Config
local CONFIGS = {
    Instant = {
        rodSlot = 1,
        chargeTime = 1.0,
        waitBetween = 0.05,
        spamDelay = 0.02,        -- 20ms spam interval
        spamAfterBait = 0,       -- Instant spam setelah bait
        maxSpamTime = 15,
        aggressiveSpam = true    -- Spam bahkan sebelum bait
    },
    Fast = {
        rodSlot = 1,
        chargeTime = 1.0,
        waitBetween = 0.1,
        spamDelay = 0.05,
        spamAfterBait = 0.1,     -- 100ms delay
        maxSpamTime = 15,
        aggressiveSpam = false
    },
    Legit = {
        rodSlot = 1,
        chargeTime = 1.0,
        waitBetween = 0.5,
        spamDelay = 0.1,
        spamAfterBait = 2,       -- 2s delay (bypass detection)
        maxSpamTime = 20,
        aggressiveSpam = false
    }
}

-- Init
function AutoFishFeature:Init()
    if not initializeRemotes() then
        logger:warn("Failed init remotes")
        return false
    end
    
    self:SetupListeners()
    logger:info("Init complete - Bypass optimized")
    return true
end

-- Setup listeners
function AutoFishFeature:SetupListeners()
    -- Listen FishingMinigameChanged (ini yang set UUID session)
    if FishingMinigameChanged then
        connections.minigameChanged = FishingMinigameChanged.OnClientEvent:Connect(function(action, data)
            if not isRunning then return end
            
            if action == "Activated" then
                fishingState.minigameActive = true
                logger:info("Minigame activated - UUID:", data.UUID)
                
                -- Mode Instant: Mulai spam SEBELUM bait (aggressive)
                local config = CONFIGS[currentMode]
                if config.aggressiveSpam then
                    logger:info("Aggressive spam enabled - starting NOW")
                    task.wait(0.05)
                    if not fishingState.spamActive then
                        self:StartSpam()
                    end
                end
            end
        end)
    end
    
    -- Listen BaitSpawned
    if BaitSpawned then
        connections.baitSpawned = BaitSpawned.OnClientEvent:Connect(function()
            if not isRunning then return end
            fishingState.baitSpawned = true
            logger:info("Bait spawned!")
            
            -- Start spam setelah delay (kalo belum spam)
            if not fishingState.spamActive then
                local config = CONFIGS[currentMode]
                task.wait(config.spamAfterBait)
                
                if fishingState.baitSpawned and not fishingState.fishCaught then
                    self:StartSpam()
                end
            end
        end)
    end
    
    -- Listen FishObtained
    if FishObtainedNotification then
        connections.fishObtained = FishObtainedNotification.OnClientEvent:Connect(function()
            if not isRunning then return end
            logger:info("Fish caught!")
            
            fishingState.fishCaught = true
            fishingState.spamActive = false
            
            -- Reset untuk cycle baru
            task.wait(0.1)
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
    
    logger:info("Started -", currentMode, "mode")
    
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
    if not self:EquipRod(config.rodSlot) then
        fishingState.inProgress = false
        return
    end
    task.wait(0.1)
    
    -- 2. Charge
    if not self:ChargeRod(config.chargeTime) then
        fishingState.inProgress = false
        return
    end
    
    -- 3. Cast
    if not self:CastRod() then
        fishingState.inProgress = false
        return
    end
    
    -- Listener akan handle spam (FishingMinigameChanged atau BaitSpawned)
end

-- Equip rod
function AutoFishFeature:EquipRod(slot)
    if not EquipTool then return false end
    return pcall(function()
        EquipTool:FireServer(slot)
    end)
end

-- Charge rod
function AutoFishFeature:ChargeRod(chargeTime)
    if not ChargeFishingRod then return false end
    return pcall(function()
        local val = tick() + (chargeTime * 1000)
        ChargeFishingRod:InvokeServer(val)
    end)
end

-- Cast rod
function AutoFishFeature:CastRod()
    if not RequestFishing then return false end
    return pcall(function()
        RequestFishing:InvokeServer(-1.233184814453125, 0.9999120558411321)
    end)
end

-- Start spam (CORE BYPASS)
function AutoFishFeature:StartSpam()
    if fishingState.spamActive then return end
    
    fishingState.spamActive = true
    local config = CONFIGS[currentMode]
    local startTime = tick()
    
    logger:info("Spam started -", currentMode, "mode")
    
    task.spawn(function()
        local spamCount = 0
        
        while fishingState.spamActive and isRunning do
            -- Timeout check
            if tick() - startTime > config.maxSpamTime then
                logger:info("Spam timeout")
                break
            end
            
            -- Fish caught check
            if fishingState.fishCaught then
                logger:info("Fish caught - stopping spam")
                break
            end
            
            -- Fire completion
            self:FireCompletion()
            spamCount = spamCount + 1
            
            task.wait(config.spamDelay)
        end
        
        logger:info("Spam stopped - fired", spamCount, "times")
        fishingState.spamActive = false
    end)
end

-- Fire completion
function AutoFishFeature:FireCompletion()
    if not FishingCompleted then return false end
    return pcall(function()
        FishingCompleted:FireServer()
    end)
end

-- Set mode
function AutoFishFeature:SetMode(mode)
    if CONFIGS[mode] then
        currentMode = mode
        logger:info("Mode changed:", mode)
        
        local config = CONFIGS[mode]
        if config.aggressiveSpam then
            logger:info("  - Aggressive spam: ON (spam before bait)")
        else
            logger:info("  - Spam delay:", config.spamAfterBait, "s after bait")
        end
        
        return true
    end
    return false
end

-- Get status
function AutoFishFeature:GetStatus()
    return {
        running = isRunning,
        mode = currentMode,
        state = fishingState,
        listeners = {
            minigameChanged = connections.minigameChanged ~= nil,
            baitSpawned = connections.baitSpawned ~= nil,
            fishObtained = connections.fishObtained ~= nil
        }
    }
end

-- Cleanup
function AutoFishFeature:Cleanup()
    self:Stop()
end

return AutoFishFeature