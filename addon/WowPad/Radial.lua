-- Radial.lua - the Start button's main menu wheel.
--
-- 8 wedges per page, LB/RB change page, D-pad or right-stick pointer selects, A opens, B or Start
-- closes. Also the wheel art shared with the utility ring (WP.BuildWheelArt).

local WP = WowPad

local function Toggle(name)
  local f = getglobal(name)
  if not f then return end
  if f:IsVisible() then HideUIPanel(f) else ShowUIPanel(f) end
end

local PAGES = {
  {
    { "Character",  "Interface\\Icons\\INV_Helmet_25",        function() ToggleCharacter("PaperDollFrame") end },
    { "Bags",       "Interface\\Icons\\INV_Misc_Bag_08",      function() OpenAllBags() end },
    { "Spellbook",  "Interface\\Icons\\INV_Misc_Book_09",     function() ToggleSpellBook(BOOKTYPE_SPELL) end },
    { "Talents",    "Interface\\Icons\\Ability_Marksmanship", function() if ToggleTalentFrame then ToggleTalentFrame() end end },
    { "Game Menu",  "Interface\\Icons\\INV_Misc_Gear_01",     function() Toggle("GameMenuFrame") end },
    { "World Map",  "Interface\\Icons\\INV_Misc_Map_01",      function() ToggleWorldMap() end },
    { "Social",     "Interface\\Icons\\INV_Letter_15",        function() ToggleFriendsFrame() end },
    { "Quest Log",  "Interface\\Icons\\INV_Misc_Note_01",     function() Toggle("QuestLogFrame") end },
  },
  {
    { "Guild",          "Interface\\Icons\\INV_Shirt_GuildTabard_01",       function() ToggleFriendsFrame(3) end },
    { "Macros",         "Interface\\Icons\\INV_Misc_Note_06",               function() if ShowMacroFrame then ShowMacroFrame() end end },
    { "Chat",           "Interface\\Icons\\Spell_Holy_PrayerOfSpirit",      function() ChatFrame_OpenChat("") end },
    { "Help",           "Interface\\Icons\\INV_Misc_QuestionMark",          function() ToggleHelpFrame() end },
    { "Edit Bar",       "Interface\\Icons\\Trade_Engineering",              function() WP.ToggleEdit() end },
    { "Blizzard Bars",  "Interface\\Icons\\INV_Misc_EngGizmos_01",          function() WP.ToggleBlizzBars() end },
    { "Crosshair",      "Interface\\Icons\\Ability_Hunter_SniperShot",      function() WP.ToggleCrosshair() end },
    { "Bar Visibility", "Interface\\Icons\\Spell_Shadow_DetectInvisibility", function() WP.Bar.ToggleAlways() end },
  },
}
local RADIUS, WEDGE = 120, 44     -- icon distance from the centre, icon size
local WHEEL = 400                 -- wheel diameter
local TEX = "Interface\\AddOns\\WowPad\\Textures\\"

local R = CreateFrame("Frame", "WowPadRadial", UIParent)
R:SetWidth(420)
R:SetHeight(470)
R:SetPoint("CENTER", UIParent, "CENTER", 380, 30)
R:SetFrameStrata("DIALOG")
R:EnableMouse(true)
R:Hide()
WP.Radial = R
table.insert(WP.overlays, R)

-- Edit mode: the wheel shows with a mover box (drag to move, mouse wheel to resize; Snap.lua).
WP.MakeMover(R, "radial", "Main menu", { "CENTER", UIParent, "CENTER", 380, 30 })
local shownForEdit = false
function WP.RadialSetEditing(on)
  if on then
    if not R:IsShown() then R:Show(); shownForEdit = true end
    R.mover:Show()
  else
    R.mover:Hide()
    if shownForEdit then R:Hide(); shownForEdit = false end
  end
end
table.insert(WP.setupHooks, function() WP.ApplyMoverPos(R) end)

-- Wheel art: translucent wedges, bronze frame. One quarter frame and two wedge shapes, turned into
-- place in 90 degree steps with SetTexCoord.
local ROT = {
  [0] = { 0, 0, 0, 1, 1, 0, 1, 1 },
  [1] = { 0, 1, 1, 1, 0, 0, 1, 0 },   -- 90 degrees clockwise
  [2] = { 1, 1, 1, 0, 0, 1, 0, 0 },
  [3] = { 1, 0, 0, 0, 1, 1, 0, 1 },
}
local function Turn(tex, k)
  local t = ROT[math.mod(k, 4)]
  tex:SetTexCoord(t[1], t[2], t[3], t[4], t[5], t[6], t[7], t[8])
