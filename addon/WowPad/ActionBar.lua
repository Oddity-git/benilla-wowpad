-- ActionBar.lua - the controller action bar and the utility ring.
--
-- One frame (WowPadBar) holding four clusters drawn like the pad:
--     Default (no trigger)   top    : D-pad = 4 slots, face = fixed (jump/back/attack/menu)
--     Left    (LT held)      left   : D-pad + face = 8 slots
--     Right   (RT held)      right  : 8 slots
--     Bottom  (LT+RT held)   bottom : 8 slots
-- Lite mode shows a single cluster that switches to the held set.
--
-- The slots are WowPad's own: benilla-wowpad's engine patch adds client-only action slots
-- (ids 121-256) that work like any action slot (icon, range, usable, cooldown, drag and drop) but
-- never reach the server, so the stock bars keep their spells when WowPad is off. WowPad saves
-- them per character (WowPadCharDB.bars):
--     Default D-pad  -> 121-124, Left set -> 125-132 (both paged with stance / stealth / forms,
--                       12 more slots per page, like the main bar: page n = 121 + 12n ...)
--     Right set      -> 181-188
--     Bottom set     -> 189-196
--     Utility ring   -> 197-204
-- The first time, each slot takes what its old stock slot held (see Migrate below). On a benilla
-- without the patch the slots are the stock ones, as before:
--     Default D-pad  -> main bar 1-4, Left set -> main bar 5-12 (paged), Right set -> 25-32,
--     Bottom set -> 37-44, Utility ring -> 49-56.
-- The bar's position and scale are account-wide (WowPadDB.bar).

local WP = WowPad
local Bar = {}
WP.Bar = Bar

local SIZE, STEP, HALF = 32, 26.5, 52.5  -- button size, spacing in a pad shape, D-pad/face offset from the cluster centre
local SIDE, VERT = 189, 50               -- left/right and top/bottom set offsets from the centre
local LAYOUT_VERSION = 2                 -- bump when the shape changes (resets saved position/scale)
local CLUSTERS = {                       -- set -> centre offset inside the bar
  [0] = { 0, VERT },
  [1] = { -SIDE, 0 },
  [2] = { SIDE, 0 },
  [3] = { 0, -VERT },
}
-- slot index -> position inside a cluster (D-pad on the left, face on the right)
local SLOT_POS = {
  [1] = { -HALF, STEP }, [2] = { -HALF, -STEP }, [3] = { -HALF - STEP, 0 }, [4] = { -HALF + STEP, 0 }, -- U D L R
  [5] = { HALF, -STEP }, [6] = { HALF + STEP, 0 }, [7] = { HALF - STEP, 0 }, [8] = { HALF, STEP },     -- A B X Y
}
local TEX = "Interface\\AddOns\\WowPad\\Textures\\"
local FACE_KEY = { [5] = "A", [6] = "B", [7] = "X", [8] = "Y" }
-- One arrow (Textures/dpadarrow, points up) turned per direction with SetTexCoord.
local DPAD_ARROW = {
  [1] = { 0, 0, 0, 1, 1, 0, 1, 1 },   -- up
  [2] = { 1, 1, 1, 0, 0, 1, 0, 0 },   -- down
  [3] = { 1, 0, 0, 0, 1, 1, 0, 1 },   -- left
  [4] = { 0, 1, 1, 1, 0, 0, 1, 0 },   -- right
}
-- The default set's face buttons are fixed functions (display only).
local FIXED = {
  [5] = { "Interface\\Icons\\Ability_Rogue_Sprint", "Jump" },
  [6] = { "Interface\\Icons\\Spell_Shadow_SacrificialShield", "Back / clear target" },
  [7] = { "Interface\\Icons\\Ability_MeleeDamage", "Interact + attack" },
  [8] = { "Interface\\Icons\\Ability_Hunter_SniperShot", "Target menu" },
}
local RING_ICON = "Interface\\Icons\\INV_Jewelry_Ring_03"

local bar, clusters, slots = nil, {}, {}   -- slots["set_i"] = button
Bar.editing = false

-- The 1.12 cooldown sweep is a model drawn at a fixed size (made for the 36 x 36 action button)
-- from its frame's bottom-left corner, so resizing the frame moves the sweep off centre instead
-- of shrinking it. Keep the frame 36 x 36, centred, and scale it to the size wanted.
function WP.FitCooldown(cd, parent, size)
  cd:ClearAllPoints()
  cd:SetWidth(36)
  cd:SetHeight(36)
  cd:SetScale(size / 36)
  cd:SetPoint("CENTER", parent, "CENTER", 0, 0)
end

local function Key(set, i) return set .. "_" .. i end
local function Shown(region, on) if on then region:Show() else region:Hide() end end

