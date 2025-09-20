-- Simple AutoReconnect - No force close issues
local AutoReconnect = {}
AutoReconnect.__index = AutoReconnect

local logger = _G.Logger and _G.Logger.new("AutoReconnect") or {
    debug = function() end,
    info = function() end,
    warn = function() end,
    error = function() end
}

local GuiService = game:GetService("GuiService")
local Players = game:GetService("Players")
local TeleportService = game:GetService("TeleportService")

local player = Players.LocalPlayer
local isEnabled = false
local connection = nil
local isTeleporting = false

-- Anti-cheat keywords to avoid getting banned
local antiCheatKeywords = { "exploit", "cheat", "suspicious", "unauthorized", "script", "ban" }

local function containsAntiCheat(message)
    local lowerMsg = string.lower(message or "")
    for _, keyword in ipairs(antiCheatKeywords) do
        if string.find(lowerMsg, keyword, 1, true) then
            return true
        end
    end
    return false
end

local function onErrorMessageChanged(errorMessage)
    if not isEnabled or isTeleporting then return end
    
    if errorMessage and errorMessage ~= "" then
        logger:info("AutoReconnect: Error detected -", errorMessage)
        
        -- Don't reconnect if it's anti-cheat related
        if containsAntiCheat(errorMessage) then
            logger:info("AutoReconnect: Anti-cheat detected, skipping reconnect")
            return
        end
        
        isTeleporting = true
        
        -- Try to rejoin same server first, then any server
        local success = false
        if game.JobId and game.JobId ~= "" then
            local ok, err = pcall(function()
                TeleportService:TeleportToPlaceInstance(game.PlaceId, game.JobId, player)
            end)
            if ok then 
                success = true
                logger:info("AutoReconnect: Rejoining same server")
            end
        end
        
        if not success then
            wait(1) -- Small delay
            pcall(function()
                TeleportService:Teleport(game.PlaceId, player)
            end)
            logger:info("AutoReconnect: Joining new server")
        end
    end
end

function AutoReconnect:Start()
    if isEnabled then
        logger:info("AutoReconnect: Already running")
        return false
    end
    
    isEnabled = true
    isTeleporting = false
    connection = GuiService.ErrorMessageChanged:Connect(onErrorMessageChanged)
    
    logger:info("AutoReconnect: Started")
    return true
end

function AutoReconnect:Stop()
    if not isEnabled then
        logger:info("AutoReconnect: Already stopped")
        return false
    end
    
    isEnabled = false
    isTeleporting = false
    
    if connection then
        connection:Disconnect()
        connection = nil
    end
    
    logger:info("AutoReconnect: Stopped")
    return true
end

function AutoReconnect:IsEnabled()
    return isEnabled
end

function AutoReconnect:GetStatus()
    return {
        enabled = isEnabled,
        teleporting = isTeleporting,
        hasConnection = connection ~= nil
    }
end

return AutoReconnect