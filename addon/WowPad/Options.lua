-- Options.lua - WowPad's options window: /wp options, the minimap button (right-click), the
-- WowPad button under the game menu, or the wheel's "WowPad Options".
--
-- 1.12 has no Interface > AddOns panel (that is 3.0), so this is a window of its own. Every
-- setting applies at once: benilla-wowpad reads the stick settings each frame (WowPad_Frame).
-- Numbers are steppers (< and > buttons) rather than sliders, so the D-pad and A can work them.

local WP = WowPad

local W, H = 560, 500
local F = CreateFrame("Frame", "WowPadOptionsFrame", UIParent)
F:SetWidth(W)
F:SetHeight(H)
F:SetPoint("CENTER", UIParent, "CENTER", 0, 40)
F:SetFrameStrata("DIALOG")
F:SetToplevel(true)
F:EnableMouse(true)
F:SetMovable(true)
F:RegisterForDrag("LeftButton")
F:SetScript("OnDragStart", function() this:StartMoving() end)
F:SetScript("OnDragStop", function() this:StopMovingOrSizing() end)
F:SetBackdrop({
  bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
  edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
  tile = true, tileSize = 32, edgeSize = 32,
  insets = { left = 11, right = 12, top = 12, bottom = 11 },
})
F:Hide()
table.insert(UISpecialFrames, "WowPadOptionsFrame")   -- Escape closes it

local title = F:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
title:SetPoint("TOP", F, "TOP", 0, -18)
title:SetText("WowPad")
local sub = F:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
sub:SetPoint("TOP", title, "BOTTOM", 0, -4)
sub:SetText("Changes apply at once. Stick speeds: 100% = wowpad.ini.")

local close = CreateFrame("Button", "WowPadOptionsClose", F, "UIPanelCloseButton")
close:SetPoint("TOPRIGHT", F, "TOPRIGHT", -6, -6)

local controls = {}
local L, R = 24, 292           -- column left edges
local COL = 244                -- column width

local function DB() WowPadDB = WowPadDB or {} return WowPadDB end

local function Header(text, x, y)
  local h = F:CreateFontString(nil, "ARTWORK", "GameFontNormal")
  h:SetPoint("TOPLEFT", F, "TOPLEFT", x, y)
  h:SetText(text)
end

local function Check(name, label, tip, x, y, get, set)
  local c = CreateFrame("CheckButton", name, F, "OptionsCheckButtonTemplate")
  c:SetWidth(26)
  c:SetHeight(26)
  c:SetPoint("TOPLEFT", F, "TOPLEFT", x - 4, y)
  getglobal(name .. "Text"):SetText(label)
  c.tooltipText = tip
  c:SetScript("OnClick", function()
    set(this:GetChecked() and true or false)
  end)
  c.Load = function() c:SetChecked(get() and 1 or nil) end
  table.insert(controls, c)
  return c
end

-- A number with < and > buttons: o = { min, max, step, fmt(v), get(), set(v) }.
local function Stepper(name, label, x, y, o)
  local f = CreateFrame("Frame", name, F)
  f:SetWidth(COL)
  f:SetHeight(22)
  f:SetPoint("TOPLEFT", F, "TOPLEFT", x, y)
  local text = f:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
  text:SetPoint("LEFT", f, "LEFT", 0, 0)
  local function Show(v) text:SetText(label .. ":  |cffffd100" .. o.fmt(v) .. "|r") end
  local function Step(dir)
    local v = o.get() + dir * o.step
    v = math.floor(v / o.step + 0.5) * o.step
    v = math.max(o.min, math.min(o.max, v))
    o.set(v)
    Show(v)
  end
  local up = CreateFrame("Button", name .. "Up", f, "UIPanelButtonTemplate")
  up:SetWidth(24)
  up:SetHeight(20)
  up:SetPoint("RIGHT", f, "RIGHT", -6, 0)
  up:SetText(">")
  up:SetScript("OnClick", function() Step(1) end)
  local down = CreateFrame("Button", name .. "Down", f, "UIPanelButtonTemplate")
  down:SetWidth(24)
  down:SetHeight(20)
  down:SetPoint("RIGHT", up, "LEFT", -2, 0)
  down:SetText("<")
  down:SetScript("OnClick", function() Step(-1) end)
  f.Load = function() Show(o.get()) end
  table.insert(controls, f)
  return f
end

