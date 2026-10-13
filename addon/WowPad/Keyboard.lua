-- Keyboard.lua - an on-screen keyboard above the chat window, also used for text fields
-- (auction house search, mail, ...). Ported from WowPad 1.4.2 (3.3.5).
--
-- The chat box takes every key while it has focus, so the pad can't drive it. Instead you type
-- into this keyboard and WowPad hands the finished line to the chat box to send (slash commands
-- like /w name or /p work too).
--
-- Opening: Back + A (benilla-wowpad presses Enter, the game focuses the chat box, and in
-- controller mode we swap that for this keyboard). Out of combat only, like the other menus.
-- Navigated like any window:
--   D-pad: move   A: type   X: type as capital   Y: space   B: delete (empty: close)
--   LB / RB: channel   Start or Back + A: send   Back + B: close
--
-- Text fields: A on a field in a window opens the keyboard under it. What you type goes into the
-- field as you type; Start / Back + A = Enter in that field (the auction house searches), B on an
-- empty line closes. Number fields only take digits.
--
-- benilla-wowpad tells us when an edit box takes the keyboard focus (WowPad_EditFocus).

local WP = WowPad

local ROWS = {
  { "1", "2", "3", "4", "5", "6", "7", "8", "9", "0" },
  { "q", "w", "e", "r", "t", "y", "u", "i", "o", "p" },
  { "a", "s", "d", "f", "g", "h", "j", "k", "l", "'" },
  { "z", "x", "c", "v", "b", "n", "m", ",", ".", "/" },
}
local SHIFTED = {
  ["1"] = "!", ["2"] = "@", ["3"] = "#", ["4"] = "$", ["5"] = "%", ["6"] = "^", ["7"] = "&",
  ["8"] = "*", ["9"] = "(", ["0"] = ")", ["'"] = '"', [","] = ";", ["."] = ":", ["/"] = "?",
}
local CHANNELS = {
  { type = "SAY",     label = "Say" },
  { type = "PARTY",   label = "Party" },
  { type = "GUILD",   label = "Guild" },
  { type = "RAID",    label = "Raid" },
  { type = "WHISPER", label = "Reply" },
}
local KEY, GAP, PAD = 30, 3, 10
local MAXLEN = 255

local K      -- the keyboard frame: built on first use only (Build below)
local line   -- its text line
local M = {} -- its functions, copied onto the frame when it's built
local text, shift, chan = "", false, 1
local field, fieldOrig, fieldDone, chatText   -- text-field mode (nil = chat)

local function Enabled() return not (WowPadDB and WowPadDB.keyboard == false) end

local function Channel()
  local c = CHANNELS[chan]
  local target
  if c.type == "WHISPER" then
    target = ChatEdit_GetLastTellTarget and ChatEdit_GetLastTellTarget(ChatFrameEditBox)
    if target == "" then target = nil end
  end
  return c, target
end

-- The end of a long line.
local function Tail(s)
  if string.len(s) > 48 then return "..." .. string.sub(s, -45) end
  return s
end

local keys = {}
local function Redraw()
  if field then
    line:SetText("|cffffd100>|r " .. Tail(text) .. "|cffffd100_|r")
  else
    local c, target = Channel()
    local info = ChatTypeInfo and ChatTypeInfo[c.type]
    local col = "|cffffffff"
    if info then
      col = string.format("|cff%02x%02x%02x", math.floor(info.r * 255), math.floor(info.g * 255),
                          math.floor(info.b * 255))
    end
    local label = c.type == "WHISPER" and ("To " .. (target or "?")) or c.label
    line:SetText(col .. "[" .. label .. "]|r " .. Tail(text) .. "|cffffd100_|r")
  end
  for k = 1, table.getn(keys) do
    local b = keys[k]
    if b.char then
      local ch = b.char
      if shift then ch = SHIFTED[ch] or string.upper(ch) end
      b:SetText(ch)
    end
  end
  if K.shiftKey then K.shiftKey:SetText(shift and "|cffffd100SHIFT|r" or "Shift") end
end

-- Longest line: the field's own limit in field mode.
local function MaxLen()
  local m = field and field.GetMaxLetters and field:GetMaxLetters() or 0
  if m and m > 0 then return math.min(m, MAXLEN) end
  return MAXLEN
end

local function Numeric() return field and field.IsNumeric and field:IsNumeric() end

-- Field mode: the field shows what you type straight away.
local function Changed()
  if field then field:SetText(text) end
  Redraw()
