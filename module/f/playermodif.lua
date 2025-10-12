-- LocalPlayer Module (Updated Fly + No Walk on Water)
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
    FlySpeed = 1
}

--// Fly Variables
local FLYING = false
local QEfly = true
local flyKeyDown, flyKeyUp
local velocityHandlerName = "VH_" .. tick()
local gyroHandlerName = "GH_" .. tick()
local mfly1, mfly2

--// Mobile Detection
local IsOnMobile = UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled

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

--// PC FLY
local function sFLY(vfly)
    if not character or not humanoid or not rootPart then return end
    
    local T = rootPart
    local CONTROL = {F = 0, B = 0, L = 0, R = 0, Q = 0, E = 0}
    local lCONTROL = {F = 0, B = 0, L = 0, R = 0, Q = 0, E = 0}
    local SPEED = 0

    local function FLY()
        FLYING = true
        local BG = Instance.new('BodyGyro')
        local BV = Instance.new('BodyVelocity')
        BG.P = 9e4
        BG.Parent = T
        BV.Parent = T
        BG.MaxTorque = Vector3.new(9e9, 9e9, 9e9)
        BG.CFrame = T.CFrame
        BV.Velocity = Vector3.new(0, 0, 0)
        BV.MaxForce = Vector3.new(9e9, 9e9, 9e9)
        
        instances.FlyBG = BG
        instances.FlyBV = BV
        
        task.spawn(function()
            repeat task.wait()
                local camera = workspace.CurrentCamera
                if not vfly and humanoid then
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
            BG:Destroy()
            BV:Destroy()
            if humanoid then humanoid.PlatformStand = false end
        end)
    end

    flyKeyDown = UserInputService.InputBegan:Connect(function(input, processed)
        if processed then return end
        if input.KeyCode == Enum.KeyCode.W then
            CONTROL.F = (vfly and States.FlySpeed or States.FlySpeed)
        elseif input.KeyCode == Enum.KeyCode.S then
            CONTROL.B = -(vfly and States.FlySpeed or States.FlySpeed)
        elseif input.KeyCode == Enum.KeyCode.A then
            CONTROL.L = -(vfly and States.FlySpeed or States.FlySpeed)
        elseif input.KeyCode == Enum.KeyCode.D then
            CONTROL.R = (vfly and States.FlySpeed or States.FlySpeed)
        elseif input.KeyCode == Enum.KeyCode.E and QEfly then
            CONTROL.Q = (vfly and States.FlySpeed or States.FlySpeed) * 2
        elseif input.KeyCode == Enum.KeyCode.Q and QEfly then
            CONTROL.E = -(vfly and States.FlySpeed or States.FlySpeed) * 2
        end
    end)

    flyKeyUp = UserInputService.InputEnded:Connect(function(input, processed)
        if input.KeyCode == Enum.KeyCode.W then CONTROL.F = 0
        elseif input.KeyCode == Enum.KeyCode.S then CONTROL.B = 0
        elseif input.KeyCode == Enum.KeyCode.A then CONTROL.L = 0
        elseif input.KeyCode == Enum.KeyCode.D then CONTROL.R = 0
        elseif input.KeyCode == Enum.KeyCode.E then CONTROL.Q = 0
        elseif input.KeyCode == Enum.KeyCode.Q then CONTROL.E = 0
        end
    end)
    
    connections.FlyKeyDown = flyKeyDown
    connections.FlyKeyUp = flyKeyUp
    FLY()
end

