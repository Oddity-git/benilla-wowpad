-- ExtraBars.lua - WowPad's own XP/reputation bar and pet bar, shown while Blizzard's bottom bars
-- are hidden (/wp blizz), since those carry the stock XP, reputation and pet bars.
-- Each moves and scales in edit mode (/wp edit: drag the labelled box, mouse wheel to resize).
-- Positions and scales are account-wide (WowPadDB.extra).

local WP = WowPad
local Extra = {}
WP.Extra = Extra
local movers = {}
local editing = false

---------------------------------------------------------------------------
-- Movable, scalable holders with an edit-mode box
---------------------------------------------------------------------------
local function DB(key)
  WowPadDB.extra = WowPadDB.extra or {}
  WowPadDB.extra[key] = WowPadDB.extra[key] or {}
  return WowPadDB.extra[key]
end

local function ApplyPos(holder)
  local p = DB(holder.key)
  holder:SetScale(p.scale or 1)
  if not WP.PlaceAt(holder, p) then
    local d = holder.defaultPoint
    holder:ClearAllPoints()
    holder:SetPoint(d[1], d[2], d[3], d[4], d[5])
  end
end

local function MakeMover(holder, label)
  local m = CreateFrame("Frame", nil, holder)
  m.holder = holder
  m:SetAllPoints(holder)
  m:SetFrameLevel(holder:GetFrameLevel() + 20)
  local bg = m:CreateTexture(nil, "OVERLAY")
  bg:SetTexture(0.2, 0.5, 1, 0.45)
  bg:SetAllPoints(m)
  local t = m:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  t:SetPoint("CENTER", m, "CENTER", 0, 0)
  t:SetText(label .. "  (drag / wheel)")
  m:EnableMouse(true)
  m:RegisterForDrag("LeftButton")
  m:SetScript("OnDragStart", function() WP.SnapDragStart(holder) end)
  m:SetScript("OnDragStop", function()
    WP.SnapDragStop()
    WP.SavePlace(holder, DB(holder.key))
  end)
  m:EnableMouseWheel(true)
  m:SetScript("OnMouseWheel", function()
    local p = DB(holder.key)
    local old = holder:GetScale()
    local new = math.max(0.4, math.min(2.0, (p.scale or 1) + arg1 * 0.05))
    if not p.dx then WP.SavePlace(holder, p) end
    WP.RescalePlace(p, old, new)
    p.scale = new
    ApplyPos(holder)
  end)
  m:Hide()
  table.insert(movers, m)
  holder.mover = m
end

local function MakeHolder(name, key, w, h, defaultPoint)
  local f = CreateFrame("Frame", name, UIParent)
  f:SetWidth(w)
  f:SetHeight(h)
  f:SetMovable(true)
  f:SetClampedToScreen(true)
  f.key, f.defaultPoint = key, defaultPoint
  f:Hide()
  return f
end

-- Our bars stand in for Blizzard's while those are hidden.
local function Wanted() return WowPadDB and WowPadDB.hideBlizz and true or false end

---------------------------------------------------------------------------
-- XP + reputation bar
---------------------------------------------------------------------------
local XP_W, XP_H, REP_H = 520, 12, 9
local xpHolder, repHolder, xpBar, restBar, xpText, repBar, repText

-- Rounded bar: half-disc caps (Textures/barcap, mirrored on the right) and a flat middle, a thin
-- bronze outline, and a fill whose left cap shows once there is progress and right cap when full.
local CAP = "Interface\\AddOns\\WowPad\\Textures\\barcap"
local RING = "Interface\\AddOns\\WowPad\\Textures\\barcapring"
local FLAT = "Interface\\Buttons\\WHITE8X8"
local EDGE = { 0.72, 0.56, 0.33, 1 }

local function Cap(frame, layer, tex, side, cw, h, color)
  local t = frame:CreateTexture(nil, layer)
  t:SetTexture(tex)
  t:SetWidth(cw)
  t:SetHeight(h)
  t:SetPoint(side, frame, side, 0, 0)
  if side == "RIGHT" then t:SetTexCoord(1, 0, 0, 1) end
  if color then t:SetVertexColor(color[1], color[2], color[3], color[4]) end
  return t
end

