-- ===========================
-- AUTO FISH V5 - ULTRA BYPASS EDITION
-- No Animation + Instant Bite Detection + Aggressive Spam
-- ===========================

local AutoFishFeature = {}
AutoFishFeature.__index = AutoFishFeature

-- Logger setup
local logger = _G.Logger and _G.Logger.new("AutoFish") or {
    debug = function(self, ...) print("[AutoFish DEBUG]", ...) end,
    info = function(self, ...) print("[AutoFish INFO]", ...) end,
    warn = function(self, ...) warn("[AutoFish WARN]", ...) end,
    error = function(self, ...) warn("[AutoFish ERROR]", ...) end
}

-- Services
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")  
local RunService = game:GetService("RunService")
local LocalPlayer = Players.LocalPlayer

-- Network remotes
local NetPath = nil
local EquipTool, ChargeFishingRod, RequestFishing, FishingCompleted
local FishObtainedNotification, FishingMinigameChanged

-- State management
local isRunning = false
local currentMode = "Ultra"
local connection = nil
local minigameConnection = nil
local fishObtainedConnection = nil
local fishingInProgress = false
local spamActive = false
local fishCaughtFlag = false
local lastFishTime = 0
local lastBackpackCount = 0
local remotesInitialized = false
local patchesApplied = false

-- Configuration
local FISHING_CONFIGS = {
    ["Ultra"] = {
        chargeTime = 0.5,           -- Minimal charge
        waitBetween = 0.1,          -- Fast cycle restart
        rodSlot = 1,
        spamDelay = 0.005,          -- 5ms spam interval
        burstCount = 10,            // Spam 10x per burst
        maxSpamTime = 25,
        preemptiveSpam = true,      -- Start spam before minigame
        instantComplete = true      -- Hook minigame for instant complete
    },
    ["Fast"] = {
        chargeTime = 0.8,
        waitBetween = 0.2,
        rodSlot = 1,
        spamDelay = 0.01,
        burstCount = 5,
        maxSpamTime = 20,
        preemptiveSpam = true,
        instantComplete = true
    },
    ["Safe"] = {
        chargeTime = 1.0,
        waitBetween = 0.5,
        rodSlot = 1,
        spamDelay = 0.05,
        burstCount = 3,
        maxSpamTime = 20,
        preemptiveSpam = false,
        instantComplete = false
    }
}

-- ===========================
-- NETWORK INITIALIZATION
-- ===========================

local function initializeRemotes()
    local success, err = pcall(function()
        NetPath = ReplicatedStorage:WaitForChild("Packages", 5)
            :WaitForChild("_Index", 5)
            :WaitForChild("sleitnick_net@0.2.0", 5)
            :WaitForChild("net", 5)
        
        -- Essential remotes
        EquipTool = NetPath:WaitForChild("RE/EquipToolFromHotbar", 5)
        ChargeFishingRod = NetPath:WaitForChild("RF/ChargeFishingRod", 5)
        RequestFishing = NetPath:WaitForChild("RF/RequestFishingMinigameStarted", 5)
        FishingCompleted = NetPath:WaitForChild("RE/FishingCompleted", 5)
        
        -- Event listeners
        FishObtainedNotification = NetPath:FindFirstChild("RE/ObtainedNewFishNotification")
        FishingMinigameChanged = NetPath:FindFirstChild("RE/FishingMinigameChanged")
        
        logger:info("All remotes initialized successfully")
        return true
    end)
    
    if not success then
        logger:error("Failed to initialize remotes:", err)
    end
    
    return success
end

-- ===========================
-- BYPASS PATCHES
-- ===========================

-- Patch 1: Disable ALL fishing animations
local function PatchAnimations()
    local success = pcall(function()
        local AnimationController = require(ReplicatedStorage.Controllers.AnimationController)
        
        -- Store original functions
        local originalPlay = AnimationController.PlayAnimation
        local originalStop = AnimationController.StopAnimation
        local originalDestroy = AnimationController.DestroyActiveAnimationTracks
        
        -- Override PlayAnimation
        AnimationController.PlayAnimation = function(self, animName, ...)
            local fishingAnims = {
                "StartRodCharge", "LoopedRodCharge", "RodThrow",
                "EasyFishReelStart", "EasyFishReel", "FishCaught",
                "FishingFailure", "ReelingIdle"
            }
            
            -- Skip fishing animations entirely
            for _, fishAnim in pairs(fishingAnims) do
                if string.find(animName, fishAnim) then
                    logger:debug("Blocked animation:", animName)
                    -- Return fake animation track
                    return nil, {
                        Wait = function() return true end,
                        Stop = function() end,
                        IsPlaying = function() return false end
                    }
                end
            end
            
            return originalPlay(self, animName, ...)
        end
        
        -- Override StopAnimation (prevent errors)
        AnimationController.StopAnimation = function(self, animName, ...)
            pcall(function()
                originalStop(self, animName, ...)
            end)
        end
        
        -- Override DestroyActiveAnimationTracks
        AnimationController.DestroyActiveAnimationTracks = function(self, ...)
            pcall(function()
                originalDestroy(self, ...)
            end)
        end
        
        logger:info("✓ Animation patches applied")
    end)
    
    if not success then
        logger:warn("Animation patch failed (non-critical)")
    end
    
    return success
