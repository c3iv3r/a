-- ==========================================
-- AUTO EXECUTE ON RECONNECT (QoT-Only, No Files)
-- API: Init(opts?), Start(), Stop(), Cleanup()
-- ==========================================

local AutoReexec = {}
AutoReexec.__index = AutoReexec

-- ===== Logger (colon-compatible, no-op fallback) =====
local _L = _G.Logger and _G.Logger.new and _G.Logger:new("AutoReexec")
local logger = _L or {}
function logger:debug(...) end
function logger:info(...)  end
function logger:warn(...)  end
function logger:error(...) end

-- ===== Services =====
local Players         = game:GetService("Players")
local TeleportService = game:GetService("TeleportService")

local LocalPlayer = Players.LocalPlayer

-- ===== State =====
local isInitialized = false
local isEnabled     = false
local connections   = {}
local armedOnce     = false       -- sudah nge-arm QoT minimal sekali
local lastArmStamp  = 0           -- os.clock() terakhir nge-arm
local qotFunc       = nil         -- fungsi queue_on_teleport terdeteksi

-- Payload config
--  - mode = "url"  → loadstring(game:HttpGet(url))()
--  - mode = "code" → langsung inject codeString
local opts = {
    mode        = "url",
    url         = "https://your.cdn/Loader.lua", -- ganti sendiri (kalau pakai mode url)
    codeString  = nil,                            -- kalau pakai mode code
    rearmEveryS = 20,                             -- re-arm berkala biar tetap siap
    addBootGuard = true,                          -- guard supaya gak double-boot
    minDelayAfterTeleportStartMs = 0,             -- 0=default; beberapa executor aman walau QoT dipanggil mepet
}

-- ===== Utils =====
local function addCon(con)
    if con then table.insert(connections, con) end
end

local function clearConnections()
    for _, c in ipairs(connections) do
        pcall(function() c:Disconnect() end)
    end
    connections = {}
end

local function detectQoT()
    -- urutan deteksi dari yang paling umum
    local f = rawget(getgenv(), "queue_on_teleport")
           or (syn and syn.queue_on_teleport)
           or (fluxus and fluxus.queue_on_teleport)
           or (krnl and krnl.queue_on_teleport)
           or (identifyexecutor and (select(1, pcall(function()
                local ex = identifyexecutor()
                -- beberapa executor expose lewat global tertentu; tambahkan di sini jika perlu
                return nil
            end))))
           or rawget(_G, "queue_on_teleport")

    -- Validasi minimal: harus callable
    if type(f) == "function" then
        return f
    end
    return nil
end

