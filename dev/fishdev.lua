local Logger       = loadstring(game:HttpGet("https://raw.githubusercontent.com/c3iv3r/a/refs/heads/main/utils/logger.lua"))()

-- FOR PRODUCTION: Uncomment this line to disable all logging
--Logger.disableAll()

-- FOR DEVELOPMENT: Enable all logging
Logger.enableAll()

local mainLogger = Logger.new("Main")
local featureLogger = Logger.new("FeatureManager")

local Noctis       = loadstring(game:HttpGet("https://raw.githubusercontent.com/hailazra/Obsidian/refs/heads/main/Library.lua"))()
local ThemeManager = loadstring(game:HttpGet("https://raw.githubusercontent.com/hailazra/Obsidian/refs/heads/main/addons/ThemeManager.lua"))()
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

--- === WINDOW === ---
local Window = Noctis:CreateWindow({
    Title         = "<b>Noctis</b>",
    Footer        = "Fish It | v1.4.9",
    Icon          = "rbxassetid://123156553209294",
    NotifySide    = "Right",
    IconSize      = UDim2.fromOffset(30, 30),
    Resizable     = true,
    Center        = true,
    AutoShow      = true,
    DisableSearch = true,
    ShowCustomCursor = false
})

--- === OPEN BUTTON === ---
Window:EditOpenButton({
    Image = "rbxassetid://123156553209294",
    Size = Vector2.new(100, 100),
    StartPos = UDim2.new(0.5, 8, 0, 0),
})

--- === TABS === ---
local TabHome            = Window:AddTab("Home", "house")
local TabMain            = Window:AddTab("Main", "gamepad")
local TabBackpack        = Window:AddTab("Backpack", "backpack")
local TabAutomation      = Window:AddTab("Automation", "workflow")
local TabShop            = Window:AddTab("Shop", "shopping-bag")
local TabTeleport        = Window:AddTab("Teleport","map")
local TabMisc            = Window:AddTab("Misc", "cog")
local TabSetting         = Window:AddTab("Setting", "settings")

--- === CHANGELOG & DISCORD LINK === ---
local CHANGELOG = table.concat({
    "[+] Added Save GPU"
}, "\n")
local DISCORD = table.concat({
    "https://discord.gg/3AzvRJFT3M",
}, "\n")

--- === HOME === ---
--- INFO 
local InformationBox = TabHome:AddLeftGroupbox("<b>Information</b>", "info")
local changelogtitle = InformationBox:AddLabel("<b>Changelog</b>")
local changelog      = InformationBox:AddLabel({
    Text     = CHANGELOG,
    DoesWrap = true 
})
local sugestbugs     = InformationBox:AddLabel("Report bugs to our<br/>Discord Server")
InformationBox:AddDivider()
local joindc         = InformationBox:AddLabel("<b>Join our Discord</b>")
local discordbtn     = InformationBox:AddButton({
    Text = "Discord",
    Func = function()
        if typeof(setclipboard) == "function" then
            setclipboard(DISCORD)
            Noctis:Notify({ Title = title, Description = "Discord link copied!", Duration = 2 })
        else
            Noctis:Notify({ Title = title, Description = "Clipboard not available", Duration = 3 })
        end
    end
})

--- PLAYER STATS
local PlayerStatBox = TabHome:AddRightGroupbox("<b>Player Stats</b>", "circle-user-round")
local CaughtLabel = PlayerStatBox:AddLabel("Caught:")
local RarestLabel = PlayerStatBox:AddLabel("Rarest Fish:")
local playerinvent = PlayerStatBox:AddLabel("<b>Inventory</b>")
local FishesLabel= PlayerStatBox:AddLabel("Fishes:")
local ItemsLabel = PlayerStatBox:AddLabel("Items:")

local inventoryWatcher = _G.InventoryWatcher and _G.InventoryWatcher.new()

if inventoryWatcher then
    inventoryWatcher:onReady(function()
        local function updateLabels()
            local counts = inventoryWatcher:getCountsByType()
            FishesLabel:SetText("Fishes: " .. (counts["Fishes"] or 0))
            ItemsLabel:SetText("Items: " .. (counts["Items"] or 0))
        end
        updateLabels()
        inventoryWatcher:onChanged(updateLabels)
    end)
