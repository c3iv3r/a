-- ===========================
-- FISH WEBHOOK FEATURE V2 (FIXED)
-- File: fishwebhook_v2.lua
-- Detects fish from RE/ObtainedNewFishNotification only
-- Pre-loads all fish data during Init
-- ===========================

local FishWebhookFeature = {}
FishWebhookFeature.__index = FishWebhookFeature

local logger = _G.Logger and _G.Logger.new("FishWebhook") or {
    debug = function() end,
    info = function() end,
    warn = function() end,
    error = function() end
}

-- Services
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local HttpService = game:GetService("HttpService")
local LocalPlayer = Players.LocalPlayer

-- Configuration
local CONFIG = {
    DEBUG = true,
    WEIGHT_DECIMALS = 2,
    DEDUP_TTL_SEC = 12.0,
    USE_LARGE_IMAGE = false,
    THUMB_SIZE = "420x420",
    TARGET_EVENT = "RE/ObtainedNewFishNotification"
}

-- Feature state
local isRunning = false
local webhookUrl = ""
local selectedTiers = {}
local controls = {}

-- Internal state
local connections = {}
local fishDatabase = {} -- Pre-loaded fish data
local tierDatabase = {} -- Pre-loaded tier data
local sentCache = {} -- Deduplication cache

-- Caches
local thumbCache = {}

-- ===========================
-- UTILITY FUNCTIONS
-- ===========================
local function now() return os.clock() end
local function log(...) if CONFIG.DEBUG then warn("[FishWebhook-v2]", ...) end end
local function toIdStr(v) 
    local n = tonumber(v) 
    return n and tostring(n) or (v and tostring(v) or nil) 
end

local function safeClear(t) 
    if table and table.clear then 
        table.clear(t) 
    else 
        for k in pairs(t) do t[k] = nil end 
    end 
end

local function asSet(tbl)
    local set = {}
    if type(tbl) == "table" then
        -- Array form
        for _, v in ipairs(tbl) do
            if v ~= nil then set[tostring(v):lower()] = true end
        end
        -- Map form
        for k, v in pairs(tbl) do
            if type(k) ~= "number" and v then
                set[tostring(k):lower()] = true
            end
        end
    end
    return set
end

-- ===========================
-- HTTP FUNCTIONS
-- ===========================
local function getRequestFn()
    if syn and type(syn.request) == "function" then return syn.request end
    if http and type(http.request) == "function" then return http.request end
    if type(http_request) == "function" then return http_request end
    if type(request) == "function" then return request end
    if fluxus and type(fluxus.request) == "function" then return fluxus.request end
    return nil
end

local function sendWebhook(payload)
    if not webhookUrl or webhookUrl:find("XXXX/BBBB") or webhookUrl == "" then
        log("WEBHOOK_URL not set or invalid")
        return
    end
    
    local req = getRequestFn()
    if not req then 
        log("No HTTP backend available")
        return 
    end
    
    local ok, res = pcall(req, {
        Url = webhookUrl,
        Method = "POST",
        Headers = {
            ["Content-Type"] = "application/json",
            ["User-Agent"] = "Mozilla/5.0",
            ["Accept"] = "*/*"
        },
        Body = HttpService:JSONEncode(payload)
    })
    
    if not ok then 
        log("HTTP request error:", tostring(res))
        return 
    end
    
    local code = tonumber(res.StatusCode or res.Status) or 0
    if code < 200 or code >= 300 then
        log("HTTP status:", code, "body:", tostring(res.Body))
    else
        log("Webhook sent successfully (", code, ")")
    end
end

local function httpGet(url)
    local req = getRequestFn()
    if not req then return nil, "no_request_fn" end
    
    local ok, res = pcall(req, {
        Url = url,
        Method = "GET",
        Headers = {
            ["User-Agent"] = "Mozilla/5.0",
            ["Accept"] = "application/json,*/*"
        }
    })
    
    if not ok then return nil, tostring(res) end
    
    local code = tonumber(res.StatusCode or res.Status) or 0
    if code < 200 or code >= 300 then
        return nil, "status:" .. tostring(code)
    end
    
    return res.Body or "", nil
