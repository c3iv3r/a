-- BoostFPS Feature
local BoostFPS = {}
BoostFPS.__index = BoostFPS

local logger = _G.Logger and _G.Logger.new("BoostFPS") or {
    debug = function() end,
    info = function() end,
    warn = function() end,
    error = function() end
}

-- Services
local Lighting = game:GetService("Lighting")
local Workspace = game:GetService("Workspace")
local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local SoundService = game:GetService("SoundService")
local RunService = game:GetService("RunService")

-- State
local inited = false
local running = false
local connections = {}
local originalSettings = {}

-- === lifecycle ===
function BoostFPS:Init(guiControls)
    if inited then return true end
    
    -- Simpan setting asli untuk bisa dikembalikan
    originalSettings = {
        GlobalShadows = Lighting.GlobalShadows,
        FogEnd = Lighting.FogEnd,
        Brightness = Lighting.Brightness,
        QualityLevel = settings().Rendering.QualityLevel,
        EnableShadowMap = settings().Rendering.EnableShadowMap,
        MeshPartDetailLevel = settings().Rendering.MeshPartDetailLevel,
        WaterWaveSize = 0,
        WaterWaveSpeed = 0,
        WaterReflectance = 0,
        WaterTransparency = 0,
        CameraFieldOfView = 70
    }
    
    inited = true
    return true
end

function BoostFPS:Start(config)
    if running then return end
    if not inited then
        local ok = self:Init()
        if not ok then return end
    end
    running = true

    -- Mengatur pengaturan grafis ke rendah
    Lighting.GlobalShadows = false
    Lighting.FogEnd = 100000
    Lighting.Brightness = 1
    
    -- Mengurangi kualitas tekstur
    settings().Rendering.QualityLevel = 1 -- Set ke level terendah
    
    -- Nonaktifkan shadow map
    settings().Rendering.EnableShadowMap = false
    
    -- Mengatur frame rate limit
    settings().Rendering.MeshPartDetailLevel = 1
    
    -- Nonaktifkan suara jika diperlukan
    SoundService.RespectFilteringEnabled = true
    
    -- Mengurangi jarak pandang kamera
    local Camera = Workspace.CurrentCamera
    originalSettings.CameraFieldOfView = Camera.FieldOfView
    Camera.FieldOfView = 70
    
    -- Nonaktifkan efek visual pada kamera
    local function disableCameraEffects()
        for _, effect in pairs(Camera:GetChildren()) do
            if effect:IsA("PostEffect") then
                effect.Enabled = false
            end
        end
    end
    disableCameraEffects()
    
    -- Koneksi untuk efek baru di kamera
    table.insert(connections, Camera.ChildAdded:Connect(function(child)
        if child:IsA("PostEffect") then
            child.Enabled = false
        end
    end))
    
    -- Nonaktifkan partikel dan efek lainnya
    local function disableEffects(obj)
        if obj:IsA("ParticleEmitter") or obj:IsA("Smoke") or obj:IsA("Fire") or obj:IsA("Trail") or obj:IsA("Beam") then
            obj.Enabled = false
        end
    end
    
    -- Terapkan pada objek yang sudah ada
    for _, obj in pairs(Workspace:GetDescendants()) do
        disableEffects(obj)
    end
    
    -- Koneksi untuk objek baru
    table.insert(connections, Workspace.DescendantAdded:Connect(function(descendant)
        disableEffects(descendant)
    end))
    
    -- Mengatur kualitas material
    local function optimizeMaterial(obj)
        if obj:IsA("BasePart") or obj:IsA("MeshPart") or obj:IsA("UnionOperation") then
            obj.Material = Enum.Material.Plastic
        end
    end
    
    -- Terapkan pada objek yang sudah ada
    for _, obj in pairs(Workspace:GetDescendants()) do
        optimizeMaterial(obj)
    end
    
    -- Koneksi untuk objek baru
    table.insert(connections, Workspace.DescendantAdded:Connect(function(descendant)
        optimizeMaterial(descendant)
    end))
    
    -- Mengurangi detail pohon dan vegetasi
    local function optimizeVegetation(model)
        if model:IsA("Model") and (model.Name:match("Tree") or model.Name:match("Bush") or model.Name:match("Grass")) then
            for _, part in pairs(model:GetDescendants()) do
                if part:IsA("BasePart") then
                    part.Material = Enum.Material.Plastic
                end
            end
        end
    end
    
    -- Terapkan pada model yang sudah ada
    for _, model in pairs(Workspace:GetChildren()) do
        optimizeVegetation(model)
    end
    
    -- Koneksi untuk model baru
    table.insert(connections, Workspace.ChildAdded:Connect(function(model)
        optimizeVegetation(model)
    end))
    
    -- Nonaktifkan animasi kompleks
    local function disableComplexAnimations(model)
        if model:IsA("Model") then
            for _, descendant in pairs(model:GetDescendants()) do
                if descendant:IsA("Animation") or descendant:IsA("BodyMover") then
                    descendant:Destroy()
                end
            end
        end
    end
    
    -- Terapkan pada semua model di workspace
    for _, model in pairs(Workspace:GetChildren()) do
        disableComplexAnimations(model)
    end
    
    -- Koneksi untuk model baru
    table.insert(connections, Workspace.ChildAdded:Connect(function(model)
        if model:IsA("Model") then
            disableComplexAnimations(model)
        end
    end))
    
    -- Nonaktifkan efek air
    for _, terrain in pairs(Workspace:GetChildren()) do
        if terrain:IsA("Terrain") then
            originalSettings.WaterWaveSize = terrain.WaterWaveSize
            originalSettings.WaterWaveSpeed = terrain.WaterWaveSpeed
            originalSettings.WaterReflectance = terrain.WaterReflectance
            originalSettings.WaterTransparency = terrain.WaterTransparency
            
            terrain.WaterWaveSize = 0
            terrain.WaterWaveSpeed = 0
            terrain.WaterReflectance = 0
            terrain.WaterTransparency = 0.9
        end
    end
    
    -- Nonaktifkan efek post-processing
    local function disablePostEffects()
        for _, effect in pairs(Lighting:GetChildren()) do
            if effect:IsA("PostEffect") then
                effect.Enabled = false
            end
        end
    end
    disablePostEffects()
    
    -- Koneksi untuk efek post-processing baru
    table.insert(connections, Lighting.ChildAdded:Connect(function(effect)
        if effect:IsA("PostEffect") then
            effect.Enabled = false
        end
    end))
    
    -- Mengatur detail karakter
    local function optimizeCharacter(character)
        for _, part in pairs(character:GetDescendants()) do
            if part:IsA("BasePart") or part:IsA("MeshPart") then
                part.Material = Enum.Material.Plastic
            end
        end
    end
    
    -- Terapkan pada karakter yang sudah ada
    local LocalPlayer = Players.LocalPlayer
    if LocalPlayer.Character then
        optimizeCharacter(LocalPlayer.Character)
    end
    
    -- Koneksi untuk karakter baru
    table.insert(connections, LocalPlayer.CharacterAdded:Connect(function(character)
        optimizeCharacter(character)
    end))
    
    -- Mengurangi detail pada mesh
    local function optimizeMesh(obj)
        if obj:IsA("MeshPart") then
            obj.RenderFidelity = Enum.RenderFidelity.Automatic
            obj.LevelOfDetail = Enum.LevelOfDetail.Low
        end
    end
    
    -- Terapkan pada mesh yang sudah ada
    for _, obj in pairs(Workspace:GetDescendants()) do
        optimizeMesh(obj)
    end
    
    -- Koneksi untuk mesh baru
    table.insert(connections, Workspace.DescendantAdded:Connect(function(descendant)
        optimizeMesh(descendant)
    end))
    
    -- Nonaktifkan physics rendering yang tidak perlu
    local function optimizePhysics(obj)
        if obj:IsA("BasePart") then
            obj.CanCollide = true
            obj.Anchored = true
        end
    end
    
    -- Terapkan pada objek yang sudah ada
    for _, obj in pairs(Workspace:GetDescendants()) do
        optimizePhysics(obj)
    end
    
    -- Koneksi untuk objek baru
    table.insert(connections, Workspace.DescendantAdded:Connect(function(descendant)
        optimizePhysics(descendant)
    end))
    
    logger:info("BoostFPS started")
