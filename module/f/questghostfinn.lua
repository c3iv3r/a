-- QuestGhostfinn Module
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local QuestController = require(ReplicatedStorage.Controllers.QuestController)
local QuestUtility = require(ReplicatedStorage.Shared.Quests.QuestUtility)
local QuestList = require(ReplicatedStorage.Shared.Quests.QuestList)
local Replion = require(ReplicatedStorage.Packages.Replion)

local LocalPlayer = Players.LocalPlayer
local QuestGhostfinn = {}
QuestGhostfinn.__index = QuestGhostfinn

local logger = _G.Logger and _G.Logger.new("QuestGhostfinn") or {
    debug = function() end,
    info = function() end,
    warn = function() end,
    error = function() end
}

local LOCATIONS = {
    ["Treasure Room"] = CFrame.new(-3599.24976, -266.57373, -1580.3894, 0.997320652, 8.38383407e-09, -0.0731537938, -5.83303805e-09, 1, 3.50825857e-08, 0.0731537938, -3.45618787e-08, 0.997320652),
    ["Sisyphus Statue"] = CFrame.new(-3741.66113, -135.074417, -1013.1358, -0.957978785, 1.63582214e-08, -0.286838979, 9.84434312e-09, 1, 2.41513547e-08, 0.286838979, 2.03127435e-08, -0.957978785)
}

local AUTOFISHV3_URL = "https://raw.githubusercontent.com/c3iv3r/a/refs/heads/main/module/f/autofishv3.lua"
local AUTOSELL_URL = "https://raw.githubusercontent.com/c3iv3r/a/refs/heads/main/module/f/autosellfish.lua"

function QuestGhostfinn.new()
    local self = setmetatable({}, QuestGhostfinn)
    
    self._running = false
    self._dataReplion = nil
    self._autoFishModule = nil
    self._autoSellModule = nil
    self._autoFishInstance = nil
    self._autoSellInstance = nil
    self._questData = nil
    self._monitorConnection = nil
    self._currentQuestIndex = 1
    self._lastProgressCheck = {}
    self._isTeleporting = false
    
    return self
end

function QuestGhostfinn:Init()
    self._dataReplion = Replion.Client:WaitReplion("Data")
    self._questData = QuestList.DeepSea
    
    if not self._questData then
        logger:warn("[QuestGhostfinn] DeepSea quest data not found")
        return false
    end
    
    -- Load modules
    local fishLoaded = self:_loadAutoFish()
    local sellLoaded = self:_loadAutoSell()
    
    if not fishLoaded or not sellLoaded then
        logger:warn("[QuestGhostfinn] Failed to load required modules")
        return false
    end
    
    logger:info("[QuestGhostfinn] Initialized")
    return true
end

function QuestGhostfinn:Start()
    if self._running then return end
    
    self._running = true
    self._currentQuestIndex = 1
    self._lastProgressCheck = {}
    
    -- Create instances
    if self._autoFishModule then
        self._autoFishInstance = self._autoFishModule.new and self._autoFishModule.new() or self._autoFishModule
        if self._autoFishInstance.Init then
            self._autoFishInstance:Init()
        end
    end
    
    if self._autoSellModule then
        self._autoSellInstance = self._autoSellModule.new and self._autoSellModule.new() or self._autoSellModule
        if self._autoSellInstance.Init then
            self._autoSellInstance:Init()
        end
    end
    
    -- Start monitoring
    self:_startMonitoring()
    
    logger:info("[QuestGhostfinn] Started")
end

function QuestGhostfinn:Stop()
    if not self._running then return end
    
    self._running = false
    
    -- Stop monitoring
    self:_stopMonitoring()
    
    -- Stop modules
    if self._autoFishInstance and self._autoFishInstance.Stop then
        pcall(function() self._autoFishInstance:Stop() end)
    end
    
    if self._autoSellInstance and self._autoSellInstance.Stop then
        pcall(function() self._autoSellInstance:Stop() end)
    end
    
    -- Cleanup instances
    if self._autoFishInstance and self._autoFishInstance.Cleanup then
        pcall(function() self._autoFishInstance:Cleanup() end)
    end
    
    if self._autoSellInstance and self._autoSellInstance.Cleanup then
        pcall(function() self._autoSellInstance:Cleanup() end)
    end
    
    self._autoFishInstance = nil
    self._autoSellInstance = nil
    
    logger:info("[QuestGhostfinn] Stopped")
