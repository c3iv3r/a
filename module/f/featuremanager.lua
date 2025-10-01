-- FeatureManager.lua
-- Synchronous feature loader for Noctis GUI

local FeatureManager = {}
FeatureManager.LoadedFeatures = {}
FeatureManager.InitializedFeatures = {}
FeatureManager.TotalFeatures = 0
FeatureManager.LoadedCount = 0
FeatureManager.IsReady = false

local FEATURE_URLS = {
    AutoFish           = "https://raw.githubusercontent.com/c3iv3r/a/refs/heads/main/module/f/autofish.lua",
    AutoSellFish       = "https://raw.githubusercontent.com/c3iv3r/a/refs/heads/main/module/f/autosellfish.lua",
    AutoTeleportIsland = "https://raw.githubusercontent.com/c3iv3r/a/refs/heads/main/module/f/autoteleportisland.lua",
    FishWebhook        = "https://raw.githubusercontent.com/c3iv3r/a/refs/heads/main/module/f/fishwebhook.lua",
    AutoBuyWeather     = "https://raw.githubusercontent.com/c3iv3r/a/refs/heads/main/module/f/autobuyweather.lua",
    AutoBuyBait        = "https://raw.githubusercontent.com/c3iv3r/a/refs/heads/main/module/f/autobuybait.lua",
    AutoBuyRod         = "https://raw.githubusercontent.com/c3iv3r/a/refs/heads/main/module/f/autobuyrod.lua",
    AutoTeleportEvent  = "https://raw.githubusercontent.com/c3iv3r/a/refs/heads/main/module/f/autoteleportevent.lua",
    AutoGearOxyRadar   = "https://raw.githubusercontent.com/c3iv3r/a/refs/heads/main/module/f/autogearoxyradar.lua",
    AntiAfk            = "https://raw.githubusercontent.com/c3iv3r/a/refs/heads/main/module/f/antiafk.lua",
    AutoEnchantRod     = "https://raw.githubusercontent.com/c3iv3r/a/refs/heads/main/module/f/autoenchantrod.lua",
    AutoFavoriteFish   = "https://raw.githubusercontent.com/c3iv3r/a/refs/heads/main/module/f/autofavoritefish.lua",
    AutoFavoriteFishV2 = "https://raw.githubusercontent.com/c3iv3r/a/refs/heads/main/module/f/autofavoritefishv2.lua",
    AutoTeleportPlayer = "https://raw.githubusercontent.com/c3iv3r/a/refs/heads/main/module/f/autoteleportplayer.lua",
    BoostFPS           = "https://raw.githubusercontent.com/c3iv3r/a/refs/heads/main/module/f/boostfps.lua",
    AutoSendTrade      = "https://raw.githubusercontent.com/c3iv3r/a/refs/heads/main/module/f/autosendtrade.lua",
    AutoAcceptTrade    = "https://raw.githubusercontent.com/c3iv3r/a/refs/heads/main/module/f/autoaccepttrade.lua",
    SavePosition       = "https://raw.githubusercontent.com/c3iv3r/a/refs/heads/main/module/f/saveposition.lua",
    PositionManager    = "https://raw.githubusercontent.com/c3iv3r/a/refs/heads/main/module/f/positionmanager.lua",
    CopyJoinServer     = "https://raw.githubusercontent.com/c3iv3r/a/refs/heads/main/module/f/copyjoinserver.lua",
    PlayerEsp          = "https://raw.githubusercontent.com/c3iv3r/a/refs/heads/main/module/f-pub/playeresp.lua",
    AutoReconnect      = "https://raw.githubusercontent.com/c3iv3r/a/refs/heads/main/module/f/autoreconnect.lua",
    AutoReexec         = "https://raw.githubusercontent.com/c3iv3r/a/refs/heads/main/module/f/autoreexec.lua",
    AutoBuyMerchant    = "https://raw.githubusercontent.com/c3iv3r/a/refs/heads/main/module/f/autobuymerchant.lua",
    AutoFixFishing     = "https://raw.githubusercontent.com/c3iv3r/a/refs/heads/main/module/f/autofixfishing.lua"  
}