---------------------------------------------------------------------------
-- Which action slot a pad slot uses right now.
---------------------------------------------------------------------------
-- The main bar's slot `id` (1-12) on the current page, with the stance bar (warrior stances, druid
-- forms, rogue stealth) on page 1, as ActionButton_GetPagedID does for the main bar.
local function MainSlot(id)
  local page = CURRENT_ACTIONBAR_PAGE or 1
  if page == 1 then
    local offset = GetBonusBarOffset()
    if offset > 0 then return id + (NUM_ACTIONBAR_PAGES + offset - 1) * NUM_ACTIONBAR_BUTTONS end
  end
  return id + (page - 1) * NUM_ACTIONBAR_BUTTONS
end

-- The stock slot a pad slot used before WowPad had its own (and still uses without the patch).
local function StockSlot(set, i)
  if set == 0 then return MainSlot(i) end
  if set == 1 then return MainSlot(4 + i) end
  if set == 2 then return 24 + i end
  if set == 3 then return 36 + i end
  return 48 + i   -- 9: the ring
end

local OWN = SetClientAction ~= nil and GetClientAction ~= nil
local OWN_FIRST, OWN_LAST = 121, 204

-- WowPad's own slot for a pad slot on stance page `page` (0 = none, as GetBonusBarOffset).
local function OwnSlot(set, i, page)
  if set == 0 or set == 1 then
    local k = set == 0 and i or 4 + i
    return 120 + (page or GetBonusBarOffset()) * 12 + k
  end
  if set == 2 then return 180 + i end
  if set == 3 then return 188 + i end
  return 196 + i
end

local function ActionSlot(set, i)
  if OWN then return OwnSlot(set, i) end
  return StockSlot(set, i)
end
Bar.ActionSlot = ActionSlot

---------------------------------------------------------------------------
-- Keeping the own slots: restored at login, saved on every change, and filled from the stock
-- slots once per character.
---------------------------------------------------------------------------
local restored = false

local function SaveSlot(id)
  if not restored or id < OWN_FIRST or id > OWN_LAST then return end
  local kind, action = GetClientAction(id)
  WowPadCharDB.bars = WowPadCharDB.bars or {}
  if kind and action then
    WowPadCharDB.bars[id] = { kind, action }
  else
    WowPadCharDB.bars[id] = nil
  end
end

-- Each own slot, with the stock slot it takes over the first time.
local function EachOwnSlot(fn)
  for page = 0, 4 do
    for k = 1, 12 do
      local stock = page == 0 and k or (NUM_ACTIONBAR_PAGES + page - 1) * NUM_ACTIONBAR_BUTTONS + k
      fn(120 + page * 12 + k, stock)
    end
  end
  for i = 1, 8 do
    fn(180 + i, 24 + i)
    fn(188 + i, 36 + i)
    fn(196 + i, 48 + i)
  end
end

-- First time on this character: copy what the stock slots WowPad used held. The stock bar keeps
-- them too; from here on the two are separate.
local function Migrate()
  WowPadCharDB.bars = {}
  local n = 0
  EachOwnSlot(function(own, stock)
    local kind, action = GetClientAction(stock)
    if kind and action then
      WowPadCharDB.bars[own] = { kind, action }
      n = n + 1
    end
  end)
  WowPadCharDB.barsVersion = 1
  if n > 0 then
    DEFAULT_CHAT_FRAME:AddMessage("|cff33ccffWowPad|r: the controller bar now has its own slots. "
      .. n .. " actions copied from your action bars, which WowPad no longer changes.")
  end
end

local function Restore()
  WowPadCharDB = WowPadCharDB or {}
  if not WowPadCharDB.barsVersion then Migrate() end
  local bars = WowPadCharDB.bars or {}
  for id = OWN_FIRST, OWN_LAST do
    -- A slot the client already holds as saved is left alone: the client keeps the slots for the
    -- whole session (an addon reload, or WowPad turned off and on), and writing one again drops
    -- its icon, which the client does not send back for a slot it thinks is unchanged.
    local a = bars[id]
    local kind, action = GetClientAction(id)
    if a then
      if kind ~= a[1] or action ~= a[2] then SetClientAction(id, a[1], a[2]) end
    elseif kind then
      SetClientAction(id)
    end
  end
  restored = true
end

-- The stock bars arrive a moment after the world: restore once they have, or after a few seconds.
local restoreWait
local restorer = CreateFrame("Frame")
restorer:Hide()
restorer:SetScript("OnUpdate", function()
  restoreWait = restoreWait - arg1
  local stockIn = false
  for id = 1, 120 do if HasAction(id) then stockIn = true break end end
  if (stockIn and restoreWait < 2.5) or restoreWait <= 0 then
    this:Hide()
    Restore()
    if Bar.UpdateAll then Bar.UpdateAll() end
  end
end)
if OWN then
  restorer:RegisterEvent("PLAYER_ENTERING_WORLD")
  restorer:RegisterEvent("PLAYER_LOGOUT")
  restorer:SetScript("OnEvent", function()
    if event == "PLAYER_ENTERING_WORLD" and not restored then
      restoreWait = 3
      this:Show()
    elseif event == "PLAYER_LOGOUT" and restored then
      for id = OWN_FIRST, OWN_LAST do SaveSlot(id) end
    end
  end)
