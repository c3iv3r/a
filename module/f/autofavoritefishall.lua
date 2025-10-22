-- autofavoritefish.lua (FINAL PATCHED) - Favorite by tier, variant & fish names
local AutoFavoriteFish = {}
AutoFavoriteFish.__index = AutoFavoriteFish

local logger = _G.Logger and _G.Logger.new("AutoFavoriteFish") or {
    debug = function() end,
    info = function() end,
    warn = function() end,
    error = function() end
}

local RS = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local FishWatcher = loadstring(game:HttpGet("https://raw.githubusercontent.com/c3iv3r/a/refs/heads/main/utils/fishit/fishwatcher.lua"))()

local running = false
local hbConn = nil
local fishWatcher = nil

local selectedTiers = {}
local selectedVariants = {}
local selectedFishNames = {}
local FAVORITE_DELAY = 0.3
local FAVORITE_COOLDOWN = 2.0

local fishDataCache = {}
local tierDataCache = {}
local variantDataCache = {}
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

local function loadVariantData()
    local variantsFolder = RS:FindFirstChild("Variants")
    if not variantsFolder then
        logger:warn("Variants folder not found")
        return false
    end
    
    for _, variantModule in ipairs(variantsFolder:GetChildren()) do
        if variantModule:IsA("ModuleScript") then
            local success, data = pcall(function()
                return require(variantModule)
            end)
            
            if success and data and data.Data then
                local variantData = data.Data
                if variantData.Id and variantData.Name then
                    variantDataCache[variantData.Id] = variantData
                end
            end
        end
    end
    
    return next(variantDataCache) ~= nil
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
                    if fishData.Type == "Fishes" and fishData.Id and fishData.Tier then
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
    
    local hasTierSelected = next(selectedTiers) ~= nil
    local hasVariantSelected = next(selectedVariants) ~= nil
    local hasFishNameSelected = next(selectedFishNames) ~= nil
    
    if not hasTierSelected and not hasVariantSelected and not hasFishNameSelected then
        return false
    end
    
    local tierMatch = false
    local variantMatch = false
    local fishNameMatch = false
    
    if hasTierSelected then
        local tier = itemData.Tier
        tierMatch = tier and selectedTiers[tier] == true
    else
        tierMatch = true
    end
    
    if hasVariantSelected then
        local variant = fishData.variant
        variantMatch = variant and selectedVariants[variant] == true
    else
        variantMatch = true
    end
    
    if hasFishNameSelected then
        local fishName = itemData.Name
        fishNameMatch = fishName and selectedFishNames[fishName] == true
    else
        fishNameMatch = true
    end
    
    return tierMatch and variantMatch and fishNameMatch
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
            -- Cooldown tracked in favoriteFish()
        end
        lastFavoriteTime = currentTime
    end
end

local function mainLoop()
    if not running then return end
    
    processInventory()
    processFavoriteQueue()
end

