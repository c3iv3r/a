--[[
    Auto Quest DeepSea - All-in-One Module
    Automatically completes DeepSea questline with integrated AutoFish and AutoSell
    By: c3iv3r
]]

local AutoQuestDeepSea = {}
AutoQuestDeepSea.__index = AutoQuestDeepSea

-- Logger
local logger = _G.Logger and _G.Logger.new("AutoQuestDeepSea") or {
    debug = function() end,
    info = function() end,
    warn = function() end,
    error = function() end
}

-- Services
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

-- Modules
local Replion = require(ReplicatedStorage.Packages.Replion)
local QuestUtility = require(ReplicatedStorage.Shared.Quests.QuestUtility)
local QuestList = require(ReplicatedStorage.Shared.Quests.QuestList)

-- Network setup
local NetPath = nil
local FishingRemotes = {}
local SellRemotes = {}

-- Locations
local LOCATIONS = {
    SisyphusStatue = CFrame.new(-3741.66113, -135.074417, -1013.1358, -0.957978785, 1.63582214e-08, -0.286838979, 9.84434312e-09, 1, 2.41513547e-08, 0.286838979, 2.03127435e-08, -0.957978785),
    TreasureRoom = CFrame.new(-3599.24976, -266.57373, -1580.3894, 0.997320652, 8.38383407e-09, -0.0731537938, -5.83303805e-09, 1, 3.50825857e-08, 0.0731537938, -3.45618787e-08, 0.997320652)
}

-- Fishing Config
local FISHING_CONFIG = {
    chargeTime = 1.0,
    rodSlot = 1,
    spamDelay = 0.05,
    maxSpamTime = 20,
    textEffectTimeout = 15,
    spamStartDelay = 1
}

-- AutoSell Config
local THRESHOLD_ENUM = {
    Legendary = 5,
    Mythic = 6,
    Secret = 7,
}

local AUTOSELL_CONFIG = {
    threshold = "Legendary",
    limit = 0, -- 0 = sell immediately
    autoOnLimit = true,
    waitBetween = 0.15
}

--------------------------------------------------------------------------
-- Initialize Network Remotes
--------------------------------------------------------------------------

local function initializeRemotes()
    local success = pcall(function()
        NetPath = ReplicatedStorage:WaitForChild("Packages", 5)
            :WaitForChild("_Index", 5)
            :WaitForChild("sleitnick_net@0.2.0", 5)
            :WaitForChild("net", 5)
        
        -- Fishing remotes
        FishingRemotes.EquipTool = NetPath:WaitForChild("RE/EquipToolFromHotbar", 5)
        FishingRemotes.ChargeFishingRod = NetPath:WaitForChild("RF/ChargeFishingRod", 5)
        FishingRemotes.RequestFishing = NetPath:WaitForChild("RF/RequestFishingMinigameStarted", 5)
        FishingRemotes.FishingCompleted = NetPath:WaitForChild("RE/FishingCompleted", 5)
        FishingRemotes.FishObtainedNotification = NetPath:WaitForChild("RE/ObtainedNewFishNotification", 5)
        FishingRemotes.UpdateAutoFishingState = NetPath:WaitForChild("RF/UpdateAutoFishingState", 5)
        FishingRemotes.ReplicateTextEffect = NetPath:WaitForChild("RE/ReplicateTextEffect", 5)
        
        -- Selling remotes
        SellRemotes.UpdateAutoSellThreshold = NetPath:WaitForChild("RF/UpdateAutoSellThreshold", 5)
        SellRemotes.SellAllItems = NetPath:WaitForChild("RF/SellAllItems", 5)
    end)
    
    return success
end

--------------------------------------------------------------------------
-- Main Class
--------------------------------------------------------------------------

function AutoQuestDeepSea.new()
    local self = setmetatable({}, AutoQuestDeepSea)
    
    self.Player = Players.LocalPlayer
    self.Character = nil
    self.HumanoidRootPart = nil
    
    -- Main state
    self.Running = false
    self.Initialized = false
    self.RemotesInitialized = false
    
    -- Quest state
    self.PlayerData = nil
    self.CurrentQuest = nil
    self.QuestProgress = {}
    
    -- AutoFish state
    self.FishingActive = false
    self.SpamActive = false
    self.FishCaughtFlag = false
    self.TextEffectReceived = false
    
    -- AutoSell state
    self.AutoSellActive = false
    self.LastAppliedThreshold = nil
    self.LastSellTime = 0
    self.LastSellTick = 0
    
    -- Connections
    self.Connections = {}
    self.ProgressConnection = nil
    self.FishObtainedConnection = nil
    self.TextEffectConnection = nil
    self.FishingHeartbeat = nil
    self.SellHeartbeat = nil
    
    return self