local function buildPayload()
    local guard = ""
    if opts.addBootGuard then
        -- guard untuk mencegah double-run kalau QoT di-arm lebih dari sekali
        guard = [[
if not getgenv()._DL_BOOTED then
    getgenv()._DL_BOOTED = true
else
    return
end
]]
    end

    local body = ""
    if opts.mode == "url" then
        assert(type(opts.url) == "string" and #opts.url > 5, "[AutoReexec] invalid url")
        body = string.format([[loadstring(game:HttpGet(%q))()]], opts.url)
    elseif opts.mode == "code" then
        assert(type(opts.codeString) == "string" and #opts.codeString > 0, "[AutoReexec] invalid codeString")
        body = opts.codeString
    else
        error("[AutoReexec] invalid mode: " .. tostring(opts.mode))
    end

    -- Tambahkan sedikit log supaya user bisa lihat dari console di next server
    local pre = [[
do
    local ok, err = pcall(function()
]]
    local post = [[
    end)
    if not ok then
        -- jangan spam notify; cukup print
        print("[AutoReexec] payload error:", err)
    end
end
]]

    return guard .. pre .. "        " .. body .. "\n" .. post
end

local function armQoT(reason)
    if not isEnabled then return false, "disabled" end
    if not qotFunc then
        qotFunc = detectQoT()
        if not qotFunc then
            logger:warn("No queue_on_teleport function detected; cannot arm payload.")
            return false, "no_qot"
        end
    end

    local payload
    local ok, err = pcall(function()
        payload = buildPayload()
    end)
    if not ok then
        logger:error("Build payload failed:", err)
        return false, err
    end

    local ok2, err2 = pcall(function()
        qotFunc(payload)
    end)
    if ok2 then
        armedOnce = true
        lastArmStamp = os.clock()
        logger:info("QoT armed (" .. tostring(reason or "manual") .. ").")
        return true
    else
        logger:error("Arm QoT failed:", err2)
        return false, err2
    end
end

local function keepArmedLoop()
    -- re-arm berkala (idempotent; aman karena ada boot guard di payload)
    task.spawn(function()
        while isEnabled do
            local now = os.clock()
            if (now - lastArmStamp) >= math.max(5, tonumber(opts.rearmEveryS) or 20) then
                armQoT("periodic")
            end
            task.wait(5)
        end
    end)
end

-- ===== Public API =====
function AutoReexec:Init(userOpts)
    if isInitialized then
        logger:debug("Init called again; updating opts.")
    end
    if type(userOpts) == "table" then
        for k, v in pairs(userOpts) do
            if opts[k] ~= nil then
                opts[k] = v
            end
        end
    end
    qotFunc = detectQoT()
    if qotFunc then
        logger:info("QoT detected and ready.")
    else
        logger:warn("QoT not found now; will retry on Start().")
    end
    isInitialized = true
    return true
end

function AutoReexec:SetPayload(conf)
    -- conf = { mode="url"/"code", url="...", codeString="..." }
    assert(type(conf) == "table", "SetPayload expects table")
    if conf.mode then
        assert(conf.mode == "url" or conf.mode == "code", "mode must be 'url' or 'code'")
        opts.mode = conf.mode
    end
    if conf.url ~= nil then
        opts.url = conf.url
    end
    if conf.codeString ~= nil then
        opts.codeString = conf.codeString
    end
    logger:info("Payload updated. Mode:", opts.mode)
    -- auto re-arm kalau sedang enabled
    if isEnabled then
        armQoT("payload_update")
    end
end

function AutoReexec:Start()
    if not isInitialized then
        logger:warn("Start() called before Init().")
        return false
    end
    if isEnabled then
        logger:debug("Already running.")
        return true
    end
    isEnabled = true
    armedOnce = false

    -- sinkronisasi ulang QoT
    qotFunc = qotFunc or detectQoT()
    if not qotFunc then
        logger:warn("QoT not found on Start(); will keep trying.")
    end

    clearConnections()

    -- Arm segera saat Start
    armQoT("start")

    -- Re-arm saat teleport dimulai (biar mepet ke event teleport)
    addCon(LocalPlayer.OnTeleport:Connect(function(state)
        -- state: Enum.TeleportState
        -- Kita arm ulang di semua state yang menandakan proses mulai
        if state == Enum.TeleportState.Started or state == Enum.TeleportState.RequestedFromServer
           or state == Enum.TeleportState.InProgress then
            if opts.minDelayAfterTeleportStartMs > 0 then
                task.wait((opts.minDelayAfterTeleportStartMs or 0)/1000)
            end
            armQoT("on_teleport_" .. tostring(state))
        end
    end))

    -- Loop periodic re-arm
    keepArmedLoop()

    logger:info("AutoReexec started.")
    return true
end

function AutoReexec:Stop()
    if not isEnabled then
        logger:debug("Already stopped.")
        return true
    end
    isEnabled = false
    clearConnections()
    logger:info("AutoReexec stopped.")
    return true
end

function AutoReexec:Cleanup()
    self:Stop()
    isInitialized = false
    logger:info("Cleaned up.")
end

-- Status helper (opsional)
function AutoReexec:GetStatus()
    return {
        initialized = isInitialized,
        enabled = isEnabled,
        qot = (qotFunc ~= nil),
        armedOnce = armedOnce,
        lastArm = lastArmStamp,
        mode = opts.mode,
    }
end

return AutoReexec