end

-- ===========================
-- THUMBNAIL FUNCTIONS
-- ===========================
local function extractAssetId(icon)
    if not icon then return nil end
    if type(icon) == "number" then return tostring(icon) end
    if type(icon) == "string" then
        local m = icon:match("rbxassetid://(%d+)")
        if m then return m end
        local n = icon:match("(%d+)$")
        if n then return n end
    end
    return nil
end

local function resolveIconUrl(icon)
    local id = extractAssetId(icon)
    if not id then return nil end
    
    if thumbCache[id] then return thumbCache[id] end
    
    local size = CONFIG.THUMB_SIZE or "420x420"
    local api = string.format(
        "https://thumbnails.roblox.com/v1/assets?assetIds=%s&size=%s&format=Png&isCircular=false", 
        id, size
    )
    
    local body, err = httpGet(api)
    if body then
        local ok, data = pcall(function() return HttpService:JSONDecode(body) end)
        if ok and data and data.data and data.data[1] then
            local d = data.data[1]
            if d.state == "Completed" and d.imageUrl and #d.imageUrl > 0 then
                thumbCache[id] = d.imageUrl
                return d.imageUrl
            end
        end
    else
        log("Thumbnail API failed:", err or "unknown")
    end
    
    local url = string.format(
        "https://www.roblox.com/asset-thumbnail/image?assetId=%s&width=420&height=420&format=png", 
        id
    )
    thumbCache[id] = url
    return url
end

-- ===========================
-- DATA LOADING FUNCTIONS
-- ===========================
local function findItemsRoot()
    local function findPath(root, path)
        local cur = root
        for part in string.gmatch(path, "[^/]+") do
            cur = cur and cur:FindFirstChild(part)
        end
        return cur
    end
    
    local hints = {"Items", "GameData/Items", "Data/Items"}
    for _, h in ipairs(hints) do
        local r = findPath(ReplicatedStorage, h)
        if r then return r end
    end
    
    return ReplicatedStorage:FindFirstChild("Items") or ReplicatedStorage
end

local function findTiersModule()
    -- Look for Tiers module in common locations
    local hints = {"Tiers", "GameData/Tiers", "Data/Tiers", "Modules/Tiers"}
    
    local function findPath(root, path)
        local cur = root
        for part in string.gmatch(path, "[^/]+") do
            cur = cur and cur:FindFirstChild(part)
        end
        return cur
    end
    
    for _, h in ipairs(hints) do
        local r = findPath(ReplicatedStorage, h)
        if r and r:IsA("ModuleScript") then return r end
    end
    
    -- Fallback: search descendants
    for _, d in ipairs(ReplicatedStorage:GetDescendants()) do
        if d:IsA("ModuleScript") and d.Name:lower():find("tier") then
            return d
        end
    end
    
    return nil
end

local function loadTierData()
    local tiersModule = findTiersModule()
    if not tiersModule then
        log("Tiers module not found, using fallback")
        return {
            [1] = {Name = "Common", Id = 1},
            [2] = {Name = "Uncommon", Id = 2},
            [3] = {Name = "Rare", Id = 3},
            [4] = {Name = "Epic", Id = 4},
            [5] = {Name = "Legendary", Id = 5},
            [6] = {Name = "Mythic", Id = 6},
            [7] = {Name = "Secret", Id = 7},
        }
    end
    
    local ok, tiersData = pcall(require, tiersModule)
    if not ok or type(tiersData) ~= "table" then
        log("Failed to load tiers module:", tostring(tiersData))
        return {}
    end
    
    log("Loaded tiers data from:", tiersModule:GetFullName())
    return tiersData
end

