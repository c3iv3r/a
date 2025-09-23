-- Player ESP Feature
-- File: Fish-It/playerespFeature.lua
local playerespFeature = {}
playerespFeature.__index = playerespFeature

local logger = _G.Logger and _G.Logger.new("PlayerEsp") or {
    debug = function() end,
    info = function() end,
    warn = function() end,
    error = function() end
}

--// Services
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

--// Short refs
local LocalPlayer = Players.LocalPlayer

--// State
local inited = false
local running = false
local espObjects = {}
local connections = {}

--// ESP Configuration - EDIT WARNA ESP DI SINI
local ESP_CONFIG = {
    Color = Color3.fromRGB(255, 0, 0),      -- Merah - UBAH WARNA DI SINI
    Transparency = 0.0,                      -- Transparansi (0 = tidak transparan, 1 = transparan penuh)
    OutlineColor = Color3.fromRGB(255, 255, 255), -- Putih untuk outline
    OutlineTransparency = 0.5,
    Thickness = 2
}

-- === Helper Functions ===
local function createHighlight(character)
    local highlight = Instance.new("Highlight")
    highlight.Adornee = character
    highlight.FillColor = ESP_CONFIG.Color
    highlight.FillTransparency = ESP_CONFIG.Transparency
    highlight.OutlineColor = ESP_CONFIG.OutlineColor
    highlight.OutlineTransparency = ESP_CONFIG.OutlineTransparency
    highlight.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
    highlight.Parent = character
    return highlight
end

local function addPlayerESP(player)
    if player == LocalPlayer then return end -- Skip local player
    
    local function onCharacterAdded(character)
        if not running then return end
        
        -- Wait for character to be fully loaded
        local humanoid = character:WaitForChild("Humanoid", 5)
        if not humanoid then return end
        
        -- Create highlight
        local highlight = createHighlight(character)
        
        -- Store reference
        if not espObjects[player] then
            espObjects[player] = {}
        end
        espObjects[player].highlight = highlight
        
        logger:debug("ESP added for player: " .. player.Name)
        
        -- Clean up when character is removed
        character.AncestryChanged:Connect(function()
            if not character.Parent then
                if espObjects[player] and espObjects[player].highlight then
                    espObjects[player].highlight:Destroy()
                    espObjects[player].highlight = nil
                end
            end
        end)
    end
    
    -- Connect to character spawning
    if player.Character then
        onCharacterAdded(player.Character)
    end
    
    local charConn = player.CharacterAdded:Connect(onCharacterAdded)
    connections[player] = charConn
end

local function removePlayerESP(player)
    -- Remove highlight
    if espObjects[player] then
        if espObjects[player].highlight then
            espObjects[player].highlight:Destroy()
        end
        espObjects[player] = nil
    end
    
    -- Disconnect character connection
    if connections[player] then
        connections[player]:Disconnect()
        connections[player] = nil
    end
    
    logger:debug("ESP removed for player: " .. player.Name)
end

-- === Lifecycle Functions ===
function playerespFeature:Init(guiControls)
    if inited then return true end
    
    logger:info("Initializing Player ESP...")
    
    -- Setup player connections
    connections.playerAdded = Players.PlayerAdded:Connect(function(player)
        if running then
            addPlayerESP(player)
        end
    end)
    
    connections.playerRemoving = Players.PlayerRemoving:Connect(function(player)
        removePlayerESP(player)
    end)
    
    inited = true
    logger:info("Player ESP initialized successfully")
    return true
end

function playerespFeature:Start(config)
    if running then return end
    
    if not inited then
        local ok = self:Init()
        if not ok then 
            logger:error("Failed to initialize Player ESP")
            return 
        end
    end
    
    running = true
    logger:info("Starting Player ESP...")
    
    -- Add ESP to all existing players
    for _, player in pairs(Players:GetPlayers()) do
        if player ~= LocalPlayer then
            addPlayerESP(player)
        end
    end
    
    logger:info("Player ESP started")
end

function playerespFeature:Stop()
    if not running then return end
    
    running = false
    logger:info("Stopping Player ESP...")
    
    -- Remove ESP from all players
    for player, _ in pairs(espObjects) do
        removePlayerESP(player)
    end
    
    -- Clear tables
    espObjects = {}
    
    logger:info("Player ESP stopped")
end

function playerespFeature:Cleanup()
    self:Stop()
    
    -- Disconnect all connections
    for _, connection in pairs(connections) do
        if connection and connection.Connected then
            connection:Disconnect()
        end
    end
    connections = {}
    
    -- Reset state
    inited = false
    espObjects = {}
    
    logger:info("Player ESP cleaned up")
end

-- === Configuration Functions ===
function playerespFeature:SetESPColor(color)
    ESP_CONFIG.Color = color
    
    -- Update existing highlights
    if running then
        for player, data in pairs(espObjects) do
            if data.highlight then
                data.highlight.FillColor = color
            end
        end
    end
end

function playerespFeature:SetESPTransparency(transparency)
    ESP_CONFIG.Transparency = transparency
    
    -- Update existing highlights
    if running then
        for player, data in pairs(espObjects) do
            if data.highlight then
                data.highlight.FillTransparency = transparency
            end
        end
    end
end

function playerespFeature:SetOutlineColor(color)
    ESP_CONFIG.OutlineColor = color
    
    -- Update existing highlights
    if running then
        for player, data in pairs(espObjects) do
            if data.highlight then
                data.highlight.OutlineColor = color
            end
        end
    end
end

-- Getter untuk config
function playerespFeature:GetESPConfig()
    return ESP_CONFIG
end

return playerespFeature