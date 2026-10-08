-- Crosshair.lua - a dot at the crosshair while the right stick drives the camera (controller mode,
-- camera look on or paused for the peek), plus the tooltip of the unit under it, as a mouse
-- pointer would give.
--
-- The game does not track the unit under the pointer during camera look, so the tooltip shows
-- when the right stick rests and camera look pauses (the peek, Core.lua); benilla-wowpad parks the
-- hidden pointer at the crosshair for it.
-- Dot colour: red = attackable, green = friendly, yellow = neutral, white = nothing.
-- /wp crosshair toggles it, /wp peek toggles the peek.

local WP = WowPad

local C = CreateFrame("Frame", "WowPadCrosshair", UIParent)
C:SetWidth(10)
C:SetHeight(10)
C:SetFrameStrata("HIGH")
C:Hide()
local dot = C:CreateTexture(nil, "OVERLAY")
dot:SetAllPoints(C)
dot:SetTexture("Interface\\AddOns\\WowPad\\Textures\\dot")

local ownTooltip, lastName, acc = false, nil, 0

local function HideOurTooltip()
  if ownTooltip and GameTooltip:IsOwned(UIParent) then GameTooltip:Hide() end
  ownTooltip, lastName = false, nil
end
C:SetScript("OnHide", HideOurTooltip)

-- The crosshair: CrosshairY (wowpad.ini) above the screen centre, where the pointer is parked.
local function Place()
  C:ClearAllPoints()
  C:SetPoint("CENTER", UIParent, "CENTER", 0, (WP.crosshairFrac or 0) * UIParent:GetHeight())
end

local driver = CreateFrame("Frame")
driver:SetScript("OnUpdate", function()
  acc = acc + arg1
  if acc < 0.03 then return end
  acc = 0
  local active = WowPadDB and WowPadDB.crosshair ~= false and WP.mode == "controller"
                 and not WP.pointer and (IsMouselooking() or WP.peeking)
  if not active then
    if C:IsShown() then C:Hide() end
    return
  end
  Place()
  if not C:IsShown() then C:Show() end
  if UnitExists("mouseover") then
    if UnitCanAttack("player", "mouseover") then dot:SetVertexColor(1, 0.25, 0.2)
    elseif UnitIsFriend("player", "mouseover") then dot:SetVertexColor(0.3, 1, 0.3)
    else dot:SetVertexColor(1, 0.85, 0.2) end
    local name = UnitName("mouseover")
    if not ownTooltip or name ~= lastName or not GameTooltip:IsVisible() then
      GameTooltip_SetDefaultAnchor(GameTooltip, UIParent)
      GameTooltip:SetUnit("mouseover")
      ownTooltip, lastName = true, name
    end
  else
    dot:SetVertexColor(1, 1, 1)
    HideOurTooltip()
  end
end)

function WP.ToggleCrosshair()
  WowPadDB.crosshair = (WowPadDB.crosshair == false)
  WP.Print("Crosshair: " .. (WowPadDB.crosshair and "on" or "off"))
end

-- The pointer, drawn: while the pad drives, benilla-wowpad hides the OS cursor (Wayland cannot
-- move it, and ending camera look would flash it) and moves benilla's pointer itself, so this
-- draws the game's cursor art there. Hidden during camera look and the peek (the dot is the
-- pointer then) and on the world map (MapCursor.lua draws it there).
local P = CreateFrame("Frame", "WowPadPointer", UIParent)
P:SetFrameStrata("TOOLTIP")
P:SetFrameLevel(100)
P:SetWidth(32)
P:SetHeight(32)
P:Hide()
local ptex = P:CreateTexture(nil, "OVERLAY")
ptex:SetAllPoints(P)
local ART = {
  point  = "Interface\\Cursor\\Point",
  attack = "Interface\\Cursor\\Attack",
  speak  = "Interface\\Cursor\\Speak",
  cast   = "Interface\\Cursor\\Cast",
}
local curArt
WP.screenH = 768

-- benilla-wowpad: the window's height in pixels, so the pointer is 32 pixels like the real one.
function WowPad_SetScreen(h)
  if h and h > 0 then WP.screenH = h end
end

local pdriver = CreateFrame("Frame")
pdriver:SetScript("OnUpdate", function()
  if not (WP.mode == "controller" and not IsMouselooking() and not WP.peeking)
     or (WP.MapCursorWanted and WP.MapCursorWanted()) then
    if P:IsShown() then P:Hide() end
    return
  end
  local x, y = GetCursorPosition()
  local s = UIParent:GetEffectiveScale()
  local size = 32 * GetScreenHeight() / WP.screenH   -- 32 pixels in UIParent units
  P:SetWidth(size)
  P:SetHeight(size)
  P:ClearAllPoints()
  P:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", x / s, y / s)
  local art = ART.point
  if SpellIsTargeting() then art = ART.cast
  elseif UnitExists("mouseover") then
    if UnitCanAttack("player", "mouseover") then art = ART.attack
    elseif not UnitIsPlayer("mouseover") then art = ART.speak end
  end
  if curArt ~= art then ptex:SetTexture(art); curArt = art end
  if not P:IsShown() then P:Show() end
end)