end

function QuestGhostfinn:Cleanup()
    self:Stop()
    
    self._dataReplion = nil
    self._questData = nil
    self._autoFishModule = nil
    self._autoSellModule = nil
    table.clear(self._lastProgressCheck)
    
    logger:info("[QuestGhostfinn] Cleaned up")
end

function QuestGhostfinn:_loadAutoFish()
    local success, result = pcall(function()
        return loadstring(game:HttpGet(AUTOFISHV3_URL))()
    end)
    
    if success then
        self._autoFishModule = result
        logger:info("[QuestGhostfinn] AutoFishV3 loaded")
        return true
    else
        logger:warn("[QuestGhostfinn] Failed to load AutoFishV3:", result)
        return false
    end
end

function QuestGhostfinn:_loadAutoSell()
    local success, result = pcall(function()
        return loadstring(game:HttpGet(AUTOSELL_URL))()
    end)
    
    if success then
        self._autoSellModule = result
        logger:info("[QuestGhostfinn] AutoSell loaded")
        return true
    else
        logger:warn("[QuestGhostfinn] Failed to load AutoSell:", result)
        return false
    end
end

function QuestGhostfinn:_startMonitoring()
    if self._monitorConnection then
        self._monitorConnection:Disconnect()
    end
    
    local lastUpdate = tick()
    
    self._monitorConnection = RunService.Heartbeat:Connect(function()
        if not self._running then return end
        
        -- Update setiap 1 detik untuk hindari lag
        if tick() - lastUpdate < 1 then return end
        lastUpdate = tick()
        
        self:_checkAndProcessQuests()
    end)
end

function QuestGhostfinn:_stopMonitoring()
    if self._monitorConnection then
        self._monitorConnection:Disconnect()
        self._monitorConnection = nil
    end
end

function QuestGhostfinn:_getQuestProgress(questIndex)
    if not self._dataReplion then return nil end
    
    local questPath = {"DeepSea", "Available", "Forever", "Quests", questIndex}
    local questData = self._dataReplion:Get(questPath)
    
    if not questData then return nil end
    
    local questInfo = self._questData.Forever[questIndex]
    if not questInfo then return nil end
    
    local maxValue = QuestUtility:GetQuestValue(self._dataReplion, questInfo)
    local progress = questData.Progress or 0
    
    return {
        progress = progress,
        maxValue = maxValue,
        redeemed = questData.Redeemed or false,
        completed = progress >= maxValue,
        info = questInfo,
        index = questIndex
    }
end

function QuestGhostfinn:_isAllQuestsCompleted()
    for i = 1, #self._questData.Forever do
        local progress = self:_getQuestProgress(i)
        if progress and not progress.redeemed then
            return false
        end
    end
    return true
end

function QuestGhostfinn:_teleportToLocation(locationName)
    if self._isTeleporting then return false end
    
    local cframe = LOCATIONS[locationName]
    if not cframe then
        logger:warn("[QuestGhostfinn] Location not found:", locationName)
        return false
    end
    
    local char = LocalPlayer.Character
    if not char or not char.PrimaryPart then return false end
    
    self._isTeleporting = true
    
    pcall(function()
        char:SetPrimaryPartCFrame(cframe)
    end)
    
    task.wait(1)
    self._isTeleporting = false
    
    return true
end

function QuestGhostfinn:_startAutoFish()
    if not self._autoFishInstance then return end
    
    pcall(function()
        if self._autoFishInstance.Start then
            self._autoFishInstance:Start()
        end
    end)
end

function QuestGhostfinn:_stopAutoFish()
    if not self._autoFishInstance then return end
    
    pcall(function()
        if self._autoFishInstance.Stop then
            self._autoFishInstance:Stop()
        end
    end)
end

function QuestGhostfinn:_startAutoSell()
    if not self._autoSellInstance then return end
    
    pcall(function()
        if self._autoSellInstance.Start then
            -- Sell legendary only untuk coins
            self._autoSellInstance:Start({
                threshold = "Legendary",
                limit = 5,
                autoOnLimit = true
            })
        end
    end)