end

--------------------------------------------------------------------------
-- Initialization
--------------------------------------------------------------------------

function AutoQuestDeepSea:Init()
    if self.Initialized then
        logger:warn("Already initialized!")
        return false
    end
    
    logger:info("Initializing...")
    
    -- Initialize remotes
    self.RemotesInitialized = initializeRemotes()
    if not self.RemotesInitialized then
        logger:error("Failed to initialize remotes!")
        return false
    end
    
    -- Wait for player data
    self.PlayerData = Replion.Client:WaitReplion("Data")
    if not self.PlayerData then
        logger:error("Failed to get player data!")
        return false
    end
    
    -- Initial quest scan
    self:ScanProgress()
    
    -- Setup character
    self:SetupCharacter(self.Player.Character)
    table.insert(self.Connections, self.Player.CharacterAdded:Connect(function(char)
        self:SetupCharacter(char)
    end))
    
    self.Initialized = true
    logger:info("Initialized successfully!")
    logger:info("Current progress:")
    self:PrintProgress()
    
    return true
end

function AutoQuestDeepSea:SetupCharacter(character)
    if not character then return end
    
    self.Character = character
    self.HumanoidRootPart = character:WaitForChild("HumanoidRootPart", 5)
    
    if not self.HumanoidRootPart then
        logger:warn("Failed to get HumanoidRootPart!")
    end
end

--------------------------------------------------------------------------
-- Quest Management
--------------------------------------------------------------------------

function AutoQuestDeepSea:ScanProgress()
    self.QuestProgress = {}
    
    local questData = self.PlayerData:Get({"DeepSea", "Available", "Forever", "Quests"})
    if not questData then
        logger:warn("No DeepSea quest data found!")
        return
    end
    
    local deepSeaQuests = QuestList.DeepSea.Forever
    
    for index, quest in ipairs(questData) do
        local questInfo = deepSeaQuests[quest.QuestId]
        if questInfo then
            local required = QuestUtility.GetQuestValue(self.PlayerData, questInfo)
            local progress = quest.Progress or 0
            local completed = progress >= required
            
            self.QuestProgress[index] = {
                QuestId = quest.QuestId,
                UUID = quest.UUID,
                DisplayName = questInfo.DisplayName,
                Arguments = questInfo.Arguments,
                Progress = progress,
                Required = required,
                Completed = completed,
                Redeemed = quest.Redeemed or false
            }
        end
    end
end

function AutoQuestDeepSea:PrintProgress()
    logger:info("=== DeepSea Quest Progress ===")
    for index, quest in ipairs(self.QuestProgress) do
        local status = quest.Completed and "✓" or "○"
        local percentage = math.floor((quest.Progress / quest.Required) * 100)
        logger:info(string.format(
            "%s [%d] %s: %.1f / %d (%.1f%%)",
            status,
            index,
            quest.DisplayName,
            quest.Progress,
            quest.Required,
            percentage
        ))
    end
    logger:info("==============================")
end

function AutoQuestDeepSea:GetCurrentTargetQuest()
    for index, quest in ipairs(self.QuestProgress) do
        if not quest.Completed and not quest.Redeemed then
            return quest
        end
    end
    return nil
end

function AutoQuestDeepSea:StartLiveTracking()
    if self.ProgressConnection then
        self.ProgressConnection:Disconnect()
    end
    
    self.ProgressConnection = self.PlayerData:OnChange({"DeepSea", "Available", "Forever", "Quests"}, function(newData)
        if not self.Running then return end
        
        self:ScanProgress()
        
        local currentTarget = self:GetCurrentTargetQuest()
        if not currentTarget then
            logger:info("All quests completed!")
            self:Stop()
            return
        end
        
        -- Switch quest if current is completed
        if self.CurrentQuest and self.CurrentQuest.QuestId ~= currentTarget.QuestId then
            logger:info("Switching to next quest:", currentTarget.DisplayName)
            self.CurrentQuest = currentTarget
            self:ExecuteQuest(currentTarget)
        end
    end)
