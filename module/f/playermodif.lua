-- LocalPlayer Module (Updated)
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
    FlySpeed = 1,
    WalkOnWater = false,
    NoOxygen = false
}

--// Fly Variables
local FLYING = false
local CONTROL = {F = 0, B = 0, L = 0, R = 0, Q = 0, E = 0}
local lCONTROL = {F = 0, B = 0, L = 0, R = 0, Q = 0, E = 0}
local SPEED = 0

--// Internal Functions
local function getRoot(char)
    return char:FindFirstChild("HumanoidRootPart") or char:FindFirstChild("Torso") or char:FindFirstChild("UpperTorso")
end

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
    rootPart = getRoot(char)
    
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
    
    -- Walk on Water Loop
    connections.WalkOnWaterLoop = RunService.Heartbeat:Connect(function()
        if States.WalkOnWater and instances.WaterPart and rootPart then
            local region = Region3.new(rootPart.Position - Vector3.new(5, 5, 5), rootPart.Position + Vector3.new(5, 5, 5))
            region = region:ExpandToGrid(4)
            
            local parts = workspace:FindPartsInRegion3(region, character, 100)
            local inWater = false
            
            for _, part in pairs(parts) do
                if part:IsA("Terrain") or (part:IsA("BasePart") and part.Name:lower():find("water")) then
                    inWater = true
                    break
                end
            end
            
            if inWater then
                instances.WaterPart.Position = rootPart.Position - Vector3.new(0, 3, 0)
            else
                instances.WaterPart.Position = Vector3.new(0, -10000, 0)
            end
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
    
    if connections.WalkOnWaterLoop then
        connections.WalkOnWaterLoop:Disconnect()
        connections.WalkOnWaterLoop = nil
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
    FLYING = true
    
    local T = rootPart
    
    local BG = Instance.new('BodyGyro')
    local BV = Instance.new('BodyVelocity')
    BG.P = 9e4
    BG.Parent = T
    BV.Parent = T
    BG.MaxTorque = Vector3.new(9e9, 9e9, 9e9)
    BG.CFrame = T.CFrame
    BV.Velocity = Vector3.new(0, 0, 0)
    BV.MaxForce = Vector3.new(9e9, 9e9, 9e9)
    
    instances.BodyGyro = BG
    instances.BodyVelocity = BV
    
    -- Input handlers
    connections.FlyKeyDown = UserInputService.InputBegan:Connect(function(input, processed)
        if input.KeyCode == Enum.KeyCode.W then
            CONTROL.F = States.FlySpeed
        elseif input.KeyCode == Enum.KeyCode.S then
            CONTROL.B = -States.FlySpeed
        elseif input.KeyCode == Enum.KeyCode.A then
            CONTROL.L = -States.FlySpeed
        elseif input.KeyCode == Enum.KeyCode.D then
            CONTROL.R = States.FlySpeed
        elseif input.KeyCode == Enum.KeyCode.E then
            CONTROL.Q = States.FlySpeed * 2
        elseif input.KeyCode == Enum.KeyCode.Q then
            CONTROL.E = -States.FlySpeed * 2
        end
    end)
    
    connections.FlyKeyUp = UserInputService.InputEnded:Connect(function(input, processed)
        if input.KeyCode == Enum.KeyCode.W then
            CONTROL.F = 0
        elseif input.KeyCode == Enum.KeyCode.S then
            CONTROL.B = 0
        elseif input.KeyCode == Enum.KeyCode.A then
            CONTROL.L = 0
        elseif input.KeyCode == Enum.KeyCode.D then
            CONTROL.R = 0
        elseif input.KeyCode == Enum.KeyCode.E then
            CONTROL.Q = 0
        elseif input.KeyCode == Enum.KeyCode.Q then
            CONTROL.E = 0
        end
    end)
    
    -- Fly loop
    task.spawn(function()
        repeat task.wait()
            local camera = workspace.CurrentCamera
            if humanoid then
                humanoid.PlatformStand = true
            end
            
            if CONTROL.L + CONTROL.R ~= 0 or CONTROL.F + CONTROL.B ~= 0 or CONTROL.Q + CONTROL.E ~= 0 then
                SPEED = 50
            elseif not (CONTROL.L + CONTROL.R ~= 0 or CONTROL.F + CONTROL.B ~= 0 or CONTROL.Q + CONTROL.E ~= 0) and SPEED ~= 0 then
                SPEED = 0
            end
            
            if (CONTROL.L + CONTROL.R) ~= 0 or (CONTROL.F + CONTROL.B) ~= 0 or (CONTROL.Q + CONTROL.E) ~= 0 then
                BV.Velocity = ((camera.CFrame.LookVector * (CONTROL.F + CONTROL.B)) + ((camera.CFrame * CFrame.new(CONTROL.L + CONTROL.R, (CONTROL.F + CONTROL.B + CONTROL.Q + CONTROL.E) * 0.2, 0).p) - camera.CFrame.p)) * SPEED
                lCONTROL = {F = CONTROL.F, B = CONTROL.B, L = CONTROL.L, R = CONTROL.R}
            elseif (CONTROL.L + CONTROL.R) == 0 and (CONTROL.F + CONTROL.B) == 0 and (CONTROL.Q + CONTROL.E) == 0 and SPEED ~= 0 then
                BV.Velocity = ((camera.CFrame.LookVector * (lCONTROL.F + lCONTROL.B)) + ((camera.CFrame * CFrame.new(lCONTROL.L + lCONTROL.R, (lCONTROL.F + lCONTROL.B + CONTROL.Q + CONTROL.E) * 0.2, 0).p) - camera.CFrame.p)) * SPEED
            else
                BV.Velocity = Vector3.new(0, 0, 0)
            end
            BG.CFrame = camera.CFrame
        until not FLYING
        
        CONTROL = {F = 0, B = 0, L = 0, R = 0, Q = 0, E = 0}
        lCONTROL = {F = 0, B = 0, L = 0, R = 0, Q = 0, E = 0}
        SPEED = 0
        
        if BG and BG.Parent then BG:Destroy() end
        if BV and BV.Parent then BV:Destroy() end
        if humanoid then humanoid.PlatformStand = false end
    end)
end

function LocalPlayerModule:DisableFly()
    if not States.Fly then return end
    States.Fly = false
    FLYING = false
    
    if connections.FlyKeyDown then
        connections.FlyKeyDown:Disconnect()
        connections.FlyKeyDown = nil
    end
    if connections.FlyKeyUp then
        connections.FlyKeyUp:Disconnect()
        connections.FlyKeyUp = nil
    end
    
    instances.BodyVelocity = nil
    instances.BodyGyro = nil
end

function LocalPlayerModule:SetFlySpeed(speed)
    States.FlySpeed = speed
end

function LocalPlayerModule:EnableWalkOnWater()
    if States.WalkOnWater or instances.WaterPart then return end
    States.WalkOnWater = true
    
    instances.WaterPart = Instance.new("Part")
    instances.WaterPart.Size = Vector3.new(10, 1, 10)
    instances.WaterPart.Transparency = 1
    instances.WaterPart.CanCollide = true
    instances.WaterPart.Anchored = true
    instances.WaterPart.Position = Vector3.new(0, -10000, 0)
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
    
    -- Swim state handler (prevent oxygen loss)
    connections.NoOxygen = RunService.Heartbeat:Connect(function()
        if humanoid:GetState() == Enum.HumanoidStateType.Swimming then
            humanoid:ChangeState(Enum.HumanoidStateType.Running)
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