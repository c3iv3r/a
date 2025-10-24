-- autofavoritefishunified.lua - Unified auto-favorite module (Tier + Name + Variant kombinasi)
local AutoFavoriteFish = {}
AutoFavoriteFish.__index = AutoFavoriteFish

local logger = _G.Logger and _G.Logger.new("AutoFavoriteFishAll") or {
    debug = function() end, info = function() end, warn = function() end, error = function() end
}

local RS = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local FishWatcher = loadstring(game:HttpGet("https://raw.githubusercontent.com/c3iv3r/a/refs/heads/main/utils/fishit/fishwatcherori.lua"))()

local running = false
local hbConn = nil
local fishWatcher = nil

-- Active filters (bisa multiple aktif bersamaan)
local activeFilters = {
    tier = false,
    name = false,
    variant = false
}

local selectedTiers = {}
local selectedNames = {}
local selectedVariants = {}

local FAVORITE_DELAY = 0.3
local FAVORITE_COOLDOWN = 2.0

-- Data caches
local fishDataCache = {}
local tierDataCache = {}
local variantDataCache = {}
local variantIdToName = {}

-- Queue & tracking
local lastFavoriteTime = 0
local favoriteQueue = {}
local pendingFavorites = {}
local favoriteRemote = nil

-- ========== DATA LOADING ==========

local function loadTierData()
    local success, tierModule = pcall(function()
        return RS:WaitForChild("Tiers", 5)
    end)
    
    if not success or not tierModule then
        logger:warn("Failed to find Tiers module")
        return false
    end
    
    local success2, tierList = pcall(function()
        return require(tierModule)
    end)
    
    if not success2 or not tierList then
        logger:warn("Failed to load Tiers data")
        return false
    end
    
    for _, tierInfo in ipairs(tierList) do
        tierDataCache[tierInfo.Tier] = tierInfo
    end
    
    return true
end

local function scanFishData()
    local itemsFolder = RS:FindFirstChild("Items")
    if not itemsFolder then
        logger:warn("Items folder not found")
        return false
    end
    
    local function scanRecursive(folder)
        for _, child in ipairs(folder:GetChildren()) do
            if child:IsA("ModuleScript") then
                local success, data = pcall(function()
                    return require(child)
                end)
                
                if success and data and data.Data then
                    local fishData = data.Data
                    if fishData.Type == "Fishes" and fishData.Id then
                        fishDataCache[fishData.Id] = fishData
                    end
                end
            elseif child:IsA("Folder") then
                scanRecursive(child)
            end
        end
    end
    
    scanRecursive(itemsFolder)
    return next(fishDataCache) ~= nil
end

local function loadVariantData()
    local VariantsFolder = RS:FindFirstChild("Variants")
    if not VariantsFolder then
        logger:warn("Variants folder not found in ReplicatedStorage")
        return false
    end
    
    local count = 0
    for _, item in pairs(VariantsFolder:GetChildren()) do
        if item:IsA("ModuleScript") then
            local success, moduleData = pcall(require, item)
            if success and moduleData and moduleData.Data then
                local data = moduleData.Data
                if data.Type == "Variant" and data.Name and data.Id then
                    variantDataCache[data.Name] = moduleData
                    variantIdToName[data.Id] = data.Name
                    count = count + 1
                end
            end
        end
    end
    
    logger:info(string.format("Loaded %d variants", count))
    return count > 0
end

local function findFavoriteRemote()
    local success, remote = pcall(function()
        return RS:WaitForChild("Packages", 5)
                  :WaitForChild("_Index", 5)
                  :WaitForChild("sleitnick_net@0.2.0", 5)
                  :WaitForChild("net", 5)
                  :WaitForChild("RE/FavoriteItem", 5)
    end)
    
    if success and remote then
        favoriteRemote = remote
        return true
    end
    
    logger:warn("Failed to find FavoriteItem remote")
    return false
end

