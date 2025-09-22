-- autoquest.lua (v1.1)
local AutoQuest = {}
AutoQuest.__index = AutoQuest

local RS         = game:GetService("ReplicatedStorage")
local Players    = game:GetService("Players")
local RunService = game:GetService("RunService")
local LP         = Players.LocalPlayer

local Replion       = require(RS.Packages.Replion)
local QuestList     = require(RS.Shared.Quests.QuestList)      -- static defs (AuraQuest/DeepSea, exclude Primary) 
local QuestUtility  = require(RS.Shared.Quests.QuestUtility)   -- GetQuestValue(DATA, questDef) 2

local FeatureManager = _G.FeatureManager
local AutoFish, AutoSell, TeleIsland
local DATA = Replion.Client:WaitReplion("Data")

local controls, running, opId, conn = nil, false, 0, nil
local owned = {autofish=false, autosell=false}

-- ===== helpers =====
local function log(...) print("[AutoQuest]", ...) end

local function norm(val)
    if type(val) == "table" then
        return val.Value or val.value or val[1] or val.Selected or val.selection
    end
    return val
end

local function ellipsis(s, max)
    s = tostring(s or "")
    max = max or 46  -- sesuaikan kalau masih kepanjangan
    if #s <= max then return s end
    return s:sub(1, max-1) .. "…"
end

local function getQuestLinesNonPrimary()
    local out = {}
    for name, def in pairs(QuestList) do
        if type(def)=="table" and def.Forever and name~="Primary" then
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
    if dd.SetValues then dd:SetValues(values) return end
    pcall(function() dd.Values = values end)
    if dd.Refresh then pcall(function() dd:Refresh() end) end
end

local function setLabelText(lbl, text)
    if not lbl then return end
    text = ellipsis(text, 58) -- potong sebelum Obsidian overflow
    if lbl.SetText then lbl:SetText(text) else pcall(function() lbl.Text = text end) end
end

local function clearAllLabels()
    if not (controls and controls.labels) then return end
    for _, l in ipairs(controls.labels) do setLabelText(l, "") end
end

local function ensureFeatures()
    if not FeatureManager then return false end
    AutoFish   = AutoFish   or FeatureManager:Get("AutoFish")        or FeatureManager:Get("Autofish")
    AutoSell   = AutoSell   or FeatureManager:Get("AutoSellFish")    or FeatureManager:Get("AutoSell")
    TeleIsland = TeleIsland or FeatureManager:Get("AutoTeleportIsland") or FeatureManager:Get("TeleportIsland")
    return AutoFish and AutoSell and TeleIsland
end

local function getStateMapForLine(questLine)
    local avail = DATA:Get({ getReplionPath(questLine), "Available" })
    local map = {}
    if avail and avail.Forever and avail.Forever.Quests then
        for _, q in ipairs(avail.Forever.Quests) do
            if q.QuestId ~= nil then map[q.QuestId] = q end
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
        local req = QuestUtility.GetQuestValue(DATA, sub) -- target resmi 3
        local name = tostring(sub.DisplayName or ("Quest "..qid))
        table.insert(lines, {
            text  = string.format("%d) %s — %s / %s", idx, name, cur, req),
            qid   = qid, cur = cur, req = req, def = sub, state = st
        })
        total += 1
    end
    return lines, total
end

local function renderProgressSimple(questLine)
    local lines, total = buildProgressLines(questLine)
    if not (controls and controls.labels) then return lines end
    local maxL = #controls.labels
    for i=1, maxL do
        local lbl = controls.labels[i]
        local item = lines[i]
        if item then setLabelText(lbl, item.text) else setLabelText(lbl, "") end
    end
    local extra = total - maxL
    if extra > 0 then
        setLabelText(controls.labels[maxL], ("(+%d lagi...)"):format(extra))
    end
    return lines
end

