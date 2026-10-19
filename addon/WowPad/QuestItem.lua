-- QuestItem.lua - the quick-use quest item: a hint when a quest item in the bags can be used
-- here, and LT + RT + L3 uses it. benilla-wowpad looks through the bags a few times a second and
-- calls WowPad_QuestItems(list) when the list changes, each row { bag, slot, "here" } (the item's
-- zone, or the object its spell needs, is right here) or { bag, slot, "target", text } (no place
-- binding: shown while the target's name is in the item's spell text). A { bag, slot, "no", why }
-- row is one that is not ready; /wp debug prints why. /wp questitem turns the hint off.

local WP = WowPad
local M = {}
WP.QuestItem = M
local items = {}
local pick
local frame, icon, line

local function Enabled() return not (WowPadDB and WowPadDB.questItem == false) end

-- The first item that works here, else the first whose text names the target.
local function Pick()
  for i = 1, table.getn(items) do
    if items[i][3] == "here" then return items[i] end
  end
  local name = UnitExists("target") and not UnitIsUnit("target", "player") and UnitName("target")
  if not name or string.len(name) < 3 then return nil end
  name = string.lower(name)
  for i = 1, table.getn(items) do
    local row = items[i]
    if row[3] == "target" and row[4] and string.find(string.lower(row[4]), name, 1, true) then
      return row
    end
  end
  return nil
end

function M.Update()
  pick = Enabled() and Pick() or nil
  if not frame then return end
  local texture = pick and GetContainerItemInfo(pick[1], pick[2])
  local show = texture and WP.mode == "controller" and not (WP.MenuContext and WP.MenuContext())
  if not show then frame:Hide(); return end
  local link = GetContainerItemLink(pick[1], pick[2])
  local _, _, name = link and string.find(link, "%[(.+)%]")
  icon:SetTexture(texture)
  frame:SetWidth(line:SetParts({ { key = "LT + RT + L3", text = "Use " .. (name or "item") } }, 4)
    + 34 + 16)
  frame:Show()
end

-- L3 with LT + RT held: true when it used the item, so L3's auto-run stays out of it.
function M.Use()
  if not pick or WP.set ~= 3 then return false end
  UseContainerItem(pick[1], pick[2])
  return true
end

-- Called by benilla-wowpad when the list changes.
function WowPad_QuestItems(list)
  items = list or {}
  if WowPadDB and WowPadDB.debug then
    for i = 1, table.getn(items) do
      local row = items[i]
      local name = GetContainerItemLink(row[1], row[2]) or "?"
      if row[3] == "no" then WP.Print("quest item not ready: " .. (row[4] or "?"))
      else WP.Print("quest item " .. row[3] .. ": " .. name) end
    end
  end
  M.Update()
end

function M.Toggle()
  WowPadDB.questItem = not Enabled()
  WP.Print("Quest item hint (LT + RT + L3 uses it): " .. (Enabled() and "on" or "off"))
  M.Update()
end

table.insert(WP.setupHooks, function()
  frame = CreateFrame("Frame", "WowPadQuestItemHint", UIParent)
  frame:SetHeight(32)
  frame:SetPoint("BOTTOM", UIParent, "BOTTOM", 0, 230)
  frame:SetFrameStrata("MEDIUM")
  frame:SetBackdrop({ bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
                      edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
                      tile = true, tileSize = 16, edgeSize = 12,
                      insets = { left = 3, right = 3, top = 3, bottom = 3 } })
  frame:SetBackdropColor(0, 0, 0, 0.8)
  icon = frame:CreateTexture(nil, "ARTWORK")
  icon:SetWidth(24)
  icon:SetHeight(24)
  icon:SetPoint("LEFT", frame, "LEFT", 6, 0)
  line = WP.NewKeyLine(frame, "GameFontHighlightSmall", 18)
  line:SetPoint("LEFT", icon, "RIGHT", 6, 0)
  frame:Hide()
  table.insert(WP.styleHooks, M.Update)
end)

-- The target, the bags and the mode change what shows.
local ev = CreateFrame("Frame")
ev:RegisterEvent("PLAYER_TARGET_CHANGED")
ev:RegisterEvent("BAG_UPDATE")
ev:SetScript("OnEvent", function() M.Update() end)
local acc = 0
ev:SetScript("OnUpdate", function()
  acc = acc + arg1
  if acc < 0.25 then return end
  acc = 0
  if table.getn(items) > 0 then M.Update() end
end)