-- ========== FILTERING LOGIC (KOMBINASI DENGAN AND LOGIC) ==========

local function matchesTierFilter(itemData)
    if not activeFilters.tier then return true end
    if next(selectedTiers) == nil then return true end
    
    local tier = itemData.Tier
    if not tier then return false end
    
    return selectedTiers[tier] == true
end

local function matchesNameFilter(itemData)
    if not activeFilters.name then return true end
    if next(selectedNames) == nil then return true end
    
    if not itemData.Name then return false end
    
    return selectedNames[itemData.Name] == true
end

local function matchesVariantFilter(fishData)
    if not activeFilters.variant then return true end
    if next(selectedVariants) == nil then return true end
    
    if not fishData.mutant then return false end
    
    if fishData.variantName then
        for selectedName in pairs(selectedVariants) do
            if string.lower(fishData.variantName) == string.lower(selectedName) then
                return true
            end
        end
    end
    
    if fishData.variantId then
        local variantName = variantIdToName[fishData.variantId]
        if variantName and selectedVariants[variantName] then
            return true
        end
    end
    
    return false
end

local function shouldFavoriteFish(fishData)
    if not fishData or fishData.favorited then return false end
    
    -- Jika tidak ada filter aktif, jangan favorite apapun
    if not activeFilters.tier and not activeFilters.name and not activeFilters.variant then
        return false
    end
    
    local itemData = fishDataCache[fishData.id]
    if not itemData then return false end
    
    -- AND logic: semua filter yang aktif harus match
    local tierMatch = matchesTierFilter(itemData)
    local nameMatch = matchesNameFilter(itemData)
    local variantMatch = matchesVariantFilter(fishData)
    
    return tierMatch and nameMatch and variantMatch
end

-- ========== FAVORITING ==========

local function favoriteFish(uuid)
    if not favoriteRemote or not uuid then return false end
    
    local success = pcall(function()
        favoriteRemote:FireServer(uuid)
    end)
    
    if success then
        pendingFavorites[uuid] = tick()
        logger:info("Favorited fish:", uuid)
    else
        logger:warn("Failed to favorite fish:", uuid)
    end
    
    return success
end

local function cooldownActive(uuid, now)
    local t = pendingFavorites[uuid]
    return t and (now - t) < FAVORITE_COOLDOWN
end

local function processInventory()
    if not fishWatcher then return end

    local allFishes = fishWatcher:getAllFishes()
    if not allFishes or #allFishes == 0 then return end

    local now = tick()

    for _, fishData in ipairs(allFishes) do
        local uuid = fishData.uuid
        
        if uuid and cooldownActive(uuid, now) then
            continue
        end
        
        if shouldFavoriteFish(fishData) then
            if not table.find(favoriteQueue, uuid) then
                table.insert(favoriteQueue, uuid)
            end
        end
    end
end

local function processFavoriteQueue()
    if #favoriteQueue == 0 then return end

    local currentTime = tick()
    if currentTime - lastFavoriteTime < FAVORITE_DELAY then return end

    local uuid = table.remove(favoriteQueue, 1)
    if uuid then
        local fish = fishWatcher:getFishByUUID(uuid)
        if not fish then
            lastFavoriteTime = currentTime
            return
        end
        
        if fish.favorited then
            lastFavoriteTime = currentTime
            return
        end
        
        if favoriteFish(uuid) then
        end
        lastFavoriteTime = currentTime
    end
end

local function mainLoop()
    if not running then return end
    processInventory()
    processFavoriteQueue()
end

-- ========== PUBLIC API ==========

