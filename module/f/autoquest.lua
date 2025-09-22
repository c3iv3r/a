-- ===========================
-- AUTO QUEST FEATURE - COMPLETE PATCH
-- File: autoquest.lua
-- ===========================

local AutoQuest = {}
AutoQuest.__index = AutoQuest

local logger = _G.Logger and _G.Logger.new("AutoQuest") or {
    debug = function() end,
    info = function() end,
    warn = function() end,
    error = function() end
}

-- Services
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local LocalPlayer = Players.LocalPlayer

-- Required modules
local QuestUtility = require(ReplicatedStorage.Shared.Quests.QuestUtility)
local QuestList = require(ReplicatedStorage.Shared.Quests.QuestList)
local Replion = require(ReplicatedStorage.Packages.Replion)

-- Feature dependencies (will be resolved in Init)
local AutoFish = nil
local AutoSellFish = nil
local AutoTeleportIsland = nil

-- State
local isInitialized = false
local isRunning = false
local currentQuestId = nil
local currentSubQuests = {}
local currentSubQuestIndex = 1
local dataReplion = nil
local progressConnection = nil
local runConnection = nil

-- Constants
local CHECK_PROGRESS_INTERVAL = 2  -- seconds
local SUBQUEST_TIMEOUT = 300  -- 5 minutes
local TELEPORT_DURATION = 1  -- seconds

-- Quest action priority (lower = easier)
local QUEST_ACTION_PRIORITY = {
    VisitLocation = 1,
    SellFish = 2,
    BuyRod = 3,
    BuyBobber = 4,
    CatchFish = 5,
    LavaFisherman = 6,
    EarnCoins = 7
}

-- Utility functions
local function safeSetDropdownValues(dropdown, values)
    if not dropdown then return end
    
    if dropdown.SetValues then
        dropdown:SetValues(values)
    elseif dropdown.Values then
        dropdown.Values = values
        if dropdown.Refresh then
            dropdown:Refresh()
        end
    end
end

local function safeSetLabelText(label, text)
    if not label then return end
    
    if label.SetText then
        label:SetText(text)
    else
        label.Text = text
    end
end

local function safeSetToggleValue(toggle, value)
    if not toggle then return end
    
    if toggle.SetValue then
        toggle:SetValue(value)
    elseif toggle.SetState then
        toggle:SetState(value)
    end
end

-- Calculate difficulty score for sub-quest
local function calculateDifficulty(subQuest)
    local score = 0
    
    -- Base score from target value
    local target = subQuest.Arguments.value
    if type(target) == "number" then
        score = score + target
    end
    
    -- Add score based on action type
    local actionType = subQuest.Arguments.key
    if QUEST_ACTION_PRIORITY[actionType] then
        score = score + (QUEST_ACTION_PRIORITY[actionType] * 1000)
    else
        score = score + 10000  -- Unknown actions get high score
    end
    
    -- Add score for specific conditions
    if subQuest.Arguments.conditions then
        local conditions = subQuest.Arguments.conditions
        if conditions.Tier then
            score = score + (conditions.Tier * 100)  -- Higher tier = harder
        end
        if conditions.Name then
            score = score + 500  -- Specific fish name might be rarer
        end
    end
    
    return score
end

-- Sort sub-quests by difficulty (easiest first)
local function sortSubQuestsByDifficulty(subQuests)
    local sorted = {}
    
    for i, subQuest in ipairs(subQuests) do
        local difficulty = calculateDifficulty(subQuest)
        table.insert(sorted, {
            index = i,
            difficulty = difficulty,
            data = subQuest
        })
    end
    
    table.sort(sorted, function(a, b)
        return a.difficulty < b.difficulty
    end)
    
    return sorted
end

-- Get all available quest lines (non-Primary)
local function getAvailableQuestLines()
    local questLines = {}
    
    for questId, questData in pairs(QuestList) do
        if questId ~= "Primary" and type(questData) == "table" and questData.Forever then
            table.insert(questLines, {
                id = questId,
                name = questData.Identifier or questId,
                subQuests = #questData.Forever
            })
        end
    end
    
    table.sort(questLines, function(a, b)
        return a.name < b.name
    end)
    
    return questLines
