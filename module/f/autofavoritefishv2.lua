-- autofavoritefishv2_patched.lua - Favorite by fish names
-- v2: Patched to use event-driven logic from InventoryWatcher

local AutoFavoriteFishV2 = {}
AutoFavoriteFishV2.__index = AutoFavoriteFishV2

local logger = _G.Logger and _G.Logger.new("AutoFavoriteFishV2") or {
    debug = function() end, info = function() end, warn = function() end, error = function() end
}

local RS = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

-- IMPORTANT: This now requires the _patched version of InventoryWatcher
local InventoryWatcher = _G.InventoryWatcher_Patched or loadstring(game:HttpGet("https://raw.githubusercontent.com/c3iv3r/a/refs/heads/main/utils/fishit/inventdetect_patched.lua"))()

-- State
local running = false
local hbConn = nil -- Heartbeat is now ONLY for the queue
local inventoryWatcher = nil
local selectedFishNames = {} 
local FAVORITE_DELAY = 0.3
local FAVORITE_COOLDOWN = 2.0

-- Cache
local fishDataCache = {} 
local lastFavoriteTime = 0
local favoriteQueue = {}
local pendingFavorites = {} 
local favoriteRemote = nil

local function scanFishData()
    local itemsModule = RS:FindFirstChild("Items")
    if not itemsModule then
        logger:warn("Items module not found")
        return false
    end

    for _, item in pairs(itemsModule:GetChildren()) do
        if item:IsA("ModuleScript") then
            local success, moduleData = pcall(function()
                return require(item)
            end)

            if success and moduleData and moduleData.Data then
                local fishData = moduleData.Data
                if fishData.Type == "Fishes" and fishData.Id and fishData.Name then
                    fishDataCache[fishData.Id] = fishData
                end
            end
        end
    end
    return next(fishDataCache) ~= nil
end

local function getFishNamesForDropdown()
    local fishNames = {}
    for _, fishData in pairs(fishDataCache) do
        if fishData.Name then
            table.insert(fishNames, fishData.Name)
        end
    end
    table.sort(fishNames)
    return fishNames
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

local function shouldFavoriteFish(fishEntry)
    if not fishEntry then return false end
    
    local fishId = fishEntry.Id or fishEntry.id
    if not fishId then return false end
    
    local fishData = fishDataCache[fishId]
    if not fishData or not fishData.Name then return false end
    
    return selectedFishNames[fishData.Name] == true
end

local function favoriteFish(uuid)
    if not favoriteRemote or not uuid then return false end
    
    local success = pcall(function()
        favoriteRemote:FireServer(uuid)
    end)
    
    if success then
        logger:info("Favorited fish:", uuid)
    else
        logger:warn("Failed to favorite fish:", uuid)
    end
    
    return success
end

local function getUUID(entry)
    return entry.UUID or entry.Uuid or entry.uuid
end

local function isFavorited(entry)
    if entry.Favorited ~= nil then return entry.Favorited end
    if entry.favorited ~= nil then return entry.favorited end
    if entry.Metadata and entry.Metadata.Favorited ~= nil then return entry.Metadata.Favorited end
    if entry.Metadata and entry.Metadata.favorited ~= nil then return entry.Metadata.favorited end
    return false
end

local function cooldownActive(uuid, now)
    local t = pendingFavorites[uuid]
    return t and (now - t) < FAVORITE_COOLDOWN
end

-- OPTIMIZED: This function now processes a SINGLE fish entry from an event.
local function processSingleFish(fishEntry)
    if not running or not fishEntry then return end

    if shouldFavoriteFish(fishEntry) and not isFavorited(fishEntry) then
        local uuid = getUUID(fishEntry)
        if uuid and not cooldownActive(uuid, tick()) and not table.find(favoriteQueue, uuid) then
            table.insert(favoriteQueue, uuid)
        end
    end
end

-- The queue processor still needs a heartbeat to run periodically.
local function processFavoriteQueue()
    if #favoriteQueue == 0 then return end

    local currentTime = tick()
    if currentTime - lastFavoriteTime < FAVORITE_DELAY then return end

    local uuid = table.remove(favoriteQueue, 1)
    if uuid then
        if favoriteFish(uuid) then
            pendingFavorites[uuid] = currentTime
        end
        lastFavoriteTime = currentTime
    end
end

function AutoFavoriteFishV2:Init(guiControls)
    if not scanFishData() then return false end
    if not findFavoriteRemote() then return false end
    
    inventoryWatcher = InventoryWatcher.new()
    
    inventoryWatcher:onReady(function()
        logger:info("Inventory watcher ready")

        -- OPTIMIZED: Connect to the new onItemAdded event
        inventoryWatcher:onItemAdded(function(itemEntry, itemType)
            if running and itemType == "Fishes" then
                processSingleFish(itemEntry)
            end
        end)
    end)
    
    if guiControls and guiControls.fishDropdown then
        local fishNames = getFishNamesForDropdown()
        pcall(function()
            guiControls.fishDropdown:Reload(fishNames)
        end)
    end
    
    return true
end

function AutoFavoriteFishV2:Start(config)
    if running then return end
    
    if config and config.fishNames then
        self:SetSelectedFishNames(config.fishNames)
    end
    
    running = true
    
    -- The main loop now only processes the favorite queue.
    hbConn = RunService.Heartbeat:Connect(processFavoriteQueue)
    
    logger:info("AutoFavoriteFishV2 Started (Patched Event-Driven Mode)")
end

function AutoFavoriteFishV2:Stop()
    if not running then return end
    
    running = false
    
    if hbConn then
        hbConn:Disconnect()
        hbConn = nil
    end
    
    logger:info("AutoFavoriteFishV2 Stopped")
end

function AutoFavoriteFishV2:Cleanup()
    self:Stop()
    
    if inventoryWatcher then
        inventoryWatcher:destroy()
        inventoryWatcher = nil
    end
    
    table.clear(fishDataCache)
    table.clear(selectedFishNames)
    table.clear(favoriteQueue)
    table.clear(pendingFavorites)
    
    favoriteRemote = nil
    lastFavoriteTime = 0
end

function AutoFavoriteFishV2:SetSelectedFishNames(fishInput)
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
    return true
end

-- Other public methods remain the same...
function AutoFavoriteFishV2:GetFishNames()
    return getFishNamesForDropdown()
end

function AutoFavoriteFishV2:GetSelectedFishNames()
    local selected = {}
    for fishName, enabled in pairs(selectedFishNames) do
        if enabled then
            table.insert(selected, fishName)
        end
    end
    return selected
end

function AutoFavoriteFishV2:GetQueueSize()
    return #favoriteQueue
end

return AutoFavoriteFishV2
