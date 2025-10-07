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

--- === CHANGELOG & DC LINK === ---
local CHANGELOG = table.concat({
    "[+] Added Auto Fishing V3 (Animation)",
    "Report bugs to our Discord"
}, "\n")
local DISCORD = table.concat({
    "https://discord.gg/3AzvRJFT3M",
}, "\n")

--- === HOME === ---
Home:Section({
    Title = gradient("Home", Color3.fromHex("#6A11CB"), Color3.fromHex("#2575FC")),
    TextSize = 25 })
Home:Divider()
Home:Paragraph({
    Title = gradient("Information", Color3.fromHex("#6A11CB"), Color3.fromHex("#2575FC")),
    Desc = CHANGELOG,
    Buttons = {
        {
            Icon = "",
            Title = "Discord",
            Callback = function()
                 if typeof(setclipboard) == "function" then
            setclipboard(DISCORD)
            Noctis:Notify({ Title = title, Content = "Discord link copied!", Duration = 2 })
        else
            Noctis:Notify({ Title = title, Content = "Clipboard not available", Duration = 3 })
        end
    end
        }
    }
})
-- Buat paragraph dengan desc kosong dulu
local PlayerInfoParagraph = Home:Paragraph({Title = gradient("Player Information", Color3.fromHex("#6A11CB"), Color3.fromHex("#2575FC")), Desc = ""})

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
Main:Section({
    Title = gradient("Main", Color3.fromHex("#6A11CB"), Color3.fromHex("#2575FC")),
    TextSize = 25 })
Main:Divider()
--- FISHING
local autoFishV1Feature = FeatureManager:Get("AutoFish") 
local autoFishV2Feature = FeatureManager:Get("AutoFishV2") 
local autoFishV3Feature = FeatureManager:Get("AutoFishV3")
local autoFixFishFeature = FeatureManager:Get("AutoFixFishing")

