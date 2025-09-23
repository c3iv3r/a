-- Player ESP Feature (Username + Distance)
-- Drop-in replacement: minimal change dari versi kamu
local playerespFeature = {}
playerespFeature.__index = playerespFeature

local logger = _G.Logger and _G.Logger.new("PlayerEsp") or { debug=function()end, info=function()end, warn=function()end, error=function()end }

local Players      = game:GetService("Players")
local RunService   = game:GetService("RunService")
local LocalPlayer  = Players.LocalPlayer

local inited, running = false, false
local espObjects, connections, conRender = {}, {}, nil
local LABEL_MAX_M = 500

-- EDIT WARNA ESP DI SINI
local ESP_CONFIG = {
    Color = Color3.fromRGB(125, 85, 255),
    Transparency = 0.0,
    OutlineColor = Color3.fromRGB(255, 255, 255),
    OutlineTransparency = 0.5,
    Thickness = 2
}

-- ===== Helpers =====
local function getAdornee(character)
    return character:FindFirstChild("Head") or character:FindFirstChild("HumanoidRootPart")
end

local function createHighlight(character)
    local h = Instance.new("Highlight")
    h.Adornee = character
    h.FillColor = ESP_CONFIG.Color
    h.FillTransparency = ESP_CONFIG.Transparency
    h.OutlineColor = ESP_CONFIG.OutlineColor
    h.OutlineTransparency = ESP_CONFIG.OutlineTransparency
    h.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
    h.Parent = character
    return h
end

local function createBillboard(player, character)
    local adornee = getAdornee(character)
    if not adornee then return nil end

    local bb = Instance.new("BillboardGui")
    bb.Name = "ESP_Name_"..player.Name
    bb.Adornee = adornee
    bb.AlwaysOnTop = true
    bb.LightInfluence = 0
    bb.Size = UDim2.fromOffset(200, 30)
    bb.StudsOffsetWorldSpace = Vector3.new(0, 2.1, 0) -- tepat di atas kepala, tidak ketinggian
    bb.Parent = character

    local tl = Instance.new("TextLabel")
    tl.BackgroundTransparency = 1
    tl.Size = UDim2.fromScale(1, 1)
    tl.TextScaled = false
    tl.FontFace = Font.new("rbxasset://fonts/families/RobotoMono.json")
    tl.TextSize = 14
    tl.TextColor3 = Color3.new(1,1,1)
    tl.TextStrokeTransparency = 0
    tl.TextStrokeColor3 = Color3.new(0,0,0)
    tl.Text = player.Name
    tl.Parent = bb

    return bb, tl
end

local function addPlayerESP(player)
    if player == LocalPlayer then return end

    local function onCharacterAdded(character)
        if not running then return end
        if not character:WaitForChild("Humanoid", 5) then return end

        local highlight = createHighlight(character)
        local bb, tl = createBillboard(player, character)

        espObjects[player] = espObjects[player] or {}
        espObjects[player].highlight = highlight
        espObjects[player].bb = bb
        espObjects[player].tl = tl

        character.AncestryChanged:Connect(function(_, parent)
            if not parent then
                local data = espObjects[player]
                if data then
                    if data.highlight then pcall(function() data.highlight:Destroy() end) end
                    if data.bb then pcall(function() data.bb:Destroy() end) end
                    espObjects[player] = nil
                end
            end
        end)
    end

    if player.Character then onCharacterAdded(player.Character) end
    connections[player] = player.CharacterAdded:Connect(onCharacterAdded)
end

local function removePlayerESP(player)
    local data = espObjects[player]
    if data then
        if data.highlight then pcall(function() data.highlight:Destroy() end) end
        if data.bb then pcall(function() data.bb:Destroy() end) end
        espObjects[player] = nil
    end
    if connections[player] then connections[player]:Disconnect(); connections[player]=nil end
end

-- ===== Lifecycle =====
function playerespFeature:Init()
    if inited then return true end

    connections.playerAdded = Players.PlayerAdded:Connect(function(p)
        if running then addPlayerESP(p) end
    end)
    connections.playerRemoving = Players.PlayerRemoving:Connect(removePlayerESP)

    inited = true
    logger:info("Player ESP initialized")
    return true
end

function playerespFeature:Start()
    if running then return end
    if not inited then if not self:Init() then return end end
    running = true

    for _, p in ipairs(Players:GetPlayers()) do
        if p ~= LocalPlayer then addPlayerESP(p) end
    end

    -- update username + distance (meter)
    conRender = RunService.RenderStepped:Connect(function()
    local myChar = LocalPlayer.Character
    local myHRP  = myChar and (myChar:FindFirstChild("HumanoidRootPart") or myChar:FindFirstChild("Head"))
    if not myHRP then return end

    for p, data in pairs(espObjects) do
        local c = p.Character
        local adornee = c and getAdornee(c)
        if data and data.bb and data.tl and adornee then
            local dist = (adornee.Position - myHRP.Position).Magnitude
            local meters = math.floor(dist + 0.5)
            if meters <= LABEL_MAX_M then
                if not data.bb.Enabled then data.bb.Enabled = true end
                data.tl.Text = string.format("%s\n%dm", p.Name, meters)
            else
                if data.bb.Enabled then data.bb.Enabled = false end
            end
        elseif data and data.bb then
            if data.bb.Enabled then data.bb.Enabled = false end
        end
    end
end)

    logger:info("Player ESP started")
end

function playerespFeature:Stop()
    if not running then return end
    running = false
    if conRender then conRender:Disconnect(); conRender=nil end

    for p in pairs(espObjects) do removePlayerESP(p) end
    espObjects = {}
    logger:info("Player ESP stopped")
end

function playerespFeature:Cleanup()
    self:Stop()
    for _, conn in pairs(connections) do if conn and conn.Connected then conn:Disconnect() end end
    connections = {}
    inited = false
    logger:info("Player ESP cleaned up")
end

-- Optional setters (tetap jalan)
function playerespFeature:SetESPColor(color)
    ESP_CONFIG.Color = color
    if running then
        for _, data in pairs(espObjects) do
            if data.highlight then data.highlight.FillColor = color end
        end
    end
end
function playerespFeature:SetESPTransparency(t)
    ESP_CONFIG.Transparency = t
    if running then
        for _, data in pairs(espObjects) do
            if data.highlight then data.highlight.FillTransparency = t end
        end
    end
end
function playerespFeature:SetOutlineColor(color)
    ESP_CONFIG.OutlineColor = color
    if running then
        for _, data in pairs(espObjects) do
            if data.highlight then data.highlight.OutlineColor = color end
        end
    end
end
function playerespFeature:GetESPConfig() return ESP_CONFIG end

return playerespFeature