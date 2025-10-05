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
Main:Section({
    Title = "Main",
    TextSize = 25 })
Main:Divider()
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
    Title = "Backpack",
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

favfishv2_ddm = FavFishSec:Dropdown({
    Title = "Select Fish",
    Values = rarityName,
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
    Callback = function(Values)
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
    Title = "Automation",
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
    Title = "Shop",
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