local FishingSec = Main:Section({
    Title = "Fishing",
    Box = false,
    Icon = "fish",
    TextTransparency = 0.05,
    TextXAlignment = "Left",
    TextSize = 17,
    Opened = false })
    do
        autofishv1_tgl = FishingSec:Toggle({
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
        autofishv2_tgl = FishingSec:Toggle({
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
        autofishv3_tgl = FishingSec:Toggle({
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
autofixfish_tgl = FishingSec:Toggle({
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

--- SAVE POSITION
local savePositionFeature = FeatureManager:Get("SavePosition")
local SaveposSec = Main:Section({
    Title = "Save Position",
    Box = false,
    Icon = "anchor",
    TextTransparency = 0.05,
    TextXAlignment = "Left",
    TextSize = 17,
    Opened = false }) do
        savepos_tgl = SaveposSec:Toggle({
           Title = "Save Position",
           Desc = "Save current position",
           Default = false,
           Callback = function(Value)
            if Value then savePositionFeature:Start() else savePositionFeature:Stop() end
    end
})

if savePositionFeature then
    savePositionFeature.__controls = {
        toggle = savepos_tgl
    }
    
    if savePositionFeature.Init and not savePositionFeature.__initialized then
        savePositionFeature:Init(savePositionFeature, savePositionFeature.__controls)
        savePositionFeature.__initialized = true
    end
end
end

--- EVENT
local eventteleFeature = FeatureManager:Get("AutoTeleportEvent")
local selectedEventsArray = {}
local EventSec = Main:Section({
    Title = "Event",
    Box = false,
    Icon = "calendar-plus-2",
    TextTransparency = 0.05,
    TextXAlignment = "Left",
    TextSize = 17,
    Opened = false }) do

eventtele_ddm = EventSec:Dropdown({
    Title = "Select Event",
    Values = eventNames,
    Value = {},
    SearchBarEnabled = true,
    Multi = true,
    AllowNone = true,
    Callback = function(Values)
    selectedEventsArray = Helpers.normalizeList(Values or {})   
        if eventteleFeature and eventteleFeature.SetSelectedEvents then
            eventteleFeature:SetSelectedEvents(selectedEventsArray)
        end
    end
})

eventtele_tgl = EventSec:Toggle({
           Title = "Auto Teleport",
           Desc = "Automatically teleport to selected Event",
           Default = false,
           Callback = function(Value)
        if Value and eventteleFeature then
            local arr = Helpers.normalizeList(selectedEventsArray or {})
            if eventteleFeature.SetSelectedEvents then eventteleFeature:SetSelectedEvents(arr) end
            if eventteleFeature.Start then
                eventteleFeature:Start({ selectedEvents = arr, hoverHeight = 12 })
            end
        elseif eventteleFeature and eventteleFeature.Stop then
            eventteleFeature:Stop()
        end
    end
})
if eventteleFeature then
    eventteleFeature.__controls = {
        Dropdown = eventtele_ddm,
        toggle = eventtele_tgl
    }
    
    if eventteleFeature.Init and not eventteleFeature.__initialized then
        eventteleFeature:Init(eventteleFeature, eventteleFeature.__controls)
        eventteleFeature.__initialized = true
    end
end
end

--- === BACKPACK === ---
Backpack:Section({
    Title = gradient("Backpack", Color3.fromHex("#6A11CB"), Color3.fromHex("#2575FC")),
    TextSize = 25 })
Backpack:Divider()
--- FAVORITE FISH
local autoFavFishFeature =  FeatureManager:Get("AutoFavoriteFish")
local autoFavFishV2Feature = FeatureManager:Get("AutoFavoriteFishV2")
local selectedFishNames = {}
local selectedTiers = {}
local FavFishSec = Backpack:Section({
    Title = "Favorite Fish",
    Box = false,
    Icon = "star",
    TextTransparency = 0.05,
    TextXAlignment = "Left",
    TextSize = 17,
    Opened = false }) do

FavFishSec:Paragraph({
    Title = gradient("By Rarity", Color3.fromHex("#6A11CB"), Color3.fromHex("#2575FC"))
})
        
favfish_ddm = FavFishSec:Dropdown({
    Title = "Select Rarity",
    Values = rarityName,
    Value = {},
    SearchBarEnabled = true,
    Multi = true,
    AllowNone = true,
    Callback = function(Values)
        selectedTiers = Values or {}
        if autoFavFishFeature and autoFavFishFeature.SetDesiredTiersByNames then
           autoFavFishFeature:SetDesiredTiersByNames(selectedTiers)
        end
    end
})
favfish_tgl = FavFishSec:Toggle({
           Title = "Favorite by Rarity",
           Desc = "Automatically Favorite fish with selected rarity",
           Default = false,
           Callback = function(Value)
             if Value and autoFavFishFeature then
            if autoFavFishFeature.SetDesiredTiersByNames then autoFavFishFeature:SetDesiredTiersByNames(selectedTiers) end
            if autoFavFishFeature.Start then autoFavFishFeature:Start({ tierList = selectedTiers }) end
        elseif autoFavFishFeature and autoFavFishFeature.Stop then
            autoFavFishFeature:Stop()
        end
    end
})

FavFishSec:Paragraph({
    Title = gradient("By Name", Color3.fromHex("#6A11CB"), Color3.fromHex("#2575FC"))
})

favfishv2_ddm = FavFishSec:Dropdown({
    Title = "Select Fish",
    Values = Helpers.getFishNamesForTrade(),
    Value = {},
    SearchBarEnabled = true,
    Multi = true,
    AllowNone = true,
    Callback = function(Values)
         selectedFishNames = Values or {}
        if autoFavFishV2Feature and autoFavFishV2Feature.SetSelectedFishNames then
           autoFavFishV2Feature:SetSelectedFishNames(selectedFishNames)
        end
    end
})

favfish_tgl = FavFishSec:Toggle({
           Title = "Favorite by Name",
           Desc = "Automatically Favorite fish with selected name",
           Default = false,
           Callback = function(Value)
           if Value and autoFavFishV2Feature then
            if autoFavFishV2Feature.SetSelectedFishNames then 
                autoFavFishV2Feature:SetSelectedFishNames(selectedFishNames) 
            end
            if autoFavFishV2Feature.Start then 
                autoFavFishV2Feature:Start({ fishNames = selectedFishNames }) 
            end
        elseif autoFavFishV2Feature and autoFavFishV2Feature.Stop then
            autoFavFishV2Feature:Stop()
        end
    end
})

if autoFavFishFeature then
    autoFavFishFeature.__controls = {
        Dropdown = favfish_ddm,
        toggle = favfish_tgl
    }
    
    if autoFavFishFeature.Init and not autoFavFishFeature.__initialized then
        autoFavFishFeature:Init(autoFavFishFeature, autoFavFishFeature.__controls)
        autoFavFishFeature.__initialized = true
    end
end

if autoFavFishV2Feature then
    autoFavFishV2Feature.__controls = {
        fishDropdown = favfishv2_ddm,
        toggle = favfishv2_tgl
    }
    
    if autoFavFishV2Feature.Init and not autoFavFishV2Feature.__initialized then
        autoFavFishV2Feature:Init(autoFavFishV2Feature.__controls)
        autoFavFishV2Feature.__initialized = true
    end
end
end

--- SELL FISH
local sellfishFeature        = FeatureManager:Get("AutoSellFish")
local currentSellThreshold   = "Legendary"
local currentSellLimit       = 0
local SellFishSec = Backpack:Section({
    Title = "Sell Fish",
    Box = false,
    Icon = "badge-dollar-sign",
    TextTransparency = 0.05,
    TextXAlignment = "Left",
    TextSize = 17,
    Opened = false }) do

     sellfish_dd = SellFishSec:Dropdown({
    Title = "Select Rarity",
    Values = {"Secret", "Mythic", "Legendary"},
    Value = "Legendary",
    SearchBarEnabled = true,
    Multi = false,
    AllowNone = false,
    Callback = function(Value)
        currentSellThreshold = Value or {}
        if sellfishFeature and sellfishFeature.SetMode then
           sellfishFeature:SetMode(Value)
        end
    end
})

  sellfish_in = SellFishSec:Input({
    Title = "Delay",
    Desc = "Enter delay for auto sell",
    Value = "60",
    Type = "Input", -- or "Textarea"
    Placeholder = "e.g 60 (second)",
    Callback = function(Value) 
        local n = tonumber(Value) or 0
        currentSellLimit = n
        if sellfishFeature and sellfishFeature.SetLimit then
            sellfishFeature:SetLimit(n)
        end
    end
})

sellfish_tgl  = SellFishSec:Toggle({
           Title = "Auto Sell",
           Desc = "Automatically Sell fish with selected rarity",
           Default = false,
           Callback = function(Value)
             if Value and sellfishFeature then
            if sellfishFeature.SetMode then sellfishFeature:SetMode(currentSellThreshold) end
            if sellfishFeature.Start then sellfishFeature:Start({ 
                threshold   = currentSellThreshold,
                limit       = currentSellLimit,
                autoOnLimit = true 
            }) end
        elseif sellfishFeature and sellfishFeature.Stop then
            sellfishFeature:Stop()
        end
    end
})

if sellfishFeature then
    sellfishFeature.__controls = {
        Dropdown = sellfish_dd,
        Input    = sellfish_in,
        toggle = sellfish_tgl
    }
    
    if sellfishFeature.Init and not sellfishFeature.__initialized then
        sellfishFeature:Init(sellfishFeature, sellfishFeature.__controls)
        sellfishFeature.__initialized = true
    end
end
end

--- === AUTOMATION === ---
Automation:Section({
    Title = gradient("Automation", Color3.fromHex("#6A11CB"), Color3.fromHex("#2575FC")),
    TextSize = 25 })
Automation:Divider()
--- ENCHANT
local autoEnchantFeature = FeatureManager:Get("AutoEnchantRod")
local selectedEnchants   = {}
local EnchantSec = Automation:Section({
    Title = "Enchant",
    Box = false,
    Icon = "circle-fading-arrow-up",
    TextTransparency = 0.05,
    TextXAlignment = "Left",
    TextSize = 17,
    Opened = false }) do

        enchant_ddm = EnchantSec:Dropdown({
    Title = "Select Enchant",
    Values = enchantName,
    Value = {},
    SearchBarEnabled = true,
    Multi = true,
    AllowNone = true,
     Callback = function(Values)
        selectedEnchants = Helpers.normalizeList(Values or {})
        if autoEnchantFeature and autoEnchantFeature.SetDesiredByNames then
            autoEnchantFeature:SetDesiredByNames(selectedEnchants)
        end
    end
})

enchant_tgl  = EnchantSec:Toggle({
           Title = "Auto Enchant",
           Desc = "Automatically stopped at selected Enchant",
           Default = false,
           Callback = function(Value)
        if Value and autoEnchantFeature then
            if #selectedEnchants == 0 then
                Noctis:Notify({ Title="Info", Content="Select at least 1 enchant", Duration=3 })
                return
            end
            if autoEnchantFeature.SetDesiredByNames then
                autoEnchantFeature:SetDesiredByNames(selectedEnchants)
            end
            if autoEnchantFeature.Start then
                autoEnchantFeature:Start({
                    enchantNames = selectedEnchants,
                    delay = 8
                })
            end
        elseif autoEnchantFeature and autoEnchantFeature.Stop then
            autoEnchantFeature:Stop()
        end
    end
})
if autoEnchantFeature then
    autoEnchantFeature.__controls = {
        Dropdown = enchant_ddm,
        toggle = enchant_tgl
    }
    
    if autoEnchantFeature.Init and not autoEnchantFeature.__initialized then
        autoEnchantFeature:Init(autoEnchantFeature.__controls)
        autoEnchantFeature.__initialized = true
    end
end
end

--- TRADE
local autoTradeFeature       = FeatureManager:Get("AutoSendTrade")
local autoAcceptTradeFeature = FeatureManager:Get("AutoAcceptTrade")
local selectedTradeItems    = {}
local selectedTradeEnchants = {}
local selectedTargetPlayers = {}
local TradeSec = Automation:Section({
    Title = "Trade",
    Box = false,
    Icon = "gift",
    TextTransparency = 0.05,
    TextXAlignment = "Left",
    TextSize = 17,
    Opened = false }) do

        tradeplayer_dd = TradeSec:Dropdown({
    Title = "Select Player",
    Values = Helpers.listPlayers(true),
    Value = "",
    SearchBarEnabled = true,
    Multi = false,
    AllowNone = true,
    Callback = function(Value)
        selectedTargetPlayers = Helpers.normalizeList(Value or {})
        if autoTradeFeature and autoTradeFeature.SetTargetPlayers then
            autoTradeFeature:SetTargetPlayers(selectedTargetPlayers)
        end
    end
})

tradeitem_ddm = TradeSec:Dropdown({
    Title = "Select Fish",
    Values = Helpers.getFishNamesForTrade(),
    Value = {},
    SearchBarEnabled = true,
    Multi = true,
    AllowNone = true,
    Callback = function(Values)
        selectedTradeItems = Helpers.normalizeList(Values or {})
        if autoTradeFeature and autoTradeFeature.SetSelectedFish then
            autoTradeFeature:SetSelectedFish(selectedTradeItems)
        end
    end
})

tradeenchant_ddm = TradeSec:Dropdown({
    Title = "Select Enchant",
    Values = Helpers.getEnchantStonesForTrade(),
    Value = {},
    SearchBarEnabled = true,
    Multi = true,
    AllowNone = true,
    Callback = function(Values)
        selectedTradeEnchants = Helpers.normalizeList(Values or {})
        if autoTradeFeature and autoTradeFeature.SetSelectedItems then
            autoTradeFeature:SetSelectedItems(selectedTradeEnchants)
        end
    end
})

 tradelay_in = TradeSec:Input({
    Title = "Delay",
    Desc = "Enter delay for auto trade",
    Value = "15",
    Type = "Input", -- or "Textarea"
    Placeholder = "e.g 15 (second)",
    Callback = function(Value)
        local delay = math.max(1, tonumber(Value) or 5)
        if autoTradeFeature and autoTradeFeature.SetTradeDelay then
            autoTradeFeature:SetTradeDelay(delay)
        end
    end
})

traderefresh_btn = TradeSec:Button({
    Title = "Refresh Player List",
    Desc = "",
    Locked = false,
    Callback = function()
         local names = Helpers.listPlayers(true)
        if tradeplayer_dd.Refresh then tradeplayer_dd:Refresh(names) end
        Noctis:Notify({ Title = "Players", Content = ("Online: %d"):format(#names), Duration = 2 })
    end
})

tradesend_tgl  = TradeSec:Toggle({
           Title = "Auto Send Trade",
           Desc = "Automatically send trade",
           Default = false,
           Callback = function(Value)
        if Value and autoTradeFeature then
            if #selectedTradeItems == 0 and #selectedTradeEnchants == 0 then
                Noctis:Notify({ Title="Info", Content="Select at least 1 fish or enchant stone first", Duration=3 })
                return
            end
            if #selectedTargetPlayers == 0 then
                Noctis:Notify({ Title="Info", Content="Select at least 1 target player", Duration=3 })
                return
            end

            local delay = math.max(1, tonumber(tradelay_in.Value) or 5)
            if autoTradeFeature.SetSelectedFish then autoTradeFeature:SetSelectedFish(selectedTradeItems) end
            if autoTradeFeature.SetSelectedItems then autoTradeFeature:SetSelectedItems(selectedTradeEnchants) end
            if autoTradeFeature.SetTargetPlayers then autoTradeFeature:SetTargetPlayers(selectedTargetPlayers) end
            if autoTradeFeature.SetTradeDelay then autoTradeFeature:SetTradeDelay(delay) end

            autoTradeFeature:Start({
                fishNames  = selectedTradeItems,
                itemNames  = selectedTradeEnchants,
                playerList = selectedTargetPlayers,
                tradeDelay = delay,
            })
        elseif autoTradeFeature and autoTradeFeature.Stop then
            autoTradeFeature:Stop()
        end
    end
})

if autoTradeFeature then
    autoTradeFeature.__controls = {
        playerDropdown = tradeplayer_dd,
        itemDropdown = tradeitem_ddm,
        itemsDropdown = tradeenchant_ddm,
        delayInput = tradelay_in,
        toggle = tradesend_tgl,
        button = traderefresh_btn
    }
    
    if autoTradeFeature.Init and not autoTradeFeature.__initialized then
        autoTradeFeature:Init(autoTradeFeature, autoTradeFeature.__controls)
        autoTradeFeature.__initialized = true
    end
end

tradesend_tgl  = TradeSec:Toggle({
           Title = "Auto Accept Trade",
           Desc = "Automatically accept trade",
           Default = false,
           Callback = function(Values)
        if Values and autoAcceptTradeFeature and autoAcceptTradeFeature.Start then
            autoAcceptTradeFeature:Start({ 
                ClicksPerSecond = 18,
                EdgePaddingFrac = 0 
            })
        elseif autoAcceptTradeFeature and autoAcceptTradeFeature.Stop then
            autoAcceptTradeFeature:Stop()
        end
    end
})
if autoAcceptTradeFeature then
    autoAcceptTradeFeature.__controls = {
        toggle = tradeacc_tgl
    }
    
    if autoAcceptTradeFeature.Init and not autoAcceptTradeFeature.__initialized then
        autoAcceptTradeFeature:Init(autoAcceptTradeFeature, autoAcceptTradeFeature.__controls)
        autoAcceptTradeFeature.__initialized = true
    end
end
end

--- ==== TAB SHOP === ---
Shop:Section({
    Title = gradient("Shop", Color3.fromHex("#6A11CB"), Color3.fromHex("#2575FC")),
    TextSize = 25 })
Shop:Divider()
local autobuyrodFeature = FeatureManager:Get("AutoBuyRod")
local autobuybaitFeature = FeatureManager:Get("AutoBuyBait")
local weatherFeature = FeatureManager:Get("AutoBuyWeather")
--- ROD
local rodPriceLabel
local selectedRodsSet = {}
local function updateRodPriceLabel()
    local total = Helpers.calculateTotalPrice(selectedRodsSet, Helpers.getRodPrice)
    if shoprod_btn then
        shoprod_btn:SetDesc("Total Price: " .. Helpers.abbreviateNumber(total, 1))
    end
end
local RodShopSec = Shop:Section({
    Title = "Rod",
    Box = false,
    Icon = "store",
    TextTransparency = 0.05,
    TextXAlignment = "Left",
    TextSize = 17,
    Opened = false }) do

shoprod_ddm = RodShopSec:Dropdown({
    Title = "Select Rod",
    Values = listRod,
    Value = {},
    SearchBarEnabled = true,
    Multi = true,
    AllowNone = true,
    Callback = function(Values)
        selectedRodsSet = Helpers.normalizeList(Values or {})
        updateRodPriceLabel()

        if autobuyrodFeature and autobuyrodFeature.SetSelectedRodsByName then
            autobuyrodFeature:SetSelectedRodsByName(selectedRodsSet)
        end
    end
})

shoprod_btn = RodShopSec:Button({
    Title = "Buy Rod",
    Desc = "Total Price: $0",
    Locked = false,
    Callback = function()
        if autobuyrodFeature.SetSelectedRodsByName then autobuyrodFeature:SetSelectedRodsByName(selectedRodsSet) end
        if autobuyrodFeature.Start then autobuyrodFeature:Start({ 
            rodList = selectedRodsSet,
            interDelay = 0.5 
        }) end
    end
})
if autobuyrodFeature then
    autobuyrodFeature.__controls = {
        Dropdown = shoprod_ddm,
        button = shoprod_btn
    }
    
    if autobuyrodFeature.Init and not autobuyrodFeature.__initialized then
        autobuyrodFeature:Init(autobuyrodFeature, autobuyrodFeature.__controls)
        autobuyrodFeature.__initialized = true
    end
end
end

--- BAIT
local baitName = Helpers.getBaitNames()
local baitPriceLabel
local selectedBaitsSet = {}
local function updateBaitPriceLabel()
    local total = Helpers.calculateTotalPrice(selectedBaitsSet, Helpers.getBaitPrice)
    if shopbait_btn then
        shopbait_btn:SetDesc("Total Price: " .. Helpers.abbreviateNumber(total, 1))
    end
end
local BaitShopSec = Shop:Section({
    Title = "Bait",
    Box = false,
    Icon = "store",
    TextTransparency = 0.05,
    TextXAlignment = "Left",
    TextSize = 17,
    Opened = false }) do

        shopbait_ddm = BaitShopSec:Dropdown({
    Title = "Select Bait",
    Values = baitName,
    Value = {},
    SearchBarEnabled = true,
    Multi = true,
    AllowNone = true,
    Callback = function(Values)
         selectedBaitsSet = Helpers.normalizeList(Values or {})
        updateBaitPriceLabel()

        if autobuybaitFeature and autobuybaitFeature.SetSelectedBaitsByName then
            autobuybaitFeature:SetSelectedBaitsByName(selectedBaitsSet)
        end
    end
})

shopbait_btn = BaitShopSec:Button({
    Title = "Buy Bait",
    Desc = "Total Price: $0",
    Locked = false,
    Callback = function()
        if autobuybaitFeature.SetSelectedBaitsByName then autobuybaitFeature:SetSelectedBaitsByName(selectedBaitsSet) end
        if autobuybaitFeature.Start then autobuybaitFeature:Start({ 
            baitList = selectedBaitsSet,
            interDelay = 0.5 
        }) end
    end
})
if autobuybaitFeature then
    autobuybaitFeature.__controls = {
        Dropdown = shopbait_ddm,
        button = shopbait_btn
    }
    
    if autobuybaitFeature.Init and not autobuybaitFeature.__initialized then
        autobuybaitFeature:Init(autobuybaitFeature, autobuybaitFeature.__controls)
        autobuybaitFeature.__initialized = true
    end
end
end

--- WEATHER
local selectedWeatherSet = {} 
local WeatherShopSec = Shop:Section({
    Title = "Weather",
    Box = false,
    Icon = "store",
    TextTransparency = 0.05,
    TextXAlignment = "Left",
    TextSize = 17,
    Opened = false }) do

        shopweather_ddm = WeatherShopSec:Dropdown({
    Title = "Select Weather",
    Values = weatherName,
    Value = {},
    SearchBarEnabled = true,
    Multi = true,
    AllowNone = true,
    Callback = function(Values)
        selectedWeatherSet = Values or {}
        if weatherFeature and weatherFeature.SetWeathers then
           weatherFeature:SetWeathers(selectedWeatherSet)
        end
    end
})

 shopweather_tgl = WeatherShopSec:Toggle({
           Title = "Auto Buy Weather",
           Desc = "Max 3 weather",
           Default = false,
           Callback = function(Value)
            if Value and weatherFeature then
            if weatherFeature.SetWeathers then weatherFeature:SetWeathers(selectedWeatherSet) end
            if weatherFeature.Start then weatherFeature:Start({ 
                weatherList = selectedWeatherSet 
            }) end
        elseif weatherFeature and weatherFeature.Stop then
            weatherFeature:Stop()
        end
    end
})
if weatherFeature then
    weatherFeature.__controls = {
        Dropdown = shopweather_ddm,
        toggle = shopweather_tgl
    }
    
    if weatherFeature.Init and not weatherFeature.__initialized then
        weatherFeature:Init(weatherFeature, weatherFeature.__controls)
        weatherFeature.__initialized = true
    end
end
end

--- === TELEPORT === ---
Teleport:Section({
    Title = gradient("Teleport", Color3.fromHex("#6A11CB"), Color3.fromHex("#2575FC")),
    TextSize = 25 })
Teleport:Divider()
--- ISLAND
local autoTeleIslandFeature = FeatureManager:Get("AutoTeleportIsland")
local currentIsland = "Fisherman Island"
local IslandSec = Teleport:Section({
    Title = "Island",
    Box = false,
    Icon = "map",
    TextTransparency = 0.05,
    TextXAlignment = "Left",
    TextSize = 17,
    Opened = false }) do

         teleisland_dd = IslandSec:Dropdown({
    Title = "Select Island",
    Values = {
        "Fisherman Island",
        "Esoteric Depths",
        "Enchant Altar",
        "Kohana",
        "Kohana Volcano",
        "Tropical Grove",
        "Crater Island",
        "Coral Reefs",
        "Sisyphus Statue",
        "Treasure Room"
    },
    Value = "",
    SearchBarEnabled = true,
    Multi = false,
    AllowNone = true,
    Callback = function(Value)
        currentIsland = Value or {}
        if autoTeleIslandFeature and autoTeleIslandFeature.SetIsland then
           autoTeleIslandFeature:SetIsland(Value)
        end
    end
})

teleisland_btn = IslandSec:Button({
    Title = "Teleport",
    Desc = "",
    Locked = false,
    Callback = function()
        if autoTeleIslandFeature then
            if autoTeleIslandFeature.SetIsland then
                autoTeleIslandFeature:SetIsland(currentIsland)
            end
            if autoTeleIslandFeature.Teleport then
                autoTeleIslandFeature:Teleport(currentIsland)
            end
        end
    end
})
if autoTeleIslandFeature then
    autoTeleIslandFeature.__controls = {
        Dropdown = teleisland_dd,
        button = teleisland_btn
    }
    
    if autoTeleIslandFeature.Init and not autoTeleIslandFeature.__initialized then
        autoTeleIslandFeature:Init(autoTeleIslandFeature, autoTeleIslandFeature.__controls)
        autoTeleIslandFeature.__initialized = true
    end
end
end

--- PLAYER
local teleplayerFeature = FeatureManager:Get("AutoTeleportPlayer")
local currentPlayerName = nil
local TelePlayerSec = Teleport:Section({
    Title = "Player",
    Box = false,
    Icon = "person-standing",
    TextTransparency = 0.05,
    TextXAlignment = "Left",
    TextSize = 17,
    Opened = false }) do

        teleplayer_dd = TelePlayerSec:Dropdown({
    Title = "Select Player",
    Values = Helpers.listPlayers(true),
    Value = "",
    SearchBarEnabled = true,
    Multi = false,
    AllowNone = true,
    Callback = function(Value)
        local name = Helpers.normalizeOption(Value)
        currentPlayerName = name
        if teleplayerFeature and teleplayerFeature.SetTarget then
            teleplayerFeature:SetTarget(name)
        end
        mainLogger:info("[teleplayer] selected:", name)
    end
})

teleplayer_btn = TelePlayerSec:Button({
    Title = "Teleport",
    Desc = "",
    Locked = false,
    Callback = function()
         if teleplayerFeature then
            if teleplayerFeature.SetTarget then
                teleplayerFeature:SetTarget(currentPlayerName)
            end
            if teleplayerFeature.Teleport then
                teleplayerFeature:Teleport(currentPlayerName)
            end
        end
    end
})

teleplayerrefresh_btn = TelePlayerSec:Button({
    Title = "Refresh Player List",
    Desc = "",
    Locked = false,
    Callback = function()
        local names = Helpers.listPlayers(true)
        if teleplayer_dd.Refresh then teleplayer_dd:Refresh(names) end
        Noctis:Notify({ Title = "Players", Content = ("Online: %d"):format(#names), Duration = 2 })
    end
})

if teleplayerFeature then
    teleplayerFeature.__controls = {
        dropdown = teleplayer_dd,
        refreshButton = teleplayerrefresh_btn,
        teleportButton = teleplayer_btn
    }
    
    if teleplayerFeature.Init and not teleplayerFeature.__initialized then
        teleplayerFeature:Init(teleplayerFeature, teleplayerFeature.__controls)
        teleplayerFeature.__initialized = true
    end
end
end

--- TELE POSITION
local positionManagerFeature = FeatureManager:Get("PositionManager")
local TelePosSec = Teleport:Section({
    Title = "Position",
    Box = false,
    Icon = "anchor",
    TextTransparency = 0.05,
    TextXAlignment = "Left",
    TextSize = 17,
    Opened = false }) do

        savepos_in = TelePosSec:Input({
    Title = "Position Name",
    Desc = "Enter name for Position",
    Value = "",
    Type = "Input", -- or "Textarea"
    Placeholder = "e.g Farm",
    Callback = function(Value)
        -- Input akan digunakan saat user klik Add button
    end
})

saveposadd_btn = TelePosSec:Button({
    Title = "Add Position",
    Desc = "",
    Locked = false,
    Callback = function()
        if not positionManagerFeature then return end
        
        local name = savepos_in.Value
        if not name or name == "" or name == "Position Name" then
            Noctis:Notify({
                Title = "Position Teleport",
                Content = "Please enter a valid position name",
                Duration = 3
            })
            return
        end
        
        local success, message = positionManagerFeature:AddPosition(name)
        if success then
            positionManagerFeature:RefreshDropdown()
            Noctis:Notify({
                Title = "Position Teleport",
                Content = "Position '" .. name .. "' added successfully",
                Duration = 2
            })
            savepos_in:Refresh("")
        else
            Noctis:Notify({
                Title = "Position Teleport",
                Content = message or "Failed to add position",
                Duration = 3
            })
        end
    end
})

 savepos_dd = TelePosSec:Dropdown({
    Title = "Select Position",
    Values = {"No Positions"},
    SearchBarEnabled = true,
    Multi = false,
    AllowNone = true,
    Callback = function(Value)
        -- Callback dipanggil saat user pilih posisi dari dropdown
    end
})

savepostele_btn = TelePosSec:Button({
    Title = "Teleport",
    Desc = "",
    Locked = false,
    Callback = function()
        if not positionManagerFeature then return end
        
        local selectedPos = savepos_dd.Value
        if not selectedPos or selectedPos == "No Positions" then
            Noctis:Notify({
                Title = "Position Teleport",
                Description = "Please select a position to teleport",
                Duration = 3
            })
            return
        end
        
        local success, message = positionManagerFeature:TeleportToPosition(selectedPos)
        if success then
            Noctis:Notify({
                Title = "Position Teleport",
                Description = "Teleported to '" .. selectedPos .. "'",
                Duration = 2
            })
        else
            Noctis:Notify({
                Title = "Position Teleport",
                Description = message or "Failed to teleport",
                Duration = 3
            })
        end
    end
})

saveposrefresh_btn = TelePosSec:Button({
    Title = "Refresh Position List",
    Desc = "",
    Locked = false,
    Callback = function()
        if not positionManagerFeature then return end
        
        local list = positionManagerFeature:RefreshDropdown()
        savepos_dd:Refresh(list) 
        local count = #list
        if list[1] == "No Positions" then count = 0 end
        
        Noctis:Notify({
            Title = "Position Teleport",
            Content = count .. " positions found",
            Duration = 2
        })
    end
})

saveposdel_btn = TelePosSec:Button({
    Title = "Delete Selected Position",
    Desc = "",
    Locked = false,
    Callback = function()
        if not positionManagerFeature then return end
        
        local selectedPos = savepos_dd.Value
        if not selectedPos or selectedPos == "No Positions" then
            Noctis:Notify({
                Title = "Position Teleport",
                Content = "Please select a position to delete",
                Duration = 3
            })
            return
        end
        
        local success, message = positionManagerFeature:DeletePosition(selectedPos)
        if success then
            positionManagerFeature:RefreshDropdown()
            Noctis:Notify({
                Title = "Position Teleport",
                Content = "Position '" .. selectedPos .. "' deleted",
                Duration = 2
            })
        else
            Noctis:Notify({
                Title = "Position Teleport",
                Content = message or "Failed to delete position",
                Duration = 3
            })
        end
    end
})

if positionManagerFeature then
    positionManagerFeature.__controls = {
        dropdown = savepos_dd,
        input = savepos_in,
        addButton = saveposadd_btn,
        deleteButton = saveposdel_btn,
        teleportButton = savepostele_btn,
        refreshButton = saveposrefresh_btn
    }
    
    if positionManagerFeature.Init and not positionManagerFeature.__initialized then
        positionManagerFeature:Init(positionManagerFeature, positionManagerFeature.__controls)
        positionManagerFeature.__initialized = true
    end
end
end

--- === MISC === ---
Misc:Section({
    Title = gradient("Misc", Color3.fromHex("#6A11CB"), Color3.fromHex("#2575FC")),
    TextSize = 25 })
Misc:Divider()
--- WEBHOOK
local fishWebhookFeature = FeatureManager:Get("FishWebhook")
local currentWebhookUrl = ""
local selectedWebhookFishTypes = {}
local WebhookSec = Misc:Section({
    Title = "Webhook",
    Box = false,
    Icon = "bell-ring",
    TextTransparency = 0.05,
    TextXAlignment = "Left",
    TextSize = 17,
    Opened = false }) do

        webhookfish_in = WebhookSec:Input({
    Title = "Webhook URL",
    Desc = "Enter Webhook URL",
    Value = "",
    Type = "Input", -- or "Textarea"
    Placeholder = "https://discord.com/...",
    Callback = function(Value)
        currentWebhookUrl = Value
        if fishWebhookFeature and fishWebhookFeature.SetWebhookUrl then
            fishWebhookFeature:SetWebhookUrl(Value)
        end
    end
})

webhookfish_ddm = WebhookSec:Dropdown({
    Title = "Select Rarity",
    Values = rarityName,
    Value = {},
    SearchBarEnabled = true,
    Multi = true,
    AllowNone = true,
    Callback = function(Values)
        selectedWebhookFishTypes = Helpers.normalizeList(Values or {})
        
        if fishWebhookFeature and fishWebhookFeature.SetSelectedFishTypes then
            fishWebhookFeature:SetSelectedFishTypes(selectedWebhookFishTypes)
        end
        
        if fishWebhookFeature and fishWebhookFeature.SetSelectedTiers then
            fishWebhookFeature:SetSelectedTiers(selectedWebhookFishTypes)
        end
    end
})

WebhookSec:Paragraph({
    Title = gradient("IMPORTANT", Color3.fromHex("#6A11CB"), Color3.fromHex("#2575FC")),
    Desc = "Some fish have different Rarity, example if you caught Secret but Webhook says Mythic, isnt bug but thats Game issue"
})

webhookfish_tgl = WebhookSec:Toggle({
           Title = "Enable Webhook",
           Desc = "",
           Default = false,
           Callback = function(Value)
        if Value and fishWebhookFeature then
            if fishWebhookFeature.SetWebhookUrl then 
                fishWebhookFeature:SetWebhookUrl(currentWebhookUrl) 
            end
            
            if fishWebhookFeature.SetSelectedFishTypes then 
                fishWebhookFeature:SetSelectedFishTypes(selectedWebhookFishTypes) 
            end
            if fishWebhookFeature.SetSelectedTiers then 
                fishWebhookFeature:SetSelectedTiers(selectedWebhookFishTypes) 
            end
            
            if fishWebhookFeature.Start then 
                fishWebhookFeature:Start({ 
                    webhookUrl = currentWebhookUrl,
                    selectedTiers = selectedWebhookFishTypes,
                    selectedFishTypes = selectedWebhookFishTypes
                }) 
            end
        elseif fishWebhookFeature and fishWebhookFeature.Stop then
            fishWebhookFeature:Stop()
        end
    end
})
if fishWebhookFeature then
    fishWebhookFeature.__controls = {
        urlInput = webhookfish_in,
        fishTypesDropdown = webhookfish_ddm,
        toggle = webhookfish_tgl
    }

    if fishWebhookFeature.Init and not fishWebhookFeature.__initialized then
        fishWebhookFeature:Init(fishWebhookFeature, fishWebhookFeature.__controls)
        fishWebhookFeature.__initialized = true
    end
end
end
--- SERVER
local copyJoinServerFeature = FeatureManager:Get("CopyJoinServer")
local autoReconnectFeature = FeatureManager:Get("AutoReconnect")
local autoReexec = FeatureManager:Get("AutoReexec")
if autoReexec and autoReexec.Init and not autoReexec.__initialized then
    autoReexec:Init({
        mode = "url",
        url  = "https://raw.githubusercontent.com/c3iv3r/a/refs/heads/main/dev/fishdev.lua",
        rearmEveryS = 260,
        addBootGuard = true,
    })
    autoReexec.__initialized = true
end
local ServerSec = Misc:Section({
    Title = "Server",
    Box = false,
    Icon = "server",
    TextTransparency = 0.05,
    TextXAlignment = "Left",
    TextSize = 17,
    Opened = false }) do

         server_in = ServerSec:Input({
    Title = "JobId",
    Desc = "Enter JobId",
    Value = "",
    Type = "Input", -- or "Textarea"
    Placeholder = "e.g XXX-XXX-XX",
    Callback = function(Value)
        if copyJoinServerFeature then copyJoinServerFeature:SetTargetJobId(Value) end
    end
})

serverjoin_btn = ServerSec:Button({
    Title = "Join Server",
    Desc = "",
    Locked = false,
    Callback = function()
        if copyJoinServerFeature then
            local jobId = server_in.Value
            copyJoinServerFeature:JoinServer(jobId)
        end
    end
})

servercopy_btn = ServerSec:Button({
    Title = "Copy JobId",
    Desc = "",
    Locked = false,
    Callback = function()
        if copyJoinServerFeature then copyJoinServerFeature:CopyCurrentJobId() end
    end
})

if copyJoinServerFeature then
    copyJoinServerFeature.__controls = {
        input = server_in,
        joinButton = serverjoin_btn,
        copyButton = servercopy_btn
    }
    
    if copyJoinServerFeature.Init and not copyJoinServerFeature.__initialized then
        copyJoinServerFeature:Init(copyJoinServerFeature, copyJoinServerFeature.__controls)
        copyJoinServerFeature.__initialized = true
    end
end

reconnect_tgl = ServerSec:Toggle({
           Title = "Auto Reconnect",
           Desc = "",
           Default = false,
            Callback = function(Value)
        if Value then
            autoReconnectFeature:Start()
        else
            autoReconnectFeature:Stop()
        end
    end
})

if autoReconnectFeature then
    autoReconnectFeature.__controls = {
        toggle = reconnect_tgl
    }
    
    if autoReconnectFeature.Init and not autoReconnectFeature.__initialized then
        autoReconnectFeature:Init()
        autoReconnectFeature.__initialized = true
    end
end

reexec_tgl = ServerSec:Toggle({
           Title = "Re-Execute on Reconnect",
           Desc = "",
           Default = false,
           Callback = function(state)
        if not autoReexec then return end
        if state then
            local ok, err = pcall(function() autoReexec:Start() end)
            if not ok then warn("[AutoReexec] Start failed:", err) end
        else
            local ok, err = pcall(function() autoReexec:Stop() end)
            if not ok then warn("[AutoReexec] Stop failed:", err) end
        end
    end
})
end

--- PERFORMANCE
local boostFPSFeature = FeatureManager:Get("BoostFPS")
local blackScreenGui = nil
local function EnableBlackScreen()
    if blackScreenGui then return end
    
    RunService:Set3dRenderingEnabled(false)
    
    blackScreenGui = Instance.new("ScreenGui")
    blackScreenGui.ResetOnSpawn = false
    blackScreenGui.IgnoreGuiInset = true
    blackScreenGui.DisplayOrder = -999999
    blackScreenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
    blackScreenGui.Parent = LocalPlayer:WaitForChild("PlayerGui")
    
    local frame = Instance.new("Frame")
    frame.BackgroundColor3 = Color3.new(0, 0, 0)
    frame.BorderSizePixel = 0
    frame.Size = UDim2.new(1, 0, 1, 36)
    frame.Position = UDim2.new(0, 0, 0, -36)
    frame.ZIndex = -999999
    frame.Parent = blackScreenGui
end

local function DisableBlackScreen()
    if blackScreenGui then
        blackScreenGui:Destroy()
        blackScreenGui = nil
    end
    RunService:Set3dRenderingEnabled(true)
end
local PerformanceSec = Misc:Section({
    Title = "Performance",
    Box = false,
    Icon = "chevrons-up",
    TextTransparency = 0.05,
    TextXAlignment = "Left",
    TextSize = 17,
    Opened = false }) do

        gpusaver_tgl = PerformanceSec:Toggle({
           Title = "Save GPU",
           Desc = "Some executor may not support, it will forceclose if not support",
           Default = false,
           Callback = function(Value)
        if Value then
            EnableBlackScreen()
        else
            DisableBlackScreen()
        end
    end
})

        boostfps_btn = PerformanceSec:Button({
    Title = "Boost FPS",
    Desc = "",
    Locked = false,
    Callback = function()
        if boostFPSFeature and boostFPSFeature.Start then
            boostFPSFeature:Start()
            
            Noctis:Notify({
                Title = title,
                Description = "FPS Boost has been activated!",
                Duration = 3
            })
        end
    end
})

if boostFPSFeature then
    boostFPSFeature.__controls = {
        button = boostfps_btn
    }
    
    if boostFPSFeature.Init and not boostFPSFeature.__initialized then
        boostFPSFeature:Init(boostFPSFeature.__controls)
        boostFPSFeature.__initialized = true
    end
end
end

--- OTHERS
local playerespFeature = FeatureManager:Get("PlayerEsp")
local autoGearFeature = FeatureManager:Get("AutoGearOxyRadar")
local OtherSec = Misc:Section({
    Title = "Others",
    Box = false,
    Icon = "blend",
    TextTransparency = 0.05,
    TextXAlignment = "Left",
    TextSize = 17,
    Opened = false }) do

        playeresp_tgl = OtherSec:Toggle({
           Title = "Player ESP",
           Desc = "",
           Default = false,
           Callback = function(Value)
     if Value then playerespFeature:Start() else playerespFeature:Stop() 
       end
end
})
if playerespFeature then
    playerespFeature.__controls = {
        Toggle = playeresp_tgl
    }

    if playerespFeature.Init and not playerespFeature.__initialized then
        playerespFeature:Init(playerespFeature, playerespFeature.__controls)
        playerespFeature.__initialized = true
    end
end

eqoxygentank_tgl = OtherSec:Toggle({
           Title = "Enable Diving Gear",
           Desc = "",
           Default = false,
           Callback = function(Value)
        oxygenOn = Value
        if Value then
            if autoGearFeature and autoGearFeature.Start then
                autoGearFeature:Start()
            end
            if autoGearFeature and autoGearFeature.EnableOxygen then
                autoGearFeature:EnableOxygen(true)
            end
        else
            if autoGearFeature and autoGearFeature.EnableOxygen then
                autoGearFeature:EnableOxygen(false)
            end
        end
        if autoGearFeature and (not oxygenOn) and (not radarOn) and autoGearFeature.Stop then
            autoGearFeature:Stop()
        end
    end
})

eqfishradar_tgl = OtherSec:Toggle({
           Title = "Enable Fish Radar",
           Desc = "",
           Default = false,
           Callback = function(Value)
        radarOn = Value
        if Value then
            if autoGearFeature and autoGearFeature.Start then
                autoGearFeature:Start()
            end
            if autoGearFeature and autoGearFeature.EnableRadar then
                autoGearFeature:EnableRadar(true)
            end
        else
            if autoGearFeature and autoGearFeature.EnableRadar then
                autoGearFeature:EnableRadar(false)
            end
        end
        if autoGearFeature and (not oxygenOn) and (not radarOn) and autoGearFeature.Stop then
            autoGearFeature:Stop()
        end
    end
})
if autoGearFeature then
    autoGearFeature.__controls = {
        oxygenToggle = eqoxygentank_tgl,
        radarToggle = eqfishradar_tgl
    }
    
    if autoGearFeature.Init and not autoGearFeature.__initialized then
        autoGearFeature:Init(autoGearFeature, autoGearFeature.__controls)
        autoGearFeature.__initialized = true
    end
end
end

Window:SelectTab(1)

task.defer(function()
    task.wait(0.1)
    Noctis:Notify({
        Title = title,
        Content = "Enjoy! Join Our Discord!",
        Duration = 3
    })
end)