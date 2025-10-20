-- ===========================
-- FISH WEBHOOK FEATURE V3 (OPTIMIZED & PATCHED)
-- Pre-caches ALL data during Init
-- Queue-based sending with retry
-- Zero freeze on fish catch
-- Async thumbnail loading (non-blocking)
-- Fixed: Thumbnail batch loading & Event connection
-- ========================

local FishWebhookV3 = {}
FishWebhookV3.__index = FishWebhookV3

local logger = _G.Logger and _G.Logger.new("Webhook") or {
    debug = function() end,
    info = function() end,
    warn = function() end,
    error = function() end
}

local HttpService = game:GetService("HttpService")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

local LocalPlayer = Players.LocalPlayer

-- ===========================
-- CONFIG
-- ===========================
local CFG = {
    DEBUG = true,
    QUEUE_PROCESS_INTERVAL = 0.5,
    RETRY_ATTEMPTS = 3,
    RETRY_DELAY = 2,
    DEDUP_TTL = 12,
    WEIGHT_DECIMALS = 2,
    THUMB_SIZE = "420x420",
    USE_LARGE_IMAGE = false,
    TARGET_EVENT = "RE/ObtainedNewFishNotification",
    INIT_TIMEOUT = 30,
    THUMB_BATCH_SIZE = 30,
    THUMB_BATCH_DELAY = 0.2
}

-- ===========================
-- STATE
-- ===========================
local state = {
    running = false,
    webhookUrl = "",
    selectedTiers = {},
    
    -- Pre-loaded caches
    fishCache = {},
    tierCache = {},
    thumbnailCache = {},
    
    -- Queue & dedup
    sendQueue = {},
    dedupCache = {},
    
    -- Connections
    connections = {},
    queueThread = nil,
    thumbnailThread = nil,
    thumbnailCancelFn = nil
}

-- ===========================
-- UTILS
-- ===========================
local function log(...) 
    if CFG.DEBUG then 
        warn("[FishWebhook-v3]", ...) 
    end 
end

local function now() 
    return os.clock() 
end

local function toIdStr(v)
    local n = tonumber(v)
    return n and tostring(n) or (v and tostring(v) or nil)
end

local function asSet(tbl)
    local set = {}
    if type(tbl) ~= "table" then return set end
    
    for _, v in ipairs(tbl) do
        if v then set[tostring(v):lower()] = true end
    end
    for k, v in pairs(tbl) do
        if type(k) ~= "number" and v then
            set[tostring(k):lower()] = true
        end
    end
    return set
end

local function extractAssetId(icon)
    if not icon then return nil end
    if type(icon) == "number" then return tostring(icon) end
    if type(icon) == "string" then
        local m = icon:match("rbxassetid://(%d+)") or icon:match("(%d+)$")
        return m
    end
    return nil
end

-- ===========================
-- HTTP
-- ===========================
local requestFn = (function()
    if syn and type(syn.request) == "function" then return syn.request end
    if http and type(http.request) == "function" then return http.request end
    if type(http_request) == "function" then return http_request end
    if type(request) == "function" then return request end
    if fluxus and type(fluxus.request) == "function" then return fluxus.request end
    return nil
end)()

local function httpRequest(params)
    if not requestFn then return nil, "no_http" end
    
    local ok, res = pcall(requestFn, params)
    if not ok then return nil, tostring(res) end
    
    local code = tonumber(res.StatusCode or res.Status) or 0
    if code < 200 or code >= 300 then
        return nil, "status_" .. code
    end
    
    return res.Body or "", nil
end

local function httpGet(url)
    return httpRequest({
        Url = url,
        Method = "GET",
        Headers = {
            ["User-Agent"] = "Mozilla/5.0",
            ["Accept"] = "application/json,*/*"
        }
    })
end

local function sendWebhook(payload)
    if not state.webhookUrl or state.webhookUrl == "" then
        return false, "no_url"
    end
    
    local body, err = httpRequest({
        Url = state.webhookUrl,
        Method = "POST",
        Headers = {
            ["Content-Type"] = "application/json",
            ["User-Agent"] = "Mozilla/5.0"
        },
        Body = HttpService:JSONEncode(payload)
    })
    
    if err then
        return false, err
    end
    
    return true, nil
