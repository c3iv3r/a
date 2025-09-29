local Logger = loadstring(game:HttpGet("https://raw.githubusercontent.com/c3iv3r/a/refs/heads/main/utils/logger.lua"))()
Logger.enableAll()

-- OPTIMIZE: Consolidate loggers into table
local Loggers = {
    main = Logger.new("Main"),
    feature = Logger.new("FeatureManager")
}

-- OPTIMIZE: Load libraries into table
local Libraries = {
    Noctis = loadstring(game:HttpGet("https://raw.githubusercontent.com/hailazra/Obsidian/refs/heads/main/Library.lua"))(),
    ThemeManager = loadstring(game:HttpGet("https://raw.githubusercontent.com/hailazra/Obsidian/refs/heads/main/addons/ThemeManager.lua"))(),
    SaveManager = loadstring(game:HttpGet("https://raw.githubusercontent.com/hailazra/Obsidian/refs/heads/main/addons/SaveManager.lua"))()
}

-- OPTIMIZE: Consolidate services into single table
local Services = {
    Players = game:GetService("Players"),
    ReplicatedStorage = game:GetService("ReplicatedStorage"),
    RunService = game:GetService("RunService"),
    HttpService = game:GetService("HttpService")
}
Services.LocalPlayer = Services.Players.LocalPlayer

-- OPTIMIZE: Consolidate modules into single table
local GameModules = {
    Enchants = Services.ReplicatedStorage.Enchants,
    Baits = Services.ReplicatedStorage.Baits,
    Items = Services.ReplicatedStorage.Items,
    Events = Services.ReplicatedStorage.Events,
    Boats = Services.ReplicatedStorage.Boats,
    Tiers = Services.ReplicatedStorage.Tiers
}

-- OPTIMIZE: String constants table
local STRINGS = {
    TITLE = '<font color="#7D55FF">NOCTIS</font>',
    VERSION = "Fish It | v1.2.5",
    DISCORD = "https://discord.gg/3AzvRJFT3M",
    CHANGELOG = "[+] Added Auto Mythic",
    
    -- UI Text constants
    AUTO_FISHING = "Auto Fishing",
    SELECT_PLAYER = "Select Player",
    SELECT_ISLAND = "Select Island",
    SELECT_EVENT = "Select Event",
    SELECT_RARITY = "Select Rarity",
    AUTO_TELEPORT = "Auto Teleport",
    TOTAL_PRICE = "Total Price: $0",
    WEBHOOK_URL = "Webhook URL",
    FISHING_MODE = "Fishing Mode",
    CANCEL_FISHING = "Cancel Fishing",
    SAVE_POSITION = "Save Position",
    AUTO_FAVORITE = "Auto Favorite",
    AUTO_SELL = "Auto Sell",
    AUTO_ENCHANT = "Auto Enchant",
    AUTO_TRADE = "Auto Send Trade",
    AUTO_ACCEPT_TRADE = "Auto Accept Trade",
    BUY_ROD = "Buy Rod",
    BUY_BAIT = "Buy Bait",
    AUTO_BUY_WEATHER = "Auto Buy Weather",
    TELEPORT = "Teleport",
    ENABLE_WEBHOOK = "Enable Webhook",
    AUTO_RECONNECT = "Auto Reconnect",
    ANTI_AFK = "Anti Afk",
    BOOST_FPS = "Boost FPS"
}

-- OPTIMIZE: Consolidate helper functions
local Helpers = {}

function Helpers.getEnchantNames()
    local names = {}
    for _, ms in ipairs(GameModules.Enchants:GetChildren()) do
        if ms:IsA("ModuleScript") then
            local ok, mod = pcall(require, ms)
            if ok and type(mod) == "table" and mod.Data then
                local name = tostring(mod.Data.Name or ms.Name)
                if mod.Data.Id and name then table.insert(names, name) end
            end
        end
    end
    table.sort(names)
    return names
end

function Helpers.getBaitNames()
    local names = {}
    for _, item in pairs(GameModules.Baits:GetChildren()) do
        if item:IsA("ModuleScript") then
            local ok, mod = pcall(require, item)
            if ok and mod and mod.Data and mod.Data.Type == "Baits" and mod.Price then
                table.insert(names, item.Name)
            end
        end
    end
    return names
end

function Helpers.getFishingRodNames()
    local names = {}
    for _, item in pairs(GameModules.Items:GetChildren()) do
        if item:IsA("ModuleScript") then
            local ok, mod = pcall(require, item)
            if ok and mod and mod.Data and mod.Data.Type == "Fishing Rods" and mod.Price and mod.Data.Name then
                table.insert(names, mod.Data.Name)
            end
        end
    end
    table.sort(names)
    return names
end

function Helpers.getWeatherNames()
    local names = {}
    for _, weather in pairs(GameModules.Events:GetChildren()) do
        if weather:IsA("ModuleScript") then
            local ok, mod = pcall(require, weather)
            if ok and mod and mod.WeatherMachine == true and mod.WeatherMachinePrice then
                table.insert(names, weather.Name)
            end
        end
    end
    table.sort(names)
    return names
end

function Helpers.getEventNames()
    local names = {}
    for _, event in pairs(GameModules.Events:GetChildren()) do
        if event:IsA("ModuleScript") then
            local ok, mod = pcall(require, event)
            if ok and mod and mod.Coordinates and mod.Name then
                table.insert(names, mod.Name)
            end
        end
    end
    table.sort(names)
    return names
end

function Helpers.getTierNames()
    local names = {}
    local ok, tiersData = pcall(require, GameModules.Tiers)
    if ok and tiersData then
        for _, tierInfo in pairs(tiersData) do
            if tierInfo.Name then table.insert(names, tierInfo.Name) end
        end
    end
    return names
end

function Helpers.getFishNames()
    local names = {}
    for _, item in pairs(GameModules.Items:GetChildren()) do
        if item:IsA("ModuleScript") then
            local ok, mod = pcall(require, item)
            if ok and mod and mod.Data and mod.Data.Type == "Fishes" and mod.Data.Name then
                table.insert(names, mod.Data.Name)
            end
        end
    end
    table.sort(names)
    return names
end

function Helpers.getFishNamesForTrade()
    local names = {}
    for _, item in pairs(GameModules.Items:GetChildren()) do
        if item:IsA("ModuleScript") then
            local ok, mod = pcall(require, item)
            if ok and mod and mod.Data and mod.Data.Type == "Fishes" and mod.Data.Name then
                table.insert(names, mod.Data.Name)
            end
        end
    end
    table.sort(names)
    return names
end

function Helpers.getEnchantStonesForTrade()
    local names = {}
    for _, item in pairs(GameModules.Items:GetChildren()) do
        if item:IsA("ModuleScript") then
            local ok, mod = pcall(require, item)
            if ok and mod and mod.Data and mod.Data.Type == "EnchantStones" and mod.Data.Name then
                table.insert(names, mod.Data.Name)
            end
        end
    end
    table.sort(names)
    return names
end

function Helpers.listPlayers(excludeSelf)
    local me = Services.LocalPlayer and Services.LocalPlayer.Name
    local players = {}
    for _, p in ipairs(Services.Players:GetPlayers()) do
        if not excludeSelf or (me and p.Name ~= me) then
            table.insert(players, p.Name)
        end
    end
    table.sort(players, function(a, b) return a:lower() < b:lower() end)
    return players
end

function Helpers.normalizeOption(opt)
    if type(opt) == "string" then return opt end
    if type(opt) == "table" then
        return opt.Value or opt.value or opt[1] or opt.Selected or opt.selection
    end
    return nil
end

function Helpers.normalizeList(opts)
    local out = {}
    if type(opts) == "string" or type(opts) == "number" then
        table.insert(out, tostring(opts))
    elseif type(opts) == "table" then
        if #opts > 0 then
            for _, v in ipairs(opts) do
                if type(v) == "table" then
                    local val = v.Value or v.value or v.Name or v.name or v[1] or v.Selected or v.selection
                    if val then table.insert(out, tostring(val)) end
                else
                    table.insert(out, tostring(v))
                end
            end
        else
            for k, v in pairs(opts) do
                if type(k) ~= "number" and v then
                    table.insert(out, tostring(k))
                else
                    if type(v) == "table" then
                        local val = v.Value or v.value or v.Name or v.name or v[1] or v.Selected or v.selection
                        if val then table.insert(out, tostring(val)) end
                    else
                        table.insert(out, tostring(v))
                    end
                end
            end
        end
    end
    return out
end

function Helpers.getRodPrice(rodName)
    for _, item in pairs(GameModules.Items:GetChildren()) do
        if item:IsA("ModuleScript") then
            local ok, mod = pcall(require, item)
            if ok and mod and mod.Data and mod.Data.Type == "Fishing Rods" and mod.Data.Name == rodName then
                return mod.Price or 0
            end
        end
    end
    return 0
end

function Helpers.getBaitPrice(baitName)
    for _, item in pairs(GameModules.Baits:GetChildren()) do
        if item:IsA("ModuleScript") and item.Name == baitName then
            local ok, mod = pcall(require, item)
            if ok and mod and mod.Data and mod.Data.Type == "Baits" then
                return mod.Price or 0
            end
        end
    end
    return 0
end

function Helpers.calculateTotalPrice(selectedItems, priceFunction)
    local total = 0
    for _, itemName in ipairs(selectedItems) do
        total = total + priceFunction(itemName)
    end
    return total
end