local function loadFishData()
    local itemsRoot = findItemsRoot()
    local fishData = {}
    local loadedCount = 0
    
    for _, item in ipairs(itemsRoot:GetDescendants()) do
        if item:IsA("ModuleScript") then
            local ok, data = pcall(require, item)
            if ok and type(data) == "table" then
                local itemData = data.Data or {}
                if itemData.Type == "Fishes" and itemData.Id then
                    local fishInfo = {
                        id = toIdStr(itemData.Id),
                        name = itemData.Name,
                        tier = itemData.Tier,
                        icon = itemData.Icon,
                        description = itemData.Description,
                        chance = nil
                    }
                    
                    -- Extract probability if available
                    if type(data.Probability) == "table" then
                        fishInfo.chance = data.Probability.Chance
                    end
                    
                    if fishInfo.id then
                        fishData[fishInfo.id] = fishInfo
                        loadedCount = loadedCount + 1
                    end
                end
            end
        end
    end
    
    log("Loaded", loadedCount, "fish entries from", itemsRoot:GetFullName())
    return fishData
end

-- ===========================
-- FISH PROCESSING FUNCTIONS
-- ===========================
local function extractFishInfo(args)
    local info = {}
    
    if CONFIG.DEBUG then
        log("Processing ObtainedNewFishNotification with", args.n or #args, "args")
    end
    
    -- Process each argument
    for i = 1, args.n or #args do
        local arg = args[i]
        if type(arg) == "table" then
            -- Extract data from table argument
            info.id = info.id or arg.Id or arg.ItemId or arg.TypeId or arg.FishId
            info.weight = info.weight or arg.Weight or arg.Mass or arg.Kg or arg.WeightKg
            info.variantId = info.variantId or arg.VariantId or arg.Variant
            info.variantSeed = info.variantSeed or arg.VariantSeed
            info.shiny = info.shiny or arg.Shiny
            info.favorited = info.favorited or arg.Favorited or arg.Favorite
            info.uuid = info.uuid or arg.UUID or arg.Uuid
            info.mutations = info.mutations or arg.Mutations or arg.Modifiers
            
            -- Check nested data
            if arg.Data and type(arg.Data) == "table" then
                info.id = info.id or arg.Data.Id or arg.Data.ItemId
                info.weight = info.weight or arg.Data.Weight or arg.Data.Mass
            end
        elseif type(arg) == "number" or type(arg) == "string" then
            if not info.id then
                info.id = toIdStr(arg)
            end
        end
    end
    
    -- Get fish data from pre-loaded database
    if info.id and fishDatabase[toIdStr(info.id)] then
        local fishData = fishDatabase[toIdStr(info.id)]
        info.name = info.name or fishData.name
        info.tier = info.tier or fishData.tier
        info.icon = info.icon or fishData.icon
        info.chance = info.chance or fishData.chance
        info.description = info.description or fishData.description
    end
    
    return info
end

-- ===========================
-- FORMATTING FUNCTIONS
-- ===========================
local function getTierName(tierId)
    if not tierId then return "Unknown" end
    
    for _, tierInfo in pairs(tierDatabase) do
        if tierInfo.Id == tierId then
            return tierInfo.Name
        end
    end
    
    -- Fallback
    local fallback = {
        [1] = "Common", [2] = "Uncommon", [3] = "Rare", [4] = "Epic",
        [5] = "Legendary", [6] = "Mythic", [7] = "Secret"
    }
    return fallback[tierId] or tostring(tierId)
end

local function formatWeight(weight)
    local n = tonumber(weight)
    if not n then return (weight and tostring(weight)) or "Unknown" end
    return string.format("%0." .. tostring(CONFIG.WEIGHT_DECIMALS) .. "f kg", n)
end

local function formatChance(chance)
    local n = tonumber(chance)
    if not n or n <= 0 then return "Unknown" end
    
    local prob = n > 1 and n / 100.0 or n
    local oneIn = math.max(1, math.floor((1 / prob) + 0.5))
    return string.format("1 in %d", oneIn)
end

local function formatVariant(info)
    local parts = {}
    
    if info.variantId and info.variantId ~= "" then
        table.insert(parts, "Variant: " .. tostring(info.variantId))
    end
    
    if info.shiny then
        table.insert(parts, "✨ SHINY")
    end
    
    if info.mutations and type(info.mutations) == "table" then
        local mutations = {}
        for k, v in pairs(info.mutations) do
            if type(v) == "boolean" and v then
                table.insert(mutations, tostring(k))
            elseif v ~= nil and v ~= false then
                table.insert(mutations, tostring(k) .. ":" .. tostring(v))
            end
        end
        if #mutations > 0 then
            table.insert(parts, "Mutations: " .. table.concat(mutations, ", "))
        end
    end
    
    return (#parts > 0) and table.concat(parts, " | ") or "None"
end

-- ===========================
-- DEDUPLICATION FUNCTIONS
-- ===========================
local function createSignature(info)
    local id = info.id and tostring(info.id) or "?"
    local weight = info.weight and string.format("%.2f", tonumber(info.weight) or 0) or "?"
    local tier = tostring(info.tier or "?")
    local variant = tostring(info.variantId or "")
    local shiny = tostring(info.shiny or false)
    local uuid = tostring(info.uuid or "")
    
    return table.concat({id, weight, tier, variant, shiny, uuid}, "|")
end

local function shouldSend(sig)
    -- Clean old entries
    local currentTime = now()
    for k, timestamp in pairs(sentCache) do
        if (currentTime - timestamp) > CONFIG.DEDUP_TTL_SEC then
            sentCache[k] = nil
        end
    end
    
    -- Check if already sent
    if sentCache[sig] then return false end
    sentCache[sig] = currentTime
    return true
end

-- ===========================
-- FILTER FUNCTIONS (FIXED)
-- ===========================
local function shouldSendFish(info)
    -- If no tiers selected, send all fish
    if not selectedTiers or next(selectedTiers) == nil then
        log("No tiers selected, sending all fish")
        return true
    end
    
    -- Get tier name for this fish
    local tierName = getTierName(info.tier)
    if not tierName then
        log("No tier name found for tier ID:", tostring(info.tier))
        return false
    end
    
    -- Check if this tier is selected (case-insensitive)
    local tierNameLower = tierName:lower()
    local isSelected = selectedTiers[tierNameLower]
    
    if CONFIG.DEBUG then
        log("Fish:", info.name or "Unknown", 
            "Tier:", tierName, 
            "Selected:", tostring(isSelected),
            "SelectedTiers:", HttpService:JSONEncode(selectedTiers))
    end
    
    return isSelected == true
end

-- ===========================
-- WEBHOOK SENDING FUNCTION
-- ===========================
local function sendFishEmbed(info)
    -- Check if we should send this fish
    if not shouldSendFish(info) then
        log("Fish not in selected tiers, skipping:", info.name or "Unknown")
        return
    end
    
    -- Check deduplication
    local sig = createSignature(info)
    if not shouldSend(sig) then
        log("Duplicate fish detected, skipping:", info.name or "Unknown")
        return
    end
    
    -- Get image URL
    local imageUrl = nil
    if info.icon then
        imageUrl = resolveIconUrl(info.icon)
    end
    
    -- Discord emojis
    local EMOJI = {
        fish     = "<:emoji_1:1415617268511150130>",
        weight   = "<:emoji_2:1415617300098449419>",
        chance   = "<:emoji_3:1415617326316916787>",
        rarity   = "<:emoji_4:1415617353898790993>",
        mutation = "<:emoji_5:1415617377424511027>"
    }
    
    local function label(icon, text) 
        return string.format("%s %s", icon or "", text or "") 
    end
    
    local function box(v)
        v = v == nil and "Unknown" or tostring(v)
        v = v:gsub("```", "‹``")
        return string.format("```%s```", v)
    end
    
    local function hide(v)
        v = v == nil and "Unknown" or tostring(v)
        return string.format("||%s||", v)
    end
    
    -- Create embed
    local embed = {
        title = (info.shiny and "✨ " or "🟠 ") .. "New Catch",
        description = string.format("**Player:** %s", hide(LocalPlayer.Name)),
        color = info.shiny and 0xFFD700 or 0x030303,
        timestamp = os.date("!%Y-%m-%dT%H:%M:%SZ"),
        footer = { text = "NoctisHub | Fish-It Notifier v2" },
        fields = {
            { name = label(EMOJI.fish, "Fish Name"),     value = box(info.name or "Unknown Fish"),       inline = false },
            { name = label(EMOJI.weight, "Weight"),      value = box(formatWeight(info.weight)),         inline = true  },
            { name = label(EMOJI.chance, "Chance"),      value = box(formatChance(info.chance)),         inline = true  },
            { name = label(EMOJI.rarity, "Rarity"),      value = box(getTierName(info.tier)),            inline = true  },
            { name = label(EMOJI.mutation, "Variant"),   value = box(formatVariant(info)),               inline = false },
        }
    }
    
    -- Add UUID if available
    if info.uuid and info.uuid ~= "" then
        table.insert(embed.fields, { 
            name = "🆔 UUID", 
            value = box(info.uuid), 
            inline = true 
        })
    end
    
    -- Set image
    if imageUrl then
        if CONFIG.USE_LARGE_IMAGE then
            embed.image = {url = imageUrl}
        else
            embed.thumbnail = {url = imageUrl}
        end
    end
    
    -- Send webhook
    sendWebhook({ 
        username = "Noctis Notifier v2", 
        embeds = {embed} 
    })
    
    log("Fish notification sent:", info.name or "Unknown")
end

-- ===========================
-- EVENT HANDLERS
-- ===========================
local function onFishObtained(...)
    local args = table.pack(...)
    local info = extractFishInfo(args)
    
    if CONFIG.DEBUG then
        log("Fish obtained - ID:", info.id or "?", "Name:", info.name or "?", "Weight:", info.weight or "?")
    end
    
    if info.id or info.name then
        task.defer(sendFishEmbed, info)
    else
        log("Invalid fish data received")
    end
end

-- ===========================
-- CONNECTION FUNCTIONS
-- ===========================
local function connectToFishEvent()
    -- Look for the target RemoteEvent
    local function findAndConnect(obj)
        if obj:IsA("RemoteEvent") and obj.Name == CONFIG.TARGET_EVENT then
            table.insert(connections, obj.OnClientEvent:Connect(onFishObtained))
            log("Connected to:", obj:GetFullName())
            return true
        end
        return false
    end
    
    -- Check existing objects
    for _, obj in ipairs(ReplicatedStorage:GetDescendants()) do
        if findAndConnect(obj) then break end
    end
    
    -- Listen for new objects
    table.insert(connections, ReplicatedStorage.DescendantAdded:Connect(findAndConnect))
end

-- ===========================
-- MAIN FEATURE FUNCTIONS (FIXED)
-- ===========================
function FishWebhookFeature:Init(guiControls)
    controls = guiControls or {}
    
    log("Initializing FishWebhook v2...")
    
    -- Load tier database
    tierDatabase = loadTierData()
    log("Loaded", #tierDatabase, "tier definitions")
    
    -- Load fish database  
    fishDatabase = loadFishData()
    log("Loaded", #fishDatabase, "fish definitions")
    
    logger:info("FishWebhook v2 initialized successfully")
    return true
end

function FishWebhookFeature:Start(config)
    if isRunning then return end
    
    webhookUrl = config.webhookUrl or ""
    -- FIXED: Handle both parameter names for compatibility
    selectedTiers = asSet(config.selectedTiers or config.selectedFishTypes or {})
    
    if not webhookUrl or webhookUrl == "" then
        logger:warn("Cannot start - webhook URL not set")
        return false
    end
    
    isRunning = true
    
    -- Connect to fish events
    connectToFishEvent()
    
    logger:info("Started FishWebhook v2")
    logger:info("Webhook URL:", webhookUrl:sub(1, 50) .. "...")
    logger:info("Selected tiers:", HttpService:JSONEncode(selectedTiers))
    
    return true
end

function FishWebhookFeature:Stop()
    if not isRunning then return end
    
    isRunning = false
    
    -- Disconnect all connections
    for _, conn in ipairs(connections) do
        pcall(function() conn:Disconnect() end)
    end
    connections = {}
    
    logger:info("Stopped FishWebhook v2")
end

function FishWebhookFeature:SetWebhookUrl(url)
    webhookUrl = url or ""
    log("Webhook URL updated")
end

-- FIXED: Add both method names for compatibility
function FishWebhookFeature:SetSelectedTiers(tiers)
    selectedTiers = asSet(tiers or {})
    log("Selected tiers updated:", HttpService:JSONEncode(selectedTiers))
end

function FishWebhookFeature:SetSelectedFishTypes(fishTypes)
    -- This is for GUI compatibility - same as SetSelectedTiers
    selectedTiers = asSet(fishTypes or {})
    log("Selected fish types updated:", HttpService:JSONEncode(selectedTiers))
end

function FishWebhookFeature:TestWebhook(message)
    if not webhookUrl or webhookUrl == "" then
        logger:warn("Cannot test - webhook URL not set")
        return false
    end
    
    sendWebhook({ 
        username = "Noctis Notifier v2", 
        content = message or "🟠 Webhook test from Fish-It script v2" 
    })
    return true
end

function FishWebhookFeature:GetStatus()
    return {
        running = isRunning,
        webhookUrl = webhookUrl ~= "" and (webhookUrl:sub(1, 50) .. "...") or "Not set",
        selectedTiers = selectedTiers,
        connectionsCount = #connections,
        fishDatabaseCount = next(fishDatabase) and 1 or 0,
        tierDatabaseCount = next(tierDatabase) and 1 or 0,
        detector = CONFIG.TARGET_EVENT
    }
end

function FishWebhookFeature:GetTierNames()
    local tierNames = {}
    for _, tierInfo in pairs(tierDatabase) do
        if tierInfo.Name then
            table.insert(tierNames, tierInfo.Name)
        end
    end
    return tierNames
end

function FishWebhookFeature:Cleanup()
    logger:info("Cleaning up FishWebhook v2...")
    self:Stop()
    controls = {}
    
    -- Clear all caches and databases
    safeClear(fishDatabase)
    safeClear(tierDatabase)
    safeClear(thumbCache)
    safeClear(sentCache)
end

-- ===========================
-- DEBUG FUNCTIONS
-- ===========================
function FishWebhookFeature:EnableDebug()
    CONFIG.DEBUG = true
    log("Debug mode enabled")
end

function FishWebhookFeature:DisableDebug()
    CONFIG.DEBUG = false
end

function FishWebhookFeature:SimulateFishCatch(testData)
    testData = testData or {
        id = "69",
        name = "Test Fish",
        weight = 1.27,
        tier = 5,
        shiny = true,
        variantId = "Galaxy",
        uuid = "test-uuid-123"
    }
    
    sendFishEmbed(testData)
    log("Simulated fish catch sent")
end

function FishWebhookFeature:GetFishDatabase()
    return fishDatabase
end

function FishWebhookFeature:GetTierDatabase()
    return tierDatabase
end

-- ADDED: Debug method to check current selected tiers
function FishWebhookFeature:GetSelectedTiers()
    return selectedTiers
end

return FishWebhookFeature