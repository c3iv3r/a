-- ===========================
-- SAVE POSITION FEATURE - IMPROVED
-- Fully integrated with SaveManager for centralized persistence
-- Auto-restore on rejoin/respawn with proper position handling
-- Enhanced with delete functionality and better error handling
-- ===========================

local SavePositionFeature = {}
SavePositionFeature.__index = SavePositionFeature

-- ===== Logger (same pattern as AutoTeleportIsland) =====
local logger = _G.Logger and _G.Logger.new("SavePosition") or {
    debug = function() end,
    info  = function() end,
    warn  = function() end,
    error = function() end,
}

-- ===== Services =====
local Players       = game:GetService("Players")
local RunService    = game:GetService("RunService")
local LocalPlayer   = Players.LocalPlayer
local Workspace     = game:GetService("Workspace")

-- ===== Internal state =====
local isInitialized         = false
local isRunning             = false
local controls              = {}           -- GUI control refs
local savedPositions        = {}           -- map name -> CFrame (managed by SaveManager now)
local selectedName          = nil          -- current selected key in dropdown
local saveToggleEnabled     = false        -- Save Position toggle state
local saveAnchorCFrame      = nil          -- anchor cf captured by toggle
local charAddedConn         = nil
local heartbeatConn         = nil

-- ===== SaveManager Integration =====
-- Register SavePosition parsers with SaveManager
local function registerSaveManagerParsers()
    if not _G.SaveManager then return end
    
    -- SavePosition Toggle Parser
    _G.SaveManager.Parser.SavePositionToggle = {
        Save = function(idx, object)
            return {
                type = "SavePositionToggle",
                idx = idx,
                enabled = saveToggleEnabled,
                anchorCFrame = saveAnchorCFrame and {saveAnchorCFrame:GetComponents()} or nil
            }
        end,
        Load = function(idx, data)
            if data.enabled then
                saveToggleEnabled = true
                if data.anchorCFrame and #data.anchorCFrame >= 12 then
                    local cf = CFrame.new(unpack(data.anchorCFrame))
                    saveAnchorCFrame = cf
                    logger:info("Loaded SavePosition anchor from config")
                    
                    -- Auto-restore position after small delay for character to be ready
                    task.spawn(function()
                        task.wait(5.0) -- Give more time for character and world to load
                        if saveToggleEnabled and saveAnchorCFrame then
                            SavePositionFeature:TeleportToCFrame(saveAnchorCFrame)
                            logger:info("Auto-restored to saved position after rejoin")
                        end
                    end)
                end
            else
                saveToggleEnabled = false
                saveAnchorCFrame = nil
            end
            
            -- Update GUI toggle if exists
            if _G.SaveManager and _G.SaveManager.Library then
                local toggle = _G.SaveManager.Library.Toggles["SavePosition_Toggle"]
                if toggle and toggle.Value ~= saveToggleEnabled then
                    toggle:SetValue(saveToggleEnabled)
                end
            end
        end,
    }
    
    -- SavePosition List Parser
    _G.SaveManager.Parser.SavePositionList = {
        Save = function(idx, object)
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
            if data.positions and type(data.positions) == "table" then
                savedPositions = {}
                for name, components in pairs(data.positions) do
                    if #components >= 12 then
                        savedPositions[name] = CFrame.new(unpack(components))
                    end
                end
                
                if data.selected and savedPositions[data.selected] then
                    selectedName = data.selected
                end
                
                -- Update GUI dropdown if exists
                if _G.SaveManager and _G.SaveManager.Library then
                    local dropdown = _G.SaveManager.Library.Options["SavePosition_List"]
                    if dropdown then
                        local list = SavePositionFeature:GetSavedList()
                        dropdown:SetValues(list)
                        if selectedName and savedPositions[selectedName] then
                            dropdown:SetValue(selectedName)
                        end
                    end
                end
                
                logger:info("Loaded", table.getn(savedPositions) or 0, "saved positions from config")
            end
        end,
    }
    
    logger:info("Registered SavePosition parsers with SaveManager")
end

-- ===== Utilities =====
local function getHRP()
    local char = LocalPlayer.Character
    if not char then return nil end
    return char:FindFirstChild("HumanoidRootPart")
end

local function ensureCharacterReady(timeout)
    timeout = timeout or 10
    local char = LocalPlayer.Character or LocalPlayer.CharacterAdded:Wait()
    local t0 = os.clock()
    while (os.clock() - t0) < timeout do
        local hrp = char:FindFirstChild("HumanoidRootPart")
        local hum = char:FindFirstChildOfClass("Humanoid")
        if hrp and hum and hum.Health > 0 then
            return hrp
        end
        RunService.Heartbeat:Wait()
    end
    return getHRP()
end