end

-- Which bar slot holds the ring button ("set_i"), from WowPadDB.wpRingSlot (set*10+i).
function WP.RingSlotKey()
  local v = WowPadDB and tonumber(WowPadDB.wpRingSlot) or 0
  if v <= 0 then return nil end
  return math.floor(v / 10) .. "_" .. math.mod(v, 10)
end

---------------------------------------------------------------------------
-- Visual updates
---------------------------------------------------------------------------
local function SetIcon(btn, path)
  if path == btn.iconPath then return end
  btn.iconPath = path
  -- Round icon: SetPortraitToTexture circle-crops a texture by the texture's name.
  if path then SetPortraitToTexture(btn.icon:GetName(), path) else btn.icon:SetTexture(nil) end
end

function Bar.UpdateState(btn)
  local a = btn.action
  local on = a and (IsCurrentAction(a) or IsAutoRepeatAction(a))
  btn:SetChecked(on and 1 or nil)
end

function Bar.UpdateUsable(btn)
  local a = btn.action
  if not a or not HasAction(a) then return end
  Bar.UpdateState(btn)
  local usable, noMana = IsUsableAction(a)
  if IsActionInRange(a) == 0 then
    btn.icon:SetVertexColor(0.85, 0.2, 0.2)
  elseif noMana then
    btn.icon:SetVertexColor(0.4, 0.4, 1.0)
  elseif usable then
    btn.icon:SetVertexColor(1, 1, 1)
  else
    btn.icon:SetVertexColor(0.4, 0.4, 0.4)
  end
end

local function UpdateCooldown(btn)
  if not btn.cooldown then return end
  local a = btn.action
  if a and HasAction(a) and CooldownFrame_SetTimer then
    local start, duration, enable = GetActionCooldown(a)
    CooldownFrame_SetTimer(btn.cooldown, start, duration, enable)
  else
    btn.cooldown:Hide()
  end
end

local function UpdateButton(btn)
  btn.action = ActionSlot(btn.set, btn.index)
  local a = btn.action
  local icon = HasAction(a) and GetActionTexture(a) or nil
  if WP.RingSlotKey() == btn.key then icon = RING_ICON end   -- the ring's own button
  SetIcon(btn, icon)
  Shown(btn.icon, icon ~= nil)
  Shown(btn.empty, icon == nil)
  if btn.glyph then
    btn.glyph:ClearAllPoints()
    -- small in the bottom-right corner over a skill, big in the middle of an empty slot
    if icon then
      btn.glyph:SetWidth(16); btn.glyph:SetHeight(16)
      btn.glyph:SetPoint("BOTTOMRIGHT", btn, "BOTTOMRIGHT", 2, -2)
    else
      btn.glyph:SetWidth(20); btn.glyph:SetHeight(20)
      btn.glyph:SetPoint("CENTER", btn, "CENTER", 0, 0)
    end
  end
  UpdateCooldown(btn)
  if HasAction(a) and IsConsumableAction(a) then
    btn.count:SetText(GetActionCount(a))
  else
    btn.count:SetText("")
  end
  if icon and WP.RingSlotKey() ~= btn.key then Bar.UpdateUsable(btn) else btn:SetChecked(nil) end
end

table.insert(WP.styleHooks, function()
  for _, btn in pairs(slots) do
    if btn.faceKey then btn.glyph:SetTexture(WP.FaceTexture(btn.faceKey)) end
  end
  for _, f in pairs(Bar.fixedFrames or {}) do
    if f.faceKey then f.glyph:SetTexture(WP.FaceTexture(f.faceKey)) end
  end
  Bar.HighlightSet(WP.set)
end)

function Bar.UpdateAll()
  for _, btn in pairs(slots) do UpdateButton(btn) end
end

---------------------------------------------------------------------------
-- Which set is up: gold outline on the held set, or (lite) only that cluster.
---------------------------------------------------------------------------
local tabs, liteView = {}, 0
local LITE_NAMES = { [0] = "Default", [1] = "LT", [2] = "RT", [3] = "LT+RT" }

local function UpdateClusters()
  if not bar then return end
  local lite = WowPadDB and WowPadDB.barLite
  local view = Bar.editing and liteView or math.max(WP.set or 0, 0)
  for s, c in pairs(clusters) do Shown(c, not lite or s == view) end
  if WP.LiteCD then WP.LiteCD.Update() end
