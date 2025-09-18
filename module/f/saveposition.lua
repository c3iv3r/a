-- ===========================
-- SAVE POSITION FEATURE - IMPROVED VERSION
-- Matches AutoTeleportIsland-style API (Init, Start, Stop, Cleanup)
-- Hard teleport (Y offset = +6), logger-compatible, GUI-wireable.
-- Supports session persistence via writefile/readfile if available.
-- Auto-restore on join/respawn when Save Position toggle is ON.
-- Fixed rejoin/reconnect position restoration issues.
-- Added Delete Position functionality.
-- ===========================

local SavePositionFeature = {}
SavePositionFeature.__index = SavePositionFeature

-- ===== Logger (same pattern as AutoTeleportIsland) =====
local logger = _G.Logger and _G.Logger.new("SavePosition") or {
    debug = function() end,
    info  = function() end,
    warn  = function() end,
    error = function() end,
}

-- ===== Services =====
local Players       = game:GetService("Players")
local RunService    = game:GetService("RunService")
local LocalPlayer   = Players.LocalPlayer
local Workspace     = game:GetService("Workspace")

-- ===== Internal state =====
local isInitialized         = false
local isRunning             = false
local controls              = {}           -- GUI control refs if needed
local savedPositions        = {}           -- map name -> CFrame
local selectedName          = nil          -- current selected key in dropdown
local saveToggleEnabled     = false        -- Save Position toggle state
local saveAnchorCFrame      = nil          -- anchor cf captured by toggle
local charAddedConn         = nil
local heartbeatConn         = nil
local restoreInProgress     = false        -- prevent multiple restore attempts

-- ===== Persistence (optional) =====
local CAN_FS = (typeof(writefile) == "function") and (typeof(readfile) == "function") and (typeof(isfile) == "function")
local SAVE_PATH = ".devlogic/saveposition.json"

-- Enhanced CFrame serialization with validation
local function cframeToTable(cf)
    if typeof(cf) ~= "CFrame" then return nil end
    local a,b,c,d,e,f,g,h,i,x,y,z = cf:GetComponents()
    return {
        components = {a,b,c,d,e,f,g,h,i,x,y,z},
        position = {x, y, z},  -- backup position data
        timestamp = os.time()  -- for debugging
    }
end

local function tableToCFrame(data)
    if type(data) ~= "table" then return nil end
    
    -- Handle new format with validation
    if data.components and type(data.components) == "table" and #data.components >= 12 then
        local t = data.components
        local success, result = pcall(function()
            return CFrame.new(
                t[10], t[11], t[12],  -- position
                t[1], t[2], t[3],     -- right vector
                t[4], t[5], t[6],     -- up vector  
                t[7], t[8], t[9]      -- back vector
            )
        end)
        if success then return result end
    end
    
    -- Handle old format (backward compatibility)
    if type(data) == "table" and #data >= 12 then
        local success, result = pcall(function()
            return CFrame.new(
                data[10], data[11], data[12],
                data[1], data[2], data[3],
                data[4], data[5], data[6],
                data[7], data[8], data[9]
            )
        end)
        if success then return result end
    end
    
    -- Fallback: try to construct from position if available
    if data.position and type(data.position) == "table" and #data.position >= 3 then
        local success, result = pcall(function()
            return CFrame.new(data.position[1], data.position[2], data.position[3])
        end)
        if success then return result end
    end
    
    logger:warn("Failed to deserialize CFrame data")
    return nil
end

local function loadPersisted()
    if not CAN_FS then 
        logger:debug("File system not available for persistence")
        return 
    end
    
    local success, data = pcall(function()
        if isfile(SAVE_PATH) then
            local content = readfile(SAVE_PATH)
            return game.HttpService:JSONDecode(content)
        end
        return nil
    end)
    
    if not success or not data then 
        logger:debug("No persisted data found or failed to load")
        return 
    end

    -- Load savedPositions with validation
    if type(data.savedPositions) == "table" then
        local loaded = 0
        for name, cfData in pairs(data.savedPositions) do
            if type(name) == "string" and name ~= "" then
                local cf = tableToCFrame(cfData)
                if cf then 
                    savedPositions[name] = cf
                    loaded = loaded + 1
                else
                    logger:warn("Failed to load position:", name)
                end
            end
        end
        logger:info("Loaded", loaded, "saved positions from persistence")
    end
    
    -- Load anchor + toggle state
    if data.saveToggleEnabled then
        if type(data.saveAnchorCFrame) == "table" then
            local anchorCF = tableToCFrame(data.saveAnchorCFrame)
            if anchorCF then
                saveToggleEnabled = true
                saveAnchorCFrame = anchorCF
                logger:info("Loaded Save Position toggle state: ON with anchor")
            else
                logger:warn("Failed to load anchor CFrame, disabling toggle")
                saveToggleEnabled = false
                saveAnchorCFrame = nil
            end
        else
            logger:warn("Toggle was enabled but no anchor data found")
            saveToggleEnabled = false
        end
    else
        saveToggleEnabled = false
        saveAnchorCFrame = nil
    end
    
    -- Load selected name
    if type(data.selectedName) == "string" and data.selectedName ~= "" then
        if savedPositions[data.selectedName] then
            selectedName = data.selectedName
        else
            logger:warn("Selected name not found in saved positions:", data.selectedName)
            selectedName = nil
        end
    end
    
    logger:info("Persistence loaded - Toggle:", saveToggleEnabled, "Selected:", selectedName or "none")
