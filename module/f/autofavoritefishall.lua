-- autofavorite.lua (UNIFIED MODULE - FIXED AUTOLOAD CLEAN)
local AutoFavorite = {}
AutoFavorite.__index = AutoFavorite

local logger = _G.Logger and _G.Logger.new("AutoFavorite") or {
    debug = function() end,
    info = function() end,
    warn = function() end,
    error = function() end
}

local RS = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local FishWatcher = loadstring(game:HttpGet("https://raw.githubusercontent.com/c3iv3r/a/refs/heads/main/utils/fishit/fishwatcherori.lua"))()

local running = false
local hbConn = nil
local fishWatcher = nil

local selectedTiers = {}
local selectedFishNames = {}
local selectedVariants = {}

local FAVORITE_DELAY = 0.3
local FAVORITE_COOLDOWN = 2.0

local fishDataCache = {}
local tierDataCache = {}
local variantDataCache = {}
local variantIdToName = {}

local lastFavoriteTime = 0
local favoriteQueue = {}
local pendingFavorites = {}
local favoriteRemote = nil

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
        logger:warn("Variants folder not found")
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

local function shouldFavoriteFish(fishData)
    if not fishData or fishData.favorited then return false end
    
    local itemData = fishDataCache[fishData.id]
    if not itemData then return false end
    
    local hasTierFilter = next(selectedTiers) ~= nil
    local hasNameFilter = next(selectedFishNames) ~= nil
    local hasVariantFilter = next(selectedVariants) ~= nil
    
    if not hasTierFilter and not hasNameFilter and not hasVariantFilter then
        return false
    end
    
    local tierMatch = not hasTierFilter
    local nameMatch = not hasNameFilter
    local variantMatch = not hasVariantFilter
    
    if hasTierFilter then
        local tier = itemData.Tier
        tierMatch = tier and selectedTiers[tier] == true
    end
    
    if hasNameFilter then
        local fishName = itemData.Name
        nameMatch = fishName and selectedFishNames[fishName] == true
    end
    
    if hasVariantFilter then
        if fishData.mutant then
            if fishData.variantName then
                for selectedName in pairs(selectedVariants) do
                    if string.lower(fishData.variantName) == string.lower(selectedName) then
                        variantMatch = true
                        break
                    end
                end
            end
            
            if not variantMatch and fishData.variantId then
                local variantName = variantIdToName[fishData.variantId]
                if variantName and selectedVariants[variantName] then
                    variantMatch = true
                end
            end
        else
            variantMatch = false
        end
    end
    
    return tierMatch and nameMatch and variantMatch
end

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
            -- Cooldown tracked in pendingFavorites
        end
        lastFavoriteTime = currentTime
    end
end

local function mainLoop()
    if not running then return end
    
    processInventory()
    processFavoriteQueue()
end