end

-- The set the lite bar shows now, or nil when the bar is full or hidden.
function Bar.LiteView()
  if not bar or not bar:IsVisible() or not (WowPadDB and WowPadDB.barLite) then return nil end
  return Bar.editing and liteView or math.max(WP.set or 0, 0)
end

function Bar.HighlightSet(set)
  local lite = WowPadDB and WowPadDB.barLite
  for s, c in pairs(clusters) do
    for k = 1, table.getn(c.outlines) do Shown(c.outlines[k], s == set and not lite) end
  end
  if Bar.badge then
    local name = set and set > 0 and ({ "LT", "RT", "LT+RT" })[set]
    if lite and name then Bar.badge:SetText(WP.Keys(name)); Bar.badge:Show() else Bar.badge:Hide() end
  end
  UpdateClusters()
end

-- Shown always (default), or in controller mode only (/wp bar); always while editing.
function Bar.UpdateVisibility()
  if not bar then return end
  local show = Bar.editing or WowPadDB.barAlways ~= false or WP.mode == "controller"
  Shown(bar, show)
  UpdateClusters()
end

---------------------------------------------------------------------------
-- Pressing a slot
---------------------------------------------------------------------------
-- The icon sinks in and darkens for a moment whenever the slot fires.
local PRESS_TIME, PRESS_INSET, PRESS_DARK = 0.12, 2, 0.55
local pressed = {}
local pressDriver = CreateFrame("Frame")
pressDriver:Hide()
local function Release(btn)
  pressed[btn] = nil
  btn.icon:ClearAllPoints()
  btn.icon:SetAllPoints(btn)
  if btn.action then Bar.UpdateUsable(btn) else btn.icon:SetVertexColor(1, 1, 1) end
end
pressDriver:SetScript("OnUpdate", function()
  local any = false
  for btn, t in pairs(pressed) do
    t = t - arg1
    if t <= 0 then Release(btn) else pressed[btn] = t; any = true end
  end
  if not any then this:Hide() end
end)
function Bar.Press(btn)
  if not btn or not btn.icon or not btn:IsVisible() then return end
  btn.icon:ClearAllPoints()
  btn.icon:SetPoint("TOPLEFT", btn, "TOPLEFT", PRESS_INSET, -PRESS_INSET)
  btn.icon:SetPoint("BOTTOMRIGHT", btn, "BOTTOMRIGHT", -PRESS_INSET, PRESS_INSET)
  local r, g, b = btn.icon:GetVertexColor()
  btn.icon:SetVertexColor((r or 1) * PRESS_DARK, (g or 1) * PRESS_DARK, (b or 1) * PRESS_DARK)
  pressed[btn] = PRESS_TIME
  pressDriver:Show()
end

function Bar.PressFixed(i)
  if Bar.fixedFrames then Bar.Press(Bar.fixedFrames[i]) end
end

-- The pad fired slot i of a set: use its action on the press, like a key bound to the slot.
function Bar.Fire(set, i, down)
  if not down then return end
  local btn = slots[Key(set, i)]
  local a = ActionSlot(set, i)
  UseAction(a, 0)
  if btn then Bar.UpdateState(btn); Bar.Press(btn) end
end

---------------------------------------------------------------------------
-- Mouse: click to use, drag to move actions (shift, or any time in edit mode).
---------------------------------------------------------------------------
local function ShowTooltip()
  local btn = this
  GameTooltip:SetOwner(btn, "ANCHOR_TOP")
  if btn.fixed then
    GameTooltip:SetText(btn.fixed)
  elseif btn.action and HasAction(btn.action) then
    GameTooltip:SetAction(btn.action)
  else
    GameTooltip:SetText(Bar.editing and "Empty: drop a spell, item or macro here" or "Empty")
  end
  if Bar.editing and btn.action and HasAction(btn.action) then
    GameTooltip:AddLine("Drag out to move, right-click to clear", 0.6, 0.8, 1)
  end
  GameTooltip:Show()
end

local function OnClick()
  local btn = this
  if Bar.editing and arg1 == "RightButton" then
    if HasAction(btn.action) then PickupAction(btn.action); ClearCursor() end
  elseif Bar.editing then
    if CursorHasItem() or CursorHasSpell() then PlaceAction(btn.action) end
  else
    UseAction(btn.action, 1)
    Bar.Press(btn)
  end
  Bar.UpdateState(btn)
end

local function OnDragStart()
  if Bar.editing or IsShiftKeyDown() then PickupAction(this.action) end
end

local function OnReceiveDrag()
  PlaceAction(this.action)
end

