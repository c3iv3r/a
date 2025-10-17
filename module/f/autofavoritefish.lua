-- autofavoritefish_optimized.lua
-- Optimized: Direct Replion access with incremental tracking, no InventoryWatcher overhead
local AutoFavoriteFish = {}
AutoFavoriteFish.__index = AutoFavoriteFish

local logger = _G.Logger and _G.Logger.new("AutoFavoriteFish") or {
    debug = function() end, info = function() end, warn = function() end, error = function() end
}

local RS = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Replion = require(RS.Packages.Replion)

-- State
local running = false
local hbConn = nil
local dataReplion = nil
local replionConns = {}

-- Config
local selectedTiers = {} -- { [tierNumber] = true }
local FAVORITE_DELAY = 0.3
local FAVORITE_COOLDOWN = 2.0

-- Cache
local fishDataCache = {} -- { [fishId] = fishData }
local tierDataCache = {} -- { [tierNumber] = tierInfo }
local inventorySnapshot = {} -- Local copy: { [uuid] = fishEntry }
local lastFavoriteTime = 0
local favoriteQueue = {}
local pendingFavorites = {} -- [uuid] = lastActionTick
local favoriteRemote = nil

-- === Init Helpers ===

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
                local success, data = pcall(function() return require(child) end)
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

-- === Fish Logic ===

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

local function shouldFavoriteFish(fishEntry)
    if not fishEntry then return false end
    local fishId = fishEntry.Id or fishEntry.id
    if not fishId then return false end
    local fishData = fishDataCache[fishId]
    if not fishData or not fishData.Tier then return false end
    return selectedTiers[fishData.Tier] == true
end

local function cooldownActive(uuid, now)
    local t = pendingFavorites[uuid]
    return t and (now - t) < FAVORITE_COOLDOWN
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

-- === Inventory Tracking ===

local function initialScan()
    if not dataReplion then return end
    
    table.clear(inventorySnapshot)
    
    local fishArray = dataReplion:Get({"Inventory", "Fishes"})
    if type(fishArray) ~= "table" then return end
    
    for _, fishEntry in ipairs(fishArray) do
        local uuid = getUUID(fishEntry)
        if uuid then
            inventorySnapshot[uuid] = fishEntry
            
            -- Queue unfavorited fish that match criteria
            if shouldFavoriteFish(fishEntry) and not isFavorited(fishEntry) then
                if not table.find(favoriteQueue, uuid) then
                    table.insert(favoriteQueue, uuid)
                end
            end
        end
    end
    
    logger:info("Initial scan complete:", table.getn(inventorySnapshot), "fishes")
end

local function onFishAdded(index, fishEntry)
    if not fishEntry then return end
    
    local uuid = getUUID(fishEntry)
    if not uuid then return end
    
    -- Add to snapshot
    inventorySnapshot[uuid] = fishEntry
    
    -- Queue if matches criteria and not favorited
    if shouldFavoriteFish(fishEntry) and not isFavorited(fishEntry) then
        local now = tick()
        if not cooldownActive(uuid, now) and not table.find(favoriteQueue, uuid) then
            table.insert(favoriteQueue, uuid)
            logger:debug("Queued new fish:", uuid)
        end
    end
end

local function onFishRemoved(index, fishEntry)
    if not fishEntry then return end
    
    local uuid = getUUID(fishEntry)
    if not uuid then return end
    
    -- Remove from snapshot
    inventorySnapshot[uuid] = nil
    
    -- Remove from queue if present
    local queueIndex = table.find(favoriteQueue, uuid)
    if queueIndex then
        table.remove(favoriteQueue, queueIndex)
    end
    
    -- Clear cooldown
    pendingFavorites[uuid] = nil
end

local function onFishArrayChanged()
    -- Fallback: full rescan if array changes unexpectedly
    logger:warn("Fish array changed, rescanning...")
    initialScan()
end