-- Load single feature synchronously
function FeatureManager:LoadSingleFeature(featureName, url, logger)
    local success, result = pcall(function()
        local code = game:HttpGet(url)
        if not code or code == "" then
            error("Empty response from URL")
        end
        
        local module = loadstring(code)()
        if type(module) ~= "table" then
            error("Module did not return a table")
        end
        
        return module
    end)
    
    if success and result then
        result.__featureName = featureName
        result.__initialized = false
        self.LoadedFeatures[featureName] = result
        self.LoadedCount = self.LoadedCount + 1
        
        if logger then
            logger:info(string.format("✓ %s loaded (%d/%d)", 
                featureName, self.LoadedCount, self.TotalFeatures))
        end
        return true
    else
        if logger then
            logger:warn(string.format("✗ Failed to load %s: %s", featureName, result or "Unknown error"))
        end
        return false
    end
end

-- Initialize all features synchronously
function FeatureManager:InitializeAllFeatures(notifyLib, logger)
    if logger then
        logger:info("Starting synchronous feature loading...")
    end
    
    -- Show loading notification
    if notifyLib then
        local c = Color3.fromRGB(125, 85, 255)
        local title = ('<font color="#%s">NOCTIS</font>'):format(c:ToHex())
        notifyLib:Notify({
            Title = title,
            Description = "Loading script...",
            Duration = 5
        })
    end
    
    -- Count total features
    self.TotalFeatures = 0
    for _ in pairs(FEATURE_URLS) do
        self.TotalFeatures = self.TotalFeatures + 1
    end
    
    -- Load order for proper dependency handling
    local loadOrder = {
        "AntiAfk", "SavePosition", "PositionManager", "AutoReexec", "BoostFPS", 
        "AutoFish", "AutoSellFish", "AutoTeleportIsland", "AutoTeleportPlayer", 
        "AutoTeleportEvent", "AutoEnchantRod", "AutoFavoriteFish", "AutoFavoriteFishV2", 
        "AutoSendTrade", "AutoAcceptTrade", "FishWebhook", "AutoBuyWeather", 
        "AutoBuyBait", "AutoBuyRod", "AutoGearOxyRadar", "CopyJoinServer", 
        "AutoReconnect", "AutoBuyMerchant", "PlayerEsp", "AutoFixFishing"
    }
    
    local successCount = 0
    
    -- Load all features synchronously
    for _, featureName in ipairs(loadOrder) do
        local url = FEATURE_URLS[featureName]
        if url and self:LoadSingleFeature(featureName, url, logger) then
            successCount = successCount + 1
        end
        -- Small delay to prevent rate limiting
        wait(0.02)
    end
    
    self.IsReady = true
    
    if logger then
        logger:info(string.format("Loading completed: %d/%d features ready", 
            successCount, self.TotalFeatures))
    end
    
    -- Show completion notification
    if notifyLib then
        notifyLib:Notify({
            Title = "Features Ready",
            Description = string.format("%d/%d features loaded successfully", successCount, self.TotalFeatures),
            Duration = 3
        })
    end
    
    return successCount, self.TotalFeatures
end

-- Get feature with controls attachment
function FeatureManager:GetFeature(featureName, controls, logger)
    if not self.IsReady then
        if logger then
            logger:warn("Features not ready yet!")
        end
        return nil
    end
    
    local feature = self.LoadedFeatures[featureName]
    if not feature then
        if logger then
            logger:warn(string.format("Feature %s not found", featureName))
        end
        return nil
    end
    
    if controls and not feature.__controlsAttached then
        feature.__controls = controls
        feature.__controlsAttached = true
        
        if feature.Init and not feature.__initialized then
            local success, err = pcall(feature.Init, feature, controls)
            if success then 
                feature.__initialized = true
                if logger then
                    logger:info(string.format("✓ %s initialized", featureName))
                end
            else
                if logger then
                    logger:warn(string.format("✗ Init failed for %s: %s", featureName, err))
                end
            end
        end
    end
    
    return feature
end

-- Simple getter without controls
function FeatureManager:Get(featureName)
    return self.LoadedFeatures[featureName]
end

-- Check if manager is ready
function FeatureManager:IsLoaded()
    return self.IsReady
end

-- Get loading status
function FeatureManager:GetStatus()
    return {
        isReady = self.IsReady,
        loaded = self.LoadedCount,
        total = self.TotalFeatures,
        features = {}
    }
end

return FeatureManager