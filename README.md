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

## Install into a benilla checkout

```sh
cd path/to/benilla
git clone https://github.com/Oddity-git/benilla-wowpad crates/benilla-wowpad
git apply -3 crates/benilla-wowpad/patches/benilla-engine.patch
cargo build --release -p benilla-wowpad
```

benilla's workspace takes every folder under `crates/`, so nothing else needs registering.

`patches/benilla-engine.patch` is the small engine change WowPad needs: X interacts with the
target the way a right-click on it would (and loots it all), and action slots 121-256 are
client-only, so the controller bar has slots of its own that never touch your normal action bars.
It was made against benilla `main`; `-3` merges it where benilla has moved on.

Already applied an older `benilla-engine.patch`? Apply only the newer pieces under
`patches/updates/`, in order (`git apply -3 crates/benilla-wowpad/patches/updates/01-client-action-slots.patch`).

On a benilla fork with the ragdoll physics, add its feature:

```sh
cargo build --release -p benilla-wowpad --features benilla-app/ragdoll
```

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