local function subscribeToInventory()
    if not dataReplion then return false end
    
    -- Clear old connections
    for _, conn in ipairs(replionConns) do
        pcall(function() conn:Disconnect() end)
    end
    table.clear(replionConns)
    
    -- Subscribe to fish array changes
    table.insert(replionConns, dataReplion:OnArrayInsert({"Inventory", "Fishes"}, function(index, value)
        pcall(onFishAdded, index, value)
    end))
    
    table.insert(replionConns, dataReplion:OnArrayRemove({"Inventory", "Fishes"}, function(index, value)
        pcall(onFishRemoved, index, value)
    end))
    
    table.insert(replionConns, dataReplion:OnChange({"Inventory", "Fishes"}, function()
        pcall(onFishArrayChanged)
    end))
    
    return true
end

-- === Queue Processing ===

local function processFavoriteQueue()
    if #favoriteQueue == 0 then return end
    
    local currentTime = tick()
    if currentTime - lastFavoriteTime < FAVORITE_DELAY then return end
    
    local uuid = table.remove(favoriteQueue, 1)
    if uuid then
        -- Double-check still in inventory and not favorited
        local fishEntry = inventorySnapshot[uuid]
        if fishEntry and shouldFavoriteFish(fishEntry) and not isFavorited(fishEntry) then
            if favoriteFish(uuid) then
                pendingFavorites[uuid] = currentTime
            end
        end
        lastFavoriteTime = currentTime
    end
end

local function mainLoop()
    if not running then return end
    processFavoriteQueue()
end

-- === Lifecycle ===

function AutoFavoriteFish:Init(guiControls)
    if not loadTierData() then return false end
    if not scanFishData() then return false end
    if not findFavoriteRemote() then return false end
    
    -- Wait for Replion
    local success = false
    Replion.Client:AwaitReplion("Data", function(data)
        dataReplion = data
        initialScan()
        subscribeToInventory()
        success = true
        logger:info("Replion initialized")
    end)
    
    -- Populate GUI
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
    
    hbConn = RunService.Heartbeat:Connect(function()
        pcall(mainLoop)
    end)
    
    logger:info("Started")
end

function AutoFavoriteFish:Stop()
    if not running then return end
    running = false
    
    if hbConn then
        hbConn:Disconnect()
        hbConn = nil
    end
    
    logger:info("Stopped")
end

function AutoFavoriteFish:Cleanup()
    self:Stop()
    
    for _, conn in ipairs(replionConns) do
        pcall(function() conn:Disconnect() end)
    end
    table.clear(replionConns)
    
    table.clear(fishDataCache)
    table.clear(tierDataCache)
    table.clear(selectedTiers)
    table.clear(favoriteQueue)
    table.clear(inventorySnapshot)
    table.clear(pendingFavorites)
    
    dataReplion = nil
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
    
    -- Re-scan inventory with new tier selection
    if running then
        initialScan()
    end
    
    logger:info("Selected tiers:", selectedTiers)
    return true
end

function AutoFavoriteFish:SetFavoriteDelay(delay)
    if type(delay) == "number" and delay >= 0.1 then
        FAVORITE_DELAY = delay
        return true
    end
    return false
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

function AutoFavoriteFish:GetInventoryCount()
    local count = 0
    for _ in pairs(inventorySnapshot) do count = count + 1 end
    return count
end

function AutoFavoriteFish:DebugFishStatus(limit)
    logger:info("=== DEBUG FISH STATUS ===")
    logger:info("Total in snapshot:", self:GetInventoryCount())
    logger:info("Queue size:", #favoriteQueue)
    
    local i = 0
    for uuid, fishEntry in pairs(inventorySnapshot) do
        i = i + 1
        if limit and i > limit then break end
        
        local fishId = fishEntry.Id or fishEntry.id
        local fishData = fishDataCache[fishId]
        local fishName = fishData and fishData.Name or "Unknown"
        
        logger:info(string.format("%d. %s (%s)", i, fishName, uuid))
        logger:info("   Is favorited:", isFavorited(fishEntry))
        
        if fishData then
            local tierInfo = tierDataCache[fishData.Tier]
            local tierName = tierInfo and tierInfo.Name or "Unknown"
            logger:info("   Tier:", tierName, "- Should favorite:", shouldFavoriteFish(fishEntry))
        end
    end
end

return AutoFavoriteFish