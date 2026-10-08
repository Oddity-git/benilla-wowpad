-- MapCursor.lua - a visible cursor on the world map in controller mode, like the console
-- versions: a gold diamond, crosshair lines across the map, cursor and player coordinates.
--
-- The right stick moves the pointer while the map is open and the D-pad jumps it to the map's
-- buttons (Core.lua's Nav); this draws it in place of WowPad's pointer (Crosshair.lua). A is a
-- left click (zoom in, or the button under it), X a right click (zoom out), B goes back a level
-- (zone, continent, world), then closes the map.

local WP = WowPad

local holder, diamond, hLine, vLine, coords, hint

local function Build()
  local detail = WorldMapDetailFrame
  if not detail then return false end
  if holder then return true end
  holder = CreateFrame("Frame", "WowPadMapCursor", detail)
  holder:SetAllPoints(detail)
  holder:SetFrameStrata("TOOLTIP")       -- above the map's pins
  holder:EnableMouse(false)

  hLine = holder:CreateTexture(nil, "ARTWORK")
  hLine:SetTexture(1, 0.82, 0.1, 0.85)
  hLine:SetHeight(2)
  vLine = holder:CreateTexture(nil, "ARTWORK")
  vLine:SetTexture(1, 0.82, 0.1, 0.85)
  vLine:SetWidth(2)

  diamond = holder:CreateTexture(nil, "OVERLAY")
  diamond:SetTexture("Interface\\AddOns\\WowPad\\Textures\\mapcursor")
  diamond:SetWidth(30)
  diamond:SetHeight(30)

  coords = holder:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
  coords:SetPoint("BOTTOMLEFT", detail, "BOTTOMLEFT", 10, 10)
  coords:SetJustifyH("LEFT")

  hint = WP.NewKeyLine(holder, "GameFontHighlight", 20)
  hint:SetPoint("BOTTOM", detail, "BOTTOM", 0, 10)
  holder:Hide()
  return true
end

-- Wanted while the map is open in controller mode.
local function Wanted()
  return WP.mode == "controller" and WorldMapFrame ~= nil and WorldMapFrame:IsVisible()
end
WP.MapCursorWanted = Wanted

local function Continent() return GetCurrentMapContinent() or 0 end

-- B on the map: zoom out a level while there is one, else close it.
function WP.MapBack()
  if not Wanted() then return false end
  if Continent() > 0 and WorldMapZoomOutButton and WorldMapZoomOutButton:IsVisible() then
    WorldMapZoomOutButton:Click()
  else
    ToggleWorldMap()
  end
  return true
end

local lastHint
local function Hints()
  local back = Continent() > 0 and "Back" or "Close"
  if back == lastHint then return end
  lastHint = back
  hint:SetParts({ { key = "A", text = "Zoom In" }, { key = "X", text = "Zoom Out" },
                  { key = "D-pad", text = "Buttons" }, { key = "B", text = back } }, 14)
end

local active, acc = false, 0
local driver = CreateFrame("Frame")
driver:SetScript("OnUpdate", function()
  acc = acc + arg1
  if acc < 0.016 then return end
  acc = 0
  if not Wanted() then
    if active then active = false; holder:Hide() end
    return
  end
  if not Build() then return end
  local detail = WorldMapDetailFrame
  local left, bottom = detail:GetLeft(), detail:GetBottom()
  if not left then return end
  local s = detail:GetEffectiveScale()
  local cx, cy = GetCursorPosition()
  local x, y = cx / s - left, cy / s - bottom
  if not active then active = true; lastHint = nil; holder:Show() end
  Hints()

  local w, h = detail:GetWidth(), detail:GetHeight()
  diamond:ClearAllPoints()
  diamond:SetPoint("CENTER", detail, "BOTTOMLEFT", x, y)
  local inside = x >= 0 and x <= w and y >= 0 and y <= h
  if inside then
    hLine:ClearAllPoints()
    hLine:SetPoint("LEFT", detail, "BOTTOMLEFT", 0, y)
    hLine:SetPoint("RIGHT", detail, "BOTTOMRIGHT", 0, y)
    vLine:ClearAllPoints()
    vLine:SetPoint("BOTTOM", detail, "BOTTOMLEFT", x, 0)
    vLine:SetPoint("TOP", detail, "TOPLEFT", x, 0)
    hLine:Show(); vLine:Show()
  else
    hLine:Hide(); vLine:Hide()
  end

  local text = ""
  if inside then
    text = string.format("Cursor: %.1f, %.1f", x / w * 100, (1 - y / h) * 100)
  end
  local px, py = GetPlayerMapPosition("player")
  if px and (px > 0 or py > 0) then
    if text ~= "" then text = text .. "\n" end
    text = text .. string.format("Player: %.1f, %.1f", px * 100, py * 100)
  end
  coords:SetText(text)
end)