end

local function Type(ch, capital)
  if string.len(text) >= MaxLen() then return end
  if capital or shift then ch = SHIFTED[ch] or string.upper(ch) end
  if Numeric() and not string.find(ch, "^%d$") then return end
  text = text .. ch
  shift = false
  Changed()
end

function M.Space()
  if Numeric() then return end
  if string.len(text) < MaxLen() then text = text .. " "; Changed() end
end

function M.Delete()
  if text == "" then fieldDone = true; K:Hide() return end
  text = string.sub(text, 1, -2)
  Changed()
end

function M.IsField() return field ~= nil end

-- LB / RB: next / previous channel (Reply only when someone has whispered you).
function M.Page(step)
  if field then return end
  local n = table.getn(CHANNELS)
  for _ = 1, n do
    chan = math.mod(chan - 1 + step + n, n) + 1
    local c, target = Channel()
    if c.type ~= "WHISPER" or target then break end
  end
  Redraw()
end

-- A field's OnEnterPressed, run as its own script would be (1.12 handlers read `this`).
local function PressEnter(f)
  local onEnter = f:GetScript("OnEnterPressed")
  if not onEnter then return end
  local was = this
  this = f
  onEnter()
  this = was
end

local function Trim(s)
  s = string.gsub(s, "^%s+", "")
  s = string.gsub(s, "%s+$", "")
  return s
end

-- Hand the line to the chat box and send it: it handles channels, whisper targets and slash
-- commands exactly as if you had typed it.
function M.Send()
  if field then                          -- text field: Enter in that field
    local f = field
    f:SetText(text)
    fieldDone = true
    K:Hide()
    PressEnter(f)
    return
  end
  local msg = Trim(text)
  if msg == "" then K:Hide() return end
  local c, target = Channel()
  local eb = ChatFrameEditBox
  if eb and ChatEdit_SendText then
    eb.chatType = c.type
    if target then eb.tellTarget = target end
    eb:SetText(msg)
    ChatEdit_SendText(eb, 1)
    eb:SetText("")
  elseif string.sub(msg, 1, 1) ~= "/" then
    SendChatMessage(msg, c.type, nil, target)
  end
  text, shift = "", false
  K:Hide()
end

---------------------------------------------------------------------------
-- Build (first use only; never when the keyboard option is off)
---------------------------------------------------------------------------
local function Build()
  if K then return end
  K = CreateFrame("Frame", "WowPadKeyboard", UIParent)
  K:SetFrameStrata("DIALOG")
  K:EnableMouse(true)
  K:SetClampedToScreen(true)
  K:SetBackdrop({
    bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
    edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
    tile = true, tileSize = 16, edgeSize = 16,
    insets = { left = 4, right = 4, top = 4, bottom = 4 },
  })
  K:SetWidth(PAD * 2 + 10 * KEY + 9 * GAP)
  K:SetHeight(PAD * 2 + 26 + 5 * (KEY + GAP))
  K:Hide()
  table.insert(WP.overlays, K)
  table.insert(UISpecialFrames, "WowPadKeyboard")   -- Esc (Back + B) closes it
  -- Leaving field mode: closed without Start (Esc) puts the field back as it was; the chat line
  -- you had started comes back.
  K:SetScript("OnHide", function()
    if not field then return end
    if not fieldDone then field:SetText(fieldOrig or "") end
    field, fieldOrig = nil, nil
    text, shift = chatText or "", false
    chatText = nil
  end)

  -- Version label above the top-right corner.
  local ver = K:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
  ver:SetPoint("BOTTOMRIGHT", K, "TOPRIGHT", -4, 2)
  ver:SetText("WowPad " .. ((GetAddOnMetadata and GetAddOnMetadata("WowPad", "Version")) or ""))

  -- Text line: [Channel] what you typed_
  line = K:CreateFontString(nil, "OVERLAY", "ChatFontNormal")
  line:SetPoint("TOPLEFT", K, "TOPLEFT", PAD, -PAD - 4)
  line:SetPoint("TOPRIGHT", K, "TOPRIGHT", -PAD, -PAD - 4)
  line:SetJustifyH("LEFT")

  local function MakeKey(name, label, w, onClick)
    local b = CreateFrame("Button", name, K, "UIPanelButtonTemplate")
    b:SetWidth(w)
    b:SetHeight(KEY)
    b:SetText(label)
    b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    b:SetScript("OnClick", onClick)
    keys[table.getn(keys) + 1] = b
    return b
  end

  local top = -PAD - 26
  for r = 1, table.getn(ROWS) do
    local row = ROWS[r]
    for c = 1, table.getn(row) do
      local ch = row[c]
      local b = MakeKey("WowPadKeyboardKey" .. r .. "_" .. c, ch, KEY, function()
        Type(ch, arg1 == "RightButton")           -- X (right-click) = capital
      end)
      b.char = ch
      b:SetPoint("TOPLEFT", K, "TOPLEFT", PAD + (c - 1) * (KEY + GAP), top - (r - 1) * (KEY + GAP))
    end
  end
  local function Unit(n) return n * KEY + (n - 1) * GAP end
  local y = top - 4 * (KEY + GAP)
  K.shiftKey = MakeKey("WowPadKeyboardShift", "Shift", Unit(2), function() shift = not shift; Redraw() end)
  K.shiftKey:SetPoint("TOPLEFT", K, "TOPLEFT", PAD, y)
  local space = MakeKey("WowPadKeyboardSpace", "Space", Unit(4), function() M.Space() end)
  space:SetPoint("TOPLEFT", K, "TOPLEFT", PAD + 2 * (KEY + GAP), y)
  local del = MakeKey("WowPadKeyboardDelete", "Delete", Unit(2), function() M.Delete() end)
  del:SetPoint("TOPLEFT", K, "TOPLEFT", PAD + 6 * (KEY + GAP), y)
  local send = MakeKey("WowPadKeyboardSend", "Send", Unit(2), function() M.Send() end)
  send:SetPoint("TOPLEFT", K, "TOPLEFT", PAD + 8 * (KEY + GAP), y)
  K.deleteKey, K.firstKey = del, getglobal("WowPadKeyboardKey2_1")   -- used by Core's navigation

  -- Copy M's functions onto the frame (Core and Radial call them).
  for k, v in pairs(M) do K[k] = v end
  WP.Keyboard = K
