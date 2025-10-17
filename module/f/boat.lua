-- Boat Manager (Simplified)
local boatFeature = {}
boatFeature.__index = boatFeature

local logger = _G.Logger and _G.Logger.new("Boat") or {
    debug = function() end,
    info = function() end,
    warn = function() end,
    error = function() end
}

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local SpawnBoatRF = nil
local DespawnBoatRF = nil
local inited = false
local running = false
local selectedBoatId = nil

function boatFeature:Init(guiControls)
    local ok, rf = pcall(function()
        return ReplicatedStorage.Packages._Index["sleitnick_net@0.2.0"].net["RF/SpawnBoat"]
    end)
    if not ok or not rf then
        logger:warn("SpawnBoat RemoteFunction tidak ditemukan")
        return false
    end
    SpawnBoatRF = rf
    
    local ok2, rf2 = pcall(function()
        return ReplicatedStorage.Packages._Index["sleitnick_net@0.2.0"].net["RF/DespawnBoat"]
    end)
    if not ok2 or not rf2 then
        logger:warn("DespawnBoat RemoteFunction tidak ditemukan")
        return false
    end
    DespawnBoatRF = rf2
    
    inited = true
    return true
end

function boatFeature:Start(config)
    if running then return end
    if not inited then
        local ok = self:Init()
        if not ok then return end
    end
    running = true
    logger:info("Boat Manager ready")
end

function boatFeature:Stop()
    if not running then return end
    running = false
end

function boatFeature:Cleanup()
    self:Stop()
    selectedBoatId = nil
end

function boatFeature:SetSelectedBoat(boatId)
    selectedBoatId = boatId
    logger:debug("Selected boat ID: " .. tostring(boatId))
end

function boatFeature:SpawnBoat()
    if not SpawnBoatRF then
        logger:warn("SpawnBoat RemoteFunction tidak tersedia")
        return
    end
    
    if not selectedBoatId then
        logger:warn("Pilih boat terlebih dahulu")
        return
    end
    
    local ok, result = pcall(function()
        return SpawnBoatRF:InvokeServer(selectedBoatId)
    end)
    
    if ok then
        logger:info("Boat ID " .. selectedBoatId .. " spawned")
    else
        logger:error("Gagal spawn boat: " .. tostring(result))
    end
end

function boatFeature:DespawnBoat()
    if not DespawnBoatRF then
        logger:warn("DespawnBoat RemoteFunction tidak tersedia")
        return
    end
    
    local ok, result = pcall(function()
        return DespawnBoatRF:InvokeServer()
    end)
    
    if ok then
        logger:info("Boat despawned")
        selectedBoatId = nil
    else
        logger:error("Gagal despawn boat: " .. tostring(result))
    end
end

return boatFeature