-- ===========================
-- FISH WEBHOOK FEATURE V2 (PATCHED FOR ASYNC)
-- File: fishwebhook_patched.lua
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

-- State
local isRunning = false
local webhookUrl = ""
local selectedTiers = {}
local controls = {}
local connections = {}
local fishDatabase = {}
local tierDatabase = {}
local sentCache = {}
local thumbCache = {}

-- Util Functions
local function now() return os.clock() end
local function log(...) if CONFIG.DEBUG then warn("[FishWebhook-v2-Patched]", ...) end end
local function toIdStr(v) 
    local n = tonumber(v) 
    return n and tostring(n) or (v and tostring(v) or nil) 
end

local function safeClear(t) 
    if table and table.clear then table.clear(t) else for k in pairs(t) do t[k] = nil end end 
end

local function asSet(tbl)
    local set = {}
    if type(tbl) == "table" then
        for _, v in ipairs(tbl) do
            if v ~= nil then set[tostring(v):lower()] = true end
        end
        for k, v in pairs(tbl) do
            if type(k) ~= "number" and v then
                set[tostring(k):lower()] = true
            end
        end
    end
    return set
end

-- HTTP Functions
local function getRequestFn()
    if syn and type(syn.request) == "function" then return syn.request end
    if http and type(http.request) == "function" then return http.request end
    if type(http_request) == "function" then return http_request end
    if type(request) == "function" then return request end
    if fluxus and type(fluxus.request) == "function" then return fluxus.request end
    return nil
end

local function sendWebhook(payload)
    if not webhookUrl or webhookUrl:find("XXXX/BBBB") or webhookUrl == "" then return end
    local req = getRequestFn()
    if not req then return end
    
    pcall(req, {
        Url = webhookUrl,
        Method = "POST",
        Headers = {
            ["Content-Type"] = "application/json",
            ["User-Agent"] = "Mozilla/5.0"
        },
        Body = HttpService:JSONEncode(payload)
    })
end

local function httpGet(url)
    local req = getRequestFn()
    if not req then return nil, "no_request_fn" end
    
    local ok, res = pcall(req, {
        Url = url,
        Method = "GET",
        Headers = { ["User-Agent"] = "Mozilla/5.0" }
    })
    
    if not ok then return nil, tostring(res) end
    
    local code = tonumber(res.StatusCode or res.Status) or 0
    if code < 200 or code >= 300 then return nil, "status:" .. tostring(code) end
    
    return res.Body or "", nil
end

-- Thumbnail Functions
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
    local api = string.format("https://thumbnails.roblox.com/v1/assets?assetIds=%s&size=%s&format=Png&isCircular=false", id, size)
    
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
    end
    
    local url = string.format("https://www.roblox.com/asset-thumbnail/image?assetId=%s&width=420&height=420&format=png", id)
    thumbCache[id] = url
    return url
end

-- Data Loading Functions (remains the same)
-- ... (All data loading functions like findItemsRoot, loadTierData, loadFishData are unchanged)

-- Fish Processing & Formatting (remains the same)
-- ... (All processing functions like extractFishInfo, getTierName, formatWeight are unchanged)

-- Deduplication (remains the same)
-- ...

-- Filter (remains the same)
-- ...

