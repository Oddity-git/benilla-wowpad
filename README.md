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

WowPad is a crate plus a small engine patch that goes on top of a benilla checkout
(<https://github.com/samwhosung/benilla>, or any fork of it). You need what benilla itself needs
to build: Git, and Rust from <https://rustup.rs> (on Windows, with the MSVC build tools the Rust
installer sets up).

### The usual way (git)

From your benilla folder:

```sh
git clone https://github.com/Oddity-git/benilla-wowpad crates/benilla-wowpad
git apply -3 crates/benilla-wowpad/patches/00-soft-interact.patch
git apply -3 crates/benilla-wowpad/patches/01-client-action-slots.patch
cargo build --release -p benilla-wowpad
```

benilla's workspace takes every folder under `crates/`, so nothing else needs registering. To
update, `git -C crates/benilla-wowpad pull`, apply any new numbered patch in `patches/`, and build
again. If a patch says it does not apply, that patch is already in, or your benilla moved past it:
see the installer below, which sorts that out for you.

### The easier way (installer)

Not something other forks do: this repository also ships an installer, for anyone who would rather
not apply patches by hand. It does exactly the steps above. It is a plain text script you can read
before running, it downloads nothing, needs no admin rights, and only changes the benilla folder
you point it at.

Linux and macOS (and Git Bash on Windows):

```sh
git clone https://github.com/Oddity-git/benilla-wowpad
bash benilla-wowpad/install.sh path/to/benilla
```

Windows, in PowerShell:

```powershell
git clone https://github.com/Oddity-git/benilla-wowpad
powershell -ExecutionPolicy Bypass -File benilla-wowpad\install.ps1 C:\path\to\benilla
```

(`-ExecutionPolicy Bypass` lets this one script run without changing any Windows setting.)

To update later, pull either side (`git -C benilla-wowpad pull`, or a benilla update) and run the
same line again: patches already in are skipped, so it is safe to run any number of times.

What it does differently from the manual steps:

- It applies the patches in `patches/` in their numbered order, like a load order, each the first
  way that fits: as is, then by a three-way merge, then hunk by hunk by its nearest lines (for
  forks that changed the code around it). A patch that fits no way stops the installer, which
  names the files and changes nothing after it.
- A patch that is already in is skipped.
- `--no-build`, `--patches-only` (for your own update scripts) and `--remove` (takes the patches
  back out and deletes the crate); in PowerShell `-NoBuild`, `-PatchesOnly`, `-Remove`.
- Extra cargo features for your benilla build go in `WOWPAD_FEATURES="a,b"`
  (`$env:WOWPAD_FEATURES="a,b"` in PowerShell).

### What the patches change

- `00-soft-interact`: X interacts with your target the way a right-click on it would, and loots
  it all.
- `01-client-action-slots`: action slots 121-256 are client-only, so the controller bar has slots
  of its own that never touch your normal action bars.

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

## License

MIT, see [LICENSE](LICENSE).