---------------------------------------------------------------------------
-- Position / scale (account-wide). Normal and lite layouts keep their own spot and size.
---------------------------------------------------------------------------
function Bar.Pos()
  if not WowPadDB.bar or WowPadDB.bar.layout ~= LAYOUT_VERSION then
    WowPadDB.bar = { layout = LAYOUT_VERSION }
  end
  if WowPadDB.barLite then
    WowPadDB.bar.lite = WowPadDB.bar.lite or {}
    return WowPadDB.bar.lite
  end
  return WowPadDB.bar
end

local function SavePosition()
  WP.SavePlace(bar, Bar.Pos())
end

local PAD = 10   -- margin around the clusters (edit-mode background)
local function ApplyPosition()
  local p = Bar.Pos()
  local lite = WowPadDB.barLite
  if lite then
    bar:SetWidth(2 * (HALF + STEP) + SIZE + 2 * PAD)
    bar:SetHeight(2 * STEP + SIZE + 2 * PAD)
  else
    bar:SetWidth(2 * SIDE + 2 * (HALF + STEP) + SIZE + 2 * PAD)
    bar:SetHeight(2 * VERT + 2 * STEP + SIZE + 2 * PAD)
  end
  for set, c in pairs(clusters) do
    c:ClearAllPoints()
    if lite then c:SetPoint("CENTER", bar, "CENTER", 0, 0)
    else c:SetPoint("CENTER", bar, "CENTER", CLUSTERS[set][1], CLUSTERS[set][2]) end
  end
  bar:SetScale(p.scale or 1)
  if not WP.PlaceAt(bar, p) then
    bar:ClearAllPoints()
    bar:SetPoint("BOTTOM", UIParent, "BOTTOM", 0, lite and 100 or 120)
  end
end

function Bar.SetScale(scale)
  if not bar then return end
  scale = math.max(0.4, math.min(1.6, scale))
  local old = bar:GetScale()
  local p = Bar.Pos()
  if not p.dx then WP.SavePlace(bar, p) end
  WP.RescalePlace(p, old, scale)
  p.scale = scale
  ApplyPosition()
end

---------------------------------------------------------------------------
-- Lite mode: one cluster; holding a trigger shows that set in its place.
---------------------------------------------------------------------------
local function UpdateTabs()
  for s, t in pairs(tabs) do
    Shown(t, Bar.editing and WowPadDB.barLite)
    if s == liteView then t:LockHighlight() else t:UnlockHighlight() end
  end
end

function Bar.SetLite(on)
  if not bar then return end
  WowPadDB.barLite = on and true or false
  liteView = 0
  ApplyPosition()
  Bar.HighlightSet(WP.set)
  UpdateTabs()
end

---------------------------------------------------------------------------
-- Edit mode
---------------------------------------------------------------------------
local editHelp
function Bar.SetEditing(on)
  if not bar then return end
  Bar.editing = on and true or false
  bar:EnableMouse(Bar.editing)
  bar:EnableMouseWheel(Bar.editing)   -- only while editing, so camera zoom works over the bar
  Shown(bar.editBg, Bar.editing)
  Shown(editHelp, Bar.editing)
  editHelp:ClearAllPoints()
  editHelp:SetPoint("BOTTOM", bar, "TOP", 0, WowPadDB.barLite and 30 or 6)
  if not Bar.editing then liteView = 0 end
  if WP.RadialSetEditing then WP.RadialSetEditing(Bar.editing) end
  if WP.Ring and WP.Ring.SetEditing then WP.Ring.SetEditing(Bar.editing) end
  if WP.Extra then WP.Extra.SetEditing(Bar.editing) end
  if WP.LiteCD then WP.LiteCD.SetEditing(Bar.editing) end
  UpdateTabs()
  Bar.UpdateVisibility()
  if Bar.editing then
    WP.Print("Edit mode: drag spells, items or macros onto slots; drag the bar to move it; "
             .. "mouse wheel over it to resize; right-click a slot to clear. /wp edit to finish.")
  else
    WP.Print("Controller bar saved.")
  end
end
function WP.ToggleEdit() Bar.SetEditing(not Bar.editing) end

function Bar.ToggleAlways()
  if not bar then return end
  WowPadDB.barAlways = (WowPadDB.barAlways == false)
  Bar.UpdateVisibility()
  WP.Print("Controller bar: " .. (WowPadDB.barAlways and "always visible" or "controller mode only"))
end

---------------------------------------------------------------------------
-- Construction
---------------------------------------------------------------------------
local function MakeCluster(set)
  local c = CreateFrame("Frame", "WowPadBarCluster" .. set, bar)
  c:SetWidth(2 * (HALF + STEP) + SIZE)
  c:SetHeight(2 * STEP + SIZE)
  c:SetPoint("CENTER", bar, "CENTER", CLUSTERS[set][1], CLUSTERS[set][2])
  c.outlines = {}
  clusters[set] = c
  return c
end