end

-- Returns the hub frame and a Highlight(index or nil) function (1 = top, clockwise).
local FILL, FILL_SEL, GLOW = { 0.17, 0.085, 0.05, 0.82 }, { 0.30, 0.17, 0.07, 0.90 }, { 1, 0.78, 0.25, 0.75 }
function WP.BuildWheelArt(parent, size)
  local hub = CreateFrame("Frame", nil, parent)
  hub:SetWidth(size)
  hub:SetHeight(size)
  hub:SetFrameLevel(parent:GetFrameLevel())   -- under the wedge buttons
  local fills, glows = {}, {}
  for i = 1, 8 do                       -- 1 = top, clockwise
    local k = math.floor((i - 1) / 2)
    local shape = (math.mod(i, 2) == 1) and "0" or "45"
    local f = hub:CreateTexture(nil, "BACKGROUND")
    f:SetTexture(TEX .. "radial_wedge" .. shape)
    f:SetAllPoints(hub)
    Turn(f, k)
    f:SetVertexColor(FILL[1], FILL[2], FILL[3], FILL[4])
    fills[i] = f
    local g = hub:CreateTexture(nil, "BORDER")
    g:SetTexture(TEX .. "radial_glow" .. shape)
    g:SetAllPoints(hub)
    g:SetBlendMode("ADD")
    Turn(g, k)
    g:SetVertexColor(GLOW[1], GLOW[2], GLOW[3], GLOW[4])
    g:Hide()
    glows[i] = g
  end
  local spots = { { "TOPRIGHT", 0 }, { "BOTTOMRIGHT", 1 }, { "BOTTOMLEFT", 2 }, { "TOPLEFT", 3 } }
  for n = 1, 4 do
    local t = hub:CreateTexture(nil, "ARTWORK")
    t:SetTexture(TEX .. "radial_frame")
    t:SetWidth(size / 2)
    t:SetHeight(size / 2)
    t:SetPoint(spots[n][1], hub, spots[n][1], 0, 0)
    Turn(t, spots[n][2])
  end
  local selected
  local function Highlight(idx)
    if idx == selected then return end
    if selected then
      fills[selected]:SetVertexColor(FILL[1], FILL[2], FILL[3], FILL[4])
      glows[selected]:Hide()
    end
    selected = idx
    if idx then
      fills[idx]:SetVertexColor(FILL_SEL[1], FILL_SEL[2], FILL_SEL[3], FILL_SEL[4])
      glows[idx]:Show()
    end
  end
  return hub, Highlight
end

local hub, Highlight = WP.BuildWheelArt(R, WHEEL)
hub:SetPoint("CENTER", R, "CENTER", 0, 10)

local title = R:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
title:SetPoint("TOP", R, "TOP", 0, 0)
title:SetText("Main Menu")
-- LB  o o  RB   (current page in gold)
local pageBar = CreateFrame("Frame", nil, R)
pageBar:SetWidth(10)
pageBar:SetHeight(14)
pageBar:SetPoint("TOP", title, "BOTTOM", 0, -6)
local dots = {}
local lbText = pageBar:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
local rbText = pageBar:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
WP.KeyText(lbText, "LB"); WP.KeyText(rbText, "RB")
local function LayoutDots(n)
  local gap = 14
  pageBar:SetWidth(n * gap)
  for i = 1, n do
    local d = dots[i]
    if not d then
      d = pageBar:CreateTexture(nil, "OVERLAY")
      d:SetTexture(TEX .. "dot")
      dots[i] = d
    end
    d:ClearAllPoints()
    d:SetPoint("CENTER", pageBar, "LEFT", (i - 0.5) * gap, 0)
  end
  lbText:SetPoint("RIGHT", pageBar, "LEFT", -6, 0)
  rbText:SetPoint("LEFT", pageBar, "RIGHT", 6, 0)
end
local hint = WP.NewKeyLine(R, "GameFontHighlightSmall", 18)
hint:SetPoint("BOTTOM", R, "BOTTOM", 0, 2)
hint:SetParts({ { key = "A", text = "open" }, { key = "B", text = "close" }, { key = "LB/RB", text = "page" } }, 10)