end

-- Patch 2: Remove bobber animation delays
local function PatchBobberDelays()
    local success = pcall(function()
        local ItemUtility = require(ReplicatedStorage.Shared.ItemUtility)
        local originalGetItemData = ItemUtility.GetItemData
        
        ItemUtility.GetItemData = function(...)
            local result = originalGetItemData(...)
            
            if result and type(result) == "table" then
                -- Zero out all delays
                if result.BobberAnimationDelay then
                    result.BobberAnimationDelay = 0
                end
                if result.catchAnimationDelay then
                    result.catchAnimationDelay = 0
                end
                -- Boost rod stats for faster completion
                if result.ClickPower then
                    result.ClickPower = math.max(result.ClickPower, 0.5)
                end
                if result.Resilience then
                    result.Resilience = math.max(result.Resilience, 10)
                end
            end
            
            return result
        end
        
        logger:info("✓ Bobber delay patches applied")
    end)
    
    if not success then
        logger:warn("Bobber patch failed (non-critical)")
    end
    
    return success
end

-- Patch 3: Optimize rod stats (client-side display only)
local function PatchRodStats()
    local success = pcall(function()
        local rodsFolder = ReplicatedStorage:FindFirstChild("Data")
        if rodsFolder then
            rodsFolder = rodsFolder:FindFirstChild("FishingRods")
        end
        
        if not rodsFolder then
            logger:warn("Rods folder not found")
            return
        end
        
        for _, rodModule in pairs(rodsFolder:GetDescendants()) do
            if rodModule:IsA("ModuleScript") then
                pcall(function()
                    local rodData = require(rodModule)
                    if rodData and type(rodData) == "table" then
                        -- Optimize stats (client-side prediction)
                        if rodData.Windup then
                            rodData.Windup = NumberRange.new(0.1, 0.5) -- Min windup
                        end
                        if rodData.ClickPower then
                            rodData.ClickPower = 1.0 -- Max power
                        end
                        if rodData.Resilience then
                            rodData.Resilience = 15 -- Max resilience
                        end
                    end
                end)
            end
        end
        
        logger:info("✓ Rod stat patches applied")
    end)
    
    if not success then
        logger:warn("Rod stat patch failed (non-critical)")
    end
    
    return success
end

-- Patch 4: Disable charge UI animations
local function PatchChargeUI()
    local success = pcall(function()
        local PlayerGui = LocalPlayer:WaitForChild("PlayerGui", 5)
        local ChargeUI = PlayerGui:FindFirstChild("Charge")
        
        if ChargeUI then
            ChargeUI.Enabled = false -- Hide charge UI
            logger:info("✓ Charge UI disabled")
        end
        
        local FishingUI = PlayerGui:FindFirstChild("Fishing")
        if FishingUI then
            -- Speed up UI animations
            local spr = require(ReplicatedStorage.Packages.spr)
            local oldTarget = spr.target
            
            spr.target = function(instance, freq, damp, props)
                -- Instant animations for fishing UI
                if instance and instance:IsDescendantOf(FishingUI) then
                    for prop, value in pairs(props) do
                        instance[prop] = value
                    end
                    return
                end
                return oldTarget(instance, freq, damp, props)
            end
            
            logger:info("✓ Fishing UI animations bypassed")
        end
    end)
    
    return success
end

