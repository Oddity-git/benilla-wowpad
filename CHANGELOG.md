# Changelog

## 0.2.1

**Update:** pull WowPad and run the installer again. Needed on the newest benilla: upstream
rewrote the action bar and the pick code, and 0.2.0's two engine patches no longer fit it (the
installer stopped with "patch 01-client-action-slots does not fit"). Both patches are refreshed;
the installer takes an older copy of them out first, and keeps using the older copy on a benilla
that is not new enough for the refreshed one.

- The engine patches 01 (the gamepad bar's own action slots) and 02 (crosshair tooltips while the
  camera turns) fit upstream benilla as of 25 Oct 2026 and the physics fork built on it.
- `tools/update-benilla-personal.sh`: when the physics fork changes the lines WowPad's engine
  patches sit on, the patch commits are taken out before the merge (the patch step puts the
  current ones back), instead of stopping on a conflict.

## 0.2.0

**Update:** pull WowPad and run the installer again; it adds the two engine patches (01 and 02)
and skips the ones already in.

- Window navigation: holding LT or RT no longer sends the focus back to the first window, and
  LT / RT swap windows whenever more than one is open, tabbed or not.
- L3 disenchant works on the newest Benilla: the item pick now runs through a keybinding, as the
  game only accepts it from an input event.
- A cast bar of WowPad's own (player casts and channels, movable), with `/wp castbar` to switch it.
- Compare plates (hold Y) use the stock shopping tooltips and never show a blank plate.

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
