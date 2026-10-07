-- Signals.lua - the signals benilla-wowpad sends, the slot order and the set names shared by
-- the other files. On 3.3.5 each signal was a key the DLL pressed; here each is a binding command
-- (Bindings.xml, WOWPAD_<NAME>) that benilla-wowpad runs, down and up, the way a key would.
-- Lua 5.0 and the 1.12 API throughout: no #, %, ..., string methods, or self in handlers.

WowPad = WowPad or {}

-- The 8 slot buttons, in slot order (1..8).
WowPad.SLOT_SIGNALS = { "DPAD_UP", "DPAD_DOWN", "DPAD_LEFT", "DPAD_RIGHT", "A", "B", "X", "Y" }
WowPad.SLOT_LABELS  = { "D-pad Up", "D-pad Down", "D-pad Left", "D-pad Right", "A", "B", "X", "Y" }
WowPad.SET_NAMES    = { [0] = "Default", [1] = "Left (LT)", [2] = "Right (RT)", [3] = "Bottom (LT+RT)" }
WowPad.SLOT_INDEX = {}
for i = 1, 8 do WowPad.SLOT_INDEX[WowPad.SLOT_SIGNALS[i]] = i end
