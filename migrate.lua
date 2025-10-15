local Noctis = loadstring(game:HttpGet("https://raw.githubusercontent.com/c3iv3r/a/refs/heads/main/lib.lua"))()

local Helpers = loadstring(game:HttpGet("https://raw.githubusercontent.com/c3iv3r/a/refs/heads/main/module/f-pub/helpers.lua"))()

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
local Group = Window:TabGroup()
local Home = Group:Tab({ Title = "Home", Image = "rbxassetid://123156553209294"})
local Main = Group:Tab({ Title = "Main", Image = "rbxassetid://123156553209294"})
local Backpack = Group:Tab({ Title = "Backpack", Image = "rbxassetid://123156553209294"})
local Automation = Group:Tab({ Title = "Automation", Image = "rbxassetid://123156553209294"})
local Teleprort = Group:Tab({ Title = "Teleport", Image = "rbxassetid://123156553209294"})
local Misc = Group:Tab({ Title = "Misc", Image = "rbxassetid://123156553209294"})
local Setting = Group:Tab({ Title = "Settings", Image = "rbxassetid://123156553209294"})

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
local Information = Home:Section({ Title = "Information", Opened = true })
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
	Title = gradient("Player Stats", Color3.fromHex("#6A11CB"), Color3.fromHex("#2575FC")),
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
