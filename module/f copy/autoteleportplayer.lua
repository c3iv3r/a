-- ===========================
-- AUTO TELEPORT PLAYER FEATURE
-- API disamakan dengan AutoTeleportIsland:
--   :Init(guiControls) -> bool
--   :SetTarget(playerName) -> bool
--   :Teleport(optionalPlayerName) -> bool
--   :GetPlayerList(excludeSelf) -> {string}
--   :GetStatus() -> table
--   :Cleanup() -> ()
-- ===========================

local AutoTeleportPlayer = {}
AutoTeleportPlayer.__index = AutoTeleportPlayer

local logger = _G.Logger and _G.Logger.new("AutoTeleportPlayer") or {
    debug = function() end,
    info = function() end,
    warn = function() end,
    error = function() end
}

-- Services
local Workspace = game:GetService("Workspace")
local Players = game:GetService("Players")
local LocalPlayer = Players.LocalPlayer

-- State
local isInitialized = false
local controls = {}
local selectedPlayerName = nil

-- Settings (boleh lu ubah sesuai preferensi)
local SETTINGS = {
    yOffset = 6,        -- naik 6 stud biar ga nyangkut
    behindDist = 3,     -- spawn 3 stud di belakang target
    excludeSelf = true, -- dropdown ga nampilin diri sendiri
    notify = true,      -- pake _G.WindUI:Notify kalau ada
}

-- ===== Helpers =====
local function getCharacter(player)
    return player and player.Character or nil
end

local function getHRP(character)
    if not character then return nil end
    return character:FindFirstChild("HumanoidRootPart")
        or character:FindFirstChild("Torso") -- R6 fallback
end

local function getTargetCFrame(targetPlayer)
    local char = getCharacter(targetPlayer)
    if not char then return nil end

    -- Prioritas HRP; fallback ke Pivot
    local hrp = getHRP(char)
    if hrp then
        return hrp.CFrame
    end

    if char.PrimaryPart then
        return char.PrimaryPart.CFrame
    end

    -- Roblox modern model biasanya punya Pivot
    local ok, pivot = pcall(function()
        return char:GetPivot()
    end)
    if ok and typeof(pivot) == "CFrame" then
        return pivot
    end

    return nil
end

local function tpNotify(title, content, icon, duration)
    if SETTINGS.notify and _G.WindUI and _G.WindUI.Notify then
        _G.WindUI:Notify({
            Title = title, Content = content, Icon = icon or "map-pin", Duration = duration or 2
        })
    end
end

-- Hard teleport to CFrame (sedikit di belakang target + offset Y)
function AutoTeleportPlayer:TeleportToPosition(baseCF, targetCharacter)
    if not LocalPlayer or not LocalPlayer.Character then
        logger:warn("Local character not found")
        return false
    end
    local myChar = LocalPlayer.Character
    local myHRP  = myChar:FindFirstChild("HumanoidRootPart")
    local hum    = myChar:FindFirstChildOfClass("Humanoid")
    if not (myHRP and hum) then
        logger:warn("Missing HRP/Humanoid")
        return false
    end

   -- Posisi "di belakang" target dalam local-space target
    -- catatan: di CFrame, +Z itu ke belakang relatif LookVector
    local spawnCF = baseCF * CFrame.new(0, 0, SETTINGS.behindDist)

    -- Raycast ke bawah untuk cari permukaan lantai
    local rp = RaycastParams.new()
    rp.FilterType = Enum.RaycastFilterType.Exclude
    rp.FilterDescendantsInstances = { myChar }
    if targetCharacter then
        table.insert(rp.FilterDescendantsInstances, targetCharacter)
    end

    local origin = spawnCF.Position + Vector3.new(0, 50, 0)
    local dir    = Vector3.new(0, -500, 0)
    local hit    = Workspace:Raycast(origin, dir, rp)

    local finalPos
    if hit then
        -- Stand height: permukaan + HipHeight + setengah tinggi HRP
        local standY = hit.Position.Y + hum.HipHeight + (myHRP.Size.Y * 0.5)
        finalPos = Vector3.new(spawnCF.X, standY, spawnCF.Z)
    else
        -- Fallback: pakai offset kecil (lebih rendah dari +6 biar ga “melayang lama”)
        finalPos = (spawnCF + Vector3.new(0, math.max(2, SETTINGS.yOffset - 2), 0)).Position
    end

    -- Orientasi hadap sama dengan target
    local finalCF = CFrame.lookAt(finalPos, finalPos + baseCF.LookVector)

    -- Nolkan kecepatan biar ga seluncur / jatoh
    local ok = pcall(function()
        myHRP.AssemblyLinearVelocity  = Vector3.zero
        myHRP.AssemblyAngularVelocity = Vector3.zero
        -- Hard TP (cepat). Kalau anti-cheat sensitif, ganti ke PivotTo:
        myHRP.CFrame = finalCF
        -- myChar:PivotTo(finalCF) -- opsi “soft”
    end)
    return ok
