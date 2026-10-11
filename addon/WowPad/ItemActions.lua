-- ItemActions.lua - L3 on a bag item: a small menu with what you can do to it, and Y previews
-- the selected item in the dressing room. Out of combat only, like the rest of menu navigation.
--
-- 1.12 has no secure code, so the 3.3.5 secure "Disenchant" button is left out: disenchanting
-- needs a secure macro to cast the spell and then take the item, which this client cannot do.
-- Destroy asks for a confirmation (Cancel is preselected).
--
-- Returns link, bag, slot from the selected bag button; the tooltip its OnEnter showed, the bag
-- and slot IDs when it is a real bag slot, else a search of the bags for that link.

local WP = WowPad
local Nav = WP.Nav

-- Is this button part of a bag window? Default bags, the bank, and bag addons by frame name.
local function InBags(n)
  local f, depth = n, 0
  while f and depth < 8 do
    local name = f.GetName and f:GetName()
    if name then
      local l = string.lower(name)
      if string.find(l, "container") or string.find(l, "bag") or string.find(l, "inventory")
         or string.find(l, "^bankframe") then return true end
    end
    if f.GetParent then f = f:GetParent() else f = nil end
    depth = depth + 1
  end
  return false
end

function Nav.FocusedItem()
  local n = Nav.cur
  if not n then return end
  local p = n.GetParent and n:GetParent()
  local bag = (type(n.GetBag) == "function") and n:GetBag() or (p and p.GetID and p:GetID())
  local slot = n.GetID and n:GetID()
  -- A real bag slot: straight from the container, no tooltip needed.
  if InBags(n) and bag and slot then
    local bl = GetContainerItemLink(bag, slot)
    if bl then return bl, bag, slot end
  end
  -- Anything else (vendor, loot, quest reward, character): the tooltip its OnEnter showed.
  -- benilla's GameTooltip has no GetItem, so only ask when it is there.
  local link
  if GameTooltip.GetItem and GameTooltip:IsShown() and GameTooltip:IsOwned(n) then
    local _, l = GameTooltip:GetItem()
    link = l
  end
  if link and InBags(n) then
    for b = 0, (NUM_BAG_SLOTS or 4) do
      for sl = 1, (GetContainerNumSlots(b) or 0) do
        if GetContainerItemLink(b, sl) == link then return link, b, sl end
      end
    end
  end
  return link
end

-- Y: preview the selected item in the dressing room. The reference has no fit check, so any item
-- link is previewed; benilla dresses through the stock DressUpItemLink, or the DressUpModel's
-- TryOn when that stock function is not loaded.
function Nav.Preview()
  local link = Nav.FocusedItem()
  if not link then
    if WowPadDB and WowPadDB.debug then WP.Print("preview: nothing selected") end
    return
  end
  if DressUpItemLink then
    DressUpItemLink(link)
    if WowPadDB and WowPadDB.debug then WP.Print("preview: " .. link) end
  elseif DressUpModel and DressUpModel.TryOn then
    local _, _, id = string.find(link, "item:(%d+)")
    if id then
      DressUpModel:TryOn(tonumber(id))
      if WowPadDB and WowPadDB.debug then WP.Print("preview (TryOn): " .. link) end
    end
  else
    WP.Print("Preview is not available on this client.")
  end
end

-- Destroy the selected bag item, after a confirmation (Cancel is preselected).
local destroyPending
StaticPopupDialogs.WOWPAD_DESTROY = {
  text = "Destroy %s?",
  button1 = DELETE or "Destroy",
  button2 = CANCEL or "Cancel",
  OnAccept = function()
    local d = destroyPending
    destroyPending = nil
    if not d or GetContainerItemLink(d.bag, d.slot) ~= d.link then
      WP.Print("That item moved; nothing was destroyed.")
      return
    end
    ClearCursor()
    PickupContainerItem(d.bag, d.slot)
    if CursorHasItem() then DeleteCursorItem() end
  end,
  timeout = 0, whileDead = 1, hideOnEscape = 1, showAlert = 1,
}

function Nav.Destroy(link, bag, slot)
  if not link then link, bag, slot = Nav.FocusedItem() end
  if not (link and bag) then return end
  local _, count = GetContainerItemInfo(bag, slot)
  local what = link .. ((count and count > 1) and (" x" .. count) or "")
  destroyPending = { bag = bag, slot = slot, link = link }
  StaticPopup_Show("WOWPAD_DESTROY", what)
end

-----------------------------------------------------------------------------
-- The menu window
-----------------------------------------------------------------------------
local F = CreateFrame("Frame", "WowPadItemActions", UIParent)
F:SetWidth(200)
F:SetFrameStrata("DIALOG")
F:EnableMouse(true)
F:SetBackdrop({
  bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
  edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
  tile = true, tileSize = 16, edgeSize = 16,
  insets = { left = 4, right = 4, top = 4, bottom = 4 },
})
F:SetPoint("CENTER", 0, 80)
F:Hide()
table.insert(WP.overlays, F)
table.insert(UISpecialFrames, "WowPadItemActions")   -- Escape closes it

local title = F:CreateFontString(nil, "OVERLAY", "GameFontNormal")
title:SetPoint("TOP", 0, -10)
title:SetWidth(184)

local item = {}

local function Row(name, label)
  local b = CreateFrame("Button", name, F)
  b:SetWidth(180)
  b:SetHeight(20)
  b:RegisterForClicks("LeftButtonUp")
  b:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")
  b.text = b:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
  b.text:SetPoint("LEFT", b, "LEFT", 10, 0)
  b.text:SetText(label)
  b:SetScript("OnEnter", function()
    if this.tooltipText then
      GameTooltip:SetOwner(this, "ANCHOR_RIGHT")
      GameTooltip:SetText(this.tooltipText, nil, nil, nil, nil, 1)
      GameTooltip:Show()
    end
  end)
  b:SetScript("OnLeave", function() GameTooltip:Hide() end)
  b:Hide()
  return b
end

local destroy = Row("WowPadItemActionsDestroy", DELETE or "Destroy")
destroy.tooltipText = "Destroy the item for good."
destroy:SetScript("OnClick", function()
  F:Hide()
  Nav.Destroy(item.link, item.bag, item.slot)
end)

local cancel = Row("WowPadItemActionsCancel", CANCEL or "Cancel")
cancel.tooltipText = "Keep the item."
cancel:SetScript("OnClick", function() F:Hide() end)

function WP.OpenItemActions()
  if F:IsShown() then F:Hide() return end
  local link, bag, slot = Nav.FocusedItem()
  if not (link and bag) then
    WP.Print("Select a bag item first.")
    return
  end
  item.link, item.bag, item.slot = link, bag, slot
  local _, count = GetContainerItemInfo(bag, slot)
  title:SetText(link .. ((count and count > 1) and (" x" .. count) or ""))
  destroy:ClearAllPoints()
  destroy:SetPoint("TOP", F, "TOP", 0, -30)
  destroy:Show()
  cancel:ClearAllPoints()
  cancel:SetPoint("TOP", F, "TOP", 0, -52)
  cancel:Show()
  F:SetHeight(40 + 2 * 22)
  F:Show()
  if WP.Nav then WP.Nav.SelectSoon(cancel) end
end
