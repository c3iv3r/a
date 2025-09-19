-- ===========================
-- SAVEPOSITION - FIXED VERSION
-- Debug dan perbaikan untuk masalah persistence dan dropdown
-- ===========================

local SavePositionFeature = {}
SavePositionFeature.__index = SavePositionFeature

-- ===== Logger =====
local logger = _G.Logger and _G.Logger.new("SavePosition") or {
    debug = function(self, ...) print("[SavePosition DEBUG]", ...) end,
    info  = function(self, ...) print("[SavePosition INFO]", ...) end,
    warn  = function(self, ...) print("[SavePosition WARN]", ...) end,
    error = function(self, ...) print("[SavePosition ERROR]", ...) end,
}

-- ===== Services =====
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local LocalPlayer = Players.LocalPlayer

-- ===== Internal state =====
local isInitialized = false
local isRunning = false
local controls = {}
local savedPositions = {}
local selectedName = nil
local saveToggleEnabled = false
local saveAnchorCFrame = nil
local charAddedConn = nil
local heartbeatConn = nil

-- ===== SaveManager Integration - FIXED =====
local function registerSaveManagerParsers()
    if not _G.SaveManager then 
        logger:warn("SaveManager not found!")
        return 
    end
    
    logger:info("Registering SaveManager parsers...")
    
    -- Create dummy objects that SaveManager can recognize
    if not _G.SaveManager.Library then
        _G.SaveManager.Library = {}
    end
    if not _G.SaveManager.Library.Toggles then
        _G.SaveManager.Library.Toggles = {}
    end
    if not _G.SaveManager.Library.Options then
        _G.SaveManager.Library.Options = {}
    end
    
    -- Register dummy objects for SaveManager to track
    _G.SaveManager.Library.Toggles["SavePosition_Toggle"] = {
        Type = "SavePositionToggle",
        Value = saveToggleEnabled,
        SetValue = function(self, value)
            self.Value = value
            SavePositionFeature:SetSaveToggle(value)
        end
    }
    
    _G.SaveManager.Library.Options["SavePosition_List"] = {
        Type = "SavePositionList", 
        Value = selectedName,
        SetValue = function(self, value)
            self.Value = value
            SavePositionFeature:SetSelected(value)
        end,
        SetValues = function(self, values)
            -- Update dropdown values
            if controls.dropdown then
                controls.dropdown:SetValues(values)
            end
        end
    }
    
    -- SavePosition Toggle Parser
    _G.SaveManager.Parser.SavePositionToggle = {
        Save = function(idx, object)
            logger:info("Saving SavePosition toggle state:", saveToggleEnabled)
            local data = {
                type = "SavePositionToggle",
                idx = idx,
                enabled = saveToggleEnabled
            }
            
            if saveAnchorCFrame then
                data.anchorCFrame = {saveAnchorCFrame:GetComponents()}
                logger:info("Saving anchor position:", saveAnchorCFrame.Position)
            end
            
            return data
        end,
        Load = function(idx, data)
            logger:info("Loading SavePosition toggle data:", data)
            
            if data.enabled then
                saveToggleEnabled = true
                
                if data.anchorCFrame and #data.anchorCFrame >= 12 then
                    saveAnchorCFrame = CFrame.new(unpack(data.anchorCFrame))
                    logger:info("Restored anchor position:", saveAnchorCFrame.Position)
                    
                    -- Auto-restore setelah delay
                    task.spawn(function()
                        logger:info("Starting auto-restore sequence...")
                        task.wait(3.0) -- Wait for world to load
                        
                        if saveToggleEnabled and saveAnchorCFrame then
                            logger:info("Attempting to teleport to restored position...")
                            local success = SavePositionFeature:TeleportToCFrame(saveAnchorCFrame)
                            if success then
                                logger:info("Successfully restored to saved position!")
                                if _G.Noctis then
                                    _G.Noctis:Notify({
                                        Title = "Save Position",
                                        Description = "Restored to saved position!",
                                        Duration = 3
                                    })
                                end
                            else
                                logger:warn("Failed to restore saved position")
                            end
                        end
                    end)
                end
            else
                saveToggleEnabled = false
                saveAnchorCFrame = nil
            end
            
            -- Update GUI toggle
            if controls.toggle then
                controls.toggle:SetValue(saveToggleEnabled)
            end
        end,
    }
    
    -- SavePosition List Parser
    _G.SaveManager.Parser.SavePositionList = {
        Save = function(idx, object)
            logger:info("Saving", #savedPositions or 0, "saved positions")
            local positions = {}
            for name, cf in pairs(savedPositions) do
                positions[name] = {cf:GetComponents()}
            end
            
            return {
                type = "SavePositionList",
                idx = idx,
                positions = positions,
                selected = selectedName
            }
        end,
        Load = function(idx, data)
            logger:info("Loading saved positions data...")
            
            if data.positions and type(data.positions) == "table" then
                savedPositions = {}
                local count = 0
                
                for name, components in pairs(data.positions) do
                    if type(components) == "table" and #components >= 12 then
                        savedPositions[name] = CFrame.new(unpack(components))
                        count = count + 1
                    end
                end
                
                logger:info("Restored", count, "saved positions")
                
                if data.selected and savedPositions[data.selected] then
                    selectedName = data.selected
                end
                
                -- Update GUI dropdown
                if controls.dropdown then
                    local list = SavePositionFeature:GetSavedList()
                    controls.dropdown:SetValues(list)
                    if selectedName then
                        controls.dropdown:SetValue(selectedName)
                    end
                end
            end
        end,
    }
    
    logger:info("SaveManager parsers registered successfully!")
end

-- ===== Utilities =====
local function getHRP()
    local char = LocalPlayer.Character
    if not char then return nil end
    return char:FindFirstChild("HumanoidRootPart")
end

local function ensureCharacterReady(timeout)
    timeout = timeout or 10
    
    -- Wait for character
    local char = LocalPlayer.Character
    if not char then
        char = LocalPlayer.CharacterAdded:Wait()
    end
    
    local startTime = tick()
    while (tick() - startTime) < timeout do
        local hrp = char:FindFirstChild("HumanoidRootPart")
        local hum = char:FindFirstChildOfClass("Humanoid")
        
        if hrp and hum and hum.Health > 0 then
            return hrp
        end
        
        RunService.Heartbeat:Wait()
    end
    
    return char:FindFirstChild("HumanoidRootPart")
end

-- Improved teleport function
function SavePositionFeature:TeleportToCFrame(cf)
    logger:info("Attempting teleport to:", cf.Position)
    
    local hrp = ensureCharacterReady(8)
    if not hrp then
        logger:warn("Character not ready for teleport")
        return false
    end

    local success = pcall(function()
        local char = hrp.Parent
        local hum = char:FindFirstChildOfClass("Humanoid")
        
        -- Set physics state
        if hum then
            hum:ChangeState(Enum.HumanoidStateType.Physics)
        end
        
        -- Clear velocities and teleport with offset
        hrp.AssemblyLinearVelocity = Vector3.zero
        hrp.AssemblyAngularVelocity = Vector3.zero
        hrp.CFrame = cf + Vector3.new(0, 6, 0)
        
        -- Restore normal state
        task.wait(0.1)
        if hum and hum.Health > 0 then
            hum:ChangeState(Enum.HumanoidStateType.Running)
        end
    end)

    if success then
        logger:info("Teleport successful!")
        return true
    else
        logger:warn("Teleport failed")
        return false
    end
end

-- ===== API Methods =====

function SavePositionFeature:Init(guiControls)
    if isInitialized then return true end
    
    logger:info("Initializing SavePosition...")
    controls = guiControls or {}
    
    -- Register with SaveManager
    registerSaveManagerParsers()
    
    isInitialized = true
    logger:info("SavePosition initialized successfully")
    return true
end

function SavePositionFeature:Start()
    if not isInitialized then
        logger:warn("Cannot start - not initialized")
        return false
    end
    if isRunning then return true end
    
    isRunning = true
    logger:info("Starting SavePosition...")

    -- Character respawn handler
    if charAddedConn then charAddedConn:Disconnect() end
    charAddedConn = LocalPlayer.CharacterAdded:Connect(function()
        logger:info("Character respawned, checking for saved position...")
        if saveToggleEnabled and saveAnchorCFrame then
            task.spawn(function()
                task.wait(2.0)
                local success = self:TeleportToCFrame(saveAnchorCFrame)
                if success then
                    logger:info("Restored position after respawn")
                end
            end)
        end
    end)

    -- Guard loop
    if heartbeatConn then heartbeatConn:Disconnect() end
    heartbeatConn = RunService.Heartbeat:Connect(function()
        if not saveToggleEnabled or not saveAnchorCFrame then return end
        
        local hrp = getHRP()
        if not hrp then return end
        
        local pos = hrp.Position
        local anchorPos = saveAnchorCFrame.Position
        local distance = (pos - anchorPos).Magnitude
        
        -- Restore if drifted too far
        if distance > 120 or pos.Y < (anchorPos.Y - 40) then
            logger:debug("Player drifted, restoring position")
            self:TeleportToCFrame(saveAnchorCFrame)
        end
    end)

    return true
end

function SavePositionFeature:Stop()
    if not isRunning then return true end
    
    isRunning = false
    logger:info("Stopping SavePosition...")
    
    if charAddedConn then
        charAddedConn:Disconnect()
        charAddedConn = nil
    end
    if heartbeatConn then
        heartbeatConn:Disconnect()
        heartbeatConn = nil
    end
    
    return true
end

function SavePositionFeature:SetSelected(name)
    if type(name) == "string" and name ~= "" then
        if savedPositions[name] then
            selectedName = name
            logger:info("Selected position:", name)
            return true
        else
            logger:warn("Position not found:", name)
            selectedName = nil
            return false
        end
    end
    
    selectedName = nil
    return true
end

function SavePositionFeature:AddPosition(name)
    if type(name) ~= "string" or name:match("^%s*$") then
        logger:warn("Invalid position name")
        return false
    end
    
    local hrp = getHRP()
    if not hrp then
        logger:warn("Character not ready")
        return false
    end
    
    savedPositions[name] = hrp.CFrame
    selectedName = name
    
    logger:info("Added position:", name, "at", hrp.CFrame.Position)
    
    -- Update dropdown
    if controls.dropdown then
        local list = self:GetSavedList()
        controls.dropdown:SetValues(list)
        controls.dropdown:SetValue(name)
    end
    
    return true
end

function SavePositionFeature:RemovePosition(name)
    local targetName = name or selectedName
    if not targetName then
        logger:warn("No position to delete")
        return false
    end
    
    if not savedPositions[targetName] then
        logger:warn("Position not found:", targetName)
        return false
    end
    
    savedPositions[targetName] = nil
    
    if selectedName == targetName then
        selectedName = nil
    end
    
    -- Update dropdown
    if controls.dropdown then
        local list = self:GetSavedList()
        controls.dropdown:SetValues(list)
        controls.dropdown:SetValue(nil)
    end
    
    logger:info("Removed position:", targetName)
    return true
end

function SavePositionFeature:Teleport(name)
    local targetName = name or selectedName
    if not targetName then
        logger:warn("No position selected for teleport")
        return false
    end

    local cf = savedPositions[targetName]
    if not cf then
        logger:warn("Position not found:", targetName)
        return false
    end

    local success = self:TeleportToCFrame(cf)
    if success then
        logger:info("Teleported to:", targetName)
    else
        logger:warn("Teleport failed:", targetName)
    end
    
    return success
end

function SavePositionFeature:SetSaveToggle(state)
    local newState = not not state
    logger:info("Setting save toggle to:", newState)
    
    if newState then
        local hrp = getHRP()
        if not hrp then
            logger:warn("Character not ready for save toggle")
            return false
        end
        
        saveToggleEnabled = true
        saveAnchorCFrame = hrp.CFrame
        
        logger:info("Save position enabled at:", saveAnchorCFrame.Position)
        
        -- Immediate teleport to anchor position
        self:TeleportToCFrame(saveAnchorCFrame)
    else
        saveToggleEnabled = false
        saveAnchorCFrame = nil
        logger:info("Save position disabled")
    end
    
    return true
end

-- ===== Utility Methods =====

function SavePositionFeature:GetStatus()
    local list = {}
    for name in pairs(savedPositions) do
        table.insert(list, name)
    end
    table.sort(list)
    
    return {
        initialized = isInitialized,
        running = isRunning,
        saveToggleEnabled = saveToggleEnabled,
        selectedName = selectedName,
        count = #list,
        names = list,
        hasAnchor = saveAnchorCFrame ~= nil
    }
end

function SavePositionFeature:GetSavedList()
    local list = {}
    for name in pairs(savedPositions) do
        table.insert(list, name)
    end
    table.sort(list)
    return list
end

-- Debug function
function SavePositionFeature:Debug()
    local status = self:GetStatus()
    print("=== SavePosition Debug ===")
    print("Initialized:", status.initialized)
    print("Running:", status.running) 
    print("Save Toggle:", status.saveToggleEnabled)
    print("Has Anchor:", status.hasAnchor)
    print("Selected:", status.selectedName or "none")
    print("Total Positions:", status.count)
    
    if status.names and #status.names > 0 then
        print("Positions:")
        for i, name in ipairs(status.names) do
            print(string.format("  %d. %s", i, name))
        end
    end
    
    print("SaveManager Integration:")
    print("  SaveManager exists:", _G.SaveManager ~= nil)
    print("  Parsers registered:", _G.SaveManager and _G.SaveManager.Parser.SavePositionToggle ~= nil)
    print("========================")
end

-- Make debug globally accessible
_G.DebugSavePosition = function()
    if SavePositionFeature then
        SavePositionFeature:Debug()
    else
        print("SavePosition feature not loaded")
    end
end

return SavePositionFeature