function Helpers.abbreviateNumber(n, maxDecimals)
    if not n then return "0" end
    maxDecimals = (maxDecimals == nil) and 1 or math.max(0, math.min(2, maxDecimals))
    local neg = n < 0
    n = math.abs(n)

    local units = {{1e12, "T"}, {1e9, "B"}, {1e6, "M"}, {1e3, "K"}}

    for _, u in ipairs(units) do
        local div, suf = u[1], u[2]
        if n >= div then
            local v = n / div
            local fmt = "%." .. tostring(maxDecimals) .. "f"
            local s = string.format(fmt, v):gsub("%.0+$", ""):gsub("%.(%d-)0+$", ".%1")
            return (neg and "-" or "") .. s .. suf
        end
    end

    local s = string.format("%." .. tostring(maxDecimals) .. "f", n):gsub("%.0+$", ""):gsub("%.(%d-)0+$", ".%1")
    return (neg and "-" or "") .. s
end

function Helpers.getCaughtValue()
    local leaderstats = Services.LocalPlayer:FindFirstChild("leaderstats")
    if leaderstats then
        local caught = leaderstats:FindFirstChild("Caught")
        if caught and caught:IsA("IntValue") then
            return caught.Value
        end
    end
    return 0
end

function Helpers.getRarestValue()
    local leaderstats = Services.LocalPlayer:FindFirstChild("leaderstats")
    if leaderstats then
        local rarest = leaderstats:FindFirstChild("Rarest Fish")
        if rarest and rarest:IsA("StringValue") then
            return rarest.Value
        end
    end
    return "None"
end

-- OPTIMIZE: Consolidate game data
local GameData = {
    enchantNames = Helpers.getEnchantNames(),
    baitNames = Helpers.getBaitNames(),
    rodNames = Helpers.getFishingRodNames(),
    weatherNames = Helpers.getWeatherNames(),
    eventNames = Helpers.getEventNames(),
    tierNames = Helpers.getTierNames(),
    fishNames = Helpers.getFishNames()
}

-- Set globals
_G.GameServices = Services
_G.NetPath = nil
pcall(function()
    _G.NetPath = Services.ReplicatedStorage:WaitForChild("Packages"):WaitForChild("_Index"):WaitForChild("sleitnick_net@0.2.0"):WaitForChild("net")
end)

_G.InventoryWatcher = nil
pcall(function()
    _G.InventoryWatcher = loadstring(game:HttpGet("https://raw.githubusercontent.com/c3iv3r/a/refs/heads/main/utils/fishit/inventdetect.lua"))()
end)

-- FeatureManager (keep sync loading as requested)
local FeatureManager = {}
FeatureManager.LoadedFeatures = {}
FeatureManager.TotalFeatures = 0
FeatureManager.LoadedCount = 0
FeatureManager.IsReady = false

local FEATURE_URLS = {
    AutoFish = "https://raw.githubusercontent.com/c3iv3r/a/refs/heads/main/module/f/autofish.lua",
    AutoSellFish = "https://raw.githubusercontent.com/c3iv3r/a/refs/heads/main/module/f/autosellfish.lua",
    AutoTeleportIsland = "https://raw.githubusercontent.com/c3iv3r/a/refs/heads/main/module/f/autoteleportisland.lua",
    FishWebhook = "https://raw.githubusercontent.com/c3iv3r/a/refs/heads/main/module/f/fishwebhook.lua",
    AutoBuyWeather = "https://raw.githubusercontent.com/c3iv3r/a/refs/heads/main/module/f/autobuyweather.lua",
    AutoBuyBait = "https://raw.githubusercontent.com/c3iv3r/a/refs/heads/main/module/f/autobuybait.lua",
    AutoBuyRod = "https://raw.githubusercontent.com/c3iv3r/a/refs/heads/main/module/f/autobuyrod.lua",
    AutoTeleportEvent = "https://raw.githubusercontent.com/c3iv3r/a/refs/heads/main/module/f/autoteleportevent.lua",
    AutoGearOxyRadar = "https://raw.githubusercontent.com/c3iv3r/a/refs/heads/main/module/f/autogearoxyradar.lua",
    AntiAfk = "https://raw.githubusercontent.com/c3iv3r/a/refs/heads/main/module/f/antiafk.lua",
    AutoEnchantRod = "https://raw.githubusercontent.com/c3iv3r/a/refs/heads/main/module/f/autoenchantrod.lua",
    AutoFavoriteFish = "https://raw.githubusercontent.com/c3iv3r/a/refs/heads/main/module/f/autofavoritefish.lua",
    AutoFavoriteFishV2 = "https://raw.githubusercontent.com/c3iv3r/a/refs/heads/main/module/f/autofavoritefishv2.lua",
    AutoTeleportPlayer = "https://raw.githubusercontent.com/c3iv3r/a/refs/heads/main/module/f/autoteleportplayer.lua",
    BoostFPS = "https://raw.githubusercontent.com/c3iv3r/a/refs/heads/main/module/f/boostfps.lua",
    AutoSendTrade = "https://raw.githubusercontent.com/c3iv3r/a/refs/heads/main/module/f/autosendtrade.lua",
    AutoAcceptTrade = "https://raw.githubusercontent.com/c3iv3r/a/refs/heads/main/module/f/autoaccepttrade.lua",
    SavePosition = "https://raw.githubusercontent.com/c3iv3r/a/refs/heads/main/module/f/saveposition.lua",
    PositionManager = "https://raw.githubusercontent.com/c3iv3r/a/refs/heads/main/module/f/positionmanager.lua",
    CopyJoinServer = "https://raw.githubusercontent.com/c3iv3r/a/refs/heads/main/module/f/copyjoinserver.lua",
    AutoReconnect = "https://raw.githubusercontent.com/c3iv3r/a/refs/heads/main/module/f/autoreconnect.lua",
    AutoReexec = "https://raw.githubusercontent.com/c3iv3r/a/refs/heads/main/module/f/autoreexec.lua",
    InfEnchant = "https://raw.githubusercontent.com/c3iv3r/a/refs/heads/main/module/f/infenchant.lua",
    AutoMythic = "https://raw.githubusercontent.com/c3iv3r/a/refs/heads/main/module/f/automythic.lua"
}

function FeatureManager:LoadSingleFeature(featureName, url)
    local success, result = pcall(function()
        local code = game:HttpGet(url)
        if not code or code == "" then error("Empty response") end
        local module = loadstring(code)()
        if type(module) ~= "table" then error("Module not table") end
        return module
    end)
    
    if success and result then
        result.__featureName = featureName
        result.__initialized = false
        self.LoadedFeatures[featureName] = result
        self.LoadedCount = self.LoadedCount + 1
        Loggers.feature:info(string.format("✓ %s loaded (%d/%d)", featureName, self.LoadedCount, self.TotalFeatures))
        return true
    else
        Loggers.feature:warn(string.format("✗ Failed to load %s: %s", featureName, result or "Unknown error"))
        return false
    end
end

function FeatureManager:InitializeAllFeatures()
    Loggers.feature:info("Starting synchronous feature loading...")
    
    if Libraries.Noctis then
        Libraries.Noctis:Notify({ Title = STRINGS.TITLE, Description = "Loading script...", Duration = 5 })
    end
    
    self.TotalFeatures = 0
    for _ in pairs(FEATURE_URLS) do self.TotalFeatures = self.TotalFeatures + 1 end
    
    local loadOrder = {
        "AntiAfk", "SavePosition", "PositionManager", "AutoReexec", "BoostFPS", "AutoFish", "AutoSellFish", 
        "AutoTeleportIsland", "AutoTeleportPlayer", "AutoTeleportEvent", "AutoEnchantRod", "AutoFavoriteFish", 
        "AutoFavoriteFishV2", "AutoSendTrade", "AutoAcceptTrade", "FishWebhook", "AutoBuyWeather", 
        "AutoBuyBait", "AutoBuyRod", "AutoGearOxyRadar", "CopyJoinServer", "AutoReconnect", "InfEnchant", "AutoMythic"
    }
    
    local successCount = 0
    for _, featureName in ipairs(loadOrder) do
        local url = FEATURE_URLS[featureName]
        if url and self:LoadSingleFeature(featureName, url) then
            successCount = successCount + 1
        end
        wait(0.02)
    end
    
    self.IsReady = true
    Loggers.feature:info(string.format("Loading completed: %d/%d features ready", successCount, self.TotalFeatures))
    
    if Libraries.Noctis then
        Libraries.Noctis:Notify({
            Title = "Features Ready",
            Description = string.format("%d/%d features loaded", successCount, self.TotalFeatures),
            Duration = 3
        })
    end
    
    return successCount, self.TotalFeatures
end

function FeatureManager:Get(featureName)
    return self.LoadedFeatures[featureName]
end

-- Initialize features
FeatureManager:InitializeAllFeatures()

-- OPTIMIZE: Consolidate all UI elements into single table
local UI = {
    Window = nil,
    Tabs = {},
    Controls = {},
    Features = {},
    State = {},
    Boxes = {}
}

-- Create Window
UI.Window = Libraries.Noctis:CreateWindow({
    Title = "<b>Noctis</b>",
    Footer = STRINGS.VERSION,
    Icon = "rbxassetid://123156553209294",
    NotifySide = "Right",
    IconSize = UDim2.fromOffset(30, 30),
    Resizable = true,
    Center = true,
    AutoShow = true,
    DisableSearch = true,
    ShowCustomCursor = false
})

UI.Window:EditOpenButton({
    Image = "rbxassetid://123156553209294",
    Size = Vector2.new(100, 100),
    StartPos = UDim2.new(0.5, 8, 0, 0),
})

