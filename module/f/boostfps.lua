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

-- Helper functions untuk safe setting access
local function safeSetProperty(obj, prop, value)
    pcall(function()
        if obj and prop then
            obj[prop] = value
        end
    end)
end

local function safeGetProperty(obj, prop, defaultValue)
    local success, result = pcall(function()
        if obj and prop then
            return obj[prop]
        end
        return defaultValue
    end)
    return success and result or defaultValue
end

-- Fungsi untuk mengecek apakah objek adalah bagian dari karakter
local function isCharacterPart(obj)
    local character = Players.LocalPlayer and Players.LocalPlayer.Character
    if not character then return false end
    
    return obj:IsDescendantOf(character)
end

-- Fungsi untuk mengecek apakah objek penting untuk gameplay
local function isImportantObject(obj)
    -- Jangan sentuh karakter pemain
    if isCharacterPart(obj) then return true end
    
    -- Jangan sentuh tools atau equipment
    if obj:IsA("Tool") or obj:IsA("HopperBin") then return true end
    
    -- Jangan sentuh objek dengan nama tertentu
    local importantNames = {"FishingRod", "Rod", "Bait", "Net", "Boat"}
    for _, name in ipairs(importantNames) do
        if string.find(string.lower(obj.Name), string.lower(name)) then
            return true
        end
    end
    
    return false
end

