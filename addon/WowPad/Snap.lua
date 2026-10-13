-- Snap.lua - dragging in edit mode with a soft snap to the screen's vertical centre line: within
-- SNAP units the frame's centre locks onto the line (a gold guide shows), pull further and it lets
-- go. Up/down stays free. Also the edit-mode mover for frames that are not the bar.

local WP = WowPad
local SNAP = 12   -- UI units

local guide = CreateFrame("Frame", nil, UIParent)
guide:SetFrameStrata("TOOLTIP")
guide:SetAllPoints(UIParent)
guide:Hide()
local line = guide:CreateTexture(nil, "OVERLAY")
line:SetTexture(1, 0.82, 0.2, 0.7)
line:SetWidth(2)
line:SetPoint("TOP", UIParent, "TOP", 0, 0)
line:SetPoint("BOTTOM", UIParent, "BOTTOM", 0, 0)

-- UIParent's centre in frame f's own units (what f:GetCenter() and its SetPoint offsets use).
local function MidOf(f)
  local k = UIParent:GetEffectiveScale() / f:GetEffectiveScale()
  return UIParent:GetWidth() * k / 2, UIParent:GetHeight() * k / 2
end

-- Positions are kept as the frame centre's offset from the screen centre, so a frame stays where
-- it was (a centred one stays centred) when the UI scale or the window size changes. Older saves
-- (p.x, p.y from the bottom-left corner) are converted the first time they are placed.
function WP.PlaceAt(f, p)
  if p.x and not p.dx then
    local mx, my = MidOf(f)
    p.dx, p.dy = p.x - mx, p.y - my
  end
  p.x, p.y = nil, nil
  if not p.dx then return false end
  f:ClearAllPoints()
  f:SetPoint("CENTER", UIParent, "CENTER", p.dx, p.dy)
  return true
end

-- Remember where f is now, in p.
function WP.SavePlace(f, p)
  local x, y = f:GetCenter()
  if not x then return end
  local mx, my = MidOf(f)
  p.dx, p.dy = x - mx, y - my
  -- a centre within a hair of the line is on it, so rounding never leaves it a pixel off
  if math.abs(p.dx) < 0.5 then p.dx = 0 end
  p.x, p.y = nil, nil
end

-- f's scale is changing from old to new: keep its centre where it is on screen.
function WP.RescalePlace(p, old, new)
  if p.dx then p.dx, p.dy = p.dx * old / new, p.dy * old / new end
end

local dragging, offX, offY
local driver = CreateFrame("Frame")
driver:Hide()
driver:SetScript("OnUpdate", function()
  local f = dragging
  if not f then driver:Hide(); return end
  local eff = f:GetEffectiveScale()
  local cx, cy = GetCursorPosition()
  local x, y = cx / eff + offX, cy / eff + offY
  -- the screen centre and the snap distance in the frame's own units
  local ui = UIParent:GetEffectiveScale()
  local midX, midY = MidOf(f)
  local snapped = math.abs(x - midX) <= SNAP * ui / eff
  if snapped then x = midX; guide:Show() else guide:Hide() end
  f:ClearAllPoints()
  f:SetPoint("CENTER", UIParent, "CENTER", x - midX, y - midY)
end)

-- Start dragging frame f (from OnDragStart).
function WP.SnapDragStart(f)
  local eff = f:GetEffectiveScale()
  local cx, cy = GetCursorPosition()
  local fx, fy = f:GetCenter()
  if not fx then return end
  offX, offY = fx - cx / eff, fy - cy / eff
  dragging = f
  driver:Show()
end

-- Stop dragging (from OnDragStop). Returns the frame's centre in its own units.
function WP.SnapDragStop()
  local f = dragging
  dragging = nil
  driver:Hide()
  guide:Hide()
  if f then return f:GetCenter() end
end

---------------------------------------------------------------------------
-- Edit-mode mover for a frame that is not the bar (the main menu wheel, the utility ring): a blue
-- "drag / wheel" box, `size` square in the frame's middle (default: the whole frame). Drag moves
-- the frame (with the centre-line snap), the mouse wheel resizes it. Saved account-wide in
-- WowPadDB.movers[key].
---------------------------------------------------------------------------
local function MoverDB(key)
  WowPadDB.movers = WowPadDB.movers or {}
  WowPadDB.movers[key] = WowPadDB.movers[key] or {}
  return WowPadDB.movers[key]
end

-- Put the frame where it was saved (or at its default spot), at its size.
function WP.ApplyMoverPos(f)
  if not WowPadDB then return end
  local p = MoverDB(f.moverKey)
  f:SetScale(p.scale or 1)
  if not WP.PlaceAt(f, p) then
    local d = f.moverDefault
    f:ClearAllPoints()
    f:SetPoint(d[1], d[2], d[3], d[4], d[5])
  end
end

-- `default` is the frame's home point: { point, relativeTo, relativePoint, x, y }.
function WP.MakeMover(f, key, label, default, size, minScale, maxScale)
  f.moverKey = key
  f.moverDefault = default
  f:SetClampedToScreen(true)
  local m = CreateFrame("Frame", nil, f)
  if size then
    m:SetPoint("CENTER", f, "CENTER", 0, 0)
    m:SetWidth(size)
    m:SetHeight(size)
  else
    m:SetAllPoints(f)
  end
  m:SetFrameLevel(f:GetFrameLevel() + 30)
  m:SetBackdrop({ bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
                  edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
                  tile = true, tileSize = 16, edgeSize = 14,
                  insets = { left = 3, right = 3, top = 3, bottom = 3 } })
  m:SetBackdropColor(0.2, 0.5, 1, 0.35)
  m:SetBackdropBorderColor(0.35, 0.7, 1, 0.8)
  local t = m:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  t:SetPoint("CENTER", m, "CENTER", 0, 0)
  t:SetText(label .. "\n(drag / wheel)")
  m:EnableMouse(true)
  m:RegisterForDrag("LeftButton")
  m:SetScript("OnDragStart", function() WP.SnapDragStart(f) end)
  m:SetScript("OnDragStop", function()
    WP.SnapDragStop()
    WP.SavePlace(f, MoverDB(key))
  end)
  m:EnableMouseWheel(true)
  m:SetScript("OnMouseWheel", function()
    local p = MoverDB(key)
    local old = f:GetScale()
    local new = math.max(minScale or 0.5, math.min(maxScale or 1.5, (p.scale or 1) + arg1 * 0.05))
    if not p.dx then WP.SavePlace(f, p) end
    WP.RescalePlace(p, old, new)
    p.scale = new
    WP.ApplyMoverPos(f)
  end)
  m:Hide()
  f.mover = m
  return m
end
