-- autofavoritefishv2_patched.lua - Favorite by fish names (with incremental inventory detection)
local AutoFavoriteFishV2 = {}
AutoFavoriteFishV2.__index = AutoFavoriteFishV2

local logger = _G.Logger and _G.Logger.new("AutoFavoriteFishV2") or {
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
local selectedFishNames = {} -- set: { [fishName] = true }
local FAVORITE_DELAY = 0.3
local FAVORITE_COOLDOWN = 2.0

-- Cache
local fishDataCache = {} -- { [fishId] = fishData }
local inventorySnapshot = {} -- Local copy: { [uuid] = fishEntry }
local lastFavoriteTime = 0
local favoriteQueue = {}
local pendingFavorites = {} -- [uuid] = lastActionTick
local favoriteRemote = nil

-- === Init Helpers ===

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
                    if fishData.Type == "Fishes" and fishData.Id and fishData.Name then
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
    if not fishData or not fishData.Name then return false end

    -- Check if this fish name is selected
    return selectedFishNames[fishData.Name] == true
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

-- === Inventory Tracking (Incremental) ===

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

    -- Subscribe to fish array changes (INCREMENTAL)
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

function AutoFavoriteFishV2:Init(guiControls)
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

    -- Populate dropdown with fish names
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

    hbConn = RunService.Heartbeat:Connect(function()
        pcall(mainLoop)
    end)

    logger:info("AutoFavoriteFishV2 Started")
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

    for _, conn in ipairs(replionConns) do
        pcall(function() conn:Disconnect() end)
    end
    table.clear(replionConns)

    table.clear(fishDataCache)
    table.clear(selectedFishNames)
    table.clear(favoriteQueue)
    table.clear(inventorySnapshot)
    table.clear(pendingFavorites)

    dataReplion = nil
    favoriteRemote = nil
    lastFavoriteTime = 0

    logger:info("AutoFavoriteFishV2 Cleaned up")
end

function AutoFavoriteFishV2:SetSelectedFishNames(fishInput)
    if not fishInput then return false end

    table.clear(selectedFishNames)

    if type(fishInput) == "table" then
        if #fishInput > 0 then
            -- Array format
            for _, fishName in ipairs(fishInput) do
                selectedFishNames[fishName] = true
            end
        else
            -- Set format
            for fishName, enabled in pairs(fishInput) do
                if enabled then
                    selectedFishNames[fishName] = true
                end
            end
        end
    end

    -- Re-scan inventory with new selection
    if running then
        initialScan()
    end

    logger:info("Selected fish names:", selectedFishNames)
    return true
end

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

function AutoFavoriteFishV2:GetInventoryCount()
    local count = 0
    for _ in pairs(inventorySnapshot) do count = count + 1 end
    return count
end

function AutoFavoriteFishV2:DebugFishStatus(limit)
    logger:info("=== DEBUG FISH STATUS V2 ===")
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
        logger:info("   Should favorite:", shouldFavoriteFish(fishEntry))
    end
end

return AutoFavoriteFishV2