-- Create Tabs
UI.Tabs.Home = UI.Window:AddTab("Home", "house")
UI.Tabs.Main = UI.Window:AddTab("Main", "gamepad")
UI.Tabs.Backpack = UI.Window:AddTab("Backpack", "backpack")
UI.Tabs.Automation = UI.Window:AddTab("Automation", "workflow")
UI.Tabs.Shop = UI.Window:AddTab("Shop", "shopping-bag")
UI.Tabs.Teleport = UI.Window:AddTab("Teleport","map")
UI.Tabs.Misc = UI.Window:AddTab("Misc", "cog")
UI.Tabs.Setting = UI.Window:AddTab("Setting", "settings")

-- OPTIMIZE: Create UI sections with consolidated approach
local function createHomeSection()
    UI.Boxes.Information = UI.Tabs.Home:AddLeftGroupbox("<b>Information</b>", "info")
    UI.Boxes.Information:AddLabel("<b>Changelog</b>")
    UI.Boxes.Information:AddLabel({ Text = STRINGS.CHANGELOG, DoesWrap = true })
    UI.Boxes.Information:AddLabel("Report bugs to our<br/>Discord Server")
    UI.Boxes.Information:AddDivider()
    UI.Boxes.Information:AddLabel("<b>Join our Discord</b>")
    UI.Controls.discordButton = UI.Boxes.Information:AddButton({
        Text = "Discord",
        Func = function()
            if typeof(setclipboard) == "function" then
                setclipboard(STRINGS.DISCORD)
                Libraries.Noctis:Notify({ Title = STRINGS.TITLE, Description = "Discord link copied!", Duration = 2 })
            else
                Libraries.Noctis:Notify({ Title = STRINGS.TITLE, Description = "Clipboard not available", Duration = 3 })
            end
        end
    })
    
    UI.Boxes.PlayerStats = UI.Tabs.Home:AddRightGroupbox("<b>Player Stats</b>", "circle-user-round")
    UI.Controls.caughtLabel = UI.Boxes.PlayerStats:AddLabel("Caught:")
    UI.Controls.rarestLabel = UI.Boxes.PlayerStats:AddLabel("Rarest Fish:")
    UI.Boxes.PlayerStats:AddLabel("<b>Inventory</b>")
    UI.Controls.fishesLabel = UI.Boxes.PlayerStats:AddLabel("Fishes:")
    UI.Controls.itemsLabel = UI.Boxes.PlayerStats:AddLabel("Items:")
end

local function createMainSection()
    -- Fishing Section
    UI.Boxes.Fishing = UI.Tabs.Main:AddLeftGroupbox("<b>Fishing</b>", "fish")
    UI.Features.autoFish = FeatureManager:Get("AutoFish")
    UI.State.currentFishingMode = "Fast"
    
    UI.Controls.fishingModeDropdown = UI.Boxes.Fishing:AddDropdown("fishingMode", {
        Text = STRINGS.FISHING_MODE,
        Values = {"Fast", "Slow"},
        Default = 1,
        Callback = function(Value)
            UI.State.currentFishingMode = Value
            if UI.Features.autoFish and UI.Features.autoFish.SetMode then
                UI.Features.autoFish:SetMode(Value)
            end
        end
    })
    
    UI.Controls.autoFishToggle = UI.Boxes.Fishing:AddToggle("autoFish", {
        Text = STRINGS.AUTO_FISHING,
        Default = false,
        Callback = function(state)
            if state and UI.Features.autoFish then
                if UI.Features.autoFish.SetMode then UI.Features.autoFish:SetMode(UI.State.currentFishingMode) end
                if UI.Features.autoFish.Start then UI.Features.autoFish:Start({ mode = UI.State.currentFishingMode }) end
            elseif UI.Features.autoFish and UI.Features.autoFish.Stop then
                UI.Features.autoFish:Stop()
            end
        end
    })
    
    if UI.Features.autoFish then
        UI.Features.autoFish.__controls = {
            modeDropdown = UI.Controls.fishingModeDropdown,
            toggle = UI.Controls.autoFishToggle
        }
        if UI.Features.autoFish.Init and not UI.Features.autoFish.__initialized then
            UI.Features.autoFish:Init(UI.Features.autoFish, UI.Features.autoFish.__controls)
            UI.Features.autoFish.__initialized = true
        end
    end
    
    UI.Boxes.Fishing:AddDivider()
    UI.Boxes.Fishing:AddLabel("Use this if fishing stuck")
    UI.Controls.cancelFishingButton = UI.Boxes.Fishing:AddButton({
        Text = STRINGS.CANCEL_FISHING,
        Func = function()
            local cancelEvent = _G.NetPath and _G.NetPath:FindFirstChild("RF/CancelFishingInputs")
            if cancelEvent and cancelEvent.InvokeServer then
                local success, result = pcall(function()
                    return cancelEvent:InvokeServer()
                end)
                if success then
                    Loggers.main:info("[CancelFishingInputs] Fixed", result)
                else
                    Loggers.main:warn("[CancelFishingInputs] Error", result)
                end
            end
        end
    })
    
    -- Position Section
    UI.Boxes.Position = UI.Tabs.Main:AddRightGroupbox("<b>Position</b>", "anchor")
    UI.Features.savePosition = FeatureManager:Get("SavePosition")
    UI.Boxes.Position:AddLabel("Use this with Autoload<br/>Config for AFK")
    UI.Boxes.Position:AddDivider()
    UI.Controls.savePositionToggle = UI.Boxes.Position:AddToggle("savePosition", {
        Text = STRINGS.SAVE_POSITION,
        Default = false,
        Callback = function(Value)
            if Value then 
                UI.Features.savePosition:Start() 
            else 
                UI.Features.savePosition:Stop()
            end
        end
    })
    
    if UI.Features.savePosition then
        UI.Features.savePosition.__controls = { toggle = UI.Controls.savePositionToggle }
        if UI.Features.savePosition.Init and not UI.Features.savePosition.__initialized then
            UI.Features.savePosition:Init(UI.Features.savePosition, UI.Features.savePosition.__controls)
            UI.Features.savePosition.__initialized = true
        end
    end
    
    -- Event Section
    UI.Boxes.Event = UI.Tabs.Main:AddLeftGroupbox("<b>Event</b>", "calendar-plus-2")
    UI.Features.eventTeleport = FeatureManager:Get("AutoTeleportEvent")
    UI.State.selectedEventsArray = {}
    
    UI.Controls.eventDropdown = UI.Boxes.Event:AddDropdown("eventDropdown", {
        Text = STRINGS.SELECT_EVENT,
        Values = GameData.eventNames,
        Searchable = true,
        MaxVisibileDropdownItems = 6,
        Multi = true,
        Callback = function(Values)
            UI.State.selectedEventsArray = Helpers.normalizeList(Values or {})   
            if UI.Features.eventTeleport and UI.Features.eventTeleport.SetSelectedEvents then
                UI.Features.eventTeleport:SetSelectedEvents(UI.State.selectedEventsArray)
            end
        end
    })
    
    UI.Controls.eventTeleportToggle = UI.Boxes.Event:AddToggle("eventTeleport", {
        Text = STRINGS.AUTO_TELEPORT,
        Default = false,
        Callback = function(Value)
            if Value and UI.Features.eventTeleport then
                local arr = Helpers.normalizeList(UI.State.selectedEventsArray or {})
                if UI.Features.eventTeleport.SetSelectedEvents then UI.Features.eventTeleport:SetSelectedEvents(arr) end
                if UI.Features.eventTeleport.Start then
                    UI.Features.eventTeleport:Start({ selectedEvents = arr, hoverHeight = 12 })
                end
            elseif UI.Features.eventTeleport and UI.Features.eventTeleport.Stop then
                UI.Features.eventTeleport:Stop()
            end
        end
    })
    
    if UI.Features.eventTeleport then
        UI.Features.eventTeleport.__controls = {
            Dropdown = UI.Controls.eventDropdown,
            toggle = UI.Controls.eventTeleportToggle
        }
        if UI.Features.eventTeleport.Init and not UI.Features.eventTeleport.__initialized then
            UI.Features.eventTeleport:Init(UI.Features.eventTeleport, UI.Features.eventTeleport.__controls)
            UI.Features.eventTeleport.__initialized = true
        end
    end
    UI.Boxes.Event:AddLabel("Prioritize selected event")
    
    -- Vuln Section
    UI.Boxes.Vuln = UI.Tabs.Main:AddRightGroupbox("<b>Vuln</b>", "infinite")
    UI.Features.infEnchant = FeatureManager:Get("InfEnchant")
    
    UI.Controls.infEnchantToggle = UI.Boxes.Vuln:AddToggle("infEnchant", {
        Text = "Auto Inf Enchant",
        Tooltip = "Farm enchant stones (cancel Uncommon/Rare)",
        Default = false,
        Callback = function(Value)
            if UI.Features.infEnchant then
                if Value then
                    UI.Features.infEnchant:Start()
                else
                    UI.Features.infEnchant:Stop()
                end
            end
        end
    })
    
    if UI.Features.infEnchant then
        UI.Features.infEnchant.__controls = { toggle = UI.Controls.infEnchantToggle }
        if UI.Features.infEnchant.Init and not UI.Features.infEnchant.__initialized then
            UI.Features.infEnchant:Init()
            UI.Features.infEnchant.__initialized = true
        end
    end
    
    UI.Features.autoMythic = FeatureManager:Get("AutoMythic")
    UI.Controls.autoMythicToggle = UI.Boxes.Vuln:AddToggle("autoMythic", {
        Text = "Auto Mythic",
        Tooltip = "Cancel Fishing until Mythic",
        Default = false,
        Callback = function(Value)
            if UI.Features.autoMythic then
                if Value then
                    UI.Features.autoMythic:Start()
                else
                    UI.Features.autoMythic:Stop()
                end
            end
        end
    })
    
    if UI.Features.autoMythic then
        UI.Features.autoMythic.__controls = { toggle = UI.Controls.autoMythicToggle }
        if UI.Features.autoMythic.Init and not UI.Features.autoMythic.__initialized then
            UI.Features.autoMythic:Init()
            UI.Features.autoMythic.__initialized = true
        end
    end
