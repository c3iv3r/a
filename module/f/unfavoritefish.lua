-- unfavoritefish.lua (FINAL PATCHED)
local UnfavoriteAllFish = {}
UnfavoriteAllFish.__index = UnfavoriteAllFish

local logger = _G.Logger and _G.Logger.new("UnfavoriteAllFish") or {
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

local UNFAVORITE_DELAY = 0.3
local UNFAVORITE_COOLDOWN = 2.0

local lastUnfavoriteTime = 0
local unfavoriteQueue = {}
local pendingUnfavorites = {}
local processedCount = 0

local favoriteRemote = nil

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
        pendingUnfavorites[uuid] = tick()
        processedCount = processedCount + 1
        logger:info("Unfavorited fish:", uuid, "- Total processed:", processedCount)
    else
        logger:warn("Failed to unfavorite fish:", uuid)
    end
    
    return success
end

local function cooldownActive(uuid, now)
    local t = pendingUnfavorites[uuid]
    return t and (now - t) < UNFAVORITE_COOLDOWN
end

local function processInventory()
    if not fishWatcher then return end

    local favoritedFishes = fishWatcher:getFavoritedFishes()
    if not favoritedFishes or #favoritedFishes == 0 then 
        logger:debug("No favorited fish left")
        return 
    end

    local now = tick()

    for _, fishData in ipairs(favoritedFishes) do
        local uuid = fishData.uuid
        
        if uuid and cooldownActive(uuid, now) then
            continue
        end
        
        if not table.find(unfavoriteQueue, uuid) then
            table.insert(unfavoriteQueue, uuid)
            logger:debug("Added to queue:", uuid)
        end
    end

    logger:debug("Found", #favoritedFishes, "favorited fish, Queue size:", #unfavoriteQueue)
end

local function processUnfavoriteQueue()
    if #unfavoriteQueue == 0 then return end

    local currentTime = tick()
    if currentTime - lastUnfavoriteTime < UNFAVORITE_DELAY then return end

    local uuid = table.remove(unfavoriteQueue, 1)
    if uuid then
        local fish = fishWatcher:getFishByUUID(uuid)
        if not fish then
            lastUnfavoriteTime = currentTime
            return
        end
        
        if not fish.favorited then
            lastUnfavoriteTime = currentTime
            return
        end
        
        if unfavoriteFish(uuid) then
            -- Cooldown tracked
        end
        lastUnfavoriteTime = currentTime
    end
end

local function mainLoop()
    if not running then return end
    
    processInventory()
    processUnfavoriteQueue()
end

function UnfavoriteAllFish:Init(guiControls)
    logger:info("Initializing...")
    
    if not findFavoriteRemote() then
        logger:error("Failed to initialize - Remote not found")
        return false
    end
    
    fishWatcher = FishWatcher.getShared()
    
    fishWatcher:onReady(function()
        logger:info("Fish watcher ready")
    end)
    
    logger:info("Initialization complete")
    return true
end

function UnfavoriteAllFish:Start()
    if running then 
        logger:warn("Already running")
        return 
    end
    
    processedCount = 0
    table.clear(unfavoriteQueue)
    table.clear(pendingUnfavorites)
    
    running = true
    
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
    
    if hbConn then
        hbConn:Disconnect()
        hbConn = nil
    end
    
    logger:info("Stopped - Total fish unfavorited:", processedCount)
end

function UnfavoriteAllFish:Cleanup()
    self:Stop()
    
    if fishWatcher then
        fishWatcher = nil
    end
    
    table.clear(unfavoriteQueue)
    table.clear(pendingUnfavorites)
    
    favoriteRemote = nil
    lastUnfavoriteTime = 0
    processedCount = 0
    
    logger:info("Cleanup complete")
end

function UnfavoriteAllFish:GetQueueSize()
    return #unfavoriteQueue
end

function UnfavoriteAllFish:GetProcessedCount()
    return processedCount
end

function UnfavoriteAllFish:IsRunning()
    return running
end

function UnfavoriteAllFish:GetFavoritedCount()
    if not fishWatcher then return 0 end
    local _, totalFavorited = fishWatcher:getTotals()
    return totalFavorited
end

function UnfavoriteAllFish:DebugFavoritedFish(limit)
    if not fishWatcher then 
        logger:warn("Fish watcher not initialized")
        return 
    end
    
    fishWatcher:dumpFavorited(limit)
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