end

-- ===========================
-- THUMBNAIL CACHE
-- ===========================
local function fetchThumbnailBatch(assetIds)
    if #assetIds == 0 then return {} end
    
    local ids = table.concat(assetIds, ",")
    local api = string.format(
        "https://thumbnails.roblox.com/v1/assets?assetIds=%s&size=%s&format=Png&isCircular=false",
        ids, CFG.THUMB_SIZE
    )
    
    local body, err = httpGet(api)
    if not body then return {} end
    
    local ok, data = pcall(function() return HttpService:JSONDecode(body) end)
    if not ok or not data or not data.data then return {} end
    
    local results = {}
    for _, item in ipairs(data.data) do
        if item.state == "Completed" and item.imageUrl then
            results[tostring(item.targetId)] = item.imageUrl
        end
    end
    
    return results
end

local function buildThumbnailCacheAsync(fishData)
    logger:info("Starting background thumbnail cache...")
    
    local assetIds = {}
    
    for fishId, fish in pairs(fishData) do
        local assetId = extractAssetId(fish.icon)
        if assetId and not state.thumbnailCache[assetId] then
            table.insert(assetIds, assetId)
        end
    end
    
    if #assetIds == 0 then
        logger:info("No thumbnails to fetch")
        return function() end
    end
    
    logger:info("Will fetch " .. #assetIds .. " thumbnails in background...")
    
    local isCancelled = false
    
    -- Spawn background task
    state.thumbnailThread = task.spawn(function()
        local batchSize = CFG.THUMB_BATCH_SIZE
        local totalBatches = math.ceil(#assetIds / batchSize)
        
        for i = 1, #assetIds, batchSize do
            if isCancelled then
                logger:info("Thumbnail loading cancelled")
                break
            end
            
            local batch = {}
            for j = i, math.min(i + batchSize - 1, #assetIds) do
                table.insert(batch, assetIds[j])
            end
            
            local batchNum = math.ceil(i / batchSize)
            local results = fetchThumbnailBatch(batch)
            
            for assetId, url in pairs(results) do
                state.thumbnailCache[assetId] = url
            end
            
            logger:info(string.format("Thumbnail batch %d/%d complete (%d loaded)", 
                batchNum, totalBatches, #batch))
            
            if i + batchSize < #assetIds then
                task.wait(CFG.THUMB_BATCH_DELAY)
            end
        end
        
        if not isCancelled then
            -- Fallback URLs for missing
            for _, assetId in ipairs(assetIds) do
                if not state.thumbnailCache[assetId] then
                    state.thumbnailCache[assetId] = string.format(
                        "https://www.roblox.com/asset-thumbnail/image?assetId=%s&width=420&height=420&format=png",
                        assetId
                    )
                end
            end
            
            logger:info("Background thumbnail cache COMPLETE: " .. #assetIds .. " entries")
        end
        
        state.thumbnailThread = nil
    end)
    
    -- Return cancel function
    return function()
        isCancelled = true
        if state.thumbnailThread then
            pcall(function() task.cancel(state.thumbnailThread) end)
            state.thumbnailThread = nil
        end
    end
end

local function getThumbnailUrl(icon)
    local assetId = extractAssetId(icon)
    return assetId and state.thumbnailCache[assetId] or nil
end

-- ===========================
-- DATA LOADING
-- ===========================
local function findPath(root, path)
    local cur = root
    for part in string.gmatch(path, "[^/]+") do
        cur = cur and cur:FindFirstChild(part)
    end
    return cur
end

local function loadTiers()
    logger:info("Loading tier data...")
    
    local hints = {"Tiers", "GameData/Tiers", "Data/Tiers", "Modules/Tiers"}
    local tiersModule
    
    for _, h in ipairs(hints) do
        local r = findPath(ReplicatedStorage, h)
        if r and r:IsA("ModuleScript") then
            tiersModule = r
            break
        end
    end
    
    if not tiersModule then
        for _, d in ipairs(ReplicatedStorage:GetDescendants()) do
            if d:IsA("ModuleScript") and d.Name:lower():find("tier") then
                tiersModule = d
                break
            end
        end
    end
    
    local tierData = {}
    
    if tiersModule then
        local ok, data = pcall(require, tiersModule)
        if ok and type(data) == "table" then
            tierData = data
            logger:info("Loaded tiers from: " .. tiersModule:GetFullName())
        end
    end
    
    if not next(tierData) then
        tierData = {
            [1] = {Name = "Common", Id = 1},
            [2] = {Name = "Uncommon", Id = 2},
            [3] = {Name = "Rare", Id = 3},
            [4] = {Name = "Epic", Id = 4},
            [5] = {Name = "Legendary", Id = 5},
            [6] = {Name = "Mythic", Id = 6},
            [7] = {Name = "Secret", Id = 7}
        }
        logger:info("Using fallback tier data")
    end
    
    return tierData
end

local function loadFish()
    logger:info("Loading fish data...")
    
    local hints = {"Items", "GameData/Items", "Data/Items"}
    local itemsRoot
    
    for _, h in ipairs(hints) do
        local r = findPath(ReplicatedStorage, h)
        if r then
            itemsRoot = r
            break
        end
    end
    
    itemsRoot = itemsRoot or ReplicatedStorage:FindFirstChild("Items") or ReplicatedStorage
    
    local fishData = {}
    local count = 0
    
    for _, item in ipairs(itemsRoot:GetDescendants()) do
        if item:IsA("ModuleScript") then
            local ok, data = pcall(require, item)
            if ok and type(data) == "table" then
                local itemData = data.Data or {}
                if itemData.Type == "Fishes" and itemData.Id then
                    local fishId = toIdStr(itemData.Id)
                    if fishId then
                        fishData[fishId] = {
                            id = fishId,
                            name = itemData.Name,
                            tier = itemData.Tier,
                            icon = itemData.Icon,
                            description = itemData.Description,
                            chance = type(data.Probability) == "table" and data.Probability.Chance or nil
                        }
                        count = count + 1
                    end
                end
            end
        end
    end
    
    logger:info("Loaded " .. count .. " fish from " .. itemsRoot:GetFullName())
    return fishData
end

-- ===========================
-- FORMATTING
-- ===========================
local function getTierName(tierId)
    if not tierId then return "Unknown" end
    
    for _, tier in pairs(state.tierCache) do
        if tier.Id == tierId then return tier.Name end
    end
    
    local fallback = {
        [1] = "Common", [2] = "Uncommon", [3] = "Rare", [4] = "Epic",
        [5] = "Legendary", [6] = "Mythic", [7] = "Secret"
    }
    return fallback[tierId] or tostring(tierId)
end

local function formatWeight(w)
    local n = tonumber(w)
    if not n then return tostring(w or "Unknown") end
    return string.format("%0." .. CFG.WEIGHT_DECIMALS .. "f kg", n)
end

local function formatChance(c)
    local n = tonumber(c)
    if not n or n <= 0 then return "Unknown" end
    local prob = n > 1 and n / 100 or n
    return string.format("1 in %d", math.max(1, math.floor(1 / prob + 0.5)))
end

local function formatVariant(info)
    local parts = {}
    
    if info.variantId and info.variantId ~= "" then
        table.insert(parts, "Variant: " .. tostring(info.variantId))
    end
    
    if info.shiny then
        table.insert(parts, "✨ SHINY")
    end
    
    if type(info.mutations) == "table" then
        local mut = {}
        for k, v in pairs(info.mutations) do
            if type(v) == "boolean" and v then
                table.insert(mut, tostring(k))
            elseif v ~= nil and v ~= false then
                table.insert(mut, tostring(k) .. ":" .. tostring(v))
            end
        end
        if #mut > 0 then
            table.insert(parts, "Mutations: " .. table.concat(mut, ", "))
        end
    end
    
    return #parts > 0 and table.concat(parts, " | ") or "None"
end

-- ===========================
-- DEDUP
-- ===========================
local function createSig(info)
    return table.concat({
        tostring(info.id or "?"),
        string.format("%.2f", tonumber(info.weight) or 0),
        tostring(info.tier or "?"),
        tostring(info.variantId or ""),
        tostring(info.shiny or false),
        tostring(info.uuid or "")
    }, "|")
end

local function cleanDedup()
    local t = now()
    for sig, time in pairs(state.dedupCache) do
        if (t - time) > CFG.DEDUP_TTL then
            state.dedupCache[sig] = nil
        end
    end
end

local function isDuplicate(sig)
    cleanDedup()
    if state.dedupCache[sig] then return true end
    state.dedupCache[sig] = now()
    return false
end

-- ===========================
-- FILTER
-- ===========================
local function shouldSendFish(info)
    if not next(state.selectedTiers) then return true end
    
    local tierName = getTierName(info.tier)
    if not tierName then return false end
    
    return state.selectedTiers[tierName:lower()] == true
end

-- ===========================
-- EMBED BUILDER
-- ===========================
local EMOJI = {
    fish = "<:emoji_1:1415617268511150130>",
    weight = "<:emoji_2:1415617300098449419>",
    chance = "<:emoji_3:1415617326316916787>",
    rarity = "<:emoji_4:1415617353898790993>",
    mutation = "<:emoji_5:1415617377424511027>"
}

local function buildEmbed(info)
    local function label(e, t) return string.format("%s %s", e, t) end
    local function box(v) return string.format("```%s```", tostring(v):gsub("```", "‹``")) end
    local function hide(v) return string.format("||%s||", tostring(v)) end
    
    local embed = {
        title = (info.shiny and "✨ " or "🎣 ") .. "New Catch",
        description = string.format("**Player:** %s", hide(LocalPlayer.Name)),
        color = info.shiny and 0xFFD700 or 0x030303,
        timestamp = os.date("!%Y-%m-%dT%H:%M:%SZ"),
        footer = {text = "NoctisHub | Fish-It Notifier"},
        fields = {
            {name = label(EMOJI.fish, "Fish Name"), value = box(info.name or "Unknown"), inline = false},
            {name = label(EMOJI.weight, "Weight"), value = box(formatWeight(info.weight)), inline = true},
            {name = label(EMOJI.chance, "Chance"), value = box(formatChance(info.chance)), inline = true},
            {name = label(EMOJI.rarity, "Rarity"), value = box(getTierName(info.tier)), inline = true},
            {name = label(EMOJI.mutation, "Mutations"), value = box(formatVariant(info)), inline = false}
        }
    }
    
    if info.uuid and info.uuid ~= "" then
        table.insert(embed.fields, {
            name = "🆔 UUID",
            value = box(info.uuid),
            inline = true
        })
    end
    
    local thumbUrl = getThumbnailUrl(info.icon)
    if thumbUrl then
        if CFG.USE_LARGE_IMAGE then
            embed.image = {url = thumbUrl}
        else
            embed.thumbnail = {url = thumbUrl}
        end
    end
    
    return embed
end

-- ===========================
-- QUEUE PROCESSOR
-- ===========================
local function processQueue()
    while state.running do
        task.wait(CFG.QUEUE_PROCESS_INTERVAL)
        
        if #state.sendQueue == 0 then continue end
        
        local item = table.remove(state.sendQueue, 1)
        if not item then continue end
        
        local success, err = sendWebhook({
            username = "Noctis Notifier",
            embeds = {item.embed}
        })
        
        if not success then
            item.retries = (item.retries or 0) + 1
            if item.retries < CFG.RETRY_ATTEMPTS then
                logger:info("Webhook failed, retry " .. item.retries .. ": " .. err)
                table.insert(state.sendQueue, item)
                task.wait(CFG.RETRY_DELAY)
            else
                logger:info("Webhook failed after " .. item.retries .. " retries: " .. err)
            end
        else
            logger:info("Webhook sent: " .. item.fishName)
        end
    end
end

local function queueFish(info)
    if not shouldSendFish(info) then
        logger:info("Fish tier not selected: " .. (info.name or "Unknown"))
        return
    end
    
    local sig = createSig(info)
    if isDuplicate(sig) then
        logger:info("Duplicate fish: " .. (info.name or "Unknown"))
        return
    end
    
    table.insert(state.sendQueue, {
        embed = buildEmbed(info),
        fishName = info.name or "Unknown",
        retries = 0
    })
    
    logger:info("Queued fish: " .. (info.name or "Unknown"))
end

-- ===========================
-- EVENT HANDLER
-- ===========================
local function extractFishInfo(args)
    local info = {}
    
    for i = 1, args.n or #args do
        local arg = args[i]
        
        if type(arg) == "table" then
            info.id = info.id or arg.Id or arg.ItemId or arg.TypeId or arg.FishId
            info.weight = info.weight or arg.Weight or arg.Mass or arg.Kg or arg.WeightKg
            info.variantId = info.variantId or arg.VariantId or arg.Variant
            info.variantSeed = info.variantSeed or arg.VariantSeed
            info.shiny = info.shiny or arg.Shiny
            info.favorited = info.favorited or arg.Favorited or arg.Favorite
            info.uuid = info.uuid or arg.UUID or arg.Uuid
            info.mutations = info.mutations or arg.Mutations or arg.Modifiers
            
            if arg.Data and type(arg.Data) == "table" then
                info.id = info.id or arg.Data.Id or arg.Data.ItemId
                info.weight = info.weight or arg.Data.Weight or arg.Data.Mass
            end
        elseif not info.id then
            info.id = toIdStr(arg)
        end
    end
    
    -- Instant lookup dari cache
    if info.id then
        local cached = state.fishCache[toIdStr(info.id)]
        if cached then
            info.name = info.name or cached.name
            info.tier = info.tier or cached.tier
            info.icon = info.icon or cached.icon
            info.chance = info.chance or cached.chance
            info.description = info.description or cached.description
        end
    end
    
    return info
end

local function onFishObtained(...)
    local args = table.pack(...)
    local info = extractFishInfo(args)
    
    if info.id or info.name then
        queueFish(info)
    else
        logger:info("Invalid fish data")
    end
end

-- ===========================
-- CONNECTION
-- ===========================
local function connectEvents()
    local function tryConnect(obj)
        if obj:IsA("RemoteEvent") and obj.Name == CFG.TARGET_EVENT then
            local conn = obj.OnClientEvent:Connect(onFishObtained)
            table.insert(state.connections, conn)
            logger:info("Connected to: " .. obj:GetFullName())
            return true
        end
        return false
    end
    
    -- Check existing
    for _, obj in ipairs(ReplicatedStorage:GetDescendants()) do
        if tryConnect(obj) then 
            return
        end
    end
    
    -- Wait for descendant
    local addConn = ReplicatedStorage.DescendantAdded:Connect(function(obj)
        task.wait(0.1)
        tryConnect(obj)
    end)
    table.insert(state.connections, addConn)
    
    logger:info("Waiting for " .. CFG.TARGET_EVENT .. "...")
end

-- ===========================
-- PUBLIC API
-- ===========================
function FishWebhookV3:Init()
    logger:info("=== INITIALIZING FISH WEBHOOK V3 ===")
    
    local startTime = now()
    
    -- Load tier data
    state.tierCache = loadTiers()
    logger:info("Tiers loaded")
    
    -- Load fish data
    state.fishCache = loadFish()
    logger:info("Fish loaded")
    
    -- Start background thumbnail loading (non-blocking)
    state.thumbnailCancelFn = buildThumbnailCacheAsync(state.fishCache)
    
    local elapsed = now() - startTime
    logger:info("=== INIT COMPLETE in " .. string.format("%.2f", elapsed) .. " seconds ===")
    logger:info("Fish cache: " .. (next(state.fishCache) and "OK" or "EMPTY"))
    logger:info("Tier cache: " .. (next(state.tierCache) and "OK" or "EMPTY"))
    logger:info("Thumbnail cache: Loading in background...")
    
    return true
end

function FishWebhookV3:Start(config)
    if state.running then return false end
    
    state.webhookUrl = config.webhookUrl or ""
    state.selectedTiers = asSet(config.selectedTiers or config.selectedFishTypes or {})
    
    if state.webhookUrl == "" then
        logger:info("No webhook URL")
        return false
    end
    
    state.running = true
    
    connectEvents()
    
    state.queueThread = task.spawn(processQueue)
    
    logger:info("Started - URL: " .. state.webhookUrl:sub(1, 50) .. "...")
    logger:info("Selected tiers: " .. HttpService:JSONEncode(state.selectedTiers))
    
    return true
end

function FishWebhookV3:Stop()
    if not state.running then return end
    
    state.running = false
    
    for _, conn in ipairs(state.connections) do
        pcall(function() conn:Disconnect() end)
    end
    state.connections = {}
    
    if state.queueThread then
        task.cancel(state.queueThread)
        state.queueThread = nil
    end
    
    if state.thumbnailCancelFn then
        pcall(state.thumbnailCancelFn)
        state.thumbnailCancelFn = nil
    end
    
    state.thumbnailThread = nil
    
    logger:info("Stopped")
end

function FishWebhookV3:SetWebhookUrl(url)
    state.webhookUrl = url or ""
end

function FishWebhookV3:SetSelectedTiers(tiers)
    state.selectedTiers = asSet(tiers or {})
end

function FishWebhookV3:SetSelectedFishTypes(fishTypes)
    state.selectedTiers = asSet(fishTypes or {})
end

function FishWebhookV3:TestWebhook(msg)
    if state.webhookUrl == "" then return false end
    return sendWebhook({
        username = "Noctis Notifier",
        content = msg or "🟠 Test from Fish-It v3"
    })
end

function FishWebhookV3:GetStatus()
    local thumbCount = 0
    for _ in pairs(state.thumbnailCache) do
        thumbCount = thumbCount + 1
    end
    
    return {
        running = state.running,
        webhookUrl = state.webhookUrl ~= "" and (state.webhookUrl:sub(1, 50) .. "...") or "Not set",
        selectedTiers = state.selectedTiers,
        queueSize = #state.sendQueue,
        connectionsCount = #state.connections,
        fishCacheSize = next(state.fishCache) and 1 or 0,
        tierCacheSize = next(state.tierCache) and 1 or 0,
        thumbnailCacheSize = thumbCount,
        thumbnailLoading = state.thumbnailThread ~= nil
    }
end

function FishWebhookV3:GetTierNames()
    local names = {}
    for _, tier in pairs(state.tierCache) do
        if tier.Name then table.insert(names, tier.Name) end
    end
    return names
end

function FishWebhookV3:Cleanup()
    self:Stop()
    
    state.fishCache = {}
    state.tierCache = {}
    state.thumbnailCache = {}
    state.sendQueue = {}
    state.dedupCache = {}
    
    logger:info("Cleanup complete")
end

-- Debug
function FishWebhookV3:EnableDebug() CFG.DEBUG = true end
function FishWebhookV3:DisableDebug() CFG.DEBUG = false end
function FishWebhookV3:GetFishCache() return state.fishCache end
function FishWebhookV3:GetTierCache() return state.tierCache end
function FishWebhookV3:GetSelectedTiers() return state.selectedTiers end
function FishWebhookV3:GetQueueSize() return #state.sendQueue end
function FishWebhookV3:GetThumbnailCacheSize() 
    local count = 0
    for _ in pairs(state.thumbnailCache) do count = count + 1 end
    return count
end

function FishWebhookV3:SimulateFishCatch(data)
    data = data or {
        id = "69",
        name = "Test Fish",
        weight = 1.27,
        tier = 5,
        shiny = true,
        variantId = "Galaxy",
        uuid = "test-123"
    }
    queueFish(data)
end

return FishWebhookV3