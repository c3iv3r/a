-- autoquest.lua
-- API: Init(controls), Start(opts?), Stop(), Cleanup()
-- Controls expected:
--   controls.dropdown  : dropdown control (quest-line selector)
--   controls.labels    : array of label controls (1..N)
--   controls.toggle    : toggle control (for sync if needed)

local AutoQuest = {}
AutoQuest.__index = AutoQuest

-- ===== Services & Game Modules =====
local RS         = game:GetService("ReplicatedStorage")
local Players    = game:GetService("Players")
local RunService = game:GetService("RunService")
local LP         = Players.LocalPlayer

local Replion       = require(RS.Packages.Replion)
local QuestList     = require(RS.Shared.Quests.QuestList)
local QuestUtility  = require(RS.Shared.Quests.QuestUtility)

-- ===== Feature dependencies (looked up by your FeatureManager) =====
local FeatureManager = _G.FeatureManager  -- set by your main script
local AutoFish, AutoSell, TeleIsland

-- ===== Replion Data store =====
local DATA = Replion.Client:WaitReplion("Data")

-- ===== State =====
local controls = nil
local running  = false
local opId     = 0
local conn     = nil    -- progress listener
local owned = { autofish=false, autosell=false } -- ownership flags

-- ===== Utils =====
local function getQuestLinesNonPrimary()
    local out = {}
    for name, def in pairs(QuestList) do
        if type(def) == "table" and def.Forever and name ~= "Primary" then
            table.insert(out, name)
        end
    end
    table.sort(out)
    return out
end

local function getReplionPath(questLine)
    local def = QuestList[questLine]
    return (def and def.ReplionPath) or questLine
end

local function safeSetDropdownValues(dd, values)
    if not dd then return end
    -- Try common method names used by your GUI libs
    if dd.SetValues then dd:SetValues(values) return end
    if dd.SetValue and type(values)=="table" then
        -- Some libs expect direct property + Refresh
        pcall(function() dd.Values = values end)
        pcall(function() dd:SetValue(values[1]) end)
        return
    end
    pcall(function() dd.Values = values end)
    if dd.Refresh then pcall(function() dd:Refresh() end) end
end

local function setLabelText(label, text)
    if not label then return end
    if label.SetText then label:SetText(text) else
        -- fallback
        pcall(function() label.Text = text end)
    end
end

local function clearAllLabels()
    if not controls or not controls.labels then return end
    for _, lbl in ipairs(controls.labels) do
        setLabelText(lbl, "")
    end
end

local function getStateMapForLine(questLine)
    local path = getReplionPath(questLine)
    local avail = DATA:Get({path, "Available"})
    local map = {}
    if avail and avail.Forever and avail.Forever.Quests then
        for _, q in ipairs(avail.Forever.Quests) do
            if q.QuestId ~= nil then
                map[q.QuestId] = q
            end
        end
    end
    return map
end

local function buildProgressLines(questLine)
    local def = QuestList[questLine]
    if not def or not def.Forever then return {}, 0 end
    local stateById = getStateMapForLine(questLine)
    local lines, total = {}, 0
    for idx, sub in ipairs(def.Forever) do
        local qid = sub.QuestId or idx
        local st  = stateById[qid]
        local cur = (st and st.Progress) or 0
        local req = QuestUtility.GetQuestValue(DATA, sub) -- penting: target yg akurat
        local name = tostring(sub.DisplayName or ("Quest "..qid))
        local s = string.format("%d) %s — %s / %s", idx, name, tostring(cur), tostring(req))
        table.insert(lines, {text=s, qid=qid, cur=cur, req=req, def=sub, state=st})
        total += 1
    end
    return lines, total
end

local function renderProgressSimple(questLine)
    local lines, total = buildProgressLines(questLine)
    if not controls or not controls.labels then return end
    local maxL = #controls.labels
    for i=1, maxL do
        local lbl = controls.labels[i]
        local item = lines[i]
        if item then setLabelText(lbl, item.text)
        else setLabelText(lbl, "") end
    end
    local extra = total - maxL
    if extra > 0 then
        setLabelText(controls.labels[maxL], ("(+%d lagi...)"):format(extra))
    end
    return lines
end

-- ===== Planner (heuristik easy-first) =====
local function classifyAndScore(sub)
    local key = sub.Arguments and sub.Arguments.key
    local cond = sub.conditions or {}
    local score = 50
    local reason = {}

    local function push(r) table.insert(reason, r) end

    if key == "EarnCoins" then
        score = 1; push("EarnCoins (disambi AutoSell)")
    elseif key == "CatchRareTreasureRoom" then
        score = 2; push("Treasure Room")
    elseif key == "CatchFish" then
        local tier = cond.Tier
        local name = cond.Name
        local area = cond.AreaName
        if name then
            score = 7; push("Name-specific (RNG tinggi)")
        elseif tier ~= nil then
            if tier >= 7 then score = 6; push("Tier SECRET/7")
            elseif tier >= 6 then score = 4; push("Tier Mythic/6")
            elseif tier >= 4 then score = 3; push("Tier Epic/4")
            else score = 5; push("Tier rendah") end
        else
            score = 9; push("Generic catch (grind)")
        end
        if area then score = score - 1; push("Area jelas") end
    else
        score = 5; push("Unknown type (default)")
    end

    -- modifier: target kecil => lebih mudah
    local reqOk, req = pcall(function() return QuestUtility.GetQuestValue(DATA, sub) end)
    if reqOk and tonumber(req) and req <= 10 then
        score = score - 1; push("Target kecil")
    end

    return score, table.concat(reason, " · ")