end

local function persist()
    if not CAN_FS then return end
    
    local obj = {
        version = "1.1",  -- version tracking
        savedPositions = {},
        saveToggleEnabled = saveToggleEnabled or false,
        saveAnchorCFrame = saveAnchorCFrame and cframeToTable(saveAnchorCFrame) or nil,
        selectedName = selectedName,
        timestamp = os.time()
    }
    
    -- Serialize all saved positions
    for name, cf in pairs(savedPositions) do
        if typeof(cf) == "CFrame" then
            obj.savedPositions[name] = cframeToTable(cf)
        end
    end
    
    local success = pcall(function()
        local jsonData = game.HttpService:JSONEncode(obj)
        writefile(SAVE_PATH, jsonData)
    end)
    
    if success then
        logger:debug("Data persisted successfully")
    else
        logger:warn("Failed to persist data")
    end
end

-- ===== Utilities =====
local function getHRP()
    local char = LocalPlayer.Character
    if not char then return nil end
    return char:FindFirstChild("HumanoidRootPart")
end

local function ensureCharacterReady(timeout)
    timeout = timeout or 10
    local char = LocalPlayer.Character or LocalPlayer.CharacterAdded:Wait()
    local startTime = os.clock()
    
    while (os.clock() - startTime) < timeout do
        local hrp = char:FindFirstChild("HumanoidRootPart")
        local hum = char:FindFirstChildOfClass("Humanoid")
        if hrp and hum and hum.Health > 0 then
            -- Additional check: make sure the character is properly loaded
            if hrp.AssemblyLinearVelocity and hrp.CFrame then
                return hrp
            end
        end
        RunService.Heartbeat:Wait()
    end
    
    logger:warn("Character not ready within timeout")
    return getHRP()
end

-- Enhanced teleport with better error handling and validation
function SavePositionFeature:TeleportToCFrame(cf)
    if typeof(cf) ~= "CFrame" then
        logger:warn("Invalid CFrame provided for teleport")
        return false
    end
    
    local hrp = ensureCharacterReady(8)
    if not hrp then
        logger:warn("HumanoidRootPart not ready for teleport")
        return false
    end

    local success = pcall(function()
        local char = hrp.Parent
        local hum = char and char:FindFirstChildOfClass("Humanoid")
        
        if not hum or hum.Health <= 0 then
            error("Character not ready for teleport")
        end
        
        -- Calculate target with Y offset
        local targetPos = cf.Position + Vector3.new(0, 6, 0)
        local targetCF = CFrame.new(targetPos, targetPos + cf.LookVector)
        
        -- Prepare for teleport
        if hum then 
            hum:ChangeState(Enum.HumanoidStateType.Physics) 
        end
        
        -- Zero out velocities
        hrp.AssemblyLinearVelocity = Vector3.zero
        hrp.AssemblyAngularVelocity = Vector3.zero
        
        -- Execute teleport
        hrp.CFrame = targetCF
        
        -- Restore normal state after brief delay
        task.delay(0.1, function()
            if hum and hum.Health > 0 and hum.Parent then
                hum:ChangeState(Enum.HumanoidStateType.RunningNoPhysics)
                task.delay(0.05, function()
                    if hum and hum.Health > 0 and hum.Parent then
                        hum:ChangeState(Enum.HumanoidStateType.Running)
                    end
                end)
            end
        end)
    end)

    if not success then
        logger:warn("Teleport execution failed")
        return false
    end
    
    logger:debug("Teleport executed successfully")
    return true
end

-- ===== Public API =====