local function RoundBar(parent, w, h)
  local f = CreateFrame("Frame", nil, parent)
  f:SetWidth(w)
  f:SetHeight(h)
  local cw = h / 2
  local dark = { 0, 0, 0, 0.6 }
  Cap(f, "BACKGROUND", CAP, "LEFT", cw, h, dark)
  Cap(f, "BACKGROUND", CAP, "RIGHT", cw, h, dark)
  local mid = f:CreateTexture(nil, "BACKGROUND")
  mid:SetPoint("TOPLEFT", f, "TOPLEFT", cw, 0)
  mid:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -cw, 0)
  mid:SetTexture(0, 0, 0, 0.6)

  f.Fill = function(level, cr, cg, cb, alpha)
    local s = CreateFrame("StatusBar", nil, f)
    s:SetPoint("TOPLEFT", f, "TOPLEFT", cw, 0)
    s:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -cw, 0)
    s:SetFrameLevel(f:GetFrameLevel() + level)
    s:SetStatusBarTexture(FLAT)
    s:SetMinMaxValues(0, 1)
    s:SetValue(0)
    s.capL = Cap(s, "ARTWORK", CAP, "LEFT", cw, h)
    s.capL:ClearAllPoints()
    s.capL:SetPoint("RIGHT", s, "LEFT", 0, 0)
    s.capR = Cap(s, "ARTWORK", CAP, "RIGHT", cw, h)
    s.capR:ClearAllPoints()
    s.capR:SetPoint("LEFT", s, "RIGHT", 0, 0)
    s.SetColor = function(self, r, g, b)
      self:SetStatusBarColor(r, g, b, alpha)
      self.capL:SetVertexColor(r, g, b, alpha)
      self.capR:SetVertexColor(r, g, b, alpha)
    end
    s.SetProgress = function(self, max, v)
      max = math.max(max, 1)
      v = math.max(0, math.min(v, max))
      self:SetMinMaxValues(0, max)
      self:SetValue(v)
      if v > 0 then self.capL:Show() else self.capL:Hide() end
      if v >= max then self.capR:Show() else self.capR:Hide() end
    end
    s:SetColor(cr, cg, cb)
    return s
  end

  local edge = CreateFrame("Frame", nil, f)
  edge:SetAllPoints(f)
  edge:SetFrameLevel(f:GetFrameLevel() + 5)
  Cap(edge, "OVERLAY", RING, "LEFT", cw, h, EDGE)
  Cap(edge, "OVERLAY", RING, "RIGHT", cw, h, EDGE)
  local lw = math.max(1, h * 6 / 64)
  local top = edge:CreateTexture(nil, "OVERLAY")
  top:SetTexture(EDGE[1], EDGE[2], EDGE[3], EDGE[4])
  top:SetHeight(lw)
  top:SetPoint("TOPLEFT", edge, "TOPLEFT", cw, 0)
  top:SetPoint("TOPRIGHT", edge, "TOPRIGHT", -cw, 0)
  local bot = edge:CreateTexture(nil, "OVERLAY")
  bot:SetTexture(EDGE[1], EDGE[2], EDGE[3], EDGE[4])
  bot:SetHeight(lw)
  bot:SetPoint("BOTTOMLEFT", edge, "BOTTOMLEFT", cw, 0)
  bot:SetPoint("BOTTOMRIGHT", edge, "BOTTOMRIGHT", -cw, 0)
  f.text = edge:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  f.text:SetPoint("CENTER", edge, "CENTER", 0, 0)
  return f
end

local MAX_LEVEL = 60

function Extra.UpdateXP()
  if not xpHolder then return end
  local show = Wanted() or editing
  if show and UnitLevel("player") < MAX_LEVEL then
    local cur, max, rested = UnitXP("player"), UnitXPMax("player"), GetXPExhaustion() or 0
    max = math.max(max, 1)
    xpBar:SetProgress(max, cur)
    restBar:SetProgress(max, cur + rested)
    local text = string.format("Level %d   %d / %d  (%d%%)", UnitLevel("player"), cur, max,
                               math.floor(cur / max * 100))
    if rested > 0 then text = text .. "   rested " .. rested end
    xpText:SetText(text)
    xpHolder:Show()
  elseif editing then
    xpHolder:Show()
  else
    xpHolder:Hide()
  end
  local name, reaction, minV, maxV, value = GetWatchedFactionInfo()
  if show and name then
    local span = math.max(maxV - minV, 1)
    repBar:SetProgress(span, value - minV)
    local c = FACTION_BAR_COLORS and FACTION_BAR_COLORS[reaction]
    if c then repBar:SetColor(c.r, c.g, c.b) end
    repText:SetText(string.format("%s   %d / %d", name, value - minV, span))
    repHolder:Show()
  elseif editing then
    repHolder:Show()
  else
    repHolder:Hide()
  end
