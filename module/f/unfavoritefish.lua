-- Fish-It/unfavoriteallfish.lua
local UnfavoriteAllFish = {}
UnfavoriteAllFish.__index = UnfavoriteAllFish

local logger = _G.Logger and _G.Logger.new("UnfavoriteAllFish") or {
    debug = function() end,
    info = function() end,
    warn = function() end,
    error = function() end
}

-- Services
local RS = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

-- Dependencies
local InventoryWatcher = loadstring(game:HttpGet("https://raw.githubusercontent.com/c3iv3r/a/refs/heads/main/utils/fishit/inventdetect3.lua"))()

-- State
local running = false
local hbConn = nil
local inventoryWatcher = nil

-- Configuration
local TICK_STEP = 0.5
local UNFAVORITE_DELAY = 0.3 -- delay between unfavorite calls
local UNFAVORITE_COOLDOWN = 2.0

-- Cache
local lastUnfavoriteTime = 0
local unfavoriteQueue = {} -- queue of fish UUIDs to unfavorite
local pendingUnfavorites = {} -- [uuid] = lastActionTick (cooldown)
local processedCount = 0

-- Remotes
local favoriteRemote = nil -- same remote as favorite, just toggles

-- === Helper Functions ===

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
        logger:info("Found FavoriteItem remote")
        return true
    end
    
    logger:warn("Failed to find FavoriteItem remote")
    return false
end

local function unfavoriteFish(uuid)
    if not favoriteRemote or not uuid then return false end
    
    local success = pcall(function()
        favoriteRemote:FireServer(uuid)
    end)
    
    if success then
        processedCount = processedCount + 1
        logger:info("Unfavorited fish:", uuid, "- Total processed:", processedCount)
    else
        logger:warn("Failed to unfavorite fish:", uuid)
    end
    
    return success
end

local function getUUID(entry)
    return entry.UUID or entry.Uuid or entry.uuid
end

local function isFavorited(entry)
    -- Check all possible favorited field locations based on InventoryController analysis
    if entry.Favorited ~= nil then return entry.Favorited end
    if entry.favorited ~= nil then return entry.favorited end
    if entry.Metadata and entry.Metadata.Favorited ~= nil then return entry.Metadata.Favorited end
    if entry.Metadata and entry.Metadata.favorited ~= nil then return entry.Metadata.favorited end
    return false
end

local function cooldownActive(uuid, now)
    local t = pendingUnfavorites[uuid]
    return t and (now - t) < UNFAVORITE_COOLDOWN
end