end

function AutoQuestDeepSea:StopLiveTracking()
    if self.ProgressConnection then
        self.ProgressConnection:Disconnect()
        self.ProgressConnection = nil
    end
end

--------------------------------------------------------------------------
-- AutoFish Implementation
--------------------------------------------------------------------------

function AutoQuestDeepSea:StartAutoFish()
    if self.FishingActive then return end
    
    self.FishingActive = true
    self.SpamActive = false
    self.FishCaughtFlag = false
    self.TextEffectReceived = false
    
    logger:info("Starting AutoFish...")
    
    -- Setup listeners
    self:SetupFishObtainedListener()
    self:SetupTextEffectListener()
    
    -- Execute fishing sequence
    spawn(function()
        -- Equip rod
        if not self:EquipRod(FISHING_CONFIG.rodSlot) then
            logger:warn("Failed to equip rod")
            self:StopAutoFish()
            return
        end
        
        task.wait(0.2)
        
        -- Enable auto fishing state
        if not self:SetAutoFishingState(true) then
            logger:warn("Failed to enable auto fishing state")
            self:StopAutoFish()
            return
        end
        
        logger:info("Auto fishing state enabled")
        
        -- Wait for text effect
        logger:info("Waiting for text effect...")
        self:WaitForTextEffect(FISHING_CONFIG.textEffectTimeout)
        
        if not self.TextEffectReceived then
            logger:warn("Text effect never received - starting spam anyway")
        else
            logger:info("✅ Text effect confirmed!")
        end
        
        -- Delay before spam
        if FISHING_CONFIG.spamStartDelay > 0 then
            task.wait(FISHING_CONFIG.spamStartDelay)
        end
        
        -- Start spam
        self:StartCompletionSpam(FISHING_CONFIG.spamDelay, FISHING_CONFIG.maxSpamTime)
    end)
end

function AutoQuestDeepSea:StopAutoFish()
    if not self.FishingActive then return end
    
    self.FishingActive = false
    self.SpamActive = false
    self.FishCaughtFlag = false
    self.TextEffectReceived = false
    
    -- Disable auto fishing state
    self:SetAutoFishingState(false)
    
    if self.FishObtainedConnection then
        self.FishObtainedConnection:Disconnect()
        self.FishObtainedConnection = nil
    end
    
    if self.TextEffectConnection then
        self.TextEffectConnection:Disconnect()
        self.TextEffectConnection = nil
    end
    
    logger:info("AutoFish stopped")
end

function AutoQuestDeepSea:SetAutoFishingState(enabled)
    if not FishingRemotes.UpdateAutoFishingState then return false end
    
    local success = pcall(function()
        FishingRemotes.UpdateAutoFishingState:InvokeServer(enabled)
    end)
    
    return success
end

function AutoQuestDeepSea:SetupTextEffectListener()
    if not FishingRemotes.ReplicateTextEffect then
        logger:warn("ReplicateTextEffect not available")
        return
    end
    
    if self.TextEffectConnection then
        self.TextEffectConnection:Disconnect()
    end
    
    self.TextEffectConnection = FishingRemotes.ReplicateTextEffect.OnClientEvent:Connect(function(data)
        if not self.FishingActive then return end
        
        if not data or not data.TextData then return end
        if not self.Character or not self.Character.Head then return end
        if data.TextData.AttachTo ~= self.Character.Head then return end
        
        logger:info("🎣 Text effect received!")
        self.TextEffectReceived = true
    end)
end

function AutoQuestDeepSea:WaitForTextEffect(timeout)
    local startTime = tick()
    self.TextEffectReceived = false
    
    while self.FishingActive and not self.TextEffectReceived and (tick() - startTime) < timeout do
        task.wait(0.1)
    end
    
    return self.TextEffectReceived
end

