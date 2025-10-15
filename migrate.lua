local Logger       = loadstring(game:HttpGet("https://raw.githubusercontent.com/c3iv3r/a/refs/heads/main/utils/logger.lua"))()

-- FOR PRODUCTION: Uncomment this line to disable all logging
--Logger.disableAll()

-- FOR DEVELOPMENT: Enable all logging
Logger.enableAll()

local mainLogger = Logger.new("Main")
local featureLogger = Logger.new("FeatureManager")

--// Library
local Noctis = loadstring(game:HttpGet("https://raw.githubusercontent.com/c3iv3r/a/refs/heads/main/lib.lua"))()

-- ===========================
-- LOAD HELPERS & FEATURE MANAGER
-- ===========================
mainLogger:info("Loading Helpers...")
local Helpers = loadstring(game:HttpGet("https://raw.githubusercontent.com/c3iv3r/a/refs/heads/main/module/f-pub/helpers.lua"))()

mainLogger:info("Loading FeatureManager...")
local FeatureManager = loadstring(game:HttpGet("https://raw.githubusercontent.com/c3iv3r/a/refs/heads/main/module/f/featuremanager2.lua"))()

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

local Window = Noctis:Window({
	Title = "Noctis",
	Subtitle = "Fish It | v1.0.1",
	Size = UDim2.fromOffset(600, 300),
	DragStyle = 1,
	DisabledWindowControls = {},
	OpenButtonImage = "rbxassetid://123156553209294", 
	OpenButtonSize = UDim2.fromOffset(32, 32),
	OpenButtonPosition = UDim2.fromScale(0.45, 0.1),
	Keybind = Enum.KeyCode.RightControl,
	AcrylicBlur = true,
})

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

--- === TAB === ---
local Group      = Window:TabGroup()
local Home       = Group:Tab({ Title = "Home", Image = "house"})
local Main       = Group:Tab({ Title = "Main", Image = "gamepad"})
local Backpack   = Group:Tab({ Title = "Backpack", Image = "backpack"})
local Automation = Group:Tab({ Title = "Automation", Image = "workflow"})
local Shop       = Group:Tab({ Title = "Shop", Image = "shopping-bag"})
local Teleprort  = Group:Tab({ Title = "Teleport", Image = "map"})
local Misc       = Group:Tab({ Title = "Misc", Image = "cog"})
local Setting    = Group:Tab({ Title = "Settings", Image = "settings"})

--- === CHANGELOG & DISCORD LINK === ---
local CHANGELOG = table.concat({
    "[+] Added LocalPlayer",
    "[+] Added New Island to Teleport Island",
    "[+] Added Quest Info",
    "[+] Added Auto Enchant Slot 2",
    "[+] Added No Animation",
    "[+] Added Auto Submit SECRET to Temple Guardian"
}, "\n")
local DISCORD = table.concat({
    "https://discord.gg/3AzvRJFT3M",
}, "\n")

--- === HOME === ---
--- === INFORMATION === ---
local Information = Home:Section({ Title = "<b>Information</b>", Opened = true })
Information:Paragraph({
	Title = "<b>Information</b>",
	Desc = CHANGELOG
})
Information:Button({
	Title = "<b>Join Discord</b>",
	Callback = function()
		if typeof(setclipboard) == "function" then
            setclipboard(DISCORD)
            Window:Notify({ Title = title, Desc = "Discord link copied!", Duration = 2 })
        else
            Window:Notify({ Title = title, Desc = "Clipboard not available", Duration = 3 })
        end
    end
})
Information:Divider()
local PlayerInfoParagraph = Information:Paragraph({
	Title = gradient("<b>Player Stats</b>", Color3.fromHex("#6A11CB"), Color3.fromHex("#2575FC")),
	Desc = ""
})
local inventoryWatcher = _G.InventoryWatcher and _G.InventoryWatcher.new()

-- Variabel untuk nyimpen nilai-nilai
local caughtValue = "0"
local rarestValue = "-"
local fishesCount = "0"
local itemsCount = "0"

-- Function untuk update desc paragraph
local function updatePlayerInfoDesc()
    local descText = string.format(
        "<b>Statistics</b>\nCaught: %s\nRarest Fish: %s\n\n<b>Inventory</b>\nFishes: %s\nItems: %s",
        caughtValue,
        rarestValue,
        fishesCount,
        itemsCount
    )
    PlayerInfoParagraph:SetDesc(descText)
end

-- Update inventory counts
if inventoryWatcher then
    inventoryWatcher:onReady(function()
        local function updateInventory()
            local counts = inventoryWatcher:getCountsByType()
            fishesCount = tostring(counts["Fishes"] or 0)
            itemsCount = tostring(counts["Items"] or 0)
            updatePlayerInfoDesc()
        end
        updateInventory()
        inventoryWatcher:onChanged(updateInventory)
    end)
end

-- Update caught value
local function updateCaught()
    caughtValue = tostring(Helpers.getCaughtValue())
    updatePlayerInfoDesc()
end

local function connectToCaughtChanges()
    local leaderstats = LocalPlayer:FindFirstChild("leaderstats")
    if leaderstats then
        local caught = leaderstats:FindFirstChild("Caught")
        if caught and caught:IsA("IntValue") then
            caught:GetPropertyChangedSignal("Value"):Connect(updateCaught)
        end
    end
