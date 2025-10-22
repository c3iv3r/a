-- autofavoritevariant.lua (v3) - Favorite by variant/mutation
local AutoFavoriteVariant = {}
AutoFavoriteVariant.__index = AutoFavoriteVariant

local logger = _G.Logger and _G.Logger.new("AutoFavoriteVariant") or {
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

local selectedVariants = {}  -- {[variantName] = true}
local FAVORITE_DELAY = 0.3
local FAVORITE_COOLDOWN = 2.0

local variantDataCache = {}  -- {[variantName] = {Data = {Id, Name, Type, ...}}}
local variantIdToName = {}   -- {[variantId] = variantName}
local lastFavoriteTime = 0
local favoriteQueue = {}
local pendingFavorites = {}
local favoriteRemote = nil

-- ✅ Load all variant data from ReplicatedStorage.Variants
local function loadVariantData()
    local VariantsFolder = RS:FindFirstChild("Variants")
    if not VariantsFolder then
        logger:warn("Variants folder not found in ReplicatedStorage")
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

-- ✅ Find favorite remote
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

-- ✅ Check if fish should be favorited based on variant
local function shouldFavoriteFish(fishData)
    if not fishData or fishData.favorited then return false end
    
    -- Check if fish has variant/mutation
    if not fishData.mutant then return false end
    
    -- Check by variant name (case-insensitive)
    if fishData.variantName then
        for selectedName in pairs(selectedVariants) do
            if string.lower(fishData.variantName) == string.lower(selectedName) then
                return true
            end
        end
    end
    
    -- Fallback: check by variant ID
    if fishData.variantId then
        local variantName = variantIdToName[fishData.variantId]
        if variantName and selectedVariants[variantName] then
            return true
        end
    end
    
    return false
end

-- ✅ Favorite a fish by UUID
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

-- ✅ Check if UUID is in cooldown
local function cooldownActive(uuid, now)
    local t = pendingFavorites[uuid]
    return t and (now - t) < FAVORITE_COOLDOWN
end

-- ✅ Process inventory and queue fishes for favoriting
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

-- ✅ Process favorite queue with rate limiting
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

-- ✅ Main loop
local function mainLoop()
    if not running then return end
    
    processInventory()
    processFavoriteQueue()
end

-- ✅ Initialize the module
function AutoFavoriteVariant:Init(guiControls)
    if not loadVariantData() then
        logger:error("Failed to load variant data")
        return false
    end
    
    if not findFavoriteRemote() then
        logger:error("Failed to find favorite remote")
        return false
    end
    
    fishWatcher = FishWatcher.getShared()
    
    fishWatcher:onReady(function()
        logger:info("Fish watcher ready")
    end)
    
    -- Setup GUI dropdown if provided
    if guiControls and guiControls.variantDropdown then
        local variantNames = self:GetVariantNames()
        
        pcall(function()
            guiControls.variantDropdown:Reload(variantNames)
        end)
    end
    
    logger:info("AutoFavoriteVariant initialized successfully")
    return true
end

-- ✅ Start auto-favoriting
function AutoFavoriteVariant:Start(config)
    if running then 
        logger:warn("Already running")
        return 
    end
    
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
    
    logger:info("[AutoFavoriteVariant] Started")
end

-- ✅ Stop auto-favoriting
function AutoFavoriteVariant:Stop()
    if not running then 
        logger:warn("Not running")
        return 
    end
    
    running = false
    
    if hbConn then
        hbConn:Disconnect()
        hbConn = nil
    end
    
    logger:info("[AutoFavoriteVariant] Stopped")
end

-- ✅ Cleanup all resources
function AutoFavoriteVariant:Cleanup()
    self:Stop()
    
    if fishWatcher then
        fishWatcher = nil
    end
    
    table.clear(variantDataCache)
    table.clear(variantIdToName)
    table.clear(selectedVariants)
    table.clear(favoriteQueue)
    table.clear(pendingFavorites)
    
    favoriteRemote = nil
    lastFavoriteTime = 0
    
    logger:info("Cleaned up")
end

-- ✅ Set which variants to auto-favorite
function AutoFavoriteVariant:SetVariants(variantInput)
    if not variantInput then return false end
    
    table.clear(selectedVariants)
    
    if type(variantInput) == "table" then
        -- Array format: {"Shiny", "Sparkling", ...}
        if #variantInput > 0 then
            for _, variantName in ipairs(variantInput) do
                if variantDataCache[variantName] then
                    selectedVariants[variantName] = true
                end
            end
        -- Dictionary format: {Shiny = true, Sparkling = false, ...}
        else
            for variantName, enabled in pairs(variantInput) do
                if enabled and variantDataCache[variantName] then
                    selectedVariants[variantName] = true
                end
            end
        end
    end
    
    logger:info("Selected variants:", selectedVariants)

    -- Auto-start if variants selected and not running
    if next(selectedVariants) and not running then
        self:Start({ variantList = variantInput })
    end

    return true
end

-- ✅ Set favorite delay
function AutoFavoriteVariant:SetFavoriteDelay(delay)
    if type(delay) == "number" and delay >= 0.1 then
        FAVORITE_DELAY = delay
        logger:info("Favorite delay set to:", delay)
        return true
    end
    return false
end

-- ✅ Alias for SetVariants
function AutoFavoriteVariant:SetDesiredVariantsByNames(variantInput)
    return self:SetVariants(variantInput)
end

-- ✅ Get all available variant names
function AutoFavoriteVariant:GetVariantNames()
    local names = {}
    for variantName in pairs(variantDataCache) do
        table.insert(names, variantName)
    end
    table.sort(names)
    return names
end

-- ✅ Get currently selected variants
function AutoFavoriteVariant:GetSelectedVariants()
    local selected = {}
    for variantName, enabled in pairs(selectedVariants) do
        if enabled then
            table.insert(selected, variantName)
        end
    end
    table.sort(selected)
    return selected
end

-- ✅ Get favorite queue size
function AutoFavoriteVariant:GetQueueSize()
    return #favoriteQueue
end

-- ✅ Get variant statistics from inventory
function AutoFavoriteVariant:GetVariantStats()
    if not fishWatcher then return {} end
    
    local stats = {}
    local allVariants = fishWatcher:getAllVariants()
    
    for _, variant in ipairs(allVariants) do
        local variantName = variant.name
        local isSelected = selectedVariants[variantName] == true
        
        table.insert(stats, {
            name = variantName,
            id = variant.id,
            count = variant.count,
            selected = isSelected
        })
    end
    
    return stats
end

-- ✅ Debug fish status
function AutoFavoriteVariant:DebugFishStatus(limit)
    if not fishWatcher then 
        logger:warn("FishWatcher not initialized")
        return 
    end
    
    local allFishes = fishWatcher:getAllFishes()
    if not allFishes or #allFishes == 0 then 
        logger:info("No fishes in inventory")
        return 
    end
    
    logger:info("=== DEBUG FISH STATUS ===")
    local count = 0
    
    for i, fishData in ipairs(allFishes) do
        if limit and i > limit then break end
        
        -- Only show mutant fishes
        if fishData.mutant then
            count = count + 1
            logger:info(string.format("%d. %s (%s)", count, fishData.name, fishData.uuid or "no-uuid"))
            logger:info("   Variant:", fishData.variantName or "Unknown", "ID:", fishData.variantId or "?")
            logger:info("   Is favorited:", fishData.favorited)
            logger:info("   Should favorite:", shouldFavoriteFish(fishData))
            logger:info("")
        end
    end
    
    if count == 0 then
        logger:info("No mutant fishes found in inventory")
    end
end

-- ✅ Print current status
function AutoFavoriteVariant:Status()
    logger:info("=== AUTO-FAVORITE VARIANT STATUS ===")
    logger:info("Running:", running)
    logger:info("Queue size:", #favoriteQueue)
    logger:info("Selected variants:", #self:GetSelectedVariants())
    
    local stats = self:GetVariantStats()
    if #stats > 0 then
        logger:info("\n--- Variants in Inventory ---")
        for _, variant in ipairs(stats) do
            local marker = variant.selected and "★" or " "
            logger:info(string.format("%s %s: %d fish(es) [ID:%s]", 
                marker, variant.name, variant.count, tostring(variant.id)))
        end
    else
        logger:info("No variants in inventory")
    end
end

-- ✅ Quick setup presets
function AutoFavoriteVariant:SetupCommon()
    local commonVariants = {
        "Shiny",
        "Sparkling", 
        "Glossy",
        "Lunar",
        "Aurora",
        "Hexed",
        "Darkened"
    }
    
    local found = {}
    for _, name in ipairs(commonVariants) do
        if variantDataCache[name] then
            table.insert(found, name)
        end
    end
    
    if #found > 0 then
        self:SetVariants(found)
        logger:info(string.format("Common variants setup: %d/%d found", #found, #commonVariants))
    else
        logger:warn("No common variants found")
    end
    
    return #found > 0
end

function AutoFavoriteVariant:SetupAll()
    local allVariants = self:GetVariantNames()
    
    if #allVariants > 0 then
        self:SetVariants(allVariants)
        logger:info(string.format("All variants setup: %d variants", #allVariants))
    else
        logger:warn("No variants found")
    end
    
    return #allVariants > 0
end

return AutoFavoriteVariant


--[[
=== USAGE EXAMPLES ===

-- Basic initialization
local AutoFavVariant = require(script.AutoFavoriteVariant)
local autoFav = AutoFavVariant.new()

-- Initialize (required first)
if not autoFav:Init() then
    warn("Failed to initialize AutoFavoriteVariant")
    return
end

-- Method 1: Select specific variants
autoFav:SetVariants({"Shiny", "Sparkling", "Glossy"})
autoFav:Start()

-- Method 2: Use presets
autoFav:SetupCommon()  -- Auto-favorite common rare variants
autoFav:Start()

-- Method 3: Auto-favorite ALL variants
autoFav:SetupAll()
autoFav:Start()

-- Check status
autoFav:Status()

-- Debug specific fishes
autoFav:DebugFishStatus(20)  -- Show first 20 mutant fishes

-- Stop/Start
autoFav:Stop()
autoFav:Start()

-- Change delay (default 0.3s)
autoFav:SetFavoriteDelay(0.5)

-- Get info
local selectedVariants = autoFav:GetSelectedVariants()
local allVariants = autoFav:GetVariantNames()
local queueSize = autoFav:GetQueueSize()

-- Cleanup when done
autoFav:Cleanup()


=== GUI INTEGRATION ===

-- In your GUI code:
local Helpers = {}

function Helpers.getVariantNames()
    local variantNames = {}
    local VariantsFolder = ReplicatedStorage:FindFirstChild("Variants")
    if not VariantsFolder then 
        warn("Variants folder not found in ReplicatedStorage")
        return variantNames 
    end
    
    for _, item in pairs(VariantsFolder:GetChildren()) do
        if item:IsA("ModuleScript") then
            local success, moduleData = pcall(require, item)
            if success and moduleData and moduleData.Data and moduleData.Data.Type == "Variant" and moduleData.Data.Name then
                table.insert(variantNames, moduleData.Data.Name)
            end
        end
    end
    table.sort(variantNames)
    return variantNames
end

-- Initialize with GUI controls
local autoFav = AutoFavVariant.new()
autoFav:Init({
    variantDropdown = yourDropdownElement
})

-- When user selects variants from dropdown
local function onVariantSelected(selectedVariants)
    autoFav:SetVariants(selectedVariants)
    autoFav:Start()
end

]]