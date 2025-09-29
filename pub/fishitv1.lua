local Logger       = loadstring(game:HttpGet("https://raw.githubusercontent.com/c3iv3r/a/refs/heads/main/utils/logger.lua"))()

-- FOR PRODUCTION: 
Logger.disableAll()

-- FOR DEVELOPMENT:
--Logger.enableAll()

local mainLogger = Logger.new("Main")
local featureLogger = Logger.new("FeatureManager")

local Noctis       = loadstring(game:HttpGet("https://raw.githubusercontent.com/hailazra/Obsidian/refs/heads/main/Library.lua"))()
local ThemeManager = loadstring(game:HttpGet("https://raw.githubusercontent.com/hailazra/Obsidian/refs/heads/main/addons/ThemeManager.lua"))()
local SaveManager  = loadstring(game:HttpGet("https://raw.githubusercontent.com/hailazra/Obsidian/refs/heads/main/addons/SaveManager.lua"))()

-- ===========================
-- GLOBAL SERVICES & VARIABLES
-- ===========================
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local LocalPlayer = Players.LocalPlayer
local HttpService = game:GetService("HttpService")
local EnchantModule = ReplicatedStorage.Enchants
local BaitModule = ReplicatedStorage.Baits
local ItemsModule = ReplicatedStorage.Items
local WeatherModule = ReplicatedStorage.Events
local BoatModule = ReplicatedStorage.Boats
local TiersModule = ReplicatedStorage.Tiers

--- === HELPERS FOR DROPDOWN BY REAL DATA GAME === ---
local function getEnchantName()
    local names = {}
    for _, ms in ipairs(EnchantModule:GetChildren()) do
        if ms:IsA("ModuleScript") then
            local ok, mod = pcall(require, ms)
            if ok and type(mod)=="table" and mod.Data then
                local id   = tonumber(mod.Data.Id)
                local name = tostring(mod.Data.Name or ms.Name)
                if id and name then
                    table.insert(names, name)
                end
            end
        end
    end
    table.sort(names)
    return names
end


--- Bait
local function getBaitNames()
    local baitName = {}
    for _, item in pairs(BaitModule:GetChildren()) do
        if item:IsA("ModuleScript") then
            local success, moduleData = pcall(function()
                return require(item)
            end)

            if success and moduleData then
                if moduleData.Data and moduleData.Data.Type == "Baits" then
                    if moduleData.Price then
                        table.insert(baitName, item.Name)
                    end
                end
            end
        end
    end

    return baitName
end

--- Rod
local function getFishingRodNames()
    local rodNames = {}
    for _, item in pairs(ItemsModule:GetChildren()) do
        if item:IsA("ModuleScript") then
            local success, moduleData = pcall(function()
                return require(item)
            end)

            if success and moduleData and moduleData.Data then
                -- Gabungin semua kondisi jadi 1 line
                if moduleData.Data.Type == "Fishing Rods" and moduleData.Price and moduleData.Data.Name then
                    table.insert(rodNames, moduleData.Data.Name)
                end
            end
        end
    end

    table.sort(rodNames)
    return rodNames
end

--- Weather (Buyable)
local function getWeatherNames()
    local weatherName = {}
    for _, weather in pairs(WeatherModule:GetChildren()) do
        if weather:IsA("ModuleScript") then
            local success, moduleData = pcall(function()
                return require(weather)
            end)

            if success and moduleData then 
                if moduleData.WeatherMachine == true and moduleData.WeatherMachinePrice then
                    table.insert(weatherName, weather.Name)
                end
            end
        end
    end

    table.sort(weatherName)
    return weatherName
end

--- Weather (Event)
local function getEventNames()
    local eventNames = {}
    for _, event in pairs(WeatherModule:GetChildren()) do
        if event:IsA("ModuleScript") then
            local success, moduleData = pcall(function()
                return require(event)
            end)

            if success and moduleData then
                if moduleData.Coordinates and moduleData.Name then
                    table.insert(eventNames, moduleData.Name)
                end
            end
        end
    end

    table.sort(eventNames)
    return eventNames
end

--- Tiers (Rarity)
-- Function untuk ambil semua tier names
local function getTierNames()
    local tierNames = {}
    -- Require the Tiers module
    local success, tiersData = pcall(function()
        return require(TiersModule)
    end)

    if success and tiersData then
        -- Loop through setiap tier data
        for _, tierInfo in pairs(tiersData) do
            if tierInfo.Name then
                table.insert(tierNames, tierInfo.Name)
            end
        end
    end

    return tierNames