function AutoQuestDeepSea:SetupFishObtainedListener()
    if not FishingRemotes.FishObtainedNotification then
        logger:warn("FishObtainedNotification not available")
        return
    end
    
    if self.FishObtainedConnection then
        self.FishObtainedConnection:Disconnect()
    end
    
    self.FishObtainedConnection = FishingRemotes.FishObtainedNotification.OnClientEvent:Connect(function(...)
        if self.FishingActive then
            logger:info("Fish caught! Starting new cycle...")
            self.FishCaughtFlag = true
            
            self.SpamActive = false
            
            task.wait(0.1)
            self.FishCaughtFlag = false
            
            spawn(function()
                if not self.FishingActive then return end
                
                logger:info("Waiting for text effect...")
                self.TextEffectReceived = false
                self:WaitForTextEffect(FISHING_CONFIG.textEffectTimeout)
                
                if not self.TextEffectReceived then
                    logger:warn("Text effect never received in new cycle")
                else
                    logger:info("✅ Text effect received!")
                end
                
                if FISHING_CONFIG.spamStartDelay > 0 then
                    task.wait(FISHING_CONFIG.spamStartDelay)
                end
                
                self:StartCompletionSpam(FISHING_CONFIG.spamDelay, FISHING_CONFIG.maxSpamTime)
            end)
        end
    end)
end

function AutoQuestDeepSea:EquipRod(slot)
    if not FishingRemotes.EquipTool then return false end
    
    local success = pcall(function()
        FishingRemotes.EquipTool:FireServer(slot)
    end)
    
    return success
end

function AutoQuestDeepSea:StartCompletionSpam(delay, maxTime)
    if self.SpamActive then return end
    
    self.SpamActive = true
    local spamStartTime = tick()
    
    logger:info("Starting completion spam...")
    
    spawn(function()
        while self.SpamActive and self.FishingActive and (tick() - spamStartTime) < maxTime do
            self:FireCompletion()
            
            if self.FishCaughtFlag then
                logger:info("✅ Fish caught after", string.format("%.2f", tick() - spamStartTime), "seconds")
                break
            end
            
            task.wait(delay)
        end
        
        self.SpamActive = false
        
        if not self.FishCaughtFlag and (tick() - spamStartTime) >= maxTime then
            logger:warn("⏱️ Completion timeout after", maxTime, "seconds")
        end
    end)
end

function AutoQuestDeepSea:FireCompletion()
    if not FishingRemotes.FishingCompleted then return false end
    
    pcall(function()
        FishingRemotes.FishingCompleted:FireServer()
    end)
    
    return true
end

--------------------------------------------------------------------------
-- AutoSell Implementation
--------------------------------------------------------------------------

function AutoQuestDeepSea:StartAutoSell()
    if self.AutoSellActive then return end
    
    self.AutoSellActive = true
    self.LastSellTime = tick()
    self.LastSellTick = 0
    
    logger:info("Starting AutoSell with threshold:", AUTOSELL_CONFIG.threshold)
    
    -- Apply threshold
    self:ApplyThreshold(AUTOSELL_CONFIG.threshold)
    
    -- Start sell loop
    if self.SellHeartbeat then
        self.SellHeartbeat:Disconnect()
    end
    
    self.SellHeartbeat = RunService.Heartbeat:Connect(function()
        if not self.AutoSellActive then return end
        self:AutoSellLoop()
    end)
end

function AutoQuestDeepSea:StopAutoSell()
    if not self.AutoSellActive then return end
    
    self.AutoSellActive = false
    
    if self.SellHeartbeat then
        self.SellHeartbeat:Disconnect()
        self.SellHeartbeat = nil
    end
    
    logger:info("AutoSell stopped")
end

function AutoQuestDeepSea:ApplyThreshold(mode)
    if not SellRemotes.UpdateAutoSellThreshold then return false end
    if self.LastAppliedThreshold == mode then return true end
    
    local code = THRESHOLD_ENUM[mode]
    if not code then return false end
    
    local ok = pcall(function()
        SellRemotes.UpdateAutoSellThreshold:InvokeServer(code)
    end)
    
    if ok then
        self.LastAppliedThreshold = mode
    end
    
    return ok
end

function AutoQuestDeepSea:PerformSellAll()
    if not SellRemotes.SellAllItems then return false end
    
    local ok = pcall(function()
        SellRemotes.SellAllItems:InvokeServer()
    end)
    
    return ok
end

