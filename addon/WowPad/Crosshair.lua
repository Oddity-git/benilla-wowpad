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