end

--- Fish List 
local function getFishNames()
    local fishNames = {}

    for _, item in pairs(ItemsModule:GetChildren()) do
        if item:IsA("ModuleScript") then
            local success, moduleData = pcall(function()
                return require(item)
            end)

            if success and moduleData then
                -- Check apakah Type = "Fishes"
                if moduleData.Data and moduleData.Data.Type == "Fishes" then
                    -- Ambil nama dari Data.Name (bukan nama ModuleScript)
                    if moduleData.Data.Name then
                        table.insert(fishNames, moduleData.Data.Name)
                    end
                end
            end
        end
    end

    table.sort(fishNames)
    return fishNames
end

--- Fish Name KHUSUS TRADE
local function getFishNamesForTrade()
    local fishNames = {}
    local itemsModule = ReplicatedStorage:FindFirstChild("Items")
    if not itemsModule then
        featureLogger:warn("Items module not found")
        return fishNames
    end

    for _, item in pairs(itemsModule:GetChildren()) do
        if item:IsA("ModuleScript") then
            local success, moduleData = pcall(function()
                return require(item)
            end)

            if success and moduleData then
                -- Check apakah Type = "Fishes"
                if moduleData.Data and moduleData.Data.Type == "Fishes" then
                    -- Ambil nama dari Data.Name (sama seperti di script autosendtrade)
                    if moduleData.Data.Name then
                        table.insert(fishNames, moduleData.Data.Name)
                    end
                end
            end
        end
    end

    table.sort(fishNames)
    return fishNames
end

--- Enchant Stones Names KHUSUS TRADE 
local function getEnchantStonesForTrade()
    local enchantStoneNames = {}
    local itemsModule = ReplicatedStorage:FindFirstChild("Items")
    if not itemsModule then
        featureLogger:warn("Items module not found")
        return enchantStoneNames
    end

    for _, item in pairs(itemsModule:GetChildren()) do
        if item:IsA("ModuleScript") then
            local success, moduleData = pcall(function()
                return require(item)
            end)

            if success and moduleData then
                -- Check apakah Type = "EnchantStones"
                if moduleData.Data and moduleData.Data.Type == "EnchantStones" then
                    -- Ambil nama dari Data.Name
                    if moduleData.Data.Name then
                        table.insert(enchantStoneNames, moduleData.Data.Name)
                    end
                end
            end
        end
    end

    table.sort(enchantStoneNames)
    return enchantStoneNames
end

-- helpers for player lists
local function listPlayers(excludeSelf)
    local me = LocalPlayer and LocalPlayer.Name
    local t = {}
    for _, p in ipairs(Players:GetPlayers()) do
        if not excludeSelf or (me and p.Name ~= me) then
            table.insert(t, p.Name)
        end
    end
    table.sort(t, function(a, b) return a:lower() < b:lower() end)
    return t
end

-- normalize apapun yang dikasih Dropdown (string atau table)
local function normalizeOption(opt)
    if type(opt) == "string" then return opt end
    if type(opt) == "table" then
        return opt.Value or opt.value or opt[1] or opt.Selected or opt.selection
    end
    return nil
end

local function normalizeList(opts)
    local out = {}
    local function push(v)
        if v ~= nil then table.insert(out, tostring(v)) end
    end
    if type(opts) == "string" or type(opts) == "number" then
        push(opts)
    elseif type(opts) == "table" then
        if #opts > 0 then
            for _, v in ipairs(opts) do
                if type(v) == "table" then
                    push(v.Value or v.value or v.Name or v.name or v[1] or v.Selected or v.selection)
                else
                    push(v)
                end
            end
        else
            for k, v in pairs(opts) do
                if type(k) ~= "number" and v then
                    push(k)
                else
                    if type(v) == "table" then
                        push(v.Value or v.value or v.Name or v.name or v[1] or v.Selected or v.selection)
                    else
                        push(v)
                    end
                end
            end
        end
    end
    return out
end

--- HELPER ROD AND BAITS PRICE 
-- Function untuk ambil harga Rod berdasarkan nama
local function getRodPrice(rodName)
    for _, item in pairs(ItemsModule:GetChildren()) do
        if item:IsA("ModuleScript") then
            local success, moduleData = pcall(function()
                return require(item)
            end)

            if success and moduleData and moduleData.Data then
                if moduleData.Data.Type == "Fishing Rods" and moduleData.Data.Name == rodName then
                    return moduleData.Price or 0
                end
            end
        end
    end
    return 0