function AutoFavorite:Init(guiControls)
    if not loadTierData() then
        return false
    end
    
    if not scanFishData() then
        return false
    end
    
    if not loadVariantData() then
        return false
    end
    
    if not findFavoriteRemote() then
        return false
    end
    
    fishWatcher = FishWatcher.getShared()
    
    -- Setup onReady to trigger initial scan when running
    fishWatcher:onReady(function()
        logger:info("Fish watcher ready")
        
        -- If already started with config, do initial scan
        if running and (next(selectedTiers) or next(selectedFishNames) or next(selectedVariants)) then
            task.wait(0.3)
            processInventory()
            logger:info("Initial inventory scan completed")
        end
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
        
        if guiControls.fishDropdown then
            local fishNames = {}
            for _, fishData in pairs(fishDataCache) do
                if fishData.Name then
                    table.insert(fishNames, fishData.Name)
                end
            end
            table.sort(fishNames)
            pcall(function()
                guiControls.fishDropdown:Reload(fishNames)
            end)
        end
        
        if guiControls.variantDropdown then
            local variantNames = {}
            for variantName in pairs(variantDataCache) do
                table.insert(variantNames, variantName)
            end
            table.sort(variantNames)
            pcall(function()
                guiControls.variantDropdown:Reload(variantNames)
            end)
        end
    end
    
    return true
end

function AutoFavorite:Start(config)
    if running then return end
    
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
    
    logger:info("[AutoFavorite] Started")
end

function AutoFavorite:Stop()
    if not running then return end
    
    running = false
    
    if hbConn then
        hbConn:Disconnect()
        hbConn = nil
    end
    
    logger:info("[AutoFavorite] Stopped")
end

function AutoFavorite:Cleanup()
    self:Stop()
    
    if fishWatcher then
        fishWatcher = nil
    end
    
    table.clear(fishDataCache)
    table.clear(tierDataCache)
    table.clear(variantDataCache)
    table.clear(variantIdToName)
    table.clear(selectedTiers)
    table.clear(selectedFishNames)
    table.clear(selectedVariants)
    table.clear(favoriteQueue)
    table.clear(pendingFavorites)
    
    favoriteRemote = nil
    lastFavoriteTime = 0
    
    logger:info("Cleaned up")
end

function AutoFavorite:SetTiers(tierInput)
    table.clear(selectedTiers)
    
    if not tierInput then return true end
    
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
    
    logger:info("Selected tiers:", selectedTiers)
    return true
end

function AutoFavorite:SetFishNames(fishInput)
    table.clear(selectedFishNames)

    if not fishInput then return true end

    if type(fishInput) == "table" then
        if #fishInput > 0 then
            for _, fishName in ipairs(fishInput) do
                selectedFishNames[fishName] = true
            end
        else
            for fishName, enabled in pairs(fishInput) do
                if enabled then
                    selectedFishNames[fishName] = true
                end
            end
        end
    end

    logger:info("Selected fish names:", selectedFishNames)
    return true
end

function AutoFavorite:SetVariants(variantInput)
    table.clear(selectedVariants)
    
    if not variantInput then return true end
    
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
    
    logger:info("Selected variants:", selectedVariants)
    return true
end

function AutoFavorite:SetFavoriteDelay(delay)
    if type(delay) == "number" and delay >= 0.1 then
        FAVORITE_DELAY = delay
        return true
    end
    return false
end

function AutoFavorite:GetTierNames()
    local names = {}
    for tierNum = 1, 7 do
        if tierDataCache[tierNum] then
            table.insert(names, tierDataCache[tierNum].Name)
        end
    end
    return names
end

function AutoFavorite:GetFishNames()
    local names = {}
    for _, fishData in pairs(fishDataCache) do
        if fishData.Name then
            table.insert(names, fishData.Name)
        end
    end
    table.sort(names)
    return names
end

function AutoFavorite:GetVariantNames()
    local names = {}
    for variantName in pairs(variantDataCache) do
        table.insert(names, variantName)
    end
    table.sort(names)
    return names
end

function AutoFavorite:GetSelectedTiers()
    local selected = {}
    for tierNum, enabled in pairs(selectedTiers) do
        if enabled and tierDataCache[tierNum] then
            table.insert(selected, tierDataCache[tierNum].Name)
        end
    end
    return selected
end

function AutoFavorite:GetSelectedFishNames()
    local selected = {}
    for fishName, enabled in pairs(selectedFishNames) do
        if enabled then
            table.insert(selected, fishName)
        end
    end
    return selected
end

function AutoFavorite:GetSelectedVariants()
    local selected = {}
    for variantName, enabled in pairs(selectedVariants) do
        if enabled then
            table.insert(selected, variantName)
        end
    end
    table.sort(selected)
    return selected
end

function AutoFavorite:GetQueueSize()
    return #favoriteQueue
end

function AutoFavorite:DebugFishStatus(limit)
    if not fishWatcher then return end
    
    local allFishes = fishWatcher:getAllFishes()
    if not allFishes or #allFishes == 0 then return end
    
    logger:info("=== DEBUG FISH STATUS ===")
    for i, fishData in ipairs(allFishes) do
        if limit and i > limit then break end
        
        local itemData = fishDataCache[fishData.id]
        local fishName = itemData and itemData.Name or "Unknown"
        
        logger:info(string.format("%d. %s (%s)", i, fishName, fishData.uuid or "no-uuid"))
        logger:info("   Is favorited:", fishData.favorited)
        
        if itemData then
            local tierInfo = tierDataCache[itemData.Tier]
            local tierName = tierInfo and tierInfo.Name or "Unknown"
            logger:info("   Tier:", tierName)
        end
        
        if fishData.mutant then
            logger:info("   Variant:", fishData.variantName or "Unknown")
        end
        
        logger:info("   Should favorite:", shouldFavoriteFish(fishData))
        logger:info("")
    end
end

function AutoFavorite:Status()
    logger:info("=== AUTO-FAVORITE STATUS ===")
    logger:info("Running:", running)
    logger:info("Queue size:", #favoriteQueue)
    logger:info("Selected tiers:", #self:GetSelectedTiers())
    logger:info("Selected fish names:", #self:GetSelectedFishNames())
    logger:info("Selected variants:", #self:GetSelectedVariants())
end

return AutoFavorite