function AutoFavoriteFish:Init(guiControls)
    if not loadTierData() then
        return false
    end
    
    if not loadVariantData() then
        logger:warn("No variants loaded, continuing without variants")
    end
    
    if not scanFishData() then
        return false
    end
    
    if not findFavoriteRemote() then
        return false
    end
    
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
        
        if guiControls.variantDropdown then
            local variantNames = {}
            for _, variantData in pairs(variantDataCache) do
                table.insert(variantNames, variantData.Name)
            end
            table.sort(variantNames)
            
            pcall(function()
                guiControls.variantDropdown:Reload(variantNames)
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
    end
    
    return true
end

function AutoFavoriteFish:Start(config)
    if running then return end
    
    running = true
    
    if config then
        if config.tierList then
            self:SetTiers(config.tierList)
        end
        if config.variantList then
            self:SetVariants(config.variantList)
        end
        if config.fishNames then
            self:SetFishNames(config.fishNames)
        end
    end
    
    hbConn = RunService.Heartbeat:Connect(function()
        local success = pcall(mainLoop)
        if not success then
            logger:warn("Error in main loop")
        end
    end)
    
    logger:info("[AutoFavoriteFish] Started")
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
    table.clear(selectedTiers)
    table.clear(selectedVariants)
    table.clear(selectedFishNames)
    table.clear(favoriteQueue)
    table.clear(pendingFavorites)
    
    favoriteRemote = nil
    lastFavoriteTime = 0
    
    logger:info("Cleaned up")
end

function AutoFavoriteFish:SetTiers(tierInput)
    if not tierInput then return false end
    
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
    
    logger:info("Selected tiers:", selectedTiers)

    if (next(selectedTiers) or next(selectedVariants) or next(selectedFishNames)) and not running then
        self:Start({ tierList = tierInput })
    end

    return true
end

function AutoFavoriteFish:SetVariants(variantInput)
    if not variantInput then return false end
    
    table.clear(selectedVariants)
    
    if type(variantInput) == "table" then
        if #variantInput > 0 then
            for _, variantName in ipairs(variantInput) do
                for variantId, variantData in pairs(variantDataCache) do
                    if variantData.Name == variantName then
                        selectedVariants[variantId] = true
                        break
                    end
                end
            end
        else
            for variantName, enabled in pairs(variantInput) do
                if enabled then
                    for variantId, variantData in pairs(variantDataCache) do
                        if variantData.Name == variantName then
                            selectedVariants[variantId] = true
                            break
                        end
                    end
                end
            end
        end
    end
    
    logger:info("Selected variants:", selectedVariants)

    if (next(selectedTiers) or next(selectedVariants) or next(selectedFishNames)) and not running then
        self:Start({ variantList = variantInput })
    end

    return true
end

function AutoFavoriteFish:SetFishNames(fishInput)
    if not fishInput then return false end
    
    table.clear(selectedFishNames)
    
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

    if (next(selectedTiers) or next(selectedVariants) or next(selectedFishNames)) and not running then
        self:Start({ fishNames = fishInput })
    end

    return true
end

function AutoFavoriteFish:SetFavoriteDelay(delay)
    if type(delay) == "number" and delay >= 0.1 then
        FAVORITE_DELAY = delay
        return true
    end
    return false
end

function AutoFavoriteFish:SetDesiredTiersByNames(tierInput)
    return self:SetTiers(tierInput)
end

function AutoFavoriteFish:SetDesiredVariantsByNames(variantInput)
    return self:SetVariants(variantInput)
end

function AutoFavoriteFish:SetDesiredFishNames(fishInput)
    return self:SetFishNames(fishInput)
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

function AutoFavoriteFish:GetVariantNames()
    local names = {}
    for _, variantData in pairs(variantDataCache) do
        table.insert(names, variantData.Name)
    end
    table.sort(names)
    return names
end

function AutoFavoriteFish:GetFishNames()
    local names = {}
    for _, fishData in pairs(fishDataCache) do
        if fishData.Name then
            table.insert(names, fishData.Name)
        end
    end
    table.sort(names)
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

function AutoFavoriteFish:GetSelectedVariants()
    local selected = {}
    for variantId, enabled in pairs(selectedVariants) do
        if enabled and variantDataCache[variantId] then
            table.insert(selected, variantDataCache[variantId].Name)
        end
    end
    table.sort(selected)
    return selected
end

function AutoFavoriteFish:GetSelectedFishNames()
    local selected = {}
    for fishName, enabled in pairs(selectedFishNames) do
        if enabled then
            table.insert(selected, fishName)
        end
    end
    table.sort(selected)
    return selected
end

function AutoFavoriteFish:GetQueueSize()
    return #favoriteQueue
end

function AutoFavoriteFish:DebugFishStatus(limit)
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
            
            if fishData.variant then
                local variantData = variantDataCache[fishData.variant]
                local variantName = variantData and variantData.Name or "Unknown"
                logger:info("   Variant:", variantName)
            end
            
            logger:info("   Should favorite:", shouldFavoriteFish(fishData))
        end
        logger:info("")
    end
end

return AutoFavoriteFish