end

function QuestGhostfinn:_stopAutoSell()
    if not self._autoSellInstance then return end
    
    pcall(function()
        if self._autoSellInstance.Stop then
            self._autoSellInstance:Stop()
        end
    end)
end

function QuestGhostfinn:_checkAndProcessQuests()
    -- Check if all completed
    if self:_isAllQuestsCompleted() then
        logger:info("[QuestGhostfinn] ✅ All DeepSea quests completed!")
        self:Stop()
        return
    end
    
    -- Find first incomplete quest
    local targetQuest = nil
    for i = 1, #self._questData.Forever do
        local progress = self:_getQuestProgress(i)
        if progress and not progress.redeemed and not progress.completed then
            targetQuest = progress
            self._currentQuestIndex = i
            break
        end
    end
    
    if not targetQuest then
        -- Semua completed tapi belum redeemed, tunggu server
        return
    end
    
    -- Check if progress changed
    local lastProgress = self._lastProgressCheck[targetQuest.index]
    if lastProgress ~= targetQuest.progress then
        logger:info(string.format("[QuestGhostfinn] Quest %d: %d/%d", targetQuest.index, targetQuest.progress, targetQuest.maxValue))
        self._lastProgressCheck[targetQuest.index] = targetQuest.progress
    end
    
    -- Process quest
    self:_processQuest(targetQuest)
end

function QuestGhostfinn:_processQuest(progress)
    local questInfo = progress.info
    local args = questInfo.Arguments
    
    -- Quest 1: Catch 300 Rare/Epic fish in Treasure Room
    if args.key == "CatchRareTreasureRoom" then
        self:_handleTreasureRoomQuest()
        
    -- Quest 2: Catch 3 Mythic at Sisyphus Statue
    elseif args.key == "CatchFish" and args.conditions then
        if args.conditions.Tier == 6 and args.conditions.AreaName == "Sisyphus Statue" then
            self:_handleSisyphusQuest()
        
        -- Quest 3: Catch 1 SECRET at Sisyphus Statue
        elseif args.conditions.Tier == 7 and args.conditions.AreaName == "Sisyphus Statue" then
            self:_handleSisyphusQuest()
        end
        
    -- Quest 4: Earn 1M Coins
    elseif args.key == "EarnCoins" then
        self:_handleCoinsQuest()
    end
end

function QuestGhostfinn:_handleTreasureRoomQuest()
    -- Teleport ke Treasure Room
    local currentLoc = self:_getCurrentLocation()
    if currentLoc ~= "Treasure Room" then
        self:_stopAutoFish()
        self:_stopAutoSell()
        self:_teleportToLocation("Treasure Room")
    end
    
    -- Start fishing
    self:_startAutoFish()
end

function QuestGhostfinn:_handleSisyphusQuest()
    -- Teleport ke Sisyphus Statue
    local currentLoc = self:_getCurrentLocation()
    if currentLoc ~= "Sisyphus Statue" then
        self:_stopAutoFish()
        self:_stopAutoSell()
        self:_teleportToLocation("Sisyphus Statue")
    end
    
    -- Start fishing
    self:_startAutoFish()
end

function QuestGhostfinn:_handleCoinsQuest()
    -- Fishing di location mana saja + auto sell legendary
    local currentLoc = self:_getCurrentLocation()
    if not currentLoc then
        self:_teleportToLocation("Treasure Room")
    end
    
    self:_startAutoFish()
    self:_startAutoSell()
end

function QuestGhostfinn:_getCurrentLocation()
    local char = LocalPlayer.Character
    if not char or not char.PrimaryPart then return nil end
    
    local pos = char.PrimaryPart.Position
    
    for name, cframe in pairs(LOCATIONS) do
        local locPos = cframe.Position
        if (pos - locPos).Magnitude < 150 then
            return name
        end
    end
    
    return nil
end

function QuestGhostfinn:GetStatus()
    return {
        running = self._running,
        currentQuest = self._currentQuestIndex,
        allCompleted = self:_isAllQuestsCompleted(),
        location = self:_getCurrentLocation(),
        autoFishActive = self._autoFishInstance ~= nil,
        autoSellActive = self._autoSellInstance ~= nil
    }
end

return QuestGhostfinn