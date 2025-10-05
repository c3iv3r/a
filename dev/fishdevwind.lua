local Logger       = loadstring(game:HttpGet("https://raw.githubusercontent.com/c3iv3r/a/refs/heads/main/utils/logger.lua"))()

-- FOR PRODUCTION: Uncomment this line to disable all logging
--Logger.disableAll()

-- FOR DEVELOPMENT: Enable all logging
Logger.enableAll()

local mainLogger = Logger.new("Main")
local featureLogger = Logger.new("FeatureManager")

local Noctis       = loadstring(game:HttpGet("https://raw.githubusercontent.com/c3iv3r/WindUI/refs/heads/main/dist/main.lua"))()
local SaveManager  = loadstring(game:HttpGet("https://raw.githubusercontent.com/hailazra/Obsidian/refs/heads/main/addons/SaveManager.lua"))()

-- ===========================
-- LOAD HELPERS & FEATURE MANAGER
-- ===========================
mainLogger:info("Loading Helpers...")
local Helpers = loadstring(game:HttpGet("https://raw.githubusercontent.com/c3iv3r/a/refs/heads/main/module/f-pub/helpers.lua"))()

mainLogger:info("Loading FeatureManager...")
local FeatureManager = loadstring(game:HttpGet("https://raw.githubusercontent.com/c3iv3r/a/refs/heads/main/module/f/featuremanager.lua"))()

-- ===========================
-- GLOBAL SERVICES & VARIABLES
-- ===========================
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local LocalPlayer = Players.LocalPlayer
local HttpService = game:GetService("HttpService")

-- Make global for features to access
_G.GameServices = {
    Players = Players,
    ReplicatedStorage = ReplicatedStorage,
    RunService = RunService,
    LocalPlayer = LocalPlayer,
    HttpService = HttpService
}

-- Safe network path access
local NetPath = nil
pcall(function()
    NetPath = ReplicatedStorage:WaitForChild("Packages"):WaitForChild("_Index"):WaitForChild("sleitnick_net@0.2.0"):WaitForChild("net")
end)
_G.NetPath = NetPath

-- Load InventoryWatcher globally for features that need it
_G.InventoryWatcher = nil
pcall(function()
    _G.InventoryWatcher = loadstring(game:HttpGet("https://raw.githubusercontent.com/c3iv3r/a/refs/heads/main/utils/fishit/inventdetect.lua"))()
end)

-- Cache helper results
local listRod = Helpers.getFishingRodNames()
local weatherName = Helpers.getWeatherNames()
local eventNames = Helpers.getEventNames()
local rarityName = Helpers.getTierNames()
local fishName = Helpers.getFishNames()
local enchantName = Helpers.getEnchantName()

local CancelFishingEvent = ReplicatedStorage.Packages._Index["sleitnick_net@0.2.0"].net["RF/CancelFishingInputs"]

--- NOCTIS TITLE
local c = Color3.fromRGB(125, 85, 255)
local title = ('<font color="#%s">NOCTIS</font>'):format(c:ToHex())

-- ===========================
-- INITIALIZE FEATURE MANAGER
-- ===========================
mainLogger:info("Initializing features synchronously...")
local loadedCount, totalCount = FeatureManager:InitializeAllFeatures(Noctis, featureLogger)
mainLogger:info(string.format("Features ready: %d/%d", loadedCount, totalCount))


Noctis.TransparencyValue = 0.2
Noctis:SetTheme("Indigo")

