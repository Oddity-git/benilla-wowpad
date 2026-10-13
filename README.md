# benilla-wowpad

[WowPad](https://github.com/Oddity-git/WoW-Pad), my controller addon for WoW 3.3.5, ported to
[benilla](https://github.com/samwhosung/benilla), the from-scratch 1.12.1 client in Rust.

On 3.3.5 WowPad is a `version.dll` that reads the pad plus an addon. Here the DLL's half is this
crate, running inside benilla, and the addon is ported to the 1.12 API. The binary,
`benilla-wowpad`, is benilla with WowPad on top.

## What it does

- Console-style play on a gamepad: left stick moves, right stick turns the camera, four action
  sets on LT / RT / LT+RT, a utility ring, LB / RB targeting (healer mode cycles the party).
- Its own controller bar with its own action slots (range, usable and cooldown like any bar),
  saved per character, plus its own XP, reputation and pet bars when the Blizzard bars are hidden.
- An on-screen keyboard for chat (Back + A) and text fields, a Controller Map, a welcome window,
  and a party highlight in healer mode.
- Start opens a radial main menu; Y opens a target menu; the D-pad and A drive any window.
- A drawn pointer for pointer mode (R3) and a crosshair with tooltips when the stick rests.
- A world map cursor with coordinates.
- Options window: `/wp options`, the minimap button, or the WowPad button under the Esc menu.
- Unmapped pads on Linux (8BitDo Ultimate 2, Steam Controller through Steam Input) are detected.

## Install

You need a benilla checkout (`git clone https://github.com/samwhosung/benilla`, or any fork of it)
and Rust (https://rustup.rs). Then, from anywhere:

```sh
git clone https://github.com/Oddity-git/benilla-wowpad
bash benilla-wowpad/install.sh path/to/benilla
```

That copies WowPad into `crates/benilla-wowpad`, applies its engine patches and builds. To update
later, pull either side (`git -C benilla-wowpad pull`, or a benilla update) and run the same line
again: patches already in are skipped, so it is safe to run any number of times.

**How the patches work.** `patches/` holds WowPad's small engine changes as a numbered series,
applied in order like a load order: `00-soft-interact` (X interacts with the target the way a
right-click on it would, and loots it all) and `01-client-action-slots` (action slots 121-256 are
client-only, so the controller bar has slots of its own that never touch your normal bars). Each
one is applied the first way that fits: as is, then by a three-way merge, then hunk by hunk by its
nearest lines (for forks that changed the code around it). One that fits no way stops the
installer, which names the files and changes nothing after it. A daily check
(`.github/workflows/upstream.yml`) installs onto the newest benilla `main` and builds, so a patch
that stops fitting gets refreshed here.

Other options: `--no-build`, `--patches-only` (for your own update scripts), `--remove` (takes the
patches back out and deletes the crate). Forks with the ragdoll physics get its feature switched on
automatically; other cargo features go in `WOWPAD_FEATURES="a,b"`.

`patches/updates/` is kept for update scripts written before the installer; new installs ignore it.

## Run

```sh
WOW_HOST=your.server ./target/release/benilla-wowpad
```

The addon installs itself into `benilla-config/AddOns/WowPad` at start, and the pad settings
are `benilla-config/wowpad.ini` (written with defaults the first time).

**Steam Controller:** add `benilla-wowpad` to Steam as a non-Steam game and turn Steam Input on.
On Wayland, launch it as an X11 window so Steam can see it:
`env -u WAYLAND_DISPLAY WOW_HOST=your.server %command%` in its launch options.

## License

MIT, see [LICENSE](LICENSE).