-- A choice from a list with < and > buttons: values = { v1, v2, ... }, name(v) its label.
local function Cycler(name, label, x, y, values, nameOf, get, set)
  local f = CreateFrame("Frame", name, F)
  f:SetWidth(COL)
  f:SetHeight(22)
  f:SetPoint("TOPLEFT", F, "TOPLEFT", x, y)
  local text = f:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
  text:SetPoint("LEFT", f, "LEFT", 0, 0)
  local function Show() text:SetText(label .. ":  |cffffd100" .. nameOf(get()) .. "|r") end
  local function Step(dir)
    local n, at = table.getn(values), 1
    for k = 1, n do if values[k] == get() then at = k end end
    set(values[math.mod(at - 1 + dir + n, n) + 1])
    Show()
  end
  local up = CreateFrame("Button", name .. "Up", f, "UIPanelButtonTemplate")
  up:SetWidth(24)
  up:SetHeight(20)
  up:SetPoint("RIGHT", f, "RIGHT", -6, 0)
  up:SetText(">")
  up:SetScript("OnClick", function() Step(1) end)
  local down = CreateFrame("Button", name .. "Down", f, "UIPanelButtonTemplate")
  down:SetWidth(24)
  down:SetHeight(20)
  down:SetPoint("RIGHT", up, "LEFT", -2, 0)
  down:SetText("<")
  down:SetScript("OnClick", function() Step(-1) end)
  f.Load = Show
  table.insert(controls, f)
  return f
end

local function Pct(v) return math.floor(v * 100 + 0.5) .. "%" end
local function Ms(v) return math.floor(v + 0.5) .. " ms" end
local function X(v) return string.format("%.2fx", v) end
local function Num(k, default) return function() return tonumber(DB()[k]) or default end end
local function Put(k) return function(v) DB()[k] = v end end

---------------------------------------------------------------------------
-- Left column: sticks and crosshair
---------------------------------------------------------------------------
Header("Sticks", L, -56)
Stepper("WowPadOptCam", "Camera speed", L, -74,
  { min = 0.05, max = 3, step = 0.05, fmt = Pct, get = Num("wpCamSens", 1), set = Put("wpCamSens") })
Stepper("WowPadOptPtr", "Pointer speed", L, -98,
  { min = 0.05, max = 3, step = 0.05, fmt = Pct, get = Num("wpPtrSens", 1), set = Put("wpPtrSens") })
Stepper("WowPadOptZoom", "Zoom speed", L, -122,
  { min = 0.25, max = 3, step = 0.25, fmt = Pct, get = Num("wpZoomSens", 1), set = Put("wpZoomSens") })
Stepper("WowPadOptPeekDelay", "Peek delay", L, -146,
  { min = 100, max = 1000, step = 50, fmt = Ms, get = Num("wpPeekDelay", 250), set = Put("wpPeekDelay") })
Check("WowPadOptInv", "Invert camera up/down", nil, L, -172,
  function() return DB().wpInvertY == true end, Put("wpInvertY"))
Check("WowPadOptSmooth", "Smooth camera",
  "Smooths right-stick camera turning, so it glides instead of stepping. Adds a little delay.",
  L, -196, function() return DB().wpCamSmooth == true end, Put("wpCamSmooth"))
Check("WowPadOptWalk", "Walk/run by stick tilt",
  "Slight tilt walks, full tilt runs, using the game's Run/Walk toggle.",
  L, -220, function() return DB().wpWalkRun == true end, Put("wpWalkRun"))

Header("Crosshair", L, -256)
Check("WowPadOptCross", "Show the crosshair dot", "A dot at the crosshair while the right stick drives the camera.",
  L, -274, function() return DB().crosshair ~= false end, Put("crosshair"))
Check("WowPadOptPeek", "Crosshair tooltips (peek)",
  "When the right stick rests, camera look pauses for a moment so the unit under the crosshair shows its tooltip.",
  L, -298, function() return DB().peek ~= false end, Put("peek"))

Header("Messages", L, -334)
Check("WowPadOptStatus", "Show the status line", "Mode, set and context near the top of the screen.",
  L, -352, function() return DB().showStatus == true end,
  function(v) DB().showStatus = v; WP.UpdateStatus() end)
Check("WowPadOptDebug", "Debug messages in chat", nil,
  L, -376, function() return DB().debug == true end, Put("debug"))

---------------------------------------------------------------------------
-- Right column: buttons and bars
---------------------------------------------------------------------------
Header("Buttons", R, -56)
Check("WowPadOptXAttack", "X also starts auto attack",
  "X interacts with your target and starts attacking it when it is hostile.",
  R, -74, function() return DB().xAttack ~= false end, Put("xAttack"))
Check("WowPadOptSwap", "Swap LB / RB targeting", "LB targets enemies and RB targets friends.",
  R, -98, function() return DB().swapBumpers == true end, Put("swapBumpers"))
Check("WowPadOptHealer", "Healer mode",
  "The friendly bumper targets the party member you last picked; hold it and flick the right stick down / up "
  .. "for the next / previous member.",
  R, -122, function() return DB().wpBumperFlick == true end, Put("wpBumperFlick"))
Check("WowPadOptPS", "PlayStation button labels", "Cross / Circle / Square / Triangle instead of A / B / X / Y.",
  R, -146, function() return WP.ButtonStyle() == "ps" end,
  function(v) WP.SetButtonStyle(v and "ps" or "xbox") end)