local function gradient(text, startColor, endColor)
    local result = ""
    for i = 1, #text do
        local t = (i - 1) / (#text - 1)
        local r = math.floor((startColor.R + (endColor.R - startColor.R) * t) * 255)
        local g = math.floor((startColor.G + (endColor.G - startColor.G) * t) * 255)
        local b = math.floor((startColor.B + (endColor.B - startColor.B) * t) * 255)
        result = result .. string.format('<font color="rgb(%d,%d,%d)">%s</font>', r, g, b, text:sub(i, i))
    end
    return result
end


local Window = Noctis:CreateWindow({
    Title = "Noctis | v0.0.2",
    Icon = "rbxassetid://123156553209294",
    Author = "discord.gg/Noctis",
    Folder = "Noctis",
    Size = UDim2.fromOffset(400, 350),
    Theme = "Indigo",
    Transparent = true,
    HidePanelBackground = false,
    NewElements = false,
    BackgroundImageTransparency = 0.42,
    Acrylic = false,
    HideSearchBar = true,
    SideBarWidth = 140,
    AutoScale = false,
    Resizable = false
    
})


Window:SetIconSize(24)

local Home = Window:Tab({Title = "Home", Icon = "house"})
local Main = Window:Tab({Title = "Main", Icon = "gamepad"})
local Backpack = Window:Tab({Title = "Backpack", Icon = "backpack"})
local Automation = Window:Tab({Title = "Automation", Icon = "workflow"})
local Shop = Window:Tab({Title = "Shop", Icon = "shopping-bag"})
local Teleport = Window:Tab({Title = "Teleport", Icon = "map"})
local Misc = Window:Tab({Title = "Misc", Icon = "cog"})
local Setting = Window:Tab({Title = "Setting", Icon = "settings"})

--- FISHING
local autoFishV1Feature = FeatureManager:Get("AutoFish") 
local autoFishV2Feature = FeatureManager:Get("AutoFishV2") 
local autoFishV3Feature = FeatureManager:Get("AutoFishV3")
local autoFixFishFeature = FeatureManager:Get("AutoFixFishing")

local FishingSec = Main:Section({
    Title = "Section",
    Box = false,
    TextTransparency = 0.05,
    TextXAlignment = "Left",
    TextSize = 17,
    Opened = true })
    do
        autofishv1_tgl = FishingSec:Toggle("autofishv1tgl", {
           Title = "Auto Fishing V1",
           Desc = "Faster but unstable",
           Default = false,
           Callback = function(state)
               if state then
            -- Silently stop V2 if running
            if autoFishV2Feature and autoFishV2Feature.Stop then
                autoFishV2Feature:Stop()
            end
            
            -- Start V1
            if autoFishV1Feature and autoFishV1Feature.Start then
                autoFishV1Feature:Start({ mode = "Fast" })
            end
        else
            -- Stop V1
            if autoFishV1Feature and autoFishV1Feature.Stop then
                autoFishV1Feature:Stop()
            end
        end
    end
})      
        autofishv2_tgl = FishingSec:Toggle("autofishv2tgl", {
           Title = "Auto Fishing V2",
           Desc = "Slower but stable",
           Default = false,
           Callback = function(state)
            if state then
            -- Silently stop V1 if running
            if autoFishV1Feature and autoFishV1Feature.Stop then
                autoFishV1Feature:Stop()
            end
            
            -- Start V2
            if autoFishV2Feature then
                if autoFishV2Feature.SetMode then 
                    autoFishV2Feature:SetMode("Fast") 
                end
                if autoFishV2Feature.Start then 
                    autoFishV2Feature:Start({ mode = "Fast" }) 
                end
            end
        else
            -- Stop V2
            if autoFishV2Feature and autoFishV2Feature.Stop then
                autoFishV2Feature:Stop()
            end
        end
    end
})      
        autofishv3_tgl = FishingSec:Toggle("autofishv3tgl", {
           Title = "Auto Fishing V3",
           Desc = "Normal fishing with animation.",
           Default = false,
           Callback = function(state)
            if state then
            -- Start V1
            if autoFishV3Feature and autoFishV3Feature.Start then
                autoFishV3Feature:Start({ mode = "Fast" })
            end
        else
            -- Stop V1
            if autoFishV3Feature and autoFishV3Feature.Stop then
                autoFishV3Feature:Stop()
            end
        end
    end
})

if autoFishV1Feature then
    autoFishV1Feature.__controls = {
        toggle = autofishv1_tgl
    }

    if autoFishV1Feature.Init and not autoFishV1Feature.__initialized then
        autoFishV1Feature:Init(autoFishV1Feature.__controls)
        autoFishV1Feature.__initialized = true
    end
end

if autoFishV2Feature then
    autoFishV2Feature.__controls = {
        toggle = autofishv2_tgl
    }

    if autoFishV2Feature.Init and not autoFishV2Feature.__initialized then
        autoFishV2Feature:Init(autoFishV2Feature.__controls)
        autoFishV2Feature.__initialized = true
    end
end

if autoFishV3Feature then
    autoFishV3Feature.__controls = {
        toggle = autofishv3_tgl
    }

    if autoFishV3Feature.Init and not autoFishV3Feature.__initialized then
        autoFishV3Feature:Init(autoFishV3Feature.__controls)
        autoFishV3Feature.__initialized = true
    end
end

--- CANCEL FISHING
autofixfish_tgl = FishingSec:Toggle("fixfishingtgl", {
           Title = "Auto Fishing",
           Desc = "Automatically fix fishing if stuck",
           Default = false,
           Callback = function(Value)
            if Value then
            autoFixFishFeature:Start()
        else
            autoFixFishFeature:Stop()
        end
    end
})

if autoFixFishFeature then  
    autoFixFishFeature.__controls = {  
        toggle = autofixfish_tgl
    }
    if autoFixFishFeature.Init and not autoFixFishFeature.__initialized then
        autoFixFishFeature:Init(autoFixFishFeature.__controls) 
        autoFixFishFeature.__initialized = true
    end
end
    
cancelautofish_btn = FishingSec:Button({
    Title = "Cancel Fishing",
    Desc = "",
    Locked = false,
    Callback = function()
        if CancelFishingEvent and CancelFishingEvent.InvokeServer then
            local success, result = pcall(function()
                return CancelFishingEvent:InvokeServer()
            end)

            if success then
                mainLogger:info("[CancelFishingInputs] Fixed", result)
            else
                 mainLogger:warn("[CancelFishingInputs] Error, Report to Dev", result)
            end
        else
             mainLogger:warn("[CancelFishingInputs] Report this bug to Dev")
        end
    end
})
end