end

local function planSubquests(questLine)
    local def = QuestList[questLine]
    local items = {}
    if not def or not def.Forever then return items end
    for idx, sub in ipairs(def.Forever) do
        local score, why = classifyAndScore(sub)
        table.insert(items, {idx=idx, sub=sub, score=score, why=why})
    end
    table.sort(items, function(a,b) return a.score < b.score end)
    return items
end

-- ===== Arrival polling after teleport =====
local function awaitArrived(targetCF, timeout)
    timeout = timeout or 4
    local start = tick()
    while tick() - start < timeout do
        local char = LP.Character
        local root = char and char.PrimaryPart
        if root and typeof(targetCF)=="CFrame" then
            local d = (root.Position - targetCF.Position).Magnitude
            if d < 12 then return true end
        end
        RunService.Heartbeat:Wait()
    end
    return false
end

-- ===== Orchestration helpers =====
local function ensureFeatures()
    if FeatureManager and not AutoFish then
        AutoFish  = FeatureManager:Get("AutoFish")
        AutoSell  = FeatureManager:Get("AutoSellFish")
        TeleIsland= FeatureManager:Get("AutoTeleportIsland")
    end
    return AutoFish and AutoSell and TeleIsland
end

local function startAutofishOwned(mode)
    if not AutoFish then return end
    local wasRunning = AutoFish.GetStatus and AutoFish:GetStatus().running
    if not wasRunning then
        owned.autofish = true
        if AutoFish.SetMode then AutoFish:SetMode(mode or "Fast") end
        AutoFish:Start({ mode = mode or "Fast" })
    else
        owned.autofish = false
    end
end

local function stopAutofishOwned()
    if AutoFish and owned.autofish and AutoFish.Stop then
        AutoFish:Stop()
    end
    owned.autofish = false
end

local function startAutosellOwned(threshold, limit)
    if not AutoSell then return end
    local wasRunning = AutoSell.GetStatus and AutoSell:GetStatus().running
    if not wasRunning then
        owned.autosell = true
        if AutoSell.SetMode then AutoSell:SetMode(threshold or "Legendary") end
        if AutoSell.SetLimit then AutoSell:SetLimit(tonumber(limit or 0) or 0) end
        AutoSell:Start({ threshold = threshold or "Legendary", limit = tonumber(limit or 0) or 0, autoOnLimit = true })
    else
        owned.autosell = false
    end
end

local function stopAutosellOwned()
    if AutoSell and owned.autosell and AutoSell.Stop then
        AutoSell:Stop()
    end
    owned.autosell = false
end

local function tryTeleport(areaName, cfList)
    if TeleIsland then
        if areaName and TeleIsland.SetIsland then TeleIsland:SetIsland(areaName) end
        if areaName and TeleIsland.Teleport then
            TeleIsland:Teleport(areaName)
            -- no target CF from API; rely on polling around current root as best-effort
            return true
        end
    end
    -- If we have CFrames (from TrackQuestCFrame), pick nearest and set arrived when close
    if cfList and #cfList > 0 then
        local target = cfList[1]
        -- If your TeleIsland supports direct CFrame teleport, you could add a method; else rely on arrival polling only.
        return awaitArrived(target, 3)
    end
    return false
end

-- ===== Public API =====
function AutoQuest:Init(ctrls)
    controls = ctrls or controls
    ensureFeatures()

    -- 1) isi dropdown non-Primary
    local lines = getQuestLinesNonPrimary()
    safeSetDropdownValues(controls and controls.dropdown, lines)

    -- 2) hook dropdown change (kalau lib kamu sudah set callback di GUI, panggil ini manual saat select)
    -- render awal jika ada default
    if controls and controls.dropdown and controls.dropdown.Value then
        renderProgressSimple(controls.dropdown.Value)
    end
end