end

-- Function untuk ambil harga Bait berdasarkan nama ModuleScript
local function getBaitPrice(baitName)
    for _, item in pairs(BaitModule:GetChildren()) do
        if item:IsA("ModuleScript") and item.Name == baitName then
            local success, moduleData = pcall(function()
                return require(item)
            end)

            if success and moduleData then
                if moduleData.Data and moduleData.Data.Type == "Baits" then
                    return moduleData.Price or 0
                end
            end
        end
    end
    return 0
end

-- Function untuk format angka dengan koma
local function formatPrice(price)
    local formatted = tostring(price)
    while true do  
        formatted, k = string.gsub(formatted, "^(-?%d+)(%d%d%d)", '%1,%2')
        if k == 0 then break end
    end
    return formatted
end

-- Function untuk hitung total harga dari array yang dipilih
local function calculateTotalPrice(selectedItems, priceFunction)
    local total = 0
    for _, itemName in ipairs(selectedItems) do
        total = total + priceFunction(itemName)
    end
    return total
end

--- HELPER PRICE
-- Number → "12.3K", "7.5M", "2B", "950"
local function abbreviateNumber(n, maxDecimals)
    if not n then return "0" end
    maxDecimals = (maxDecimals == nil) and 1 or math.max(0, math.min(2, maxDecimals))
    local neg = n < 0
    n = math.abs(n)

    local units = {
        {1e12, "T"},
        {1e9,  "B"},
        {1e6,  "M"},
        {1e3,  "K"},
    }

    for _, u in ipairs(units) do
        local div, suf = u[1], u[2]
        if n >= div then
            local v = n / div
            local fmt = "%." .. tostring(maxDecimals) .. "f"
            local s = string.format(fmt, v):gsub("%.0+$", ""):gsub("%.(%d-)0+$", ".%1")
            return (neg and "-" or "") .. s .. suf
        end
    end

    -- < 1K → tampilkan apa adanya (trim trailing .0)
    local s = string.format("%." .. tostring(maxDecimals) .. "f", n):gsub("%.0+$", ""):gsub("%.(%d-)0+$", ".%1")
    return (neg and "-" or "") .. s
end

--- HELPER CANCEL FISHING
local CancelFishingEvent = game:GetService("ReplicatedStorage")
    .Packages._Index["sleitnick_net@0.2.0"]
    .net["RF/CancelFishingInputs"]

local listRod       = getFishingRodNames()
local weatherName   = getWeatherNames()
local eventNames    = getEventNames()
local rarityName    = getTierNames()
local fishName      = getFishNames()
local enchantName = getEnchantName()

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

--- === HELPERS FOR PLAYER INFO === ---
local function getCaughtValue()
    local leaderstats = LocalPlayer:FindFirstChild("leaderstats")
    if leaderstats then
        local caught = leaderstats:FindFirstChild("Caught")
        if caught and caught:IsA("IntValue") then
            return caught.Value
        end
    end
    return 0 -- Return 0 jika tidak ditemukan
end

local function getRarestValue()
    local leaderstats = LocalPlayer:FindFirstChild("leaderstats")
    if leaderstats then
        local rarest = leaderstats:FindFirstChild("Rarest Fish")
        if rarest and rarest:IsA("StringValue") then
            return rarest.Value
        end
    end
    return 0 -- Return 0 jika tidak ditemukan
end

--- NOCTIS TITLE
local c = Color3.fromRGB(125, 85, 255)
local title = ('<font color="#%s">Noctis</font>'):format(c:ToHex())

-- ===========================
-- SYNCHRONOUS FEATURE MANAGER
-- ===========================
local FeatureManager = {}
FeatureManager.LoadedFeatures = {}
FeatureManager.InitializedFeatures = {}
FeatureManager.TotalFeatures = 0
FeatureManager.LoadedCount = 0
FeatureManager.IsReady = false