end

-- Get sub-quests for a quest line, sorted by difficulty
local function getSortedSubQuests(questId)
    local questData = QuestList[questId]
    if not questData or not questData.Forever then
        return {}
    end
    
    local sortedSubQuests = sortSubQuestsByDifficulty(questData.Forever)
    local result = {}
    
    for _, item in ipairs(sortedSubQuests) do
        table.insert(result, item.data)
    end
    
    return result
end

-- Get current progress for a sub-quest
local function getSubQuestProgress(questId, subQuest)
    local paths = QuestUtility:GetPaths("PrimaryQuests")
    local questData = dataReplion:Get({paths.Forever, "Quests"})
    
    if not questData then return 0 end
    
    for _, quest in ipairs(questData) do
        if quest.QuestId == questId then
            local target = QuestUtility:GetQuestValue(dataReplion, subQuest)
            return math.min(quest.Progress or 0, target)
        end
    end
    
    return 0
end

-- Check if sub-quest is completed
local function isSubQuestCompleted(questId, subQuest)
    local progress = getSubQuestProgress(questId, subQuest)
    local target = QuestUtility:GetQuestValue(dataReplion, subQuest)
    return progress >= target
end

-- Teleport to location
local function teleportTo(location)
    if not location then return false end
    
    local character = LocalPlayer.Character
    if not character or not character.PrimaryPart then return false end
    
    -- Handle multiple locations
    local targetLocation = location
    if type(location) == "table" then
        local closest = nil
        local closestDist = math.huge
        
        for _, loc in ipairs(location) do
            local dist = (character.PrimaryPart.Position - loc.Position).Magnitude
            if dist < closestDist then
                closestDist = dist
                closest = loc
            end
        end
        
        targetLocation = closest
    end
    
    -- Smooth teleport
    local tween = TweenService:Create(
        character.PrimaryPart,
        TweenInfo.new(TELEPORT_DURATION, Enum.EasingStyle.Linear),
        {CFrame = targetLocation}
    )
    
    tween:Play()
    tween.Completed:Wait()
    
    return true
end

-- Execute sub-quest action
local function executeSubQuestAction(subQuest)
    local actionType = subQuest.Arguments.key
    logger:info("Executing action:", actionType, "for sub-quest:", subQuest.DisplayName)
    
    -- Teleport to location if available
    if subQuest.TrackQuestCFrame then
        logger:info("Teleporting to quest location")
        teleportTo(subQuest.TrackQuestCFrame)
        task.wait(0.5)
    end
    
    -- Execute based on action type
    if actionType == "CatchFish" then
        if AutoFish then
            logger:info("Starting auto fishing")
            AutoFish:Start({mode = "Fast"})
        else
            logger:warn("AutoFish module not available")
        end
        
    elseif actionType == "SellFish" then
        if AutoSellFish then
            logger:info("Starting auto selling")
            AutoSellFish:Start({
                threshold = "Legendary",
                limit = 0,
                autoOnLimit = true
            })
        else
            logger:warn("AutoSellFish module not available")
        end
        
    elseif actionType == "VisitLocation" then
        logger:info("Visited location, waiting 2 seconds")
        task.wait(2)
        
    elseif actionType == "BuyRod" or actionType == "BuyBobber" then
        logger:info("Teleporting to shop for:", actionType)
        task.wait(2)
        
    elseif actionType == "LavaFisherman" then
        logger:info("Talking to Lava Fisherman")
        task.wait(2)
        
    elseif actionType == "EarnCoins" then
        if AutoSellFish then
            logger:info("Starting auto selling for EarnCoins")
            AutoSellFish:Start({
                threshold = "Legendary",
                limit = 0,
                autoOnLimit = true
            })
        else
            logger:warn("AutoSellFish module not available")
        end
        
    else
        logger:warn("Unknown action type:", actionType)
        return false
    end
    
    return true
end

-- Stop all running actions
local function stopAllActions()
    if AutoFish then
        AutoFish:Stop()
    end
    
    if AutoSellFish then
        AutoSellFish:Stop()
    end
end

