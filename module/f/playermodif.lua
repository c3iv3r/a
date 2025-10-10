-- LocalPlayer Module (Fixed)
local LocalPlayerModule = {}
LocalPlayerModule.__index = LocalPlayerModule

local logger = _G.Logger and _G.Logger.new("LocalPlayer") or {
    debug = function() end,
    info = function() end,
    warn = function() end,
    error = function() end
}

--// Services
local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")

--// Short refs
local LocalPlayer = Players.LocalPlayer

--// State
local inited = false
local running = false

local character
local humanoid
local rootPart

local connections = {}
local instances = {}

local States = {
    WalkSpeed = 20,
    InfJump = false,
    Fly = false,
    FlySpeed = 50,
    WalkOnWater = false
}

--// Fly Variables
local FLYING = false
local flyBG = nil
local flyBV = nil

--// Internal Functions
local function getRoot(char)
    return char:FindFirstChild("HumanoidRootPart") or char:FindFirstChild("Torso") or char:FindFirstChild("UpperTorso")
end

local function cleanupInstances()
    for name, instance in pairs(instances) do
        if instance and instance.Parent then
            pcall(function() instance:Destroy() end)
        end
        instances[name] = nil
    end
end

local function cleanupConnections()
    for name, conn in pairs(connections) do
        if conn and conn.Connected then
            pcall(function() conn:Disconnect() end)
        end
        connections[name] = nil
    end
end

local function setupCharacter(char)
    character = char
    humanoid = char:WaitForChild("Humanoid")
    rootPart = getRoot(char)
    
    if running then
        humanoid.WalkSpeed = States.WalkSpeed
        if States.InfJump then LocalPlayerModule:EnableInfJump() end
        if States.Fly then LocalPlayerModule:EnableFly() end
        if States.WalkOnWater then LocalPlayerModule:EnableWalkOnWater() end
    end
end

--// Lifecycle
function LocalPlayerModule:Init(guiControls)
    if inited then return true end
    
    local char = LocalPlayer.Character or LocalPlayer.CharacterAdded:Wait()
    setupCharacter(char)
    
    connections.CharacterAdded = LocalPlayer.CharacterAdded:Connect(setupCharacter)
    
    inited = true
    logger:info("Initialized")
    return true
end

function LocalPlayerModule:Start(config)
    if running then return end
    if not inited then
        local ok = self:Init()
        if not ok then return end
    end
    running = true
    logger:info("Started")
end

function LocalPlayerModule:Stop()
    if not running then return end
    running = false
    
    self:DisableInfJump()
    self:DisableFly()
    self:DisableWalkOnWater()
    
    logger:info("Stopped")
end

function LocalPlayerModule:Cleanup()
    self:Stop()
    cleanupConnections()
    cleanupInstances()
    inited = false
    logger:info("Cleaned up")
end

--// Feature Controls
function LocalPlayerModule:SetWalkSpeed(speed)
    States.WalkSpeed = speed
    if humanoid then
        humanoid.WalkSpeed = speed
    end
end

function LocalPlayerModule:EnableInfJump()
    if States.InfJump then return end
    States.InfJump = true
    
    connections.InfJump = UserInputService.JumpRequest:Connect(function()
        if humanoid then
            humanoid:ChangeState(Enum.HumanoidStateType.Jumping)
        end
    end)
end

function LocalPlayerModule:DisableInfJump()
    if not States.InfJump then return end
    States.InfJump = false
    
    if connections.InfJump then
        connections.InfJump:Disconnect()
        connections.InfJump = nil
    end
end

--// FLY (Rewritten)
function LocalPlayerModule:EnableFly()
    if States.Fly or not rootPart or not humanoid then return end
    States.Fly = true
    FLYING = true
    
    -- Create BodyGyro and BodyVelocity
    flyBG = Instance.new('BodyGyro')
    flyBG.P = 9e4
    flyBG.MaxTorque = Vector3.new(9e9, 9e9, 9e9)
    flyBG.CFrame = rootPart.CFrame
    flyBG.Parent = rootPart
    
    flyBV = Instance.new('BodyVelocity')
    flyBV.Velocity = Vector3.new(0, 0, 0)
    flyBV.MaxForce = Vector3.new(9e9, 9e9, 9e9)
    flyBV.Parent = rootPart
    
    instances.FlyBG = flyBG
    instances.FlyBV = flyBV
    
    -- Set humanoid to flying state
    humanoid.PlatformStand = true
    
    -- Main fly loop
    connections.FlyLoop = RunService.Heartbeat:Connect(function()
        if not FLYING or not rootPart or not flyBG or not flyBV then return end
        
        local camera = workspace.CurrentCamera
        local moveVector = Vector3.new(0, 0, 0)
        
        -- Check input
        if UserInputService:IsKeyDown(Enum.KeyCode.W) then
            moveVector = moveVector + camera.CFrame.LookVector
        end
        if UserInputService:IsKeyDown(Enum.KeyCode.S) then
            moveVector = moveVector - camera.CFrame.LookVector
        end
        if UserInputService:IsKeyDown(Enum.KeyCode.A) then
            moveVector = moveVector - camera.CFrame.RightVector
        end
        if UserInputService:IsKeyDown(Enum.KeyCode.D) then
            moveVector = moveVector + camera.CFrame.RightVector
        end
        if UserInputService:IsKeyDown(Enum.KeyCode.Space) then
            moveVector = moveVector + Vector3.new(0, 1, 0)
        end
        if UserInputService:IsKeyDown(Enum.KeyCode.LeftShift) then
            moveVector = moveVector - Vector3.new(0, 1, 0)
        end
        
        -- Apply velocity
        if moveVector.Magnitude > 0 then
            flyBV.Velocity = moveVector.Unit * States.FlySpeed
        else
            flyBV.Velocity = Vector3.new(0, 0, 0)
        end
        
        -- Update rotation to match camera
        flyBG.CFrame = camera.CFrame
    end)