local FEATURE_URLS = {
    AutoFish           = "https://raw.githubusercontent.com/c3iv3r/a/refs/heads/main/module/f-pub/autofish.lua",
    AutoSellFish       = "https://raw.githubusercontent.com/c3iv3r/a/refs/heads/main/module/f-pub/autosellfish.lua",
    AutoTeleportIsland = "https://raw.githubusercontent.com/c3iv3r/a/refs/heads/main/module/f-pub/autoteleportisland.lua",
    FishWebhook        = "https://raw.githubusercontent.com/c3iv3r/a/refs/heads/main/module/f-pub/fishwebhook.lua",
    AutoBuyWeather     = "https://raw.githubusercontent.com/c3iv3r/a/refs/heads/main/module/f-pub/autobuyweather.lua",
    AutoBuyBait        = "https://raw.githubusercontent.com/c3iv3r/a/refs/heads/main/module/f-pub/autobuybait.lua",
    AutoBuyRod         = "https://raw.githubusercontent.com/c3iv3r/a/refs/heads/main/module/f-pub/autobuyrod.lua",
    AutoTeleportEvent  = "https://raw.githubusercontent.com/c3iv3r/a/refs/heads/main/module/f-pub/autoteleportevent.lua",
    AutoGearOxyRadar   = "https://raw.githubusercontent.com/c3iv3r/a/refs/heads/main/module/f-pub/autogearoxyradar.lua",
    AntiAfk            = "https://raw.githubusercontent.com/c3iv3r/a/refs/heads/main/module/f-pub/antiafk.lua",
    AutoEnchantRod     = "https://raw.githubusercontent.com/c3iv3r/a/refs/heads/main/module/f-pub/autoenchantrod.lua",
    AutoFavoriteFish   = "https://raw.githubusercontent.com/c3iv3r/a/refs/heads/main/module/f-pub/autofavoritefish.lua",
    AutoTeleportPlayer = "https://raw.githubusercontent.com/c3iv3r/a/refs/heads/main/module/f-pub/autoteleportplayer.lua",
    BoostFPS           = "https://raw.githubusercontent.com/c3iv3r/a/refs/heads/main/module/f-pub/boostfps.lua",
    AutoSendTrade      = "https://raw.githubusercontent.com/c3iv3r/a/refs/heads/main/module/f-pub/autosendtrade.lua",
    AutoAcceptTrade    = "https://raw.githubusercontent.com/c3iv3r/a/refs/heads/main/module/f-pub/autoaccepttrade.lua",
    SavePosition       = "https://raw.githubusercontent.com/c3iv3r/a/refs/heads/main/module/f-pub/saveposition.lua",
    PositionManager    = "https://raw.githubusercontent.com/c3iv3r/a/refs/heads/main/module/f-pub/positionmanager.lua",
    CopyJoinServer     = "https://raw.githubusercontent.com/c3iv3r/a/refs/heads/main/module/f-pub/copyjoinserver.lua",
    AutoReconnect      = "https://raw.githubusercontent.com/c3iv3r/a/refs/heads/main/module/f-pub/autoreconnect.lua",
    AutoReexec         = "https://raw.githubusercontent.com/c3iv3r/a/refs/heads/main/module/f-pub/autoreexec.lua",
    PlayerEsp          = "https://raw.githubusercontent.com/c3iv3r/a/refs/heads/main/module/f-pub/playeresp.lua",
    InfEnchant         = "https://raw.githubusercontent.com/c3iv3r/a/refs/heads/main/module/f-pub/infenchant.lua",
    AutoMythic         = "https://raw.githubusercontent.com/c3iv3r/a/refs/heads/main/module/f-pub/automythic.lua"
}

-- Load single feature synchronously
function FeatureManager:LoadSingleFeature(featureName, url)
    local success, result = pcall(function()
        local code = game:HttpGet(url)
        if not code or code == "" then
            error("Empty response from URL")
        end

        local module = loadstring(code)()
        if type(module) ~= "table" then
            error("Module did not return a table")
        end

        return module
    end)

    if success and result then
        result.__featureName = featureName
        result.__initialized = false
        self.LoadedFeatures[featureName] = result
        self.LoadedCount = self.LoadedCount + 1
        featureLogger:info(string.format("✓ %s loaded (%d/%d)", 
            featureName, self.LoadedCount, self.TotalFeatures))
        return true
    else
        featureLogger:warn(string.format("✗ Failed to load %s: %s", featureName, result or "Unknown error"))
        return false
    end
end