-- Patch 5: Hook module functions for instant completion
local function PatchFishingController()
    local success = pcall(function()
        local FishingController = require(ReplicatedStorage.Client.FishingController)
        
        -- Override FishingMinigameClick to auto-complete
        local originalClick = FishingController.FishingMinigameClick
        FishingController.FishingMinigameClick = function(self, ...)
            if isRunning and FISHING_CONFIGS[currentMode].instantComplete then
                -- Force instant completion
                spawn(function()
                    for i = 1, 20 do
                        pcall(function()
                            FishingCompleted:FireServer()
                        end)
                        task.wait(0.01)
                    end
                end)
            end
            return originalClick(self, ...)
        end
        
        logger:info("✓ Fishing controller patched")
    end)
    
    return success
end

-- Apply all patches
local function ApplyAllPatches()
    if patchesApplied then
        logger:warn("Patches already applied")
        return true
    end
    
    logger:info("Applying bypass patches...")
    
    local results = {
        animations = PatchAnimations(),
        bobber = PatchBobberDelays(),
        stats = PatchRodStats(),
        chargeUI = PatchChargeUI(),
        controller = PatchFishingController()
    }
    
    local successCount = 0
    for name, result in pairs(results) do
        if result then successCount = successCount + 1 end
    end
    
    logger:info(string.format("Patches applied: %d/%d successful", successCount, 5))
    patchesApplied = true
    
    return successCount >= 3 -- At least 3 patches must succeed
end

-- ===========================
-- EVENT LISTENERS
-- ===========================

-- Setup fish obtained notification listener
function AutoFishFeature:SetupFishObtainedListener()
    if not FishObtainedNotification then
        logger:warn("FishObtainedNotification remote not found")
        return false
    end
    
    if fishObtainedConnection then
        fishObtainedConnection:Disconnect()
    end
    
    fishObtainedConnection = FishObtainedNotification.OnClientEvent:Connect(function(...)
        if isRunning then
            logger:info("🐟 Fish obtained!")
            fishCaughtFlag = true
            spamActive = false
            
            -- Instant reset for next cycle
            spawn(function()
                task.wait(0.05)
                fishingInProgress = false
                fishCaughtFlag = false
            end)
        end
    end)
    
    logger:info("✓ Fish obtained listener active")
    return true
end

-- Setup minigame detection for instant completion
function AutoFishFeature:SetupMinigameHook()
    if not FishingMinigameChanged then
        logger:warn("FishingMinigameChanged remote not found")
        return false
    end
    
    if minigameConnection then
        minigameConnection:Disconnect()
    end
    
    minigameConnection = FishingMinigameChanged.OnClientEvent:Connect(function(action, data)
        if not isRunning then return end
        
        local config = FISHING_CONFIGS[currentMode]
        
        if action == "Activated" and config.instantComplete then
            logger:info("⚡ Minigame detected - INSTANT SPAM!")
            
            -- Aggressive burst spam
            spawn(function()
                local burstStart = tick()
                local spamCount = 0
                
                while isRunning and not fishCaughtFlag and (tick() - burstStart) < 3 do
                    -- Fire multiple completions per cycle
                    for burst = 1, config.burstCount * 2 do
                        pcall(function()
                            FishingCompleted:FireServer()
                            spamCount = spamCount + 1
                        end)
                    end
                    
                    if fishCaughtFlag then
                        logger:info(string.format("Completed after %d spam requests", spamCount))
                        break
                    end
                    
                    task.wait(0.002) -- 2ms between bursts
                end
            end)
        end
    end)
    
    logger:info("✓ Minigame hook active")
    return true
end

-- ===========================
-- FISHING CORE FUNCTIONS
-- ===========================

-- Equip fishing rod
function AutoFishFeature:EquipRod(slot)
    if not EquipTool then return false end
    
    local success, err = pcall(function()
        EquipTool:FireServer(slot)
    end)
    
    if not success then
        logger:warn("Failed to equip rod:", err)
    end
    
    return success
end

-- Charge fishing rod
function AutoFishFeature:ChargeRod(chargeTime)
    if not ChargeFishingRod then return false end
    
    local success, result = pcall(function()
        -- Use current server time + charge duration
        local chargeValue = workspace:GetServerTimeNow()
        return ChargeFishingRod:InvokeServer(chargeValue)
    end)
    
    if not success then
        logger:warn("Failed to charge rod:", result)
        return false
    end
    
    return result == true or result == nil -- Accept nil as success
end

-- Cast fishing rod
function AutoFishFeature:CastRod()
    if not RequestFishing then return false end
    
    local success, result = pcall(function()
        -- Cast parameters (Y position, power)
        local waterY = -1.233184814453125
        local power = 0.9999120558411321
        return RequestFishing:InvokeServer(waterY, power)
    end)
    
    if not success then
        logger:warn("Failed to cast rod:", result)
        return false
    end
    
    -- Check if cast was accepted
    if result == false then
        logger:warn("Server rejected cast")
        return false
    end
    
    return true
