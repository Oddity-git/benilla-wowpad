-- PartyHighlight.lua - healer mode: after a bumper tap or flick (hold the ally bumper, flick the
-- right stick), a gold frame briefly marks the targeted member's unit frame, then fades. Works
-- with any unit frames that keep their unit in a `unit` field (Blizzard's, and most 1.12 unit
-- frame addons). Only pictures, so it works in combat too. Ported from WowPad 1.4.2.

local WP = WowPad
local SHOW_FOR, FADE = 1.5, 0.3
local UNITS = { player = true, party1 = true, party2 = true, party3 = true, party4 = true }

local hl = CreateFrame("Frame", "WowPadPartyHighlight", UIParent)
hl:SetFrameStrata("HIGH")
hl:SetBackdrop({ edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border", edgeSize = 14 })
hl:SetBackdropBorderColor(1, 0.82, 0.1, 1)
local glow = hl:CreateTexture(nil, "BACKGROUND")
glow:SetTexture(1, 0.82, 0.1, 0.12)
glow:SetPoint("TOPLEFT", hl, "TOPLEFT", 3, -3)
glow:SetPoint("BOTTOMRIGHT", hl, "BOTTOMRIGHT", -3, 3)
hl:Hide()

local function UnitOf(f)
  local u = rawget(f, "unit")
  if type(u) == "string" then return u end
end

-- Unit frames on screen for you and your party, found by their `unit` field. Re-scanned at most
-- every few seconds.
local frames, scannedAt = {}, -100
local function Scan()
  frames = {}
  local f = EnumerateFrames()
  while f do
    if f.IsVisible and f:IsVisible() then
      local u = UnitOf(f)
      if u and UNITS[u] and f:GetWidth() > 20 and f:GetHeight() > 10 then
        frames[table.getn(frames) + 1] = f
      end
    end
    f = EnumerateFrames(f)
  end
  scannedAt = GetTime()
end

-- The frame showing your current target; if several do, the biggest one.
local function TargetFrame()
  if not UnitExists("target") then return nil end
  if GetTime() - scannedAt > 3 then Scan() end
  local best, area
  for i = 1, table.getn(frames) do
    local f = frames[i]
    local u = UnitOf(f)
    if f:IsVisible() and u and UnitIsUnit(u, "target") then
      local a = f:GetWidth() * f:GetHeight()
      if not best or a > area then best, area = f, a end
    end
  end
  return best
end

-- The updater is a separate, shown frame: a hidden frame's OnUpdate never runs.
local driver = CreateFrame("Frame", nil, UIParent)
local untilTime = 0
local function Update()
  local left = untilTime - GetTime()
  if left <= 0 then hl:Hide(); driver:SetScript("OnUpdate", nil) return end
  local f = TargetFrame()
  if not f then hl:Hide() return end
  if hl.on ~= f then
    hl.on = f
    hl:ClearAllPoints()
    hl:SetPoint("TOPLEFT", f, "TOPLEFT", -4, 4)
    hl:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", 4, -4)
  end
  if left < FADE then hl:SetAlpha(left / FADE) else hl:SetAlpha(1) end
  hl:Show()
end

-- Core's party step calls this after it targets a member.
function WP.PartyFlicked()
  untilTime = GetTime() + SHOW_FOR
  hl.on = nil
  driver:SetScript("OnUpdate", Update)
  Update()
end