function AutoFavoriteFish:Init(guiControls)
    if not loadTierData() then return false end
    if not scanFishData() then return false end
    if not loadVariantData() then return false end
    if not findFavoriteRemote() then return false end
    
    fishWatcher = FishWatcher.getShared()
    
    fishWatcher:onReady(function()
        logger:info("Fish watcher ready")
    end)
    
    if guiControls then
        if guiControls.tierDropdown then
            local tierNames = {}
            for tierNum = 1, 7 do
                if tierDataCache[tierNum] then
                    table.insert(tierNames, tierDataCache[tierNum].Name)
                end
            end
            pcall(function()
                guiControls.tierDropdown:Reload(tierNames)
            end)
        end
        
        if guiControls.nameDropdown then
            local fishNames = {}
            for _, fishData in pairs(fishDataCache) do
                if fishData.Name then
                    table.insert(fishNames, fishData.Name)
                end
            end
            table.sort(fishNames)
            pcall(function()
                guiControls.nameDropdown:Reload(fishNames)
            end)
        end
        
        if guiControls.variantDropdown then
            local variantNames = self:GetVariantNames()
            pcall(function()
                guiControls.variantDropdown:Reload(variantNames)
            end)
        end
    end
    
    return true
end

function AutoFavoriteFish:Start(config)
    if running then
        self:Stop()
        task.wait(0.1)
    end
    
    table.clear(favoriteQueue)
    table.clear(pendingFavorites)
    lastFavoriteTime = 0
    
    if config then
        if config.tierList then
            self:SetTiers(config.tierList)
        end
        if config.fishNames then
            self:SetFishNames(config.fishNames)
        end
        if config.variantList then
            self:SetVariants(config.variantList)
        end
    end
    
    running = true
    
    hbConn = RunService.Heartbeat:Connect(function()
        pcall(mainLoop)
    end)
    
    local activeFiltersList = {}
    if activeFilters.tier then table.insert(activeFiltersList, "tier") end
    if activeFilters.name then table.insert(activeFiltersList, "name") end
    if activeFilters.variant then table.insert(activeFiltersList, "variant") end
    
    logger:info("[AutoFavoriteFish] Started with filters:", table.concat(activeFiltersList, " + "))
end

function AutoFavoriteFish:Stop()
    if not running then return end
    
    running = false
    
    if hbConn then
        hbConn:Disconnect()
        hbConn = nil
    end
    
    logger:info("[AutoFavoriteFish] Stopped")
end

function AutoFavoriteFish:Cleanup()
    self:Stop()
    
    if fishWatcher then
        fishWatcher = nil
    end
    
    table.clear(fishDataCache)
    table.clear(tierDataCache)
    table.clear(variantDataCache)
    table.clear(variantIdToName)
    table.clear(selectedTiers)
    table.clear(selectedNames)
    table.clear(selectedVariants)
    table.clear(favoriteQueue)
    table.clear(pendingFavorites)
    
    activeFilters.tier = false
    activeFilters.name = false
    activeFilters.variant = false
    
    favoriteRemote = nil
    lastFavoriteTime = 0
end

-- ========== TIER FILTER ==========

function AutoFavoriteFish:SetTiers(tierInput)
    if not tierInput then 
        activeFilters.tier = false
        table.clear(selectedTiers)
        return true
    end
    
    table.clear(selectedTiers)
    
    if type(tierInput) == "table" then
        if #tierInput > 0 then
            for _, tierName in ipairs(tierInput) do
                for tierNum, tierInfo in pairs(tierDataCache) do
                    if tierInfo.Name == tierName then
                        selectedTiers[tierNum] = true
                        break
                    end
                end
            end
        else
            for tierName, enabled in pairs(tierInput) do
                if enabled then
                    for tierNum, tierInfo in pairs(tierDataCache) do
                        if tierInfo.Name == tierName then
                            selectedTiers[tierNum] = true
                            break
                        end
                    end
                end
            end
        end
    end
    
    activeFilters.tier = next(selectedTiers) ~= nil
    logger:info("Tier filter active:", activeFilters.tier, "Selected:", selectedTiers)
    return true
end

function AutoFavoriteFish:GetTierNames()
    local names = {}
    for tierNum = 1, 7 do
        if tierDataCache[tierNum] then
            table.insert(names, tierDataCache[tierNum].Name)
        end
    end
    return names
