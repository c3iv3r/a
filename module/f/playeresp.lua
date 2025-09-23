-- ===========================
-- PLAYER ESP FEATURE (Client)
-- Hanya untuk player lain (exclude LocalPlayer)
-- ===========================
local PlayerEsp = {}
PlayerEsp.__index = PlayerEsp

local _L = _G.Logger and _G.Logger.new and _G.Logger:new("PlayerESP")
local logger = _L or {}
function logger:debug(...) end
function logger:info(...)  end

local Players, RunService = game:GetService("Players"), game:GetService("RunService")
local Camera, LocalPlayer = workspace.CurrentCamera, Players.LocalPlayer

local inited, running = false, false
local conRender, conAdded, conRemoving
local drawOK, registry = false, {}

-- === CONFIG (ubah sesuka hati) ===
local CONFIG = {
  useBox          = true,
  useTracer       = true,
  showName        = true,
  espColor        = Color3.fromRGB(0, 200, 255), -- <<== UBAH WARNA DISINI
  nameColor       = Color3.fromRGB(255, 255, 255),
  nameOutline     = Color3.fromRGB(0, 0, 0),
  boxThickness    = 1,
  tracerThickness = 1,
  maxDistance     = 2000,
}

local function HRP(c) return c and (c:FindFirstChild("HumanoidRootPart") or c:FindFirstChild("UpperTorso") or c:FindFirstChild("Head")) end
local function w2s(p) local v,on=Camera:WorldToViewportPoint(p); return Vector2.new(v.X,v.Y),on,v.Z end
local function boxWH(hrp,c)
  local head=c:FindFirstChild("Head")
  local h=math.max(((head and head.Position or hrp.Position+Vector3.new(0,2,0))-hrp.Position).Magnitude*3,2)
  return h*0.6,h
end

local function newSq() local s=Drawing.new("Square");s.Visible=false;s.Thickness=CONFIG.boxThickness;s.Filled=false;return s end
local function newTx() local t=Drawing.new("Text");t.Visible=false;t.Size=13;t.Center=true;t.Outline=true;t.Color=CONFIG.nameColor;t.OutlineColor=CONFIG.nameOutline;return t end
local function newLn() local l=Drawing.new("Line");l.Visible=false;l.Thickness=CONFIG.tracerThickness;return l end
local function rm(o) if o then pcall(function() o:Remove() end) end end

local function build(plr)
  if plr==LocalPlayer or registry[plr] then return end
  registry[plr]={box=newSq(),name=newTx(),tracer=newLn()}
end
local function destroy(plr)
  local r=registry[plr]; if not r then return end
  rm(r.box);rm(r.name);rm(r.tracer);registry[plr]=nil
end

local function onRender()
  if not running then return end
  for _,plr in ipairs(Players:GetPlayers()) do
    if plr~=LocalPlayer then
      if not registry[plr] then build(plr) end
      local r=registry[plr]; local c=plr.Character; local hrp=HRP(c)
      if not hrp then
        if r.box then r.box.Visible=false end
        if r.name then r.name.Visible=false end
        if r.tracer then r.tracer.Visible=false end
      else
        if CONFIG.maxDistance and (Camera.CFrame.Position-hrp.Position).Magnitude>CONFIG.maxDistance then
          if r.box then r.box.Visible=false end
          if r.name then r.name.Visible=false end
          if r.tracer then r.tracer.Visible=false end
        else
          local p2,on,z=w2s(hrp.Position)
          if on and z>0 then
            local w,h=boxWH(hrp,c)
            if r.box then
              r.box.Visible=CONFIG.useBox
              r.box.Color=CONFIG.espColor
              r.box.Position=Vector2.new(p2.X-w/2,p2.Y-h/2)
              r.box.Size=Vector2.new(w,h)
            end
            if r.name then
              r.name.Visible=CONFIG.showName
              r.name.Text=plr.Name
              r.name.Position=Vector2.new(p2.X,p2.Y-(h/2)-10)
            end
            if r.tracer then
              r.tracer.Visible=CONFIG.useTracer
              r.tracer.Color=CONFIG.espColor
              r.tracer.From=Vector2.new(Camera.ViewportSize.X/2,Camera.ViewportSize.Y-2)
              r.tracer.To=p2
            end
          end
        end
      end
    end
  end
end

function PlayerEsp:Init(_,controls)
  if inited then return true end
  drawOK=pcall(function() local t=Drawing.new("Square");t:Remove() end)
  for _,p in ipairs(Players:GetPlayers()) do if p~=LocalPlayer then build(p) end end
  conAdded=Players.PlayerAdded:Connect(function(p) if running then build(p) end end)
  conRemoving=Players.PlayerRemoving:Connect(destroy)
  if controls and controls.Toggle and controls.Toggle.SetCallback then
    controls.Toggle:SetCallback(function(v) if v then self:Start() else self:Stop() end end)
  end
  inited=true;logger:info("PlayerESP Init");return true
end

function PlayerEsp:Start()
  if running then return end
  running=true;conRender=RunService.RenderStepped:Connect(onRender)
  logger:info("PlayerESP Started")
end

function PlayerEsp:Stop()
  if not running then return end
  running=false;if conRender then conRender:Disconnect();conRender=nil end
  for _,r in pairs(registry) do if r.box then r.box.Visible=false end;if r.name then r.name.Visible=false end;if r.tracer then r.tracer.Visible=false end end
  logger:info("PlayerESP Stopped")
end

function PlayerEsp:Cleanup()
  self:Stop();for p in pairs(registry) do destroy(p) end;registry={}
  if conAdded then conAdded:Disconnect() end;if conRemoving then conRemoving:Disconnect() end
  inited=false;logger:info("PlayerESP Cleaned up")
end

return PlayerEsp