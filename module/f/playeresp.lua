-- ===========================
-- PLAYER BODY ESP (Highlight)
-- API: Init(self, controls?), Start(), Stop(), Cleanup()
-- Hanya untuk player lain (exclude LocalPlayer)
-- ===========================
local BodyEsp = {}
BodyEsp.__index = BodyEsp

-- ===== Logger (fallback) =====
local _L = _G.Logger and _G.Logger.new and _G.Logger:new("PlayerBodyESP")
local logger = _L or {}
function logger:debug(...) end
function logger:info(...)  end
function logger:warn(...)  end

-- ===== Services =====
local Players    = game:GetService("Players")
local RunService = game:GetService("RunService") -- (dipakai untuk konsistensi API)
local LocalPlayer= Players.LocalPlayer

-- ===== State =====
local inited, running = false, false
local conAdded, conRemoving
local registry = {}  -- [player] = { hl=Highlight, charCon=RBXScriptConnection }

-- ===== CONFIG (UBAH DI SINI) =====
local CONFIG = {
  FillColor         = Color3.fromRGB(125, 85, 255), -- warna isi siluet
  OutlineColor      = Color3.fromRGB(125, 85, 255), -- warna outline
  FillTransparency  = 0.0, -- 0.0 = solid, 1.0 = tembus
  OutlineTransparency= 0.0, -- 0.0 = solid, 1.0 = tembus
  AlwaysOnTop       = true, -- tembus tembok (AlwaysOnTop)
}

-- ===== Helpers =====
local function attachHighlight(plr, character)
  if not character or not character:IsA("Model") then return end
  local r = registry[plr] or {}
  -- reuse kalau ada
  local hl = r.hl
  if not hl or not hl.Parent then
    hl = Instance.new("Highlight")
    hl.Name = "ESP_Highlight_"..plr.Name
    r.hl = hl
  end

  -- apply config
  hl.Adornee = character
  hl.FillColor = CONFIG.FillColor
  hl.OutlineColor = CONFIG.OutlineColor
  hl.FillTransparency = CONFIG.FillTransparency
  hl.OutlineTransparency = CONFIG.OutlineTransparency
  hl.DepthMode = CONFIG.AlwaysOnTop and Enum.HighlightDepthMode.AlwaysOnTop
                                   or  Enum.HighlightDepthMode.Occluded
  hl.Enabled = running
  hl.Parent = character -- follow lifecycle character

  -- listen respawn: re-attach saat CharacterAdded
  if r.charCon then r.charCon:Disconnect() end
  r.charCon = plr.CharacterAdded:Connect(function(newChar)
    attachHighlight(plr, newChar)
  end)

  registry[plr] = r
  logger:debug("Highlight attached:", plr.Name)
end

local function build(plr)
  if plr == LocalPlayer then return end
  if registry[plr] then return end
  registry[plr] = {}
  if plr.Character then attachHighlight(plr, plr.Character) end
end

local function destroy(plr)
  local r = registry[plr]
  if not r then return end
  if r.charCon then r.charCon:Disconnect() end
  if r.hl and r.hl.Destroy then pcall(function() r.hl:Destroy() end) end
  registry[plr] = nil
  logger:debug("Highlight destroyed:", plr.Name)
end

-- ===== Lifecycle =====
function BodyEsp:Init(_, controls)
  if inited then return true end

  -- build awal untuk semua player lain
  for _, p in ipairs(Players:GetPlayers()) do
    if p ~= LocalPlayer then build(p) end
  end

  -- join/leave
  conAdded    = Players.PlayerAdded:Connect(function(p)
    if p ~= LocalPlayer then
      build(p)
      if running and registry[p] and registry[p].hl then
        registry[p].hl.Enabled = true
      end
    end
  end)
  conRemoving = Players.PlayerRemoving:Connect(function(p) destroy(p) end)

  -- wiring toggle kalau library punya SetCallback()
  if controls and controls.Toggle and controls.Toggle.SetCallback then
    controls.Toggle:SetCallback(function(v) if v then self:Start() else self:Stop() end end)
  end

  inited = true
  logger:info("PlayerBodyESP Init")
  return true
end

function BodyEsp:Start()
  if running then return end
  if not inited then self:Init() end
  running = true
  -- enable semua highlight
  for _, r in pairs(registry) do
    if r.hl then r.hl.Enabled = true end
  end
  logger:info("PlayerBodyESP Started")
end

function BodyEsp:Stop()
  if not running then return end
  running = false
  -- disable tanpa destroy
  for _, r in pairs(registry) do
    if r.hl then r.hl.Enabled = false end
  end
  logger:info("PlayerBodyESP Stopped")
end

function BodyEsp:Cleanup()
  self:Stop()
  -- hancurkan semua highlight & koneksi
  for plr in pairs(registry) do destroy(plr) end
  registry = {}
  if conAdded then conAdded:Disconnect(); conAdded = nil end
  if conRemoving then conRemoving:Disconnect(); conRemoving = nil end
  inited = false
  logger:info("PlayerBodyESP Cleaned up")
end

return BodyEsp