-- Hard teleport with +Y offset, zero velocity
function SavePositionFeature:TeleportToCFrame(cf)
    local hrp = ensureCharacterReady(8)
    if not hrp then
        logger:warn("HumanoidRootPart not ready for teleport")
        return false
    end

    local ok = pcall(function()
        local target = cf + Vector3.new(0, 6, 0)
        local char   = hrp.Parent
        local hum    = char and char:FindFirstChildOfClass("Humanoid")

        -- Set physics state to avoid conflicts
        if hum then 
            hum:ChangeState(Enum.HumanoidStateType.Physics) 
        end
        
        -- Clear velocities and teleport
        hrp.AssemblyLinearVelocity = Vector3.zero
        hrp.AssemblyAngularVelocity = Vector3.zero
        hrp.CFrame = target
        
        -- Restore normal state after brief delay
        task.delay(0.2, function()
            if hum and hum.Health > 0 then
                hum:ChangeState(Enum.HumanoidStateType.RunningNoPhysics)
                task.delay(0.05, function()
                    if hum and hum.Health > 0 then
                        hum:ChangeState(Enum.HumanoidStateType.Running)
                    end
                end)
            end
        end)
    end)

    if not ok then
        logger:warn("Teleport operation failed")
        return false
    end
    
    return true
end

-- ===== Public API =====

function SavePositionFeature:Init(guiControls)
    if isInitialized then return true end
    controls = guiControls or {}
    
    -- Register parsers with SaveManager
    registerSaveManagerParsers()
    
    isInitialized = true
    logger:info("Initialized SavePositionFeature with SaveManager integration")
    return true
end

function SavePositionFeature:Start()
    if not isInitialized then
        logger:warn("Start called before Init")
        return false
    end
    if isRunning then return true end
    isRunning = true

    -- Handle respawn/rejoin restoration
    if charAddedConn then charAddedConn:Disconnect() end
    charAddedConn = LocalPlayer.CharacterAdded:Connect(function()
        if saveToggleEnabled and saveAnchorCFrame then
            task.spawn(function()
                -- Wait longer for character and world to be fully loaded
                task.wait(3.0)
                ensureCharacterReady(8)
                local success = self:TeleportToCFrame(saveAnchorCFrame)
                if success then
                    logger:info("Restored save position after respawn")
                else
                    logger:warn("Failed to restore save position after respawn")
                end
            end)
        end
    end)

    -- Guard loop for save position toggle
    if heartbeatConn then heartbeatConn:Disconnect() end
    heartbeatConn = RunService.Heartbeat:Connect(function()
        if not saveToggleEnabled or not saveAnchorCFrame then return end
        local hrp = getHRP()
        if not hrp then return end
        
        local pos = hrp.Position
        local anchorPos = saveAnchorCFrame.Position
        local dist = (pos - anchorPos).Magnitude
        
        -- Teleport back if player drifted too far or fell
        if dist > 150 or pos.Y < (anchorPos.Y - 50) then
            self:TeleportToCFrame(saveAnchorCFrame)
            logger:debug("Restored player to save position (drift detected)")
        end
    end)

    logger:info("Started SavePositionFeature")
    return true
end

function SavePositionFeature:Stop()
    if not isRunning then return true end
    isRunning = false
    
    if charAddedConn then 
        charAddedConn:Disconnect() 
        charAddedConn = nil 
    end
    if heartbeatConn then 
        heartbeatConn:Disconnect() 
        heartbeatConn = nil 
    end
    
    logger:info("Stopped SavePositionFeature")
    return true
end

function SavePositionFeature:Cleanup()
    self:Stop()
    controls = {}
    savedPositions = {}
    saveToggleEnabled = false
    saveAnchorCFrame = nil
    selectedName = nil
    isInitialized = false
    logger:info("Cleanup SavePositionFeature completed")
end

-- ===== GUI-facing methods =====

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
    return true -- Allow deselection
end

function SavePositionFeature:AddPosition(name)
    if type(name) ~= "string" or name:match("^%s*$") then
        logger:warn("AddPosition requires a valid name")
        if _G.WindUI then
            _G.WindUI:Notify({
                Title = "Add Position Failed",
                Content = "Please enter a valid position name.",
                Icon = "alert-triangle",
                Duration = 3
            })
        end
        return false
    end
    
    local hrp = getHRP()
    if not hrp then
        logger:warn("Cannot add position: Character not ready")
        if _G.WindUI then
            _G.WindUI:Notify({
                Title = "Add Position Failed", 
                Content = "Character not ready. Please try again.",
                Icon = "alert-triangle",
                Duration = 3
            })
        end
        return false
    end
    
    savedPositions[name] = hrp.CFrame
    selectedName = name
    
    -- Update GUI dropdown
    if _G.SaveManager and _G.SaveManager.Library then
        local dropdown = _G.SaveManager.Library.Options["SavePosition_List"]
        if dropdown then
            local list = self:GetSavedList()
            dropdown:SetValues(list)
            dropdown:SetValue(name)
        end
    end
    
    if _G.WindUI then
        _G.WindUI:Notify({
            Title = "Position Added",
            Content = ("Successfully saved '%s'"):format(name),
            Icon = "bookmark-plus",
            Duration = 2
        })
    end
    
    logger:info("Position added:", name)
    return true
end

