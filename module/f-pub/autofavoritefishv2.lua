-- autofavoritefishv2.lua - Favorite by fish names
local AutoFavoriteFishV2 = {}
AutoFavoriteFishV2.__index = AutoFavoriteFishV2

local logger = _G.Logger and _G.Logger.new("AutoFavoriteFishV2") or {
    debug = function() end, info = function() end, warn = function() end, error = function() end
}

local RS = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local InventoryWatcher = loadstring(game:HttpGet("https://raw.githubusercontent.com/c3iv3r/a/refs/heads/main/utils/fishit/inventdetect.lua"))()

-- State
local running = false
local hbConn = nil
local inventoryWatcher = nil
local selectedFishNames = {} -- set: { [fishName] = true }
local FAVORITE_DELAY = 0.3
local FAVORITE_COOLDOWN = 2.0

-- Cache
local fishDataCache = {} -- { [fishId] = fishData }
local lastFavoriteTime = 0
local favoriteQueue = {}
local pendingFavorites = {} -- [uuid] = lastActionTick
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

    -- Check if this fish name is selected
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

local function processInventory()
    if not inventoryWatcher then return end

    local fishes = inventoryWatcher:getSnapshotTyped("Fishes")
    if not fishes or #fishes == 0 then return end

    local now = tick()

    for _, fishEntry in ipairs(fishes) do
        if shouldFavoriteFish(fishEntry) and not isFavorited(fishEntry) then
            local uuid = getUUID(fishEntry)
            if uuid and not cooldownActive(uuid, now) and not table.find(favoriteQueue, uuid) then
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
        if favoriteFish(uuid) then
            pendingFavorites[uuid] = currentTime
        end
        lastFavoriteTime = currentTime
    end
end

local function mainLoop()
    if not running then return end
    processInventory()
    processFavoriteQueue()
end

function AutoFavoriteFishV2:Init(guiControls)
    if not scanFishData() then return false end
    if not findFavoriteRemote() then return false end

    inventoryWatcher = InventoryWatcher.new()

    inventoryWatcher:onReady(function()
        logger:info("Inventory watcher ready")
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

function AutoFavoriteFishV2:DebugFishStatus(limit)
    if not inventoryWatcher then return end

    local fishes = inventoryWatcher:getSnapshotTyped("Fishes")
    if not fishes or #fishes == 0 then return end

    logger:info("=== DEBUG FISH STATUS V2 ===")
    for i, fishEntry in ipairs(fishes) do
        if limit and i > limit then break end

        local fishId = fishEntry.Id or fishEntry.id
        local uuid = getUUID(fishEntry)
        local fishData = fishDataCache[fishId]
        local fishName = fishData and fishData.Name or "Unknown"

        logger:info(string.format("%d. %s (%s)", i, fishName, uuid or "no-uuid"))
        logger:info("   Should favorite:", shouldFavoriteFish(fishEntry))
        logger:info("   Is favorited:", isFavorited(fishEntry))
    end
end

return AutoFavoriteFishV2