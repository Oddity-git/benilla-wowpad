-- BlizzBars.lua - hide Blizzard's bottom bars (like Bartender), /wp blizz or the main menu.
--
-- Frames are re-parented to a hidden frame instead of hidden, so stock code that shows them later
-- (stance change, level up) cannot bring them back. Their key bindings still work. Off by
-- default. While they are hidden WowPad shows its own XP, reputation and pet bars (ExtraBars.lua);
-- bags and menus are on the Start wheel.

local WP = WowPad

local hider = CreateFrame("Frame", "WowPadBlizzHider", UIParent)
hider:Hide()

local FRAMES = {
  "MainMenuBar",            -- main action bar, art, XP/rep bars, bag buttons, micro menu
  "MultiBarBottomLeft", "MultiBarBottomRight",
  "MultiBarLeft", "MultiBarRight",
  "ShapeshiftBarFrame",     -- stance / form bar
  "PetActionBarFrame",
  "BonusActionBarFrame",    -- warrior stances, druid forms, rogue stealth bar
}

local original = {}         -- frame -> original parent

local function Apply(hide)
  for k = 1, table.getn(FRAMES) do
    local f = getglobal(FRAMES[k])
    if f then
      if hide then
        if not original[f] then original[f] = f:GetParent() end
        f:SetParent(hider)
      elseif original[f] then
        f:SetParent(original[f])
      end
    end
  end
end

function WP.ToggleBlizzBars()
  WowPadDB.hideBlizz = not WowPadDB.hideBlizz
  Apply(WowPadDB.hideBlizz)
  if WP.Extra then WP.Extra.ApplyShown() end
  WP.Print("Blizzard bars and bottom art: " .. (WowPadDB.hideBlizz and "hidden" or "shown"))
end

table.insert(WP.setupHooks, function()
  if WowPadDB.hideBlizz then Apply(true) end
end)