end

local function BuildXP()
  xpHolder = MakeHolder("WowPadXPBar", "xp", XP_W, XP_H, { "BOTTOM", UIParent, "BOTTOM", 0, 2 })
  local xp = RoundBar(xpHolder, XP_W, XP_H)
  xp:SetAllPoints(xpHolder)
  restBar = xp.Fill(1, 0.0, 0.39, 0.88, 0.55)
  xpBar = xp.Fill(2, 0.58, 0.0, 0.55, 1)
  xpText = xp.text
  MakeMover(xpHolder, "XP")
  ApplyPos(xpHolder)

  repHolder = MakeHolder("WowPadRepBar", "rep", XP_W, REP_H, { "BOTTOM", UIParent, "BOTTOM", 0, 18 })
  local rep = RoundBar(repHolder, XP_W, REP_H)
  rep:SetAllPoints(repHolder)
  repBar = rep.Fill(1, 0, 0.6, 0.1, 1)
  repText = rep.text
  MakeMover(repHolder, "Reputation")
  ApplyPos(repHolder)
end

---------------------------------------------------------------------------
-- Pet bar: the 10 pet actions; left click uses one, right click toggles its autocast.
---------------------------------------------------------------------------
local PET_SIZE, PET_GAP = 30, 4
local petHolder, petButtons = nil, {}

function Extra.UpdatePet()
  if not petHolder then return end
  local show = editing or (Wanted() and UnitExists("pet") and PetHasActionBar())
  if not show then petHolder:Hide() return end
  petHolder:Show()
  for i = 1, 10 do
    local b = petButtons[i]
    local name, _, texture, isToken, isActive, autoAllowed, autoEnabled = GetPetActionInfo(i)
    if isToken and texture then texture = getglobal(texture) end
    if texture then b.icon:SetTexture(texture); b.icon:Show() else b.icon:Hide() end
    b:SetChecked(isActive and 1 or nil)
    if autoAllowed then b.autocastable:Show() else b.autocastable:Hide() end
    if autoEnabled then b.autocast:Show() else b.autocast:Hide() end
    if b.cooldown and CooldownFrame_SetTimer then
      local start, duration, enable = GetPetActionCooldown(i)
      if start then CooldownFrame_SetTimer(b.cooldown, start, duration, enable) end
    end
  end
end