-- Initialize all features at once
function FeatureManager:InitializeAllFeatures()
    featureLogger:info("Starting synchronous feature loading...")

    -- Show loading notification
    if Noctis then
        Noctis:Notify({
            Title = title,
            Description = "Loading script...",
            Duration = 5
        })
    end

    self.TotalFeatures = 0
    for _ in pairs(FEATURE_URLS) do
        self.TotalFeatures = self.TotalFeatures + 1
    end

    local loadOrder = {
        "AntiAfk", "SavePosition", "PositionManager", "AutoReexec", "BoostFPS", "AutoFish", "AutoSellFish", 
        "AutoTeleportIsland", "AutoTeleportPlayer", "AutoTeleportEvent",
        "AutoEnchantRod", "AutoFavoriteFish", "AutoSendTrade", 
        "AutoAcceptTrade", "FishWebhook", "AutoBuyWeather", 
        "AutoBuyBait", "AutoBuyRod", "AutoGearOxyRadar", "CopyJoinServer", "AutoReconnect", "PlayerEsp", "InfEnchant", "AutoMythic"
    }

    local successCount = 0

    -- Load all features synchronously
    for _, featureName in ipairs(loadOrder) do
        local url = FEATURE_URLS[featureName]
        if url and self:LoadSingleFeature(featureName, url) then
            successCount = successCount + 1
        end
        -- Small delay to prevent rate limiting
        wait(0.02)
    end

    self.IsReady = true

    featureLogger:info(string.format("Loading completed: %d/%d features ready", 
        successCount, self.TotalFeatures))

    -- Show completion notification
    if Noctis then
        Noctis:Notify({
            Title = "Features Ready",
            Description = string.format("%d/%d features loaded successfully", successCount, self.TotalFeatures),
            Duration = 3
        })
    end

    return successCount, self.TotalFeatures
end

-- Get feature with controls attachment
function FeatureManager:GetFeature(featureName, controls)
    if not self.IsReady then
        featureLogger:warn("Features not ready yet!")
        return nil
    end

    local feature = self.LoadedFeatures[featureName]
    if not feature then
        featureLogger:warn(string.format("Feature %s not found", featureName))
        return nil
    end

    if controls and not feature.__controlsAttached then
        feature.__controls = controls
        feature.__controlsAttached = true

        if feature.Init and not feature.__initialized then
            local success, err = pcall(feature.Init, feature, controls)
            if success then 
                feature.__initialized = true
                featureLogger:info(string.format("✓ %s initialized", featureName))
            else
                featureLogger:warn(string.format("✗ Init failed for %s: %s", featureName, err))
            end
        end
    end

    return feature
end

-- Simple getter without controls
function FeatureManager:Get(featureName)
    return self.LoadedFeatures[featureName]
end

-- Check if manager is ready
function FeatureManager:IsLoaded()
    return self.IsReady
end

-- Get loading status
function FeatureManager:GetStatus()
    return {
        isReady = self.IsReady,
        loaded = self.LoadedCount,
        total = self.TotalFeatures,
        features = {}
    }
end

-- Initialize the manager (call this early in your script)
local loadedCount, totalCount = FeatureManager:InitializeAllFeatures()

--- === WINDOW === ---
local Window = Noctis:CreateWindow({
    Title         = "<b>Noctis</b>",
    Footer        = "Fish It | v0.1.5",
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
    "[+] Added Auto Mythic"
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
                        Noctis:Notify({ Title = title, Description = "Disord link copied!", Duration = 2 })
                    else
                        Noctis:Notify({ Title = title, Description = "Clipboard not available", Duration = 3 })
                    end
                end
})

--- PLAYER STATS
local PlayerStatBox = TabHome:AddRightGroupbox("<b>Player Stats</b>", "circle-user-round")
local CaughtLabel = PlayerStatBox:AddLabel("Caught:")
local RarestLabel = PlayerStatBox:AddLabel("Rarest Fish:")
local playerinvent = PlayerStatBox:AddLabel("Inventory")
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
    local currentValue = getCaughtValue()
    CaughtLabel:SetText("Caught: " .. currentValue)
end

-- Connect ke perubahan Value di Caught IntValue
local function connectToValueChanges()
    local leaderstats = LocalPlayer:FindFirstChild("leaderstats")
    if leaderstats then
        local caught = leaderstats:FindFirstChild("Caught")
        if caught and caught:IsA("IntValue") then
            -- Update label setiap kali Value berubah
            caught:GetPropertyChangedSignal("Value"):Connect(updateCaughtLabel)
        end
    end
end

local function updateRarestLabel()
    local currentValue = getRarestValue()
    RarestLabel:SetText("Rarest Fish: " .. currentValue)
end