-- === lifecycle ===
function BoostFPS:Init(guiControls)
    if inited then return true end
    
    -- Simpan setting asli untuk bisa dikembalikan
    originalSettings = {
        GlobalShadows = Lighting.GlobalShadows,
        FogEnd = Lighting.FogEnd,
        Brightness = Lighting.Brightness,
        QualityLevel = safeGetProperty(settings().Rendering, "QualityLevel", 10),
        EnableShadowMap = safeGetProperty(settings().Rendering, "EnableShadowMap", true),
        MeshPartDetailLevel = safeGetProperty(settings().Rendering, "MeshPartDetailLevel", 10),
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
    safeSetProperty(Lighting, "GlobalShadows", false)
    safeSetProperty(Lighting, "FogEnd", 100000)
    safeSetProperty(Lighting, "Brightness", 1)
    
    -- Mengurangi kualitas tekstur
    safeSetProperty(settings().Rendering, "QualityLevel", 1) -- Set ke level terendah
    
    -- Nonaktifkan shadow map (dengan pcall untuk menghindari error)
    pcall(function()
        settings().Rendering.EnableShadowMap = false
    end)
    
    -- Mengatur frame rate limit
    pcall(function()
        settings().Rendering.MeshPartDetailLevel = 1
    end)
    
    -- Nonaktifkan suara jika diperlukan
    safeSetProperty(SoundService, "RespectFilteringEnabled", true)
    
    -- Mengurangi jarak pandang kamera
    local Camera = Workspace.CurrentCamera
    originalSettings.CameraFieldOfView = safeGetProperty(Camera, "FieldOfView", 70)
    safeSetProperty(Camera, "FieldOfView", 70)
    
    -- Nonaktifkan efek visual pada kamera
    local function disableCameraEffects()
        for _, effect in pairs(Camera:GetChildren()) do
            if effect:IsA("PostEffect") then
                safeSetProperty(effect, "Enabled", false)
            end
        end
    end
    disableCameraEffects()
    
    -- Koneksi untuk efek baru di kamera
    table.insert(connections, Camera.ChildAdded:Connect(function(child)
        if child:IsA("PostEffect") then
            safeSetProperty(child, "Enabled", false)
        end
    end))
    
    -- Nonaktifkan partikel dan efek lainnya (kecuali yang penting)
    local function disableEffects(obj)
        if isImportantObject(obj) then return end
        
        if obj:IsA("ParticleEmitter") or obj:IsA("Smoke") or obj:IsA("Fire") or obj:IsA("Trail") or obj:IsA("Beam") then
            safeSetProperty(obj, "Enabled", false)
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
    
    -- Mengatur kualitas material (kecuali untuk karakter)
    local function optimizeMaterial(obj)
        if isImportantObject(obj) then return end
        
        if obj:IsA("BasePart") or obj:IsA("MeshPart") or obj:IsA("UnionOperation") then
            safeSetProperty(obj, "Material", Enum.Material.Plastic)
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
        if isImportantObject(model) then return end
        
        if model:IsA("Model") and (model.Name:match("Tree") or model.Name:match("Bush") or model.Name:match("Grass")) then
            for _, part in pairs(model:GetDescendants()) do
                if part:IsA("BasePart") then
                    safeSetProperty(part, "Material", Enum.Material.Plastic)
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
    
    -- Nonaktifkan animasi kompleks (kecuali untuk karakter)
    local function disableComplexAnimations(model)
        if isImportantObject(model) then return end
        
        if model:IsA("Model") then
            for _, descendant in pairs(model:GetDescendants()) do
                if descendant:IsA("Animation") or descendant:IsA("BodyMover") then
                    pcall(function()
                        descendant:Destroy()
                    end)
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
        disableComplexAnimations(model)
    end))
    
    -- Nonaktifkan efek air
    for _, terrain in pairs(Workspace:GetChildren()) do
        if terrain:IsA("Terrain") then
            originalSettings.WaterWaveSize = safeGetProperty(terrain, "WaterWaveSize", 0)
            originalSettings.WaterWaveSpeed = safeGetProperty(terrain, "WaterWaveSpeed", 0)
            originalSettings.WaterReflectance = safeGetProperty(terrain, "WaterReflectance", 0)
            originalSettings.WaterTransparency = safeGetProperty(terrain, "WaterTransparency", 0)
            
            safeSetProperty(terrain, "WaterWaveSize", 0)
            safeSetProperty(terrain, "WaterWaveSpeed", 0)
            safeSetProperty(terrain, "WaterReflectance", 0)
            safeSetProperty(terrain, "WaterTransparency", 0.9)
        end
    end
    
    -- Nonaktifkan efek post-processing
    local function disablePostEffects()
        for _, effect in pairs(Lighting:GetChildren()) do
            if effect:IsA("PostEffect") then
                safeSetProperty(effect, "Enabled", false)
            end
        end
    end
    disablePostEffects()
    
    -- Koneksi untuk efek post-processing baru
    table.insert(connections, Lighting.ChildAdded:Connect(function(effect)
        if effect:IsA("PostEffect") then
            safeSetProperty(effect, "Enabled", false)
        end
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
        safeSetProperty(Lighting, "GlobalShadows", originalSettings.GlobalShadows)
    end
    if originalSettings.FogEnd ~= nil then
        safeSetProperty(Lighting, "FogEnd", originalSettings.FogEnd)
    end
    if originalSettings.Brightness ~= nil then
        safeSetProperty(Lighting, "Brightness", originalSettings.Brightness)
    end
    if originalSettings.QualityLevel ~= nil then
        safeSetProperty(settings().Rendering, "QualityLevel", originalSettings.QualityLevel)
    end
    if originalSettings.EnableShadowMap ~= nil then
        pcall(function()
            settings().Rendering.EnableShadowMap = originalSettings.EnableShadowMap
        end)
    end
    if originalSettings.MeshPartDetailLevel ~= nil then
        pcall(function()
            settings().Rendering.MeshPartDetailLevel = originalSettings.MeshPartDetailLevel
        end)
    end
    
    -- Kembalikan setting terrain
    for _, terrain in pairs(Workspace:GetChildren()) do
        if terrain:IsA("Terrain") then
            if originalSettings.WaterWaveSize ~= nil then
                safeSetProperty(terrain, "WaterWaveSize", originalSettings.WaterWaveSize)
            end
            if originalSettings.WaterWaveSpeed ~= nil then
                safeSetProperty(terrain, "WaterWaveSpeed", originalSettings.WaterWaveSpeed)
            end
            if originalSettings.WaterReflectance ~= nil then
                safeSetProperty(terrain, "WaterReflectance", originalSettings.WaterReflectance)
            end
            if originalSettings.WaterTransparency ~= nil then
                safeSetProperty(terrain, "WaterTransparency", originalSettings.WaterTransparency)
            end
        end
    end
    
    -- Kembalikan FOV kamera
    local Camera = Workspace.CurrentCamera
    if originalSettings.CameraFieldOfView ~= nil then
        safeSetProperty(Camera, "FieldOfView", originalSettings.CameraFieldOfView)
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