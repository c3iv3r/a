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
local currentTrackedQuestKey = nil
local isRunning = false
local updateDebounceTimer = nil

-- Constants
local DEBOUNCE_TIME = 0.2
local EXCLUDED_QUEST = "Primary" -- Exclude Primary quests

-- ============================================================================
-- UTILITY FUNCTIONS
-- ============================================================================

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

local function getAvailableQuestKeys()
    local questKeys = {}
    
    for questKey, questGroup in pairs(QuestList) do
        -- Skip Primary quests
        if questKey == EXCLUDED_QUEST then
            continue
        end
        
        -- Only include quests with Forever array
        if questGroup.Forever and type(questGroup.Forever) == "table" and #questGroup.Forever > 0 then
            table.insert(questKeys, questKey)
        end
    end
    
    -- Sort alphabetically
    table.sort(questKeys)
    
    return questKeys
end

local function getQuestGroupProgress(questKey)
    if not playerData or not QuestList[questKey] then
        return nil
    end
    
    local questGroup = QuestList[questKey]
    local path = {questKey, "Available", "Forever", "Quests"}
    local questsArray = playerData:Get(path)
    
    if not questsArray or type(questsArray) ~= "table" then
        return nil
    end
    
    -- Build progress data for each quest
    local progressData = {}
    
    for index, questDefinition in ipairs(questGroup.Forever) do
        local displayName = questDefinition.DisplayName or "Quest " .. index
        local targetValue = getQuestValue(questDefinition)
        
        -- Find matching quest in player data
        local questProgress = nil
        for _, playerQuest in ipairs(questsArray) do
            if playerQuest.QuestId == index then
                questProgress = playerQuest
                break
            end
        end
        
        if questProgress then
            local current = questProgress.Progress or 0
            local isCompleted = questProgress.Redeemed or false
            local isReady = current >= targetValue and not isCompleted
            
            table.insert(progressData, {
                DisplayName = displayName,
                Current = current,
                Target = targetValue,
                IsCompleted = isCompleted,
                IsReady = isReady
            })
        else
            -- Quest not started yet
            table.insert(progressData, {
                DisplayName = displayName,
                Current = 0,
                Target = targetValue,
                IsCompleted = false,
                IsReady = false
            })
        end
    end
    
    return progressData
end

-- ============================================================================
-- UI UPDATE FUNCTIONS
-- ============================================================================

local function buildProgressText(questKey)
    local progressData = getQuestGroupProgress(questKey)
    
    if not progressData or #progressData == 0 then
        return string.format("%s: Not Available", questKey)
    end
    
    local lines = {}
    table.insert(lines, string.format("<b>%s Quest</b>", questKey))
    
    for _, quest in ipairs(progressData) do
        local statusIcon = ""
        local progressText = formatProgress(quest.Current, quest.Target)
        
        if quest.IsCompleted then
            statusIcon = " ✓"
            progressText = progressText .. " DONE"
        elseif quest.IsReady then
            statusIcon = " !"
            progressText = progressText .. " READY"
        end
        
        local line = string.format("• %s: %s%s", quest.DisplayName, progressText, statusIcon)
        table.insert(lines, line)
    end
    
    return table.concat(lines, "\n")
end

local function updateProgressLabel(controls, questKey)
    if not controls or not controls.progressLabel then
        return
    end
    
    local progressText = buildProgressText(questKey)
    controls.progressLabel:SetText(progressText)
end

