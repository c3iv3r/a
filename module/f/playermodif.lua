-- LocalPlayer Module
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
    WalkSpeed = 16,
    InfJump = false,
    Fly = false,
    FlySpeed = 50,
    WalkOnWater = false,
    NoOxygen = false
}

--// Internal Functions
local function cleanupInstances()
    for name, instance in pairs(instances) do
        if instance and instance.Parent then
            instance:Destroy()
        end
        instances[name] = nil
    end
end

local function cleanupConnections()
    for name, conn in pairs(connections) do
        if conn and conn.Connected then
            conn:Disconnect()
        end
        connections[name] = nil
    end
end

local function setupCharacter(char)
    character = char
    humanoid = char:WaitForChild("Humanoid")
    rootPart = char:WaitForChild("HumanoidRootPart")
    
    if running then
        humanoid.WalkSpeed = States.WalkSpeed
        if States.InfJump then LocalPlayerModule:EnableInfJump() end
        if States.Fly then LocalPlayerModule:EnableFly() end
        if States.WalkOnWater then LocalPlayerModule:EnableWalkOnWater() end
        if States.NoOxygen then LocalPlayerModule:EnableNoOxygen() end
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
    
    -- Main Loop
    connections.MainLoop = RunService.Heartbeat:Connect(function()
        if not character or not humanoid or not rootPart then return end
        
        -- Fly Movement
        if States.Fly and instances.BodyVelocity and instances.BodyGyro then
            local camera = workspace.CurrentCamera
            local moveDirection = Vector3.zero
            
            if UserInputService:IsKeyDown(Enum.KeyCode.W) then moveDirection += camera.CFrame.LookVector end
            if UserInputService:IsKeyDown(Enum.KeyCode.S) then moveDirection -= camera.CFrame.LookVector end
            if UserInputService:IsKeyDown(Enum.KeyCode.A) then moveDirection -= camera.CFrame.RightVector end
            if UserInputService:IsKeyDown(Enum.KeyCode.D) then moveDirection += camera.CFrame.RightVector end
            if UserInputService:IsKeyDown(Enum.KeyCode.Space) then moveDirection += Vector3.new(0, 1, 0) end
            if UserInputService:IsKeyDown(Enum.KeyCode.LeftShift) then moveDirection -= Vector3.new(0, 1, 0) end
            
            instances.BodyVelocity.Velocity = moveDirection * States.FlySpeed
            instances.BodyGyro.CFrame = camera.CFrame
        end
        
        -- Walk on Water Position Update
        if States.WalkOnWater and instances.WaterPart and rootPart then
            instances.WaterPart.Position = rootPart.Position - Vector3.new(0, 3, 0)
        end
    end)
    
    logger:info("Started")
end

function LocalPlayerModule:Stop()
    if not running then return end
    running = false
    
    self:DisableInfJump()
    self:DisableFly()
    self:DisableWalkOnWater()
    self:DisableNoOxygen()
    
    if connections.MainLoop then
        connections.MainLoop:Disconnect()
        connections.MainLoop = nil
    end
    
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

function LocalPlayerModule:EnableFly()
    if States.Fly or not rootPart or not humanoid then return end
    States.Fly = true
    
    instances.BodyVelocity = Instance.new("BodyVelocity")
    instances.BodyVelocity.Velocity = Vector3.zero
    instances.BodyVelocity.MaxForce = Vector3.new(9e9, 9e9, 9e9)
    instances.BodyVelocity.Parent = rootPart
    
    instances.BodyGyro = Instance.new("BodyGyro")
    instances.BodyGyro.MaxTorque = Vector3.new(9e9, 9e9, 9e9)
    instances.BodyGyro.CFrame = rootPart.CFrame
    instances.BodyGyro.Parent = rootPart
    
    humanoid.PlatformStand = true
end

function LocalPlayerModule:DisableFly()
    if not States.Fly then return end
    States.Fly = false
    
    if instances.BodyVelocity then
        instances.BodyVelocity:Destroy()
        instances.BodyVelocity = nil
    end
    if instances.BodyGyro then
        instances.BodyGyro:Destroy()
        instances.BodyGyro = nil
    end
    
    if humanoid then
        humanoid.PlatformStand = false
    end
end

function LocalPlayerModule:SetFlySpeed(speed)
    States.FlySpeed = speed
end

function LocalPlayerModule:EnableWalkOnWater()
    if States.WalkOnWater or instances.WaterPart then return end
    States.WalkOnWater = true
    
    instances.WaterPart = Instance.new("Part")
    instances.WaterPart.Size = Vector3.new(10, 0.5, 10)
    instances.WaterPart.Transparency = 1
    instances.WaterPart.CanCollide = true
    instances.WaterPart.Anchored = true
    instances.WaterPart.Parent = workspace
end

function LocalPlayerModule:DisableWalkOnWater()
    if not States.WalkOnWater then return end
    States.WalkOnWater = false
    
    if instances.WaterPart then
        instances.WaterPart:Destroy()
        instances.WaterPart = nil
    end
end

function LocalPlayerModule:EnableNoOxygen()
    if States.NoOxygen or not humanoid then return end
    States.NoOxygen = true
    
    connections.NoOxygen = humanoid:GetPropertyChangedSignal("Health"):Connect(function()
        if humanoid.Health < humanoid.MaxHealth then
            task.wait(0.1)
            humanoid.Health = humanoid.MaxHealth
        end
    end)
end

function LocalPlayerModule:DisableNoOxygen()
    if not States.NoOxygen then return end
    States.NoOxygen = false
    
    if connections.NoOxygen then
        connections.NoOxygen:Disconnect()
        connections.NoOxygen = nil
    end
end

--// Getters
function LocalPlayerModule:GetStates()
    return States
end

return LocalPlayerModule