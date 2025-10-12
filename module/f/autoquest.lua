-- AutoQuest Feature Module
-- Real-time quest progress tracking with event-driven updates

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Replion = require(ReplicatedStorage.Packages.Replion)
local QuestUtility = require(ReplicatedStorage.Shared.Quests.QuestUtility)
local QuestList = require(ReplicatedStorage.Shared.Quests.QuestList)

local AutoQuestFeature = {}
AutoQuestFeature.__index = AutoQuestFeature

-- Module state
local playerData
local connections = {}
local questProgressListeners = {}
local currentTrackedQuest = nil
local isRunning = false
local updateDebounceTimer = nil

-- Constants
local DEBOUNCE_TIME = 0.2
local EXCLUDED_QUEST = "Primary" -- Exclude Primary quests

-- ============================================================================
-- UTILITY FUNCTIONS
-- ============================================================================

local function getQuestDisplayName(questKey, questData)
    if questData.DisplayName then
        return questData.DisplayName
    end
    return questKey
end

local function formatProgress(current, total)
    return string.format("%.1f / %d", math.floor(current * 10) / 10, total)
end

local function getQuestValue(questData)
    local value = questData.Arguments and questData.Arguments.value
    if typeof(value) == "function" then
        return value(playerData)
    elseif typeof(value) == "number" then
        return value
    end
    return 0
end

-- ============================================================================
-- QUEST DATA RETRIEVAL
-- ============================================================================

local function getAllAvailableQuests()
    local quests = {}
    
    for questKey, questGroup in pairs(QuestList) do
        -- Skip Primary quests
        if questKey == EXCLUDED_QUEST then
            continue
        end
        
        -- Check if quest group has Forever quests
        if questGroup.Forever and type(questGroup.Forever) == "table" then
            for index, questData in ipairs(questGroup.Forever) do
                local displayName = getQuestDisplayName(questKey, questData)
                table.insert(quests, {
                    Key = questKey,
                    Index = index,
                    DisplayName = displayName,
                    FullName = string.format("[%s] %s", questKey, displayName),
                    Data = questData
                })
            end
        end
    end
    
    return quests
end

local function getQuestProgress(questKey, questIndex)
    if not playerData then
        return nil
    end
    
    local path = {questKey, "Available", "Forever", "Quests"}
    local questsArray = playerData:Get(path)
    
    if not questsArray or type(questsArray) ~= "table" then
        return nil
    end
    
    -- Find quest by index (QuestId matches index)
    for _, quest in ipairs(questsArray) do
        if quest.QuestId == questIndex then
            return quest
        end
    end
    
    return nil
end

-- ============================================================================
-- UI UPDATE FUNCTIONS
-- ============================================================================

local function updateProgressLabel(controls, questInfo)
    if not controls or not controls.progressLabel then
        return
    end
    
    local questProgress = getQuestProgress(questInfo.Key, questInfo.Index)
    
    if not questProgress then
        controls.progressLabel:SetText("Progress: Not Started")
        return
    end
    
    local current = questProgress.Progress or 0
    local total = getQuestValue(questInfo.Data)
    local progressText = formatProgress(current, total)
    
    local statusText = ""
    if questProgress.Redeemed then
        statusText = " ✓ COMPLETED"
    elseif current >= total then
        statusText = " (Ready to claim!)"
    end
    
    controls.progressLabel:SetText(string.format("Progress: %s%s", progressText, statusText))
end

local function debouncedUpdate(controls, questInfo)
    if updateDebounceTimer then
        task.cancel(updateDebounceTimer)
    end
    
    updateDebounceTimer = task.delay(DEBOUNCE_TIME, function()
        updateProgressLabel(controls, questInfo)
        updateDebounceTimer = nil
    end)
end

-- ============================================================================
-- QUEST TRACKING
-- ============================================================================

local function stopTrackingQuest()
    -- Disconnect all progress listeners
    for _, connection in pairs(questProgressListeners) do
        if connection and connection.Disconnect then
            connection:Disconnect()
        end
    end
    table.clear(questProgressListeners)
    
    -- Cancel debounce timer
    if updateDebounceTimer then
        task.cancel(updateDebounceTimer)
        updateDebounceTimer = nil
    end
    
    currentTrackedQuest = nil
end

