-- ===========================
-- AUTO RECONNECT FEATURE
-- Automatically reconnects to the same PlaceId when player disconnects
-- ===========================

local AutoReconnect = {}
AutoReconnect.__index = AutoReconnect

local logger = _G.Logger and _G.Logger.new("AutoReconnect") or {
    debug = function() end,
    info = function() end,
    warn = function() end,
    error = function() end
}

-- Services
local Players = game:GetService("Players")
local TeleportService = game:GetService("TeleportService")
local GuiService = game:GetService("GuiService")

-- Feature state
local isInitialized = false
local controls = {}
local isEnabled = false
local connection = nil

-- Store current place info
local currentPlaceId = game.PlaceId

-- Handle disconnection and reconnect
function AutoReconnect:HandleDisconnect()
    if not isEnabled then
        return
    end
    
    logger:info("Player disconnected, attempting to reconnect to PlaceId:", currentPlaceId)
    
    local success, errorMessage = pcall(function()
        TeleportService:Teleport(currentPlaceId, Players.LocalPlayer)
    end)
    
    if success then
        logger:info("Reconnection initiated successfully")
    else
        logger:warn("Failed to reconnect:", errorMessage)
    end
end

-- Start auto reconnect monitoring
function AutoReconnect:Start()
    if not isInitialized then
        logger:warn("Feature not initialized")
        return false
    end
    
    if isEnabled then
        logger:warn("AutoReconnect already enabled")
        return true
    end
    
    isEnabled = true
    
    -- Connect to player removing event (when player disconnects)
    connection = Players.PlayerRemoving:Connect(function(player)
        if player == Players.LocalPlayer then
            self:HandleDisconnect()
        end
    end)
    
    -- Also connect to GuiService ErrorMessageChanged for additional disconnect detection
    local errorConnection
    errorConnection = GuiService:GetPropertyChangedSignal("ErrorMessageChanged"):Connect(function()
        if GuiService.ErrorMessage ~= "" and isEnabled then
            -- Small delay to ensure the error is a disconnect
            wait(0.5)
            if GuiService.ErrorMessage ~= "" then
                logger:info("Error detected, attempting reconnect:", GuiService.ErrorMessage)
                self:HandleDisconnect()
            end
        end
    end)
    
    logger:info("AutoReconnect started for PlaceId:", currentPlaceId)
    
    if _G.Noctis then
        _G.Noctis:Notify({
            Title = "Auto Reconnect",
            Description = "Auto Reconnect enabled",
            Duration = 2
        })
    end
    
    return true
end

-- Stop auto reconnect monitoring
function AutoReconnect:Stop()
    if not isEnabled then
        logger:warn("AutoReconnect already disabled")
        return true
    end
    
    isEnabled = false
    
    -- Disconnect the connection
    if connection then
        connection:Disconnect()
        connection = nil
    end
    
    logger:info("AutoReconnect stopped")
    
    if _G.Noctis then
        _G.Noctis:Notify({
            Title = "Auto Reconnect",
            Description = "Auto Reconnect disabled",
            Duration = 2
        })
    end
    
    return true
end

-- Check if feature is enabled
function AutoReconnect:IsEnabled()
    return isEnabled
end

-- Get current place info
function AutoReconnect:GetPlaceInfo()
    return {
        placeId = currentPlaceId,
        jobId = game.JobId,
        playerCount = #Players:GetPlayers()
    }
end

-- Init function called by GUI
function AutoReconnect:Init(guiControls)
    controls = guiControls or {}
    currentPlaceId = game.PlaceId
    isInitialized = true
    
    logger:info("Initialized successfully")
    logger:info("Monitoring PlaceId:", currentPlaceId)
    
    return true
end

-- Get status
function AutoReconnect:GetStatus()
    return {
        initialized = isInitialized,
        enabled = isEnabled,
        placeId = currentPlaceId,
        hasConnection = connection ~= nil
    }
end

-- Cleanup function
function AutoReconnect:Cleanup()
    logger:info("Cleaning up...")
    
    if isEnabled then
        self:Stop()
    end
    
    controls = {}
    isInitialized = false
end

return AutoReconnect