function SavePositionFeature:Init(guiControls)
    if isInitialized then return true end
    
    controls = guiControls or {}
    logger:info("Initializing SavePositionFeature...")
    
    -- Load persisted data first
    loadPersisted()
    
    -- Update GUI if available
    if controls.dropdown and self.GetSavedList then
        local list = self:GetSavedList()
        if controls.dropdown.SetValues then
            controls.dropdown:SetValues(list)
        end
        if selectedName and controls.dropdown.SetValue then
            controls.dropdown:SetValue(selectedName)
        end
    end
    
    -- Update toggle state in GUI if available
    if controls.toggle and controls.toggle.SetValue then
        controls.toggle:SetValue(saveToggleEnabled)
    end

    isInitialized = true
    logger:info("SavePositionFeature initialized successfully")
    
    return true
end

function SavePositionFeature:Start()
    if not isInitialized then
        logger:warn("Start called before Init")
        return false
    end
    if isRunning then return true end
    
    isRunning = true
    logger:info("Starting SavePositionFeature...")

    -- Handle character respawn/rejoin restoration
    if charAddedConn then charAddedConn:Disconnect() end
    charAddedConn = LocalPlayer.CharacterAdded:Connect(function()
        logger:info("Character added, checking for restoration...")
        
        if saveToggleEnabled and saveAnchorCFrame and not restoreInProgress then
            restoreInProgress = true
            
            task.spawn(function()
                -- Wait for character to be properly loaded
                task.wait(1.5)  -- Increased wait time for better reliability
                
                local hrp = ensureCharacterReady(10)
                if hrp then
                    logger:info("Restoring to saved anchor position...")
                    local success = self:TeleportToCFrame(saveAnchorCFrame)
                    if success then
                        logger:info("Successfully restored to anchor position on spawn")
                        if _G.WindUI then
                            _G.WindUI:Notify({
                                Title = "Position Restored",
                                Content = "Returned to saved position",
                                Icon = "map-pin",
                                Duration = 2
                            })
                        end
                    else
                        logger:warn("Failed to restore anchor position on spawn")
                    end
                else
                    logger:warn("Character not ready for restoration")
                end
                
                restoreInProgress = false
            end)
        end
    end)

    -- Guard loop to prevent drifting when toggle is ON
    if heartbeatConn then heartbeatConn:Disconnect() end
    heartbeatConn = RunService.Heartbeat:Connect(function()
        if not saveToggleEnabled or not saveAnchorCFrame or restoreInProgress then return end
        
        local hrp = getHRP()
        if not hrp then return end
        
        local currentPos = hrp.Position
        local anchorPos = saveAnchorCFrame.Position
        local distance = (currentPos - anchorPos).Magnitude
        
        -- Check if player has drifted too far or fallen
        if distance > 150 or currentPos.Y < (anchorPos.Y - 50) then
            logger:debug("Player drifted too far, restoring position...")
            self:TeleportToCFrame(saveAnchorCFrame)
        end
    end)

    -- Auto-restore on initial join if toggle was enabled
    if saveToggleEnabled and saveAnchorCFrame then
        task.spawn(function()
            task.wait(2.0)  -- Wait for game to fully load
            logger:info("Performing initial restoration on join...")
            local hrp = ensureCharacterReady(8)
            if hrp then
                self:TeleportToCFrame(saveAnchorCFrame)
            end
        end)
    end

    logger:info("SavePositionFeature started successfully")
    return true
end

function SavePositionFeature:Stop()
    if not isRunning then return true end
    
    isRunning = false
    if charAddedConn then 
        charAddedConn:Disconnect() 
        charAddedConn = nil 
    end
    if heartbeatConn then 
        heartbeatConn:Disconnect() 
        heartbeatConn = nil 
    end
    
    logger:info("SavePositionFeature stopped")
    return true
end

function SavePositionFeature:Cleanup()
    self:Stop()
    controls = {}
    savedPositions = {}
    selectedName = nil
    saveToggleEnabled = false
    saveAnchorCFrame = nil
    isInitialized = false
    restoreInProgress = false
    logger:info("SavePositionFeature cleanup completed")
end

-- ===== GUI-facing helpers =====

function SavePositionFeature:SetSelected(name)
    if type(name) == "string" and name ~= "" then
        if savedPositions[name] then
            selectedName = name
            persist()
            logger:info("Selected position:", name)
            return true
        else
            logger:warn("Position not found:", name)
        end
    end
    selectedName = nil
    persist()
    return false
end

function SavePositionFeature:AddPosition(name)
    if type(name) ~= "string" or name == "" then
        logger:warn("AddPosition requires a valid name")
        return false
    end
    
    local hrp = getHRP()
    if not hrp then
        logger:warn("Cannot add position: character not ready")
        return false
    end
    
    -- Validate the CFrame before saving
    local currentCF = hrp.CFrame
    if typeof(currentCF) ~= "CFrame" then
        logger:warn("Invalid CFrame detected")
        return false
    end
    
    savedPositions[name] = currentCF
    selectedName = name
    persist()
    
    if _G.WindUI then
        _G.WindUI:Notify({
            Title = "Position Added",
            Content = ("Saved '%s' at position"):format(name),
            Icon = "bookmark-plus",
            Duration = 2
        })
    end
    
    logger:info("Position added successfully:", name, "at", tostring(currentCF.Position))
    return true
