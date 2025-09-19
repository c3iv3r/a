-- ===========================
-- SAVE POSITION FEATURE
-- Saves current player position when toggled on and auto-teleports back on respawn/rejoin
-- Uses SaveManager for persistent storage across sessions
-- ===========================

local SavePosition = {}
SavePosition.__index = SavePosition

local logger = _G.Logger and _G.Logger.new("SavePosition") or {
    debug = function() end,
    info = function() end,
    warn = function() end,
    error = function() end
}

-- Services
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local LocalPlayer = Players.LocalPlayer

-- Feature state
local isInitialized = false
local isEnabled = false
local controls = {}
local savedPosition = nil
local connections = {}

-- Storage key for SaveManager
local STORAGE_KEY = "SavePosition_Data"

-- ===========================
-- CORE FUNCTIONS
-- ===========================

-- Save current player position
function SavePosition:SaveCurrentPosition()
    if not LocalPlayer.Character then
        logger:warn("No character found to save position")
        return false
    end
    
    local humanoidRootPart = LocalPlayer.Character:FindFirstChild("HumanoidRootPart")
    if not humanoidRootPart then
        logger:warn("HumanoidRootPart not found")
        return false
    end
    
    savedPosition = {
        position = humanoidRootPart.Position,
        cframe = humanoidRootPart.CFrame,
        timestamp = tick()
    }
    
    -- Save to persistent storage using SaveManager
    self:SaveToStorage()
    
    logger:info("Position saved:", savedPosition.position)
    
    -- Notify user
    if _G.WindUI then
        _G.WindUI:Notify({
            Title = "Position Saved",
            Content = string.format("Saved at (%.1f, %.1f, %.1f)", 
                savedPosition.position.X, 
                savedPosition.position.Y, 
                savedPosition.position.Z),
            Icon = "map-pin",
            Duration = 3
        })
    end
    
    return true
end

-- Teleport to saved position
function SavePosition:TeleportToSavedPosition()
    if not savedPosition then
        logger:warn("No saved position found")
        return false
    end
    
    if not LocalPlayer.Character then
        logger:warn("No character found for teleportation")
        return false
    end
    
    local humanoidRootPart = LocalPlayer.Character:FindFirstChild("HumanoidRootPart")
    if not humanoidRootPart then
        logger:warn("HumanoidRootPart not found for teleportation")
        return false
    end
    
    local success = pcall(function()
        humanoidRootPart.CFrame = savedPosition.cframe
    end)
    
    if success then
        logger:info("Teleported to saved position:", savedPosition.position)
        
        if _G.WindUI then
            _G.WindUI:Notify({
                Title = "Position Restored",
                Content = string.format("Teleported to (%.1f, %.1f, %.1f)", 
                    savedPosition.position.X, 
                    savedPosition.position.Y, 
                    savedPosition.position.Z),
                Icon = "navigation",
                Duration = 3
            })
        end
        return true
    else
        logger:warn("Failed to teleport to saved position")
        return false
    end
end

-- ===========================
-- STORAGE FUNCTIONS
-- ===========================

-- Save position data to persistent storage
function SavePosition:SaveToStorage()
    if not savedPosition then return end
    
    local data = {
        enabled = isEnabled,
        position = {
            x = savedPosition.position.X,
            y = savedPosition.position.Y,
            z = savedPosition.position.Z
        },
        cframe = {
            x = savedPosition.cframe.X,
            y = savedPosition.cframe.Y,
            z = savedPosition.cframe.Z,
            r00 = savedPosition.cframe.R00, r01 = savedPosition.cframe.R01, r02 = savedPosition.cframe.R02,
            r10 = savedPosition.cframe.R10, r11 = savedPosition.cframe.R11, r12 = savedPosition.cframe.R12,
            r20 = savedPosition.cframe.R20, r21 = savedPosition.cframe.R21, r22 = savedPosition.cframe.R22
        },
        timestamp = savedPosition.timestamp
    }
    
    -- Use SaveManager if available
    if _G.SaveManager and _G.SaveManager.Library then
        -- Store in library options for SaveManager to handle
        if not _G.SaveManager.Library.Options[STORAGE_KEY] then
            -- Create a dummy option to store our data
            _G.SaveManager.Library.Options[STORAGE_KEY] = {
                Type = "SavePosition",
                Value = data
            }
        else
            _G.SaveManager.Library.Options[STORAGE_KEY].Value = data
        end
    end
    
    logger:debug("Position data saved to storage")
end

