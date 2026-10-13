-- LiteCooldowns.lua - with the lite bar, a small row of the cooldowns you cannot see: an action on
-- a set the bar is not showing (or on the utility ring) appears here while it cools down and goes
-- once it is ready. The global cooldown is left out. WowPadDB.liteCooldowns == false turns it off
-- (Options > Bars); it moves with the bar layout editor.

local WP = WowPad
local M = {}
WP.LiteCD = M

local ICON, GAP, MAX = 30, 4, 8
local MIN_DURATION = 1.6           -- longer than the global cooldown

-- The pad slots of each set that hold actions (set 0's 5-8 are the fixed buttons).
local SETS = { { 0, 4 }, { 1, 8 }, { 2, 8 }, { 3, 8 }, { 9, 8 } }

local frame, icons = nil, {}

local function Enabled() return WowPadDB and WowPadDB.liteCooldowns ~= false end

local function MakeIcon(k)
  local b = CreateFrame("Frame", "WowPadLiteCD" .. k, frame)
  b:SetWidth(ICON)
  b:SetHeight(ICON)
  b.icon = b:CreateTexture(nil, "ARTWORK")
  b.icon:SetAllPoints(b)
  b.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
  local ok, cd = pcall(CreateFrame, "Model", "WowPadLiteCD" .. k .. "Cooldown", b, "CooldownFrameTemplate")
  if ok and cd then
    WP.FitCooldown(cd, b, ICON)
    b.cooldown = cd
  end
  b.time = b:CreateFontString(nil, "OVERLAY", "NumberFontNormal")
  b.time:SetPoint("BOTTOM", b, "BOTTOM", 0, 1)
  b:Hide()
  return b
end

local function TimeText(left)
  if left >= 60 then return math.ceil(left / 60) .. "m" end
  return tostring(math.ceil(left))
end

-- Whether a set's buttons are out of sight right now.
local function Hidden(set, view)
  if set == 9 then
    return not (WP.Ring and WP.Ring.frame and WP.Ring.frame:IsVisible())
  end
  return set ~= view
end

-- The actions cooling down on hidden sets, one per icon, soonest ready first.
local function Collect(view)
  local list, seen = {}, {}
  local now = GetTime()
  for k = 1, table.getn(SETS) do
    local set, n = SETS[k][1], SETS[k][2]
    if Hidden(set, view) then
      for i = 1, n do
        local a = WP.Bar.ActionSlot(set, i)
        if a and HasAction(a) then
          local start, duration, enable = GetActionCooldown(a)
          local tex = GetActionTexture(a)
          if tex and enable == 1 and start and start > 0 and duration and duration > MIN_DURATION
              and not seen[tex] then
            seen[tex] = true
            table.insert(list, { tex = tex, start = start, duration = duration,
                                 left = start + duration - now })
          end
        end
      end
    end
  end
  table.sort(list, function(x, y) return x.left < y.left end)
  return list
end

local function Layout(n)
  frame:SetWidth(math.max(n, 1) * (ICON + GAP) - GAP)
  for k = 1, MAX do
    local b = icons[k]
    b:ClearAllPoints()
    b:SetPoint("LEFT", frame, "LEFT", (k - 1) * (ICON + GAP), 0)
  end
end

function M.Update()
  if not frame then return end
  local view = WP.Bar and WP.Bar.LiteView and WP.Bar.LiteView()
  local list = (Enabled() and view) and Collect(view) or {}
  if M.editing then
    -- Placeholders, so the row can be placed while nothing is cooling down.
    for k = 1, 3 do
      local b = icons[k]
      b.icon:SetTexture("Interface\\Icons\\INV_Misc_QuestionMark")
      b.time:SetText("")
      if b.cooldown then b.cooldown:Hide() end
      b:Show()
    end
    for k = 4, MAX do icons[k]:Hide() end
    Layout(3)
    frame:Show()
    return
  end
  local n = math.min(table.getn(list), MAX)
  for k = 1, MAX do
    local b, e = icons[k], list[k]
    if k <= n then
      b.icon:SetTexture(e.tex)
      b.time:SetText(TimeText(e.left))
      -- The sweep restarts only when the cooldown itself changed, so it does not flicker.
      if b.cooldown and (b.start ~= e.start or b.duration ~= e.duration) then
        CooldownFrame_SetTimer(b.cooldown, e.start, e.duration, 1)
      end
      b.start, b.duration = e.start, e.duration
      b:Show()
    else
      b.start, b.duration = nil, nil
      b:Hide()
    end
  end
  Layout(n)
  if n > 0 then frame:Show() else frame:Hide() end
end

function M.SetEditing(on)
  if not frame then return end
  M.editing = on and Enabled() and WowPadDB.barLite and true or false
  if frame.mover then
    if M.editing then frame.mover:Show() else frame.mover:Hide() end
  end
  M.Update()
end

table.insert(WP.setupHooks, function()
  frame = CreateFrame("Frame", "WowPadLiteCooldowns", UIParent)
  frame:SetHeight(ICON)
  frame:SetWidth(ICON)
  frame:SetFrameStrata("MEDIUM")
  for k = 1, MAX do icons[k] = MakeIcon(k) end
  Layout(1)
  -- Home: just right of the bar, clear of the edit-mode tabs above it.
  local home = getglobal("WowPadBar")
  WP.MakeMover(frame, "liteCooldowns", "Cooldowns",
    home and { "LEFT", home, "RIGHT", 8, 0 } or { "BOTTOM", UIParent, "BOTTOM", 160, 140 })
  WP.ApplyMoverPos(frame)
  frame:Hide()
  M.Update()
end)

local ev = CreateFrame("Frame")
ev:RegisterEvent("ACTIONBAR_UPDATE_COOLDOWN")
ev:RegisterEvent("ACTIONBAR_SLOT_CHANGED")
ev:RegisterEvent("SPELL_UPDATE_COOLDOWN")
ev:RegisterEvent("BAG_UPDATE_COOLDOWN")
ev:SetScript("OnEvent", function() M.Update() end)

-- The timers count down, and an icon goes the moment its cooldown ends.
local acc = 0
ev:SetScript("OnUpdate", function()
  acc = acc + arg1
  if acc < 0.25 then return end
  acc = 0
  if frame and (frame:IsShown() or Enabled()) then M.Update() end
end)