end

-- NEW: Delete Position functionality
function SavePositionFeature:RemovePosition(name)
    name = name or selectedName
    if not name or type(name) ~= "string" then
        logger:warn("RemovePosition: no valid name provided")
        return false
    end
    
    if not savedPositions[name] then
        logger:warn("RemovePosition: position not found:", name)
        return false
    end
    
    savedPositions[name] = nil
    
    -- Clear selection if deleted position was selected
    if selectedName == name then
        selectedName = nil
    end
    
    persist()
    
    if _G.WindUI then
        _G.WindUI:Notify({
            Title = "Position Deleted",
            Content = ("Removed '%s'"):format(name),
            Icon = "trash",
            Duration = 2
        })
    end
    
    logger:info("Position removed:", name)
    return true
end

function SavePositionFeature:Teleport(name)
    local targetName = name or selectedName
    if not targetName then
        logger:warn("Teleport: no position selected")
        if _G.WindUI then
            _G.WindUI:Notify({
                Title = "Teleport Failed",
                Content = "Please select a saved position first",
                Icon = "alert-triangle",
                Duration = 3
            })
        end
        return false
    end

    local targetCF = savedPositions[targetName]
    if not targetCF then
        logger:warn("Teleport: position not found:", targetName)
        if _G.WindUI then
            _G.WindUI:Notify({
                Title = "Teleport Failed",
                Content = ("Position '%s' not found"):format(targetName),
                Icon = "x",
                Duration = 3
            })
        end
        return false
    end

    local success = self:TeleportToCFrame(targetCF)
    if success then
        if _G.WindUI then
            _G.WindUI:Notify({
                Title = "Teleport Success",
                Content = ("Teleported to '%s'"):format(targetName),
                Icon = "map-pin",
                Duration = 2
            })
        end
        logger:info("Successfully teleported to:", targetName)
    else
        if _G.WindUI then
            _G.WindUI:Notify({
                Title = "Teleport Failed",
                Content = ("Failed to teleport to '%s'"):format(targetName),
                Icon = "x",
                Duration = 3
            })
        end
        logger:warn("Teleport failed for:", targetName)
    end
    
    return success
end

function SavePositionFeature:SetSaveToggle(state)
    local newState = not not state
    
    if newState then
        -- Enabling Save Position
        local hrp = getHRP()
        if not hrp then
            logger:warn("SaveToggle: cannot enable, character not ready")
            return false
        end
        
        saveToggleEnabled = true
        saveAnchorCFrame = hrp.CFrame
        persist()
        
        -- Snap to current position immediately
        self:TeleportToCFrame(saveAnchorCFrame)
        
        logger:info("Save Position enabled, anchor set at:", tostring(saveAnchorCFrame.Position))
        
        if _G.WindUI then
            _G.WindUI:Notify({
                Title = "Save Position Enabled",
                Content = "Current position will be maintained",
                Icon = "anchor",
                Duration = 2
            })
        end
    else
        -- Disabling Save Position
        saveToggleEnabled = false
        saveAnchorCFrame = nil
        persist()
        
        logger:info("Save Position disabled")
        
        if _G.WindUI then
            _G.WindUI:Notify({
                Title = "Save Position Disabled",
                Content = "Position saving turned off",
                Icon = "anchor",
                Duration = 2
            })
        end
    end
    
    return true
end

-- Status and utility functions
function SavePositionFeature:GetStatus()
    local positionList = {}
    for name in pairs(savedPositions) do
        table.insert(positionList, name)
    end
    table.sort(positionList)
    
    return {
        initialized = isInitialized,
        running = isRunning,
        saveToggleEnabled = saveToggleEnabled,
        selectedName = selectedName,
        count = #positionList,
        names = positionList,
        hasAnchor = saveAnchorCFrame ~= nil,
        canPersist = CAN_FS
    }
end

function SavePositionFeature:GetSavedList()
    local list = {}
    for name in pairs(savedPositions) do
        table.insert(list, name)
    end
    table.sort(list)
    return list
end

-- NEW: Get detailed position info
function SavePositionFeature:GetPositionInfo(name)
    name = name or selectedName
    if not name or not savedPositions[name] then return nil end
    
    local cf = savedPositions[name]
    return {
        name = name,
        position = cf.Position,
        cframe = cf,
        isSelected = selectedName == name
    }
end

return SavePositionFeature