local function connectToRarestChanges()
    local leaderstats = LocalPlayer:FindFirstChild("leaderstats")
    if leaderstats then
        local rarest = leaderstats:FindFirstChild("Rarest Fish")
        if rarest and rarest:IsA("StringValue") then
            -- Update label setiap kali Value berubah
            rarest:GetPropertyChangedSignal("Value"):Connect(updateRarestLabel)
        end
    end
end

-- Wait for leaderstats to load dan connect
LocalPlayer:WaitForChild("leaderstats")
connectToValueChanges()
connectToRarestChanges()
-- Update pertama kali
updateCaughtLabel()
updateRarestLabel()

--- === MAIN === ---
--- FISHING
local FishingBox = TabMain:AddLeftGroupbox("<b>Fishing</b>", "fish")
-- Initialize feature FIRST (pindah ke atas)
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

-- Attach controls setelah controls dibuat
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
FishingBox:AddDivider()
local cancellabel = FishingBox:AddLabel("Use this if fishing stuck")
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
    if Value then savePositionFeature:Start() else savePositionFeature:Stop()
     end
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
        selectedEventsArray = Values or {}
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
            if eventteleFeature.SetSelectedEvents then eventteleFeature:SetSelectedEvents(selectedEventsArray) end
            if eventteleFeature.Start then eventteleFeature:Start({ 
                    selectedEvents = selectedEventsArray,
                    hoverHeight    = 12  }) end
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
local eventlabel = EventBox:AddLabel("Prioritize selected Event")

--- INF ENCHANT
local VulnBox = TabMain:AddRightGroupbox("<b>Vuln</b>", "infinite")
local infenchantFeature = FeatureManager:Get("InfEnchant")

local infenchant_tgl = VulnBox:AddToggle("infenchanttgl",{
    Text = "Auto Inf Enchant",  -- More descriptive
    Tooltip = "Farm enchant stones (cancel Uncommon/Rare)",
    Default = false,
    Callback = function(Value)
        if infenchantFeature then
            if Value then
                infenchantFeature:Start()
            else
                infenchantFeature:Stop()
            end
        end
    end
})

if infenchantFeature then
    infenchantFeature.__controls = {
        toggle = infenchant_tgl
    }

    if infenchantFeature.Init and not infenchantFeature.__initialized then
        infenchantFeature:Init()  -- No params needed now
        infenchantFeature.__initialized = true
    end
end

VulnBox:AddDivider()

--- AUTO MYTHIC
local automythicFeature = FeatureManager:Get("AutoMythic")

local automythic_tgl = VulnBox:AddToggle("automythictgl",{
    Text = "Auto Mythic",  -- More descriptive
    Tooltip = "Cancel Fishing until Mythic",
    Default = false,
    Callback = function(Value)
        if automythicFeature then
            if Value then
                automythicFeature:Start()
            else
                automythicFeature:Stop()
            end
        end
    end
})

if automythicFeature then
    automythicFeature.__controls = {
        toggle = automythic_tgl
    }

    if automythicFeature.Init and not automythicFeature.__initialized then
        automythicFeature:Init()  -- No params needed now
        automythicFeature.__initialized = true
    end
end

local vulnlabel = VulnBox:AddLabel("Want to know about<br/>this? Join our Discord.")

--- === BACKPACK === ---
--- FAVFISH
local FavoriteBox = TabBackpack:AddLeftGroupbox("<b>Favorite Fish</b>", "star")
local autoFavFishFeature =  FeatureManager:Get("AutoFavoriteFish")
local selectedTiers = {}
local favfish_ddm = FavoriteBox:AddDropdown("favfishddm", {
    Text                     = "Select Rarity",
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
    Text = "Auto Favorite",
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
          autoOnLimit = true }) end
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
        selectedEnchants = normalizeList(Values or {})  -- <— PENTING
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

local enchantlabel = EnchantBox:AddLabel("Empty atleast 1<br/>Hotbar slot")

--- TRADE
local TradeBox = TabAutomation:AddRightGroupbox("<b>Trade</b>", "gift")
local autoTradeFeature       = FeatureManager:Get("AutoSendTrade")
local autoAcceptTradeFeature = FeatureManager:Get("AutoAcceptTrade")
local selectedTradeItems    = {}
local selectedTradeEnchants = {}
local selectedTargetPlayers = {}