local function startTrackingQuest(controls, questInfo)
    if not playerData or not questInfo then
        return
    end
    
    -- Stop previous tracking
    stopTrackingQuest()
    
    currentTrackedQuest = questInfo
    
    -- Initial update
    updateProgressLabel(controls, questInfo)
    
    -- Listen to quest array changes (when quests are added/removed)
    local questArrayPath = {questInfo.Key, "Available", "Forever", "Quests"}
    local arrayConnection = playerData:OnChange(questArrayPath, function(newValue)
        if not newValue then
            return
        end
        debouncedUpdate(controls, questInfo)
    end)
    table.insert(questProgressListeners, arrayConnection)
    
    -- Try to find and listen to specific quest progress
    local questsArray = playerData:Get(questArrayPath)
    if questsArray and type(questsArray) == "table" then
        for arrayIndex, quest in ipairs(questsArray) do
            if quest.QuestId == questInfo.Index then
                -- Listen to this specific quest's progress
                local progressPath = {questInfo.Key, "Available", "Forever", "Quests", arrayIndex, "Progress"}
                local progressConnection = playerData:OnChange(progressPath, function()
                    debouncedUpdate(controls, questInfo)
                end)
                table.insert(questProgressListeners, progressConnection)
                
                -- Listen to redeemed status
                local redeemedPath = {questInfo.Key, "Available", "Forever", "Quests", arrayIndex, "Redeemed"}
                local redeemedConnection = playerData:OnChange(redeemedPath, function()
                    debouncedUpdate(controls, questInfo)
                end)
                table.insert(questProgressListeners, redeemedConnection)
                
                break
            end
        end
    end
end

-- ============================================================================
-- PUBLIC API
-- ============================================================================

function AutoQuestFeature:Init(controls)
    self.controls = controls
    
    -- Validate controls
    if not controls or not controls.questdropdown then
        warn("[AutoQuest] Missing required controls")
        return false
    end
    
    -- Get available quests
    local availableQuests = getAllAvailableQuests()
    local questNames = {}
    
    self.questMap = {}
    for _, questInfo in ipairs(availableQuests) do
        table.insert(questNames, questInfo.FullName)
        self.questMap[questInfo.FullName] = questInfo
    end
    
    -- Update dropdown values
    if #questNames > 0 then
        controls.questdropdown:SetValues(questNames)
    else
        warn("[AutoQuest] No quests available")
    end
    
    -- Setup dropdown callback
    controls.questdropdown:OnChanged(function(value)
        local questInfo = self.questMap[value]
        if questInfo and isRunning then
            startTrackingQuest(self.controls, questInfo)
        end
    end)
    
    print("[AutoQuest] Initialized with", #questNames, "quests")
    return true
end

function AutoQuestFeature:Start()
    if isRunning then
        warn("[AutoQuest] Already running")
        return
    end
    
    -- Wait for player data
    local success, result = pcall(function()
        playerData = Replion.Client:WaitReplion("Data", 10)
        return playerData ~= nil
    end)
    
    if not success or not result then
        warn("[AutoQuest] Failed to get player data:", result)
        return
    end
    
    isRunning = true
    
    -- Listen to data availability changes
    local dataConnection = playerData:OnChange({}, function()
        if currentTrackedQuest and self.controls then
            debouncedUpdate(self.controls, currentTrackedQuest)
        end
    end)
    table.insert(connections, dataConnection)
    
    -- Start tracking selected quest if any
    local selectedValue = self.controls.questdropdown:GetActiveValues()
    if selectedValue and selectedValue[1] then
        local questInfo = self.questMap[selectedValue[1]]
        if questInfo then
            startTrackingQuest(self.controls, questInfo)
        end
    end
    
    print("[AutoQuest] Started")
end

function AutoQuestFeature:Stop()
    if not isRunning then
        return
    end
    
    isRunning = false
    
    -- Stop tracking current quest
    stopTrackingQuest()
    
    -- Clear progress label
    if self.controls and self.controls.progressLabel then
        self.controls.progressLabel:SetText("Progress: Stopped")
    end
    
    print("[AutoQuest] Stopped")
end

function AutoQuestFeature:Cleanup()
    self:Stop()
    
    -- Disconnect all connections
    for _, connection in pairs(connections) do
        if connection and connection.Disconnect then
            connection:Disconnect()
        end
    end
    table.clear(connections)
    
    -- Clear state
    playerData = nil
    currentTrackedQuest = nil
    
    if self.questMap then
        table.clear(self.questMap)
    end
    
    print("[AutoQuest] Cleaned up")
end

-- Refresh quest list (call this if quests are updated dynamically)
function AutoQuestFeature:RefreshQuests()
    if not self.controls or not self.controls.questdropdown then
        return
    end
    
    local availableQuests = getAllAvailableQuests()
    local questNames = {}
    
    self.questMap = {}
    for _, questInfo in ipairs(availableQuests) do
        table.insert(questNames, questInfo.FullName)
        self.questMap[questInfo.FullName] = questInfo
    end
    
    self.controls.questdropdown:SetValues(questNames)
    print("[AutoQuest] Refreshed quest list:", #questNames, "quests")
end

-- Get current tracked quest info
function AutoQuestFeature:GetTrackedQuest()
    return currentTrackedQuest
end

-- Check if module is running
function AutoQuestFeature:IsRunning()
    return isRunning
end

return AutoQuestFeature