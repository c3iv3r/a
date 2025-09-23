-- BoostFPS Feature untuk Fish It
-- Mengurangi kualitas grafis untuk meningkatkan FPS

local BoostFPS = {}
BoostFPS.__index = BoostFPS

-- Services
local Lighting = game:GetService("Lighting")
local Workspace = game:GetService("Workspace")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

-- Logger
local Logger = _G.Logger or { info = print, warn = print, error = print }
local logger = Logger.new and Logger.new("BoostFPS") or Logger

-- State
local isActive = false
local originalSettings = {}

-- Function untuk menyimpan pengaturan asli
local function saveOriginalSettings()
    originalSettings = {
        -- Lighting settings
        Brightness = Lighting.Brightness,
        GlobalShadows = Lighting.GlobalShadows,
        FogEnd = Lighting.FogEnd,
        FogStart = Lighting.FogStart,
        
        -- Workspace settings
        StreamingEnabled = Workspace.StreamingEnabled,
        
        -- Render settings
        QualityLevel = settings().Rendering.QualityLevel,
    }
    
    -- Simpan effects di Lighting (hanya PostEffect yang punya Enabled)
    for _, effect in pairs(Lighting:GetChildren()) do
        if effect:IsA("PostEffect") then
            originalSettings[effect.Name] = effect.Enabled
        elseif effect:IsA("Atmosphere") then
            -- Atmosphere properties
            originalSettings["AtmosphereDensity"] = effect.Density
            originalSettings["AtmosphereOffset"] = effect.Offset
            originalSettings["AtmosphereColor"] = effect.Color
            originalSettings["AtmosphereDecay"] = effect.Decay
            originalSettings["AtmosphereGlare"] = effect.Glare
            originalSettings["AtmosphereHaze"] = effect.Haze
        end
    end
    
    logger:info("Original settings saved")
end

-- Function untuk apply low quality settings
local function applyLowQualitySettings()
    -- Lighting optimizations
    Lighting.GlobalShadows = false
    Lighting.FogEnd = 9e9
    Lighting.FogStart = 0
    Lighting.Brightness = 0
    
    -- Handle effects di Lighting
    for _, effect in pairs(Lighting:GetChildren()) do
        if effect:IsA("PostEffect") then
            -- PostEffect punya property Enabled
            pcall(function() effect.Enabled = false end)
        elseif effect:IsA("Atmosphere") then
            -- Atmosphere ga punya Enabled, tapi bisa set properties ke minimum
            pcall(function() 
                effect.Density = 0
                effect.Offset = 0
                effect.Glare = 0
                effect.Haze = 0
            end)
        end
    end
    
    -- Render quality ke minimum
    pcall(function()
        settings().Rendering.QualityLevel = Enum.QualityLevel.Level01
    end)
    
    -- Workspace optimizations
    pcall(function()
        Workspace.StreamingEnabled = true
    end)
    
    logger:info("Low quality settings applied")
end

-- Function untuk reduce part details
local function optimizeParts()
    local function processInstance(instance)
        -- Skip player character dan important objects
        local player = game.Players.LocalPlayer
        if player and player.Character and instance:IsDescendantOf(player.Character) then
            return
        end
        
        if instance:IsA("BasePart") then
            -- Reduce material quality
            if instance.Material ~= Enum.Material.Air then
                instance.Material = Enum.Material.Plastic
            end
            
            -- Remove textures/decals untuk performance
            for _, child in pairs(instance:GetChildren()) do
                if child:IsA("Decal") or child:IsA("Texture") or child:IsA("SurfaceGui") then
                    child.Transparency = 1
                end
            end
        elseif instance:IsA("ParticleEmitter") then
            -- Disable particle effects
            instance.Enabled = false
        elseif instance:IsA("Fire") or instance:IsA("Smoke") or instance:IsA("Sparkles") then
            -- Disable special effects
            instance.Enabled = false
        end
        
        -- Process children
        for _, child in pairs(instance:GetChildren()) do
            processInstance(child)
        end
    end
    
    -- Process workspace
    processInstance(Workspace)
    logger:info("Parts optimized")
end

-- Function untuk disable unnecessary services
local function disableUnnecessaryFeatures()
    -- Disable tween animations untuk performance
    for _, tween in pairs(TweenService:GetTweens()) do
        if tween.PlaybackState == Enum.PlaybackState.Playing then
            tween:Pause()
        end
    end
    
    logger:info("Unnecessary features disabled")
end

-- Main function untuk boost FPS
function BoostFPS:Start()
    if isActive then
        logger:warn("BoostFPS already active")
        return
    end
    
    logger:info("Starting FPS boost...")
    
    -- Save original settings first
    saveOriginalSettings()
    
    -- Apply optimizations
    applyLowQualitySettings()
    
    -- Wait sedikit untuk loading
    task.wait(0.5)
    
    -- Optimize parts
    optimizeParts()
    
    -- Disable unnecessary features
    disableUnnecessaryFeatures()
    
    isActive = true
    
    logger:info("FPS boost activated! Game quality reduced for better performance.")
    
    -- Notify user
    if _G.Noctis then
        _G.Noctis:Notify({
            Title = "BoostFPS",
            Description = "FPS optimization applied! Graphics quality reduced.",
            Duration = 3
        })
    end
end

-- Check if boost is active
function BoostFPS:IsActive()
    return isActive
end

-- Get status info
function BoostFPS:GetStatus()
    return {
        active = isActive,
        appliedOptimizations = isActive and {
            "Low quality rendering",
            "Disabled shadows",
            "Reduced fog",
            "Disabled effects",
            "Optimized materials"
        } or {}
    }
end

-- Initialize controls (dipanggil dari GUI)
function BoostFPS:Init(controls)
    self.__controls = controls or {}
    logger:info("BoostFPS initialized")
    return self
end

-- Create new instance
function BoostFPS.new()
    local self = setmetatable({}, BoostFPS)
    return self
end

return BoostFPS