end

local function createBackpackSection()
    -- Favorite Fish Section
    UI.Boxes.FavoriteFish = UI.Tabs.Backpack:AddLeftGroupbox("<b>Favorite Fish</b>", "star")
    UI.Features.autoFavFish = FeatureManager:Get("AutoFavoriteFish")
    UI.State.selectedTiers = {}
    
    UI.Controls.favFishDropdown = UI.Boxes.FavoriteFish:AddDropdown("favFishRarity", {
        Text = "Favorite by Rarity",
        Values = GameData.tierNames,  
        Searchable = true,
        MaxVisibileDropdownItems = 6, 
        Multi = true,
        Callback = function(Values)
            UI.State.selectedTiers = Values or {}
            if UI.Features.autoFavFish and UI.Features.autoFavFish.SetDesiredTiersByNames then
               UI.Features.autoFavFish:SetDesiredTiersByNames(UI.State.selectedTiers)
            end
        end
    })
    
    UI.Controls.favFishToggle = UI.Boxes.FavoriteFish:AddToggle("favFish", {
        Text = STRINGS.AUTO_FAVORITE,
        Default = false,
        Callback = function(Value)
            if Value and UI.Features.autoFavFish then
                if UI.Features.autoFavFish.SetDesiredTiersByNames then UI.Features.autoFavFish:SetDesiredTiersByNames(UI.State.selectedTiers) end
                if UI.Features.autoFavFish.Start then UI.Features.autoFavFish:Start({ tierList = UI.State.selectedTiers }) end
            elseif UI.Features.autoFavFish and UI.Features.autoFavFish.Stop then
                UI.Features.autoFavFish:Stop()
            end
        end
    })
    
    if UI.Features.autoFavFish then
        UI.Features.autoFavFish.__controls = {
            Dropdown = UI.Controls.favFishDropdown,
            toggle = UI.Controls.favFishToggle
        }
        if UI.Features.autoFavFish.Init and not UI.Features.autoFavFish.__initialized then
            UI.Features.autoFavFish:Init(UI.Features.autoFavFish, UI.Features.autoFavFish.__controls)
            UI.Features.autoFavFish.__initialized = true
        end
    end
    
    UI.Boxes.FavoriteFish:AddDivider()
    
    UI.Features.autoFavFishV2 = FeatureManager:Get("AutoFavoriteFishV2")
    UI.State.selectedFishNames = {}
    
    UI.Controls.favFishV2Dropdown = UI.Boxes.FavoriteFish:AddDropdown("favFishV2Names", {
        Text = "Favorite by Fish Name",
        Tooltip = "Select fish names to auto favorite",
        Values = {},
        Searchable = true,
        MaxVisibileDropdownItems = 6, 
        Multi = true,
        Callback = function(Values)
            UI.State.selectedFishNames = Values or {}
            if UI.Features.autoFavFishV2 and UI.Features.autoFavFishV2.SetSelectedFishNames then
               UI.Features.autoFavFishV2:SetSelectedFishNames(UI.State.selectedFishNames)
            end
        end
    })
    
    UI.Controls.favFishV2Toggle = UI.Boxes.FavoriteFish:AddToggle("favFishV2", {
        Text = "Auto Favorite Fish V2",
        Tooltip = "Auto favorite fish by selected names",
        Default = false,
        Callback = function(Value)
            if Value and UI.Features.autoFavFishV2 then
                if UI.Features.autoFavFishV2.SetSelectedFishNames then 
                    UI.Features.autoFavFishV2:SetSelectedFishNames(UI.State.selectedFishNames) 
                end
                if UI.Features.autoFavFishV2.Start then 
                    UI.Features.autoFavFishV2:Start({ fishNames = UI.State.selectedFishNames }) 
                end
            elseif UI.Features.autoFavFishV2 and UI.Features.autoFavFishV2.Stop then
                UI.Features.autoFavFishV2:Stop()
            end
        end
    })
    
    if UI.Features.autoFavFishV2 then
        UI.Features.autoFavFishV2.__controls = {
            fishDropdown = UI.Controls.favFishV2Dropdown,
            toggle = UI.Controls.favFishV2Toggle
        }
        if UI.Features.autoFavFishV2.Init and not UI.Features.autoFavFishV2.__initialized then
            UI.Features.autoFavFishV2:Init(UI.Features.autoFavFishV2.__controls)
            UI.Features.autoFavFishV2.__initialized = true
        end
    end
    
    -- Sell Fish Section
    UI.Boxes.SellFish = UI.Tabs.Backpack:AddRightGroupbox("<b>Sell Fish</b>", "badge-dollar-sign")
    UI.Features.sellFish = FeatureManager:Get("AutoSellFish")
    UI.State.currentSellThreshold = "Legendary"
    UI.State.currentSellLimit = 0
    
    UI.Controls.sellFishDropdown = UI.Boxes.SellFish:AddDropdown("sellFish", {
        Text = STRINGS.SELECT_RARITY,
        Values = {"Secret", "Mythic", "Legendary"},
        Multi = false,
        Callback = function(Value)
            UI.State.currentSellThreshold = Value
            if UI.Features.sellFish and UI.Features.sellFish.SetMode then
               UI.Features.sellFish:SetMode(Value)
            end
        end
    })
    
    UI.Controls.sellFishInput = UI.Boxes.SellFish:AddInput("sellFishDelay", {
        Text = "Input Delay",
        Default = "60",
        Numeric = true,
        Finished = true,
        Callback = function(Value)
            local n = tonumber(Value) or 0
            UI.State.currentSellLimit = n
            if UI.Features.sellFish and UI.Features.sellFish.SetLimit then
              UI.Features.sellFish:SetLimit(n)
            end
        end
    })
    
    UI.Controls.sellFishToggle = UI.Boxes.SellFish:AddToggle("sellFish", {
        Text = STRINGS.AUTO_SELL,
        Default = false,
        Callback = function(Value)
            if Value and UI.Features.sellFish then
                if UI.Features.sellFish.SetMode then UI.Features.sellFish:SetMode(UI.State.currentSellThreshold) end
                if UI.Features.sellFish.Start then UI.Features.sellFish:Start({ 
                    threshold = UI.State.currentSellThreshold,
                    limit = UI.State.currentSellLimit,
                    autoOnLimit = true 
                }) end
            elseif UI.Features.sellFish and UI.Features.sellFish.Stop then
                UI.Features.sellFish:Stop()
            end
        end
    })
    
    if UI.Features.sellFish then
        UI.Features.sellFish.__controls = {
            Dropdown = UI.Controls.sellFishDropdown,
            Input = UI.Controls.sellFishInput,
            toggle = UI.Controls.sellFishToggle
        }
        if UI.Features.sellFish.Init and not UI.Features.sellFish.__initialized then
            UI.Features.sellFish:Init(UI.Features.sellFish, UI.Features.sellFish.__controls)
            UI.Features.sellFish.__initialized = true
        end
    end
end

