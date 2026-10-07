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
  local roots = WP.PopupRoots()
  for i = 1, table.getn(roots) do open[roots[i]] = true; any = true end
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
-- Menu navigation: the D-pad jumps the pointer to the nearest button that way; A clicks it and
-- X right-clicks it (benilla-wowpad presses the mouse), B backs out.
---------------------------------------------------------------------------
local Nav = {}
WP.Nav = Nav

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

-- Put the pointer on a frame: benilla-wowpad moves it there on its next frame, given as a
-- fraction of the screen from the bottom left.
function Nav.Select(f)
  Nav.cur = f
  if not f then return end
  local x, y = Centre(f)
  if x then Nav.WarpAbs(x, y) end
end

-- Put the pointer at absolute units (GetCursorPosition's).
function Nav.WarpAbs(x, y)
  local s = UIParent:GetEffectiveScale()
  local w, h = GetScreenWidth() * s, GetScreenHeight() * s
  if w > 0 and h > 0 then WP.warpX, WP.warpY = x / w, y / h end
  Nav.selectedAt = GetTime()
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

function Nav.Move(dir)
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

-- B: back out of the top window (a popup, a dropdown, then every window).
function Nav.Back()
  if WP.Radial and WP.Radial:IsVisible() then WP.Radial:Hide() return end
  if WP.UnitMenu and WP.UnitMenu:IsVisible() then WP.UnitMenu:Hide() return end
  for i = 1, 4 do
    local p = getglobal("StaticPopup" .. i)
    if p and p:IsVisible() then
      local cancel = getglobal("StaticPopup" .. i .. "Button2")
      if cancel and cancel:IsVisible() then cancel:Click() else p:Hide() end
      return
    end
  end
  if DropDownList1 and DropDownList1:IsVisible() then CloseDropDownMenus() return end
  if CursorHasItem() or CursorHasSpell() then ClearCursor() return end
  if WP.Bar and WP.Bar.editing then WP.Bar.SetEditing(false) return end
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
    if not down then return end
    local sig = WP.SLOT_SIGNALS[i]
    if i <= 4 then Nav.Move(sig)
    elseif i == 5 and WP.OwnMenu() then Nav.Press()
    elseif i == 6 then Nav.Back() end
    -- Elsewhere A and X are mouse clicks, pressed by benilla-wowpad; Y has nothing yet.
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
end

local function Bumper(which)
  if WP.RadialBumper and WP.RadialBumper(which) then return end
  if MenuContext() then return end
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

-- Signals that act once, on their key going down.
local ON_DOWN = {
  MODE_CONTROLLER = function() SetMode("controller") end,
  MODE_DESKTOP    = function() SetMode("desktop") end,
  POINTER_ON      = function() WP.pointer = true; WP.UpdateStatus() end,
  POINTER_OFF     = function() WP.pointer = false; WP.UpdateStatus() end,
  LT_ON           = function() WP.lt = true; SetFromTriggers() end,
  LT_OFF          = function() WP.lt = false; SetFromTriggers() end,
  RT_ON           = function() WP.rt = true; SetFromTriggers() end,
  RT_OFF          = function() WP.rt = false; SetFromTriggers() end,
  ZOOM_ON         = function() zoomHint:Show() end,
  ZOOM_OFF        = function() zoomHint:Hide() end,
  CAM_IDLE        = CamIdle,
  CAM_ACTIVE      = CamActive,
  L3              = function() if not MenuContext() then ToggleAutoRun() end end,
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
    wx, wy
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
  elseif cmd == "status" then
    WowPadDB.showStatus = not WowPadDB.showStatus
    WP.UpdateStatus()
  else
    Print(string.format("mode=%s set=%s context=%s pointer=%s", WP.mode, tostring(WP.set),
      tostring(WP.context), tostring(WP.pointer)))
    Print("/wp options | edit | bar | lite | blizz | crosshair | peek | scale <0.4-1.6> | sens <x> | psens <x>"
          .. " | invert | smooth | walk | swap | healer | ring <set_slot|off> | xattack | xbox | ps | status | debug")
  end
end