local tradeplayer_dd = TradeBox:AddDropdown("tradeplayerdd", {
    Text                     = "Select Player",
    Values                   = listPlayers(true),
    Searchable               = true,
    MaxVisibileDropdownItems = 6,
    Multi                    = true,
    Callback = function(Value)
        selectedTargetPlayers = normalizeList(Value or {})
        if autoTradeFeature and autoTradeFeature.SetTargetPlayers then
            autoTradeFeature:SetTargetPlayers(selectedTargetPlayers)
        end
    end
})

local tradeitem_ddm = TradeBox:AddDropdown("tradeitemddm", {
    Text                     = "Select Fish",
    Values                   = getFishNamesForTrade(),
    Searchable               = true,
    MaxVisibileDropdownItems = 6,
    Multi = true,
    Callback = function(Values)
        selectedTradeItems = normalizeList(Values or {})
        if autoTradeFeature and autoTradeFeature.SetSelectedFish then
            autoTradeFeature:SetSelectedFish(selectedTradeItems)
        end
    end
})

local tradeenchant_ddm = TradeBox:AddDropdown("tradeenchantddm", {
    Text                     = "Select Enchant Stones",
    Values                   = getEnchantStonesForTrade(),
    Searchable               = true,
    MaxVisibileDropdownItems = 6,
    Multi = true,
    Callback = function(Values)
        selectedTradeEnchants = normalizeList(Values or {})
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
        local names = listPlayers(true)
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
    local total = calculateTotalPrice(selectedRodsSet, getRodPrice)
    if rodPriceLabel then
        rodPriceLabel:SetText("Total Price: " .. abbreviateNumber(total, 1))
    end
end

local shoprod_ddm = RodShopBox:AddDropdown("rodshopddm", {
    Text = "Select Rod",
    Values = listRod,
    Searchable = true,
    MaxVisibileDropdownItems = 6,
    Multi = true,
    Callback = function(Values)

        selectedRodsSet = normalizeList(Values or {})
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
          interDelay = 0.5 }) end
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
local baitName = getBaitNames()
local baitPriceLabel
local selectedBaitsSet = {}
local function updateBaitPriceLabel()
    local total = calculateTotalPrice(selectedBaitsSet, getBaitPrice)
    if baitPriceLabel then
        baitPriceLabel:SetText("Total Price: " .. abbreviateNumber(total, 1))
    end
end

local shopbait_ddm = BaitShopBox:AddDropdown("baitshop", {
    Text = "Select Bait",
    Values = baitName,
    Searchable = true,
    MaxVisibileDropdownItems = 6,
    Multi = true,
    Callback = function(Values)

        selectedBaitsSet = normalizeList(Values or {})
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
          interDelay = 0.5 }) end
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
local weatherFeature          = FeatureManager:Get("AutoBuyWeather")
local selectedWeatherSet      = {} 
local shopweather_ddm = WeatherShopBox:AddDropdown("weathershopddm", {
    Text = "Select Weather",
    Tooltip                  = "",
    Values                   = weatherName,
    Searchable               = true,
    MaxVisibileDropdownItems = 6,
    Multi = true,
    Callback = function(Values)
        selectedWeatherSet = Values or {}
        if weatherFeature and weatherFeature.SetWeathers then
           weatherFeature:SetWeathers(selectedWeatherSet)
        end
    end
})
local maxbuyweather = WeatherShopBox:AddLabel("Max 3")
local shopweather_tgl = WeatherShopBox:AddToggle("weathershoptgl",{
    Text = "Auto Buy Weather",
    Tooltip = "",
    Default = false,
    Callback = function(Value)
    if Value and weatherFeature then
            if weatherFeature.SetWeathers then weatherFeature:SetWeathers(selectedWeatherSet) end
            if weatherFeature.Start then weatherFeature:Start({ 
          weatherList = selectedWeatherSet }) end
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

--- === TAB TELEPORT === ---
--- ISLAND
local IslandBox = TabTeleport:AddLeftGroupbox("<b>Island</b>", "map")
local autoTeleIslandFeature = FeatureManager:Get("AutoTeleportIsland")
local currentIsland = "Fisherman Island"
local teleisland_dd = IslandBox:AddDropdown("teleislanddd", {
    Text                    = "Select Island",
    Tooltip                 = "",
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
    Searchable               = true,
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
    Text                     = "Select Player",
    Tooltip                  = "",
    Values                   = listPlayers(true),
    Searchable               = true,
    MaxVisibileDropdownItems = 6,
    Multi = false,
    Callback = function(Value)
        local name = normalizeOption(Value)
        currentPlayerName = name
        if teleplayerFeature and teleplayerFeature.SetTarget then
            teleplayerFeature:SetTarget(name)
        end
        -- optional: debug
         mainLogger:info("[teleplayer] selected:", name, typeof(option))
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
        local names = listPlayers(true)
        if teleplayer_dd.Refresh then teleplayer_dd:SetValue(names) end -- FIX: correct var
        Noctis:Notify({ Title = "Players", Description = ("Online: %d"):format(#names), Duration = 2 })
    end
})

if teleplayerFeature then
    teleplayerFeature.__controls = {
        dropdown       = teleplayer_dd,
        refreshButton  = teleplayerrefresh_btn,
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
            -- Clear input setelah berhasil
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
        -- Value akan digunakan saat user klik teleport button
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
                Description = "Position" .. selectedPos .. "' deleted",
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
    Text                     = "Select Rarity",
    Tooltip                  = "",
    Values                   = rarityName,
    Searchable               = true,
    MaxVisibileDropdownItems = 6,
    Multi = true,
    Callback = function(Values)
        selectedWebhookFishTypes = normalizeList(Values or {})
        print("[DEBUG] Dropdown callback - selectedWebhookFishTypes:", table.concat(selectedWebhookFishTypes, ", "))

        -- FIXED: Use the correct method name
        if fishWebhookFeature and fishWebhookFeature.SetSelectedFishTypes then
            fishWebhookFeature:SetSelectedFishTypes(selectedWebhookFishTypes)
        end

        -- Also call the other method name for compatibility
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

            -- FIXED: Set selected tiers using both methods for compatibility
            if fishWebhookFeature.SetSelectedFishTypes then 
                fishWebhookFeature:SetSelectedFishTypes(selectedWebhookFishTypes) 
            end
            if fishWebhookFeature.SetSelectedTiers then 
                fishWebhookFeature:SetSelectedTiers(selectedWebhookFishTypes) 
            end

            if fishWebhookFeature.Start then 
                -- FIXED: Use both parameter names for compatibility
                fishWebhookFeature:Start({ 
                    webhookUrl = currentWebhookUrl,
                    selectedTiers = selectedWebhookFishTypes,    -- Main parameter name
                    selectedFishTypes = selectedWebhookFishTypes -- Backup parameter name
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
local serverjoin_btn = serverjoin_btn:AddButton({
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

-- Pattern yang sama seperti feature lain di GUI kamu
if autoReconnectFeature then
    autoReconnectFeature.__controls = {
        toggle = reconnect_tgl
    }

    -- FIX: Init dengan parameter yang benar
    if autoReconnectFeature.Init and not autoReconnectFeature.__initialized then
        autoReconnectFeature:Init()  -- Simple version tanpa parameter
        -- Atau kalau mau kasih options: autoReconnectFeature:Init({maxRetries = 2})
        autoReconnectFeature.__initialized = true
    end
end
--- AUTO REEXECUTE
local autoReexec = FeatureManager:Get("AutoReexec")
if autoReexec and autoReexec.Init and not autoReexec.__initialized then
    autoReexec:Init({
        mode = "url",  -- atau "code"
        url  = "https://raw.githubusercontent.com/hailazra/Public/refs/heads/main/fishit.lua",
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
        autoGearFeature:Start()      -- init & konfigurasi default
    end
      -- nyalakan oxygen tank
    if autoGearFeature and autoGearFeature.EnableOxygen then
      autoGearFeature:EnableOxygen(true)
    end
  else
    -- matikan oxygen tank
    if autoGearFeature and autoGearFeature.EnableOxygen then
      autoGearFeature:EnableOxygen(false)
    end
  end
  -- hentikan modul jika kedua toggle mati
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
            -- Ketika toggle ON
            if antiafkFeature and antiafkFeature.Start then
                antiafkFeature:Start()
            end
        else
            -- Ketika toggle OFF
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

OtherBox:AddDivider()
--- BOOST FPS
local boostFPSFeature = FeatureManager:Get("BoostFPS")

-- Tambahkan tombol BoostFPS
local boostfps_btn = OtherBox:AddButton({
    Text = "Boost FPS",
    Func = function()
        if boostFPSFeature and boostFPSFeature.Start then
            -- Jalankan fitur
            boostFPSFeature:Start()

            -- Tampilkan notifikasi
            Noctis:Notify({
                Title = title,
                Description = "FPS Boost has been activated!",
                Duration = 3
            })
        end
    end
})

-- Initialize feature dengan controls
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