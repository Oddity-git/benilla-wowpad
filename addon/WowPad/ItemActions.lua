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

-----------------------------------------------------------------------------
-- Compare (built): 1.12 has no hover compare, so Y held shows the item you wear in the same slot
-- beside the tooltip. Our own tooltip frame, so the vendor's ShoppingTooltip1/2 stay untouched.
-----------------------------------------------------------------------------
-- itemEquipLoc (GetItemInfo #8) -> the inventory slots it may occupy (0 = ammo, 1 = head, ...
-- 11/12 fingers, 13/14 trinkets, 16/17 weapons, 18 ranged, 19 tabard).
local CMP_SLOTS = {
  INVTYPE_HEAD = { 1 }, INVTYPE_NECK = { 2 }, INVTYPE_SHOULDER = { 3 }, INVTYPE_BODY = { 4 },
  INVTYPE_CHEST = { 5 }, INVTYPE_ROBE = { 5 }, INVTYPE_WAIST = { 6 }, INVTYPE_LEGS = { 7 },
  INVTYPE_FEET = { 8 }, INVTYPE_WRIST = { 9 }, INVTYPE_HAND = { 10 },
  INVTYPE_FINGER = { 11, 12 }, INVTYPE_TRINKET = { 13, 14 }, INVTYPE_CLOAK = { 15 },
  INVTYPE_WEAPON = { 16, 17 }, INVTYPE_2HWEAPON = { 16 }, INVTYPE_WEAPONMAINHAND = { 16 },
  INVTYPE_WEAPONOFFHAND = { 17 }, INVTYPE_SHIELD = { 17 }, INVTYPE_HOLDABLE = { 17 },
  INVTYPE_RANGED = { 18 }, INVTYPE_RANGEDRIGHT = { 18 }, INVTYPE_THROWN = { 18 },
  INVTYPE_RELIC = { 18 }, INVTYPE_TABARD = { 19 },
}

-- The stock compare plates (ShoppingTooltip1/2), the same XML tooltips the vendor compare uses --
-- an addon-created GameTooltip counts lines but draws no text in benilla.
local function Plate(i) return getglobal("ShoppingTooltip" .. i) end

local function CompareOn() return not (WowPadDB and WowPadDB.compare == false) end
WP.CompareOn = CompareOn

function Nav.HideCompare()
  Nav.compareShown = false
  for i = 1, 2 do
    local tt = Plate(i)
    if tt and tt:IsShown() then tt:Hide() end
  end
end

-- The worn item in the same slot, beside the bag tooltip. Returns true when a plate showed.
function Nav.StartCompare()
  if not CompareOn() then return false end
  local link = Nav.FocusedItem()
  if not link then
    if WowPadDB and WowPadDB.debug then WP.Print("compare: no item selected") end
    return false
  end
  local _, _, idstr = string.find(link, "item:(%d+)")
  if not idstr then
    if WowPadDB and WowPadDB.debug then WP.Print("compare: no item id in the link") end
    return false
  end
  -- GetItemInfo takes a plain "item:..." string or a number, not a hyperlink (GetContainerItemLink
  -- returns a hyperlink, which parses to id 0), so hand it the numeric id.
  local _, _, _, _, _, _, _, equipLoc = GetItemInfo(tonumber(idstr))
  if not equipLoc or equipLoc == "" then
    if WowPadDB and WowPadDB.debug then WP.Print("compare: item not cached yet") end
    return false
  end
  local slots = CMP_SLOTS[equipLoc]
  if not slots then
    if WowPadDB and WowPadDB.debug then WP.Print("compare: " .. equipLoc .. " is not equippable") end
    return false
  end
  -- One plate per worn candidate (rings, trinkets and dual-wield show two), to the left of the
  -- item tooltip, top-aligned with it. Anchor before content so the layout includes the final
  -- points; a plate with no lines stays hidden, never blank.
  local n, anchor = 0, GameTooltip
  for i = 1, table.getn(slots) do
    if n < 2 and GetInventoryItemLink("player", slots[i]) then
      local tt = Plate(n + 1)
      if tt then
        tt:SetOwner(GameTooltip, "ANCHOR_NONE")
        tt:ClearAllPoints()
        tt:SetPoint("TOPRIGHT", anchor, "TOPLEFT", -4, 0)
        tt:SetInventoryItem("player", slots[i])
        local lines = tt:NumLines()
        if WowPadDB and WowPadDB.debug then
          WP.Print("compare plate " .. (n + 1) .. " slot " .. slots[i] .. ": lines " .. lines)
        end
        if lines > 0 then
          tt:SetAlpha(1)
          tt:Show()
          anchor = tt
          n = n + 1
        else
          tt:Hide()
        end
      end
    end
  end
  for i = n + 1, 2 do
    local tt = Plate(i)
    if tt and tt:IsShown() then tt:Hide() end
  end
  if n == 0 then
    if WowPadDB and WowPadDB.debug then WP.Print("compare: nothing worn in " .. equipLoc) end
    return false
  end
  Nav.compareShown = true
  if WowPadDB and WowPadDB.debug then
    WP.Print("compare: " .. equipLoc .. " -> " .. n .. " plate(s)")
  end
  return true
end

function Nav.StopCompare()
  Nav.HideCompare()
end

-- Y: tap previews; hold the same button past `hold` compares.
Nav.compare = { held = false, since = 0, armed = false, hold = 0.25 }
function Nav.CompareDown()
  if not CompareOn() then Nav.Preview() return end
  Nav.compare.held = true
  Nav.compare.since = GetTime()
  Nav.compare.armed = false
  Nav.compare.lastTry = 0
  Nav.compare.confirms = 0
  Nav.compare.confirmAt = 0
end
function Nav.CompareUp()
  local c = Nav.compare
  if not c.held then return end
  c.held = false
  if c.armed then
    c.armed = false
    Nav.StopCompare()
  else
    Nav.Preview()
  end
end

-- Retry while held (so a template that arrives late still compares), then re-assert the plate a
-- couple of times: benilla sometimes lays a reused tooltip out blank on the first pass.
local cmpDriver = CreateFrame("Frame")
cmpDriver:SetScript("OnUpdate", function()
  local c = Nav.compare
  if c.held and (GetTime() - c.since) >= c.hold then c.armed = true end
  if not c.armed then return end
  if not WP.MenuContext() then
    c.armed = false
    Nav.StopCompare()
  elseif not Nav.compareShown then
    if (GetTime() - (c.lastTry or 0)) >= 0.2 then
      c.lastTry = GetTime()
      Nav.StartCompare()
    end
  elseif (c.confirms or 0) < 2 and GetTime() >= (c.confirmAt or 0) then
    c.confirms = (c.confirms or 0) + 1
    c.confirmAt = GetTime() + 0.15
    Nav.StartCompare()
  end
end)

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
