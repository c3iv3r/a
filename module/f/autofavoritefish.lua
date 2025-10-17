-- Fish-It/autofavoritefish_patched.lua
-- v2: Patched to use event-driven logic from InventoryWatcher

local AutoFavoriteFish = {}
AutoFavoriteFish.__index = AutoFavoriteFish

local logger = _G.Logger and _G.Logger.new("AutoFavoriteFish") or {
    debug = function() end,
    info = function() end,
    warn = function() end,
    error = function() end
}

-- Services
local RS = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

-- Dependencies
-- IMPORTANT: This now requires the _patched version of InventoryWatcher
local InventoryWatcher = _G.InventoryWatcher_Patched or loadstring(game:HttpGet("https://raw.githubusercontent.com/c3iv3r/a/refs/heads/main/utils/fishit/inventdetect3.lua"))()

-- State
local running = false
local hbConn = nil -- Heartbeat is now ONLY for the queue
local inventoryWatcher = nil

-- Configuration
local selectedTiers = {} -- set: { [tierNumber] = true }
local FAVORITE_DELAY = 0.3
local FAVORITE_COOLDOWN = 2.0

-- Cache
local fishDataCache = {} 
local tierDataCache = {} 
local lastFavoriteTime = 0
local favoriteQueue = {} 
local pendingFavorites = {}  

-- Remotes
local favoriteRemote = nil

-- === Helper Functions ===

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

local function shouldFavoriteFish(fishEntry)
    if not fishEntry then return false end
    
    local fishId = fishEntry.Id or fishEntry.id
    if not fishId then return false end
    
    local fishData = fishDataCache[fishId]
    if not fishData then return false end
    
    local tier = fishData.Tier
    if not tier then return false end
    
    return selectedTiers[tier] == true
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

-- === Lifecycle Methods ===

function AutoFavoriteFish:Init(guiControls)
    if not loadTierData() then return false end
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
    
    if guiControls and guiControls.tierDropdown then
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
    
    return true
end

function AutoFavoriteFish:Start(config)
    if running then return end
    
    if config and config.tierList then
        self:SetTiers(config.tierList)
    end
    
    running = true
    
    -- The main loop now only processes the favorite queue, not the whole inventory.
    hbConn = RunService.Heartbeat:Connect(processFavoriteQueue)
    
    logger:info("[AutoFavoriteFish] Started (Patched Event-Driven Mode)")
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
    
    if inventoryWatcher then
        inventoryWatcher:destroy()
        inventoryWatcher = nil
    end
    
    table.clear(fishDataCache)
    table.clear(tierDataCache)
    table.clear(selectedTiers)
    table.clear(favoriteQueue)
    
    favoriteRemote = nil
    lastFavoriteTime = 0
    
    logger:info("Cleaned up")
end

-- === Setters ===

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
    return true
end

-- Other public methods remain the same...
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

function AutoFavoriteFish:GetQueueSize()
    return #favoriteQueue
end

return AutoFavoriteFish