-- Planner dengan skor sederhana (easy-first, SECRET terakhir)
local function classifyAndScore(sub)
    local key = sub.Arguments and sub.Arguments.key
    local cond = sub.conditions or {}
    local score, reason = 50, {}

    local function R(x) table.insert(reason, x) end

    if key == "EarnCoins" then score=1; R("EarnCoins")
    elseif key=="CatchRareTreasureRoom" then score=2; R("Treasure Room")
    elseif key=="CatchFish" then
        local t, n, a = cond.Tier, cond.Name, cond.AreaName
        if n then score=7; R("Name-specific/SECRET")
        elseif t~=nil then
            if t>=7 then score=6; R("Tier 7/SECRET")
            elseif t>=6 then score=4; R("Tier 6/Mythic")
            elseif t>=4 then score=3; R("Tier 4/Epic")
            else score=5; R("Tier rendah") end
        else score=9; R("Generic catch") end
        if a then score=score-1; R("Area jelas") end
    else score=5; R("Unknown type") end

    local ok, req = pcall(function() return QuestUtility.GetQuestValue(DATA, sub) end)
    if ok and tonumber(req) and req<=10 then score=score-1; table.insert(reason,"Req kecil") end
    return score, table.concat(reason, " · ")
end

local function planSubquests(questLine)
    local def = QuestList[questLine]; local items={}
    if not def or not def.Forever then return items end
    for idx, sub in ipairs(def.Forever) do
        local s, w = classifyAndScore(sub)
        table.insert(items, {idx=idx, sub=sub, score=s, why=w})
    end
    table.sort(items, function(a,b) return a.score < b.score end)
    return items
end

-- Arrival polling: selalu dipakai setelah teleport
local function awaitArrived(timeout)
    timeout = timeout or 5
    local start = tick()
    while tick()-start < timeout do
        local char = LP.Character
        local root = char and char.PrimaryPart
        if root then
            -- cukup pastikan kecepatan/gerak stabil sedikit
            if root.AssemblyLinearVelocity.Magnitude < 2 then return true end
        end
        RunService.Heartbeat:Wait()
    end
    return true -- jangan menghambat, tapi kita sudah kasih delay stabilisasi
end

local function tryTeleport(areaName)
    if not TeleIsland then return false end
    if areaName and TeleIsland.SetIsland then
        TeleIsland:SetIsland(areaName)
    end
    if TeleIsland.Teleport then
        local ok = TeleIsland:Teleport(areaName)
        RunService.Heartbeat:Wait()
        awaitArrived(5)
        return ok ~= false
    end
    return false
end

local function startAutofishOwned(mode)
    if not AutoFish then return end
    local was = AutoFish.GetStatus and (AutoFish:GetStatus().running)
    if not was then
        owned.autofish = true
        if AutoFish.SetMode then AutoFish:SetMode(mode or "Fast") end
        AutoFish:Start({ mode = mode or "Fast" })
        log("Autofish START (owned)")
    else
        owned.autofish = false
        log("Autofish already running (not owned)")
    end
end

local function stopAutofishOwned()
    if AutoFish and owned.autofish and AutoFish.Stop then
        AutoFish:Stop()
        log("Autofish STOP (owned)")
    end
    owned.autofish = false
end

local function startAutosellOwned(threshold, limit)
    if not AutoSell then return end
    local was = AutoSell.GetStatus and (AutoSell:GetStatus().running)
    if not was then
        owned.autosell = true
        if AutoSell.SetMode then AutoSell:SetMode(threshold or "Legendary") end
        if AutoSell.SetLimit then AutoSell:SetLimit(tonumber(limit or 0) or 0) end
        AutoSell:Start({ threshold = threshold or "Legendary", limit = tonumber(limit or 0) or 0, autoOnLimit = true })
        log("AutoSell START (owned)")
    else
        owned.autosell = false
        log("AutoSell already running (not owned)")
    end
end

local function stopAutosellOwned()
    if AutoSell and owned.autosell and AutoSell.Stop then
        AutoSell:Stop()
        log("AutoSell STOP (owned)")
    end
    owned.autosell = false
end

