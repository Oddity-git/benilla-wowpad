-- InteractPrompt.lua - an X icon over the thing X would use, while it is in reach. benilla-wowpad
-- picks the soft target (an NPC with a service, a corpse to loot or skin, a chest, herb, vein,
-- mailbox...) a few times a second and calls WowPad_InteractPrompt(verb), nil when there is none,
-- and every frame WowPad_InteractPromptAt(x, y): where on screen the icon goes, as fractions of
-- the screen from its top-left corner (nil when the thing is off screen). X then acts on it
-- without targeting it. Hidden while a window takes the pad, or with /wp prompt off.

local WP = WowPad
local M = {}
WP.Prompt = M
local SIZE = 30
local frame, icon, verb, atX, atY

local function Enabled() return not (WowPadDB and WowPadDB.interactPrompt == false) end
WP.PromptOn = Enabled

function M.Update()
  if not frame then return end
  local show = verb and atX and Enabled() and WP.mode == "controller"
      and not (WP.MenuContext and WP.MenuContext()) and WP.set <= 0
  if not show then frame:Hide(); return end
  icon:SetTexture(WP.FaceTexture("X"))
  frame:ClearAllPoints()
  frame:SetPoint("BOTTOM", UIParent, "BOTTOMLEFT",
    atX * UIParent:GetWidth(), (1 - atY) * UIParent:GetHeight())
  frame:Show()
end

-- Called by benilla-wowpad when the soft target's verb changes ("Talk", "Loot", ...).
function WowPad_InteractPrompt(v)
  verb = v
  WP.interactPrompt = v
  M.Update()
end

-- Called by benilla-wowpad as the thing moves on screen.
function WowPad_InteractPromptAt(x, y)
  atX, atY = x, y
  M.Update()
end

-- X looted a corpse: the window it opens takes every row, as a Shift-click auto-loot does.
local lootAllUntil = 0
function WowPad_LootAll() lootAllUntil = GetTime() + 3 end

table.insert(WP.setupHooks, function()
  frame = CreateFrame("Frame", "WowPadInteractPrompt", UIParent)
  frame:SetFrameStrata("BACKGROUND")
  frame:SetWidth(SIZE)
  frame:SetHeight(SIZE)
  icon = frame:CreateTexture(nil, "ARTWORK")
  icon:SetAllPoints(frame)
  frame:Hide()
  table.insert(WP.styleHooks, M.Update)
end)

local ev = CreateFrame("Frame")
ev:RegisterEvent("LOOT_OPENED")
ev:SetScript("OnEvent", function()
  if GetTime() > lootAllUntil then return end
  lootAllUntil = 0
  for i = GetNumLootItems(), 1, -1 do LootSlot(i) end
end)
-- Windows opening and closing, the trigger sets and the mode change whether it may show.
local acc = 0
ev:SetScript("OnUpdate", function()
  acc = acc + arg1
  if acc < 0.2 then return end
  acc = 0
  if verb then M.Update() end
end)