local wedges, page = {}, 1

for i = 1, 8 do
  local angle = math.rad(90 - (i - 1) * 45)
  local w = CreateFrame("Button", "WowPadRadialWedge" .. i, R)
  w:SetWidth(WEDGE)
  w:SetHeight(WEDGE)
  w:SetPoint("CENTER", R, "CENTER", math.cos(angle) * RADIUS, math.sin(angle) * RADIUS + 10)
  w:RegisterForClicks("LeftButtonUp")
  w.icon = w:CreateTexture(nil, "ARTWORK")
  w.icon:SetAllPoints(w)
  w.label = w:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  w.label:SetPoint("TOP", w, "BOTTOM", 0, -3)
  w.index = i
  w:SetScript("OnClick", function()
    local fn = this.fn
    R:Hide()
    if fn then fn() end
  end)
  wedges[i] = w
end

function R.Page(step)
  local n = table.getn(PAGES)
  page = math.mod(page - 1 + step + n, n) + 1
  local entries = PAGES[page]
  for i = 1, 8 do
    local w, e = wedges[i], entries[i]
    if e then
      w.icon:SetTexture(e[2])
      w.label:SetText(e[1])
      w.fn = e[3]
      w:Show()
    else
      w:Hide()
    end
  end
  LayoutDots(n)
  for i = 1, n do
    local d = dots[i]
    if i == page then d:SetVertexColor(1, 0.82, 0.2, 1); d:SetWidth(11); d:SetHeight(11)
    else d:SetVertexColor(0.55, 0.55, 0.55, 0.8); d:SetWidth(8); d:SetHeight(8) end
  end
  if WP.Nav then WP.Nav.Select(nil) end
end

function R.Toggle()
  if R:IsShown() then R:Hide() return end
  page = 1
  R.Page(0)
  R:Show()
  if WP.Nav then WP.Nav.SelectSoon(wedges[1]) end
end

-- Start: close the open windows (like Escape), then open the wheel; with the wheel open, close it.
function WP.StartPressed()
  local wasOpen = R:IsShown()
  for k = 1, table.getn(WP.overlays) do
    local o = WP.overlays[k]
    if o ~= R and o:IsShown() then o:Hide() end
  end
  if wasOpen then R:Hide() return end
  CloseMenus()
  CloseAllWindows()
  R.Toggle()
end

-- LB / RB page the wheel while it is open (Core's Bumper only targets outside the menu context).
function WP.RadialBumper(which)
  if not R:IsShown() then return false end
  R.Page(which == "LB" and -1 or 1)
  return true
end

-- Stick-direction selection: the right stick moves the pointer while the wheel is open, so the
-- direction the pointer moves is the direction the stick is held. Hold a direction to select
-- that wedge; it stays selected on release.
-- Selecting warps the pointer onto the wedge; that jump is not stick motion, so the history
-- restarts a moment after it.
local hist, histN, SAMPLE_WINDOW, MIN_TRAVEL, quietUntil = {}, 0, 0.06, 10, 0
R:SetScript("OnShow", function() histN = 0 end)
R:SetScript("OnHide", function() Highlight(nil) end)
R:SetScript("OnUpdate", function()
  local cur = WP.Nav and WP.Nav.cur
  Highlight(cur and cur.index and wedges[cur.index] == cur and cur.index or nil)
  local x, y = GetCursorPosition()
  local now = GetTime()
  if now < quietUntil then histN = 0 return end
  histN = histN + 1
  hist[histN] = { now, x, y }
  local first = 1
  while first < histN and now - hist[first][1] > SAMPLE_WINDOW do first = first + 1 end
  if first > 1 then
    for i = first, histN do hist[i - first + 1] = hist[i] end
    histN = histN - first + 1
  end
  local dx, dy = x - hist[1][2], y - hist[1][3]
  if dx * dx + dy * dy < MIN_TRAVEL * MIN_TRAVEL then return end
  local deg = math.deg(math.atan2(dy, dx))          -- 0 = right, 90 = up
  local idx = math.mod(math.floor(math.mod(90 - deg + 360 + 22.5, 360) / 45), 8) + 1
  local w = wedges[idx]
  if w and w:IsShown() and WP.Nav and WP.Nav.cur ~= w then
    WP.Nav.Select(w)
    quietUntil = now + 0.1
  end
end)