end

-- Function untuk update label otomatis
local function updateCaughtLabel()
    local currentValue = Helpers.getCaughtValue()
    CaughtLabel:SetText("Caught: " .. currentValue)
end

-- Connect ke perubahan Value di Caught IntValue
local function connectToValueChanges()
    local leaderstats = LocalPlayer:FindFirstChild("leaderstats")
    if leaderstats then
        local caught = leaderstats:FindFirstChild("Caught")
        if caught and caught:IsA("IntValue") then
            caught:GetPropertyChangedSignal("Value"):Connect(updateCaughtLabel)
        end
    end
end

local function updateRarestLabel()
    local currentValue = Helpers.getRarestValue()
    RarestLabel:SetText("Rarest Fish: " .. currentValue)
end

local function connectToRarestChanges()
    local leaderstats = LocalPlayer:FindFirstChild("leaderstats")
    if leaderstats then
        local rarest = leaderstats:FindFirstChild("Rarest Fish")
        if rarest and rarest:IsA("StringValue") then
            rarest:GetPropertyChangedSignal("Value"):Connect(updateRarestLabel)
        end
    end
end

-- Wait for leaderstats to load dan connect
LocalPlayer:WaitForChild("leaderstats")
connectToValueChanges()
connectToRarestChanges()
updateCaughtLabel()
updateRarestLabel()

--- === MAIN === ---
--- FISHING
local FishingBox = TabMain:AddLeftGroupbox("<b>Fishing</b>", "fish")
local autoFishFeature = FeatureManager:Get("AutoFish")
local currentFishingMode = "Fast"
local autofishmode_dd = FishingBox:AddDropdown("Fishingdd", {
    Text = "Fishing Mode",
    Values = {"Fast", "Slow"},
    Default = 1,
    Callback = function(Value)
        currentFishingMode = Value
        if autoFishFeature and autoFishFeature.SetMode then
            autoFishFeature:SetMode(Value)
        end
    end
})

local autofish_tgl = FishingBox:AddToggle("Fishingtgl", {
    Text = "Auto Fishing",
    Default = false,
    Callback = function(state)
        if state and autoFishFeature then
            if autoFishFeature.SetMode then autoFishFeature:SetMode(currentFishingMode) end
            if autoFishFeature.Start then autoFishFeature:Start({ mode = currentFishingMode }) end
        elseif autoFishFeature and autoFishFeature.Stop then
            autoFishFeature:Stop()
        end
    end
})

if autoFishFeature then
    autoFishFeature.__controls = {
        modeDropdown = autofishmode_dd,
        toggle = autofish_tgl
    }
    
    if autoFishFeature.Init and not autoFishFeature.__initialized then
        autoFishFeature:Init(autoFishFeature, autoFishFeature.__controls)
        autoFishFeature.__initialized = true
    end
end

--- AUTO FIX FISHING
local autoFixFishFeature = FeatureManager:Get("AutoFixFishing")
local autofixfish_tgl = FishingBox:AddToggle("fixfishtgl", {
    Text = "Auto Fix Fishing",
    Default = false,
    Callback = function(Value)
        if Value then
            autoFixFishFeature:Start()
        else
            autoFixFishFeature:Stop()
        end
    end
})

-- TYPO: autoFishFixFeature vs autoFixFishFeature
if autoFixFishFeature then  -- Ganti dari autoFishFixFeature
    autoFixFishFeature.__controls = {  -- Ganti dari autoFishFixFeature
        toggle = autofixfish_tgl
    }
    if autoFixFishFeature.Init and not autoFixFishFeature.__initialized then
        autoFixFishFeature:Init(autoFixFishFeature.__controls)  -- Hapus parameter pertama
        autoFixFishFeature.__initialized = true
    end
end