-- ===== PUBLIC API =====
function AutoQuest:Init(ctrls)
    controls = ctrls or controls
    ensureFeatures()

    local lines = getQuestLinesNonPrimary()
    safeSetDropdownValues(controls and controls.dropdown, lines)

    -- Auto-select pertama kalau kosong
    if controls and controls.dropdown then
        local cur = norm(controls.dropdown.Value)
        if (not cur or cur=="") and lines[1] then
            if controls.dropdown.SetValue then controls.dropdown:SetValue(lines[1]) end
            cur = lines[1]
        end
        if cur and self.OnQuestSelected then self:OnQuestSelected(cur) end
    end
end

function AutoQuest:OnQuestSelected(questLine)
    questLine = norm(questLine)
    if not questLine or not QuestList[questLine] then return end
    log("Selected:", questLine)
    if conn then conn:Disconnect(); conn=nil end
    renderProgressSimple(questLine)
    local path = getReplionPath(questLine)
    conn = DATA:OnChange({path,"Available","Forever","Quests"}, function()
        if not running then renderProgressSimple(questLine) end
    end)
end

function AutoQuest:Start(opts)
    if running then return end
    ensureFeatures()

    running = true
    opId = opId + 1
    local myOp = opId

    local questLine = norm(opts and opts.questLine) or (controls and controls.dropdown and norm(controls.dropdown.Value))
    if not questLine or not QuestList[questLine] then
        clearAllLabels()
        setLabelText(controls and controls.labels and controls.labels[1], "Pilih quest terlebih dulu")
        running=false; return
    end

    log("START questline:", questLine)

    if conn then conn:Disconnect(); conn=nil end
    conn = DATA:OnChange({getReplionPath(questLine), "Available", "Forever", "Quests"}, function()
        if running and myOp==opId then renderProgressSimple(questLine) end
    end)
    renderProgressSimple(questLine)

    local plan = planSubquests(questLine)
    for i, item in ipairs(plan) do
        if not running or myOp~=opId then break end

        -- refresh current progress for this sub
        local lines = buildProgressLines(questLine)
        local this = nil
        for _, L in ipairs(lines) do if L.def==item.sub then this=L break end end
        if (not this) or (tonumber(this.cur) >= tonumber(this.req or math.huge)) then
            log(("Skip sub %d: already complete"):format(i))
            continue
        end

        local key  = item.sub.Arguments and item.sub.Arguments.key
        local cond = item.sub.conditions or {}
        local area = cond.AreaName
        log(("Run sub %d: key=%s, why=%s"):format(i, tostring(key), item.why))

        if key=="EarnCoins" then
            startAutosellOwned("Legendary", 0)
            startAutofishOwned("Fast")
        elseif key=="CatchRareTreasureRoom" or (key=="CatchFish" and area=="Treasure Room") then
            stopAutosellOwned()
            tryTeleport("Treasure Room"); -- arrival polling inside
            startAutofishOwned("Fast")
        elseif key=="CatchFish" then
            stopAutosellOwned()
            if area then tryTeleport(area) else
                -- Name-only/SECRET: kamu akan tambah island statis nanti; sementara biarkan di spot saat ini
                log("No AreaName; grinding at current spot")
            end
            startAutofishOwned("Fast")
        else
            stopAutosellOwned()
            startAutofishOwned("Fast")
        end

        -- wait until complete or canceled
        while running and myOp==opId do
            local now = buildProgressLines(questLine)
            local cur, req = 0, this.req
            for _, L in ipairs(now) do if L.def==item.sub then cur=L.cur req=L.req break end end
            if tonumber(cur) >= tonumber(req or math.huge) then break end
            RunService.Heartbeat:Wait()
        end

        -- stop owned between subs
        stopAutofishOwned()
        stopAutosellOwned()

        renderProgressSimple(questLine)
    end

    running=false
    log("DONE questline:", questLine)
end

function AutoQuest:Stop()
    running=false
    opId = opId + 1
    stopAutofishOwned()
    stopAutosellOwned()
    log("STOP")
end

function AutoQuest:Cleanup()
    self:Stop()
    if conn then conn:Disconnect(); conn=nil end
    clearAllLabels()
end

return AutoQuest