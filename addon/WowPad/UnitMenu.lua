-- UnitMenu.lua - Y: a target menu like right-clicking a unit frame. A list of plain buttons
-- (1.12 has no secure code to work around), reached with the D-pad and clicked with A.

local WP = WowPad
local MAX_ITEMS = 12

local M = CreateFrame("Frame", "WowPadUnitMenuFrame", UIParent)
M:SetWidth(170)
M:SetHeight(40)
M:SetFrameStrata("DIALOG")
M:EnableMouse(true)
M:SetBackdrop({
  bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
  edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
  tile = true, tileSize = 16, edgeSize = 16,
  insets = { left = 4, right = 4, top = 4, bottom = 4 },
})
M:Hide()
table.insert(WP.overlays, M)
WP.UnitMenu = M

local title = M:CreateFontString(nil, "OVERLAY", "GameFontNormal")
title:SetPoint("TOP", M, "TOP", 0, -10)

local function IsOtherPlayer(u) return UnitIsPlayer(u) and not UnitIsUnit(u, "player") end
local function IsFriendlyPlayer(u) return IsOtherPlayer(u) and UnitIsFriend("player", u) end
local function Always() return true end

-- { label, shown-when(unit), action }
local ITEMS = {
  { "Assist", function(u) return UnitIsFriend("player", u) and not UnitIsUnit(u, "player") end,
    function() AssistUnit("target") end },
  { "Whisper", IsFriendlyPlayer, function() ChatFrame_SendTell(UnitName("target")) end },
  { "Invite", function(u) return IsFriendlyPlayer(u) and not UnitInParty(u) and not UnitInRaid(u) end,
    function() InviteByName(UnitName("target")) end },
  { "Inspect", IsOtherPlayer, function() if InspectUnit then InspectUnit("target") end end },
  { "Trade", IsFriendlyPlayer, function() InitiateTrade("target") end },
  { "Follow", IsFriendlyPlayer, function() FollowUnit("target") end },
  { "Duel", IsFriendlyPlayer, function() StartDuel(UnitName("target")) end },
  { "Mark: Skull", Always, function() if SetRaidTarget then SetRaidTarget("target", 8) end end },
  { "Clear Target", Always, function() ClearTarget() end },
}

local buttons = {}
for i = 1, MAX_ITEMS do
  local b = CreateFrame("Button", "WowPadUnitMenuItem" .. i, M)
  b:SetWidth(150)
  b:SetHeight(20)
  b:SetPoint("TOP", M, "TOP", 0, -28 - (i - 1) * 22)
  b:RegisterForClicks("LeftButtonUp")
  b:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight")
  b.text = b:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
  b.text:SetPoint("LEFT", b, "LEFT", 10, 0)
  b:SetScript("OnClick", function()
    M:Hide()
    if this.action then this.action() end
  end)
  b:Hide()
  buttons[i] = b
end

function M.Open()
  if M:IsShown() then M:Hide() return end
  if not UnitExists("target") then WP.Print("No target.") return end
  title:SetText(UnitName("target") or "Target")
  local n = 0
  for k = 1, table.getn(ITEMS) do
    local item = ITEMS[k]
    if n < MAX_ITEMS and item[2]("target") then
      n = n + 1
      buttons[n].text:SetText(item[1])
      buttons[n].action = item[3]
      buttons[n]:Show()
    end
  end
  for i = n + 1, MAX_ITEMS do buttons[i]:Hide() end
  M:SetHeight(34 + n * 22)
  M:ClearAllPoints()
  if TargetFrame and TargetFrame:IsVisible() then
    M:SetPoint("TOPLEFT", TargetFrame, "TOPRIGHT", -20, -8)
  else
    M:SetPoint("CENTER", UIParent, "CENTER", 0, 120)
  end
  M:Show()
  if WP.Nav then WP.Nav.SelectSoon(buttons[1]) end
end

-- The selected item is lit; the pointer resting on an item selects it (A presses the selected
-- one, Core.lua's Nav.Press).
M:SetScript("OnUpdate", function()
  local Nav = WP.Nav
  if not Nav then return end
  local settled = GetTime() - (Nav.selectedAt or 0) > 0.15
  for i = 1, MAX_ITEMS do
    local b = buttons[i]
    if b:IsShown() and settled and MouseIsOver(b) then Nav.cur = b end
  end
  for i = 1, MAX_ITEMS do
    local b = buttons[i]
    if b == Nav.cur then b:LockHighlight() else b:UnlockHighlight() end
  end
end)