end

-- Fire completion remote
function AutoFishFeature:FireCompletion()
    if not FishingCompleted then return false end
    
    local success = pcall(function()
        FishingCompleted:FireServer()
    end)
    
    return success
end

-- ===========================
-- SPAM LOGIC
-- ===========================

-- Start aggressive completion spam
function AutoFishFeature:StartCompletionSpam()
    if spamActive then return end
    
    local config = FISHING_CONFIGS[currentMode]
    spamActive = true
    fishCaughtFlag = false
    
    logger:info("Starting completion spam...")
    
    spawn(function()
        local spamStart = tick()
        local totalSpam = 0
        
        -- Preemptive spam (before minigame might start)
        if config.preemptiveSpam then
            logger:debug("Preemptive spam active")
            for i = 1, config.burstCount do
                self:FireCompletion()
                totalSpam = totalSpam + 1
            end
            task.wait(0.1)
        end
        
        -- Main spam loop
        while spamActive and isRunning and (tick() - spamStart) < config.maxSpamTime do
            -- Burst spam
            for burst = 1, config.burstCount do
                if not spamActive or fishCaughtFlag then break end
                self:FireCompletion()
                totalSpam = totalSpam + 1
            end
            
            -- Check completion
            if fishCaughtFlag or self:CheckFishingCompleted() then
                logger:info(string.format("✓ Completed! (Total spam: %d)", totalSpam))
                break
            end
            
            task.wait(config.spamDelay)
        end
        
        -- Timeout check
        if (tick() - spamStart) >= config.maxSpamTime then
            logger:warn(string.format("Spam timeout after %.1fs (%d requests)", 
                config.maxSpamTime, totalSpam))
        end
        
        spamActive = false
    end)
end

-- Check if fishing completed (fallback method)
function AutoFishFeature:CheckFishingCompleted()
    -- Primary: notification flag
    if fishCaughtFlag then
        return true
    end
    
    -- Fallback: backpack count
    local currentCount = self:GetBackpackItemCount()
    if currentCount > lastBackpackCount then
        lastBackpackCount = currentCount
        logger:debug("Completion detected via backpack")
        return true
    end
    
    return false
end

-- Get backpack item count
function AutoFishFeature:GetBackpackItemCount()
    local count = 0
    
    if LocalPlayer.Backpack then
        count = count + #LocalPlayer.Backpack:GetChildren()
    end
    
    if LocalPlayer.Character then
        for _, child in pairs(LocalPlayer.Character:GetChildren()) do
            if child:IsA("Tool") then
                count = count + 1
            end
        end
    end
    
    return count
end

-- Update backpack count baseline
function AutoFishFeature:UpdateBackpackCount()
    lastBackpackCount = self:GetBackpackItemCount()
end

-- ===========================
-- FISHING SEQUENCE
-- ===========================

-- Execute complete fishing sequence
function AutoFishFeature:ExecuteFishingSequence()
    local config = FISHING_CONFIGS[currentMode]
    
    -- Step 1: Equip rod
    if not self:EquipRod(config.rodSlot) then
        logger:warn("Failed at equip step")
        return false
    end
    
    task.wait(0.05) -- Minimal delay
    
    -- Step 2: Charge rod
    if not self:ChargeRod(config.chargeTime) then
        logger:warn("Failed at charge step")
        return false
    end
    
    task.wait(config.chargeTime * 0.3) -- Wait partial charge time
    
    -- Step 3: Cast rod
    if not self:CastRod() then
        logger:warn("Failed at cast step")
        return false
    end
    
    logger:debug("Cast successful, starting spam...")
    
    -- Step 4: Start completion spam immediately
    self:StartCompletionSpam()
    
    return true
end

-- Main fishing loop
function AutoFishFeature:FishingLoop()
    if fishingInProgress or spamActive then return end
    
    local config = FISHING_CONFIGS[currentMode]
    local currentTime = tick()
    
    -- Wait between cycles
    if currentTime - lastFishTime < config.waitBetween then
        return
    end
    
    -- Start new cycle
    fishingInProgress = true
    lastFishTime = currentTime
    
    spawn(function()
        local success = self:ExecuteFishingSequence()
        
        if success then
            logger:debug("Fishing sequence completed")
        else
            logger:warn("Fishing sequence failed")
            fishingInProgress = false
            spamActive = false
        end
        
        -- Reset after spam finishes
        task.wait(0.5)
        fishingInProgress = false
    end)