function SavePositionFeature:RemovePosition(name)
    local targetName = name or selectedName
    if not targetName then
        logger:warn("RemovePosition: No position specified")
        if _G.WindUI then
            _G.WindUI:Notify({
                Title = "Delete Failed",
                Content = "Please select a position to delete.",
                Icon = "alert-triangle",
                Duration = 3
            })
        end
        return false
    end
    
    if not savedPositions[targetName] then
        logger:warn("RemovePosition: Position not found:", targetName)
        if _G.WindUI then
            _G.WindUI:Notify({
                Title = "Delete Failed",
                Content = ("Position '%s' not found."):format(targetName),
                Icon = "alert-triangle", 
                Duration = 3
            })
        end
        return false
    end
    
    savedPositions[targetName] = nil
    
    -- Clear selection if deleted item was selected
    if selectedName == targetName then
        selectedName = nil
    end
    
    -- Update GUI dropdown
    if _G.SaveManager and _G.SaveManager.Library then
        local dropdown = _G.SaveManager.Library.Options["SavePosition_List"]
        if dropdown then
            local list = self:GetSavedList()
            dropdown:SetValues(list)
            dropdown:SetValue(selectedName) -- Will be nil if we deleted selected
        end
    end
    
    if _G.WindUI then
        _G.WindUI:Notify({
            Title = "Position Deleted",
            Content = ("Removed '%s' successfully"):format(targetName),
            Icon = "trash-2",
            Duration = 2
        })
    end
    
    logger:info("Position removed:", targetName)
    return true
end

function SavePositionFeature:Teleport(name)
    local targetName = name or selectedName
    if not targetName then
        logger:warn("Teleport: No position selected")
        if _G.WindUI then
            _G.WindUI:Notify({
                Title = "Teleport Failed",
                Content = "Please select a saved position first.",
                Icon = "alert-triangle",
                Duration = 3
            })
        end
        return false
    end

    local cf = savedPositions[targetName]
    if not cf then
        logger:warn("Teleport: Position not found:", targetName)
        if _G.WindUI then
            _G.WindUI:Notify({
                Title = "Teleport Failed",
                Content = ("Position '%s' not found."):format(targetName),
                Icon = "alert-triangle",
                Duration = 3
            })
        end
        return false
    end

    local success = self:TeleportToCFrame(cf)
    if success then
        if _G.WindUI then
            _G.WindUI:Notify({
                Title = "Teleport Success",
                Content = ("Teleported to '%s'"):format(targetName),
                Icon = "map-pin",
                Duration = 2
            })
        end
        logger:info("Teleported to:", targetName)
    else
        if _G.WindUI then
            _G.WindUI:Notify({
                Title = "Teleport Failed", 
                Content = ("Could not teleport to '%s'"):format(targetName),
                Icon = "x",
                Duration = 3
            })
        end
        logger:warn("Teleport failed:", targetName)
    end
    return success
end

function SavePositionFeature:SetSaveToggle(state)
    local newState = not not state
    
    if newState then
        local hrp = getHRP()
        if not hrp then
            logger:warn("SaveToggle ON but character not ready")
            if _G.WindUI then
                _G.WindUI:Notify({
                    Title = "Save Position Failed",
                    Content = "Character not ready. Please try again.",
                    Icon = "alert-triangle",
                    Duration = 3
                })
            end
            return false
        end
        
        saveToggleEnabled = true
        saveAnchorCFrame = hrp.CFrame
        
        -- Immediate teleport to "anchor" the position
        self:TeleportToCFrame(saveAnchorCFrame)
        
        if _G.WindUI then
            _G.WindUI:Notify({
                Title = "Save Position Enabled",
                Content = "Current position saved and will be restored on rejoin.",
                Icon = "anchor",
                Duration = 3
            })
        end
        
        logger:info("Save Position enabled; anchor captured at:", saveAnchorCFrame.Position)
    else
        saveToggleEnabled = false
        saveAnchorCFrame = nil
        
        if _G.WindUI then
            _G.WindUI:Notify({
                Title = "Save Position Disabled",
                Content = "Position saving turned off.",
                Icon = "anchor",
                Duration = 2
            })
        end
        
        logger:info("Save Position disabled")
    end
    
    return true
end

-- ===== Status and utility methods =====

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

-- Force save current state to SaveManager config
function SavePositionFeature:ForceSave()
    if _G.SaveManager then
        -- Trigger save by creating dummy objects that our parsers will handle
        _G.SaveManager.Library = _G.SaveManager.Library or {}
        _G.SaveManager.Library.Toggles = _G.SaveManager.Library.Toggles or {}
        _G.SaveManager.Library.Options = _G.SaveManager.Library.Options or {}
        
        -- Create temporary objects for parsing
        _G.SaveManager.Library.Toggles["SavePosition_Toggle"] = { 
            Type = "SavePositionToggle", 
            Value = saveToggleEnabled 
        }
        _G.SaveManager.Library.Options["SavePosition_List"] = { 
            Type = "SavePositionList", 
            Value = selectedName 
        }
        
        logger:info("SavePosition state prepared for SaveManager")
        return true
    end
    return false
end

return SavePositionFeature