local function createAutomationSection()
    -- Enchant Rod Section
    UI.Boxes.EnchantRod = UI.Tabs.Automation:AddLeftGroupbox("<b>Enchant Rod</b>", "circle-fading-arrow-up")
    UI.Features.autoEnchant = FeatureManager:Get("AutoEnchantRod")
    UI.State.selectedEnchants = {}

    UI.Controls.enchantDropdown = UI.Boxes.EnchantRod:AddDropdown("enchant", {
        Text = "Select Enchant",
        Values = GameData.enchantNames,
        Searchable = true,
        MaxVisibileDropdownItems = 6,
        Multi = true,
        Callback = function(Values)
            UI.State.selectedEnchants = Helpers.normalizeList(Values or {})
            if UI.Features.autoEnchant and UI.Features.autoEnchant.SetDesiredByNames then
                UI.Features.autoEnchant:SetDesiredByNames(UI.State.selectedEnchants)
            end
        end
    })

    UI.Controls.enchantToggle = UI.Boxes.EnchantRod:AddToggle("enchant", {
        Text = STRINGS.AUTO_ENCHANT,
        Default = false,
        Callback = function(Value)
            if Value and UI.Features.autoEnchant then
                if #UI.State.selectedEnchants == 0 then
                    Libraries.Noctis:Notify({ Title="Info", Description="Select at least 1 enchant", Duration=3 })
                    return
                end
                if UI.Features.autoEnchant.SetDesiredByNames then
                    UI.Features.autoEnchant:SetDesiredByNames(UI.State.selectedEnchants)
                end
                if UI.Features.autoEnchant.Start then
                    UI.Features.autoEnchant:Start({
                        enchantNames = UI.State.selectedEnchants,
                        delay = 8
                    })
                end
            elseif UI.Features.autoEnchant and UI.Features.autoEnchant.Stop then
                UI.Features.autoEnchant:Stop()
            end
        end
    })
    
    if UI.Features.autoEnchant then
        UI.Features.autoEnchant.__controls = {
            Dropdown = UI.Controls.enchantDropdown,
            toggle = UI.Controls.enchantToggle
        }
        if UI.Features.autoEnchant.Init and not UI.Features.autoEnchant.__initialized then
            UI.Features.autoEnchant:Init(UI.Features.autoEnchant.__controls)
            UI.Features.autoEnchant.__initialized = true
        end
    end
    
    UI.Boxes.EnchantRod:AddLabel("Equip Enchant Stone at<br/>3rd slots")
    
    -- Trade Section
    UI.Boxes.Trade = UI.Tabs.Automation:AddRightGroupbox("<b>Trade</b>", "gift")
    UI.Features.autoTrade = FeatureManager:Get("AutoSendTrade")
    UI.Features.autoAcceptTrade = FeatureManager:Get("AutoAcceptTrade")
    UI.State.selectedTradeItems = {}
    UI.State.selectedTradeEnchants = {}
    UI.State.selectedTargetPlayers = {}

    UI.Controls.tradePlayerDropdown = UI.Boxes.Trade:AddDropdown("tradePlayers", {
        Text = STRINGS.SELECT_PLAYER,
        SpecialType = "Player",
        ExcludeLocalPlayer = true,
        Searchable = true,
        MaxVisibileDropdownItems = 6,
        Multi = true,
        Callback = function(Value)
            UI.State.selectedTargetPlayers = Helpers.normalizeList(Value or {})
            if UI.Features.autoTrade and UI.Features.autoTrade.SetTargetPlayers then
                UI.Features.autoTrade:SetTargetPlayers(UI.State.selectedTargetPlayers)
            end
        end
    })

    UI.Controls.tradeFishDropdown = UI.Boxes.Trade:AddDropdown("tradeFish", {
        Text = "Select Fish",
        Values = Helpers.getFishNamesForTrade(),
        Searchable = true,
        MaxVisibileDropdownItems = 6,
        Multi = true,
        Callback = function(Values)
            UI.State.selectedTradeItems = Helpers.normalizeList(Values or {})
            if UI.Features.autoTrade and UI.Features.autoTrade.SetSelectedFish then
                UI.Features.autoTrade:SetSelectedFish(UI.State.selectedTradeItems)
            end
        end
    })

    UI.Controls.tradeEnchantDropdown = UI.Boxes.Trade:AddDropdown("tradeEnchants", {
        Text = "Select Enchant Stones",
        Values = Helpers.getEnchantStonesForTrade(),
        Searchable = true,
        MaxVisibileDropdownItems = 6,
        Multi = true,
        Callback = function(Values)
            UI.State.selectedTradeEnchants = Helpers.normalizeList(Values or {})
            if UI.Features.autoTrade and UI.Features.autoTrade.SetSelectedItems then
                UI.Features.autoTrade:SetSelectedItems(UI.State.selectedTradeEnchants)
            end
        end
    })

    UI.Controls.tradeDelayInput = UI.Boxes.Trade:AddInput("tradeDelay", {
        Text = "Input Delay",
        Default = "15",
        Numeric = true,
        Finished = true,
        Callback = function(Value)
            local delay = math.max(1, tonumber(Value) or 5)
            if UI.Features.autoTrade and UI.Features.autoTrade.SetTradeDelay then
                UI.Features.autoTrade:SetTradeDelay(delay)
            end
        end
    })

    UI.Controls.tradeRefreshButton = UI.Boxes.Trade:AddButton({
        Text = "Refresh Player List",
        Func = function()
            local names = Helpers.listPlayers(true)
            if UI.Controls.tradePlayerDropdown.SetValue then UI.Controls.tradePlayerDropdown:SetValue(names) end
            Libraries.Noctis:Notify({ Title = "Players", Description = ("Online: %d"):format(#names), Duration = 2 })
        end
    })

    UI.Controls.tradeSendToggle = UI.Boxes.Trade:AddToggle("tradeSend", {
        Text = STRINGS.AUTO_TRADE,
        Default = false,
        Callback = function(Value)
            if Value and UI.Features.autoTrade then
                if #UI.State.selectedTradeItems == 0 and #UI.State.selectedTradeEnchants == 0 then
                    Libraries.Noctis:Notify({ Title="Info", Description="Select at least 1 fish or enchant stone first", Duration=3 })
                    return
                end
                if #UI.State.selectedTargetPlayers == 0 then
                    Libraries.Noctis:Notify({ Title="Info", Description="Select at least 1 target player", Duration=3 })
                    return
                end

                local delay = math.max(1, tonumber(UI.Controls.tradeDelayInput.Value) or 5)
                if UI.Features.autoTrade.SetSelectedFish then UI.Features.autoTrade:SetSelectedFish(UI.State.selectedTradeItems) end
                if UI.Features.autoTrade.SetSelectedItems then UI.Features.autoTrade:SetSelectedItems(UI.State.selectedTradeEnchants) end
                if UI.Features.autoTrade.SetTargetPlayers then UI.Features.autoTrade:SetTargetPlayers(UI.State.selectedTargetPlayers) end
                if UI.Features.autoTrade.SetTradeDelay then UI.Features.autoTrade:SetTradeDelay(delay) end

                UI.Features.autoTrade:Start({
                    fishNames = UI.State.selectedTradeItems,
                    itemNames = UI.State.selectedTradeEnchants,
                    playerList = UI.State.selectedTargetPlayers,
                    tradeDelay = delay,
                })
            elseif UI.Features.autoTrade and UI.Features.autoTrade.Stop then
                UI.Features.autoTrade:Stop()
            end
        end
    })

    if UI.Features.autoTrade then
        UI.Features.autoTrade.__controls = {
            playerDropdown = UI.Controls.tradePlayerDropdown,
            itemDropdown = UI.Controls.tradeFishDropdown,
            itemsDropdown = UI.Controls.tradeEnchantDropdown,
            delayInput = UI.Controls.tradeDelayInput,
            toggle = UI.Controls.tradeSendToggle,
            button = UI.Controls.tradeRefreshButton
        }
        if UI.Features.autoTrade.Init and not UI.Features.autoTrade.__initialized then
            UI.Features.autoTrade:Init(UI.Features.autoTrade, UI.Features.autoTrade.__controls)
            UI.Features.autoTrade.__initialized = true
        end
    end

    UI.Boxes.Trade:AddDivider()
    UI.Controls.tradeAcceptToggle = UI.Boxes.Trade:AddToggle("tradeAccept", {
        Text = STRINGS.AUTO_ACCEPT_TRADE,
        Default = false,
        Callback = function(Values)
            if Values and UI.Features.autoAcceptTrade and UI.Features.autoAcceptTrade.Start then
                UI.Features.autoAcceptTrade:Start({ 
                    ClicksPerSecond = 18,
                    EdgePaddingFrac = 0 
                })
            elseif UI.Features.autoAcceptTrade and UI.Features.autoAcceptTrade.Stop then
                UI.Features.autoAcceptTrade:Stop()
            end
        end
    })
    
    if UI.Features.autoAcceptTrade then
        UI.Features.autoAcceptTrade.__controls = { toggle = UI.Controls.tradeAcceptToggle }
        if UI.Features.autoAcceptTrade.Init and not UI.Features.autoAcceptTrade.__initialized then
            UI.Features.autoAcceptTrade:Init(UI.Features.autoAcceptTrade, UI.Features.autoAcceptTrade.__controls)
            UI.Features.autoAcceptTrade.__initialized = true
        end
    end
end

local function createShopSection()
    -- Rod Shop Section
    UI.Boxes.RodShop = UI.Tabs.Shop:AddLeftGroupbox("<b>Rod</b>", "store")
    UI.Features.autoBuyRod = FeatureManager:Get("AutoBuyRod")
    UI.State.selectedRodsSet = {}
    
    local function updateRodPriceLabel()
        local total = Helpers.calculateTotalPrice(UI.State.selectedRodsSet, Helpers.getRodPrice)
        if UI.Controls.rodPriceLabel then
            UI.Controls.rodPriceLabel:SetText("Total Price: " .. Helpers.abbreviateNumber(total, 1))
        end
    end

    UI.Controls.shopRodDropdown = UI.Boxes.RodShop:AddDropdown("shopRod", {
        Text = "Select Rod",
        Values = GameData.rodNames,
        Searchable = true,
        MaxVisibileDropdownItems = 6,
        Multi = true,
        Callback = function(Values)
            UI.State.selectedRodsSet = Helpers.normalizeList(Values or {})
            updateRodPriceLabel()
            if UI.Features.autoBuyRod and UI.Features.autoBuyRod.SetSelectedRodsByName then
                UI.Features.autoBuyRod:SetSelectedRodsByName(UI.State.selectedRodsSet)
            end
        end
    })

    UI.Controls.rodPriceLabel = UI.Boxes.RodShop:AddLabel(STRINGS.TOTAL_PRICE)
    UI.Controls.shopRodButton = UI.Boxes.RodShop:AddButton({
        Text = STRINGS.BUY_ROD,
        Func = function()
            if UI.Features.autoBuyRod.SetSelectedRodsByName then UI.Features.autoBuyRod:SetSelectedRodsByName(UI.State.selectedRodsSet) end
            if UI.Features.autoBuyRod.Start then UI.Features.autoBuyRod:Start({ 
                rodList = UI.State.selectedRodsSet,
                interDelay = 0.5 
            }) end
        end
    })
    
    if UI.Features.autoBuyRod then
        UI.Features.autoBuyRod.__controls = {
            Dropdown = UI.Controls.shopRodDropdown,
            button = UI.Controls.shopRodButton
        }
        if UI.Features.autoBuyRod.Init and not UI.Features.autoBuyRod.__initialized then
            UI.Features.autoBuyRod:Init(UI.Features.autoBuyRod, UI.Features.autoBuyRod.__controls)
            UI.Features.autoBuyRod.__initialized = true
        end
    end

    -- Bait Shop Section
    UI.Boxes.BaitShop = UI.Tabs.Shop:AddLeftGroupbox("<b>Bait</b>", "store")
    UI.Features.autoBuyBait = FeatureManager:Get("AutoBuyBait")
    UI.State.selectedBaitsSet = {}
    
    local function updateBaitPriceLabel()
        local total = Helpers.calculateTotalPrice(UI.State.selectedBaitsSet, Helpers.getBaitPrice)
        if UI.Controls.baitPriceLabel then
            UI.Controls.baitPriceLabel:SetText("Total Price: " .. Helpers.abbreviateNumber(total, 1))
        end
    end

    UI.Controls.shopBaitDropdown = UI.Boxes.BaitShop:AddDropdown("shopBait", {
        Text = "Select Bait",
        Values = GameData.baitNames,
        Searchable = true,
        MaxVisibileDropdownItems = 6,
        Multi = true,
        Callback = function(Values)
            UI.State.selectedBaitsSet = Helpers.normalizeList(Values or {})
            updateBaitPriceLabel()
            if UI.Features.autoBuyBait and UI.Features.autoBuyBait.SetSelectedBaitsByName then
                UI.Features.autoBuyBait:SetSelectedBaitsByName(UI.State.selectedBaitsSet)
            end
        end
    })

    UI.Controls.baitPriceLabel = UI.Boxes.BaitShop:AddLabel(STRINGS.TOTAL_PRICE)
    UI.Controls.shopBaitButton = UI.Boxes.BaitShop:AddButton({
        Text = STRINGS.BUY_BAIT,
        Func = function()
            if UI.Features.autoBuyBait.SetSelectedBaitsByName then UI.Features.autoBuyBait:SetSelectedBaitsByName(UI.State.selectedBaitsSet) end
            if UI.Features.autoBuyBait.Start then UI.Features.autoBuyBait:Start({ 
                baitList = UI.State.selectedBaitsSet,
                interDelay = 0.5 
            }) end
        end
    })
    
    if UI.Features.autoBuyBait then
        UI.Features.autoBuyBait.__controls = {
            Dropdown = UI.Controls.shopBaitDropdown,
            button = UI.Controls.shopBaitButton
        }
        if UI.Features.autoBuyBait.Init and not UI.Features.autoBuyBait.__initialized then
            UI.Features.autoBuyBait:Init(UI.Features.autoBuyBait, UI.Features.autoBuyBait.__controls)
            UI.Features.autoBuyBait.__initialized = true
        end
    end

    -- Weather Shop Section
    UI.Boxes.WeatherShop = UI.Tabs.Shop:AddRightGroupbox("<b>Weather</b>", "store")
    UI.Features.autoBuyWeather = FeatureManager:Get("AutoBuyWeather")
    UI.State.selectedWeatherSet = {} 
    
    UI.Controls.shopWeatherDropdown = UI.Boxes.WeatherShop:AddDropdown("shopWeather", {
        Text = "Select Weather",
        Values = GameData.weatherNames,
        Searchable = true,
        MaxVisibileDropdownItems = 6,
        Multi = true,
        Callback = function(Values)
            UI.State.selectedWeatherSet = Values or {}
            if UI.Features.autoBuyWeather and UI.Features.autoBuyWeather.SetWeathers then
               UI.Features.autoBuyWeather:SetWeathers(UI.State.selectedWeatherSet)
            end
        end
    })
    
    UI.Boxes.WeatherShop:AddLabel("Max 3")
    UI.Controls.shopWeatherToggle = UI.Boxes.WeatherShop:AddToggle("shopWeather", {
        Text = STRINGS.AUTO_BUY_WEATHER,
        Default = false,
        Callback = function(Value)
            if Value and UI.Features.autoBuyWeather then
                if UI.Features.autoBuyWeather.SetWeathers then UI.Features.autoBuyWeather:SetWeathers(UI.State.selectedWeatherSet) end
                if UI.Features.autoBuyWeather.Start then UI.Features.autoBuyWeather:Start({ 
                    weatherList = UI.State.selectedWeatherSet 
                }) end
            elseif UI.Features.autoBuyWeather and UI.Features.autoBuyWeather.Stop then
                UI.Features.autoBuyWeather:Stop()
            end
        end
    })
    
    if UI.Features.autoBuyWeather then
        UI.Features.autoBuyWeather.__controls = {
            Dropdown = UI.Controls.shopWeatherDropdown,
            toggle = UI.Controls.shopWeatherToggle
        }
        if UI.Features.autoBuyWeather.Init and not UI.Features.autoBuyWeather.__initialized then
            UI.Features.autoBuyWeather:Init(UI.Features.autoBuyWeather, UI.Features.autoBuyWeather.__controls)
            UI.Features.autoBuyWeather.__initialized = true
        end
    end
end

local function createTeleportSection()
    -- Island Teleport Section
    UI.Boxes.IslandTeleport = UI.Tabs.Teleport:AddLeftGroupbox("<b>Island</b>", "map")
    UI.Features.autoTeleIsland = FeatureManager:Get("AutoTeleportIsland")
    UI.State.currentIsland = "Fisherman Island"
    
    UI.Controls.teleIslandDropdown = UI.Boxes.IslandTeleport:AddDropdown("teleIsland", {
        Text = STRINGS.SELECT_ISLAND,
        Values = {
            "Fisherman Island", "Esoteric Depths", "Enchant Altar", "Kohana", "Kohana Volcano",
            "Tropical Grove", "Crater Island", "Coral Reefs", "Sisyphus Statue", "Treasure Room"
        },
        Searchable = true,
        MaxVisibileDropdownItems = 6,
        Multi = false,
        Callback = function(Value)
            UI.State.currentIsland = Value
            if UI.Features.autoTeleIsland and UI.Features.autoTeleIsland.SetIsland then
               UI.Features.autoTeleIsland:SetIsland(Value)
            end
        end
    })
    
    UI.Controls.teleIslandButton = UI.Boxes.IslandTeleport:AddButton({
        Text = STRINGS.TELEPORT,
        Func = function()
            if UI.Features.autoTeleIsland then
                if UI.Features.autoTeleIsland.SetIsland then
                    UI.Features.autoTeleIsland:SetIsland(UI.State.currentIsland)
                end
                if UI.Features.autoTeleIsland.Teleport then
                    UI.Features.autoTeleIsland:Teleport(UI.State.currentIsland)
                end
            end
        end
    })
    
    if UI.Features.autoTeleIsland then
        UI.Features.autoTeleIsland.__controls = {
            Dropdown = UI.Controls.teleIslandDropdown,
            button = UI.Controls.teleIslandButton
        }
        if UI.Features.autoTeleIsland.Init and not UI.Features.autoTeleIsland.__initialized then
            UI.Features.autoTeleIsland:Init(UI.Features.autoTeleIsland, UI.Features.autoTeleIsland.__controls)
            UI.Features.autoTeleIsland.__initialized = true
        end
    end

    -- Player Teleport Section
    UI.Boxes.PlayerTeleport = UI.Tabs.Teleport:AddRightGroupbox("<b>Player</b>", "person-standing")
    UI.Features.telePlayer = FeatureManager:Get("AutoTeleportPlayer")
    UI.State.currentPlayerName = nil
    
    UI.Controls.telePlayerDropdown = UI.Boxes.PlayerTeleport:AddDropdown("telePlayer", {
        Text = STRINGS.SELECT_PLAYER,
        Values = Helpers.listPlayers(true),
        Searchable = true,
        MaxVisibileDropdownItems = 6,
        Multi = false,
        Callback = function(Value)
            local name = Helpers.normalizeOption(Value)
            UI.State.currentPlayerName = name
            if UI.Features.telePlayer and UI.Features.telePlayer.SetTarget then
                UI.Features.telePlayer:SetTarget(name)
            end
        end
    })
    
    UI.Controls.telePlayerButton = UI.Boxes.PlayerTeleport:AddButton({
        Text = STRINGS.TELEPORT,
        Func = function()
            if UI.Features.telePlayer then
                if UI.Features.telePlayer.SetTarget then
                    UI.Features.telePlayer:SetTarget(UI.State.currentPlayerName)
                end
                if UI.Features.telePlayer.Teleport then
                    UI.Features.telePlayer:Teleport(UI.State.currentPlayerName)
                end
            end
        end
    })
    
    UI.Controls.telePlayerRefreshButton = UI.Controls.telePlayerButton:AddButton({
        Text = "Refresh",
        Func = function()
            local names = Helpers.listPlayers(true)
            if UI.Controls.telePlayerDropdown.SetValue then UI.Controls.telePlayerDropdown:SetValue(names) end
            Libraries.Noctis:Notify({ Title = "Players", Description = ("Online: %d"):format(#names), Duration = 2 })
        end
    })
        
    if UI.Features.telePlayer then
        UI.Features.telePlayer.__controls = {
            dropdown = UI.Controls.telePlayerDropdown,
            refreshButton = UI.Controls.telePlayerRefreshButton,
            teleportButton = UI.Controls.telePlayerButton
        }
        if UI.Features.telePlayer.Init and not UI.Features.telePlayer.__initialized then
            UI.Features.telePlayer:Init(UI.Features.telePlayer, UI.Features.telePlayer.__controls)
            UI.Features.telePlayer.__initialized = true
        end
    end

    -- Position Teleport Section
    UI.Boxes.PositionTeleport = UI.Tabs.Teleport:AddLeftGroupbox("<b>Position Teleport</b>", "anchor")
    UI.Features.positionManager = FeatureManager:Get("PositionManager")
    
    UI.Controls.savePositionInput = UI.Boxes.PositionTeleport:AddInput("savePosition", {
        Text = "Position Name",
        Default = "",
        Numeric = false,
        Finished = true,
        Callback = function(Value) end
    })
    
    UI.Controls.savePositionAddButton = UI.Boxes.PositionTeleport:AddButton({
        Text = "Add Position",
        Func = function()
            if not UI.Features.positionManager then return end
            
            local name = UI.Controls.savePositionInput.Value
            if not name or name == "" or name == "Position Name" then
                Libraries.Noctis:Notify({
                    Title = "Position Teleport",
                    Description = "Please enter a valid position name",
                    Duration = 3
                })
                return
            end
            
            local success, message = UI.Features.positionManager:AddPosition(name)
            if success then
                Libraries.Noctis:Notify({
                    Title = "Position Teleport",
                    Description = "Position '" .. name .. "' added successfully",
                    Duration = 2
                })
                UI.Controls.savePositionInput:SetValue("")
            else
                Libraries.Noctis:Notify({
                    Title = "Position Teleport",
                    Description = message or "Failed to add position",
                    Duration = 3
                })
            end
        end
    })
    
    UI.Controls.savePositionDropdown = UI.Boxes.PositionTeleport:AddDropdown("savedPositions", {
        Text = "Select Position",
        Tooltip = "Choose a saved position to teleport",
        Values = {"No Positions"},
        Searchable = true,
        MaxVisibileDropdownItems = 6,
        Multi = false,
        Callback = function(Value) end
    })
    
    UI.Controls.savePositionDeleteButton = UI.Boxes.PositionTeleport:AddButton({
        Text = "Delete Pos",
        Func = function()
            if not UI.Features.positionManager then return end
            
            local selectedPos = UI.Controls.savePositionDropdown.Value
            if not selectedPos or selectedPos == "No Positions" then
                Libraries.Noctis:Notify({
                    Title = "Position Teleport",
                    Description = "Please select a position to delete",
                    Duration = 3
                })
                return
            end
            
            local success, message = UI.Features.positionManager:DeletePosition(selectedPos)
            if success then
                Libraries.Noctis:Notify({
                    Title = "Position Teleport",
                    Description = "Position '" .. selectedPos .. "' deleted",
                    Duration = 2
                })
            else
                Libraries.Noctis:Notify({
                    Title = "Position Teleport",
                    Description = message or "Failed to delete position",
                    Duration = 3
                })
            end
        end
    })
    
    UI.Controls.savePositionRefreshButton = UI.Controls.savePositionDeleteButton:AddButton({
        Text = "Refresh Pos",
        Func = function()
            if not UI.Features.positionManager then return end
            
            local list = UI.Features.positionManager:RefreshDropdown()
            local count = #list
            if list[1] == "No Positions" then count = 0 end
            
            Libraries.Noctis:Notify({
                Title = "Position Teleport",
                Description = count .. " positions found",
                Duration = 2
            })
        end
    })
    
    UI.Controls.savePositionTeleportButton = UI.Boxes.PositionTeleport:AddButton({
        Text = STRINGS.TELEPORT,
        Func = function()
            if not UI.Features.positionManager then return end
            
            local selectedPos = UI.Controls.savePositionDropdown.Value
            if not selectedPos or selectedPos == "No Positions" then
                Libraries.Noctis:Notify({
                    Title = "Position Teleport",
                    Description = "Please select a position to teleport",
                    Duration = 3
                })
                return
            end
            
            local success, message = UI.Features.positionManager:TeleportToPosition(selectedPos)
            if success then
                Libraries.Noctis:Notify({
                    Title = "Position Teleport",
                    Description = "Teleported to '" .. selectedPos .. "'",
                    Duration = 2
                })
            else
                Libraries.Noctis:Notify({
                    Title = "Position Teleport",
                    Description = message or "Failed to teleport",
                    Duration = 3
                })
            end
        end
    })
    
    if UI.Features.positionManager then
        UI.Features.positionManager.__controls = {
            dropdown = UI.Controls.savePositionDropdown,
            input = UI.Controls.savePositionInput,
            addButton = UI.Controls.savePositionAddButton,
            deleteButton = UI.Controls.savePositionDeleteButton,
            teleportButton = UI.Controls.savePositionTeleportButton,
            refreshButton = UI.Controls.savePositionRefreshButton
        }
        if UI.Features.positionManager.Init and not UI.Features.positionManager.__initialized then
            UI.Features.positionManager:Init(UI.Features.positionManager, UI.Features.positionManager.__controls)
            UI.Features.positionManager.__initialized = true
        end
    end
end

local function createMiscSection()
    -- Webhook Section
    UI.Boxes.Webhook = UI.Tabs.Misc:AddLeftGroupbox("<b>Webhook</b>", "bell-ring")
    UI.Features.fishWebhook = FeatureManager:Get("FishWebhook")
    UI.State.currentWebhookUrl = ""
    UI.State.selectedWebhookFishTypes = {}

    UI.Controls.webhookInput = UI.Boxes.Webhook:AddInput("webhook", {
        Text = STRINGS.WEBHOOK_URL,
        Default = "",
        Numeric = false,
        Finished = true,
        Callback = function(Value)
            UI.State.currentWebhookUrl = Value
            if UI.Features.fishWebhook and UI.Features.fishWebhook.SetWebhookUrl then
                UI.Features.fishWebhook:SetWebhookUrl(Value)
            end
        end
    })

    UI.Controls.webhookDropdown = UI.Boxes.Webhook:AddDropdown("webhookRarity", {
        Text = STRINGS.SELECT_RARITY,
        Values = GameData.tierNames,
        Searchable = true,
        MaxVisibileDropdownItems = 6,
        Multi = true,
        Callback = function(Values)
            UI.State.selectedWebhookFishTypes = Helpers.normalizeList(Values or {})
            
            if UI.Features.fishWebhook and UI.Features.fishWebhook.SetSelectedFishTypes then
                UI.Features.fishWebhook:SetSelectedFishTypes(UI.State.selectedWebhookFishTypes)
            end
            
            if UI.Features.fishWebhook and UI.Features.fishWebhook.SetSelectedTiers then
                UI.Features.fishWebhook:SetSelectedTiers(UI.State.selectedWebhookFishTypes)
            end
        end
    })

    UI.Controls.webhookToggle = UI.Boxes.Webhook:AddToggle("webhook", {
        Text = STRINGS.ENABLE_WEBHOOK,
        Default = false,
        Callback = function(Value)
            if Value and UI.Features.fishWebhook then
                if UI.Features.fishWebhook.SetWebhookUrl then 
                    UI.Features.fishWebhook:SetWebhookUrl(UI.State.currentWebhookUrl) 
                end
                
                if UI.Features.fishWebhook.SetSelectedFishTypes then 
                    UI.Features.fishWebhook:SetSelectedFishTypes(UI.State.selectedWebhookFishTypes) 
                end
                if UI.Features.fishWebhook.SetSelectedTiers then 
                    UI.Features.fishWebhook:SetSelectedTiers(UI.State.selectedWebhookFishTypes) 
                end
                
                if UI.Features.fishWebhook.Start then 
                    UI.Features.fishWebhook:Start({ 
                        webhookUrl = UI.State.currentWebhookUrl,
                        selectedTiers = UI.State.selectedWebhookFishTypes,
                        selectedFishTypes = UI.State.selectedWebhookFishTypes
                    }) 
                end
            elseif UI.Features.fishWebhook and UI.Features.fishWebhook.Stop then
                UI.Features.fishWebhook:Stop()
            end
        end
    })
    
    if UI.Features.fishWebhook then
        UI.Features.fishWebhook.__controls = {
            urlInput = UI.Controls.webhookInput,
            fishTypesDropdown = UI.Controls.webhookDropdown,
            toggle = UI.Controls.webhookToggle
        }

        if UI.Features.fishWebhook.Init and not UI.Features.fishWebhook.__initialized then
            UI.Features.fishWebhook:Init(UI.Features.fishWebhook, UI.Features.fishWebhook.__controls)
            UI.Features.fishWebhook.__initialized = true
        end
    end

    -- Server Section
    UI.Boxes.Server = UI.Tabs.Misc:AddRightGroupbox("<b>Server</b>", "server")
    UI.Features.copyJoinServer = FeatureManager:Get("CopyJoinServer")
    
    UI.Controls.serverInput = UI.Boxes.Server:AddInput("server", {
        Text = "Input JobId",
        Default = "",
        Numeric = false,
        Finished = true,
        Callback = function(Value)
            if UI.Features.copyJoinServer then UI.Features.copyJoinServer:SetTargetJobId(Value) end
        end
    })
    
    UI.Controls.serverJoinButton = UI.Boxes.Server:AddButton({
        Text = "Join JobId",
        Func = function()
            if UI.Features.copyJoinServer then
                local jobId = UI.Controls.serverInput.Value
                UI.Features.copyJoinServer:JoinServer(jobId)
            end
        end
    })
    
    UI.Controls.serverCopyButton = UI.Controls.serverJoinButton:AddButton({
        Text = "Copy JobId",
        Func = function()
            if UI.Features.copyJoinServer then UI.Features.copyJoinServer:CopyCurrentJobId() end
        end
    })

    if UI.Features.copyJoinServer then
        UI.Features.copyJoinServer.__controls = {
            input = UI.Controls.serverInput,
            joinButton = UI.Controls.serverJoinButton,
            copyButton = UI.Controls.serverCopyButton
        }
        if UI.Features.copyJoinServer.Init and not UI.Features.copyJoinServer.__initialized then
            UI.Features.copyJoinServer:Init(UI.Features.copyJoinServer, UI.Features.copyJoinServer.__controls)
            UI.Features.copyJoinServer.__initialized = true
        end
    end
    
    UI.Boxes.Server:AddDivider()

    -- Auto Reconnect
    UI.Features.autoReconnect = FeatureManager:Get("AutoReconnect")
    UI.Controls.reconnectToggle = UI.Boxes.Server:AddToggle("reconnect", {
        Text = STRINGS.AUTO_RECONNECT,
        Default = false,
        Callback = function(Value)
            if Value then
                UI.Features.autoReconnect:Start()
            else
                UI.Features.autoReconnect:Stop()
            end
        end
    })

    if UI.Features.autoReconnect then
        UI.Features.autoReconnect.__controls = { toggle = UI.Controls.reconnectToggle }
        if UI.Features.autoReconnect.Init and not UI.Features.autoReconnect.__initialized then
            UI.Features.autoReconnect:Init()
            UI.Features.autoReconnect.__initialized = true
        end
    end
    
    -- Auto Reexecute
    UI.Features.autoReexec = FeatureManager:Get("AutoReexec")
    if UI.Features.autoReexec and UI.Features.autoReexec.Init and not UI.Features.autoReexec.__initialized then
        UI.Features.autoReexec:Init({
            mode = "url",
            url = "https://raw.githubusercontent.com/c3iv3r/a/refs/heads/main/dev/fishdev.lua",
            rearmEveryS = 20,
            addBootGuard = true,
        })
        UI.Features.autoReexec.__initialized = true
    end
    
    UI.Controls.reexecToggle = UI.Boxes.Server:AddToggle("reexec", {
        Text = "Re-Execute on Reconnect",
        Default = false,
        Callback = function(state)
            if not UI.Features.autoReexec then return end
            if state then
                local ok, err = pcall(function() UI.Features.autoReexec:Start() end)
                if not ok then warn("[AutoReexec] Start failed:", err) end
            else
                local ok, err = pcall(function() UI.Features.autoReexec:Stop() end)
                if not ok then warn("[AutoReexec] Stop failed:", err) end
            end
        end
    })

    -- Others Section
    UI.Boxes.Other = UI.Tabs.Misc:AddLeftGroupbox("<b>Other</b>", "blend")
    UI.Features.autoGear = FeatureManager:Get("AutoGearOxyRadar")
    UI.Features.antiAfk = FeatureManager:Get("AntiAfk")
    UI.Features.boostFPS = FeatureManager:Get("BoostFPS")
    UI.State.oxygenOn = false
    UI.State.radarOn = false
    
    UI.Controls.oxygenToggle = UI.Boxes.Other:AddToggle("oxygen", {
        Text = "Equip Diving Gear",
        Default = false,
        Callback = function(Value)
            UI.State.oxygenOn = Value
            if Value then
                if UI.Features.autoGear and UI.Features.autoGear.Start then
                    UI.Features.autoGear:Start()
                end
                if UI.Features.autoGear and UI.Features.autoGear.EnableOxygen then
                    UI.Features.autoGear:EnableOxygen(true)
                end
            else
                if UI.Features.autoGear and UI.Features.autoGear.EnableOxygen then
                    UI.Features.autoGear:EnableOxygen(false)
                end
            end
            if UI.Features.autoGear and (not UI.State.oxygenOn) and (not UI.State.radarOn) and UI.Features.autoGear.Stop then
                UI.Features.autoGear:Stop()
            end
        end
    })
    
    UI.Controls.radarToggle = UI.Boxes.Other:AddToggle("radar", {
        Text = "Enable Fish Radar",
        Default = false,
        Callback = function(Value)
            UI.State.radarOn = Value
            if Value then
                if UI.Features.autoGear and UI.Features.autoGear.Start then
                    UI.Features.autoGear:Start()
                end
                if UI.Features.autoGear and UI.Features.autoGear.EnableRadar then
                    UI.Features.autoGear:EnableRadar(true)
                end
            else
                if UI.Features.autoGear and UI.Features.autoGear.EnableRadar then
                    UI.Features.autoGear:EnableRadar(false)
                end
            end
            if UI.Features.autoGear and (not UI.State.oxygenOn) and (not UI.State.radarOn) and UI.Features.autoGear.Stop then
                UI.Features.autoGear:Stop()
            end
        end
    })
    
    if UI.Features.autoGear then
        UI.Features.autoGear.__controls = {
            oxygenToggle = UI.Controls.oxygenToggle,
            radarToggle = UI.Controls.radarToggle
        }
        if UI.Features.autoGear.Init and not UI.Features.autoGear.__initialized then
            UI.Features.autoGear:Init(UI.Features.autoGear, UI.Features.autoGear.__controls)
            UI.Features.autoGear.__initialized = true
        end
    end
    
    UI.Controls.antiAfkToggle = UI.Boxes.Other:AddToggle("antiAfk", {
        Text = STRINGS.ANTI_AFK,
        Default = false,
        Callback = function(Value)
            if Value then
                if UI.Features.antiAfk and UI.Features.antiAfk.Start then
                    UI.Features.antiAfk:Start()
                end
            else
                if UI.Features.antiAfk and UI.Features.antiAfk.Stop then 
                    UI.Features.antiAfk:Stop()
                end
            end
        end
    })
    
    if UI.Features.antiAfk then
        UI.Features.antiAfk.__controls = { Toggle = UI.Controls.antiAfkToggle }
        if UI.Features.antiAfk.Init and not UI.Features.antiAfk.__initialized then
            UI.Features.antiAfk:Init(UI.Features.antiAfk, UI.Features.antiAfk.__controls)
            UI.Features.antiAfk.__initialized = true
        end
    end

    UI.Boxes.Other:AddDivider()
    
    UI.Controls.boostFPSButton = UI.Boxes.Other:AddButton({
        Text = STRINGS.BOOST_FPS,
        Func = function()
            if UI.Features.boostFPS and UI.Features.boostFPS.Start then
                UI.Features.boostFPS:Start()
                Libraries.Noctis:Notify({
                    Title = STRINGS.TITLE,
                    Description = "FPS Boost has been activated!",
                    Duration = 3
                })
            end
        end
    })

    if UI.Features.boostFPS then
        UI.Features.boostFPS.__controls = { button = UI.Controls.boostFPSButton }
        if UI.Features.boostFPS.Init and not UI.Features.boostFPS.__initialized then
            UI.Features.boostFPS:Init(UI.Features.boostFPS.__controls)
            UI.Features.boostFPS.__initialized = true
        end
    end
end

-- Initialize UI sections
createHomeSection()
createMainSection()
createBackpackSection()
createAutomationSection()
createShopSection()
createTeleportSection()
createMiscSection()

-- Set up inventory watcher
local inventoryWatcher = _G.InventoryWatcher and _G.InventoryWatcher.new()
if inventoryWatcher then
    inventoryWatcher:onReady(function()
        local function updateLabels()
            local counts = inventoryWatcher:getCountsByType()
            UI.Controls.fishesLabel:SetText("Fishes: " .. (counts["Fishes"] or 0))
            UI.Controls.itemsLabel:SetText("Items: " .. (counts["Items"] or 0))
        end
        updateLabels()
        inventoryWatcher:onChanged(updateLabels)
    end)
end

-- Set up player stats monitoring
local function updatePlayerStats()
    local leaderstats = Services.LocalPlayer:FindFirstChild("leaderstats")
    if leaderstats then
        local caught = leaderstats:FindFirstChild("Caught")
        local rarest = leaderstats:FindFirstChild("Rarest Fish")
        if caught and caught:IsA("IntValue") then
            UI.Controls.caughtLabel:SetText("Caught: " .. caught.Value)
            caught:GetPropertyChangedSignal("Value"):Connect(function()
                UI.Controls.caughtLabel:SetText("Caught: " .. caught.Value)
            end)
        end
        if rarest and rarest:IsA("StringValue") then
            UI.Controls.rarestLabel:SetText("Rarest Fish: " .. rarest.Value)
            rarest:GetPropertyChangedSignal("Value"):Connect(function()
                UI.Controls.rarestLabel:SetText("Rarest Fish: " .. rarest.Value)
            end)
        end
    end
end

Services.LocalPlayer:WaitForChild("leaderstats")
updatePlayerStats()

-- Theme and Save managers
Libraries.ThemeManager:SetLibrary(Libraries.Noctis)
Libraries.SaveManager:SetLibrary(Libraries.Noctis)
Libraries.SaveManager:IgnoreThemeSettings()
Libraries.SaveManager:SetIgnoreIndexes({ "MenuKeybind" })
Libraries.ThemeManager:SetFolder("NoctisTheme")
Libraries.SaveManager:SetFolder("Noctis/FishIt")
Libraries.SaveManager:BuildConfigSection(UI.Tabs.Setting)
Libraries.ThemeManager:ApplyToTab(UI.Tabs.Setting)
Libraries.SaveManager:LoadAutoloadConfig()

task.defer(function()
    task.wait(0.1)
    Libraries.Noctis:Notify({
        Title = STRINGS.TITLE,
        Description = "Enjoy! Join Our Discord!",
        Duration = 3
    })
end)