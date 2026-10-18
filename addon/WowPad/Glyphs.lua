-- Glyphs.lua - button names and icons in the chosen style (Xbox or PlayStation).
--
-- Face buttons are icons (Textures/btn_xb_*.tga, btn_ps_*.tga); the other buttons are short names:
--   Xbox:        A B X Y   LB RB   LT RT   Back   Start
--   PlayStation: Cross Circle Square Triangle   L1 R1   L2 R2   Share  Options
-- 1.12 has no inline texture escape (|T), so text gets the names and the icons come only from
-- WP.NewKeyLine, which lays a line out as icon and text pieces.
--
--   WP.Keys(s)  a string of button names ("LB / RB", "Back + A"): each name in the chosen style.
--   WP.Text(s)  ordinary text with button names in braces ("press {A} to jump").
--   WP.KeyText(fontString, raw, isText)  set a label now and again whenever the style changes.

local WP = WowPad
WP.styleHooks = WP.styleHooks or {}
local TEX = "Interface\\AddOns\\WowPad\\Textures\\"

local FACE = {
  xbox = { A = "btn_xb_a", B = "btn_xb_b", X = "btn_xb_x", Y = "btn_xb_y" },
  ps   = { A = "btn_ps_cross", B = "btn_ps_circle", X = "btn_ps_square", Y = "btn_ps_triangle" },
}
local NAMES = {
  xbox = {},
  ps   = { A = "Cross", B = "Circle", X = "Square", Y = "Triangle",
           LB = "L1", RB = "R1", LT = "L2", RT = "R2", Back = "Share", Start = "Options" },
}

function WP.ButtonStyle()
  return (WowPadDB and WowPadDB.buttonStyle == "ps") and "ps" or "xbox"
end

-- Texture path of a face button's icon ("A", "B", "X" or "Y").
function WP.FaceTexture(name)
  local f = FACE[WP.ButtonStyle()][name]
  return f and (TEX .. f)
end

local function Name(w)
  return NAMES[WP.ButtonStyle()][w]
end

function WP.KeysPlain(s)
  if not s then return s end
  return (string.gsub(s, "%a%w*", function(w) return Name(w) or w end))
end

-- A string of button names as pieces for layouts that place icons themselves:
-- { tex = path } for face buttons, { text = "..." } for everything else.
function WP.KeyPieces(s)
  local out, i = {}, 1
  local style = WP.ButtonStyle()
  local function addText(t)
    if t == "" then return end
    local last = out[table.getn(out)]
    if last and last.text then last.text = last.text .. t else table.insert(out, { text = t }) end
  end
  while true do
    local a, b = string.find(s, "%a%w*", i)
    if not a then addText(string.sub(s, i)); break end
    addText(string.sub(s, i, a - 1))
    local w = string.sub(s, a, b)
    local f = FACE[style][w]
    if f then table.insert(out, { tex = TEX .. f }) else addText(NAMES[style][w] or w) end
    i = b + 1
  end
  return out
end

-- A line of hints ({ key = "A", text = "Select" }, ...) laid out piece by piece: icon, button
-- name, words, each placed by its middle on the line's centre. The frame sizes itself to fit.
--   local line = WP.NewKeyLine(parent, "GameFontHighlightSmall", 18)
--   line:SetPoint(...); line:SetParts(parts)
function WP.NewKeyLine(parent, font, icon)
  local line = CreateFrame("Frame", nil, parent)
  icon = icon or 18
  line:SetHeight(icon)
  line:SetWidth(1)
  local pool = { tex = {}, fs = {} }
  local function Piece(kind, n)
    if not pool[kind][n] then
      if kind == "tex" then
        pool.tex[n] = line:CreateTexture(nil, "OVERLAY")
        pool.tex[n]:SetWidth(icon)
        pool.tex[n]:SetHeight(icon)
      else
        pool.fs[n] = line:CreateFontString(nil, "OVERLAY", font or "GameFontHighlightSmall")
      end
    end
    return pool[kind][n]
  end
  line.SetParts = function(self, parts, gap)
    self.parts, self.gap = parts, gap
    local nt, nf, x = 0, 0, 0
    for pi = 1, table.getn(parts) do
      local part = parts[pi]
      if pi > 1 then x = x + (gap or 4) end
      local pieces = WP.KeyPieces(part.key)
      table.insert(pieces, { text = " " .. part.text, plain = true })
      for k = 1, table.getn(pieces) do
        local pc = pieces[k]
        local r
        if pc.tex then
          nt = nt + 1; r = Piece("tex", nt)
          r:SetTexture(pc.tex)
        else
          nf = nf + 1; r = Piece("fs", nf)
          r:SetText(pc.plain and pc.text or ("|cffffd100" .. pc.text .. "|r"))
        end
        r:ClearAllPoints()
        r:SetPoint("LEFT", self, "LEFT", x, 0)
        r:Show()
        x = x + (pc.tex and (icon + 1) or (r:GetStringWidth() or 0))
      end
    end
    for i = nt + 1, table.getn(pool.tex) do pool.tex[i]:Hide() end
    for i = nf + 1, table.getn(pool.fs) do pool.fs[i]:Hide() end
    self:SetWidth(math.max(x, 1))
    return x
  end
  table.insert(WP.styleHooks, function() if line.parts then line:SetParts(line.parts, line.gap) end end)
  return line
end

-- One button as text: its name in the chosen style, gold.
local function Key(name)
  local n = Name(name) or (FACE.xbox[name] and name)
  if n then return "|cffffd100" .. n .. "|r" end
  return nil
end

function WP.Keys(s)
  if not s then return s end
  return (string.gsub(s, "%a%w*", function(w) return Key(w) or Name(w) or w end))
end

function WP.Text(s)
  if not s then return s end
  return (string.gsub(s, "{(%a%w*)}", function(w) return Key(w) or w end))
end

local registered = {}
function WP.KeyText(fs, raw, isText)
  registered[fs] = { raw, isText }
  fs:SetText(isText and WP.Text(raw) or WP.Keys(raw))
end

local function Refresh()
  for fs, r in pairs(registered) do
    fs:SetText(r[2] and WP.Text(r[1]) or WP.Keys(r[1]))
  end
  for i = 1, table.getn(WP.styleHooks) do pcall(WP.styleHooks[i]) end
  if WP.UpdateStatus then WP.UpdateStatus() end
end

function WP.SetButtonStyle(style)
  WowPadDB.buttonStyle = (style == "ps") and "ps" or "xbox"
  Refresh()
end

-- Labels made while the addon loads come before the saved settings: redo them once those are in.
local ev = CreateFrame("Frame")
ev:RegisterEvent("PLAYER_LOGIN")
ev:SetScript("OnEvent", Refresh)