-- Webhook Sending Function
local function sendFishEmbed(info)
    -- ... (This function's body is unchanged)
end

-- ===========================
-- EVENT HANDLERS (PATCHED)
-- ===========================
local function onFishObtained(...)
    -- PATCHED: Wrap the entire handler in a spawned thread to prevent any blocking.
    task.spawn(function()
        local args = table.pack(...)
        local info = extractFishInfo(args)
        
        if CONFIG.DEBUG then
            log("Fish obtained - ID:", info.id or "?", "Name:", info.name or "?")
        end
        
        if info.id or info.name then
            -- No task.defer needed here as we are already in a spawned thread.
            sendFishEmbed(info)
        else
            log("Invalid fish data received")
        end
    end)
end

-- The rest of the file (connection logic, public API) remains the same.
-- ...

-- Just pasting the required functions from the original file to make it complete
local function findItemsRoot() local function findPath(root, path) local cur = root for part in string.gmatch(path, "[^/]+") do cur = cur and cur:FindFirstChild(part) end return cur end local hints = {"Items", "GameData/Items", "Data/Items"} for _, h in ipairs(hints) do local r = findPath(ReplicatedStorage, h) if r then return r end end return ReplicatedStorage:FindFirstChild("Items") or ReplicatedStorage end
local function findTiersModule() local hints = {"Tiers", "GameData/Tiers", "Data/Tiers", "Modules/Tiers"} local function findPath(root, path) local cur = root for part in string.gmatch(path, "[^/]+") do cur = cur and cur:FindFirstChild(part) end return cur end for _, h in ipairs(hints) do local r = findPath(ReplicatedStorage, h) if r and r:IsA("ModuleScript") then return r end end for _, d in ipairs(ReplicatedStorage:GetDescendants()) do if d:IsA("ModuleScript") and d.Name:lower():find("tier") then return d end end return nil end
local function loadTierData() local tiersModule = findTiersModule() if not tiersModule then return { [1] = {Name = "Common", Id = 1}, [2] = {Name = "Uncommon", Id = 2}, [3] = {Name = "Rare", Id = 3}, [4] = {Name = "Epic", Id = 4}, [5] = {Name = "Legendary", Id = 5}, [6] = {Name = "Mythic", Id = 6}, [7] = {Name = "Secret", Id = 7} } end local ok, tiersData = pcall(require, tiersModule) if not ok or type(tiersData) ~= "table" then return {} end return tiersData end
local function loadFishData() local itemsRoot = findItemsRoot() local fishData = {} local loadedCount = 0 for _, item in ipairs(itemsRoot:GetDescendants()) do if item:IsA("ModuleScript") then local ok, data = pcall(require, item) if ok and type(data) == "table" then local itemData = data.Data or {} if itemData.Type == "Fishes" and itemData.Id then local fishInfo = { id = toIdStr(itemData.Id), name = itemData.Name, tier = itemData.Tier, icon = itemData.Icon, description = itemData.Description, chance = nil } if type(data.Probability) == "table" then fishInfo.chance = data.Probability.Chance end if fishInfo.id then fishData[fishInfo.id] = fishInfo; loadedCount = loadedCount + 1 end end end end end return fishData end
local function extractFishInfo(args) local info = {} for i = 1, args.n or #args do local arg = args[i] if type(arg) == "table" then info.id = info.id or arg.Id or arg.ItemId or arg.TypeId or arg.FishId; info.weight = info.weight or arg.Weight or arg.Mass; info.shiny = info.shiny or arg.Shiny; info.uuid = info.uuid or arg.UUID; if arg.Data and type(arg.Data) == "table" then info.id = info.id or arg.Data.Id; info.weight = info.weight or arg.Data.Weight end elseif type(arg) == "number" or type(arg) == "string" then if not info.id then info.id = toIdStr(arg) end end end if info.id and fishDatabase[toIdStr(info.id)] then local fishData = fishDatabase[toIdStr(info.id)]; info.name = info.name or fishData.name; info.tier = info.tier or fishData.tier; info.icon = info.icon or fishData.icon; info.chance = info.chance or fishData.chance; info.description = info.description or fishData.description end return info end
local function getTierName(tierId) if not tierId then return "Unknown" end for _, tierInfo in pairs(tierDatabase) do if tierInfo.Id == tierId then return tierInfo.Name end end local fallback = { [1] = "Common", [2] = "Uncommon", [3] = "Rare", [4] = "Epic", [5] = "Legendary", [6] = "Mythic", [7] = "Secret" }; return fallback[tierId] or tostring(tierId) end
local function createSignature(info) return table.concat({tostring(info.id or "?"), string.format("%.2f", tonumber(info.weight) or 0), tostring(info.tier or "?"), tostring(info.uuid or "")}, "|") end
local function shouldSend(sig) local currentTime = now() for k, timestamp in pairs(sentCache) do if (currentTime - timestamp) > CONFIG.DEDUP_TTL_SEC then sentCache[k] = nil end end if sentCache[sig] then return false end; sentCache[sig] = currentTime; return true end
local function shouldSendFish(info) if not selectedTiers or next(selectedTiers) == nil then return true end local tierName = getTierName(info.tier) if not tierName then return false end return selectedTiers[tierName:lower()] == true end
function sendFishEmbed(info) if not shouldSendFish(info) then return end local sig = createSignature(info) if not shouldSend(sig) then return end local imageUrl = nil if info.icon then imageUrl = resolveIconUrl(info.icon) end local embed = { title = (info.shiny and "✨ " or "🎣 ") .. "New Catch", description = string.format("**Player:** ||%s||", LocalPlayer.Name), color = info.shiny and 0xFFD700 or 0x030303, timestamp = os.date("!%Y-%m-%dT%H:%M:%SZ"), footer = { text = "NoctisHub | Fish-It Notifier" }, fields = { { name = "Fish Name", value = string.format("```%s```", info.name or "Unknown"), inline = false }, { name = "Weight", value = string.format("```%.2f kg```", info.weight or 0), inline = true }, { name = "Rarity", value = string.format("```%s```", getTierName(info.tier)), inline = true } } }; if imageUrl then embed.thumbnail = {url = imageUrl} end sendWebhook({ username = "Noctis Notifier", embeds = {embed} }) end
local function connectToFishEvent() local function findAndConnect(obj) if obj:IsA("RemoteEvent") and obj.Name == CONFIG.TARGET_EVENT then table.insert(connections, obj.OnClientEvent:Connect(onFishObtained)); return true end return false end for _, obj in ipairs(ReplicatedStorage:GetDescendants()) do if findAndConnect(obj) then break end end table.insert(connections, ReplicatedStorage.DescendantAdded:Connect(findAndConnect)) end

function FishWebhookFeature:Init(guiControls) controls = guiControls or {}; tierDatabase = loadTierData(); fishDatabase = loadFishData(); logger:info("FishWebhook v2 (Patched) initialized"); return true end
function FishWebhookFeature:Start(config) if isRunning then return end; webhookUrl = config.webhookUrl or ""; selectedTiers = asSet(config.selectedTiers or config.selectedFishTypes or {}); if not webhookUrl or webhookUrl == "" then logger:warn("Cannot start - webhook URL not set"); return false end; isRunning = true; connectToFishEvent(); logger:info("Started FishWebhook v2 (Patched)"); return true end
function FishWebhookFeature:Stop() if not isRunning then return end; isRunning = false; for _, conn in ipairs(connections) do pcall(function() conn:Disconnect() end) end; connections = {}; logger:info("Stopped FishWebhook v2 (Patched)") end
function FishWebhookFeature:Cleanup() self:Stop(); safeClear(fishDatabase); safeClear(tierDatabase); safeClear(thumbCache); safeClear(sentCache) end
function FishWebhookFeature:SetWebhookUrl(url) webhookUrl = url or "" end
function FishWebhookFeature:SetSelectedTiers(tiers) selectedTiers = asSet(tiers or {}) end
function FishWebhookFeature:SetSelectedFishTypes(fishTypes) self:SetSelectedTiers(fishTypes) end
function FishWebhookFeature:TestWebhook(message) if not webhookUrl or webhookUrl == "" then return false end; sendWebhook({ username = "Noctis Notifier", content = message or "Test from script" }); return true end

return FishWebhookFeature