end

function BoostFPS:Stop()
    if not running then return end
    running = false
    
    -- Putuskan semua koneksi
    for _, conn in pairs(connections) do
        if conn then
            conn:Disconnect()
        end
    end
    connections = {}
    
    -- Kembalikan setting asli (jika ada)
    if originalSettings.GlobalShadows ~= nil then
        Lighting.GlobalShadows = originalSettings.GlobalShadows
    end
    if originalSettings.FogEnd ~= nil then
        Lighting.FogEnd = originalSettings.FogEnd
    end
    if originalSettings.Brightness ~= nil then
        Lighting.Brightness = originalSettings.Brightness
    end
    if originalSettings.QualityLevel ~= nil then
        settings().Rendering.QualityLevel = originalSettings.QualityLevel
    end
    if originalSettings.EnableShadowMap ~= nil then
        settings().Rendering.EnableShadowMap = originalSettings.EnableShadowMap
    end
    if originalSettings.MeshPartDetailLevel ~= nil then
        settings().Rendering.MeshPartDetailLevel = originalSettings.MeshPartDetailLevel
    end
    
    -- Kembalikan setting terrain
    for _, terrain in pairs(Workspace:GetChildren()) do
        if terrain:IsA("Terrain") then
            if originalSettings.WaterWaveSize ~= nil then
                terrain.WaterWaveSize = originalSettings.WaterWaveSize
            end
            if originalSettings.WaterWaveSpeed ~= nil then
                terrain.WaterWaveSpeed = originalSettings.WaterWaveSpeed
            end
            if originalSettings.WaterReflectance ~= nil then
                terrain.WaterReflectance = originalSettings.WaterReflectance
            end
            if originalSettings.WaterTransparency ~= nil then
                terrain.WaterTransparency = originalSettings.WaterTransparency
            end
        end
    end
    
    -- Kembalikan FOV kamera
    local Camera = Workspace.CurrentCamera
    if originalSettings.CameraFieldOfView ~= nil then
        Camera.FieldOfView = originalSettings.CameraFieldOfView
    end
    
    logger:info("BoostFPS stopped")
end

function BoostFPS:Cleanup()
    self:Stop()
    -- Reset state
    inited = false
    originalSettings = {}
    logger:info("BoostFPS cleaned up")
end

return BoostFPS