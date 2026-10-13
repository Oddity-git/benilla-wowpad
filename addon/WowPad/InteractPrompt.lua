-- InteractPrompt.lua - "X Talk" while something X can use is in reach. benilla-wowpad picks the
-- soft target (an NPC with a service, a corpse to loot or skin, a chest, herb, vein, mailbox...)
-- a few times a second and calls WowPad_InteractPrompt(verb), nil when there is none. X then acts
-- on it without targeting it. Hidden while a window takes the pad, or with /wp prompt off.

local WP = WowPad
local M = {}
WP.Prompt = M
local frame, line, verb

local function Enabled() return not (WowPadDB and WowPadDB.interactPrompt == false) end
WP.PromptOn = Enabled

function M.Update()
  if not frame then return end
  if M.editing then
    line:SetParts({ { key = "X", text = "Talk" } }, 4)
    frame:Show()
    return
  end
  local show = verb and Enabled() and WP.mode == "controller"
      and not (WP.MenuContext and WP.MenuContext()) and WP.set <= 0
  if show then
    line:SetParts({ { key = "X", text = verb } }, 4)
    frame:Show()
  else
    frame:Hide()
  end
end

-- Called by benilla-wowpad when the soft target's verb changes.
function WowPad_InteractPrompt(v)
  verb = v
  WP.interactPrompt = v
  M.Update()
end

-- X looted a corpse: the window it opens takes every row, as a Shift-click auto-loot does.
local lootAllUntil = 0
function WowPad_LootAll() lootAllUntil = GetTime() + 3 end

function M.SetEditing(on)
  if not frame then return end
  M.editing = on and true or false
  if frame.mover then
    if M.editing then frame.mover:Show() else frame.mover:Hide() end
  end
  M.Update()
end

table.insert(WP.setupHooks, function()
  frame = CreateFrame("Frame", "WowPadInteractPrompt", UIParent)
  frame:SetFrameStrata("HIGH")
  frame:SetWidth(110)
  frame:SetHeight(30)
  frame:SetBackdrop({ bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
                      edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
                      tile = true, tileSize = 16, edgeSize = 12,
                      insets = { left = 3, right = 3, top = 3, bottom = 3 } })
  frame:SetBackdropColor(0, 0, 0, 0.75)
  frame:SetBackdropBorderColor(0.6, 0.6, 0.6, 0.8)
  line = WP.NewKeyLine(frame, "GameFontHighlight", 20)
  line:SetPoint("CENTER", frame, "CENTER", 0, 0)
  local set = line.SetParts
  line.SetParts = function(self, parts, gap)
    local w = set(self, parts, gap)
    frame:SetWidth((w or 80) + 20)
    self:ClearAllPoints()
    self:SetPoint("LEFT", frame, "LEFT", 10, 0)
    return w
  end
  -- Home: below the screen centre, where the eye already is.
  WP.MakeMover(frame, "interactPrompt", "Interact prompt", { "CENTER", UIParent, "CENTER", 0, -140 })
  WP.ApplyMoverPos(frame)
  frame:Hide()
  M.Update()
end)

local ev = CreateFrame("Frame")
ev:RegisterEvent("LOOT_OPENED")
ev:SetScript("OnEvent", function()
  if GetTime() > lootAllUntil then return end
  lootAllUntil = 0
  for i = GetNumLootItems(), 1, -1 do LootSlot(i) end
end)
-- Windows opening and closing, the trigger sets and the mode change what may show.
local acc = 0
ev:SetScript("OnUpdate", function()
  acc = acc + arg1
  if acc < 0.2 then return end
  acc = 0
  if verb then M.Update() end
end)