end

-- ===== Public API =====

function AutoTeleportPlayer:Init(guiControls)
    controls = guiControls or {}
    isInitialized = true
    logger:info("Initialized")
    return true
end

function AutoTeleportPlayer:SetTarget(playerName)
    if typeof(playerName) ~= "string" or playerName == "" then
        logger:warn("Invalid player name")
        return false
    end
    if SETTINGS.excludeSelf and playerName == LocalPlayer.Name then
        logger:warn("Target is yourself; ignoring")
        return false
    end
    selectedPlayerName = playerName
    logger:info("Target set to:", selectedPlayerName)
    return true
end

function AutoTeleportPlayer:Teleport(optionalPlayerName)
    if not isInitialized then
        logger:warn("Feature not initialized")
        return false
    end

    local name = optionalPlayerName or selectedPlayerName
    if not name or name == "" then
        logger:warn("No target player selected")
        tpNotify("Teleport Failed", "Pilih player dulu dari dropdown", "x", 3)
        return false
    end

    if SETTINGS.excludeSelf and name == LocalPlayer.Name then
        logger:warn("Target is yourself")
        tpNotify("Teleport Failed", "Ga bisa teleport ke diri sendiri", "x", 3)
        return false
    end

    local target = Players:FindFirstChild(name)
    if not target then
        logger:warn("Target player not found:", name)
        tpNotify("Teleport Failed", "Player tidak ditemukan (mungkin sudah leave)", "x", 3)
        return false
    end

    local cf = getTargetCFrame(target)
    if not cf then
        logger:warn("Could not get target CFrame:", name)
        tpNotify("Teleport Failed", "Posisi player belum siap (character belum spawn?)", "x", 3)
        return false
    end

    local ok = self:TeleportToPosition(cf, target.Character)
    if ok then
        logger:info("Teleported to", name)
        tpNotify("Teleport Success", "Ke " .. name, "map-pin", 2)
    else
        logger:warn("Teleport pcall failed")
        tpNotify("Teleport Failed", "Gagal set CFrame", "x", 3)
    end
    return ok
end

function AutoTeleportPlayer:GetPlayerList(excludeSelf)
    local out, me = {}, LocalPlayer and LocalPlayer.Name
    for _, p in ipairs(Players:GetPlayers()) do
        if not excludeSelf or (me and p.Name ~= me) then
            table.insert(out, p.Name)
        end
    end
    table.sort(out, function(a,b) return a:lower() < b:lower() end)
    return out
end

function AutoTeleportPlayer:RefreshList()
    return self:GetPlayerList(SETTINGS.excludeSelf)
end

function AutoTeleportPlayer:GetStatus()
    return {
        initialized = isInitialized,
        selectedPlayer = selectedPlayerName,
        yOffset = SETTINGS.yOffset,
        behindDist = SETTINGS.behindDist,
        players = self:GetPlayerList(SETTINGS.excludeSelf),
    }
end

function AutoTeleportPlayer:Cleanup()
    controls = {}
    isInitialized = false
    selectedPlayerName = nil
    logger:info("Cleaned up")
end

return AutoTeleportPlayer
