-- FirstTime.lua - first-time setup / welcome window. Ported from WowPad 1.4.2 (3.3.5).
-- Opens once for new installs (setup check first) and once after each update (on the "What's
-- new" page). /wp firsttime, the main menu or Options reopens it any time.
-- Pages: setup check, basics, make it yours, good to know, what's new.
-- Works with the pad (D-pad + A, LB / RB = pages, B = close) and the mouse.

local WP = WowPad

-- Newest first. Shown on the last page.
local WHATS_NEW = {
  { "1.4.2-benilla", {
    "The controller bar has its own slots: your action bars stay as they are with WowPad off",
    "On-screen keyboard for chat and text fields ({Back} + {A}, or {A} on a text field)",
    "Controller Map ({Start} > page 2), party highlight in healer mode, this window",
    "Swap X / Y option for pads that report them backwards; centred cooldown sweeps",
  } },
}

local Y = "|cffffd100%s|r"
local function Gold(s) return string.format(Y, s) end
-- Check marks, as layout icons ({ok}, {warn}, {tip} in the page text).
local MARKS = {
  ok = "Interface\\RaidFrame\\ReadyCheck-Ready",
  warn = "Interface\\RaidFrame\\ReadyCheck-Waiting",
  tip = "Interface\\GossipFrame\\ActiveQuestIcon",
}

local F = CreateFrame("Frame", "WowPadFirstTime", UIParent)
F:SetWidth(660)
F:SetHeight(560)
F:SetPoint("CENTER", UIParent, "CENTER", 0, 40)
F:SetFrameStrata("DIALOG")
F:EnableMouse(true)
F:SetBackdrop({
  bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
  edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
  tile = true, tileSize = 32, edgeSize = 32,
  insets = { left = 11, right = 12, top = 12, bottom = 11 },
})
F:Hide()
table.insert(WP.overlays, F)
table.insert(UISpecialFrames, "WowPadFirstTime")
WP.FirstTime = F

local title = F:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
title:SetPoint("TOP", F, "TOP", 0, -22)
local pageNum = F:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
pageNum:SetPoint("TOPRIGHT", F, "TOPRIGHT", -40, -26)

-- Page text is laid out line by line, piece by piece (words, button icons, check marks), each
-- placed by its middle on the line, since 1.12 text has no inline icons. Long lines wrap at word
-- boundaries.
local BODY_W, LINE_H, BLANK_H, ICON = 600, 20, 10, 18
local bodyFrame = CreateFrame("Frame", nil, F)
bodyFrame:SetPoint("TOPLEFT", F, "TOPLEFT", 30, -56)
bodyFrame:SetWidth(BODY_W)
bodyFrame:SetHeight(1)
local meas = bodyFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
meas:Hide()
local pool = { tex = {}, fs = {} }
local used = { tex = 0, fs = 0 }

local function Width(s) meas:SetText(s); return meas:GetStringWidth() or 0 end
local function Visible(s)
  s = string.gsub(s, "|c%x%x%x%x%x%x%x%x", "")
  s = string.gsub(s, "|r", "")
  return s
end
-- Colour still open at the end of s (|cAARRGGBB ... |r), starting from c.
local function ColorAfter(c, s)
  for code in string.gfind(s, "|[cr]%x*") do
    if string.sub(code, 2, 2) == "r" then c = nil else c = string.sub(code, 1, 10) end
  end
  return c
end

local function Place(kind, x, y, value)
  used[kind] = used[kind] + 1
  local r = pool[kind][used[kind]]
  if not r then
    if kind == "tex" then
      r = bodyFrame:CreateTexture(nil, "OVERLAY")
      r:SetWidth(ICON)
      r:SetHeight(ICON)
    else
      r = bodyFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    end
    pool[kind][used[kind]] = r
  end
  if kind == "tex" then r:SetTexture(value) else r:SetText(value) end
  r:ClearAllPoints()
  r:SetPoint("LEFT", bodyFrame, "TOPLEFT", x, y)
  r:Show()
end

-- One source line -> pieces: { tex = path } or { text = "..." }. {A}, {LB} ... are buttons in the
-- chosen style, {ok} / {warn} / {tip} check marks.
local function Pieces(line)
  local out = {}
  local function text(t)
    if t == "" then return end
    local last = out[table.getn(out)]
    if last and last.text then last.text = last.text .. t else out[table.getn(out) + 1] = { text = t } end
  end
  local i = 1
  while true do
    local c, d, key = string.find(line, "{(%a%w*)}", i)
    if not c then text(string.sub(line, i)) break end
    text(string.sub(line, i, c - 1))
    if MARKS[key] then
      out[table.getn(out) + 1] = { tex = MARKS[key] }
    else
      local pcs = WP.KeyPieces(key)
      for k = 1, table.getn(pcs) do
        local pc = pcs[k]
        if pc.tex then out[table.getn(out) + 1] = pc else text("|cffffd100" .. pc.text .. "|r") end
      end
    end
    i = d + 1
  end
  return out
end

local function Layout(raw)
  used.tex, used.fs = 0, 0
  local y = 0
  for line in string.gfind(raw .. "\n", "(.-)\n") do
    if not string.find(line, "%S") then
      y = y + BLANK_H
    else
      local x, color, mid = 0, nil, -(y + LINE_H / 2)
      local _, _, lead = string.find(line, "^(%s*)")
      local indent = Width(lead or "") + 16   -- wrapped part: a bit further in
      local function NewRow() y = y + LINE_H; mid = -(y + LINE_H / 2); x = indent end
      local pcs = Pieces(line)
      for k = 1, table.getn(pcs) do
        local pc = pcs[k]
        if pc.tex then
          if x + ICON > BODY_W then NewRow() end
          Place("tex", x, mid, pc.tex)
          x = x + ICON + 1
        else
          local s = pc.text
          while s ~= "" do
            local w = Width(s)
            if not string.find(Visible(s), "%S") then
              x = x + w; color = ColorAfter(color, s); break
            end
            local part = s
            if x + w > BODY_W then
              -- longest run of whole words that fits
              part = ""
              for word in string.gfind(s, "%s*%S+") do
                if x + Width(part .. word) > BODY_W then break end
                part = part .. word
              end
              if part == "" and x <= indent then
                local _, _, first = string.find(s, "^(%s*%S+)")
                part = first or s
              end
            end
            if part ~= "" then
              Place("fs", x, mid, (color or "") .. part)
              x = x + Width(part)
              color = ColorAfter(color, part)
              s = string.sub(s, string.len(part) + 1)
            end
            if s ~= "" then NewRow(); s = string.gsub(s, "^%s+", "") end
          end
        end
      end
      y = y + LINE_H
    end
  end
  for i = used.tex + 1, table.getn(pool.tex) do pool.tex[i]:Hide() end
  for i = used.fs + 1, table.getn(pool.fs) do pool.fs[i]:Hide() end
  bodyFrame:SetHeight(math.max(y, 1))
end

local close = CreateFrame("Button", "WowPadFirstTimeCloseButton", F, "UIPanelCloseButton")
close:SetPoint("TOPRIGHT", F, "TOPRIGHT", -6, -6)

local function Button(name, label, w)
  local b = CreateFrame("Button", name, F, "UIPanelButtonTemplate")
  b:SetWidth(w or 110)
  b:SetHeight(24)
  b:SetText(label)
  return b
end
local prev = Button("WowPadFirstTimeBack", "Back")
prev:SetPoint("BOTTOMLEFT", F, "BOTTOMLEFT", 24, 20)
local nxt = Button("WowPadFirstTimeNext", "Next")
nxt:SetPoint("BOTTOMRIGHT", F, "BOTTOMRIGHT", -24, 20)
local foot = F:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
foot:SetPoint("BOTTOM", F, "BOTTOM", 0, 26)
WP.KeyText(foot, "{LB} / {RB}: pages    {B}: close    /wp firsttime reopens this", true)

-- Page-specific action buttons (above Back / Next).
local actCamera = Button("WowPadFirstTimeCamera", "Set camera following to Never", 230)
local actEdit = Button("WowPadFirstTimeEdit", "Edit bar layout", 150)
local actOptions = Button("WowPadFirstTimeOptions", "Open options", 150)
actCamera:SetPoint("BOTTOMLEFT", F, "BOTTOMLEFT", 30, 56)
local actPS = Button("WowPadFirstTimePS", "PlayStation buttons", 150)
local actXbox = Button("WowPadFirstTimeXbox", "Xbox buttons", 120)
actPS:SetPoint("BOTTOMRIGHT", F, "BOTTOMRIGHT", -30, 56)
actXbox:SetPoint("RIGHT", actPS, "LEFT", -10, 0)
actEdit:SetPoint("BOTTOMLEFT", F, "BOTTOMLEFT", 30, 56)
actOptions:SetPoint("LEFT", actEdit, "RIGHT", 10, 0)

---------------------------------------------------------------------------
-- Setup checks (live)
---------------------------------------------------------------------------
local padSeen = false

local function SetupText()
  local lines = {}
  local function Add(s) lines[table.getn(lines) + 1] = s end

  if padSeen or WP.mode == "controller" or WP.padStyle then
    Add("{ok} " .. Gold("Controller detected."))
  else
    Add("{warn} " .. Gold("Press any button on your controller.") .. " If nothing changes, check that you")
    Add("     started benilla-wowpad (not plain benilla) and, for a Steam Controller, Steam Input.")
  end

  if WP.ButtonStyle() == "ps" then
    Add("{ok} " .. Gold("Button labels: PlayStation") .. " ({A} {B} {X} {Y}, {LB} / {RB}, {LT} / {RT}).")
  else
    Add("{ok} " .. Gold("Button labels: Xbox") .. " ({A} {B} {X} {Y}, {LB} / {RB}). Using a DualShock / DualSense?")
  end
  Add("     Pick the button style below (also in Options > Buttons).")

  Add("{ok} " .. Gold("X / Y the wrong way round?") .. " Options > Buttons > Swap X / Y buttons.")

  if GetCVar("cameraSmoothStyle") == "0" then
    Add("{ok} " .. Gold("Camera following: Never.") .. " The right stick is in charge of the camera.")
  else
    Add("{warn} " .. Gold("Recommended: camera following set to Never,") .. " so the camera doesn't swing")
    Add("     behind you while you steer it with the right stick (button below).")
  end
  return table.concat(lines, "\n")
end

---------------------------------------------------------------------------
-- Pages
---------------------------------------------------------------------------
local function WhatsNewText()
  local lines = {}
  for i = 1, table.getn(WHATS_NEW) do
    local v = WHATS_NEW[i]
    lines[table.getn(lines) + 1] = Gold("Version " .. v[1])
    for k = 1, table.getn(v[2]) do lines[table.getn(lines) + 1] = "  -  " .. v[2][k] end
    lines[table.getn(lines) + 1] = " "
  end
  return table.concat(lines, "\n")
end

local function BasicsText()
  local ally = (WowPadDB and WowPadDB.swapBumpers) and "{RB}" or "{LB}"
  return table.concat({
    Gold("Left stick") .. " moves,  " .. Gold("right stick") .. " turns the camera (a dot marks the crosshair).",
    "{A} jump,  {B} clear target / back,  {X} interact + attack,  {Y} target menu.",
    Gold("D-pad") .. ": 4 action slots.  Hold {LT}, {RT} or " .. Gold("both") .. " for 8 more slots each.",
    "{LB} / {RB}: target nearest friend / enemy.  Hold both: right stick zooms.",
    Gold("Healer mode") .. " (Options > Buttons): tap your ally bumper (" .. ally .. ") for your last party pick;",
    "hold it + flick the right stick down / up for the next / previous member. Works in combat.",
    "{Start}: close windows, radial main menu.  {Back}: map (hold: bags).",
    Gold("R3") .. ": pointer mode.  " .. Gold("L3") .. ": autorun.",
    " ",
    "With a window open (out of combat) the D-pad moves a gold selection: {A} click,",
    "{X} right-click, {Y} preview / compare, {B} close, {LB} / {RB} windows.",
    " ",
    "Touching the mouse or keyboard switches to normal control at once; the pad switches back.",
    "Full button list: {Start} > page 2 > " .. Gold("Controller") .. ".",
  }, "\n")
end

local function YoursText()
  return table.concat({
    Gold("Edit bar layout") .. " (left-click the minimap button): drag spells, items and macros",
    "onto the round slots, drag bars to move them, mouse wheel to resize. The controller bar's",
    "slots are WowPad's own, so your normal action bars are not touched.",
    " ",
    Gold("Options") .. " (right-click the minimap button, or /wp options):",
    "  -  Camera, pointer and zoom speed, invert camera, smooth camera",
    "  -  Walk on slight stick tilt, run on full tilt",
    "  -  Healer mode (off by default): pick party members with the bumper + right stick",
    "  -  Swap {LB} / {RB} targeting,  {X} also starts attacking,  Xbox or PlayStation buttons",
    "  -  Swap X / Y buttons, on-screen keyboard, crosshair dot and crosshair tooltips",
    " ",
    Gold("Bars") .. ":",
    "  -  Lite mode: one action set on screen, triggers swap it in",
    "  -  Utility ring: pick a button for it, fill its 8 wedges in Edit bar layout",
    "  -  Hide Blizzard's action bars (WowPad's XP, reputation and pet bars take over), bar size",
    "  -  Minimap button",
  }, "\n")
end

local function GoodText()
  return table.concat({
    Gold("Chat:") .. " {Back} + {A} opens the on-screen keyboard: {A} type, {X} capital, {Y} space,",
    "{B} delete, {LB} / {RB} channel, {Start} send, {Back} + {B} close. A real keyboard works too.",
    Gold("Text fields") .. " (auction house, mail): {A} on one opens the keyboard under it.",
    " ",
    Gold("Bags:") .. " L3 on an item: Disenchant / Destroy / Cancel.  {Y}: preview, hold to compare.",
    Gold("Ground spells") .. " (Blizzard, Flare...): {A} or the same button places them, {B} cancels.",
    " ",
    Gold("Crosshair stuck somewhere odd?") .. " Press R3 twice.",
    Gold("Something stuck?") .. " Hold {Back} + {Start} for 1 second (kill switch), or touch mouse / keyboard.",
    " ",
    Gold("Commands") .. " (type in chat):",
  }, "\n")
end

local PAGES = {
  { title = "WowPad: setup check", text = SetupText, live = true, buttons = { actCamera, actXbox, actPS } },
  { title = "The basics", text = BasicsText },
  { title = "Make it yours", text = YoursText, buttons = { actEdit, actOptions } },
  { title = "Good to know", text = GoodText, commands = true },
  { title = "What's new", text = WhatsNewText },
}

-- Commands as two aligned columns (command | what it does), under page 4's text.
local COMMANDS = {
  { "/wp options",   "settings" },
  { "/wp edit",      "edit bar layout" },
  { "/wp blizz",     "show / hide Blizzard's action bars" },
  { "/wp bar",       "controller bar always, or only in controller mode" },
  { "/wp map",       "the Controller Map" },
  { "/wp status",    "mode, set and context near the top of the screen" },
  { "/wp firsttime", "this window" },
}
local cmdCol = F:CreateFontString(nil, "OVERLAY", "GameFontNormal")
cmdCol:SetPoint("TOPLEFT", bodyFrame, "BOTTOMLEFT", 16, -2)
cmdCol:SetJustifyH("LEFT")
local descCol = F:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
descCol:SetPoint("TOPLEFT", cmdCol, "TOPLEFT", 150, 0)
descCol:SetJustifyH("LEFT")
do
  local a, b = {}, {}
  for i = 1, table.getn(COMMANDS) do a[i], b[i] = COMMANDS[i][1], COMMANDS[i][2] end
  cmdCol:SetText(table.concat(a, "\n"))
  descCol:SetText(table.concat(b, "\n"))
end

local page = 1
local ALL_ACTIONS = { actCamera, actEdit, actOptions, actXbox, actPS }

local function Render()
  local p = PAGES[page]
  local n = table.getn(PAGES)
  title:SetText(p.title)
  pageNum:SetText(page .. " / " .. n)
  Layout(p.text())
  if p.commands then cmdCol:Show(); descCol:Show() else cmdCol:Hide(); descCol:Hide() end
  for i = 1, table.getn(ALL_ACTIONS) do ALL_ACTIONS[i]:Hide() end
  local bs = p.buttons or {}
  for i = 1, table.getn(bs) do bs[i]:Show() end
  if page == 1 and GetCVar("cameraSmoothStyle") == "0" then actCamera:Hide() end
  if page > 1 then prev:Show() else prev:Hide() end
  nxt:SetText(page < n and "Next" or "Done")
end

function F.Page(step)
  page = math.max(1, math.min(table.getn(PAGES), page + step))
  Render()
end

prev:SetScript("OnClick", function() F.Page(-1) end)
nxt:SetScript("OnClick", function() if page < table.getn(PAGES) then F.Page(1) else F:Hide() end end)
actCamera:SetScript("OnClick", function()
  SetCVar("cameraSmoothStyle", "0")
  WP.Print("Camera following set to Never (Interface Options to change it back).")
  Render()
end)
actXbox:SetScript("OnClick", function() WP.SetButtonStyle("xbox"); Render() end)
actPS:SetScript("OnClick", function() WP.SetButtonStyle("ps"); Render() end)
actEdit:SetScript("OnClick", function() F:Hide(); if WP.ToggleEdit then WP.ToggleEdit() end end)
actOptions:SetScript("OnClick", function() F:Hide(); if WP.OpenOptions then WP.OpenOptions() end end)

-- Live refresh of the setup checks.
local acc = 0
F:SetScript("OnUpdate", function()
  if WP.mode == "controller" then padSeen = true end
  acc = acc + arg1
  if acc < 0.5 then return end
  acc = 0
  if PAGES[page].live then Render() end
end)

local function Version()
  return GetAddOnMetadata and GetAddOnMetadata("WowPad", "Version") or "?"
end
F:SetScript("OnHide", function()
  if WowPadDB then WowPadDB.firstTimeSeen = Version() end
end)

function WP.ShowFirstTime(startPage)
  if WP.InCombat() then WP.Print("After combat.") return end
  page = startPage or 1
  Render()
  F:Show()
end

---------------------------------------------------------------------------
-- Auto-open: new install -> setup check; update -> what's new. Once per version.
---------------------------------------------------------------------------
local existingUser
local ev = CreateFrame("Frame")
ev:RegisterEvent("VARIABLES_LOADED")
ev:RegisterEvent("PLAYER_ENTERING_WORLD")
ev:RegisterEvent("PLAYER_REGEN_ENABLED")
local pending, delay = false, 0
ev:SetScript("OnEvent", function()
  if event == "VARIABLES_LOADED" then
    -- Existing saved settings (bar layout or an earlier visit) = someone updating.
    existingUser = WowPadDB ~= nil and (WowPadDB.bar ~= nil or WowPadDB.firstTimeSeen ~= nil)
  elseif event == "PLAYER_ENTERING_WORLD" or event == "PLAYER_REGEN_ENABLED" then
    if WowPadDB and WowPadDB.firstTimeSeen ~= Version() and not F:IsShown() then
      pending, delay = true, 0
    end
  end
end)
ev:SetScript("OnUpdate", function()
  if not pending then return end
  delay = delay + arg1
  if delay < 3 or WP.InCombat() then return end   -- let the UI settle first
  pending = false
  WP.ShowFirstTime(existingUser and table.getn(PAGES) or 1)
end)