function AutoQuest:Start(opts)
    if running then return end
    ensureFeatures()

    running = true
    opId = opId + 1
    local myOp = opId

    local questLine = (opts and opts.questLine) or (controls and controls.dropdown and controls.dropdown.Value)
    if not questLine or not QuestList[questLine] then
        clearAllLabels()
        setLabelText(controls and controls.labels and controls.labels[1], "Pilih quest terlebih dulu")
        running = false
        return
    end

    -- live progress update
    if conn then conn:Disconnect() conn = nil end
    local path = getReplionPath(questLine)
    conn = DATA:OnChange({path, "Available", "Forever", "Quests"}, function()
        if not running or myOp ~= opId then return end
        renderProgressSimple(questLine)
    end)

    -- initial render
    renderProgressSimple(questLine)

    -- PLAN
    local plan = planSubquests(questLine)
    for _, item in ipairs(plan) do
        if not running or myOp ~= opId then break end
        -- refresh progress for this sub
        local lines = buildProgressLines(questLine)
        local this = nil
        for _, L in ipairs(lines) do
            if L.def == item.sub then this = L break end
        end
        if not this then continue end
        if tonumber(this.cur) >= tonumber(this.req or math.huge) then
            -- already done
            continue
        end

        -- Decide action based on key
        local key  = item.sub.Arguments and item.sub.Arguments.key
        local cond = item.sub.conditions or {}
        local area = cond.AreaName
        local cframes = nil
        if item.sub.TrackQuestCFrame then
            if typeof(item.sub.TrackQuestCFrame)=="CFrame" then
                cframes = { item.sub.TrackQuestCFrame }
            elseif typeof(item.sub.TrackQuestCFrame)=="table" then
                cframes = item.sub.TrackQuestCFrame
            end
        end

        if key == "EarnCoins" then
            -- EarnCoins: AutoSell ON (Legendary), AutoFish ON
            startAutosellOwned("Legendary", 0)
            startAutofishOwned("Fast")
            -- wait until progress reached
            while running and myOp==opId do
                local linesNow = buildProgressLines(questLine)
                local cur = 0; local req = this.req
                for _, L in ipairs(linesNow) do
                    if L.def == item.sub then cur = L.cur req = L.req break end
                end
                if tonumber(cur) >= tonumber(req or math.huge) then break end
                RunService.Heartbeat:Wait()
            end
            -- stop only owned autosell; keep autofish running for next tasks if we own it? safest: stop both owned, let next task re-start.
            stopAutosellOwned()
            stopAutofishOwned()

        elseif key == "CatchRareTreasureRoom" or (key=="CatchFish" and area=="Treasure Room") then
            stopAutosellOwned() -- jangan auto-jual saat misi tangkap
            tryTeleport("Treasure Room", cframes)
            startAutofishOwned("Fast")
            while running and myOp==opId do
                local linesNow = buildProgressLines(questLine)
                local cur = 0; local req = this.req
                for _, L in ipairs(linesNow) do
                    if L.def == item.sub then cur = L.cur req = L.req break end
                end
                if tonumber(cur) >= tonumber(req or math.huge) then break end
                RunService.Heartbeat:Wait()
            end
            stopAutofishOwned()

        elseif key == "CatchFish" then
            -- Handle by Area if available, else fallback (your TeleIsland static mapping to be extended by you)
            stopAutosellOwned()
            if area then
                tryTeleport(area, cframes)
            else
                -- if you later add a static area for Name-only quests, this branch will benefit.
                if cframes and #cframes>0 then tryTeleport(nil, cframes) end
            end
            startAutofishOwned("Fast")
            while running and myOp==opId do
                local linesNow = buildProgressLines(questLine)
                local cur = 0; local req = this.req
                for _, L in ipairs(linesNow) do
                    if L.def == item.sub then cur = L.cur req = L.req break end
                end
                if tonumber(cur) >= tonumber(req or math.huge) then break end
                RunService.Heartbeat:Wait()
            end
            stopAutofishOwned()

        else
            -- Unknown: fallback generic grind (no autosell)
            stopAutosellOwned()
            startAutofishOwned("Fast")
            while running and myOp==opId do
                local linesNow = buildProgressLines(questLine)
                local cur = 0; local req = this.req
                for _, L in ipairs(linesNow) do
                    if L.def == item.sub then cur = L.cur req = L.req break end
                end
                if tonumber(cur) >= tonumber(req or math.huge) then break end
                RunService.Heartbeat:Wait()
            end
            stopAutofishOwned()
        end

        -- re-render after each sub
        renderProgressSimple(questLine)
    end

    running = false
end

function AutoQuest:Stop()
    running = false
    opId = opId + 1 -- cancel in-flight
    stopAutofishOwned()
    stopAutosellOwned()
end

function AutoQuest:Cleanup()
    self:Stop()
    if conn then conn:Disconnect() conn = nil end
    clearAllLabels()
end

-- Expose helper (optional): GUI can call this when dropdown changes
function AutoQuest:OnQuestSelected(questLine)
    if conn then conn:Disconnect() conn = nil end
    renderProgressSimple(questLine)
    local path = getReplionPath(questLine)
    conn = DATA:OnChange({path, "Available", "Forever", "Quests"}, function()
        if not running then renderProgressSimple(questLine) end
    end)
end

return AutoQuest