FishingBox:AddDivider()
cancellabel = FishingBox:AddLabel("Use this if fishing stuck")
local cancelautofish_btn = FishingBox:AddButton({
    Text = "Cancel Fishing",
    Func = function()
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

--- SAVE POS
local SavePosBox = TabMain:AddRightGroupbox("<b>Position</b>", "anchor")
local savePositionFeature = FeatureManager:Get("SavePosition")
local saveposlabel = SavePosBox:AddLabel("Use this with Autoload<br/>Config for AFK")
SavePosBox:AddDivider()
local savepos_tgl = SavePosBox:AddToggle("savepostgl",{
    Text = "Save Position",
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

--- EVENT
local EventBox = TabMain:AddLeftGroupbox("<b>Event</b>", "calendar-plus-2")
local eventteleFeature = FeatureManager:Get("AutoTeleportEvent")
local selectedEventsArray = {}
local eventtele_ddm = EventBox:AddDropdown("eventddm", {
    Text                     = "Select Event",
    Tooltip                  = "",
    Values                   = eventNames,
    Searchable               = true,
    MaxVisibileDropdownItems = 6,
    Multi                    = true,
    Callback = function(Values)
        selectedEventsArray = Helpers.normalizeList(Values or {})   
        if eventteleFeature and eventteleFeature.SetSelectedEvents then
            eventteleFeature:SetSelectedEvents(selectedEventsArray)
        end
    end
})
local eventtele_tgl = EventBox:AddToggle("eventtgl",{
    Text = "Auto Teleport",
    Tooltip = "",
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
eventlabel = EventBox:AddLabel("Prioritize selected event")

--- === BACKPACK === ---
--- FAVFISH
local FavoriteBox = TabBackpack:AddLeftGroupbox("<b>Favorite Fish</b>", "star")
local autoFavFishFeature =  FeatureManager:Get("AutoFavoriteFish")
local selectedTiers = {}
local favfish_ddm = FavoriteBox:AddDropdown("favfishddm", {
    Text                     = "Select Fish Rarity",
    Tooltip                  = "",
    Values                   = rarityName,  
    Searchable               = true,
    MaxVisibileDropdownItems = 6, 
    Multi                    = true,
    Callback = function(Values)
        selectedTiers = Values or {}
        if autoFavFishFeature and autoFavFishFeature.SetDesiredTiersByNames then
           autoFavFishFeature:SetDesiredTiersByNames(selectedTiers)
        end
    end
})
local favfish_tgl = FavoriteBox:AddToggle("favfishtgl", {
    Text = "Favorite by Rarity",
    Tooltip = "",
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

FavoriteBox:AddDivider()

local autoFavFishV2Feature = FeatureManager:Get("AutoFavoriteFishV2")
local selectedFishNames = {}

local favfishv2_ddm = FavoriteBox:AddDropdown("favfishv2ddm", {
    Text                     = "Select Fish Names",
    Tooltip                  = "Select fish names to auto favorite",
    Values                   = Helpers.getFishNamesForTrade(),
    Searchable               = true,
    MaxVisibileDropdownItems = 6, 
    Multi                    = true,
    Callback = function(Values)
        selectedFishNames = Values or {}
        if autoFavFishV2Feature and autoFavFishV2Feature.SetSelectedFishNames then
           autoFavFishV2Feature:SetSelectedFishNames(selectedFishNames)
        end
    end
})

local favfishv2_tgl = FavoriteBox:AddToggle("favfishv2tgl", {
    Text = "Favorite by Names",
    Tooltip = "Auto favorite fish by selected names",
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

--- SELL FISH
local SellBox = TabBackpack:AddRightGroupbox("<b>Sell Fish</b>", "badge-dollar-sign")
local sellfishFeature        = FeatureManager:Get("AutoSellFish")
local currentSellThreshold   = "Legendary"
local currentSellLimit       = 0
local sellfish_dd = SellBox:AddDropdown("sellfishdd", {
    Text = "Select Rarity",
    Tooltip = "",
    Values = {"Secret", "Mythic", "Legendary"},
    Multi = false,
    Callback = function(Value)
        currentSellThreshold = Value or {}
        if sellfishFeature and sellfishFeature.SetMode then
           sellfishFeature:SetMode(Value)
        end
    end
})
local sellfish_in = SellBox:AddInput("sellfishin", {
    Text = "Input Delay",
    Default = "60",
    Numeric = true,
    Finished = true,
    Callback = function(Value)
        local n = tonumber(Value) or 0
        currentSellLimit = n
        if sellfishFeature and sellfishFeature.SetLimit then
            sellfishFeature:SetLimit(n)
        end
    end
})
local sellfish_tgl = SellBox:AddToggle("sellfishtgl",{
    Text = "Auto Sell",
    Tooltip = "",
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

--- === AUTOMATION === ---
--- ENCHANT
local EnchantBox = TabAutomation:AddLeftGroupbox("<b>Enchant Rod</b>", "circle-fading-arrow-up")
local autoEnchantFeature = FeatureManager:Get("AutoEnchantRod")
local selectedEnchants   = {}

local enchant_ddm = EnchantBox:AddDropdown("enchantddm", {
    Text                     = "Select Enchant",
    Values                   = enchantName,
    Searchable               = true,
    MaxVisibileDropdownItems = 6,
    Multi                    = true,
    Callback = function(Values)
        selectedEnchants = Helpers.normalizeList(Values or {})
        if autoEnchantFeature and autoEnchantFeature.SetDesiredByNames then
            autoEnchantFeature:SetDesiredByNames(selectedEnchants)
        end
    end
})

local enchant_tgl = EnchantBox:AddToggle("enchanttgl",{
    Text = "Auto Enchant",
    Default = false,
    Callback = function(Value)
        if Value and autoEnchantFeature then
            if #selectedEnchants == 0 then
                Noctis:Notify({ Title="Info", Description="Select at least 1 enchant", Duration=3 })
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

enchantlabel = EnchantBox:AddLabel("Equip Enchant Stone at<br/>3rd slots")

--- TRADE
local TradeBox = TabAutomation:AddRightGroupbox("<b>Trade</b>", "gift")
local autoTradeFeature       = FeatureManager:Get("AutoSendTrade")
local autoAcceptTradeFeature = FeatureManager:Get("AutoAcceptTrade")
local selectedTradeItems    = {}
local selectedTradeEnchants = {}
local selectedTargetPlayers = {}

local tradeplayer_dd = TradeBox:AddDropdown("tradeplayerdd", {
    Text                     = "Select Player",
    SpecialType = "Player",
    ExcludeLocalPlayer = true,
    Searchable               = true,
    MaxVisibileDropdownItems = 6,
    Multi                    = true,
    Callback = function(Value)
        selectedTargetPlayers = Helpers.normalizeList(Value or {})
        if autoTradeFeature and autoTradeFeature.SetTargetPlayers then
            autoTradeFeature:SetTargetPlayers(selectedTargetPlayers)
        end
    end
})

local tradeitem_ddm = TradeBox:AddDropdown("tradeitemddm", {
    Text                     = "Select Fish",
    Values                   = Helpers.getFishNamesForTrade(),
    Searchable               = true,
    MaxVisibileDropdownItems = 6,
    Multi = true,
    Callback = function(Values)
        selectedTradeItems = Helpers.normalizeList(Values or {})
        if autoTradeFeature and autoTradeFeature.SetSelectedFish then
            autoTradeFeature:SetSelectedFish(selectedTradeItems)
        end
    end
})

local tradeenchant_ddm = TradeBox:AddDropdown("tradeenchantddm", {
    Text                     = "Select Enchant Stones",
    Values                   = Helpers.getEnchantStonesForTrade(),
    Searchable               = true,
    MaxVisibileDropdownItems = 6,
    Multi = true,
    Callback = function(Values)
        selectedTradeEnchants = Helpers.normalizeList(Values or {})
        if autoTradeFeature and autoTradeFeature.SetSelectedItems then
            autoTradeFeature:SetSelectedItems(selectedTradeEnchants)
        end
    end
})

local tradelay_in = TradeBox:AddInput("tradedelayin", {
    Text = "Input Delay",
    Default = "15",
    Numeric = true,
    Finished = true,
    Callback = function(Value)
        local delay = math.max(1, tonumber(Value) or 5)
        if autoTradeFeature and autoTradeFeature.SetTradeDelay then
            autoTradeFeature:SetTradeDelay(delay)
        end
    end
})

local traderefresh_btn = TradeBox:AddButton({
    Text = "Refresh Player List",
    Func = function()
        local names = Helpers.listPlayers(true)
        if tradeplayer_dd.Refresh then tradeplayer_dd:SetValue(names) end
        Noctis:Notify({ Title = "Players", Description = ("Online: %d"):format(#names), Duration = 2 })
    end
})

local tradesend_tgl = TradeBox:AddToggle("tradetgl", {
    Text = "Auto Send Trade",
    Default = false,
    Callback = function(Value)
        if Value and autoTradeFeature then
            if #selectedTradeItems == 0 and #selectedTradeEnchants == 0 then
                Noctis:Notify({ Title="Info", Description="Select at least 1 fish or enchant stone first", Duration=3 })
                return
            end
            if #selectedTargetPlayers == 0 then
                Noctis:Notify({ Title="Info", Description="Select at least 1 target player", Duration=3 })
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

TradeBox:AddDivider()
local tradeacc_tgl = TradeBox:AddToggle("tradeacctgl",{
    Text = "Auto Accept Trade",
    Tooltip = "",
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

--- ==== TAB SHOP === ---
--- ROD
local RodShopBox = TabShop:AddLeftGroupbox("<b>Rod</b>", "store")
local autobuyrodFeature = FeatureManager:Get("AutoBuyRod")
local rodPriceLabel
local selectedRodsSet = {}
local function updateRodPriceLabel()
    local total = Helpers.calculateTotalPrice(selectedRodsSet, Helpers.getRodPrice)
    if rodPriceLabel then
        rodPriceLabel:SetText("Total Price: " .. Helpers.abbreviateNumber(total, 1))
    end
end

local shoprod_ddm = RodShopBox:AddDropdown("rodshopddm", {
    Text = "Select Rod",
    Values = listRod,
    Searchable = true,
    MaxVisibileDropdownItems = 6,
    Multi = true,
    Callback = function(Values)
        selectedRodsSet = Helpers.normalizeList(Values or {})
        updateRodPriceLabel()

        if autobuyrodFeature and autobuyrodFeature.SetSelectedRodsByName then
            autobuyrodFeature:SetSelectedRodsByName(selectedRodsSet)
        end
    end
})

rodPriceLabel = RodShopBox:AddLabel("Total Price: $0")

local shoprod_btn = RodShopBox:AddButton({
    Text = "Buy Rod",
    Func = function()
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

--- BAIT
local BaitShopBox = TabShop:AddLeftGroupbox("<b>Bait</b>", "store")
local autobuybaitFeature = FeatureManager:Get("AutoBuyBait")
local baitName = Helpers.getBaitNames()
local baitPriceLabel
local selectedBaitsSet = {}
local function updateBaitPriceLabel()
    local total = Helpers.calculateTotalPrice(selectedBaitsSet, Helpers.getBaitPrice)
    if baitPriceLabel then
        baitPriceLabel:SetText("Total Price: " .. Helpers.abbreviateNumber(total, 1))
    end
end

local shopbait_ddm = BaitShopBox:AddDropdown("baitshop", {
    Text = "Select Bait",
    Values = baitName,
    Searchable = true,
    MaxVisibileDropdownItems = 6,
    Multi = true,
    Callback = function(Values)
        selectedBaitsSet = Helpers.normalizeList(Values or {})
        updateBaitPriceLabel()

        if autobuybaitFeature and autobuybaitFeature.SetSelectedBaitsByName then
            autobuybaitFeature:SetSelectedBaitsByName(selectedBaitsSet)
        end
    end
})

baitPriceLabel = BaitShopBox:AddLabel("Total Price: $0")

local shopbait_btn = BaitShopBox:AddButton({
    Text = "Buy Bait",
    Func = function()
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

--- WEATHER
local WeatherShopBox = TabShop:AddRightGroupbox("<b>Weather</b>", "store")
local weatherFeature = FeatureManager:Get("AutoBuyWeather")
local selectedWeatherSet = {} 
local shopweather_ddm = WeatherShopBox:AddDropdown("weathershopddm", {
    Text = "Select Weather",
    Tooltip = "",
    Values = weatherName,
    Searchable = true,
    MaxVisibileDropdownItems = 6,
    Multi = true,
    Callback = function(Values)
        selectedWeatherSet = Values or {}
        if weatherFeature and weatherFeature.SetWeathers then
           weatherFeature:SetWeathers(selectedWeatherSet)
        end
    end
})
maxbuyweather = WeatherShopBox:AddLabel("Max 3")
local shopweather_tgl = WeatherShopBox:AddToggle("weathershoptgl",{
    Text = "Auto Buy Weather",
    Tooltip = "",
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

--- MERCHANT
local MerchantShopBox = TabShop:AddRightGroupbox("<b>Merchant</b>", "store")
local autobuymerchantFeature = FeatureManager:Get("AutoBuyMerchant")
local selectedMerchantItems = {}

local shopmerchant_ddm = MerchantShopBox:AddDropdown("merchantshopddm", {
    Text = "Select Items",
    Tooltip = "Minimum 1 item required",
    Values = Helpers.getMerchantItemNames(),
    Searchable = true,
    MaxVisibileDropdownItems = 6,
    Multi = true,
    Callback = function(Values)
        selectedMerchantItems = Values or {}
        if autobuymerchantFeature and autobuymerchantFeature.SetTargetItems then
            autobuymerchantFeature:SetTargetItems(selectedMerchantItems)
        end
    end
})

local shopmerchant_tgl = MerchantShopBox:AddToggle("merchantshoptgl", {
    Text = "Auto Buy Merchant",
    Tooltip = "",
    Default = false,
    Callback = function(Value)
        if Value then
            if autobuymerchantFeature then
                if autobuymerchantFeature.SetTargetItems then
                    autobuymerchantFeature:SetTargetItems(selectedMerchantItems)
                end
                if autobuymerchantFeature.Start then
                    autobuymerchantFeature:Start({ targetItems = selectedMerchantItems })
                end
            end
        else
            if autobuymerchantFeature and autobuymerchantFeature.Stop then
                autobuymerchantFeature:Stop()
            end
        end
    end
})

if autobuymerchantFeature then
    autobuymerchantFeature.__controls = {
        Dropdown = shopmerchant_ddm,
        Toggle = shopmerchant_tgl
    }
    
    if autobuymerchantFeature.Init and not autobuymerchantFeature.__initialized then
        autobuymerchantFeature:Init(autobuymerchantFeature.__controls)
        autobuymerchantFeature.__initialized = true
    end
end

--- === TAB TELEPORT === ---
--- ISLAND
local IslandBox = TabTeleport:AddLeftGroupbox("<b>Island</b>", "map")
local autoTeleIslandFeature = FeatureManager:Get("AutoTeleportIsland")
local currentIsland = "Fisherman Island"
local teleisland_dd = IslandBox:AddDropdown("teleislanddd", {
    Text = "Select Island",
    Tooltip = "",
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
    Searchable = true,
    MaxVisibileDropdownItems = 6,
    Multi = false,
    Callback = function(Value)
        currentIsland = Value or {}
        if autoTeleIslandFeature and autoTeleIslandFeature.SetIsland then
           autoTeleIslandFeature:SetIsland(Value)
        end
    end
})
local teleisland_btn = IslandBox:AddButton({
    Text = "Teleport",
    Func = function()
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

--- PLAYER
local PlayerTeleBox = TabTeleport:AddRightGroupbox("<b>Player</b>", "person-standing")
local teleplayerFeature = FeatureManager:Get("AutoTeleportPlayer")
local currentPlayerName = nil
local teleplayer_dd = PlayerTeleBox:AddDropdown("teleplayerdd", {
    Text = "Select Player",
    Tooltip = "",
    Values = Helpers.listPlayers(true),
    Searchable = true,
    MaxVisibileDropdownItems = 6,
    Multi = false,
    Callback = function(Value)
        local name = Helpers.normalizeOption(Value)
        currentPlayerName = name
        if teleplayerFeature and teleplayerFeature.SetTarget then
            teleplayerFeature:SetTarget(name)
        end
        mainLogger:info("[teleplayer] selected:", name)
    end
})
local teleplayer_btn = PlayerTeleBox:AddButton({
    Text = "Teleport",
    Func = function()
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
local teleplayerrefresh_btn = teleplayer_btn:AddButton({
    Text = "Refresh",
    Func = function()
        local names = Helpers.listPlayers(true)
        if teleplayer_dd.Refresh then teleplayer_dd:SetValue(names) end
        Noctis:Notify({ Title = "Players", Description = ("Online: %d"):format(#names), Duration = 2 })
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

--- POSITION TELE
local SavePosTeleBox = TabTeleport:AddLeftGroupbox("<b>Position Teleport</b>", "anchor")
local positionManagerFeature = FeatureManager:Get("PositionManager")
local savepos_in = SavePosTeleBox:AddInput("saveposin", {
    Text = "Position Name",
    Default = "",
    Numeric = false,
    Finished = true,
    Callback = function(Value)
        -- Input akan digunakan saat user klik Add button
    end
})
local saveposadd_btn = SavePosTeleBox:AddButton({
    Text = "Add Position",
    Func = function()
        if not positionManagerFeature then return end
        
        local name = savepos_in.Value
        if not name or name == "" or name == "Position Name" then
            Noctis:Notify({
                Title = "Position Teleport",
                Description = "Please enter a valid position name",
                Duration = 3
            })
            return
        end
        
        local success, message = positionManagerFeature:AddPosition(name)
        if success then
            Noctis:Notify({
                Title = "Position Teleport",
                Description = "Position '" .. name .. "' added successfully",
                Duration = 2
            })
            savepos_in:SetValue("")
        else
            Noctis:Notify({
                Title = "Position Teleport",
                Description = message or "Failed to add position",
                Duration = 3
            })
        end
    end
})
local savepos_dd = SavePosTeleBox:AddDropdown("savedposdd", {
    Text = "Select Position",
    Tooltip = "Choose a saved position to teleport",
    Values = {"No Positions"},
    Searchable = true,
    MaxVisibileDropdownItems = 6,
    Multi = false,
    Callback = function(Value)
        -- Callback dipanggil saat user pilih posisi dari dropdown
    end
})
local saveposdel_btn = SavePosTeleBox:AddButton({
    Text = "Delete Pos",
    Func = function()
        if not positionManagerFeature then return end
        
        local selectedPos = savepos_dd.Value
        if not selectedPos or selectedPos == "No Positions" then
            Noctis:Notify({
                Title = "Position Teleport",
                Description = "Please select a position to delete",
                Duration = 3
            })
            return
        end
        
        local success, message = positionManagerFeature:DeletePosition(selectedPos)
        if success then
            Noctis:Notify({
                Title = "Position Teleport",
                Description = "Position '" .. selectedPos .. "' deleted",
                Duration = 2
            })
        else
            Noctis:Notify({
                Title = "Position Teleport",
                Description = message or "Failed to delete position",
                Duration = 3
            })
        end
    end
})
local saveposrefresh_btn = saveposdel_btn:AddButton({
    Text = "Refresh Pos",
    Func = function()
        if not positionManagerFeature then return end
        
        local list = positionManagerFeature:RefreshDropdown()
        local count = #list
        if list[1] == "No Positions" then count = 0 end
        
        Noctis:Notify({
            Title = "Position Teleport",
            Description = count .. " positions found",
            Duration = 2
        })
    end
})
local savepostele_btn = SavePosTeleBox:AddButton({
    Text = "Teleport",
    Func = function()
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

--- === TAB MISC === ---
--- Webhook
local WebhookBox = TabMisc:AddLeftGroupbox("<b>Webhook</b>", "bell-ring")
local fishWebhookFeature = FeatureManager:Get("FishWebhook")
local currentWebhookUrl = ""
local selectedWebhookFishTypes = {}

local webhookfish_in = WebhookBox:AddInput("webhookin", {
    Text = "Webhook URL",
    Default = "",
    Numeric = false,
    Finished = true,
    Callback = function(Value)
        currentWebhookUrl = Value
        if fishWebhookFeature and fishWebhookFeature.SetWebhookUrl then
            fishWebhookFeature:SetWebhookUrl(Value)
        end
    end
})

local webhookfish_ddm = WebhookBox:AddDropdown("webhookddm", {
    Text = "Select Rarity",
    Tooltip = "",
    Values = rarityName,
    Searchable = true,
    MaxVisibileDropdownItems = 6,
    Multi = true,
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

local webhookfish_tgl = WebhookBox:AddToggle("webhooktgl",{
    Text = "Enable Webhook",
    Tooltip = "",
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

--- SERVER
local ServerBox = TabMisc:AddRightGroupbox("<b>Server</b>", "server")
local copyJoinServerFeature = FeatureManager:Get("CopyJoinServer")
local server_in = ServerBox:AddInput("serverin", {
    Text = "Input JobId",
    Default = "",
    Numeric = false,
    Finished = true,
    Callback = function(Value)
        if copyJoinServerFeature then copyJoinServerFeature:SetTargetJobId(Value) end
    end
})
local serverjoin_btn = ServerBox:AddButton({
    Text = "Join JobId",
    Func = function()
        if copyJoinServerFeature then
            local jobId = server_in.Value
            copyJoinServerFeature:JoinServer(jobId)
        end
    end
})
local servercopy_btn = serverjoin_btn:AddButton({
    Text = "Copy JobId",
    Func = function()
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
ServerBox:AddDivider()

--- AUTO RECONNECT
local autoReconnectFeature = FeatureManager:Get("AutoReconnect")
local reconnect_tgl = ServerBox:AddToggle("reconnecttgl", {
    Text = "Auto Reconnect",
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

--- AUTO REEXECUTE
local autoReexec = FeatureManager:Get("AutoReexec")
if autoReexec and autoReexec.Init and not autoReexec.__initialized then
    autoReexec:Init({
        mode = "url",
        url  = "https://raw.githubusercontent.com/c3iv3r/a/refs/heads/main/dev/fishdev.lua",
        rearmEveryS = 20,
        addBootGuard = true,
    })
    autoReexec.__initialized = true
end
local reexec_tgl = ServerBox:AddToggle("autoreexectgl", {
    Text = "Re-Execute on Reconnect",
    Tooltip = "",
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

--- OTHERS
local OtherBox = TabMisc:AddLeftGroupbox("<b>Other</b>", "blend")
local autoGearFeature = FeatureManager:Get("AutoGearOxyRadar")
local antiafkFeature = FeatureManager:Get("AntiAfk")
local boostFPSFeature = FeatureManager:Get("BoostFPS")
local oxygenOn = false
local radarOn  = false
local eqoxygentank_tgl = OtherBox:AddToggle("eqoxygentanktgl",{
    Text = "Equip Diving Gear",
    Tooltip = "",
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
local eqfishradar_tgl = OtherBox:AddToggle("eqfishradartgl",{
    Text = "Enable Fish Radar",
    Tooltip = "",
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
local antiafk_tgl = OtherBox:AddToggle("antiafk", {
    Text = "Anti Afk",
    Tooltip = "",
    Default = false,
    Callback = function(Value)
        if Value then
            if antiafkFeature and antiafkFeature.Start then
                antiafkFeature:Start()
            end
        else
            if antiafkFeature and antiafkFeature.Stop then 
                antiafkFeature:Stop()
            end
        end
    end
})
if antiafkFeature then
    antiafkFeature.__controls = {
        Toggle = antiafk_tgl
    }
    
    if antiafkFeature.Init and not antiafkFeature.__initialized then
        antiafkFeature:Init(antiafkFeature, antiafkFeature.__controls)
        antiafkFeature.__initialized = true
    end
end

--- PLAYER ESP
local playerespFeature = FeatureManager:Get("PlayerEsp")
local playeresp_tgl = OtherBox:AddToggle("playeresptgl",{
    Text = "Player ESP",
    Tooltip = "",
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

--- GPU SAVER
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

local gpusaver_tgl = OtherBox:AddToggle("gpusavertgl", {
    Text = "Save GPU",
    Tooltip = "",
    Default = false,
    Callback = function(Value)
        if Value then
            EnableBlackScreen()
        else
            DisableBlackScreen()
        end
    end
})

OtherBox:AddDivider()
--- BOOST FPS
local boostfps_btn = OtherBox:AddButton({
    Text = "Boost FPS",
    Func = function()
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

--- === TAB SETTINGS === ---
ThemeManager:SetLibrary(Noctis)
SaveManager:SetLibrary(Noctis)

SaveManager:IgnoreThemeSettings()
SaveManager:SetIgnoreIndexes({ "MenuKeybind" })

ThemeManager:SetFolder("NoctisTheme")
SaveManager:SetFolder("Noctis/FishIt")

SaveManager:BuildConfigSection(TabSetting)
ThemeManager:ApplyToTab(TabSetting)

SaveManager:LoadAutoloadConfig()

task.defer(function()
    task.wait(0.1)
    Noctis:Notify({
        Title = title,
        Description = "Enjoy! Join Our Discord!",
        Duration = 3
    })
end)