function AutoQuestDeepSea:AutoSellLoop()
    local now = tick()
    if now - self.LastSellTick < AUTOSELL_CONFIG.waitBetween then
        return
    end
    self.LastSellTick = now
    
    -- Ensure threshold is applied
    self:ApplyThreshold(AUTOSELL_CONFIG.threshold)
    
    -- Auto sell logic
    if AUTOSELL_CONFIG.autoOnLimit then
        if AUTOSELL_CONFIG.limit <= 0 then
            self:PerformSellAll()
        else
            if now - self.LastSellTime >= AUTOSELL_CONFIG.limit then
                if self:PerformSellAll() then
                    self.LastSellTime = now
                end
            end
        end
    end
end

--------------------------------------------------------------------------
-- Quest Execution
--------------------------------------------------------------------------

function AutoQuestDeepSea:Teleport(cframe)
    if not self.HumanoidRootPart then
        logger:warn("No HumanoidRootPart found!")
        return false
    end
    
    self.HumanoidRootPart.CFrame = cframe
    task.wait(0.5)
    return true
end

function AutoQuestDeepSea:ExecuteQuest(quest)
    logger:info("Executing quest:", quest.DisplayName)
    
    -- Stop current activities
    self:StopAutoFish()
    self:StopAutoSell()
    
    local args = quest.Arguments
    local key = args.key
    
    -- Determine location and action based on quest
    if key == "CatchRareTreasureRoom" then
        logger:info("📍 Teleporting to Treasure Room...")
        self:Teleport(LOCATIONS.TreasureRoom)
        task.wait(0.5)
        self:StartAutoFish()
        
    elseif key == "CatchFish" then
        if args.conditions and args.conditions.AreaName == "Sisyphus Statue" then
            logger:info("📍 Teleporting to Sisyphus Statue...")
            self:Teleport(LOCATIONS.SisyphusStatue)
            task.wait(0.5)
            self:StartAutoFish()
        end
        
    elseif key == "EarnCoins" then
        logger:info("💰 Working on Earn Coins quest...")
        self:StartAutoSell()
        self:StartAutoFish()
    end
end

--------------------------------------------------------------------------
-- Main Control
--------------------------------------------------------------------------

function AutoQuestDeepSea:Start()
    if not self.Initialized then
        logger:warn("Not initialized! Call Init() first!")
        return false
    end
    
    if self.Running then
        logger:warn("Already running!")
        return false
    end
    
    logger:info("Starting AutoQuest DeepSea...")
    
    -- Rescan progress
    self:ScanProgress()
    self:PrintProgress()
    
    -- Start live tracking
    self:StartLiveTracking()
    
    -- Get current target quest
    local targetQuest = self:GetCurrentTargetQuest()
    if not targetQuest then
        logger:info("All quests already completed!")
        return false
    end
    
    self.CurrentQuest = targetQuest
    self.Running = true
    
    -- Execute the quest
    self:ExecuteQuest(targetQuest)
    
    logger:info("Started successfully!")
    return true
end

function AutoQuestDeepSea:Stop()
    if not self.Running then
        logger:warn("Not running!")
        return false
    end
    
    logger:info("Stopping...")
    
    self.Running = false
    
    -- Stop all activities
    self:StopLiveTracking()
    self:StopAutoFish()
    self:StopAutoSell()
    
    self.CurrentQuest = nil
    
    logger:info("Stopped successfully!")
    return true
end

function AutoQuestDeepSea:Cleanup()
    logger:info("Cleaning up...")
    
    if self.Running then
        self:Stop()
    end
    
    -- Disconnect all connections
    for _, connection in ipairs(self.Connections) do
        if connection and connection.Connected then
            connection:Disconnect()
        end
    end
    self.Connections = {}
    
    self:StopLiveTracking()
    
    -- Clear data
    self.PlayerData = nil
    self.QuestProgress = {}
    self.CurrentQuest = nil
    self.Initialized = false
    self.RemotesInitialized = false
    
    logger:info("Cleanup complete!")
end

function AutoQuestDeepSea:GetStatus()
    return {
        Initialized = self.Initialized,
        Running = self.Running,
        CurrentQuest = self.CurrentQuest and self.CurrentQuest.DisplayName or "None",
        FishingActive = self.FishingActive,
        AutoSellActive = self.AutoSellActive,
        Progress = self.QuestProgress
    }
end

return AutoQuestDeepSea