-- Update progress display
local function updateProgressDisplay(questId)
    if not AutoQuest.__controls or not AutoQuest.__controls.labels then return end
    
    local subQuests = getSortedSubQuests(questId)
    local labels = AutoQuest.__controls.labels
    
    for i, subQuest in ipairs(subQuests) do
        local progress = getSubQuestProgress(questId, subQuest)
        local target = QuestUtility:GetQuestValue(dataReplion, subQuest)
        
        local label = labels[i]
        if label then
            local status = ""
            if progress >= target then
                status = "✓ "
            elseif i == currentSubQuestIndex and isRunning then
                status = "→ "
            else
                status = "  "
            end
            
            safeSetLabelText(label, status .. string.format("%d) %s — %s / %s", 
                i, subQuest.DisplayName, tostring(math.floor(progress)), tostring(target)))
        end
    end
    
    -- Clear remaining labels
    for i = #subQuests + 1, #labels do
        safeSetLabelText(labels[i], "")
    end
end

-- Setup progress listener
local function setupProgressListener(questId)
    if progressConnection then
        progressConnection:Disconnect()
        progressConnection = nil
    end
    
    local paths = QuestUtility:GetPaths("PrimaryQuests")
    progressConnection = dataReplion:OnChange({paths.Forever, "Quests"}, function()
        if isRunning then
            updateProgressDisplay(questId)
        end
    end)
end

-- Main auto-quest loop
local function runAutoQuestLoop()
    logger:info("Starting auto-quest loop for:", currentQuestId)
    
    while isRunning and currentQuestId do
        -- Check if we have sub-quests to process
        if currentSubQuestIndex > #currentSubQuests then
            -- All sub-quests completed
            logger:info("All sub-quests completed for quest:", currentQuestId)
            AutoQuest:Stop()
            return
        end
        
        -- Get current sub-quest
        local currentSubQuest = currentSubQuests[currentSubQuestIndex]
        logger:info("Processing sub-quest", currentSubQuestIndex, ":", currentSubQuest.DisplayName)
        
        -- Update progress display
        updateProgressDisplay(currentQuestId)
        
        -- Execute the sub-quest
        if executeSubQuestAction(currentSubQuest) then
            -- Wait for completion
            local startTime = tick()
            
            while isRunning and (tick() - startTime) < SUBQUEST_TIMEOUT do
                -- Check if sub-quest is completed
                if isSubQuestCompleted(currentQuestId, currentSubQuest) then
                    logger:info("Sub-quest completed:", currentSubQuest.DisplayName)
                    
                    -- Stop all actions
                    stopAllActions()
                    
                    -- Move to next sub-quest
                    currentSubQuestIndex = currentSubQuestIndex + 1
                    break
                end
                
                task.wait(CHECK_PROGRESS_INTERVAL)
            end
            
            -- Check timeout
            if (tick() - startTime) >= SUBQUEST_TIMEOUT then
                logger:warn("Sub-quest timed out:", currentSubQuest.DisplayName)
                stopAllActions()
                currentSubQuestIndex = currentSubQuestIndex + 1
            end
        else
            -- Failed to execute, skip to next
            logger:warn("Failed to execute sub-quest:", currentSubQuest.DisplayName)
            currentSubQuestIndex = currentSubQuestIndex + 1
        end
        
        -- Small delay between sub-quests
        task.wait(1)
    end
end