-- Gold outline on every button of the held set, on its own frame above the button.
local function AddOutline(parent, set)
  local holder = CreateFrame("Frame", nil, parent)
  holder:SetAllPoints(parent)
  holder:SetFrameLevel(parent:GetFrameLevel() + 5)
  local o = holder:CreateTexture(nil, "OVERLAY")
  o:SetTexture(TEX .. "outline")
  o:SetBlendMode("ADD")
  o:SetWidth(SIZE * 1.15)
  o:SetHeight(SIZE * 1.15)
  o:SetPoint("CENTER", holder, "CENTER", 0, 0)
  o:Hide()
  if clusters[set] then table.insert(clusters[set].outlines, o) end
end

local function Ring(parent)
  local ring = parent:CreateTexture(nil, "OVERLAY")
  ring:SetTexture(TEX .. "ring")
  ring:SetWidth(SIZE * 1.12)
  ring:SetHeight(SIZE * 1.12)
  ring:SetPoint("CENTER", parent, "CENTER", 0, 0)
  return ring
end

local function Glyph(btn)
  local gf = CreateFrame("Frame", nil, btn)
  gf:SetAllPoints(btn)
  gf:SetFrameLevel(btn:GetFrameLevel() + 6)   -- above the set outline (+5)
  local g = gf:CreateTexture(nil, "OVERLAY")
  g:SetWidth(16)
  g:SetHeight(16)
  g:SetPoint("BOTTOMRIGHT", btn, "BOTTOMRIGHT", 2, -2)
  return g
end

local function MakeFixed(c, i)
  local name = "WowPadFixed" .. i
  local f = CreateFrame("Button", name, c)
  f:SetWidth(SIZE)
  f:SetHeight(SIZE)
  f:SetPoint("CENTER", c, "CENTER", SLOT_POS[i][1], SLOT_POS[i][2])
  f.icon = f:CreateTexture(name .. "Icon", "ARTWORK")
  f.icon:SetAllPoints(f)
  SetPortraitToTexture(name .. "Icon", FIXED[i][1])
  Ring(f)
  f.glyph = Glyph(f)
  f.faceKey = FACE_KEY[i]
  f.glyph:SetTexture(WP.FaceTexture(f.faceKey))
  AddOutline(f, 0)
  f.fixed = FIXED[i][2]
  Bar.fixedFrames = Bar.fixedFrames or {}
  Bar.fixedFrames[i] = f
  f:SetScript("OnEnter", ShowTooltip)
  f:SetScript("OnLeave", function() GameTooltip:Hide() end)
end

local function MakeSlot(c, set, i, x, y, noGlyph)
  local name = "WowPadSlot" .. set .. "_" .. i
  local btn = CreateFrame("CheckButton", name, c)
  btn:SetWidth(SIZE)
  btn:SetHeight(SIZE)
  btn:SetPoint("CENTER", c, "CENTER", x, y)
  btn:RegisterForClicks("LeftButtonUp", "RightButtonUp")
  btn:RegisterForDrag("LeftButton")
  btn.set, btn.index, btn.key = set, i, Key(set, i)
  btn.empty = btn:CreateTexture(nil, "BACKGROUND")
  btn.empty:SetTexture(TEX .. "disc")
  btn.empty:SetAllPoints(btn)
  btn.icon = btn:CreateTexture(name .. "Icon", "ARTWORK")
  btn.icon:SetAllPoints(btn)
  -- The 1.12 cooldown sweep is a model; the ring hides its square corners.
  local ok, cd = pcall(CreateFrame, "Model", name .. "Cooldown", btn, "CooldownFrameTemplate")
  if ok and cd then
    WP.FitCooldown(cd, btn, SIZE - 6)
    btn.cooldown = cd
  end
  Ring(btn)
  btn.count = btn:CreateFontString(nil, "OVERLAY", "NumberFontNormal")
  btn.count:SetPoint("BOTTOMRIGHT", btn, "BOTTOMRIGHT", -2, 2)
  btn:SetHighlightTexture(TEX .. "glow")
  if btn:GetHighlightTexture() then btn:GetHighlightTexture():SetBlendMode("ADD") end
  -- Checked = queued / repeating (Heroic Strike, Auto Shot...): gold glow.
  btn:SetCheckedTexture(TEX .. "glow")
  if btn:GetCheckedTexture() then btn:GetCheckedTexture():SetBlendMode("ADD") end
  if not noGlyph then
    btn.glyph = Glyph(btn)
    if DPAD_ARROW[i] then
      local t = DPAD_ARROW[i]
      btn.glyph:SetTexture(TEX .. "dpadarrow")
      btn.glyph:SetTexCoord(t[1], t[2], t[3], t[4], t[5], t[6], t[7], t[8])
    else
      btn.faceKey = FACE_KEY[i]
      btn.glyph:SetTexture(WP.FaceTexture(btn.faceKey))
    end
  end
  AddOutline(btn, set)
  btn:SetScript("OnClick", OnClick)
  btn:SetScript("OnDragStart", OnDragStart)
  btn:SetScript("OnReceiveDrag", OnReceiveDrag)
  btn:SetScript("OnEnter", ShowTooltip)
  btn:SetScript("OnLeave", function() GameTooltip:Hide() end)
  slots[btn.key] = btn
  return btn