end

-- ===========================
-- PUBLIC API
-- ===========================

-- Initialize feature
function AutoFishFeature:Init(guiControls)
    logger:info("=================================")
    logger:info("AUTO FISH V5 - ULTRA BYPASS")
    logger:info("=================================")
    
    -- Initialize remotes
    remotesInitialized = initializeRemotes()
    if not remotesInitialized then
        logger:error("Failed to initialize - remotes not found")
        return false
    end
    
    -- Apply bypass patches
    local patchSuccess = ApplyAllPatches()
    if not patchSuccess then
        logger:warn("Some patches failed, continuing anyway...")
    end
    
    -- Setup listeners
    self:SetupFishObtainedListener()
    self:SetupMinigameHook()
    
    -- Update backpack baseline
    self:UpdateBackpackCount()
    
    logger:info("✓ Initialization complete")
    logger:info(string.format("Default mode: %s", currentMode))
    logger:info("=================================")
    
    return true
end

-- Start auto fishing
function AutoFishFeature:Start(config)
    if isRunning then
        logger:warn("Already running")
        return
    end
    
    if not remotesInitialized then
        logger:error("Cannot start - not initialized")
        return
    end
    
    -- Apply config
    if config and config.mode and FISHING_CONFIGS[config.mode] then
        currentMode = config.mode
    end
    
    -- Reset state
    isRunning = true
    fishingInProgress = false
    spamActive = false
    fishCaughtFlag = false
    lastFishTime = 0
    
    local modeConfig = FISHING_CONFIGS[currentMode]
    logger:info("=================================")
    logger:info(string.format("🎣 AUTO FISH STARTED - Mode: %s", currentMode))
    logger:info(string.format("  • Charge time: %.1fs", modeConfig.chargeTime))
    logger:info(string.format("  • Spam delay: %.3fs", modeConfig.spamDelay))
    logger:info(string.format("  • Burst count: %d", modeConfig.burstCount))
    logger:info(string.format("  • Instant complete: %s", tostring(modeConfig.instantComplete)))
    logger:info("=================================")
    
    -- Start main loop
    connection = RunService.Heartbeat:Connect(function()
        if not isRunning then return end
        self:FishingLoop()
    end)
end

-- Stop auto fishing
function AutoFishFeature:Stop()
    if not isRunning then return end
    
    isRunning = false
    fishingInProgress = false
    spamActive = false
    fishCaughtFlag = false
    
    -- Disconnect main loop
    if connection then
        connection:Disconnect()
        connection = nil
    end
    
    logger:info("=================================")
    logger:info("🛑 AUTO FISH STOPPED")
    logger:info("=================================")
end

-- Change mode
function AutoFishFeature:SetMode(mode)
    if not FISHING_CONFIGS[mode] then
        logger:warn("Invalid mode:", mode)
        return false
    end
    
    local wasRunning = isRunning
    
    if wasRunning then
        self:Stop()
    end
    
    currentMode = mode
    logger:info(string.format("Mode changed to: %s", mode))
    
    if wasRunning then
        self:Start({mode = mode})
    end
    
    return true
end

-- Get current status
function AutoFishFeature:GetStatus()
    return {
        running = isRunning,
        mode = currentMode,
        inProgress = fishingInProgress,
        spamming = spamActive,
        lastCatch = lastFishTime,
        backpackCount = lastBackpackCount,
        fishCaughtFlag = fishCaughtFlag,
        remotesReady = remotesInitialized,
        patchesApplied = patchesApplied,
        listenerActive = fishObtainedConnection ~= nil,
        minigameHookActive = minigameConnection ~= nil
    }
end

-- Get available modes
function AutoFishFeature:GetModes()
    local modes = {}
    for mode, _ in pairs(FISHING_CONFIGS) do
        table.insert(modes, mode)
    end
    return modes
end

-- Cleanup
function AutoFishFeature:Cleanup()
    logger:info("Cleaning up...")
    
    self:Stop()
    
    -- Disconnect all listeners
    if fishObtainedConnection then
        fishObtainedConnection:Disconnect()
        fishObtainedConnection = nil
    end
    
    if minigameConnection then
        minigameConnection:Disconnect()
        minigameConnection = nil
    end
    
    remotesInitialized = false
    patchesApplied = false
    
    logger:info("Cleanup complete")
end

-- ===========================
-- EXPORT
-- ===========================

return AutoFishFeature