local function BuildPet()
  local w = 10 * PET_SIZE + 9 * PET_GAP
  petHolder = MakeHolder("WowPadPetBar", "pet", w, PET_SIZE, { "BOTTOM", UIParent, "BOTTOM", 0, 330 })
  for i = 1, 10 do
    local name = "WowPadPetButton" .. i
    local b = CreateFrame("CheckButton", name, petHolder)
    b:SetWidth(PET_SIZE)
    b:SetHeight(PET_SIZE)
    b:SetPoint("LEFT", petHolder, "LEFT", (i - 1) * (PET_SIZE + PET_GAP), 0)
    b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    b:RegisterForDrag("LeftButton")
    b.id = i
    local bg = b:CreateTexture(nil, "BACKGROUND")
    bg:SetTexture("Interface\\Buttons\\UI-Quickslot2")
    bg:SetWidth(PET_SIZE * 64 / 36)
    bg:SetHeight(PET_SIZE * 64 / 36)
    bg:SetPoint("CENTER", b, "CENTER", 0, 0)
    b.icon = b:CreateTexture(name .. "Icon", "ARTWORK")
    b.icon:SetAllPoints(b)
    local ok, cd = pcall(CreateFrame, "Model", name .. "Cooldown", b, "CooldownFrameTemplate")
    if ok and cd then
      WP.FitCooldown(cd, b, PET_SIZE)
      b.cooldown = cd
    end
    b:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square")
    if b:GetHighlightTexture() then b:GetHighlightTexture():SetBlendMode("ADD") end
    b:SetCheckedTexture("Interface\\Buttons\\CheckButtonHilight")
    if b:GetCheckedTexture() then b:GetCheckedTexture():SetBlendMode("ADD") end
    b.autocastable = b:CreateTexture(nil, "OVERLAY")
    b.autocastable:SetTexture("Interface\\Buttons\\UI-AutoCastableOverlay")
    b.autocastable:SetWidth(PET_SIZE * 2)
    b.autocastable:SetHeight(PET_SIZE * 2)
    b.autocastable:SetPoint("CENTER", b, "CENTER", 0, 0)
    b.autocastable:Hide()
    -- Autocast on: a gold glow (1.12's spinning sparkle is a model).
    b.autocast = b:CreateTexture(nil, "OVERLAY")
    b.autocast:SetTexture("Interface\\AddOns\\WowPad\\Textures\\glow")
    b.autocast:SetBlendMode("ADD")
    b.autocast:SetAllPoints(b)
    b.autocast:Hide()
    b:SetScript("OnClick", function()
      if arg1 == "RightButton" then TogglePetAutocast(this.id) else CastPetAction(this.id) end
      Extra.UpdatePet()
    end)
    b:SetScript("OnDragStart", function() if editing or IsShiftKeyDown() then PickupPetAction(this.id) end end)
    b:SetScript("OnReceiveDrag", function() PickupPetAction(this.id); Extra.UpdatePet() end)
    b:SetScript("OnEnter", function()
      GameTooltip:SetOwner(this, "ANCHOR_TOP")
      GameTooltip:SetPetAction(this.id)
      GameTooltip:Show()
    end)
    b:SetScript("OnLeave", function() GameTooltip:Hide() end)
    petButtons[i] = b
  end
  MakeMover(petHolder, "Pet bar")
  ApplyPos(petHolder)
end

---------------------------------------------------------------------------
-- Shown with Blizzard's bars hidden, and everywhere in edit mode
---------------------------------------------------------------------------
-----------------------------------------------------------------------------
-- Cast bar: WowPad's own player cast / channel bar (game textures only), in a movable holder.
-- Blizzard's fixed one is switched off while ours is on (WonderPadDB.castBar, /wp castbar).
--
-- benilla fires the 1.12 cast events: SPELLCAST_START(name, ms), SPELLCAST_CHANNEL_START(ms, name),
-- SPELLCAST_DELAYED(ms), SPELLCAST_CHANNEL_UPDATE(ms), and argless SPELLCAST_STOP / FAILED /
-- INTERRUPTED / CHANNEL_STOP. There is no UnitCastingInfo, so times come from GetTime().
-----------------------------------------------------------------------------
local castHolder, castBar
local blizzCastOff = false
local CAST_W, CAST_H = 195, 13
local COLOR_CAST, COLOR_CHANNEL, COLOR_FAIL, COLOR_DONE = { 1, 0.7, 0 }, { 0, 1, 0 }, { 1, 0, 0 }, { 0, 1, 0 }
local CAST_EVENTS = { "SPELLCAST_START", "SPELLCAST_STOP", "SPELLCAST_FAILED",
  "SPELLCAST_INTERRUPTED", "SPELLCAST_DELAYED", "SPELLCAST_CHANNEL_START",
  "SPELLCAST_CHANNEL_UPDATE", "SPELLCAST_CHANNEL_STOP", "PLAYER_ENTERING_WORLD" }

local function CastColor(c) castBar:SetStatusBarColor(c[1], c[2], c[3]) end

local function CastFadeOut()
  castBar.casting, castBar.channeling = nil, nil
  castBar.spark:Hide()
  castBar.fading = true
end

local function CastBegin(channel, name, dur)
  if not dur or dur <= 0 then return end
  castBar.startT, castBar.dur = GetTime(), dur
  castBar.casting, castBar.channeling, castBar.fading = not channel, channel, nil
  CastColor(channel and COLOR_CHANNEL or COLOR_CAST)
  castBar.text:SetText((name and name ~= "") and name or "")
  castBar:SetMinMaxValues(0, dur)
  castBar:SetValue(channel and dur or 0)
  castBar.flash:Hide()
  castBar.spark:Show()
  castBar:SetAlpha(1)
  castBar:Show()
end

local function CastEvent()
  local ev = event
  if ev == "PLAYER_ENTERING_WORLD" then
    if not (castBar.casting or castBar.channeling) then castBar:Hide() end
  elseif ev == "SPELLCAST_START" then
    CastBegin(false, arg1, (arg2 or 0) / 1000)
  elseif ev == "SPELLCAST_CHANNEL_START" then
    CastBegin(true, arg2, (arg1 or 0) / 1000)
  elseif ev == "SPELLCAST_DELAYED" then
    if castBar.casting then
      castBar.dur = castBar.dur + (arg1 or 0) / 1000
      castBar:SetMinMaxValues(0, castBar.dur)
    end
  elseif ev == "SPELLCAST_CHANNEL_UPDATE" then
    if castBar.channeling then
      castBar.startT, castBar.dur = GetTime(), (arg1 or 0) / 1000
      castBar:SetMinMaxValues(0, castBar.dur)
    end
  elseif ev == "SPELLCAST_STOP" then
    if castBar.casting or castBar.channeling then
      local _, max = castBar:GetMinMaxValues()
      castBar:SetValue(castBar.casting and max or 0)
      CastColor(COLOR_DONE)
      castBar.flash:Show()
      CastFadeOut()
    end
  elseif ev == "SPELLCAST_CHANNEL_STOP" then
    if castBar.casting or castBar.channeling then
      castBar:SetValue(0)
      CastColor(COLOR_DONE)
      castBar.flash:Show()
      CastFadeOut()
    end
  elseif ev == "SPELLCAST_FAILED" or ev == "SPELLCAST_INTERRUPTED" then
    if castBar.casting or castBar.channeling or castBar:IsShown() then
      local _, max = castBar:GetMinMaxValues()
      castBar:SetValue(max)
      CastColor(COLOR_FAIL)
      castBar.text:SetText(ev == "SPELLCAST_FAILED" and (FAILED or "Failed") or (INTERRUPTED or "Interrupted"))
      castBar.timer:SetText("")
      CastFadeOut()
    end
  end
end

local function CastUpdate()
  local self = this
  local now = GetTime()
  if self.casting or self.channeling then
    local dur = self.dur
    local v = self.casting and (now - self.startT) or (self.startT + dur - now)
    if (self.casting and v >= dur) or (self.channeling and v <= 0) then
      v = self.casting and dur or 0
    end
    if v < 0 then v = 0 end
    self:SetValue(v)
    local left = self.casting and (dur - v) or v
    self.timer:SetText(string.format("%.1f", math.max(left, 0)))
    local pos = dur > 0 and (v / dur) or 0
    self.spark:SetPoint("CENTER", self, "LEFT", pos * CAST_W, 2)
  elseif self.fading then
    local a = self:GetAlpha() - arg1 * 2
    if a <= 0 then self.fading = nil; self:Hide(); self:SetAlpha(1) else self:SetAlpha(a) end
  end
end

local function BuildCast()
  castHolder = MakeHolder("WowPadCastHolder", "cast", 240, 32, { "BOTTOM", UIParent, "BOTTOM", 0, 190 })
  castBar = CreateFrame("StatusBar", "WowPadCastBar", castHolder)
  castBar:SetWidth(CAST_W)
  castBar:SetHeight(CAST_H)
  castBar:SetPoint("CENTER", castHolder, "CENTER", 10, 0)
  castBar:SetStatusBarTexture("Interface\\TargetingFrame\\UI-StatusBar")
  castBar:SetMinMaxValues(0, 1)
  local bg = castBar:CreateTexture(nil, "BACKGROUND")
  bg:SetTexture(0, 0, 0, 0.5)
  bg:SetAllPoints(castBar)
  local border = castBar:CreateTexture(nil, "ARTWORK")
  border:SetTexture("Interface\\CastingBar\\UI-CastingBar-Border")
  border:SetWidth(256)
  border:SetHeight(64)
  border:SetPoint("TOP", castBar, "TOP", 0, 28)
  castBar.flash = castBar:CreateTexture(nil, "OVERLAY")
  castBar.flash:SetTexture("Interface\\CastingBar\\UI-CastingBar-Flash")
  castBar.flash:SetBlendMode("ADD")
  castBar.flash:SetWidth(256)
  castBar.flash:SetHeight(64)
  castBar.flash:SetPoint("TOP", castBar, "TOP", 0, 28)
  castBar.flash:Hide()
  castBar.spark = castBar:CreateTexture(nil, "OVERLAY")
  castBar.spark:SetTexture("Interface\\CastingBar\\UI-CastingBar-Spark")
  castBar.spark:SetBlendMode("ADD")
  castBar.spark:SetWidth(32)
  castBar.spark:SetHeight(32)
  castBar.text = castBar:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
  castBar.text:SetPoint("TOP", castBar, "TOP", 0, 5)
  castBar.text:SetWidth(185)
  castBar.text:SetHeight(16)
  castBar.timer = castBar:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  castBar.timer:SetPoint("LEFT", castBar, "RIGHT", 6, 1)
  castBar:SetScript("OnEvent", CastEvent)
  castBar:SetScript("OnUpdate", CastUpdate)
  castBar:Hide()
  MakeMover(castHolder, "Cast bar")
  ApplyPos(castHolder)
end

local function CastOn() return not (WowPadDB and WowPadDB.castBar == false) end

local function SetCast(on)
  if not castBar then return end
  if on then
    for i = 1, table.getn(CAST_EVENTS) do castBar:RegisterEvent(CAST_EVENTS[i]) end
    castHolder:Show()
    if CastingBarFrame and not blizzCastOff then
      CastingBarFrame:UnregisterAllEvents()
      CastingBarFrame:Hide()
      blizzCastOff = true
    end
  else
    castBar:UnregisterAllEvents()
    castBar:Hide()
    castHolder:Hide()
    if CastingBarFrame and blizzCastOff then
      -- Give Blizzard's bar its events back (we only unregistered events; its OnEvent script and
      -- frame the reference defines stay intact).
      for i = 1, table.getn(CAST_EVENTS) do
        if CAST_EVENTS[i] ~= "PLAYER_ENTERING_WORLD" then CastingBarFrame:RegisterEvent(CAST_EVENTS[i]) end
      end
      blizzCastOff = false
    end
  end