local function debouncedUpdate(controls, questKey)
    if updateDebounceTimer then
        task.cancel(updateDebounceTimer)
    end
    
    updateDebounceTimer = task.delay(DEBOUNCE_TIME, function()
        updateProgressLabel(controls, questKey)
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
    
    currentTrackedQuestKey = nil
end

local function startTrackingQuest(controls, questKey)
    if not playerData or not questKey or not QuestList[questKey] then
        return
    end
    
    -- Stop previous tracking
    stopTrackingQuest()
    
    currentTrackedQuestKey = questKey
    
    -- Initial update
    updateProgressLabel(controls, questKey)
    
    -- Listen to quest array changes
    local questArrayPath = {questKey, "Available", "Forever", "Quests"}
    local arrayConnection = playerData:OnChange(questArrayPath, function(newValue)
        if not newValue then
            return
        end
        debouncedUpdate(controls, questKey)
    end)
    table.insert(questProgressListeners, arrayConnection)
    
    -- Listen to each quest's progress individually
    local questsArray = playerData:Get(questArrayPath)
    if questsArray and type(questsArray) == "table" then
        for arrayIndex, _ in ipairs(questsArray) do
            -- Listen to progress changes
            local progressPath = {questKey, "Available", "Forever", "Quests", arrayIndex, "Progress"}
            local progressConnection = playerData:OnChange(progressPath, function()
                debouncedUpdate(controls, questKey)
            end)
            table.insert(questProgressListeners, progressConnection)
            
            -- Listen to redeemed status changes
            local redeemedPath = {questKey, "Available", "Forever", "Quests", arrayIndex, "Redeemed"}
            local redeemedConnection = playerData:OnChange(redeemedPath, function()
                debouncedUpdate(controls, questKey)
            end)
            table.insert(questProgressListeners, redeemedConnection)
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
        warn("[AutoQuest] Missing required controls (questdropdown)")
        return false
    end
    
    if not controls.progressLabel then
        warn("[AutoQuest] Missing required controls (progressLabel)")
        return false
    end
    
    -- Get available quest keys
    local questKeys = getAvailableQuestKeys()
    
    if #questKeys == 0 then
        warn("[AutoQuest] No quests available")
        controls.progressLabel:SetText("No quests available")
        return false
    end
    
    -- Update dropdown with quest keys
    controls.questdropdown:SetValues(questKeys)
    
    -- Setup dropdown callback
    controls.questdropdown:OnChanged(function(value)
        if value and isRunning then
            startTrackingQuest(self.controls, value)
        end
    end)
    
    print("[AutoQuest] Initialized with", #questKeys, "quest groups")
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
        if self.controls and self.controls.progressLabel then
            self.controls.progressLabel:SetText("Error: Failed to load player data")
        end
        return
    end
    
    isRunning = true
    
    -- Listen to global data changes (for new quests being activated)
    local dataConnection = playerData:OnChange({}, function()
        if currentTrackedQuestKey and self.controls then
            debouncedUpdate(self.controls, currentTrackedQuestKey)
        end
    end)
    table.insert(connections, dataConnection)
    
    -- Start tracking selected quest if any
    local selectedValue = self.controls.questdropdown:GetActiveValues()
    if selectedValue and selectedValue[1] then
        startTrackingQuest(self.controls, selectedValue[1])
    else
        if self.controls.progressLabel then
            self.controls.progressLabel:SetText("Select a quest to track")
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
        self.controls.progressLabel:SetText("Tracking stopped")
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
    currentTrackedQuestKey = nil
    
    print("[AutoQuest] Cleaned up")
end

-- Refresh quest list (call this if quests are updated dynamically)
function AutoQuestFeature:RefreshQuests()
    if not self.controls or not self.controls.questdropdown then
        return
    end
    
    local questKeys = getAvailableQuestKeys()
    self.controls.questdropdown:SetValues(questKeys)
    
    print("[AutoQuest] Refreshed quest list:", #questKeys, "quest groups")
end

-- Get current tracked quest key
function AutoQuestFeature:GetTrackedQuestKey()
    return currentTrackedQuestKey
end

-- Check if module is running
function AutoQuestFeature:IsRunning()
    return isRunning
end

-- Manually trigger progress update for current quest
function AutoQuestFeature:UpdateProgress()
    if currentTrackedQuestKey and self.controls then
        updateProgressLabel(self.controls, currentTrackedQuestKey)
    end
end

return AutoQuestFeature