end

function AutoFavoriteFish:GetSelectedTiers()
    local selected = {}
    for tierNum, enabled in pairs(selectedTiers) do
        if enabled and tierDataCache[tierNum] then
            table.insert(selected, tierDataCache[tierNum].Name)
        end
    end
    return selected
end

-- ========== NAME FILTER ==========

function AutoFavoriteFish:SetFishNames(fishInput)
    if not fishInput then
        activeFilters.name = false
        table.clear(selectedNames)
        return true
    end
    
    table.clear(selectedNames)
    
    if type(fishInput) == "table" then
        if #fishInput > 0 then
            for _, fishName in ipairs(fishInput) do
                selectedNames[fishName] = true
            end
        else
            for fishName, enabled in pairs(fishInput) do
                if enabled then
                    selectedNames[fishName] = true
                end
            end
        end
    end
    
    activeFilters.name = next(selectedNames) ~= nil
    logger:info("Name filter active:", activeFilters.name, "Selected:", selectedNames)
    return true
end

function AutoFavoriteFish:GetFishNames()
    local fishNames = {}
    for _, fishData in pairs(fishDataCache) do
        if fishData.Name then
            table.insert(fishNames, fishData.Name)
        end
    end
    table.sort(fishNames)
    return fishNames
end

function AutoFavoriteFish:GetSelectedFishNames()
    local selected = {}
    for fishName, enabled in pairs(selectedNames) do
        if enabled then
            table.insert(selected, fishName)
        end
    end
    return selected
end

-- ========== VARIANT FILTER ==========

function AutoFavoriteFish:SetVariants(variantInput)
    if not variantInput then
        activeFilters.variant = false
        table.clear(selectedVariants)
        return true
    end
    
    table.clear(selectedVariants)
    
    if type(variantInput) == "table" then
        if #variantInput > 0 then
            for _, variantName in ipairs(variantInput) do
                if variantDataCache[variantName] then
                    selectedVariants[variantName] = true
                end
            end
        else
            for variantName, enabled in pairs(variantInput) do
                if enabled and variantDataCache[variantName] then
                    selectedVariants[variantName] = true
                end
            end
        end
    end
    
    activeFilters.variant = next(selectedVariants) ~= nil
    logger:info("Variant filter active:", activeFilters.variant, "Selected:", selectedVariants)
    return true
end

function AutoFavoriteFish:GetVariantNames()
    local names = {}
    for variantName in pairs(variantDataCache) do
        table.insert(names, variantName)
    end
    table.sort(names)
    return names
end

function AutoFavoriteFish:GetSelectedVariants()
    local selected = {}
    for variantName, enabled in pairs(selectedVariants) do
        if enabled then
            table.insert(selected, variantName)
        end
    end
    table.sort(selected)
    return selected
end

-- ========== CLEAR FILTERS ==========

function AutoFavoriteFish:ClearTiers()
    return self:SetTiers(nil)
end

function AutoFavoriteFish:ClearFishNames()
    return self:SetFishNames(nil)
end

function AutoFavoriteFish:ClearVariants()
    return self:SetVariants(nil)
end

function AutoFavoriteFish:ClearAllFilters()
    self:ClearTiers()
    self:ClearFishNames()
    self:ClearVariants()
    logger:info("All filters cleared")
end

-- ========== UTILITIES ==========

function AutoFavoriteFish:SetFavoriteDelay(delay)
    if type(delay) == "number" and delay >= 0.1 then
        FAVORITE_DELAY = delay
        return true
    end
    return false
end

function AutoFavoriteFish:GetQueueSize()
    return #favoriteQueue
end

function AutoFavoriteFish:GetActiveFilters()
    local active = {}
    if activeFilters.tier then table.insert(active, "tier") end
    if activeFilters.name then table.insert(active, "name") end
    if activeFilters.variant then table.insert(active, "variant") end
    return active
end