local function processInventory()
    if not inventoryWatcher then return end

    local fishes = inventoryWatcher:getSnapshot()
    if not fishes or #fishes == 0 then 
        logger:debug("No fish in inventory")
        return 
    end

    local now = tick()
    local foundFavorited = 0

    for _, fishEntry in ipairs(fishes) do
        -- Only unfavorite if it's currently favorited
        if isFavorited(fishEntry) then
            foundFavorited = foundFavorited + 1
            local uuid = getUUID(fishEntry)
            if uuid and not cooldownActive(uuid, now) and not table.find(unfavoriteQueue, uuid) then
                table.insert(unfavoriteQueue, uuid)
                logger:debug("Added to queue:", uuid)
            end
        end
    end

    if foundFavorited > 0 then
        logger:debug("Found", foundFavorited, "favorited fish, Queue size:", #unfavoriteQueue)
    end
end

local function processUnfavoriteQueue()
    if #unfavoriteQueue == 0 then return end

    local currentTime = tick()
    if currentTime - lastUnfavoriteTime < UNFAVORITE_DELAY then return end

    local uuid = table.remove(unfavoriteQueue, 1)
    if uuid then
        if unfavoriteFish(uuid) then
            -- mark cooldown so we don't immediately process it again
            pendingUnfavorites[uuid] = currentTime
        end
        lastUnfavoriteTime = currentTime
    end
end

local function mainLoop()
    if not running then return end
    
    processInventory()
    processUnfavoriteQueue()
end

-- === Lifecycle Methods ===

function UnfavoriteAllFish:Init(guiControls)
    logger:info("Initializing...")
    
    -- Find favorite remote
    if not findFavoriteRemote() then
        logger:error("Failed to initialize - Remote not found")
        return false
    end
    
    -- Initialize inventory watcher
    inventoryWatcher = InventoryWatcher.getShared()
    
    -- Wait for inventory watcher to be ready
    inventoryWatcher:onReady(function()
        logger:info("Inventory watcher ready")
    end)
    
    logger:info("Initialization complete")
    return true
end

function UnfavoriteAllFish:Start()
    if running then 
        logger:warn("Already running")
        return 
    end
    
    -- Reset counters
    processedCount = 0
    table.clear(unfavoriteQueue)
    table.clear(pendingUnfavorites)
    
    running = true
    
    -- Start main loop
    hbConn = RunService.Heartbeat:Connect(function()
        local success, err = pcall(mainLoop)
        if not success then
            logger:error("Error in main loop:", err)
        end
    end)
    
    logger:info("Started - Beginning to unfavorite all fish...")
end

function UnfavoriteAllFish:Stop()
    if not running then 
        logger:warn("Not running")
        return 
    end
    
    running = false
    
    -- Disconnect heartbeat
    if hbConn then
        hbConn:Disconnect()
        hbConn = nil
    end
    
    logger:info("Stopped - Total fish unfavorited:", processedCount)
end

function UnfavoriteAllFish:Cleanup()
    self:Stop()
    
    -- Clean up inventory watcher
    if inventoryWatcher then
        inventoryWatcher = nil
    end
    
    -- Clear caches and queues
    table.clear(unfavoriteQueue)
    table.clear(pendingUnfavorites)
    
    favoriteRemote = nil
    lastUnfavoriteTime = 0
    processedCount = 0
    
    logger:info("Cleanup complete")
end

-- === Getters ===

function UnfavoriteAllFish:GetQueueSize()
    return #unfavoriteQueue
end

function UnfavoriteAllFish:GetProcessedCount()
    return processedCount
end

function UnfavoriteAllFish:IsRunning()
    return running
end

-- === Debug Helpers ===

function UnfavoriteAllFish:GetFavoritedCount()
    if not inventoryWatcher then return 0 end
    
    local fishes = inventoryWatcher:getSnapshot()
    if not fishes then return 0 end
    
    local count = 0
    for _, fishEntry in ipairs(fishes) do
        if isFavorited(fishEntry) then
            count = count + 1
        end
    end
    
    return count
end

function UnfavoriteAllFish:DebugFavoritedFish(limit)
    if not inventoryWatcher then 
        logger:warn("Inventory watcher not initialized")
        return 
    end
    
    local fishes = inventoryWatcher:getSnapshot()
    if not fishes or #fishes == 0 then 
        logger:info("No fish in inventory")
        return 
    end
    
    logger:info("=== FAVORITED FISH DEBUG ===")
    local count = 0
    
    for i, fishEntry in ipairs(fishes) do
        if limit and count >= limit then break end
        
        if isFavorited(fishEntry) then
            count = count + 1
            local uuid = getUUID(fishEntry)
            local fishId = fishEntry.Id or fishEntry.id
            
            logger:info(string.format("%d. Fish ID: %s, UUID: %s", count, tostring(fishId), uuid or "no-uuid"))
            logger:info("   Favorited =", isFavorited(fishEntry))
            logger:info("")
        end
    end
    
    logger:info("Total favorited fish:", count)
end

function UnfavoriteAllFish:GetStatus()
    return {
        running = running,
        queueSize = #unfavoriteQueue,
        processedCount = processedCount,
        favoritedCount = self:GetFavoritedCount()
    }
end

return UnfavoriteAllFish