end

function M.Open(initial)
  if WP.InCombat() then WP.Print("The keyboard isn't available in combat.") return end
  Build()
  if initial and initial ~= "" then text = initial end
  K:ClearAllPoints()
  local cf = DEFAULT_CHAT_FRAME or ChatFrame1
  if cf then
    K:SetPoint("BOTTOMLEFT", cf, "TOPLEFT", -6, 30)
  else
    K:SetPoint("BOTTOM", UIParent, "BOTTOM", 0, 200)
  end
  Redraw()
  K:Show()
end

-- Text field (A on a field in a window): type into it, Start = Enter there.
function M.OpenFor(eb)
  if WP.InCombat() then return end
  Build()
  if K:IsShown() then fieldDone = true; K:Hide() end   -- leave whatever was open
  chatText = text
  field, fieldOrig, fieldDone = eb, eb:GetText() or "", false
  text, shift = fieldOrig, false
  if eb.ClearFocus then eb:ClearFocus() end
  K:ClearAllPoints()
  K:SetPoint("TOPLEFT", eb, "BOTTOMLEFT", -8, -6)
  Redraw()
  K:Show()
end

-- The keyboard stays open when you use the mouse: its keys are ordinary buttons you can click
-- (right-click = capital).

---------------------------------------------------------------------------
-- An edit box took the keyboard focus (benilla-wowpad, in controller mode). The chat box: Back + A
-- pressed Enter, so close the box and open the keyboard (or, if it is open, send). Any other box:
-- type into it with the keyboard.
---------------------------------------------------------------------------
function WowPad_EditFocus(name)
  if not Enabled() or WP.mode ~= "controller" or WP.InCombat() then return end
  local box = name and getglobal(name)
  if not box or not box.GetText then return end
  if box == ChatFrameEditBox then
    local initial = box:GetText() or ""
    box:SetText("")
    if ChatEdit_OnEscapePressed then
      local was = this
      this = box
      ChatEdit_OnEscapePressed(box)
      this = was
    else
      box:ClearFocus()
      box:Hide()
    end
    if K and K:IsShown() and not field then M.Send() else M.Open(initial) end
    return
  end
  if K and box:GetParent() == K then return end
  M.OpenFor(box)
end

-- For other parts of WowPad: open the keyboard if it's enabled.
function WP.OpenKeyboardFor(eb)
  if not Enabled() then return false end
  M.OpenFor(eb)
  return true
end

function WP.OpenKeyboard(initial)
  if not Enabled() then return end
  M.Open(initial)
end
