<h1 align="center">benilla-wowpad</h1>

Native-feel controller support for [benilla](https://github.com/samwhosung/benilla), the
from-scratch WoW 1.12.1 client in Rust: move and look with the sticks, a round controller action
bar on the triggers, menus you drive with the D-pad, a radial main menu and a crosshair. It is
[WowPad](https://github.com/Oddity-git/WoW-Pad), my controller addon for WoW 3.3.5, ported to
benilla. Client-side only; nothing on the server changes.
<p align="center">
*some images were pulled from the original addon, minor variance may exist. 
</p>
<p align="center">
<img width="838" height="421" alt="WowPad" src="https://github.com/user-attachments/assets/922fa9c7-8896-4ee9-a7da-88c9d92bf181" />
</p>

<p align="center">Full D-pad menu navigation</p>
<p align="center">
<img width="1530" height="742" alt="Full D-pad menu navigation" src="https://github.com/user-attachments/assets/80695d57-3a9c-4ac0-bf9a-e7d5c3f5f139" />
</p>

<p align="center">Edit mode with centre-line snapping</p>
<p align="center">
<img width="1248" height="902" alt="Edit mode with centre-line snapping" src="https://github.com/user-attachments/assets/9287c97e-e8c8-44ac-b17e-1777f4f65516" />
</p>

<p align="center"><sub>Screenshots are from WowPad on 3.3.5; the benilla port has the same bar, menus and wheels.</sub></p>

On 3.3.5 WowPad is a `version.dll` that reads the pad plus an addon. Here the DLL's half is this
crate, running inside benilla (no DLL, no key-press tricks, nothing for antivirus to flag), and the
addon is ported to the 1.12 API. The binary, `benilla-wowpad`, is benilla with WowPad on top. The
addon installs itself into `benilla-config/AddOns/WowPad` when the game starts.

## What it does

- Console-style play on a gamepad: left stick moves, right stick turns the camera, four action
  sets on LT / RT / LT+RT, a utility ring, LB / RB targeting (healer mode cycles the party).
- Its own controller bar with its own action slots (range, usable and cooldown like any bar),
  saved per character, plus its own XP, reputation and pet bars when the Blizzard bars are hidden.
- An on-screen keyboard for chat (Back + A) and text fields, a Controller Map, a welcome window,
  and a party highlight in healer mode.
- Start opens a radial main menu; Y opens a target menu; the D-pad and A drive any window.
- A drawn pointer for pointer mode (R3) and a crosshair whose tooltips follow it as the camera
  turns.
- A world map cursor with coordinates.
- Options window: `/wp options`, the minimap button, or the WowPad button under the Esc menu.
- Unmapped pads on Linux (8BitDo Ultimate 2, Steam Controller through Steam Input) are detected.

## Install

WowPad is a crate plus a small engine patch that goes on top of a benilla checkout
(<https://github.com/samwhosung/benilla>, or any fork of it). It needs benilla's `main` branch
from after the 0.2.0 release: 0.2.0 itself predates the API that lets a crate build on top of
benilla, so WowPad can't be built on it. You need what benilla itself needs
to build: Git, and Rust from <https://rustup.rs> (on Windows, with the MSVC build tools the Rust
installer sets up).

### The usual way (git)

From your benilla folder:

```sh
git clone https://github.com/Oddity-git/benilla-wowpad crates/benilla-wowpad
git apply -3 crates/benilla-wowpad/patches/01-client-action-slots.patch
git apply -3 crates/benilla-wowpad/patches/02-look-hover.patch
cargo build --release -p benilla-wowpad
```

benilla's workspace takes every folder under `crates/`, so nothing else needs registering. To
update, `git -C crates/benilla-wowpad pull`, apply any new numbered patch in `patches/`, and build
again. If a patch says it does not apply, that patch is already in, or your benilla moved past it:
see the installer below, which sorts that out for you.

### The easier way (installer)

This is something I'm trying out, this repository also ships an installer, for anyone who would rather
not apply patches by hand. It does exactly the steps above. It is a plain text script you can read
before running, it downloads nothing, needs no admin rights, and only changes the benilla folder
you pick.

1. Get WowPad: `benilla-wowpad-<version>.zip` from the
   [Releases page](https://github.com/Oddity-git/benilla-wowpad/releases) (unzip it), or
   `git clone https://github.com/Oddity-git/benilla-wowpad`.
2. Double-click the installer in that folder:
   - **Windows:** `Install WowPad (Windows).bat`
   - **Linux:** `install.sh`, then choose **Run** / **Execute** (on GNOME, enable running
     executable text files in Files' settings first). It opens a terminal window to show progress.
3. Pick your benilla folder when it asks (it finds it by itself when WowPad sits inside
   `benilla/crates/`, or is the only benilla folder next to it). The first build takes a while;
   the window stays open at the end so you can read the result.

From a terminal instead: `bash install.sh path/to/benilla`, or on Windows
`powershell -ExecutionPolicy Bypass -File install.ps1 C:\path\to\benilla`
(`-ExecutionPolicy Bypass` lets this one script run without changing any Windows setting).

To update later, get the new WowPad (or update benilla) and run the installer again: patches
already in are skipped, so it is safe to run any number of times.

What it does differently from the manual steps:

- It applies the patches in `patches/` in their numbered order, like a load order, each the first
  way that fits: as is, then by a three-way merge, then hunk by hunk by its nearest lines (for
  forks that changed the code around it). A patch that fits no way stops the installer, which
  names the files and changes nothing after it.
- A patch that is already in is skipped.
- `--no-build`, `--patches-only` (for your own update scripts) and `--remove` (takes the patches
  back out and deletes the crate); in PowerShell `-NoBuild`, `-PatchesOnly`, `-Remove`.
- It builds with the same features your benilla's own game builds with by default, so a fork's
  extras stay in. (By hand: add `--features benilla-app/<name>` for each.) More go in
  `WOWPAD_FEATURES="a,b"` (`$env:WOWPAD_FEATURES="a,b"` in PowerShell).
- A WowPad folder already inside `crates/` (cloned or linked there) is used as it is.

### What the patches change

- `01-client-action-slots`: action slots 121-256 are client-only, so the controller bar has slots
  of its own that never touch your normal action bars.
- `02-look-hover`: while the camera turns, benilla's mouseover (the unit or object, its tooltip and
  highlight) follows the crosshair instead of switching off, so tooltips show live without the
  camera pausing, also with a nameplate under the hidden pointer (as in a fight). Without WowPad
  driving it, nothing changes.

A daily check (`.github/workflows/upstream.yml`) installs WowPad onto the newest benilla `main`
on Linux and Windows and builds it, so a patch that stops fitting gets refreshed here.
`patches/updates/` is kept for update scripts written before the installer; new installs ignore it.

## Run

```sh
WOW_HOST=your.server ./target/release/benilla-wowpad
```

Windows, in PowerShell: `$env:WOW_HOST="your.server"; .\target\release\benilla-wowpad.exe`

The addon installs itself into `benilla-config/AddOns/WowPad` at start, and the pad settings
are `benilla-config/wowpad.ini` (written with defaults the first time).

**Steam Controller:** add `benilla-wowpad` to Steam as a non-Steam game and turn Steam Input on.
On Wayland, launch it as an X11 window so Steam can see it:
`env -u WAYLAND_DISPLAY WOW_HOST=your.server %command%` in its launch options.

### First time in game

1. The **welcome window** opens: it checks your controller and shows where everything lives.
   Reopen it any time with `/wp firsttime`.
2. Pick up the controller: WowPad switches to controller mode by itself. Touching the mouse or
   keyboard switches back to normal desktop control at once.
3. Left-click the **gamepad button on the minimap** (or Start > page 3 > **Edit Bar**, or
   `/wp edit`): drag spells, items and macros onto the round slots. Drag bars to move them (they
   snap to the screen's centre line), mouse wheel to resize. Click again to finish. The controller
   bar has its own slots, so your normal action bars stay as they are, with or without WowPad.
4. Right-click the minimap button (or Esc > **WowPad**, or `/wp options`) for sensitivity and
   other options.

## Controls
<p align="center">
<img width="764" height="539" alt="WowPad" src="https://github.com/user-attachments/assets/142043c4-8307-4c3b-97b4-083cbf580b5e" />
</p>

| Button | Does |
|---|---|
| Left stick | Move (optional: slight tilt walks, full tilt runs) |
| Right stick | Camera. In menus and pointer mode: the pointer |
| A | Jump |
| B | Clear target / back out of menus |
| X | Interact with what the prompt shows (talk, loot everything, gather, open) without targeting it; with no prompt, your target + start attacking a hostile one |
| Y | Target menu |
| LB / RB | Target nearest friendly / enemy (can be swapped in Options; see Healer mode) |
| LB + RB held | Right stick zooms the camera |
| D-pad | 4 action slots |
| LT / RT / LT+RT held | Left / right / bottom set: D-pad + A/B/X/Y = 8 more slots each |
| L3 | Autorun |
| R3 | Pointer mode: right stick moves a cursor |
| Start | Close windows, open the radial main menu |
| Back | Tap = map, hold = bags |
| Back + A | On-screen keyboard (see Chat); in the keyboard or chat box: send |
| Back + B | Esc: close the keyboard or chat |
| Back + Start held 1 s | Kill switch: WowPad stops sending anything (again to turn it back on) |

The Controller Map (Start > page 2 > **Controller**, or `/wp map`) shows this in game.
**PlayStation pad?** It is picked up by itself, or choose PlayStation buttons in Options: hints
and the bar then show ✕ ○ □ △ and L1 / R1 / L2 / R2. Pads that report X and Y swapped: Options >
**Swap X / Y buttons**.

### Interact prompt

When something X can use is in reach (an NPC with a service, a corpse to loot or skin, a chest,
herb, vein or mailbox), an X icon shows over it. X then acts on it without targeting it, so your
target stays yours. In a fight with a target, X stays on the target. `/wp prompt` turns the icon
off.

### In menus (a window open, out of combat)

| Button | Does |
|---|---|
| D-pad / right stick | Move the selection (at the end of a list, the D-pad scrolls it) |
| A | Click |
| X | Right-click (use, equip, sell). Quest log: track / untrack the quest |
| Y tap / hold | Preview bag gear in the dressing room / compare it with what you wear |
| L3 (in bags) | Item actions: Put on bar, Disenchant (when you know it), Destroy (asks first), Cancel (preselected) |
| Y (in the spellbook) | Put the selected spell on the bar: then press a D-pad direction, or hold LT / RT / both and press a button. B cancels |
| LB / RB | Switch tabs (Character, Social, Talents, Auction House, Merchant; spellbook: the school tabs). No tabs: switch window |
| LT / RT | In a window with tabs: switch between open windows |
| B | Close the window you're on (Esc menu: Return to Game; loot roll: Pass) |

A hint bar under the window shows what the buttons do for the selected item, and each open window
remembers its selection. Group loot rolls get the selection with Need (or Greed) selected; in
combat they leave your controls alone, so roll when the fight is over.

### Chat: on-screen keyboard
<p align="center">
<img width="507" height="561" alt="WowPad" src="https://github.com/user-attachments/assets/3bef566f-1f9a-4921-88bc-1b87b1b69a8c" />
</p>

**Back + A** opens a small keyboard above the chat window (controller mode, out of combat). A on a
text field (mail, auction search...) opens it for that field. It's meant for short messages and
commands like `/reload`; a real keyboard works as usual.

| Button | Does |
|---|---|
| D-pad | Move between keys |
| A / X | Type / type a capital |
| Y | Space |
| B | Delete a letter (on an empty line: close) |
| LB / RB | Channel: Say, Party, Guild, Raid, Reply |
| Start or Back + A | Send |
| Back + B | Close |

Don't need it? Turn off **On-screen keyboard** in Options: Back + A then opens the normal chat box.

### World map
<p align="center">
<img width="861" height="632" alt="WowPad" src="https://github.com/user-attachments/assets/c5e8a8b3-ccc8-4eb8-9f64-e6897c585ebc" />
</p>

The map gets its own cursor with cursor and player coordinates. Right stick moves it, A zooms in
on the zone under it (on a pin: clicks the pin), X zooms out, the D-pad jumps between pins and
map buttons, and B backs out a level (zone, continent, world), then closes.

### Ground-targeted spells

Spells you aim at the ground (Blizzard, Flare, ...): aim with the camera, then press **A** or
**the same button again** to place the spell at the crosshair. **B** cancels.

### Healer mode
<p align="center">
<img width="602" height="611" alt="WowPad" src="https://github.com/user-attachments/assets/9e0cbfed-3c54-4531-bf85-1073ce836aa8" />
</p>

Off by default: Options > **Healer mode**.

- **Tap** your ally bumper (LB, or RB if you swapped them) to target your last party pick (you at
  first).
- **Hold** it and flick the right stick **down / up** for the next / previous party member.
- A gold frame briefly marks the picked member's unit frame. Works in combat.

### Utility ring
<p align="center">
<img width="861" height="632" alt="WowPad" src="https://github.com/user-attachments/assets/2a346832-3a23-440e-83eb-79854c0ecf1a" />
</p>

Eight spells, items or macros on one button. Options > **Utility ring**: pick the button that
opens it, then fill its eight wedges in **Edit bar layout**. In game: hold the button, point the
right stick at a wedge, let go to use it; let go in the middle to cancel. Works in combat.

### Lite bar
<p align="center">
<img width="861" height="632" alt="WowPad" src="https://github.com/user-attachments/assets/0169e017-cb97-4dfe-8d9e-e57393677e01" />
</p>

Options > **Lite bar** shows one cluster instead of four: your default set, and while you hold LT,
RT or both, that set in its place (a small badge says which). In **Edit bar layout**, tabs above
it pick which set you're filling.

New in the benilla port: **Lite: show hidden cooldowns** (on by default) adds a small row beside
the bar with the cooldowns on the sets you can't see (and the utility ring); each icon goes away
when it is ready. Move or resize it in **Edit bar layout**, or turn it off in Options.

### Radial menu (Start)
<p align="center">
<img width="505" height="519" alt="WowPad" src="https://github.com/user-attachments/assets/de2f0a1d-ddc8-4b1c-8556-8d99e423023b" />
</p>

A radial wheel with three pages (LB / RB). Point the right stick at a wedge and press A; B or
Start closes it. In **Edit bar layout** it shows in a blue box: drag it to move it, mouse wheel to
resize.

## Options

`/wp options`, right-click the minimap button, or the **WowPad** button under the Esc menu. Every
setting applies at once; numbers are steppers the D-pad can work.

- **Sticks:** camera, pointer and zoom speed, peek delay, invert camera, smooth camera, walk/run
  by stick tilt.
- **Crosshair:** dot on/off, and the old "peek" (camera look pauses when the stick rests), now
  off by default.
- **Buttons:** X also starts auto attack, swap LB / RB, healer mode, PlayStation labels, swap
  X / Y, on-screen keyboard, utility ring.
- **Bars:** controller bar always visible, lite bar, lite hidden cooldowns, hide Blizzard's bars
  (WowPad's own XP, reputation and pet bars take their place), minimap button, bar size, edit
  layout.
- **Messages:** status line, debug messages.

Advanced settings (deadzones, speeds) are in `benilla-config/wowpad.ini`, written with defaults
the first time; restart the game after editing it.

Chat commands: `/wp options`, `/wp edit`, `/wp map`, `/wp firsttime`, `/wp keyboard`, `/wp bar`,
`/wp lite`, `/wp blizz`, `/wp castbar`, `/wp compare`, `/wp crosshair`, `/wp peek`,
`/wp scale 0.8`, `/wp sens 0.7`, `/wp psens 1.0`, `/wp ring 3_8`, `/wp ps`, `/wp xbox`,
`/wp status`, `/wp debug`, `/wp save`.

Settings are saved when the UI shuts down: at logout, quit, or a UI reload. `/wp save` reloads
the UI to save them without logging out.

## Troubleshooting

- **The pad does nothing:** WowPad logs what it sees to benilla's log (`wowpad:` lines). Steam
  Controller: add `benilla-wowpad` to Steam as a non-Steam game with Steam Input on (see Run).
- **The installer stops on a patch:** get the newest WowPad and run it again. If it still stops,
  open an issue with the installer's output; a daily check usually catches this first.
- **Stuck input / something odd:** hold Back + Start for 1 second (kill switch), or touch the
  mouse or keyboard.
- **Crosshair stuck somewhere other than its usual spot:** press R3 twice.
- **A Lua error mentions WowPad:** open an issue with the error text.

## How this was made

WowPad is vibe-coded: every line of the 3.3.5 version, and of this port, was written by Claude
(Anthropic's AI) while I tested each build in game and sent back logs, screenshots and errors.
The design and testing are a player's, the code is an AI's. If something breaks on your setup,
open an issue with what you were doing.

## License

MIT, see [LICENSE](LICENSE).