end

function LocalPlayerModule:DisableFly()
    if not States.Fly then return end
    States.Fly = false
    FLYING = false
    
    -- Disconnect fly loop
    if connections.FlyLoop then
        connections.FlyLoop:Disconnect()
        connections.FlyLoop = nil
    end
    
    -- Destroy instances
    if flyBG and flyBG.Parent then
        flyBG:Destroy()
    end
    if flyBV and flyBV.Parent then
        flyBV:Destroy()
    end
    
    flyBG = nil
    flyBV = nil
    instances.FlyBG = nil
    instances.FlyBV = nil
    
    -- Reset humanoid
    if humanoid then
        humanoid.PlatformStand = false
    end
end

function LocalPlayerModule:SetFlySpeed(speed)
    States.FlySpeed = speed
end

--// WALK ON WATER (Rewritten)
function LocalPlayerModule:EnableWalkOnWater()
    if States.WalkOnWater then return end
    States.WalkOnWater = true
    
    -- Create invisible platform
    local waterPart = Instance.new("Part")
    waterPart.Name = "WaterPlatform"
    waterPart.Size = Vector3.new(12, 0.5, 12)
    waterPart.Transparency = 1
    waterPart.CanCollide = true
    waterPart.Anchored = true
    waterPart.Position = Vector3.new(0, -10000, 0)
    waterPart.Parent = workspace
    
    instances.WaterPart = waterPart
    
    -- Water detection loop using Raycast
    connections.WalkOnWaterLoop = RunService.Heartbeat:Connect(function()
        if not States.WalkOnWater or not instances.WaterPart or not rootPart then return end
        
        local rayOrigin = rootPart.Position
        local rayDirection = Vector3.new(0, -10, 0)
        
        local raycastParams = RaycastParams.new()
        raycastParams.FilterDescendantsInstances = {character}
        raycastParams.FilterType = Enum.RaycastFilterType.Exclude
        raycastParams.IgnoreWater = false
        
        local rayResult = workspace:Raycast(rayOrigin, rayDirection, raycastParams)
        
        -- Check if we're above water
        local isAboveWater = false
        if rayResult then
            local material = rayResult.Material
            if material == Enum.Material.Water then
                isAboveWater = true
            end
        else
            -- Also check terrain directly below
            local region = Region3.new(
                rootPart.Position - Vector3.new(2, 5, 2),
                rootPart.Position + Vector3.new(2, 1, 2)
            )
            region = region:ExpandToGrid(4)
            
            local terrain = workspace.Terrain
            local materials, sizes = terrain:ReadVoxels(region, 4)
            local size = materials.Size
            
            for x = 1, size.X do
                for y = 1, size.Y do
                    for z = 1, size.Z do
                        if materials[x][y][z] == Enum.Material.Water then
                            isAboveWater = true
                            break
                        end
                    end
                    if isAboveWater then break end
                end
                if isAboveWater then break end
            end
        end
        
        -- Position the platform
        if isAboveWater then
            -- Place platform slightly below the player
            instances.WaterPart.Position = rootPart.Position - Vector3.new(0, 3.5, 0)
        else
            -- Hide the platform far away
            instances.WaterPart.Position = Vector3.new(0, -10000, 0)
        end
    end)
end

function LocalPlayerModule:DisableWalkOnWater()
    if not States.WalkOnWater then return end
    States.WalkOnWater = false
    
    -- Disconnect loop
    if connections.WalkOnWaterLoop then
        connections.WalkOnWaterLoop:Disconnect()
        connections.WalkOnWaterLoop = nil
    end
    
    -- Destroy platform
    if instances.WaterPart then
        instances.WaterPart:Destroy()
        instances.WaterPart = nil
    end
end

--// Getters
function LocalPlayerModule:GetStates()
    return States
end

return LocalPlayerModule