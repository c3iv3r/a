-- autofavoritefish_v3.lua - Favorite by variant/mutation
local AutoFavoriteFishV3 = {}
AutoFavoriteFishV3.__index = AutoFavoriteFishV3

local logger = _G.Logger and _G.Logger.new("AutoFavoriteFishV3") or {
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

local selectedVariants = {}
local FAVORITE_DELAY = 0.3
local FAVORITE_COOLDOWN = 2.0

local variantDataCache = {}
local lastFavoriteTime = 0
local favoriteQueue = {}
local pendingFavorites = {}
local favoriteRemote = nil

local function loadVariantData()
    local variantsFolder = RS:FindFirstChild("Variants")
    if not variantsFolder then
        logger:warn("Variants folder not found")
        return false
    end
    
    for _, child in ipairs(variantsFolder:GetChildren()) do
        if child:IsA("ModuleScript") then
            local success, data = pcall(function()
                return require(child)
            end)
            
            if success and data and data.Data then
                local variantData = data.Data
                if variantData.Type == "Variant" and variantData.Id and variantData.Name then
                    variantDataCache[variantData.Id] = variantData
                end
            end
        end
    end
    
    if next(variantDataCache) == nil then
        logger:warn("No variant data loaded")
        return false
    end
    
    logger:info("Loaded variants:", #variantDataCache)
    return true
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
    if not fishData.mutant then return false end
    
    local variantId = fishData.variantId
    if not variantId then return false end
    
    local variantData = variantDataCache[variantId]
    if not variantData then return false end
    
    return selectedVariants[variantData.Name] == true
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

function AutoFavoriteFishV3:Init(guiControls)
    if not loadVariantData() then
        return false
    end
    
    if not findFavoriteRemote() then
        return false
    end
    
    fishWatcher = FishWatcher.getShared()
    
    fishWatcher:onReady(function()
        logger:info("Fish watcher ready")
    end)
    
    if guiControls and guiControls.variantDropdown then
        local variantNames = {}
        for _, variantData in pairs(variantDataCache) do
            table.insert(variantNames, variantData.Name)
        end
        table.sort(variantNames)
        
        pcall(function()
            guiControls.variantDropdown:Reload(variantNames)
        end)
    end
    
    return true
end

function AutoFavoriteFishV3:Start(config)
    if running then return end
    
    running = true
    
    if config and config.variantList then
        self:SetVariants(config.variantList)
    end
    
    hbConn = RunService.Heartbeat:Connect(function()
        local success = pcall(mainLoop)
        if not success then
            logger:warn("Error in main loop")
        end
    end)
    
    logger:info("[AutoFavoriteFishV3] Started")
end

function AutoFavoriteFishV3:Stop()
    if not running then return end
    
    running = false
    
    if hbConn then
        hbConn:Disconnect()
        hbConn = nil
    end
    
    logger:info("[AutoFavoriteFishV3] Stopped")
end

function AutoFavoriteFishV3:Cleanup()
    self:Stop()
    
    if fishWatcher then
        fishWatcher = nil
    end
    
    table.clear(variantDataCache)
    table.clear(selectedVariants)
    table.clear(favoriteQueue)
    table.clear(pendingFavorites)
    
    favoriteRemote = nil
    lastFavoriteTime = 0
    
    logger:info("Cleaned up")
end

function AutoFavoriteFishV3:SetVariants(variantInput)
    if not variantInput then return false end
    
    table.clear(selectedVariants)
    
    if type(variantInput) == "table" then
        if #variantInput > 0 then
            for _, variantName in ipairs(variantInput) do
                selectedVariants[variantName] = true
            end
        else
            for variantName, enabled in pairs(variantInput) do
                if enabled then
                    selectedVariants[variantName] = true
                end
            end
        end
    end
    
    logger:info("Selected variants:", selectedVariants)

    if next(selectedVariants) and not running then
        self:Start({ variantList = variantInput })
    end

    return true
end

function AutoFavoriteFishV3:SetFavoriteDelay(delay)
    if type(delay) == "number" and delay >= 0.1 then
        FAVORITE_DELAY = delay
        return true
    end
    return false
end

function AutoFavoriteFishV3:SetDesiredVariantsByNames(variantInput)
    return self:SetVariants(variantInput)
end

function AutoFavoriteFishV3:GetVariantNames()
    local names = {}
    for _, variantData in pairs(variantDataCache) do
        table.insert(names, variantData.Name)
    end
    table.sort(names)
    return names
end

function AutoFavoriteFishV3:GetSelectedVariants()
    local selected = {}
    for variantName, enabled in pairs(selectedVariants) do
        if enabled then
            table.insert(selected, variantName)
        end
    end
    table.sort(selected)
    return selected
end

function AutoFavoriteFishV3:GetQueueSize()
    return #favoriteQueue
end

function AutoFavoriteFishV3:DebugFishStatus(limit)
    if not fishWatcher then return end
    
    local allFishes = fishWatcher:getAllFishes()
    if not allFishes or #allFishes == 0 then return end
    
    logger:info("=== DEBUG FISH STATUS (VARIANTS) ===")
    for i, fishData in ipairs(allFishes) do
        if limit and i > limit then break end
        
        logger:info(string.format("%d. %s (%s)", i, fishData.name or "Unknown", fishData.uuid or "no-uuid"))
        logger:info("   Is favorited:", fishData.favorited)
        logger:info("   Has mutation:", fishData.mutant)
        
        if fishData.mutant then
            logger:info("   Variant ID:", fishData.variantId or "none")
            logger:info("   Variant Name:", fishData.variantName or "Unknown")
            logger:info("   Should favorite:", shouldFavoriteFish(fishData))
        end
        logger:info("")
    end
end

function AutoFavoriteFishV3:DebugVariantData()
    logger:info("=== LOADED VARIANT DATA ===")
    for id, data in pairs(variantDataCache) do
        logger:info(string.format("ID: %d - Name: %s", id, data.Name))
    end
end

return AutoFavoriteFishV3