end

function Extra.ApplyShown()
  Extra.UpdateXP()
  Extra.UpdatePet()
  SetCast(CastOn())
end

function Extra.SetEditing(on)
  editing = on and true or false
  for k = 1, table.getn(movers) do
    if editing then movers[k]:Show() else movers[k]:Hide() end
  end
  -- A preview bar so the cast bar can be placed even when nothing is being cast.
  if castBar and CastOn() and not (castBar.casting or castBar.channeling) then
    if editing then
      castBar:SetMinMaxValues(0, 1)
      castBar:SetValue(0.6)
      CastColor(COLOR_CAST)
      castBar.text:SetText("Cast bar")
      castBar.timer:SetText("1.2")
      castBar.fading = nil
      castBar:SetAlpha(1)
      castBar:Show()
    else
      castBar:Hide()
    end
  end
  Extra.ApplyShown()
end

table.insert(WP.setupHooks, function()
  BuildXP()
  BuildPet()
  BuildCast()
  Extra.ApplyShown()
end)

local ev = CreateFrame("Frame")
local EVENTS = { "PLAYER_XP_UPDATE", "UPDATE_EXHAUSTION", "PLAYER_LEVEL_UP", "UPDATE_FACTION",
                 "PLAYER_ENTERING_WORLD", "PET_BAR_UPDATE", "PET_BAR_UPDATE_COOLDOWN", "UNIT_PET",
                 "PLAYER_CONTROL_LOST", "PLAYER_CONTROL_GAINED", "UNIT_FLAGS", "UNIT_AURA" }
for k = 1, table.getn(EVENTS) do ev:RegisterEvent(EVENTS[k]) end
ev:SetScript("OnEvent", function()
  if (event == "UNIT_AURA" or event == "UNIT_FLAGS") and arg1 ~= "pet" then return end
  if event == "PLAYER_XP_UPDATE" or event == "UPDATE_EXHAUSTION" or event == "PLAYER_LEVEL_UP"
      or event == "UPDATE_FACTION" then
    Extra.UpdateXP()
  elseif event == "PLAYER_ENTERING_WORLD" then
    Extra.ApplyShown()
  else
    Extra.UpdatePet()
  end
end)