end

table.insert(WP.setupHooks, function()
  bar = CreateFrame("Frame", "WowPadBar", UIParent)
  bar:SetFrameStrata("MEDIUM")
  bar:SetMovable(true)
  bar:SetClampedToScreen(true)
  bar:RegisterForDrag("LeftButton")
  bar:SetScript("OnDragStart", function() if Bar.editing then WP.SnapDragStart(bar) end end)
  bar:SetScript("OnDragStop", function() WP.SnapDragStop(); SavePosition() end)
  bar:SetScript("OnMouseWheel", function()
    if Bar.editing then Bar.SetScale((Bar.Pos().scale or 1) + arg1 * 0.05) end
  end)
  bar.editBg = CreateFrame("Frame", nil, bar)
  bar.editBg:SetAllPoints(bar)
  bar.editBg:SetFrameLevel(math.max(bar:GetFrameLevel() - 1, 0))
  bar.editBg:SetBackdrop({ bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
                           edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
                           tile = true, tileSize = 16, edgeSize = 18,
                           insets = { left = 3, right = 3, top = 3, bottom = 3 } })
  bar.editBg:SetBackdropColor(0.2, 0.5, 1, 0.25)
  bar.editBg:SetBackdropBorderColor(0.35, 0.7, 1, 0.7)
  bar.editBg:Hide()
  editHelp = bar:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
  editHelp:SetPoint("BOTTOM", bar, "TOP", 0, 6)
  editHelp:SetText("EDIT MODE - drag spells here, drag bar to move, wheel to resize, right-click to clear  (/wp edit to finish)")
  editHelp:Hide()
  Bar.frame = bar

  local b = bar:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  b:SetPoint("BOTTOM", bar, "TOP", 0, -4)
  b:Hide()
  Bar.badge = b
  for s = 0, 3 do
    local t = CreateFrame("Button", "WowPadBarLiteTab" .. s, bar, "UIPanelButtonTemplate")
    t:SetWidth(s == 0 and 62 or 50)
    t:SetHeight(20)
    t:SetText(WP.KeysPlain(LITE_NAMES[s]))
    t.view = s
    t:SetScript("OnClick", function()
      liteView = this.view
      UpdateTabs()
      UpdateClusters()
    end)
    t:Hide()
    tabs[s] = t
  end
  tabs[0]:SetPoint("BOTTOMRIGHT", bar, "TOP", -52, 4)
  tabs[1]:SetPoint("LEFT", tabs[0], "RIGHT", 2, 0)
  tabs[2]:SetPoint("LEFT", tabs[1], "RIGHT", 2, 0)
  tabs[3]:SetPoint("LEFT", tabs[2], "RIGHT", 2, 0)

  for set = 0, 3 do
    local c = MakeCluster(set)
    for i = 1, 8 do
      if set == 0 and i >= 5 then MakeFixed(c, i)
      else MakeSlot(c, set, i, SLOT_POS[i][1], SLOT_POS[i][2]) end
    end
  end
  ApplyPosition()
  Bar.UpdateAll()
  Bar.HighlightSet(WP.set)
  Bar.UpdateVisibility()
end)

---------------------------------------------------------------------------
-- Events
---------------------------------------------------------------------------
local ev = CreateFrame("Frame")
local EVENTS = { "ACTIONBAR_SLOT_CHANGED", "ACTIONBAR_PAGE_CHANGED", "UPDATE_BONUS_ACTIONBAR",
                 "ACTIONBAR_UPDATE_COOLDOWN", "ACTIONBAR_UPDATE_USABLE", "ACTIONBAR_UPDATE_STATE",
                 "PLAYER_TARGET_CHANGED", "BAG_UPDATE", "UNIT_INVENTORY_CHANGED", "PLAYER_ENTERING_WORLD",
                 "START_AUTOREPEAT_SPELL", "STOP_AUTOREPEAT_SPELL", "PLAYER_ENTER_COMBAT",
                 "PLAYER_LEAVE_COMBAT", "UPDATE_SHAPESHIFT_FORMS", "PLAYER_AURAS_CHANGED" }