-- Public API
function AutoQuest:Init()
    logger:info("Initializing AutoQuest...")
    
    -- Initialize dependencies
    local FeatureManager = _G.FeatureManager
    if FeatureManager then
        AutoFish = FeatureManager:Get("AutoFish")
        AutoSellFish = FeatureManager:Get("AutoSellFish")
        AutoTeleportIsland = FeatureManager:Get("AutoTeleportIsland")
    end
    
    -- Initialize modules if available
    if AutoFish and not AutoFish.__initialized then
        AutoFish:Init()
    end
    
    if AutoSellFish and not AutoSellFish.__initialized then
        AutoSellFish:Init()
    end
    
    if AutoTeleportIsland and not AutoTeleportIsland.__initialized then
        AutoTeleportIsland:Init()
    end
    
    -- Get Replion data
    dataReplion = Replion.Client:WaitReplion("Data")
    
    -- Populate dropdown with available quests
    if self.__controls and self.__controls.dropdown then
        local questLines = getAvailableQuestLines()
        local dropdownValues = {}
        
        for _, quest in ipairs(questLines) do
            table.insert(dropdownValues, quest.name)
        end
        
        safeSetDropdownValues(self.__controls.dropdown, dropdownValues)
        logger:info("Dropdown populated with", #dropdownValues, "quests")
    end
    
    isInitialized = true
    logger:info("AutoQuest initialized successfully")
    
    return true
end

function AutoQuest:OnQuestSelected(questName)
    logger:info("Quest selected:", questName)
    
    if not isInitialized then
        logger:warn("AutoQuest not initialized")
        return
    end
    
    -- Find quest ID by name
    local questId = nil
    for id, data in pairs(QuestList) do
        if data.Identifier == questName or id == questName then
            questId = id
            break
        end
    end
    
    if not questId then
        logger:warn("Quest not found:", questName)
        return
    end
    
    -- Update progress display
    updateProgressDisplay(questId)
    
    -- Setup progress listener
    setupProgressListener(questId)
end

function AutoQuest:Start(opts)
    if not isInitialized then
        logger:warn("AutoQuest not initialized")
        return false
    end
    
    if isRunning then
        logger:warn("AutoQuest is already running")
        return false
    end
    
    if not opts or not opts.questLine then
        logger:warn("No quest line provided")
        return false
    end
    
    -- Find quest ID by name
    local questId = nil
    for id, data in pairs(QuestList) do
        if data.Identifier == opts.questLine or id == opts.questLine then
            questId = id
            break
        end
    end
    
    if not questId then
        logger:warn("Quest not found:", opts.questLine)
        return false
    end
    
    -- Get sorted sub-quests
    currentSubQuests = getSortedSubQuests(questId)
    if #currentSubQuests == 0 then
        logger:warn("No sub-quests found for quest:", questId)
        return false
    end
    
    -- Initialize state
    currentQuestId = questId
    currentSubQuestIndex = 1
    isRunning = true
    
    -- Update toggle state
    if self.__controls and self.__controls.toggle then
        safeSetToggleValue(self.__controls.toggle, true)
    end
    
    logger:info("Starting AutoQuest for:", questId)
    logger:info("Sub-quests order (easiest first):")
    for i, subQuest in ipairs(currentSubQuests) do
        logger:info(i .. ".", subQuest.DisplayName, "- Difficulty:", calculateDifficulty(subQuest))
    end
    
    -- Start the main loop
    runConnection = RunService.Heartbeat:Connect(function()
        if not isRunning then return end
        updateProgressDisplay(currentQuestId)
    end)
    
    task.spawn(runAutoQuestLoop)
    
    return true
end

function AutoQuest:Stop()
    if not isRunning then return end
    
    isRunning = false
    currentQuestId = nil
    currentSubQuestIndex = 1
    
    -- Stop all actions
    stopAllActions()
    
    -- Update toggle state
    if self.__controls and self.__controls.toggle then
        safeSetToggleValue(self.__controls.toggle, false)
    end
    
    -- Disconnect connections
    if runConnection then
        runConnection:Disconnect()
        runConnection = nil
    end
    
    logger:info("AutoQuest stopped")
end

function AutoQuest:GetStatus()
    return {
        initialized = isInitialized,
        running = isRunning,
        currentQuest = currentQuestId,
        currentSubQuestIndex = currentSubQuestIndex,
        totalSubQuests = #currentSubQuests,
        currentSubQuest = currentSubQuests[currentSubQuestIndex] and currentSubQuests[currentSubQuestIndex].DisplayName or nil
    }
end

function AutoQuest:Cleanup()
    self:Stop()
    
    if progressConnection then
        progressConnection:Disconnect()
        progressConnection = nil
    end
    
    -- Cleanup modules
    if AutoFish then
        AutoFish:Cleanup()
    end
    
    if AutoSellFish then
        AutoSellFish:Cleanup()
    end
    
    if AutoTeleportIsland then
        AutoTeleportIsland:Cleanup()
    end
    
    isInitialized = false
    logger:info("AutoQuest cleaned up")
end

return AutoQuest