--// MOBILE FLY
local function mobilefly(vfly)
    if not character or not humanoid or not rootPart then return end
    
    FLYING = true
    local root = rootPart
    local camera = workspace.CurrentCamera
    
    local controlModule = require(LocalPlayer.PlayerScripts:WaitForChild("PlayerModule"):WaitForChild("ControlModule"))
    
    local bv = Instance.new("BodyVelocity")
    bv.Name = velocityHandlerName
    bv.Parent = root
    bv.MaxForce = Vector3.new(9e9, 9e9, 9e9)
    bv.Velocity = Vector3.zero

    local bg = Instance.new("BodyGyro")
    bg.Name = gyroHandlerName
    bg.Parent = root
    bg.MaxTorque = Vector3.new(9e9, 9e9, 9e9)
    bg.P = 1000
    bg.D = 50
    
    instances.FlyBV = bv
    instances.FlyBG = bg

    mfly1 = LocalPlayer.CharacterAdded:Connect(function(char)
        task.wait()
        root = getRoot(char)
        
        local bv = Instance.new("BodyVelocity")
        bv.Name = velocityHandlerName
        bv.Parent = root
        bv.MaxForce = Vector3.new(9e9, 9e9, 9e9)
        bv.Velocity = Vector3.zero

        local bg = Instance.new("BodyGyro")
        bg.Name = gyroHandlerName
        bg.Parent = root
        bg.MaxTorque = Vector3.new(9e9, 9e9, 9e9)
        bg.P = 1000
        bg.D = 50
        
        instances.FlyBV = bv
        instances.FlyBG = bg
    end)

    mfly2 = RunService.Heartbeat:Connect(function()
        if not FLYING then return end
        
        root = getRoot(character)
        camera = workspace.CurrentCamera
        
        local VelocityHandler = root and root:FindFirstChild(velocityHandlerName)
        local GyroHandler = root and root:FindFirstChild(gyroHandlerName)
        
        if humanoid and VelocityHandler and GyroHandler then
            if not vfly then humanoid.PlatformStand = true end
            GyroHandler.CFrame = camera.CFrame
            
            local direction = controlModule:GetMoveVector()
            local velocity = Vector3.zero
            
            if direction.X ~= 0 then
                velocity = velocity + camera.CFrame.RightVector * (direction.X * ((vfly and States.FlySpeed or States.FlySpeed) * 50))
            end
            if direction.Z ~= 0 then
                velocity = velocity - camera.CFrame.LookVector * (direction.Z * ((vfly and States.FlySpeed or States.FlySpeed) * 50))
            end
            
            VelocityHandler.Velocity = velocity
        end
    end)
    
    connections.MobileFly1 = mfly1
    connections.MobileFly2 = mfly2
end

--// FLY (PC + Mobile Support)
function LocalPlayerModule:EnableFly()
    if States.Fly or not rootPart or not humanoid then return end
    States.Fly = true
    
    if IsOnMobile then
        mobilefly(false)
    else
        sFLY(false)
    end
end

function LocalPlayerModule:DisableFly()
    if not States.Fly then return end
    States.Fly = false
    FLYING = false
    
    -- Disconnect all fly connections
    if flyKeyDown then flyKeyDown:Disconnect() flyKeyDown = nil end
    if flyKeyUp then flyKeyUp:Disconnect() flyKeyUp = nil end
    if mfly1 then mfly1:Disconnect() mfly1 = nil end
    if mfly2 then mfly2:Disconnect() mfly2 = nil end
    
    if connections.FlyKeyDown then
        connections.FlyKeyDown:Disconnect()
        connections.FlyKeyDown = nil
    end
    if connections.FlyKeyUp then
        connections.FlyKeyUp:Disconnect()
        connections.FlyKeyUp = nil
    end
    if connections.MobileFly1 then
        connections.MobileFly1:Disconnect()
        connections.MobileFly1 = nil
    end
    if connections.MobileFly2 then
        connections.MobileFly2:Disconnect()
        connections.MobileFly2 = nil
    end
    
    -- Clean up instances
    if rootPart then
        if rootPart:FindFirstChild(velocityHandlerName) then 
            rootPart[velocityHandlerName]:Destroy() 
        end
        if rootPart:FindFirstChild(gyroHandlerName) then 
            rootPart[gyroHandlerName]:Destroy() 
        end
    end
    
    if instances.FlyBG and instances.FlyBG.Parent then
        instances.FlyBG:Destroy()
    end
    if instances.FlyBV and instances.FlyBV.Parent then
        instances.FlyBV:Destroy()
    end
    
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

--// Getters
function LocalPlayerModule:GetStates()
    return States
end

return LocalPlayerModule