for k = 1, table.getn(EVENTS) do ev:RegisterEvent(EVENTS[k]) end
ev:SetScript("OnEvent", function()
  if OWN and event == "ACTIONBAR_SLOT_CHANGED" and arg1 then SaveSlot(arg1) end
  if not bar then return end
  if event == "ACTIONBAR_UPDATE_STATE" or event == "START_AUTOREPEAT_SPELL" or event == "STOP_AUTOREPEAT_SPELL"
      or event == "PLAYER_ENTER_COMBAT" or event == "PLAYER_LEAVE_COMBAT" then
    for _, btn in pairs(slots) do Bar.UpdateState(btn) end
  elseif event == "ACTIONBAR_UPDATE_COOLDOWN" then
    for _, btn in pairs(slots) do UpdateCooldown(btn) end
  else
    Bar.UpdateAll()
  end
end)

-- Range / usability poll.
local acc = 0
local poll = CreateFrame("Frame")
poll:SetScript("OnUpdate", function()
  acc = acc + arg1
  if acc < 0.2 or not bar or not bar:IsVisible() then return end
  acc = 0
  for _, btn in pairs(slots) do
    if btn.action and HasAction(btn.action) and WP.RingSlotKey() ~= btn.key then Bar.UpdateUsable(btn) end
  end
end)

---------------------------------------------------------------------------
-- Utility ring: hold the button on its bar slot, point the right stick at a wedge
-- (benilla-wowpad reports which, RING_DIR_n), let go to use it. The 8 wedges are action slots
-- (WowPad's own 197-204), so dragging, icons and cooldowns work like any slot.
---------------------------------------------------------------------------
local RING_R, RING_WHEEL, RING_ICON_SCALE = 120, 400, 44 / 32
local R = {}
WP.Ring = R

table.insert(WP.setupHooks, function()
  local r = CreateFrame("Frame", "WowPadRing", UIParent)
  r:SetWidth(RING_WHEEL + 20)
  r:SetHeight(RING_WHEEL + 20)
  r:SetPoint("CENTER", UIParent, "CENTER", 0, 40)
  r:SetFrameStrata("DIALOG")
  r:Hide()
  local hub
  hub, R.Glow = WP.BuildWheelArt(r, RING_WHEEL)
  hub:SetPoint("CENTER", r, "CENTER", 0, 0)
  R.label = r:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
  R.label:SetPoint("CENTER", r, "CENTER", 0, 0)
  R.label:SetWidth(RING_R * 1.3)
  R.help = r:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  R.help:SetPoint("TOP", r, "BOTTOM", 0, -4)
  R.help:SetText("UTILITY RING - drag spells, items or macros onto the wedges; right-click clears")
  R.help:Hide()
  R.frame, R.wedges, R.cur = r, {}, 0
  WP.MakeMover(r, "ring", "Ring", { "CENTER", UIParent, "CENTER", 0, 40 }, RING_WHEEL * 0.42)
  WP.ApplyMoverPos(r)
  for d = 1, 8 do
    local a = math.rad((d - 1) * 45)   -- wedge 1 = up, clockwise
    local k = RING_ICON_SCALE
    local w = MakeSlot(r, 9, d, math.sin(a) * RING_R / k, math.cos(a) * RING_R / k, true)
    w:SetScale(k)
    R.wedges[d] = w
  end
  Bar.UpdateAll()
end)

-- Wedge highlight and its name in the middle.
function R.Highlight(d)
  d = tonumber(d) or 0
  R.cur = d
  if R.Glow then R.Glow(d > 0 and d or nil) end
  local w = R.wedges and R.wedges[d]
  local name
  if w and HasAction(w.action) then
    name = GetActionText(w.action)
    if not name then
      WowPadRingScanTooltip = WowPadRingScanTooltip or CreateFrame("GameTooltip", "WowPadRingScanTooltip", UIParent, "GameTooltipTemplate")
      WowPadRingScanTooltip:SetOwner(UIParent, "ANCHOR_NONE")
      WowPadRingScanTooltip:SetAction(w.action)
      local fs = getglobal("WowPadRingScanTooltipTextLeft1")
      name = fs and fs:GetText()
      WowPadRingScanTooltip:Hide()
    end
  end
  if R.label then R.label:SetText(name or "") end
end

-- The ring's button: down shows the ring, up uses the wedge picked.
function R.Key(down)
  if not R.frame then return end
  if down then
    Bar.UpdateAll()
    R.Highlight(0)
    R.frame:Show()
    return
  end
  local d = R.cur or 0
  if not Bar.editing then R.frame:Hide() end
  R.Highlight(0)
  local w = R.wedges[d]
  if w and HasAction(w.action) then
    UseAction(w.action, 0)
    Bar.Press(w)
  end
end

-- Edit mode shows the ring too (when one is set up), for filling its wedges.
function R.SetEditing(on)
  if not R.frame then return end
  local show = on and WP.RingSlotKey() ~= nil
  Shown(R.frame, show)
  Shown(R.help, show)
  Shown(R.frame.mover, show)
  R.Highlight(0)
end
