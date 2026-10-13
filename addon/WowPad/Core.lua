-- Core.lua - signal handling, action-set switching, controller/desktop mode, mouselook,
-- open-window detection, events and the /wp slash command.
--
-- How it fits together on benilla:
--  * benilla-wowpad (the Rust side, WowPad's DLL in-process) runs a WOWPAD_<SIGNAL> binding
--    command for each signal (Bindings.xml), down and up, so WowPad_Signal sees `keystate` as a
--    key's binding would and a cast from it is a hardware event.
--  * 1.12 has no secure code and no combat lockdown, so what the 3.3.5 secure header did (point
--    the 8 slot keys at the held set, or at menu navigation while a window is open) is a plain
--    dispatch here: WowPad_Signal reads the mode, the triggers and the context and acts.
--  * Every frame the Rust side asks WowPad_Frame() for camera look, the menu context, aiming,
--    the options that tune it, and where to put the pointer when navigation moved it.

local WP = WowPad
WP.mode, WP.set, WP.pointer = "desktop", -1, false
WP.lt, WP.rt = false, false
WP.setupHooks = WP.setupHooks or {}
WP.overlays = {}     -- our own windows (radial, target menu): count as open windows
WP.crosshairFrac = 95 / 1080

local function Print(msg) DEFAULT_CHAT_FRAME:AddMessage("|cff33ff99WowPad|r: " .. tostring(msg)) end
WP.Print = Print

local function InCombat() return UnitAffectingCombat("player") end
WP.InCombat = InCombat

-- 1.12 has no InCombatLockdown; the 3.3.5 code's "not in combat" guards were for secure frames
-- only, so the port keeps the ones that change what the player sees mid-fight.

---------------------------------------------------------------------------
-- Open-window detection (drives mouselook and the menu context)
---------------------------------------------------------------------------
WP.WINDOWS = {
  "MerchantFrame", "LootFrame", "QuestFrame", "GossipFrame", "ClassTrainerFrame", "TaxiFrame",
  "BankFrame", "MailFrame", "OpenMailFrame", "AuctionFrame", "TradeFrame", "CharacterFrame",
  "SpellBookFrame", "TalentFrame", "QuestLogFrame", "WorldMapFrame", "FriendsFrame",
  "GameMenuFrame", "OptionsFrame", "SoundOptionsFrame", "UIOptionsFrame", "KeyBindingFrame",
  "MacroFrame", "PetStableFrame", "TradeSkillFrame", "CraftFrame", "InspectFrame",
  "ItemTextFrame", "GuildRegistrarFrame", "PetitionFrame", "TabardFrame", "HelpFrame",
  "DressUpFrame", "BattlefieldFrame", "PetPaperDollFrame", "AddonList", "ChatConfigFrame",
  "StaticPopup1", "StaticPopup2", "StaticPopup3", "StaticPopup4", "DropDownList1",
  "ColorPickerFrame", "BenillaOptionsFrame", "WowPadOptionsFrame",
}
for i = 1, 12 do table.insert(WP.WINDOWS, "ContainerFrame" .. i) end

-- Pop-ups that take menu navigation when they appear: group loot rolls.
function WP.PopupRoots()
  local list = {}
  for i = 1, 4 do
    local f = getglobal("GroupLootFrame" .. i)
    if f and f:IsVisible() then table.insert(list, f) end
  end
  return list
end

-- The open windows as a set of frames, and whether there is any.
function WP.OpenWindows()
  local open, any = {}, false
  for i = 1, table.getn(WP.WINDOWS) do
    local f = getglobal(WP.WINDOWS[i])
    if f and f.IsVisible and f:IsVisible() then open[f] = true; any = true end
  end
  for i = 1, table.getn(UISpecialFrames) do
    local f = getglobal(UISpecialFrames[i])
    if f and f.IsVisible and f:IsVisible() then open[f] = true; any = true end
  end
  for i = 1, table.getn(WP.overlays) do
    local o = WP.overlays[i]
    if o:IsVisible() then open[o] = true; any = true end
  end
  -- Out of combat only, as on 3.3.5: a roll popup mid-fight must not take the camera away.
  if not InCombat() then
    local roots = WP.PopupRoots()
    for i = 1, table.getn(roots) do open[roots[i]] = true; any = true end
  end
  return open, any
end

local function AnyWindowOpen()
  if WP.Bar and WP.Bar.editing then return true end
  local _, any = WP.OpenWindows()
  if any then return true end
  if ChatFrameEditBox and ChatFrameEditBox:IsVisible() then return true end
  if CursorHasItem() or CursorHasSpell() then return true end -- holding an item or spell
  return false
end
WP.AnyWindowOpen = AnyWindowOpen

-- The menu context: a window open (or pointer mode), and not in a fight (3.3.5's windows left
-- your controls alone in combat; so do these).
local function MenuContext()
  if WP.pointer then return true end
  return AnyWindowOpen() and not InCombat()
end
WP.MenuContext = MenuContext

---------------------------------------------------------------------------
-- Menu navigation: the D-pad / right stick pick a button (gold box); A clicks it and X
-- right-clicks it (benilla-wowpad presses the mouse there), B backs out. LB / RB switch windows;
-- up / down at a list's edge scrolls it. Also the hint line, the blue focus box and the memory.
---------------------------------------------------------------------------
local Nav = { roots = {}, nodes = {}, nodeSet = {}, scrolls = {}, memory = {} }
WP.Nav = Nav

local function IsFrame(f)
  return f ~= nil and f.IsVisible ~= nil and type(f.IsVisible) == "function"
end

local function Inside(f, open)
  local depth = 0
  while f and depth < 14 do
    if open[f] then return true end
    f = f:GetParent()
    depth = depth + 1
  end
  return false
end

-- A frame's centre in absolute units (UI units times its effective scale; the screen is 768 high).
local function Centre(f)
  local l, b = f:GetLeft(), f:GetBottom()
  if not l or not b then return nil end
  local s = f:GetEffectiveScale()
  return (l + f:GetWidth() / 2) * s, (b + f:GetHeight() / 2) * s
end
WP.Centre = Centre

local function IsBags(root)
  local n = root and root:GetName()
  return n ~= nil and string.find(n, "^ContainerFrame") ~= nil
end

local function Rect(f)
  local l, b = f:GetLeft(), f:GetBottom()
  if not l or not b then return nil end
  local s = f:GetEffectiveScale()
  return l * s, b * s, (l + f:GetWidth()) * s, (b + f:GetHeight()) * s
end

local function CenterIn(n, sf)
  local l, b = n:GetLeft(), n:GetBottom()
  local L, B, R, T = Rect(sf)
  if not l or not b or not L then return false end
  local s = n:GetEffectiveScale()
  local x, y = (l + n:GetWidth() / 2) * s, (b + n:GetHeight() / 2) * s
  return x >= L - 2 and x <= R + 2 and y >= B - 2 and y <= T + 2
end

local function AddRoot(roots, seen, f)
  if IsFrame(f) and not seen[f] and f:IsVisible() then
    seen[f] = true
    roots[table.getn(roots) + 1] = f
  end
end

local function CollectRoots()
  local roots, seen = {}, {}
  for i = 1, table.getn(WP.overlays) do AddRoot(roots, seen, WP.overlays[i]) end
  for level = (UIDROPDOWNMENU_MAXLEVELS or 2), 1, -1 do
    AddRoot(roots, seen, getglobal("DropDownList" .. level))
  end
  for i = 1, (STATICPOPUP_NUMDIALOGS or 4) do AddRoot(roots, seen, getglobal("StaticPopup" .. i)) end
  local pops = WP.PopupRoots()
  for i = 1, table.getn(pops) do AddRoot(roots, seen, pops[i]) end
  for i = 1, table.getn(WP.WINDOWS) do AddRoot(roots, seen, getglobal(WP.WINDOWS[i])) end
  for i = 1, table.getn(UISpecialFrames) do AddRoot(roots, seen, getglobal(UISpecialFrames[i])) end
  return roots
end

-- The frames a root stands for (all open bags for the bags root).
local function RootFrames(root)
  if not IsBags(root) then return { root } end
  local list = {}
  for i = 1, (NUM_CONTAINER_FRAMES or 13) do
    local f = getglobal("ContainerFrame" .. i)
    if f and f:IsVisible() then list[table.getn(list) + 1] = f end
  end
  return list
end

local NODE_TYPES = { Button = true, CheckButton = true, EditBox = true }

-- Never stops: the money displays (their gold / silver / copper buttons only pick up coins).
local function Skipped(f)
  local n = f:GetName()
  if not n then return false end
  return string.find(n, "MoneyFrameGoldButton$") ~= nil
      or string.find(n, "MoneyFrameSilverButton$") ~= nil
      or string.find(n, "MoneyFrameCopperButton$") ~= nil
end

local function Usable(f)
  local t = f:GetObjectType()
  if not NODE_TYPES[t] then return false end
  if f.IsMouseEnabled and not f:IsMouseEnabled() then return false end
  if Skipped(f) then return false end
  if t ~= "EditBox" and f.IsEnabled and not f:IsEnabled() then return false end
  local w, h = f:GetWidth(), f:GetHeight()
  return w ~= nil and h ~= nil and w >= 6 and h >= 6
end

-- Nodes, plus the visible scroll frames (lists) found on the way. Nodes inside a real scroll
-- frame that are scrolled out of view are skipped.
local function Collect(frame, out, depth, scrolls, clip)
  if depth > 14 then return end
  local kids = { frame:GetChildren() }
  for i = 1, table.getn(kids) do
    local c = kids[i]
    if c:IsVisible() then
      if Usable(c) and not (clip and not CenterIn(c, clip)) then out[table.getn(out) + 1] = c end
      local ot = c.GetObjectType and c:GetObjectType()
      local isScroll = ot == "ScrollFrame"
      local isBar = ot == "Slider"
      if isScroll and scrolls then scrolls[table.getn(scrolls) + 1] = c end
      local clip2
      if isScroll then clip2 = c elseif isBar then clip2 = nil else clip2 = clip end
      Collect(c, out, depth + 1, scrolls, clip2)
    end
  end
end

-- Top-left-most node: highest first, then leftmost.
local function DefaultNode(nodes)
  local best, bx, by
  for i = 1, table.getn(nodes) do
    local n = nodes[i]
    local x, y = Centre(n)
    if x and (not best or y > by + 4 or (math.abs(y - by) <= 4 and x < bx)) then best, bx, by = n, x, y end
  end
  return best
end

-- Nearest node from cur in direction (dx, dy), favouring nodes straight ahead.
local function Pick(cur, nodes, dx, dy)
  local cx, cy = Centre(cur)
  if not cx then return nil end
  local best, bestScore
  for i = 1, table.getn(nodes) do
    local n = nodes[i]
    if n ~= cur then
      local x, y = Centre(n)
      if x then
        local vx, vy = x - cx, y - cy
        local primary = vx * dx + vy * dy
        if primary > 2 then
          local secondary = math.abs(vx * dy - vy * dx)
          local score = primary + secondary * 2.5
          if not bestScore or score < bestScore then best, bestScore = n, score end
        end
      end
    end
  end
  return best
end

local ROUNDED = "Interface\\Tooltips\\UI-Tooltip-Border"
local hl = CreateFrame("Frame", "WowPadNavHighlight", UIParent)
hl:SetFrameStrata("FULLSCREEN_DIALOG")
hl:SetBackdrop({ edgeFile = ROUNDED, edgeSize = 16 })
hl:SetBackdropBorderColor(1, 0.82, 0.1, 1)
hl:Hide()

local navFocus = CreateFrame("Frame", "WowPadNavFocus", UIParent)
navFocus:SetFrameStrata("FULLSCREEN_DIALOG")
navFocus:SetBackdrop({ edgeFile = ROUNDED, edgeSize = 20 })
navFocus:SetBackdropBorderColor(0.35, 0.7, 1, 0.7)
navFocus:Hide()

local hints = CreateFrame("Frame", "WowPadNavHints", UIParent)
hints:SetFrameStrata("FULLSCREEN_DIALOG")
hints:SetHeight(28)
hints:SetClampedToScreen(true)
hints:SetBackdrop({ bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
                    edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
                    tile = true, tileSize = 16, edgeSize = 12,
                    insets = { left = 3, right = 3, top = 3, bottom = 3 } })
hints:SetBackdropColor(0, 0, 0, 0.85)
hints:Hide()
local HINT_PAD, HINT_GAP = 10, 4
local hintLine = WP.NewKeyLine(hints, "GameFontHighlightSmall", 18)
hintLine:SetPoint("LEFT", hints, "LEFT", HINT_PAD, 0)
local function LayoutHints(parts) hints:SetWidth(hintLine:SetParts(parts, HINT_GAP) + 2 * HINT_PAD) end

local FRIENDLY = {
  MerchantFrame = "Vendor", CharacterFrame = "Character", SpellBookFrame = "Spellbook",
  TalentFrame = "Talents", QuestLogFrame = "Quest Log", WorldMapFrame = "Map",
  FriendsFrame = "Social", GossipFrame = "Gossip", QuestFrame = "Quest", LootFrame = "Loot",
  BankFrame = "Bank", MailFrame = "Mail", TradeFrame = "Trade", AuctionFrame = "Auction House",
  ClassTrainerFrame = "Trainer", TaxiFrame = "Flight Map", GameMenuFrame = "Game Menu",
  DressUpFrame = "Preview", PetStableFrame = "Stable", InspectFrame = "Inspect",
  MacroFrame = "Macros", WowPadOptionsFrame = "Options",
}

local function H(key, text) return { key = key, text = text } end

function Nav.UpdateHints()
  local root = Nav.root
  if not root then navFocus:Hide(); hints:Hide(); return end
  if root == WP.Radial then navFocus:Hide(); hints:Hide(); return end
  local parts
  if root == MerchantFrame then
    parts = { H("A", "Select"), H("X", "Buy"), H("B", "Close") }
  elseif IsBags(root) then
    local vendorOpen = MerchantFrame and MerchantFrame:IsShown()
    parts = { H("A", "Select"), H("X", vendorOpen and "Sell" or "Use"), H("L3", "Item actions"),
              H("B", "Close") }
  elseif root == WorldMapFrame then
    local onPin = Nav.byDpad and Nav.cur and Nav.cur ~= WorldMapButton
    parts = { H("A", onPin and "Select" or "Zoom In"), H("X", onPin and "Right-click" or "Zoom Out"),
              H("D-pad", "Pins"), H("B", (GetCurrentMapContinent() or 0) > 0 and "Back" or "Close") }
  elseif root == QuestLogFrame then
    parts = { H("A", "Select"), H("X", "Track"), H("B", "Close") }
  elseif string.find(root:GetName() or "", "^GroupLootFrame") then
    parts = { H("A", "Roll"), H("B", "Pass") }
  else
    parts = { H("A", "Select"), H("B", "Close") }
  end
  if Nav.HasTabs(root) then
    parts[table.getn(parts) + 1] = H("LB/RB", "Tabs")
    if table.getn(Nav.roots) > 1 then parts[table.getn(parts) + 1] = H("LT/RT", "Swap window") end
  elseif table.getn(Nav.roots) > 1 then
    parts[table.getn(parts) + 1] = H("LB/RB", "Swap window")
  end
  LayoutHints(parts)

  -- Bounding box of the focused window (all bags together), in UIParent units.
  local uiScale = UIParent:GetEffectiveScale()
  local L, B, R, T
  local frames = RootFrames(root)
  for i = 1, table.getn(frames) do
    local l, b = frames[i]:GetLeft(), frames[i]:GetBottom()
    if l and b then
      local w, h = frames[i]:GetWidth(), frames[i]:GetHeight()
      local k = frames[i]:GetEffectiveScale() / uiScale
      l, b, w, h = l * k, b * k, w * k, h * k
      L = L and math.min(L, l) or l
      B = B and math.min(B, b) or b
      R = R and math.max(R, l + w) or l + w
      T = T and math.max(T, b + h) or b + h
    end
  end
  if not L then navFocus:Hide(); hints:Hide(); return end
  hints:ClearAllPoints()
  hints:SetPoint("TOP", UIParent, "BOTTOMLEFT", (L + R) / 2, B - 4)
  hints:Show()
  if table.getn(Nav.roots) > 1 then
    navFocus:ClearAllPoints()
    navFocus:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", L - 6, T + 6)
    navFocus:SetPoint("BOTTOMRIGHT", UIParent, "BOTTOMLEFT", R + 6, B - 6)
    navFocus:Show()
  else
    navFocus:Hide()
  end
end

function Nav.Targets()
  local open = WP.OpenWindows()
  local list = {}
  local f = EnumerateFrames()
  while f do
    local kind = f:GetObjectType()
    if (kind == "Button" or kind == "CheckButton") and f:IsVisible() and Inside(f, open) then
      local w, h = f:GetWidth(), f:GetHeight()
      local x, y = Centre(f)
      if x and w > 4 and h > 4 then table.insert(list, { x = x, y = y, frame = f }) end
    end
    f = EnumerateFrames(f)
  end
  return list
end

-- Put the pointer at absolute units (GetCursorPosition's).
function Nav.WarpAbs(x, y)
  local s = UIParent:GetEffectiveScale()
  local w, h = GetScreenWidth() * s, GetScreenHeight() * s
  if w > 0 and h > 0 then WP.warpX, WP.warpY = x / w, y / h end
  Nav.selectedAt = GetTime()
end

local function Box(f)
  hl:ClearAllPoints()
  hl:SetPoint("TOPLEFT", f, "TOPLEFT", -6, 6)
  hl:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", 6, -6)
end

-- Show the gold box on a node without moving the pointer (the tick's memory / follow path).
function Nav.Highlight(f)
  if f == Nav.cur then
    if f and not WP.OwnMenu() then Box(f) end
    return
  end
  Nav.cur = f
  if f and Nav.root then
    local x, y = Centre(f)
    Nav.memory[Nav.root] = { node = f, x = x, y = y }
  end
  if f and not WP.OwnMenu() then Box(f); hl:Show() else hl:Hide() end
end

-- Select a node and park the pointer on it: A / X then click there.
function Nav.Select(f)
  if f then
    local x, y = Centre(f)
    if x then Nav.WarpAbs(x, y) end
  end
  Nav.Highlight(f)
end

-- Our own menus (the wheel, the target menu): A presses the selected button here instead of a
-- mouse click, so it works wherever the pointer is.
function WP.OwnMenu()
  if WP.Radial and WP.Radial:IsVisible() then return WP.Radial end
  if WP.UnitMenu and WP.UnitMenu:IsVisible() then return WP.UnitMenu end
  return nil
end

function Nav.Press()
  local menu, f = WP.OwnMenu(), Nav.cur
  if menu and f and f:IsVisible() and f:GetParent() == menu then f:Click() end
end

-- The same on the next frame, for a window that only just opened (its layout is not in yet).
local pending
local selDriver = CreateFrame("Frame")
selDriver:Hide()
selDriver:SetScript("OnUpdate", function()
  this:Hide()
  if pending and pending:IsVisible() then Nav.Select(pending) end
  pending = nil
end)
function Nav.SelectSoon(f)
  pending = f
  selDriver:Show()
end

-- Kept for our own menus (the wheel and the target menu): the D-pad walks their buttons.
local function MoveTargets(dir)
  local x, y = GetCursorPosition()
  local best, bestScore
  local targets = Nav.Targets()
  for i = 1, table.getn(targets) do
    local t = targets[i]
    if t.frame ~= Nav.cur then
      local dx, dy = t.x - x, t.y - y
      local along, across
      if dir == "DPAD_UP" then along, across = dy, dx
      elseif dir == "DPAD_DOWN" then along, across = -dy, dx
      elseif dir == "DPAD_LEFT" then along, across = -dx, dy
      else along, across = dx, dy end
      if along > 4 then
        local score = along + 2 * math.abs(across)
        if not bestScore or score < bestScore then best, bestScore = t, score end
      end
    end
  end
  if best then Nav.Select(best.frame) end
end

-- List scrolling: D-pad up / down at the edge of a list scrolls one row.
local function ScrollBarOf(sf)
  local n = sf:GetName()
  local bar = (n and getglobal(n .. "ScrollBar")) or sf.ScrollBar
  if not bar then
    local kids = { sf:GetChildren() }
    for i = 1, table.getn(kids) do
      local c = kids[i]
      if c.GetObjectType and c:GetObjectType() == "Slider" then bar = c; break end
    end
  end
  if bar and bar:IsVisible() and bar.GetValue then return bar end
end

-- The scroll frame the selected node sits in, if the D-pad would leave it.
local function ListOf(cur, nxt)
  for i = 1, table.getn(Nav.scrolls) do
    local sf = Nav.scrolls[i]
    if CenterIn(cur, sf) and not (nxt and CenterIn(nxt, sf)) then
      local bar = ScrollBarOf(sf)
      if bar then return bar, sf end
    end
  end
  return nil
end

local function TryScroll(cur, nxt, dy)
  if dy == 0 or not Nav.scrolls then return false end
  local bar, sf = ListOf(cur, nxt)
  if not bar then return false end
  local lo, hi = bar:GetMinMaxValues()
  local v = bar:GetValue()
  local step = math.max(cur:GetHeight() or 16, 8)
  local nv = v - dy * step
  nv = math.max(lo, math.min(hi, nv))
  if math.abs(nv - v) <= 0.5 then return false end
  local x, y = Centre(cur)
  bar:SetValue(nv)
  Nav.Refresh()
  local best, bd
  for i = 1, table.getn(Nav.nodes) do
    local n = Nav.nodes[i]
    local nx, ny = Centre(n)
    if nx and CenterIn(n, sf) then
      local d = (nx - x) ^ 2 + (ny - y) ^ 2
      if not bd or d < bd then best, bd = n, d end
    end
  end
  if best then
    if best == Nav.cur then Nav.cur = nil end
    Nav.Select(best)
  end
  return true
end

local DIRS = { DPAD_UP = { 0, 1 }, DPAD_DOWN = { 0, -1 }, DPAD_LEFT = { -1, 0 }, DPAD_RIGHT = { 1, 0 } }

-- The nav layer runs while a window is open in controller mode, out of combat, with no trigger
-- held and not on one of our own menus.
function Nav.Active()
  return WP.mode == "controller" and WP.set <= 0 and AnyWindowOpen() and not InCombat()
      and not WP.OwnMenu()
end

function Nav.Move(dir)
  local d = DIRS[dir]
  if not d then return end
  if WP.OwnMenu() then MoveTargets(dir); return end
  if not Nav.Active() then return end
  Nav.Refresh()
  local nxt = Nav.cur and Pick(Nav.cur, Nav.nodes, d[1], d[2])
  if Nav.cur and TryScroll(Nav.cur, nxt, d[2]) then Nav.byDpad = true return end
  if nxt then Nav.Select(nxt); Nav.byDpad = true end
end

-- LB / RB: the next / previous open window.
function Nav.CycleRoot(step)
  Nav.Refresh()
  local n = table.getn(Nav.roots)
  if n < 2 then return end
  local idx = 1
  for i = 1, n do if Nav.roots[i] == Nav.root then idx = i end end
  idx = math.mod(idx - 1 + step + n, n) + 1
  Nav.root = Nav.roots[idx]
  Nav.cur = nil
  if hl:IsShown() then hl:Hide() end
  Nav.byDpad = true
  Nav.Refresh()
end

-- Tab buttons of a window (Character, Social, Spellbook, Talents, Auction House...), left to
-- right; the spellbook's school tabs down its side come first. Hidden tabs are left out.
local SIDE_TABS = { SpellBookFrame = "SpellBookSkillLineTab" }
function Nav.Tabs(root)
  local name = root and root.GetName and root:GetName()
  local list = {}
  if not name then return list end
  local side = SIDE_TABS[name]
  if side then
    for i = 1, 12 do
      local t = getglobal(side .. i)
      if not IsFrame(t) then break end
      if t:IsVisible() then list[table.getn(list) + 1] = t end
    end
    if table.getn(list) > 1 then
      table.sort(list, function(a, b) return (a:GetTop() or 0) > (b:GetTop() or 0) end)
      return list
    end
    list = {}
  end
  local forms = { "Tab", "TabButton" }
  for f = 1, 2 do
    for i = 1, 12 do
      local t = getglobal(name .. forms[f] .. i)
      if not IsFrame(t) then break end
      if t:GetObjectType() == "Button" and t:IsVisible() then list[table.getn(list) + 1] = t end
    end
    if table.getn(list) > 0 then break end
  end
  table.sort(list, function(a, b) return (a:GetLeft() or 0) < (b:GetLeft() or 0) end)
  return list
end

-- LB / RB in a window with tabs: open the next tab (the open one is the window's selectedTab,
-- else the checked side tab, else the disabled one), skipping tabs that can't be clicked.
-- Returns false when the window has no tabs, so the bumper swaps window instead.
function Nav.NextTab(step)
  local root = Nav.root
  local tabs = Nav.Tabs(root)
  local n = table.getn(tabs)
  if n < 2 then return false end
  local cur
  if root.selectedTab then
    local want = (root:GetName() or "") .. "Tab" .. root.selectedTab
    for i = 1, n do if tabs[i]:GetName() == want then cur = i end end
  end
  if not cur then
    for i = 1, n do if tabs[i].GetChecked and tabs[i]:GetChecked() then cur = i; break end end
  end
  if not cur then
    for i = 1, n do if not tabs[i]:IsEnabled() then cur = i; break end end
  end
  if not cur then return false end
  local i = cur
  for k = 1, n do
    i = math.mod(i - 1 + step + n, n) + 1
    if i == cur then return true end
    if tabs[i]:IsEnabled() then
      tabs[i]:Click()
      Nav.cur = nil      -- the new tab starts on its default button
      if hl:IsShown() then hl:Hide() end
      Nav.byDpad = true
      Nav.Refresh()
      return true
    end
  end
  return true
end

-- Whether a window has tabs for the bumpers to page.
function Nav.HasTabs(root) return table.getn(Nav.Tabs(root)) > 1 end

-- Quest log, X: track / untrack the quest on the selected row (or, off the list, the quest
-- shown on the right), as shift-clicking its title does.
function Nav.TrackQuest(n)
  local idx
  local nm = n and n.GetName and n:GetName() or ""
  if n and n.GetID and string.find(nm, "^QuestLogTitle%d") then idx = n:GetID() end
  if not idx or idx < 1 then idx = GetQuestLogSelection() end
  if not idx or idx < 1 then return end
  local title, _, _, isHeader = GetQuestLogTitle(idx)
  if not title or isHeader then return end
  if IsQuestWatched(idx) then
    RemoveQuestWatch(idx)
  else
    local max = MAX_WATCHABLE_QUESTS or 5
    if GetNumQuestWatches() >= max then
      if UIErrorsFrame and QUEST_WATCH_TOO_MANY then
        UIErrorsFrame:AddMessage(string.format(QUEST_WATCH_TOO_MANY, max), 1, 0.1, 0.1, 1)
      end
      return
    end
    AddQuestWatch(idx)
  end
  if QuestLog_SetSelection then QuestLog_SetSelection(idx) end
  if QuestWatch_Update then QuestWatch_Update() end
  if QuestLog_Update then QuestLog_Update() end
end

-- B on the focused window: the button that closes it (its close button, Cancel, the game menu's
-- Return to Game, a roll's Pass), or nil.
local function CloseButtonOf(root)
  local name = root and root:GetName()
  if not name then return nil end
  if string.find(name, "^GroupLootFrame%d") then return getglobal(name .. "PassButton") end
  if name == "GameMenuFrame" then return getglobal("GameMenuButtonContinue") end
  local function Shown(b) return IsFrame(b) and b:IsVisible() and b end
  local b = Shown(getglobal(name .. "CloseButton"))
  if b then return b end
  local kids = { root:GetChildren() }
  for i = 1, table.getn(kids) do
    local n = kids[i]:GetName()
    if n and string.find(n, "CloseButton$") and kids[i]:IsVisible() then return kids[i] end
  end
  b = Shown(getglobal(name .. "Cancel")) or Shown(getglobal(name .. "CancelButton"))
  if b then return b end
  for i = 1, table.getn(kids) do
    local n = kids[i]:GetName()
    if n and (string.find(n, "Cancel$") or string.find(n, "CancelButton$")) and kids[i]:IsVisible()
        and kids[i]:GetObjectType() == "Button" then return kids[i] end
  end
  return nil
end

-- Collect the roots, nodes and lists; keep the selection and refresh the boxes and hints.
function Nav.Refresh()
  Nav.roots = CollectRoots()
  local open = {}
  for i = 1, table.getn(Nav.roots) do open[Nav.roots[i]] = true end
  for r in pairs(Nav.memory) do if not r:IsVisible() then Nav.memory[r] = nil end end
  local top = Nav.roots[1]
  local stillOpen = false
  for i = 1, table.getn(Nav.roots) do if Nav.roots[i] == Nav.root then stillOpen = true end end
  if top ~= Nav.lastTop or not stillOpen then
    -- A new window on top grabs focus, starting on its default button, not wherever the hidden
    -- pointer happens to be (the crosshair spot).
    Nav.root = top
    Nav.byDpad = true
    if hl:IsShown() then hl:Hide() end
    Nav.cur = nil
    Nav.lastMX, Nav.lastMY = GetCursorPosition()
  end
  Nav.lastTop = top

  local nodes, scrolls = {}, {}
  if Nav.root then
    local frames = RootFrames(Nav.root)
    for i = 1, table.getn(frames) do Collect(frames[i], nodes, 0, scrolls) end
  end
  Nav.nodes, Nav.nodeSet, Nav.scrolls = nodes, {}, scrolls
  for i = 1, table.getn(nodes) do Nav.nodeSet[nodes[i]] = true end

  -- Follow the pointer when it moves onto a node.
  local mx, my = GetCursorPosition()
  if math.abs(mx - (Nav.lastMX or mx)) + math.abs(my - (Nav.lastMY or my)) > 2 then
    Nav.byDpad = false
    local mf = GetMouseFocus()
    if mf and Nav.nodeSet[mf] then Nav.Highlight(mf) end
  end
  Nav.lastMX, Nav.lastMY = mx, my

  if not Nav.cur or not Nav.nodeSet[Nav.cur] then
    -- Back to where this window was: the same node, else the nearest one.
    local mem = Nav.root and Nav.memory[Nav.root]
    if mem then
      local pick = Nav.nodeSet[mem.node] and mem.node
      if not pick and mem.x then
        local bd
        for i = 1, table.getn(nodes) do
          local x, y = Centre(nodes[i])
          if x then
            local dd = (x - mem.x) ^ 2 + (y - mem.y) ^ 2
            if not bd or dd < bd then pick, bd = nodes[i], dd end
          end
        end
      end
      if pick then Nav.Select(pick); Nav.UpdateHints(); return end
    end
    local pref
    local rn = Nav.root and Nav.root:GetName()
    if rn == "WowPadItemActions" then pref = { getglobal("WowPadItemActionsCancel") }
    elseif rn == "WowPadOptionsFrame" then pref = { getglobal("WowPadOptionsDone") }
    elseif rn == "WowPadKeyboard" then pref = { WP.Keyboard.firstKey }
    elseif rn == "WowPadFirstTime" then pref = { getglobal("WowPadFirstTimeNext") }
    elseif rn == "WowPadInfo" then pref = { getglobal("WowPadInfoCloseButton") }
    elseif rn and string.find(rn, "^GroupLootFrame%d") then
      -- Need if allowed, else Greed (disabled buttons aren't nodes).
      pref = { getglobal(rn .. "RollButton"), getglobal(rn .. "GreedButton") }
    elseif rn and string.find(rn, "^StaticPopup%d$") and Nav.root.which == "WOWPAD_DESTROY" then
      pref = { getglobal(rn .. "Button2") }   -- Cancel, so a double press never destroys
    end
    local pick
    for i = 1, table.getn(pref or {}) do
      local p = pref[i]
      if p and Nav.nodeSet[p] then pick = p; break end
    end
    Nav.Select(pick or DefaultNode(nodes))
  end
  Nav.UpdateHints()
end

-- Ten times a second: refresh while a window is open, else clear the boxes and hints.
local navElapsed = 0
local navFrame = CreateFrame("Frame")
navFrame:SetScript("OnUpdate", function()
  navElapsed = navElapsed + arg1
  if navElapsed < 0.1 then return end
  navElapsed = 0
  if Nav.Active() then
    Nav.Refresh()
  else
    for r in pairs(Nav.memory) do if not r:IsVisible() then Nav.memory[r] = nil end end
    if hl:IsShown() then hl:Hide() end
    navFocus:Hide()
    hints:Hide()
    Nav.root = nil
    Nav.lastTop = nil
  end
end)

-- B: back out of the top window (a popup, a dropdown, then every window).
function Nav.Back()
  -- The keyboard: B deletes a letter (on an empty line it closes).
  if WP.Keyboard and WP.Keyboard:IsShown() then WP.Keyboard.Delete() return end
  if WP.Radial and WP.Radial:IsVisible() then WP.Radial:Hide() return end
  if WP.UnitMenu and WP.UnitMenu:IsVisible() then WP.UnitMenu:Hide() return end
  for k = 1, table.getn(WP.overlays) do
    local o = WP.overlays[k]
    if o:IsVisible() then o:Hide() return end
  end
  for i = 1, 4 do
    local p = getglobal("StaticPopup" .. i)
    if p and p:IsVisible() then
      local cancel = getglobal("StaticPopup" .. i .. "Button2")
      if cancel and cancel:IsVisible() then cancel:Click() else p:Hide() end
      return
    end
  end
  if DropDownList1 and DropDownList1:IsVisible() then CloseDropDownMenus() return end
  if WP.MapBack and WP.MapBack() then return end
  if CursorHasItem() or CursorHasSpell() then ClearCursor() return end
  if WP.Bar and WP.Bar.editing then WP.Bar.SetEditing(false) return end
  -- The focused window only, as on 3.3.5: its own close / cancel button, else hide it.
  local root = Nav.Active() and Nav.root
  if root and root:IsVisible() then
    if IsBags(root) then CloseAllBags() return end
    local b = CloseButtonOf(root)
    if b then b:Click() return end
    if root ~= WP.Radial and HideUIPanel then HideUIPanel(root) end
    if root:IsVisible() then root:Hide() end
    return
  end
  CloseMenus()
  CloseAllWindows()
end

---------------------------------------------------------------------------
-- What each slot does per set, in the world.
---------------------------------------------------------------------------
-- X with no trigger: interact went first (benilla-wowpad), then start attacking a hostile target.
local function StartAttack()
  if WowPadDB and WowPadDB.xAttack == false then return end
  if WP.autoAttacking then return end
  if UnitExists("target") and UnitCanAttack("player", "target") and not UnitIsDead("target") then
    AttackTarget()
  end
end

local function FixedSlot(i, down)
  if i == 5 then                                    -- A: jump
    if down then Jump() end
  elseif i == 6 then                                -- B: clear target
    if down then ClearTarget() end
  elseif i == 7 then                                -- X: (interact +) attack
    if down then StartAttack() end
  elseif i == 8 then                                -- Y: target menu
    if down and WP.UnitMenu then WP.UnitMenu.Open() end
  end
  if down and WP.Bar then WP.Bar.PressFixed(i) end
end

local function SlotSignal(i, down)
  local set = WP.set < 0 and 0 or WP.set
  -- The utility ring's button: down shows the ring, up fires the wedge picked.
  if WowPadDB and tonumber(WowPadDB.wpRingSlot) == set * 10 + i then
    if WP.Ring then WP.Ring.Key(down) end
    return
  end
  if set == 0 and MenuContext() then
    if i == 8 then
      -- The keyboard: Y types a space.
      if WP.Keyboard and WP.Keyboard:IsShown() then
        if down then WP.Keyboard.Space() end
        return
      end
      -- Y: tap previews, hold compares (ItemActions.lua).
      if down then
        if Nav.CompareDown then Nav.CompareDown() end
      else
        if Nav.CompareUp then Nav.CompareUp() end
      end
      return
    end
    if not down then return end
    local sig = WP.SLOT_SIGNALS[i]
    if i <= 4 then Nav.Move(sig)
    elseif i == 5 and WP.OwnMenu() then Nav.Press()
    elseif i == 6 then Nav.Back()
    elseif i == 7 and Nav.Active() and Nav.root == QuestLogFrame then Nav.TrackQuest(Nav.cur) end
    -- Elsewhere A and X are mouse clicks, pressed by benilla-wowpad.
    return
  end
  if set == 0 and i >= 5 then FixedSlot(i, down) return end
  if WP.Bar then WP.Bar.Fire(set, i, down) end
end

---------------------------------------------------------------------------
-- Targeting: LB / RB, optionally swapped; healer mode cycles the party.
---------------------------------------------------------------------------
WP.partyIndex = 0
local function PartyUnit(i) if i == 0 then return "player" end return "party" .. i end
local function PartyStep(step)
  local i = WP.partyIndex
  if step == 0 then
    if i ~= 0 and not UnitExists("party" .. i) then i = 0 end
  else
    for n = 1, 5 do
      i = math.mod(i + step + 5, 5)
      if i == 0 or UnitExists("party" .. i) then break end
    end
  end
  WP.partyIndex = i
  TargetUnit(PartyUnit(i))
  if WP.PartyFlicked then WP.PartyFlicked() end
end

local function Bumper(which)
  if WP.RadialBumper and WP.RadialBumper(which) then return end
  if MenuContext() then
    -- The welcome window: LB / RB turn its pages.
    if WP.FirstTime and WP.FirstTime:IsShown() then
      WP.FirstTime.Page(which == "LB" and -1 or 1)
      return
    end
    -- The chat keyboard: LB / RB pick the channel.
    if WP.Keyboard and WP.Keyboard:IsShown() and not WP.Keyboard.IsField() then
      WP.Keyboard.Page(which == "LB" and -1 or 1)
      return
    end
    if WP.Nav then
      local step = which == "LB" and -1 or 1
      if not (Nav.Active() and Nav.NextTab(step)) then Nav.CycleRoot(step) end
    end
    return
  end
  local swap = WowPadDB and WowPadDB.swapBumpers == true
  local friendly = (which == "LB") ~= swap
  if friendly then
    if WowPadDB and WowPadDB.wpBumperFlick == true then PartyStep(0) else TargetNearestFriend() end
  else
    TargetNearestEnemy()
  end
end

local function Flick(which, dir)
  local swap = WowPadDB and WowPadDB.swapBumpers == true
  local friendly = (which == "LB") ~= swap
  if not friendly then return end
  PartyStep(dir == "DOWN" and 1 or -1)
end

---------------------------------------------------------------------------
-- LB+RB held: hint at the top centre that the right stick zooms.
---------------------------------------------------------------------------
local zoomHint = CreateFrame("Frame", "WowPadZoomHint", UIParent)
zoomHint:SetWidth(360)
zoomHint:SetHeight(30)
zoomHint:SetPoint("TOP", UIParent, "TOP", 0, -60)
zoomHint:SetFrameStrata("HIGH")
zoomHint:SetBackdrop({ bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
                       edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
                       tile = true, tileSize = 16, edgeSize = 12,
                       insets = { left = 3, right = 3, top = 3, bottom = 3 } })
zoomHint:SetBackdropColor(0, 0, 0, 0.8)
local zoomText = zoomHint:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
zoomText:SetPoint("CENTER", zoomHint, "CENTER", 0, 0)
zoomText:SetText("|cffffd100Right stick|r  up / down to zoom the camera")
zoomHint:Hide()

-- Hide "There is nothing to attack." (X = interact + attack fires it on anything not hostile).
do
  local orig = UIErrorsFrame.AddMessage
  UIErrorsFrame.AddMessage = function(self, msg, r, g, b, id, hold)
    if msg and (msg == "There is nothing to attack." or (ERR_NO_ATTACK_TARGET and msg == ERR_NO_ATTACK_TARGET)) then return end
    return orig(self, msg, r, g, b, id, hold)
  end
end

---------------------------------------------------------------------------
-- Mouselook: on in controller mode unless something needs the pointer. Also the crosshair peek.
---------------------------------------------------------------------------
local weStarted, mlElapsed = false, 0

-- Crosshair peek: what is under the pointer is ignored during camera look, so when the right
-- stick rests (CAM_IDLE) camera look pauses and the unit under the crosshair shows. CAM_ACTIVE
-- arrives before the stick moves again and turns camera look straight back on. /wp peek toggles.
WP.peeking = false
local function CameraWanted()
  return WP.mode == "controller" and not WP.pointer and not AnyWindowOpen()
end
WP.CameraWanted = CameraWanted

function WP.EndPeek()
  WP.peeking = false
end

-- Ground-targeted spells: while one waits for its location, a hint shows; A or the same button
-- places it at the crosshair (benilla-wowpad clicks there), B cancels.
local gtHint = CreateFrame("Frame", "WowPadGroundHint", UIParent)
gtHint:SetWidth(10)
gtHint:SetHeight(10)
gtHint:SetPoint("CENTER", UIParent, "CENTER", 0, -90)
gtHint:SetFrameStrata("HIGH")
gtHint:Hide()
local gtText = WP.NewKeyLine(gtHint, "GameFontHighlight", 20)
gtText:SetPoint("CENTER", gtHint, "CENTER", 0, 0)
gtText:SetParts({ { key = "A", text = "or same button: Place" }, { key = "B", text = "Cancel" } }, 14)

function WP.GroundTargetTick()
  local aiming = SpellIsTargeting()
  local t = aiming and CameraWanted() and true or false
  if t then
    WP.groundTargeting = true
    if not gtHint:IsShown() then
      gtHint:ClearAllPoints()
      if CastingBarFrame then gtHint:SetPoint("BOTTOM", CastingBarFrame, "TOP", 0, 12)
      else gtHint:SetPoint("CENTER", UIParent, "CENTER", 0, -90) end
      gtHint:Show()
    end
  elseif WP.groundTargeting then
    WP.groundTargeting = false
    gtHint:Hide()
  end
end

-- benilla-wowpad: a ground spell is being placed; camera look off so the click lands.
function WowPad_PlaceBegin()
  if IsMouselooking() then MouselookStop() end
  WP.peeking = true
end

local function CamIdle()
  local peek = (WowPadDB and WowPadDB.peek ~= false) or SpellIsTargeting()
  if peek and CameraWanted() and IsMouselooking() then
    WP.peeking = true
    MouselookStop()
  end
end

local function CamActive()
  if WP.peeking then
    WP.EndPeek()
    if CameraWanted() then MouselookStart(); weStarted = true end
  end
end

local mlFrame = CreateFrame("Frame")
mlFrame:SetScript("OnUpdate", function()
  mlElapsed = mlElapsed + arg1
  if mlElapsed < 0.05 then return end
  mlElapsed = 0
  if WP.peeking and not CameraWanted() then WP.EndPeek() end
  WP.GroundTargetTick()
  local want = CameraWanted() and not WP.peeking
  local looking = IsMouselooking()
  if want and not looking then
    MouselookStart(); weStarted = true
  elseif not want and looking and weStarted then
    MouselookStop(); weStarted = false
  elseif not looking then
    weStarted = false
  end
  local ctx = looking and "camera" or "pointer"
  if ctx ~= WP.context then WP.context = ctx; WP.UpdateStatus() end
end)

---------------------------------------------------------------------------
-- The signals
---------------------------------------------------------------------------
local function SetFromTriggers()
  local set = -1
  if WP.mode == "controller" then
    if WP.lt and WP.rt then set = 3 elseif WP.lt then set = 1 elseif WP.rt then set = 2 else set = 0 end
  end
  if set ~= WP.set then
    WP.set = set
    if WP.Bar then WP.Bar.HighlightSet(set) end
  end
  WP.UpdateStatus()
end
WP.SetFromTriggers = SetFromTriggers

local function SetMode(mode)
  WP.mode = mode
  if mode ~= "controller" then
    WP.lt, WP.rt = false, false
    if WP.peeking then WP.EndPeek() end
  end
  if WowPadDB and WowPadDB.debug then Print("Mode: |cffffff00" .. mode .. "|r") end
  SetFromTriggers()
  if WP.Bar then WP.Bar.UpdateVisibility() end
end

-- LT / RT with a window that has tabs (so the bumpers page them): the press swaps window, as on
-- 3.3.5. The set still shows while the trigger is held.
local function TriggerSwap(step)
  if WP.set ~= 0 or not Nav.Active() or not Nav.root or not Nav.HasTabs(Nav.root) then return end
  if table.getn(Nav.roots) > 1 then Nav.CycleRoot(step) end
end

-- Signals that act once, on their key going down.
local ON_DOWN = {
  MODE_CONTROLLER = function() SetMode("controller") end,
  MODE_DESKTOP    = function() SetMode("desktop") end,
  POINTER_ON      = function() WP.pointer = true; WP.UpdateStatus() end,
  POINTER_OFF     = function() WP.pointer = false; WP.UpdateStatus() end,
  LT_ON           = function() TriggerSwap(-1); WP.lt = true; SetFromTriggers() end,
  LT_OFF          = function() WP.lt = false; SetFromTriggers() end,
  RT_ON           = function() TriggerSwap(1); WP.rt = true; SetFromTriggers() end,
  RT_OFF          = function() WP.rt = false; SetFromTriggers() end,
  ZOOM_ON         = function() zoomHint:Show() end,
  ZOOM_OFF        = function() zoomHint:Hide() end,
  CAM_IDLE        = CamIdle,
  CAM_ACTIVE      = CamActive,
  L3              = function()
    if MenuContext() then
      if WP.OpenItemActions then WP.OpenItemActions() end
    else
      ToggleAutoRun()
    end
  end,
  LB              = function() Bumper("LB") end,
  RB              = function() Bumper("RB") end,
  LB_FLICK_DOWN   = function() Flick("LB", "DOWN") end,
  LB_FLICK_UP     = function() Flick("LB", "UP") end,
  RB_FLICK_DOWN   = function() Flick("RB", "DOWN") end,
  RB_FLICK_UP     = function() Flick("RB", "UP") end,
  BACK_TAP        = function() ToggleWorldMap() end,
  BACK_HOLD       = function() OpenAllBags() end,
  START           = function() if WP.StartPressed then WP.StartPressed() end end,
}
for n = 0, 8 do
  local d = n
  ON_DOWN["RING_DIR_" .. n] = function() if WP.Ring then WP.Ring.Highlight(d) end end
end

-- The binding body of every WOWPAD_<NAME> command (Bindings.xml).
function WowPad_Signal(name)
  local down = keystate == "down"
  local i = WP.SLOT_INDEX[name]
  if i then
    if WP.mode == "controller" then SlotSignal(i, down) end
    return
  end
  if not down then return end
  local fn = ON_DOWN[name]
  if fn then fn() end
end

---------------------------------------------------------------------------
-- What benilla-wowpad asks every frame.
---------------------------------------------------------------------------
-- looking, window open, aiming, camera / pointer / zoom sensitivity, invert Y (-1 = the ini's),
-- peek delay (0 = the ini's), walk/run, smooth camera, healer mode, ring slot, menu context,
-- and a pointer target (screen fractions from the bottom left) once after navigation moved it.
function WowPad_Frame()
  local db = WowPadDB or {}
  local inv = -1
  if db.wpInvertY == true then inv = 1 elseif db.wpInvertY == false then inv = 0 end
  local wx, wy = WP.warpX, WP.warpY
  WP.warpX, WP.warpY = nil, nil
  return IsMouselooking() and true or false,
    (WP.pointer or AnyWindowOpen()) and true or false,
    SpellIsTargeting() and true or false,
    tonumber(db.wpCamSens) or 1, tonumber(db.wpPtrSens) or 1, tonumber(db.wpZoomSens) or 1,
    inv, tonumber(db.wpPeekDelay) or 0,
    db.wpWalkRun == true, db.wpCamSmooth == true, db.wpBumperFlick == true,
    tonumber(db.wpRingSlot) or 0,
    MenuContext() and WP.set <= 0 and not WP.OwnMenu() and true or false,
    wx, wy,
    db.wpSwapXY == true
end

-- benilla-wowpad: the pad's face style, when it connects.
function WowPad_Connected(style)
  WP.padStyle = style
  if WowPadDB and not WowPadDB.buttonStyle and style == "playstation" then
    WP.SetButtonStyle("ps")
  end
end

-- benilla-wowpad: the crosshair's height above the centre, as a fraction of the screen.
function WowPad_SetCrosshair(frac)
  WP.crosshairFrac = frac
end

---------------------------------------------------------------------------
-- Status line (debug aid; /wp status toggles). Mode, action set, camera / pointer context.
---------------------------------------------------------------------------
local status = CreateFrame("Frame", "WowPadStatus", UIParent)
status:SetWidth(420)
status:SetHeight(22)
status:SetPoint("TOP", UIParent, "TOP", 0, -110)
local statusText = status:CreateFontString(nil, "OVERLAY", "GameFontNormal")
statusText:SetPoint("CENTER", status, "CENTER", 0, 0)
status:Hide()

function WP.UpdateStatus()
  if not WowPadDB or not WowPadDB.showStatus then status:Hide(); return end
  status:Show()
  if WP.mode ~= "controller" then
    statusText:SetText("WowPad: |cffaaaaaaDESKTOP|r")
    return
  end
  local set = WP.Keys(WP.SET_NAMES[WP.set] or "?")
  local buttons = (MenuContext() and WP.set == 0) and "  |cff66ccffmenu buttons|r" or ""
  statusText:SetText(string.format("WowPad: |cff55ff55CONTROLLER|r  set: |cffffff00%s|r  %s%s%s",
    set, WP.context or "?", buttons, WP.pointer and "  |cffff9900pointer mode|r" or ""))
end

---------------------------------------------------------------------------
-- Events & slash
---------------------------------------------------------------------------
local ev = CreateFrame("Frame")
ev:RegisterEvent("PLAYER_LOGIN")
ev:RegisterEvent("PLAYER_ENTER_COMBAT")
ev:RegisterEvent("PLAYER_LEAVE_COMBAT")
ev:SetScript("OnEvent", function()
  if event == "PLAYER_LOGIN" then
    WowPadDB = WowPadDB or {}
    if WowPadDB.debug == nil then WowPadDB.debug = false end
    if WowPadDB.showStatus == nil then WowPadDB.showStatus = false end
    if WowPadDB.xAttack == nil then WowPadDB.xAttack = true end
    for i = 1, table.getn(WP.setupHooks) do WP.setupHooks[i]() end
    WP.UpdateStatus()
  elseif event == "PLAYER_ENTER_COMBAT" then
    WP.autoAttacking = true
  elseif event == "PLAYER_LEAVE_COMBAT" then
    WP.autoAttacking = false
  end
end)

local function Word(msg, n)
  local words = {}
  for w in string.gfind(msg or "", "%S+") do table.insert(words, w) end
  return words[n]
end

SLASH_WOWPAD1 = "/wp"
SlashCmdList["WOWPAD"] = function(msg)
  local cmd = string.lower(Word(msg, 1) or "")
  if cmd == "debug" then
    WowPadDB.debug = not WowPadDB.debug
    Print("Debug messages " .. (WowPadDB.debug and "on" or "off"))
  elseif cmd == "xattack" then
    WowPadDB.xAttack = not WowPadDB.xAttack
    Print("X also starts attack: " .. (WowPadDB.xAttack and "on" or "off"))
  elseif cmd == "swap" then
    WowPadDB.swapBumpers = not WowPadDB.swapBumpers
    Print("Bumpers: LB = " .. (WowPadDB.swapBumpers and "enemy" or "friend") .. ", RB = "
          .. (WowPadDB.swapBumpers and "friend" or "enemy"))
  elseif cmd == "healer" then
    WowPadDB.wpBumperFlick = not WowPadDB.wpBumperFlick
    Print("Healer mode (hold the friendly bumper, flick the right stick): "
          .. (WowPadDB.wpBumperFlick and "on" or "off"))
  elseif cmd == "bar" then
    if WP.Bar then WP.Bar.ToggleAlways() end
  elseif cmd == "lite" then
    if WP.Bar then WP.Bar.SetLite(not WowPadDB.barLite) end
  elseif cmd == "crosshair" then
    if WP.ToggleCrosshair then WP.ToggleCrosshair() end
  elseif cmd == "peek" then
    WowPadDB.peek = (WowPadDB.peek == false)
    Print("Crosshair peek (tooltips when the right stick rests): " .. (WowPadDB.peek and "on" or "off"))
  elseif cmd == "blizz" then
    if WP.ToggleBlizzBars then WP.ToggleBlizzBars() end
  elseif cmd == "castbar" then
    WowPadDB.castBar = not (WowPadDB.castBar ~= false)
    if WP.Extra then WP.Extra.ApplyShown() end
    Print("Cast bar: " .. ((WowPadDB.castBar ~= false) and "on" or "off"))
  elseif cmd == "compare" then
    WowPadDB.compare = not (WowPadDB.compare ~= false)
    Print("Compare (hold Y in a menu): " .. ((WowPadDB.compare ~= false) and "on" or "off"))
  elseif cmd == "options" or cmd == "o" then
    if WP.OpenOptions then WP.OpenOptions() end
  elseif cmd == "edit" then
    if WP.ToggleEdit then WP.ToggleEdit() end
  elseif cmd == "scale" then
    local v = tonumber(Word(msg, 2))
    if v and WP.Bar then WP.Bar.SetScale(v) else Print("Usage: /wp scale 0.8") end
  elseif cmd == "sens" then
    local v = tonumber(Word(msg, 2))
    if v then WowPadDB.wpCamSens = math.max(0.05, math.min(3, v)); Print("Camera sensitivity x" .. WowPadDB.wpCamSens)
    else Print("Usage: /wp sens 0.7  (camera, 0.05-3)") end
  elseif cmd == "psens" then
    local v = tonumber(Word(msg, 2))
    if v then WowPadDB.wpPtrSens = math.max(0.05, math.min(3, v)); Print("Pointer sensitivity x" .. WowPadDB.wpPtrSens)
    else Print("Usage: /wp psens 1.0  (pointer, 0.05-3)") end
  elseif cmd == "invert" then
    WowPadDB.wpInvertY = not (WowPadDB.wpInvertY == true)
    Print("Invert camera Y: " .. (WowPadDB.wpInvertY and "on" or "off"))
  elseif cmd == "smooth" then
    WowPadDB.wpCamSmooth = not WowPadDB.wpCamSmooth
    Print("Smooth camera: " .. (WowPadDB.wpCamSmooth and "on" or "off"))
  elseif cmd == "walk" then
    WowPadDB.wpWalkRun = not WowPadDB.wpWalkRun
    Print("Walk on slight stick tilt: " .. (WowPadDB.wpWalkRun and "on" or "off"))
  elseif cmd == "ring" then
    local v = Word(msg, 2)
    if v == "off" then WowPadDB.wpRingSlot = 0; Print("Utility ring off")
    else
      local s, i = tonumber(string.sub(v or "", 1, 1)), tonumber(string.sub(v or "", 3, 3))
      if s and i and s >= 0 and s <= 3 and i >= 1 and i <= 8 then
        WowPadDB.wpRingSlot = s * 10 + i
        Print("Utility ring on slot " .. s .. "_" .. i)
      else
        Print("Usage: /wp ring <set>_<slot> (e.g. 3_8) or /wp ring off")
      end
    end
    if WP.Bar then WP.Bar.UpdateAll() end
  elseif cmd == "ps" or cmd == "xbox" then
    WP.SetButtonStyle(cmd == "ps" and "ps" or "xbox")
  elseif cmd == "map" then
    if WP.ShowInfo then WP.ShowInfo() end
  elseif cmd == "firsttime" or cmd == "welcome" or cmd == "setup" then
    if WP.ShowFirstTime then WP.ShowFirstTime(1) end
  elseif cmd == "keyboard" then
    WowPadDB.keyboard = (WowPadDB.keyboard == false)
    Print("On-screen keyboard: " .. (WowPadDB.keyboard and "on" or "off"))
  elseif cmd == "status" then
    WowPadDB.showStatus = not WowPadDB.showStatus
    WP.UpdateStatus()
  else
    Print(string.format("mode=%s set=%s context=%s pointer=%s", WP.mode, tostring(WP.set),
      tostring(WP.context), tostring(WP.pointer)))
    Print("/wp options | map | firsttime | keyboard | edit | bar | lite | blizz | castbar | compare | crosshair | peek | scale <0.4-1.6> | sens <x> | psens <x>"
          .. " | invert | smooth | walk | swap | healer | ring <set_slot|off> | xattack | xbox | ps | status | debug")
  end
end