-- Load position data from persistent storage
function SavePosition:LoadFromStorage()
    if not _G.SaveManager or not _G.SaveManager.Library then
        logger:debug("SaveManager not available, skipping load")
        return false
    end
    
    local option = _G.SaveManager.Library.Options[STORAGE_KEY]
    if not option or not option.Value then
        logger:debug("No saved position data found")
        return false
    end
    
    local data = option.Value
    if not data.position or not data.cframe then
        logger:warn("Invalid saved position data")
        return false
    end
    
    -- Restore saved position
    savedPosition = {
        position = Vector3.new(data.position.x, data.position.y, data.position.z),
        cframe = CFrame.new(
            data.cframe.x, data.cframe.y, data.cframe.z,
            data.cframe.r00, data.cframe.r01, data.cframe.r02,
            data.cframe.r10, data.cframe.r11, data.cframe.r12,
            data.cframe.r20, data.cframe.r21, data.cframe.r22
        ),
        timestamp = data.timestamp or tick()
    }
    
    -- Restore enabled state
    local wasEnabled = data.enabled or false
    if wasEnabled and controls.toggle then
        controls.toggle:SetValue(true)
    end
    
    logger:info("Position data loaded from storage:", savedPosition.position)
    return true
end

-- ===========================
-- EVENT HANDLERS
-- ===========================

-- Handle character respawning
function SavePosition:OnCharacterAdded(character)
    if not isEnabled or not savedPosition then return end
    
    logger:info("Character respawned, waiting for HumanoidRootPart...")
    
    -- Wait for HumanoidRootPart to load
    local humanoidRootPart = character:WaitForChild("HumanoidRootPart", 10)
    if humanoidRootPart then
        -- Small delay to ensure character is fully loaded
        task.wait(1)
        self:TeleportToSavedPosition()
    else
        logger:warn("HumanoidRootPart not found after character respawn")
    end
end

-- ===========================
-- PUBLIC INTERFACE
-- ===========================

-- Initialize the feature
function SavePosition:Init(guiControls)
    if isInitialized then
        logger:warn("SavePosition already initialized")
        return true
    end
    
    controls = guiControls or {}
    
    -- Load saved data
    self:LoadFromStorage()
    
    -- Connect to character respawn events
    if LocalPlayer.CharacterAdded then
        connections.characterAdded = LocalPlayer.CharacterAdded:Connect(function(character)
            self:OnCharacterAdded(character)
        end)
    end
    
    -- Handle current character if it exists
    if LocalPlayer.Character then
        task.spawn(function()
            self:OnCharacterAdded(LocalPlayer.Character)
        end)
    end
    
    isInitialized = true
    logger:info("SavePosition initialized successfully")
    
    return true
end

-- Start the feature (toggle on)
function SavePosition:Start(options)
    if not isInitialized then
        logger:warn("SavePosition not initialized")
        return false
    end
    
    isEnabled = true
    
    -- Save current position immediately when enabled
    self:SaveCurrentPosition()
    
    logger:info("SavePosition started")
    return true
end

-- Stop the feature (toggle off)
function SavePosition:Stop()
    if not isInitialized then
        logger:warn("SavePosition not initialized")
        return false
    end
    
    isEnabled = false
    
    -- Clear saved position when disabled
    savedPosition = nil
    
    -- Update storage
    self:SaveToStorage()
    
    logger:info("SavePosition stopped and cleared")
    
    if _G.WindUI then
        _G.WindUI:Notify({
            Title = "Position Cleared",
            Content = "Saved position has been cleared",
            Icon = "trash-2",
            Duration = 2
        })
    end
    
    return true
end

-- Get current status
function SavePosition:GetStatus()
    return {
        initialized = isInitialized,
        enabled = isEnabled,
        hasSavedPosition = savedPosition ~= nil,
        savedPosition = savedPosition and {
            x = savedPosition.position.X,
            y = savedPosition.position.Y,
            z = savedPosition.position.Z,
            timestamp = savedPosition.timestamp
        } or nil
    }
end

-- Manual teleport to saved position (if needed)
function SavePosition:TeleportNow()
    if not isEnabled then
        logger:warn("SavePosition is disabled")
        return false
    end
    
    return self:TeleportToSavedPosition()
end

-- Update saved position manually
function SavePosition:UpdatePosition()
    if not isEnabled then
        logger:warn("SavePosition is disabled")
        return false
    end
    
    return self:SaveCurrentPosition()
end

-- Cleanup function
function SavePosition:Cleanup()
    logger:info("Cleaning up SavePosition...")
    
    -- Disconnect all connections
    for name, connection in pairs(connections) do
        if connection and connection.Disconnect then
            connection:Disconnect()
        end
    end
    connections = {}
    
    -- Reset state
    isInitialized = false
    isEnabled = false
    controls = {}
    savedPosition = nil
    
    logger:info("SavePosition cleanup completed")
end

-- ===========================
-- SAVEMANAGER INTEGRATION
-- ===========================

-- Custom parser for SaveManager integration
if _G.SaveManager and _G.SaveManager.Parser then
    _G.SaveManager.Parser.SavePosition = {
        Save = function(idx, object)
            return {
                type = "SavePosition",
                idx = idx,
                value = object.Value
            }
        end,
        Load = function(idx, data)
            local savePos = _G.SavePosition or SavePosition
            if savePos and data.value then
                -- Restore the saved position data
                if savePos.LoadFromStorage then
                    savePos:LoadFromStorage()
                end
            end
        end
    }
end

return SavePosition