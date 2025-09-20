-- ===========================
-- COPY JOIN SERVER FEATURE
-- Provides functionality to copy current server JobId and join specific servers
-- Compatible with the main GUI system
-- ===========================

local CopyJoinServer = {}
CopyJoinServer.__index = CopyJoinServer

local logger = _G.Logger and _G.Logger.new("CopyJoinServer") or {
    debug = function() end,
    info = function() end,
    warn = function() end,
    error = function() end
}

-- Services
local Players = game:GetService("Players")
local TeleportService = game:GetService("TeleportService")
local HttpService = game:GetService("HttpService")

-- Feature state
local isInitialized = false
local controls = {}
local currentJobId = ""
local targetJobId = ""

-- Get current server JobId
function CopyJoinServer:GetCurrentJobId()
    return game.JobId
end

-- Get current place ID
function CopyJoinServer:GetCurrentPlaceId()
    return game.PlaceId
end

-- Copy current JobId to clipboard
function CopyJoinServer:CopyCurrentJobId()
    local jobId = self:GetCurrentJobId()
    
    if typeof(setclipboard) == "function" then
        setclipboard(jobId)
        logger:info("JobId copied to clipboard:", jobId)
        
        -- Notify user
        if _G.Noctis then
            _G.Noctis:Notify({
                Title = "Copy Join Server",
                Description = "JobId copied to clipboard!",
                Duration = 2
            })
        end
        return true, jobId
    else
        logger:warn("Clipboard not available")
        if _G.Noctis then
            _G.Noctis:Notify({
                Title = "Copy Join Server",
                Description = "Clipboard not available",
                Duration = 3
            })
        end
        return false, "Clipboard not available"
    end
end

-- Set target JobId from input
function CopyJoinServer:SetTargetJobId(jobId)
    if not jobId or jobId == "" then
        logger:warn("Invalid JobId provided")
        return false
    end
    
    targetJobId = jobId
    logger:info("Target JobId set to:", jobId)
    return true
end

-- Join server by JobId
function CopyJoinServer:JoinServer(jobId)
    local targetId = jobId or targetJobId
    
    if not targetId or targetId == "" then
        logger:warn("No JobId provided")
        if _G.Noctis then
            _G.Noctis:Notify({
                Title = "Copy Join Server",
                Description = "Please enter a valid JobId",
                Duration = 3
            })
        end
        return false
    end
    
    -- Validate JobId format (basic check)
    if string.len(targetId) < 10 then
        logger:warn("Invalid JobId format:", targetId)
        if _G.Noctis then
            _G.Noctis:Notify({
                Title = "Copy Join Server",
                Description = "Invalid JobId format",
                Duration = 3
            })
        end
        return false
    end
    
    logger:info("Attempting to join server:", targetId)
    
    local success, errorMessage = pcall(function()
        TeleportService:TeleportToPlaceInstance(
            self:GetCurrentPlaceId(),
            targetId,
            Players.LocalPlayer
        )
    end)
    
    if success then
        logger:info("Teleport request sent successfully")
        if _G.Noctis then
            _G.Noctis:Notify({
                Title = "Copy Join Server",
                Description = "Joining server...",
                Duration = 3
            })
        end
        return true
    else
        logger:warn("Failed to join server:", errorMessage)
        if _G.Noctis then
            _G.Noctis:Notify({
                Title = "Copy Join Server",
                Description = "Failed to join server: " .. tostring(errorMessage),
                Duration = 4
            })
        end
        return false
    end
end

-- Get server information
function CopyJoinServer:GetServerInfo()
    return {
        currentJobId = self:GetCurrentJobId(),
        currentPlaceId = self:GetCurrentPlaceId(),
        targetJobId = targetJobId,
        playerCount = #Players:GetPlayers()
    }
end

-- Init function called by GUI
function CopyJoinServer:Init(guiControls)
    controls = guiControls or {}
    currentJobId = self:GetCurrentJobId()
    isInitialized = true
    
    logger:info("Initialized successfully")
    logger:info("Current JobId:", currentJobId)
    logger:info("Current PlaceId:", self:GetCurrentPlaceId())
    
    return true
end

-- Start function (for consistency with other features)
function CopyJoinServer:Start(options)
    if not isInitialized then
        logger:warn("Feature not initialized")
        return false
    end
    
    logger:info("CopyJoinServer started")
    return true
end

-- Stop function (for consistency with other features)
function CopyJoinServer:Stop()
    if not isInitialized then
        return false
    end
    
    logger:info("CopyJoinServer stopped")
    return true
end

-- Get status
function CopyJoinServer:GetStatus()
    return {
        initialized = isInitialized,
        currentJobId = self:GetCurrentJobId(),
        currentPlaceId = self:GetCurrentPlaceId(),
        targetJobId = targetJobId,
        hasClipboard = typeof(setclipboard) == "function"
    }
end

-- Cleanup function
function CopyJoinServer:Cleanup()
    logger:info("Cleaning up...")
    controls = {}
    targetJobId = ""
    isInitialized = false
end

-- Update GUI input value when setting target JobId
function CopyJoinServer:UpdateInputValue()
    if controls and controls.input then
        local currentValue = controls.input.Value
        if currentValue and currentValue ~= "" then
            self:SetTargetJobId(currentValue)
        end
    end
end

-- Handle copy button click
function CopyJoinServer:HandleCopyButton()
    return self:CopyCurrentJobId()
end

-- Handle join button click
function CopyJoinServer:HandleJoinButton()
    if controls and controls.input then
        local jobId = controls.input.Value
        if jobId and jobId ~= "" then
            return self:JoinServer(jobId)
        end
    end
    return self:JoinServer()
end

return CopyJoinServer