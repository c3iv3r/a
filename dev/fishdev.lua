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
local Helpers = loadstring(game:HttpGet("https://raw.githubusercontent.com/c3iv3r/a/refs/heads/main/module/f/helpers.lua"))()

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
--[[_G.InventoryWatcher = nil
pcall(function()
    _G.InventoryWatcher = loadstring(game:HttpGet("https://raw.githubusercontent.com/c3iv3r/a/refs/heads/main/utils/fishit/inventdetect3.lua"))()
end)]]

_G.SpamFishingActive = false

-- Spawn loop langsung
task.spawn(function()
    while task.wait(0.1) do
        if _G.SpamFishingActive and _G.NetPath then
            pcall(function()
                _G.NetPath["RE/FishingCompleted"]:FireServer()
            end)
        end
    end
end)

-- Cache helper results
local listRod = Helpers.getFishingRodNames()
local weatherName = Helpers.getWeatherNames()
local eventNames = Helpers.getEventNames()
local rarityName = Helpers.getTierNames()
local fishName = Helpers.getFishNames()
local enchantName = Helpers.getEnchantName()

local CancelFishingEvent = ReplicatedStorage.Packages._Index["sleitnick_net@0.2.0"].net["RF/CancelFishingInputs"]



-- ===========================
-- INITIALIZE FEATURE MANAGER
-- ===========================
mainLogger:info("Initializing features synchronously...")
local loadedCount, totalCount = FeatureManager:InitializeAllFeatures(Noctis, featureLogger)
mainLogger:info(string.format("Features ready: %d/%d", loadedCount, totalCount))

local function gradient(text, startColor, endColor)
    -- Default colors kalo ga dikasih
    startColor = startColor or Color3.fromRGB(0, 255, 255)    -- Cyan