-- Some pads still arrive with X and Y in each other's place after the automatic layout check (a
-- phone used as a controller, pads Linux has no mapping for): this flips them back.
Check("WowPadOptSwapXY", "Swap X / Y buttons",
  "Tick this if X does what Y should and Y does what X should. Some controllers (phone controller "
  .. "apps, pads with no Linux mapping) report the two in each other's place, and WowPad cannot always "
  .. "tell. The setting is saved, so the pad stays fixed next time.",
  R, -170, function() return DB().wpSwapXY == true end, Put("wpSwapXY"))
Check("WowPadOptKeyboard", "On-screen keyboard",
  "Back + A or A on a text field opens a keyboard you type on with the pad. Off: the normal chat box.",
  R, -194, function() return DB().keyboard ~= false end, Put("keyboard"))

-- The utility ring's button: none, a D-pad button of the default set, or any button of LT, RT, LT+RT.
local RING = { 0, 1, 2, 3, 4 }
for set = 1, 3 do for i = 1, 8 do table.insert(RING, set * 10 + i) end end
local SETS = { [0] = "Default", "LT", "RT", "LT+RT" }
local function RingName(v)
  if not v or v <= 0 then return "None" end
  return SETS[math.floor(v / 10)] .. " " .. WP.SLOT_LABELS[math.mod(v, 10)]
end
Cycler("WowPadOptRing", "Utility ring", R, -220, RING, RingName,
  function() return tonumber(DB().wpRingSlot) or 0 end,
  function(v)
    DB().wpRingSlot = v
    if WP.Bar then WP.Bar.UpdateAll() end
  end)

Header("Bars", R, -256)
Check("WowPadOptAlways", "Controller bar always visible", "Off: the bar shows only in controller mode.",
  R, -274, function() return DB().barAlways ~= false end,
  function(v) if (DB().barAlways ~= false) ~= v and WP.Bar then WP.Bar.ToggleAlways() end end)
Check("WowPadOptLite", "Lite bar (one set at a time)",
  "One cluster: your default set, and holding LT, RT or both shows that set in its place.",
  R, -298, function() return DB().barLite == true end,
  function(v) if WP.Bar then WP.Bar.SetLite(v) end end)
Check("WowPadOptLiteCD", "Lite: show hidden cooldowns",
  "With the lite bar, a row of the cooldowns on the sets you cannot see; each goes when it is ready. Move it in the bar layout editor.",
  R, -322, function() return DB().liteCooldowns ~= false end,
  function(v) DB().liteCooldowns = v; if WP.LiteCD then WP.LiteCD.Update() end end)
Check("WowPadOptBlizz", "Hide Blizzard action bars",
  "Hides the stock bars and art; WowPad's XP, reputation and pet bars take their place.",
  R, -346, function() return DB().hideBlizz == true end,
  function(v) if (DB().hideBlizz == true) ~= v then WP.ToggleBlizzBars() end end)
Check("WowPadOptMinimap", "Minimap button", "Left-click: edit the bar layout. Right-click: these options.",
  R, -370, function() return not (DB().minimap and DB().minimap.hide) end,
  function(v)
    DB().minimap = DB().minimap or {}
    DB().minimap.hide = not v
    if WP.UpdateMinimapButton then WP.UpdateMinimapButton() end
  end)
Stepper("WowPadOptScale", "Bar size", R, -398,
  { min = 0.4, max = 1.6, step = 0.05, fmt = X,
    get = function() return (WP.Bar and WP.Bar.Pos().scale) or 1 end,
    set = function(v) if WP.Bar then WP.Bar.SetScale(v) end end })

local edit = CreateFrame("Button", "WowPadOptEdit", F, "UIPanelButtonTemplate")
edit:SetWidth(150)
edit:SetHeight(22)
edit:SetPoint("TOPLEFT", F, "TOPLEFT", R, -428)
edit:SetText("Edit bar layout")
edit:SetScript("OnClick", function()
  F:Hide()
  if WP.ToggleEdit then WP.ToggleEdit() end
end)

local done = CreateFrame("Button", "WowPadOptDone", F, "UIPanelButtonTemplate")
done:SetWidth(100)
done:SetHeight(22)
done:SetPoint("BOTTOMRIGHT", F, "BOTTOMRIGHT", -20, 18)
done:SetText("Done")
done:SetScript("OnClick", function() F:Hide() end)

F:SetScript("OnShow", function()
  for k = 1, table.getn(controls) do controls[k].Load() end
end)

function WP.OpenOptions()
  if F:IsShown() then F:Hide() return end
  F:Show()
  if WP.Nav then WP.Nav.SelectSoon(done) end
end

---------------------------------------------------------------------------
-- The WowPad button, under the game menu (Escape).
---------------------------------------------------------------------------
if GameMenuFrame then
  local g = CreateFrame("Button", "WowPadGameMenuButton", GameMenuFrame, "GameMenuButtonTemplate")
  g:SetPoint("TOP", GameMenuFrame, "BOTTOM", 0, -4)
  g:SetText("WowPad")
  g:SetScript("OnClick", function()
    HideUIPanel(GameMenuFrame)
    WP.OpenOptions()
  end)
end