function AutoFavoriteFish:DebugFishStatus(limit)
    if not fishWatcher then return end
    
    local allFishes = fishWatcher:getAllFishes()
    if not allFishes or #allFishes == 0 then return end
    
    logger:info("=== DEBUG FISH STATUS ===")
    logger:info("Active Filters:", table.concat(self:GetActiveFilters(), " + "))
    
    for i, fishData in ipairs(allFishes) do
        if limit and i > limit then break end
        
        local itemData = fishDataCache[fishData.id]
        local fishName = itemData and itemData.Name or "Unknown"
        
        logger:info(string.format("%d. %s (%s)", i, fishName, fishData.uuid or "no-uuid"))
        logger:info("   Is favorited:", fishData.favorited)
        
        if itemData then
            if activeFilters.tier then
                local tierInfo = tierDataCache[itemData.Tier]
                local tierName = tierInfo and tierInfo.Name or "Unknown"
                logger:info("   Tier:", tierName, "Match:", matchesTierFilter(itemData))
            end
            
            if activeFilters.name then
                logger:info("   Name:", itemData.Name, "Match:", matchesNameFilter(itemData))
            end
            
            if activeFilters.variant then
                logger:info("   Variant:", fishData.variantName or "None", "Match:", matchesVariantFilter(fishData))
            end
            
            logger:info("   SHOULD FAVORITE:", shouldFavoriteFish(fishData))
        end
        logger:info("")
    end
end

-- ========== ALIASES (backward compatibility) ==========

AutoFavoriteFish.SetDesiredTiersByNames = AutoFavoriteFish.SetTiers
AutoFavoriteFish.SetSelectedFishNames = AutoFavoriteFish.SetFishNames
AutoFavoriteFish.SetDesiredVariantsByNames = AutoFavoriteFish.SetVariants

return AutoFavoriteFish

--[[
=== USAGE EXAMPLES ===

local autoFav = require(script.AutoFavoriteFish)

-- Init
if not autoFav:Init() then
    warn("Failed to init")
    return
end

-- Contoh 1: Hanya favorite Mythical tier
autoFav:SetTiers({"Mythical"})
autoFav:Start()

-- Contoh 2: Hanya favorite fish dengan nama tertentu
autoFav:SetFishNames({"Ancient Depth Serpent", "Megalodon"})
autoFav:Start()

-- Contoh 3: Hanya favorite fish dengan variant Shiny
autoFav:SetVariants({"Shiny"})
autoFav:Start()

-- Contoh 4: Favorite Mythical + Shiny (kombinasi tier + variant)
autoFav:SetTiers({"Mythical"})
autoFav:SetVariants({"Shiny", "Sparkling"})
autoFav:Start()
-- Hasilnya: hanya favorite fish yang Mythical DAN memiliki variant Shiny/Sparkling

-- Contoh 5: Favorite fish tertentu + variant tertentu
autoFav:SetFishNames({"Ancient Depth Serpent"})
autoFav:SetVariants({"Shiny"})
autoFav:Start()
-- Hasilnya: hanya favorite Ancient Depth Serpent yang Shiny

-- Contoh 6: Kombinasi 3 filter (tier + name + variant)
autoFav:SetTiers({"Mythical", "Legendary"})
autoFav:SetFishNames({"Ancient Depth Serpent"})
autoFav:SetVariants({"Shiny"})
autoFav:Start()
-- Hasilnya: favorite Ancient Depth Serpent yang tier Mythical/Legendary DAN Shiny

-- Clear filter tertentu
autoFav:ClearTiers()  -- hapus filter tier, filter lain tetap aktif
autoFav:ClearVariants()  -- hapus filter variant
autoFav:ClearAllFilters()  -- hapus semua filter

-- Check active filters
print(autoFav:GetActiveFilters())  -- {"tier", "variant"}

-- Load config dari saved data
autoFav:Start({
    tierList = {"Mythical"},
    variantList = {"Shiny", "Sparkling"}
})

]]