# Changelog

## Unreleased

- Quick-use quest items: LT + RT + L3 uses the quest item in your bags, with a hint above the bar
  that lights up when you are in the right spot (its zone, the altar or campfire its spell needs,
  or the target or object its text names, is right here). `/wp questitem` turns it off.
  On your own cMaNGOS server the update script exports every quest item's spots from its world
  database, so the hint knows the right spot for every quest, not just a guess.
- The WowPad button sits inside the game menu, under Macros, instead of under the menu where
  the button hint covered it.
- The lite bar's trigger hint (LT, RT, LT+RT) shows its button names again on the newest Benilla.
- A (jump) and L3 (auto-run) work on the newest Benilla, which blocks addons from calling
  movement directly and showed a "WowPad has been blocked" popup instead.
- The target menu (Y) works again, in a fight too: the camera and sticks keep working while it
  is open, D-pad up / down picks a row, A uses it, B or Y closes it.
- Put spells and items on the bar with the pad: Y on a spell in the spellbook (or Put on bar in
  a bag item's L3 menu), then press the bar button it should go on. B cancels.
- L3 in the bags offers Disenchant on green or better gear when you know Enchanting.
- Compare and preview (Y) work on loot rolls, loot window slots, vendor items and quest rewards,
  with a Y hint on loot rolls and the loot window.
- The loot window's slots can be selected and looted with the pad (it starts on the first one).
- Windows open on a sensible spot: the map in its middle, quest windows on Accept / Complete or
  the first quest, bags on the first slot.
- `/wp save` saves your settings without logging out (it reloads the UI).
- The X icon, the crosshair dot and the centre-line snap now follow the UI scale setting.
- Crosshair tooltips also work on what you are fighting.
- Crosshair tooltips are live: what is under the crosshair shows while the camera turns, so
  the camera no longer pauses when the stick rests (`/wp peek` brings the pause back). Needs the
  new engine patch `02-look-hover`; the installer applies it.
- Interact prompt: an X icon shows over what X would use when it is in reach, and X uses it
  without changing your target.
- WowPad no longer patches benilla's interact code: it uses benilla's own API for it, so that
  patch is gone.
- LT / RT and LB / RB swap windows by where they sit on screen, and stop at the last one.
- Bar and mover positions stay put (a centred bar stays centred) when the UI scale changes.
- Bag addons like OneBag get the bag hints, and the hints show Y preview / compare.
- Compare (hold Y) works again on the newest benilla.

## 0.1.0

First release of WowPad on [benilla](https://github.com/samwhosung/benilla), ported from
WowPad 1.4.2 for WoW 3.3.5.

**Install:** download `benilla-wowpad-0.1.0.zip` below, unzip it, and double-click
`Install WowPad (Windows).bat` or `install.sh` (Linux). It asks for your benilla folder, adds
WowPad and builds it. Prefer doing it by hand? See the README's "The usual way (git)". You need
what benilla itself needs to build: Git and Rust.

- Console-style play on a gamepad: sticks move and look, four action sets on LT / RT / LT+RT,
  a utility ring, LB / RB targeting with a healer mode that cycles the party.
- Its own controller bar with its own action slots (range, usable and cooldown like any bar),
  saved per character: your normal action bars stay as they are, with or without WowPad.
- Lite bar (one set at a time), with an optional row of the cooldowns on the sets you can't see.
- Menus on the D-pad: tabs on LB / RB, quest tracking on X, B closes the window you're on,
  loot rolls start on Need, Y previews and compares bag gear.
- On-screen keyboard for chat and text fields, radial main menu, target menu, world map cursor,
  crosshair with tooltips, pointer mode, Controller Map, welcome window.
- X interacts with your target (talk, loot everything, gather, open) through a small engine
  patch; the installer applies it to any benilla version and keeps a fork's own features.
- PlayStation labels picked up automatically; a Swap X / Y option for pads that report them
  backwards.