endColor = endColor or Color3.fromRGB(0, 200, 200)        -- Teal


    
    local parts = {}
    local visibleChars = {}
    local i = 1
    
    -- Extract tags dan characters
    while i <= #text do
        if text:sub(i, i) == '<' then
            local closePos = text:find('>', i)
            if closePos then
                table.insert(parts, {type = "tag", content = text:sub(i, closePos)})
                i = closePos + 1
            else
                table.insert(visibleChars, text:sub(i, i))
                i = i + 1
            end
        else
            table.insert(visibleChars, text:sub(i, i))
            i = i + 1
        end
    end
    
    -- Apply gradient ke visible chars
    local coloredChars = {}
    for idx, char in ipairs(visibleChars) do
        local t = (#visibleChars == 1) and 0 or ((idx - 1) / (#visibleChars - 1))
        local r = math.floor((startColor.R + (endColor.R - startColor.R) * t) * 255)
        local g = math.floor((startColor.G + (endColor.G - startColor.G) * t) * 255)
        local b = math.floor((startColor.B + (endColor.B - startColor.B) * t) * 255)
        table.insert(coloredChars, string.format('<font color="rgb(%d,%d,%d)">%s</font>', r, g, b, char))
    end
    
    -- Rebuild string
    local result = ""
    local charIdx = 1
    i = 1
    while i <= #text do
        if text:sub(i, i) == '<' then
            local closePos = text:find('>', i)
            if closePos then
                result = result .. text:sub(i, closePos)
                i = closePos + 1
            else
                result = result .. (coloredChars[charIdx] or text:sub(i, i))
                charIdx = charIdx + 1
                i = i + 1
            end
        else
            result = result .. (coloredChars[charIdx] or "")
            charIdx = charIdx + 1
            i = i + 1
        end
    end
    
    return result
end

local Window = Noctis:Window({
	Title = "Noctis",
	Subtitle = "Fish It | v1.0.9",
	Size = UDim2.fromOffset(600, 300),
	DragStyle = 1,
	DisabledWindowControls = {},
	OpenButtonImage = "rbxassetid://123156553209294", 
	OpenButtonSize = UDim2.fromOffset(32, 32),
	OpenButtonPosition = UDim2.fromScale(0.45, 0.1),
	Keybind = Enum.KeyCode.RightControl,
	AcrylicBlur = true,
})

FeatureManager:InitAll(Window, Logger)
local F = FeatureManager:CreateProxy(Window, Logger)

--- === TAB === ---
local Group      = Window:TabGroup()
local Home       = Group:Tab({ Title = "Home", Image = "house"})
local Main       = Group:Tab({ Title = "Main", Image = "gamepad"})
local Backpack   = Group:Tab({ Title = "Backpack", Image = "backpack"})
local Automation = Group:Tab({ Title = "Automation", Image = "workflow"})
local Shop       = Group:Tab({ Title = "Shop", Image = "shopping-bag"})
local Teleport  = Group:Tab({ Title = "Teleport", Image = "map"})
local Misc       = Group:Tab({ Title = "Misc", Image = "cog"})
local Setting    = Group:Tab({ Title = "Settings", Image = "settings"})

--- === CHANGELOG & DISCORD LINK === ---
local CHANGELOG = table.concat({
    "[+] Added Hide Nickname",
    "[+] Added Auto Finish Fishing",
    "[/] Fixed Auto Send Trade",
    "[/] Fixed Player List",
    "[/] Changed Quest Progress Info, refresh every 60 seconds",
    "[/] Improved Auto Favorite, now support Mutation + Rarity or etc",
    "[/] Fixed & Improved Balatant"
}, "\n")
local DISCORD = table.concat({
    "https://discord.gg/3AzvRJFT3M",
}, "\n")

--- === HOME === ---
--- === INFORMATION === ---
local Information = Home:Section({ Title = "Home", Opened = true })
Information:Paragraph({
	Title = gradient("<b>Information</b>"),
	Desc = CHANGELOG
})
Information:Button({
	Title = "<b>Join Discord</b>",
	Callback = function()
		if typeof(setclipboard) == "function" then
            setclipboard(DISCORD)
            Window:Notify({ Title = "Noctis", Desc = "Discord link copied!", Duration = 2 })
        else
            Window:Notify({ Title = "Noctis", Desc = "Clipboard not available", Duration = 3 })
        end
    end
})
Information:Divider()
--[[local PlayerInfoParagraph = Information:Paragraph({
	Title = gradient("<b>Player Stats</b>"),
	Desc = ""
})
local inventoryWatcher = _G.InventoryWatcher and _G.InventoryWatcher.getShared()

-- Variabel untuk nyimpen nilai-nilai
local caughtValue = "0"
local rarestValue = "-"
local fishesCount = "0"
local itemsCount = "0"

-- ✅ Throttle config
local THROTTLE_INTERVAL = 3  -- Update UI setiap 0.5 detik
local lastUpdateTime = 0
local pendingUpdate = false

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

-- ✅ Throttled update (schedule max 1x per interval)
local function scheduleUpdate()
    if pendingUpdate then return end
    
    local now = os.clock()
    local timeSinceLastUpdate = now - lastUpdateTime
    
    if timeSinceLastUpdate >= THROTTLE_INTERVAL then
        -- Update immediately
        updatePlayerInfoDesc()
        lastUpdateTime = now
    else
        -- Schedule untuk nanti
        pendingUpdate = true
        local delay = THROTTLE_INTERVAL - timeSinceLastUpdate
        
        task.delay(delay, function()
            updatePlayerInfoDesc()
            lastUpdateTime = os.clock()
            pendingUpdate = false
        end)
    end
end

-- Update inventory counts (throttled)
if inventoryWatcher then
    inventoryWatcher:onReady(function()
        local function updateInventory()
            local counts = inventoryWatcher:getCountsByType()
            fishesCount = tostring(counts["Fishes"] or 0)
            itemsCount = tostring(counts["Items"] or 0)
            scheduleUpdate()  -- ✅ Throttled
        end
        updateInventory()
        inventoryWatcher:onChanged(updateInventory)
    end)
end

-- Update caught value (throttled)
local function updateCaught()
    caughtValue = tostring(Helpers.getCaughtValue())
    scheduleUpdate()  -- ✅ Throttled
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

-- Update rarest value (throttled)
local function updateRarest()
    rarestValue = tostring(Helpers.getRarestValue())
    scheduleUpdate()  -- ✅ Throttled
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
updateRarest()]]

--- === MAIN === ---
--- === FISHING === ---
local FishingSection = Main:Section({ Title = "Fishing", Opened = false })

-- State tracking
local currentMethod = "V1" -- default
local isAutoFishActive = false

-- Balatant V5 delay configs
local balatantWaitWindow = 0.6         -- Default 600ms (ReplicateText check window)
local balatantSafetyTimeout = 3        -- Default 3s (Safety net timeout)
local balatantBaitSpawnedDelay = 0

-- Function untuk stop semua
local function stopAllAutoFish()
    if F.AutoFish and F.AutoFish.Stop then
        F.AutoFish:Stop()
    end
    if F.AutoFishV2 and F.AutoFishV2.Stop then
        F.AutoFishV2:Stop()
    end
    if F.AutoFishV3 and F.AutoFishV3.Stop then
        F.AutoFishV3:Stop()
    end
    if F.Balatant and F.Balatant.Stop then
        F.Balatant:Stop()
    end
    if F.BalatantV2 and F.BalatantV2.Stop then
        F.BalatantV2:Stop()
    end
end

-- Function untuk start sesuai method
local function startAutoFish(method)
    stopAllAutoFish() -- stop dulu yang lain
    
    if method == "V1" and F.AutoFish and F.AutoFish.Start then
        F.AutoFish:Start({ mode = "Fast" })
    elseif method == "V2" and F.AutoFishV2 and F.AutoFishV2.Start then
        F.AutoFishV2:Start({ mode = "Fast" })
    elseif method == "V3" and F.AutoFishV3 and F.AutoFishV3.Start then
        F.AutoFishV3:Start({ mode = "Fast" })
    elseif method == "Balatant" and F.Balatant and F.Balatant.Start then
        F.Balatant:Start({
            mode = "Fast",
            waitWindow = balatantWaitWindow,
            safetyTimeout = balatantSafetyTimeout,
            baitSpawnedDelay = balatantBaitSpawnedDelay
        })
    elseif method == "Balatant V2" and F.BalatantV2 and F.BalatantV2.Start then
        F.BalatantV2:Start({ mode = "Fast" })
    end
end

FishingSection:Label({ Title = "<b>Fishing Mode</b>"})

local autofish_dd = FishingSection:Dropdown({
    Title = "<b>Select Mode</b>",
    Search = true,
    Multi = false,
    Required = false,
    Options = {"Balatant (Delay)", "Balatant (Old)", "Fast", "Stable", "Normal"},
    Default = "Fast",
    Callback = function(v)
        -- Map dropdown value ke method
        if v == "Fast" then
            currentMethod = "V1"
        elseif v == "Stable" then
            currentMethod = "V2"
        elseif v == "Normal" then
            currentMethod = "V3"
        elseif v == "Balatant (Delay)" then
            currentMethod = "Balatant"
        elseif v == "Balatant (Old)" then 
            currentMethod = "Balatant V2"
        end
        
        -- Kalo lagi aktif, restart dengan method baru
        if isAutoFishActive then
            startAutoFish(currentMethod)
        end
    end
}, "autofishdd")

-- Detection Window Input (WAIT_WINDOW)
local baitdelay_in = FishingSection:Input({
    Name = "<b>Detection Window</b>",
    Placeholder = "e.g 0.6 (seconds)",
    AcceptedCharacters = "Numbers",
    Callback = function(v)
        local n = tonumber(v)
        if n and n >= 0.05 and n <= 5 then
            balatantWaitWindow = n
            
            -- Update runtime kalo Balatant lagi jalan
            if isAutoFishActive and currentMethod == "Balatant" and F.Balatant then
                F.Balatant:SetDelays(balatantWaitWindow, nil)
            end
        end
    end
}, "baitdelayin")

-- Cast Delay Input (SAFETY_TIMEOUT)
local chargedelay_in = FishingSection:Input({
    Name = "<b>Cast Delay</b>",
    Placeholder = "e.g 3 (seconds)",
    AcceptedCharacters = "Numbers",
    Callback = function(v)
        local n = tonumber(v)
        if n and n >= 1 and n <= 30 then
            balatantSafetyTimeout = n
            
            -- Update runtime kalo Balatant lagi jalan
            if isAutoFishActive and currentMethod == "Balatant" and F.Balatant then
                F.Balatant:SetDelays(nil, balatantSafetyTimeout)
            end
        end
    end
}, "chargedelayin")

local autofish_tgl = FishingSection:Toggle({
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

local autofinish_tgl = FishingSection:Toggle({
    Title = "<b>Auto Finish Fishing</b>",
    Default = false,
    Callback = function(v)
        _G.SpamFishingActive = v
    end
}, "autofinishtgl")
        

local noanim_tgl = FishingSection:Toggle({
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

local autofixfish_tgl = FishingSection:Toggle({
	Title = "<b>Auto Fix Fishing</b>",
	Default = false,
	Callback = function(v)
        if v then
            F.AutoFixFishing:Start()
        else
            F.AutoFixFishing:Stop()
        end
    end
}, "autofixfishtgl")

FishingSection:Button({
	Title = "<b>Cancel Fishing</b>",
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

local savepos_tgl = FishingSection:Toggle({
	Title = "<b>Save Current Position</b>",
	Default = false,
	Callback = function(v)
        if v then F.SavePosition:Start() else F.SavePosition:Stop() end
    end
}, "savepostgl")

--- === EVENT === ---
local EventSection = Main:Section({ Title = "Event", Opened = false })
local selectedEventsArray = {}
local eventtele_ddm = EventSection:Dropdown({
    Title = "<b>Select Event</b>",
    Search = true,
    Multi = true,
    Required = false,
    Values = eventNames,
    Callback = function(v)
        selectedEventsArray = Helpers.normalizeList(v or {})   
        if F.AutoTeleportEvent and F.AutoTeleportEvent.SetSelectedEvents then
            F.AutoTeleportEvent:SetSelectedEvents(selectedEventsArray)
        end
    end
}, "eventteleddm")

local eventtele_tgl = EventSection:Toggle({
	Title = "<b>Auto Teleport Event</b>",
	Default = false,
	Callback = function(v)
        if v and F.AutoTeleportEvent then
            local arr = Helpers.normalizeList(selectedEventsArray or {})
            if F.AutoTeleportEvent.SetSelectedEvents then F.AutoTeleportEvent:SetSelectedEvents(arr) end
            if F.AutoTeleportEvent.Start then
                F.AutoTeleportEvent:Start({ selectedEvents = arr, hoverHeight = 12 })
            end
        elseif F.AutoTeleportEvent and F.AutoTeleportEvent.Stop then
            F.AutoTeleportEvent:Stop()
        end
    end
}, "eventteletgl")

--- === BOAT === ---
--[[local BoatSection = Main:Section({ Title = "Boat", Opened = false })
local boat_dd = BoatSection:Dropdown({
    Title = "<b>Select Boat</b>",
    Search = true,
    Multi = false,
    Required = false,
    Values = Helpers.getBoatNames(),
    Callback = function(v)
    local boatName = Helpers.normalizeOption(v)
    if boatName then
        local boatId = Helpers.getBoatIdByName(boatName)
        if boatId then
            F.Boat:SetSelectedBoat(boatId)
        end
    end
end
}, "boatdd")

BoatSection:Button({
	Title = "<b>Spawn Boat</b>",
	Callback = function()
     F.Boat:SpawnBoat()
    end
})

BoatSection:Button({
	Title = "<b>Despawn Boat</b>",
	Callback = function()
     F.Boat:DespawnBoat()
    end
})]]

--- ==== LOCALPLAYER === ---
local LocalPlayerSection = Main:Section({ Title = "LocalPlayer", Opened = false})
local infjump_tgl = LocalPlayerSection:Toggle({
	Title = "<b>Inf Jump</b>",
	Default = false,
	Callback = function(v)
        if v then
                F.PlayerModif:EnableInfJump()
            else
                F.PlayerModif:DisableInfJump()
         end
    end
}, "infjumptgl")

local fly_tgl = LocalPlayerSection:Toggle({
	Title = "<b>Fly</b>",
	Default = false,
	Callback = function(v)
        if v then
                F.PlayerModif:EnableFly()
            else
                F.PlayerModif:DisableFly()
         end
    end
}, "flytgl")

local noclip_tgl = LocalPlayerSection:Toggle({
	Title = "<b>No Clip</b>",
	Default = false,
	Callback = function(v)
    end
}, "nocliptgl")

local walkspeed_sldr = LocalPlayerSection:Slider({
		Title = "Walkspeed",
		Default = 20,
		Minimum = 0,
		Maximum = 100,
		DisplayMethod = "Value",
		Precision = 0,
		Callback = function(v)
			F.PlayerModif:SetWalkSpeed(v)
        end
}, "walkspeedsldr")

--- === BACKPACK === ---
local FavoriteSection = Backpack:Section({ Title = "Favorite", Opened = false })

local isFavActive = false
local selectedRarities = {}
local selectedFishNames = {}
local selectedMutations = {}

FavoriteSection:Label({ Title = "<b>Tip: You can combine filters! (e.g., Rarity + Mutation, Name + Mutation, or all three)</b>"})

local favrarity_ddm = FavoriteSection:Dropdown({
    Title = "<b>Favorite by Rarity</b>",
    Search = true,
    Multi = true,
    Required = false,
    Values = rarityName,
    Callback = function(v)
        selectedRarities = Helpers.normalizeList(v or {})
        
        if isFavActive and F.AutoFavorite and F.AutoFavorite.SetTiers then
            F.AutoFavorite:SetTiers(selectedRarities)
        end
    end
}, "favrarityddm")

FavoriteSection:Divider()

local favfishname_ddm = FavoriteSection:Dropdown({
    Title = "<b>Favorite by Fish Name</b>",
    Search = true,
    Multi = true,
    Required = false,
    Values = fishName,
    Callback = function(v)
        selectedFishNames = Helpers.normalizeList(v or {})
        
        if isFavActive and F.AutoFavorite and F.AutoFavorite.SetFishNames then
            F.AutoFavorite:SetFishNames(selectedFishNames)
        end
    end
}, "favfishnameddm")

FavoriteSection:Divider()

local favfishmutation_ddm = FavoriteSection:Dropdown({
    Title = "<b>Favorite by Fish Mutation</b>",
    Search = true,
    Multi = true,
    Required = false,
    Values = Helpers.getVariantNames(),
    Callback = function(v)
        selectedMutations = Helpers.normalizeList(v or {})
        
        if isFavActive and F.AutoFavorite and F.AutoFavorite.SetVariants then
            F.AutoFavorite:SetVariants(selectedMutations)
        end
    end
}, "favfishmutationddm")

local autofav_tgl = FavoriteSection:Toggle({
    Title = "<b>Auto Favorite</b>",
    Default = false,
    Callback = function(v)
        isFavActive = v
        
        if v then
            if F.AutoFavorite then
                local hasAnyFilter = #selectedRarities > 0 or #selectedFishNames > 0 or #selectedMutations > 0
                
                if not hasAnyFilter then
                    Window:Notify({ 
                        Title = "Auto Favorite", 
                        Desc = "Select at least one filter first!", 
                        Duration = 3 
                    })
                    return
                end
                
                if F.AutoFavorite.SetTiers then
                    F.AutoFavorite:SetTiers(selectedRarities)
                end
                if F.AutoFavorite.SetFishNames then
                    F.AutoFavorite:SetFishNames(selectedFishNames)
                end
                if F.AutoFavorite.SetVariants then
                    F.AutoFavorite:SetVariants(selectedMutations)
                end
                
                if F.AutoFavorite.Start then
                    F.AutoFavorite:Start({
                        tierList = selectedRarities,
                        fishNames = selectedFishNames,
                        variantList = selectedMutations
                    })
                end
                
                local activeFilters = {}
                if #selectedRarities > 0 then table.insert(activeFilters, "Rarity") end
                if #selectedFishNames > 0 then table.insert(activeFilters, "Name") end
                if #selectedMutations > 0 then table.insert(activeFilters, "Mutation") end
                
                Window:Notify({ 
                    Title = "Auto Favorite", 
                    Desc = "Active with: " .. table.concat(activeFilters, " + "), 
                    Duration = 3 
                })
            end
            
        else
            if F.AutoFavorite and F.AutoFavorite.Stop then
                F.AutoFavorite:Stop()
            end
            Window:Notify({ Title = "Auto Favorite", Desc = "Stopped", Duration = 2 })
        end
    end
}, "autofavtgl")

local unfavall_tgl = FavoriteSection:Toggle({
    Title = "<b>Unfavorite All Fish</b>",
    Default = false,
    Callback = function(v)
        if v and F.UnfavoriteAllFish then
            if F.UnfavoriteAllFish.Start then 
                F.UnfavoriteAllFish:Start() 
            end
        elseif F.UnfavoriteAllFish and F.UnfavoriteAllFish.Stop then
            F.UnfavoriteAllFish:Stop()
        end
    end
}, "unfavalltgl")

--- === SELL === ---
local SellSection = Backpack:Section({ Title = "Sell", Opened = false })
local currentSellThreshold   = "Legendary"
local currentSellLimit       = 0
local sellfish_dd = SellSection:Dropdown({
    Title = "<b>Select Rarity</b>",
    Search = true,
    Multi = false,
    Required = false,
    Values = {"Secret", "Mythic", "Legendary"},
    Default = "Legendary",
    Callback = function(v)
        currentSellThreshold = v or {}
        if F.AutoSellFish and F.AutoSellFish.SetMode then
           F.AutoSellFish:SetMode(v)
        end
    end
}, "sellfishdd")

local sellfish_in = SellSection:Input({
	Name = "<b>Input Delay</b>",
	Placeholder = "e.g 60 (seconds)",
	AcceptedCharacters = "All",
	Callback = function(v)
	local n = tonumber(v) or 0
        currentSellLimit = n
        if  F.AutoSellFish and  F.AutoSellFish.SetLimit then
             F.AutoSellFish:SetLimit(n)
        end
    end
}, "sellfishin")

local sellfish_tgl = SellSection:Toggle({
    Title = "<b>Auto Sell Fish</b>",
    Default = false,
    Callback = function(v)
        if v and F.AutoSellFish then
            if F.AutoSellFish.SetMode then F.AutoSellFish:SetMode(currentSellThreshold) end
            if F.AutoSellFish.Start then F.AutoSellFish:Start({ 
                threshold   = currentSellThreshold,
                limit       = currentSellLimit,
                autoOnLimit = true 
            }) end
        elseif F.AutoSellFish and F.AutoSellFish.Stop then
            F.AutoSellFish:Stop()
        end
    end
}, "sellfishtgl")

--- === TRADE === ---
local TradeSection = Backpack:Section({ Title = "Trade", Opened = false })
local selectedTradeItems    = {}
local selectedTradeEnchants = {}
local selectedTargetPlayers = {}

TradeSection:Label({ Title = "<b>Tip: Select ONLY Enchant or Fish, dont use both at same time!</b>"})

local tradeplayer_dd = TradeSection:Dropdown({
    Title = "<b>Select Player</b>",
    Values = Helpers.listPlayers(true, function(list)
        tradeplayer_dd:ClearOptions()
        tradeplayer_dd:SetValues(list)
    end),
    Callback = function(v)
        selectedTargetPlayers = Helpers.normalizeList(v or {})
        if F.AutoSendTrade and F.AutoSendTrade.SetTargetPlayers then
            F.AutoSendTrade:SetTargetPlayers(selectedTargetPlayers)
        end
    end
}, "tradeplayerdd")
TradeSection:Divider()
local tradefish_ddm = TradeSection:Dropdown({
    Title = "<b>Select Fish</b>",
    Search = true,
    Multi = true,
    Required = false,
    Values = Helpers.getFishNamesForTrade(),
    Callback = function(v)
        selectedTradeItems = Helpers.normalizeList(v or {})
        if F.AutoSendTrade and F.AutoSendTrade.SetSelectedFish then
            F.AutoSendTrade:SetSelectedFish(selectedTradeItems)
        end
    end
}, "tradefishddm")
TradeSection:Divider()
local tradeenchant_ddm = TradeSection:Dropdown({
    Title = "<b>Select Enchant</b>",
    Search = true,
    Multi = true,
    Required = false,
    Values = Helpers.getEnchantStonesForTrade(),
    Callback = function(v)
        selectedTradeEnchants = Helpers.normalizeList(v or {})
        if F.AutoSendTrade and F.AutoSendTrade.SetSelectedItems then
            F.AutoSendTrade:SetSelectedItems(selectedTradeEnchants)
        end
    end
}, "tradeenchantddm")

local tradelay_in = TradeSection:Input({
	Name = "<b>Input Delay</b>",
	Placeholder = "e.g 15 (seconds)",
	AcceptedCharacters = "All",
	Callback = function(v)
        local delay = math.max(1, tonumber(v) or 20)
        if F.AutoSendTrade and F.AutoSendTrade.SetTradeDelay then
            F.AutoSendTrade:SetTradeDelay(delay)
        end
    end
}, "tradelayin")

TradeSection:Button({
	Title = "<b>Refresh Player List</b>",
	Callback = function()
        local names = Helpers.listPlayers(true)
        tradeplayer_dd:ClearOptions()
        tradeplayer_dd:SetValues(names)
        Window:Notify({ Title = "Players", Desc = ("Online: %d"):format(#names), Duration = 2 })
    end
})

local tradesend_tgl = TradeSection:Toggle({
    Title = "<b>Auto Send Trade</b>",
    Default = false,
    Callback = function(v)
        if v and F.AutoSendTrade then
            if #selectedTradeItems == 0 and #selectedTradeEnchants == 0 then
                Window:Notify({ Title="Info", Desc ="Select at least 1 fish or enchant stone first", Duration=3 })
                return
            end
            if #selectedTargetPlayers == 0 then
                Window:Notify({ Title="Info", Desc ="Select at least 1 target player", Duration=3 })
                return
            end

            local delay = math.max(1, tonumber(tradelay_in.Value) or 5)
            if F.AutoSendTrade.SetSelectedFish then F.AutoSendTrade:SetSelectedFish(selectedTradeItems) end
            if F.AutoSendTrade.SetSelectedItems then F.AutoSendTrade:SetSelectedItems(selectedTradeEnchants) end
            if F.AutoSendTrade.SetTargetPlayers then F.AutoSendTrade:SetTargetPlayers(selectedTargetPlayers) end
            if F.AutoSendTrade.SetTradeDelay then F.AutoSendTrade:SetTradeDelay(delay) end

            F.AutoSendTrade:Start({
                fishNames  = selectedTradeItems,
                itemNames  = selectedTradeEnchants,
                playerList = selectedTargetPlayers,
                tradeDelay = delay,
            })
        elseif F.AutoSendTrade and F.AutoSendTrade.Stop then
            F.AutoSendTrade:Stop()
        end
    end
}, "tradesendtgl")

local tradeacc_tgl = TradeSection:Toggle({
    Title = "<b>Auto Accept Trade</b>",
    Default = false,
    Callback = function(v)
        if v and F.AutoAcceptTrade and F.AutoAcceptTrade.Start then
            F.AutoAcceptTrade:Start({ 
                ClicksPerSecond = 18,
                EdgePaddingFrac = 0 
            })
        elseif F.AutoAcceptTrade and F.AutoAcceptTrade.Stop then
            F.AutoAcceptTrade:Stop()
        end
    end
}, "tradeacctgl")

--- === AUTOMATION === ---
--- === Enchant === ---
local EnchantSection = Automation:Section({ Title = "Enchant", Opened = false })

-- State tracking untuk enchant
local selectedEnchantsSlot1 = {}
local selectedEnchantsSlot2 = {}
local enchantDelay = 8
local isEnchantActive = false

EnchantSection:Label({ Title = "<b>Tip: Select ONLY slot 1 or slot 2, dont use both at same time!</b>"})

local enchantslot1_ddm = EnchantSection:Dropdown({
    Title = "<b>Enchant Slot 1</b>",
    Search = true,
    Multi = true,
    Required = false,
    Values = enchantName,
    Callback = function(v)
        selectedEnchantsSlot1 = Helpers.normalizeList(v or {})
        
        -- Update config saat jalan (hanya jika slot 1 yang aktif)
        if isEnchantActive and F.AutoEnchantRod and F.AutoEnchantRod.SetDesiredByNames then
            F.AutoEnchantRod:SetDesiredByNames(selectedEnchantsSlot1)
        end
    end
}, "enchantslot1ddm")
EnchantSection:Divider()
-- Dropdown untuk Slot 2 (Second Altar - autoenchantrod2.txt)
local enchantslot2_ddm = EnchantSection:Dropdown({
    Title = "<b>Enchant Slot 2</b>",
    Search = true,
    Multi = true,
    Required = false,
    Values = enchantName,
    Callback = function(v)
        selectedEnchantsSlot2 = Helpers.normalizeList(v or {})
        
        -- Update config saat jalan (hanya jika slot 2 yang aktif)
        if isEnchantActive and F.AutoEnchantRod2 and F.AutoEnchantRod2.SetDesiredByNames then
            F.AutoEnchantRod2:SetDesiredByNames(selectedEnchantsSlot2)
        end
    end
}, "enchantslot2ddm")

-- 1 Toggle untuk aktifkan SALAH SATU slot (prioritas: Slot 1 > Slot 2)
local autoenchant_tgl = EnchantSection:Toggle({
    Title = "<b>Auto Enchant</b>",
    Default = false,
    Callback = function(v)
        isEnchantActive = v
        
        if v then
            -- Stop semua dulu (safety)
            if F.AutoEnchantRod and F.AutoEnchantRod.Stop then
                F.AutoEnchantRod:Stop()
            end
            if F.AutoEnchantRod2 and F.AutoEnchantRod2.Stop then
                F.AutoEnchantRod2:Stop()
            end
            
            -- Logika prioritas: Slot 1 > Slot 2
            if #selectedEnchantsSlot1 > 0 and F.AutoEnchantRod then
                -- START SLOT 1
                if F.AutoEnchantRod.SetDesiredByNames then 
                    F.AutoEnchantRod:SetDesiredByNames(selectedEnchantsSlot1) 
                end
                if F.AutoEnchantRod.Start then
                    F.AutoEnchantRod:Start({
                        delay = enchantDelay,
                        enchantNames = selectedEnchantsSlot1
                    })
                end
                Window:Notify({ Title = "Auto Enchant", Desc = "Slot 1 (Enchant Altar) Active", Duration = 2 })
                
            elseif #selectedEnchantsSlot2 > 0 and F.AutoEnchantRod2 then
                -- START SLOT 2 (hanya jika Slot 1 kosong)
                if F.AutoEnchantRod2.SetDesiredByNames then 
                    F.AutoEnchantRod2:SetDesiredByNames(selectedEnchantsSlot2) 
                end
                if F.AutoEnchantRod2.Start then
                    F.AutoEnchantRod2:Start({
                        delay = enchantDelay,
                        enchantNames = selectedEnchantsSlot2
                    })
                end
                Window:Notify({ Title = "Auto Enchant", Desc = "Slot 2 (Temple Altar) Active", Duration = 2 })
                
            else
                -- Tidak ada enchant yang dipilih
                Window:Notify({ 
                    Title = "Auto Enchant", 
                    Desc = "Select enchants in Slot 1 or Slot 2 first!", 
                    Duration = 3 
                })
                
            end
            
        else
            -- Stop SEMUA
            if F.AutoEnchantRod and F.AutoEnchantRod.Stop then
                F.AutoEnchantRod:Stop()
            end
            if F.AutoEnchantRod2 and F.AutoEnchantRod2.Stop then
                F.AutoEnchantRod2:Stop()
            end
            
            Window:Notify({ Title = "Auto Enchant", Desc = "Stopped", Duration = 2 })
        end
    end
}, "autoenchanttgl")

EnchantSection:Label({ Title = "<b>Tip: Free atleast 2 slot in hotbar for Auto Enchant and Submit SECRET</b>"})

EnchantSection:Divider()
EnchantSection:Label({ Title = "<b>Auto Submit SECRET</b>" })
local selectedSecretFish = {}
local submitsecret_ddm = EnchantSection:Dropdown({
    Title = "<b>Select SECRET Fish</b>",
    Search = true,
    Multi = true,
    Required = false,
    Values = Helpers.getSecretFishNames(),
    Callback = function(v)
        selectedSecretFish = Helpers.normalizeList(v or {})
        if F.AutoSubmitSecret and F.AutoSubmitSecret.SetTargetFishName then
            -- Set first selected fish as target
            if #selectedSecretFish > 0 then
                F.AutoSubmitSecret:SetTargetFishName(selectedSecretFish[1])
            end
        end
    end
}, "submitsecretdm")

local submitsecret_tgl = EnchantSection:Toggle({
    Title = "<b>Auto Submit to Temple Guardian</b>",
    Default = false,
    Callback = function(v)
        if v and F.AutoSubmitSecret then
            if #selectedSecretFish == 0 then
                Window:Notify({ Title="Info", Desc="Select at least 1 SECRET fish", Duration=3 })
                return
            end
            if F.AutoSubmitSecret.SetTargetFishName then
                F.AutoSubmitSecret:SetTargetFishName(selectedSecretFish[1])
            end
            if F.AutoSubmitSecret.Start then
                F.AutoSubmitSecret:Start({
                    fishName = selectedSecretFish[1],
                    delay = 0.5
                })
            end
        elseif F.AutoSubmitSecret and F.AutoSubmitSecret.Stop then
            F.AutoSubmitSecret:Stop()
        end
    end
}, "submitsecrettgl")

--- === QUEST === ---
local QuestSection = Automation:Section({ Title = "Quest", Opened = false })
local deepseainfo = QuestSection:Paragraph({
	Title = gradient("<b>Deep Sea Quest (Ghostfinn)</b>"),
	Desc = Helpers.getDeepSeaQuestProgress()
})

task.spawn(function()
	local progress = Helpers.getDeepSeaQuestProgress()
	deepseainfo:SetDesc(progress)
end)

-- Auto update setiap 5 detik
task.spawn(function()
	while true do
		task.wait(60)
		local progress = Helpers.getDeepSeaQuestProgress()
		deepseainfo:SetDesc(progress)
	end
end)

local deepsea_tgl = QuestSection:Toggle({
    Title = "<b>Auto Quest Deep Sea</b>",
    Default = false,
    Callback = function(v)
         if v then 
            if F.QuestGhostfinn then F.QuestGhostfinn:Start() end
        else
            if F.QuestGhostfinn then F.QuestGhostfinn:Stop() end
        end
    end
}, "deepseatgl")

QuestSection:Divider()

local elementinfo = QuestSection:Paragraph({
	Title = gradient("<b>Element Jungle (Element Rod)</b>"),
	Desc = Helpers.getElemetJungleQuestProgress()
})

task.spawn(function()
	local progress = Helpers.getElemetJungleQuestProgress()
	elementinfo:SetDesc(progress)
end)

-- Auto update setiap 5 detik
task.spawn(function()
	while true do
		task.wait(60)
		local progress = Helpers.getElemetJungleQuestProgress()
		elementinfo:SetDesc(progress)
	end
end)

local elemental_tgl = QuestSection:Toggle({
    Title = "<b>Auto Quest</b>",
    Default = false,
    Callback = function(v)
        if v then 
            if F.QuestElemental then F.QuestElemental:Start() end
        else
            if F.QuestElemental then F.QuestElemental:Stop() end
        end
    end
}, "elementtgl")

--- ==== SHOP === ---
--- === ROD === ---
local RodSection = Shop:Section({ Title = "Rod", Opened = false })
local rodPriceLabel
local selectedRodsSet = {}
local function updateRodPriceLabel()
    local total = Helpers.calculateTotalPrice(selectedRodsSet, Helpers.getRodPrice)
    if rodPriceLabel then
        rodPriceLabel:SetTitle("Total Price: " .. Helpers.abbreviateNumber(total, 1))
    end
end
local shoprod_ddm = RodSection:Dropdown({
    Title = "<b>Select Rod</b>",
    Search = true,
    Multi = true,
    Required = false,
    Values = listRod,
    Callback = function(v)
        selectedRodsSet = Helpers.normalizeList(v or {})
        updateRodPriceLabel()

        if F.AutoBuyRod and F.AutoBuyRod.SetSelectedRodsByName then
            F.AutoBuyRod:SetSelectedRodsByName(selectedRodsSet)
        end
    end
}, "shoproddm")
rodPriceLabel = RodSection:Label({ Title = "Total Price: $0"})
RodSection:Button({
	Title = "<b>Buy Rod</b>",
	Callback = function()
        if F.AutoBuyRod.SetSelectedRodsByName then F.AutoBuyRod:SetSelectedRodsByName(selectedRodsSet) end
        if F.AutoBuyRod.Start then F.AutoBuyRod:Start({ 
            rodList = selectedRodsSet,
            interDelay = 0.5 
        }) end
    end
})

--- === BAIT === ---
local BaitSection = Shop:Section({ Title = "Bait", Opened = false })
local baitName = Helpers.getBaitNames()
local baitPriceLabel
local selectedBaitsSet = {}
local function updateBaitPriceLabel()
    local total = Helpers.calculateTotalPrice(selectedBaitsSet, Helpers.getBaitPrice)
    if baitPriceLabel then
        baitPriceLabel:SetTitle("Total Price: " .. Helpers.abbreviateNumber(total, 1))
    end
end
local shopbait_ddm = BaitSection:Dropdown({
    Title = "<b>Select Bait</b>",
    Search = true,
    Multi = true,
    Required = false,
    Values = baitName,
    Callback = function(v)
        selectedBaitsSet = Helpers.normalizeList(v or {})
        updateBaitPriceLabel()

        if F.AutoBuyBait and F.AutoBuyBait.SetSelectedBaitsByName then
            F.AutoBuyBait:SetSelectedBaitsByName(selectedBaitsSet)
        end
    end
}, "shopbaitdm")

baitPriceLabel = BaitSection:Label({ Title = "Total Price: $0"})

BaitSection:Button({
	Title = "<b>Buy Bait</b>",
	Callback = function()
        if F.AutoBuyBait.SetSelectedBaitsByName then F.AutoBuyBait:SetSelectedBaitsByName(selectedBaitsSet) end
        if F.AutoBuyBait.Start then F.AutoBuyBait:Start({ 
            baitList = selectedBaitsSet,
            interDelay = 0.5 
        }) end
    end
})

--- === WEATHER === ---
local WeatherSection = Shop:Section({ Title = "Weather", Opened = false })
local selectedWeatherSet = {} 
local shopweather_ddm = WeatherSection:Dropdown({
    Title = "<b>Select Weather</b>",
    Search = true,
    Multi = true,
    Required = false,
    Values = weatherName,
    Callback = function(v)
        selectedWeatherSet = v or {}
        if F.AutoBuyWeather and F.AutoBuyWeather.SetWeathers then
           F.AutoBuyWeather:SetWeathers(selectedWeatherSet)
        end
    end
}, "shopweatherdm")

local shopweather_tgl = WeatherSection:Toggle({
    Title = "<b>Auto Buy Weather</b>",
    Default = false,
    Callback = function(v)
    if v and F.AutoBuyWeather then
            if F.AutoBuyWeather.SetWeathers then F.AutoBuyWeather:SetWeathers(selectedWeatherSet) end
            if F.AutoBuyWeather.Start then F.AutoBuyWeather:Start({ 
                weatherList = selectedWeatherSet 
            }) end
        elseif F.AutoBuyWeather and F.AutoBuyWeather.Stop then
            F.AutoBuyWeather:Stop()
        end
    end
}, "shopweathertgl")


--- === MERCHANT === ---
local MerchantSection = Shop:Section({ Title = "Merchant", Opened = false })
local merchantstock = MerchantSection:Paragraph({
	Title = gradient("<b>Merchant Stock</b>"),
	Desc = "CHANGELOG"
})
local merchant_ddm = MerchantSection:Dropdown({
    Title = "<b>Select Item</b>",
    Search = true,
    Multi = true,
    Required = false,
    Values = {"Enchantment Stone", "Mystery Egg", "Treasure Chest", "Golden Rod", "Platinum Rod", "Diamond Rod", "Mythic Rod", "Legendary Rod", "Secret Rod"},
    Callback = function(v)
    end
}, "merchantddm")
MerchantSection:Button({
	Title = "<b>Buy Merchant Item</b>",
	Callback = function()
    end
})

--- ==== TELEPORT ==== ---
--- === ISLAND === ---
local IslandSection = Teleport:Section({ Title = "Island", Opened = false })
local currentIsland = "Fisherman Island"
local teleisland_dd = IslandSection:Dropdown({
    Title = "<b>Select Island</b>",
    Search = true,
    Multi = false,
    Required = false,
    Values = {
        "Fisherman Island",
        "Esoteric Depths",
        "Enchant Altar",
        "Enchant Temple",
        "Ancient Jungle",
        "Kohana",
        "Kohana Volcano",
        "Tropical Grove",
        "Crater Island",
        "Coral Reefs",
        "Sisyphus Statue",
        "Treasure Room",
        "Winter Island",
        "Ice Lake",
        "Weather Machine",
        "Sacred Temple",
        "Underground Cellar",
        "Hallow Bay",
        "Mount Hallow"
    },
       Callback = function(v)
        currentIsland = v or {}
        if F.AutoTeleportIsland and F.AutoTeleportIsland.SetIsland then
           F.AutoTeleportIsland:SetIsland(v)
        end
    end
}, "teleislanddd")

IslandSection:Button({
	Title = "<b>Teleport to Island</b>",
	Callback = function()
    if F.AutoTeleportIsland then
            if F.AutoTeleportIsland.SetIsland then
                F.AutoTeleportIsland:SetIsland(currentIsland)
            end
            if F.AutoTeleportIsland.Teleport then
                F.AutoTeleportIsland:Teleport(currentIsland)
            end
        end
    end
})

--- === PLAYER === ---
local PlayerSection = Teleport:Section({ Title = "Player", Opened = false })
local currentPlayerName = nil
local teleplayer_dd = PlayerSection:Dropdown({
    Title = "<b>Select Player</b>",
    Values = Helpers.listPlayers(true, function(list)
        teleplayer_dd:ClearOptions()
        teleplayer_dd:SetValues(list)
    end),
    Callback = function(v)
        local name = Helpers.normalizeOption(v)
        currentPlayerName = name
        if F.AutoTeleportPlayer and F.AutoTeleportPlayer.SetTarget then
            F.AutoTeleportPlayer:SetTarget(name)
        end
    end
}, "teleplayerdd")

PlayerSection:Button({
	Title = "<b>Teleport to Player</b>",
	Callback = function()
        if F.AutoTeleportPlayer then
            if F.AutoTeleportPlayer.SetTarget then
                F.AutoTeleportPlayer:SetTarget(currentPlayerName)
            end
            if F.AutoTeleportPlayer.Teleport then
                F.AutoTeleportPlayer:Teleport(currentPlayerName)
            end
        end
    end
})

PlayerSection:Button({
	Title = "<b>Refresh Player List</b>",
	Callback = function()
        local names = Helpers.listPlayers(true) 
            teleplayer_dd:ClearOptions()
            teleplayer_dd:SetValues(names)
        Window:Notify({ Title = "Players", Desc = ("Online: %d"):format(#names), Duration = 2 })
    end
})

--- === POSITION === ---
local PositionSection = Teleport:Section({ Title = "Position", Opened = false })
local currentPosName = ""
local currentSelectedPos = ""

local savepos_in = PositionSection:Input({
	Name = "<b>Input Name</b>",
	Placeholder = "e.g Farm",
	AcceptedCharacters = "All",
	Callback = function(v)
		currentPosName = v
	end
}, "saveposin")

PositionSection:Button({
	Title = "<b>Add New Position</b>",
	Callback = function()
		local name = currentPosName
		if not name or name == "" or name == "Position Name" then
			Window:Notify({
				Title = "Position Teleport",
				Desc = "Please enter a valid position name",
				Duration = 3
			})
			return
		end
		local success, message = F.PositionManager:AddPosition(name)
		if success then
			Window:Notify({
				Title = "Position Teleport",
				Desc = "Position '" .. name .. "' added successfully",
				Duration = 2
			})
			currentPosName = ""
			if savepos_in.UpdateText then
				savepos_in:UpdateText("")
			end
			-- auto refresh dropdown setelah add
			local list = F.PositionManager:RefreshDropdown()
            savepos_dd:ClearOptions()
			savepos_dd:SetValues(list)
		else
			Window:Notify({
				Title = "Position Teleport",
				Desc = message or "Failed to add position",
				Duration = 3
			})
		end
	end
})

local savepos_dd = PositionSection:Dropdown({
	Title = "<b>Select Position</b>",
	Search = true,
	Multi = false,
	Required = false,
	Values = {"No Positions"},
	Callback = function(v)
		currentSelectedPos = v
	end
}, "saveposdd")

PositionSection:Button({
	Title = "<b>Delete Selected Position</b>",
	Callback = function()
		local selectedPos = currentSelectedPos
		if not selectedPos or selectedPos == "No Positions" then
			Window:Notify({
				Title = "Position Teleport",
				Desc = "Please select a position to delete",
				Duration = 3
			})
			return
		end
		
		local success, message = F.PositionManager:DeletePosition(selectedPos)
		if success then
			Window:Notify({
				Title = "Position Teleport",
				Desc = "Position '" .. selectedPos .. "' deleted",
				Duration = 2
			})
			-- auto refresh dropdown setelah delete
			local list = F.PositionManager:RefreshDropdown()
            savepos_dd:ClearOptions()
			savepos_dd:SetValues(list)
			currentSelectedPos = ""
		else
			Window:Notify({
				Title = "Position Teleport",
				Desc = message or "Failed to delete position",
				Duration = 3
			})
		end
	end
})

PositionSection:Button({
	Title = "<b>Refresh Position List</b>",
	Callback = function()
		local list = F.PositionManager:RefreshDropdown()
        savepos_dd:ClearOptions()
		savepos_dd:SetValues(list) -- refresh dropdown GUI
		local count = #list
		if list[1] == "No Positions" then count = 0 end
		
		Window:Notify({
			Title = "Position Teleport",
			Desc = count .. " positions found",
			Duration = 2
		})
	end
})

PositionSection:Button({
	Title = "<b>Teleport to Position</b>",
	Callback = function()
		local selectedPos = currentSelectedPos
		if not selectedPos or selectedPos == "No Positions" then
			Window:Notify({
				Title = "Position Teleport",
				Desc = "Please select a position to teleport",
				Duration = 3
			})
			return
		end
		local success, message = F.PositionManager:TeleportToPosition(selectedPos)
		if success then
			Window:Notify({
				Title = "Position Teleport",
				Desc = "Teleported to '" .. selectedPos .. "'",
				Duration = 2
			})
		else
			Window:Notify({
				Title = "Position Teleport",
				Desc = message or "Failed to teleport",
				Duration = 3
			})
		end
	end
})

--- === MISC === ---
--- === VISUAL === ---
local VisualSection = Misc:Section({ Title = "Visual", Opened = false })
-- State variables
local customName = "HouseOfNoctis"  -- Default custom name
local customLevel = "Lv: XXXX"       -- Default custom level
local nameChangerConnection = nil

-- Function untuk change overhead
local function changeOverhead()
    local character = workspace.Characters:FindFirstChild(LocalPlayer.Name)
    if not character then return end
    
    local hrp = character:FindFirstChild("HumanoidRootPart")
    if not hrp then return end
    
    local overhead = hrp:FindFirstChild("Overhead")
    if not overhead then return end
    
    -- Ganti Nama
    local header = overhead:FindFirstChild("Content") and overhead.Content:FindFirstChild("Header")
    if header and header:IsA("TextLabel") then
        header.Text = customName
    end
    
    -- Ganti Level
    local levelLabel = overhead:FindFirstChild("LevelContainer") and overhead.LevelContainer:FindFirstChild("Label")
    if levelLabel and levelLabel:IsA("TextLabel") then
        levelLabel.Text = customLevel
    end
end

-- Function untuk reset ke original
local function resetOverhead()
    local character = workspace.Characters:FindFirstChild(LocalPlayer.Name)
    if not character then return end
    
    local hrp = character:FindFirstChild("HumanoidRootPart")
    if not hrp then return end
    
    local overhead = hrp:FindFirstChild("Overhead")
    if not overhead then return end
    
    -- Reset ke nama asli
    local header = overhead:FindFirstChild("Content") and overhead.Content:FindFirstChild("Header")
    if header and header:IsA("TextLabel") then
        header.Text = LocalPlayer.DisplayName or LocalPlayer.Name
    end
    
    -- Reset ke level asli
    local level = LocalPlayer:FindFirstChild("leaderstats") and LocalPlayer.leaderstats:FindFirstChild("Level")
    if level then
        local levelLabel = overhead:FindFirstChild("LevelContainer") and overhead.LevelContainer:FindFirstChild("Label")
        if levelLabel and levelLabel:IsA("TextLabel") then
            levelLabel.Text = tostring(level.Value)
        end
    end
end

-- Toggle untuk activate name changer
local hidenick_tgl = VisualSection:Toggle({
    Title = "<b>Hide Name & Level</b>",
    Default = false,
    Callback = function(v)
        if v then
            -- Apply custom name/level
            task.wait(0.5)
            changeOverhead()
            
            -- Setup auto-apply on respawn
            if nameChangerConnection then
                nameChangerConnection:Disconnect()
            end
            
            nameChangerConnection = LocalPlayer.CharacterAdded:Connect(function()
                task.wait(2) -- Wait for overhead to load
                changeOverhead()
            end)
        else
            -- Reset to original
            resetOverhead()
            
            -- Disconnect auto-apply
            if nameChangerConnection then
                nameChangerConnection:Disconnect()
                nameChangerConnection = nil
            end
        end
    end
}, "hidenicktgl")

--- === WEBHOOK === ---
local WebhookSection = Misc:Section({ Title = "Webhook", Opened = false })
local currentWebhookUrl = ""
local selectedWebhookFishTypes = {}
local testmessage = "@everyone Webhook URL valid, All Good!"
local webhookfish_in = WebhookSection:Input({
	Name = "<b>Input Webhook URL</b>",
	Placeholder = "e.g https://discord...",
	AcceptedCharacters = "All",
	Callback = function(v)
        currentWebhookUrl = v
        if F.FishWebhook and F.FishWebhook.SetWebhookUrl then
            F.FishWebhook:SetWebhookUrl(v)
        end
    end
}, "webhookfishin")

local webhookfish_ddm = WebhookSection:Dropdown({
    Title = "<b>Select Rarity</b>",
    Search = true,
    Multi = true,
    Required = false,
    Values = rarityName,
    Callback = function(v)
        selectedWebhookFishTypes = Helpers.normalizeList(v or {})
        if F.FishWebhook and F.FishWebhook.SetSelectedFishTypes then
            F.FishWebhook:SetSelectedFishTypes(selectedWebhookFishTypes)
        end
        if F.FishWebhook and F.FishWebhook.SetSelectedTiers then
            F.FishWebhook:SetSelectedTiers(selectedWebhookFishTypes)
        end
    end
}, "webhookfishddm")

local webhookfish_tgl = WebhookSection:Toggle({
    Title = "<b>Enable Webhook</b>",
    Default = false,
    Callback = function(v)
    if v and F.FishWebhook then
            if F.FishWebhook.SetWebhookUrl then 
                F.FishWebhook:SetWebhookUrl(currentWebhookUrl) 
            end
            
            if F.FishWebhook.SetSelectedFishTypes then 
                F.FishWebhook:SetSelectedFishTypes(selectedWebhookFishTypes) 
            end
            if F.FishWebhook.SetSelectedTiers then 
                F.FishWebhook:SetSelectedTiers(selectedWebhookFishTypes) 
            end
            
            if F.FishWebhook.Start then 
                F.FishWebhook:Start({ 
                    webhookUrl = currentWebhookUrl,
                    selectedTiers = selectedWebhookFishTypes,
                    selectedFishTypes = selectedWebhookFishTypes
                }) 
            end
        elseif F.FishWebhook and F.FishWebhook.Stop then
            F.FishWebhook:Stop()
        end
    end
}, "webhookfishtgl")

WebhookSection:Button({
	Title = "<b>Test Webhook</b>",
	Callback = function()
        if F.FishWebhook then F.FishWebhook:TestWebhook(testmessage) end
    end
})

--- === SERVER === ---
--- === JOIN SERVER, RECONNECT, REEXEC === ---
local ServerSection = Misc:Section({ Title = "Server", Opened = false })
local server_in = ServerSection:Input({
	Name = "<b>Input JobId</b>",
	Placeholder = "e.g XXX-XX-XXX",
	AcceptedCharacters = "All",
	Callback = function(v)
        if F.CopyJoinServer then F.CopyJoinServer:SetTargetJobId(v) end
    end
})

ServerSection:Button({
	Title = "<b>Join Server</b>",
	Callback = function()
    if F.CopyJoinServer then
            local jobId = server_in.v
            F.CopyJoinServer:JoinServer(jobId)
        end
    end
})

ServerSection:Button({
	Title = "<b>Copy Current Server JobId</b>",
	Callback = function()
    if F.CopyJoinServer then F.CopyJoinServer:CopyCurrentJobId() end
    end
})

ServerSection:Divider()

local reconnect_tgl = ServerSection:Toggle({
    Title = "<b>Auto Reconnect</b>",
    Default = false,
    Callback = function(v)
        if v then
            F.AutoReconnect:Start()
        else
            F.AutoReconnect:Stop()
        end
    end
}, "reconnecttgl")

local reexec_tgl = ServerSection:Toggle({
    Title = "<b>Re-Execute on Reconnect</b>",
    Default = false,
    Callback = function(v)
        if v then
            local ok, err = pcall(function() F.AutoReexec:Start() end)
            if not ok then warn("[AutoReexec] Start failed:", err) end
        else
            local ok, err = pcall(function() F.AutoReexec:Stop() end)
            if not ok then warn("[AutoReexec] Stop failed:", err) end
        end
    end
}, "reexectgl")

--- === PERFORMANCE === ---
local PerformanceSection = Misc:Section({ Title = "Performance", Opened = false })
--- === BLACK SCREEN === ---
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

local blackscreen_tgl = PerformanceSection:Toggle({
    Title = "<b>Black Screen</b>",
    Default = false,
    Callback = function(v)
        if v then
            EnableBlackScreen()
        else
            DisableBlackScreen()
        end
    end
}, "blackscreen")

--- === BOOST FPS === ---
local boostfps_tgl = PerformanceSection:Toggle({
    Title = "<b>Boost FPS</b>",
    Default = false,
    Callback = function(v)
        if v then
            if F.BoostFPS and F.BoostFPS.Start then
                F.BoostFPS:Start()
            end
        end
    end
}, "boostfpstgl")

--- === OTHER === ---
local OtherSection = Misc:Section({ Title = "Other", Opened = false })
--- === OXYRADAR === ---
local oxygenOn = false
local radarOn  = false
local eqoxygentank_tgl = OtherSection:Toggle({
    Title = "<b>Enable Diving Gear</b>",
    Default = false,
    Callback = function(v)
        oxygenOn = v
        if v then
            if F.AutoGearOxyRadar and F.AutoGearOxyRadar.Start then
                F.AutoGearOxyRadar:Start()
            end
            if F.AutoGearOxyRadar and F.AutoGearOxyRadar.EnableOxygen then
                F.AutoGearOxyRadar:EnableOxygen(true)
            end
        else
            if F.AutoGearOxyRadar and F.AutoGearOxyRadar.EnableOxygen then
                F.AutoGearOxyRadar:EnableOxygen(false)
            end
        end
        if F.AutoGearOxyRadar and (not oxygenOn) and (not radarOn) and F.AutoGearOxyRadar.Stop then
            F.AutoGearOxyRadar:Stop()
        end
    end
}, "oxygentanktgl")

local eqfishradar_tgl = OtherSection:Toggle({
    Title = "<b>Enable Fish Radar</b>",
    Default = false,
    Callback = function(v)
        radarOn = v
        if v then
            if F.AutoGearOxyRadar and F.AutoGearOxyRadar.Start then
                F.AutoGearOxyRadar:Start()
            end
            if F.AutoGearOxyRadar and F.AutoGearOxyRadar.EnableRadar then
                F.AutoGearOxyRadar:EnableRadar(true)
            end
        else
            if F.AutoGearOxyRadar and F.AutoGearOxyRadar.EnableRadar then
                F.AutoGearOxyRadar:EnableRadar(false)
            end
        end
        if F.AutoGearOxyRadar and (not oxygenOn) and (not radarOn) and F.AutoGearOxyRadar.Stop then
            F.AutoGearOxyRadar:Stop()
        end
    end
}, "fishradartgl")

--- === PLAYER ESP === ---
local playeresp_tgl = OtherSection:Toggle({
    Title = "<b>Player ESP</b>",
    Default = false,
    Callback = function(v)
        if v then F.PlayerEsp:Start() else F.PlayerEsp:Stop() 
       end
end
}, "playeresptgl")

--- === SETTING === ---
local UISection = Setting:Section({ Title = "UI Setting", Opened = false })
local acrylic_tgl = UISection:Toggle({
    Title = "Acrylic",
    Default = true,
    Callback = function(bool)
       Window:SetAcrylicBlurState(bool)
   end
}, "acrylictgl")
Setting:InsertConfigSection()
Home:Select()
Noctis:LoadAutoLoadConfig()

if F.AntiAfk and F.AntiAfk.Start then
                F.AntiAfk:Start()
end

task.defer(function()
    task.wait(0.1)
    Window:Notify({
        Title = "Noctis",
        Desc = "Enjoy! Join Our Discord!",
        Duration = 3
    })
end)