end

-- Update rarest value
local function updateRarest()
    rarestValue = tostring(Helpers.getRarestValue())
    updatePlayerInfoDesc()
end

local function connectToRarestChanges()
    local leaderstats = LocalPlayer:FindFirstChild("leaderstats")
    if leaderstats then
        local rarest = leaderstats:FindFirstChild("Rarest Fish")
        if rarest and rarest:IsA("StringValue") then
            rarest:GetPropertyChangedSignal("Value"):Connect(updateRarest)
        end
    end
end

-- Initialize
LocalPlayer:WaitForChild("leaderstats")
connectToCaughtChanges()
connectToRarestChanges()
updateCaught()
updateRarest()

--- === MAIN === ---
--- === FISHING === ---
local Fishing = Main:Section({ Title = "<b>Fishing</b>", Opened = true })
local autoFishV1Feature = FeatureManager:Get("AutoFish")   -- Old Version
local autoFishV2Feature = FeatureManager:Get("AutoFishV2") -- New Version
local autoFishV3Feature = FeatureManager:Get("AutoFishV3")
if autoFishV1Feature and autoFishV1Feature.Init and not autoFishV1Feature.__initialized then
    autoFishV1Feature:Init()
    autoFishV1Feature.__initialized = true
end

if autoFishV2Feature and autoFishV2Feature.Init and not autoFishV2Feature.__initialized then
    autoFishV2Feature:Init()
    autoFishV2Feature.__initialized = true
end

if autoFishV3Feature and autoFishV3Feature.Init and not autoFishV3Feature.__initialized then
    autoFishV3Feature:Init()
    autoFishV3Feature.__initialized = true
end

-- State tracking
local currentMethod = "V1" -- default
local isAutoFishActive = false

-- Function untuk stop semua
local function stopAllAutoFish()
    if autoFishV1Feature and autoFishV1Feature.Stop then
        autoFishV1Feature:Stop()
    end
    if autoFishV2Feature and autoFishV2Feature.Stop then
        autoFishV2Feature:Stop()
    end
    if autoFishV3Feature and autoFishV3Feature.Stop then
        autoFishV3Feature:Stop()
    end
end

-- Function untuk start sesuai method
local function startAutoFish(method)
    stopAllAutoFish() -- stop dulu yang lain
    
    if method == "V1" then
        if autoFishV1Feature and autoFishV1Feature.Start then
            autoFishV1Feature:Start({ mode = "Fast" })
        end
    elseif method == "V2" then
        if autoFishV2Feature and autoFishV2Feature.Start then
            autoFishV2Feature:Start({ mode = "Fast" })
        end
    elseif method == "V3" then
        if autoFishV3Feature and autoFishV3Feature.Start then
            autoFishV3Feature:Start({ mode = "Fast" })
        end
    end
end

local autofish_dd = Fishing:Dropdown({
	Title = "<b>Select Mode</b>",
	Search = true,
	Multi = false,
	Required = false,
	Options = {"Fast", "Stable", "Normal"},
    Default = "Fast",
	Callback = function(v)
		-- Map dropdown value ke method
        if v == "Fast" then
            currentMethod = "V1"
        elseif value == "Stable" then
            currentMethod = "V2"
        elseif value == "Normal" then
            currentMethod = "V3"
        end
        
        -- Kalo lagi aktif, restart dengan method baru
        if isAutoFishActive then
            startAutoFish(currentMethod)
        end
    end
}, "autofishdd")

local autofish_tgl = Fishing:Toggle({
	Title = "<b>Auto Fishing</b>",
	Default = false,
	Callback = function(v)
        isAutoFishActive = v
        
        if v then
            -- Start dengan method yang dipilih
            startAutoFish(currentMethod)
        else
            -- Stop semua
            stopAllAutoFish()
        end
    end
}, "autofishtgl")

local noanim_tgl = Fishing:Toggle({
	Title = "<b>No Animation</b>",
	Default = false,
	Callback = function(v)
        if v then
            -- ENABLE: Stop fishing animations only
            getgenv().NoAnimEnabled = true
            
            getgenv().NoAnimLoop = RunService.Heartbeat:Connect(function()
                pcall(function()
                    local AC = require(ReplicatedStorage.Controllers.AnimationController)
                    -- DestroyActiveAnimationTracks tanpa parameter = destroy semua
                    -- Dengan whitelist = destroy semua KECUALI yang di whitelist
                    -- Kita kasih whitelist kosong biar destroy semua fishing animations
                    AC:DestroyActiveAnimationTracks({})
                end)
            end)
        else
            -- DISABLE: Stop loop
            getgenv().NoAnimEnabled = false
            if getgenv().NoAnimLoop then
                getgenv().NoAnimLoop:Disconnect()
                getgenv().NoAnimLoop = nil
            end
        end
    end
}, "noanimtgl")

task.defer(function()
    task.wait(0.1)
    Window:Notify({
        Title = title,
        Desc = "Enjoy! Join Our Discord!",
        Duration = 3
    })
end)