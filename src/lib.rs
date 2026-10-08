//! WowPad on benilla. 1.12.1 has no gamepad, so nothing here is reference behaviour.
//!
//! On 3.3.5 WowPad is two halves: a `version.dll` that reads the pad and presses keys (movement,
//! mouse motion, and "signal" keys the addon binds), and the WowPad addon that draws the bar and
//! decides what each signal does. Here the DLL's half is this crate, in-process: the same mapper
//! (`mapper.cpp`) with the same `wowpad.ini`, but instead of faking key presses it runs the
//! addon's `WOWPAD_<SIGNAL>` binding commands through the UI VM's `execute_binding` (the path a
//! key takes, so a cast is a hardware event), runs the movement commands directly, turns the
//! camera with mouse motion and moves the cursor itself. The addon ([`addon`], embedded and
//! installed into `benilla-config/AddOns/WowPad`) is WowPad ported to the 1.12 API.
//!
//! Each frame the addon answers `WowPad_Frame()`: camera look on, a window open (menu context),
//! a spell waiting for its location, and the options that tune the mapper.

pub mod addon;
pub mod config;
mod glue;
pub mod pad;

use benilla_ui::script::UiScript;
use benilla_world::interact::TargetInteract;
use bevy::input::gamepad::{GamepadConnection, GamepadConnectionEvent};
use bevy::input::keyboard::KeyboardInput;
use bevy::input::mouse::AccumulatedMouseMotion;
use bevy::input::InputSystems;
use bevy::prelude::*;
use bevy::window::{CursorGrabMode, CursorOptions, PrimaryWindow};

use config::Config;
use pad::{Layout, PadState};
use std::collections::HashMap;

/// The WowPad plugin: re-enables bevy's gilrs backend (benilla's boot disables it), keeps the
/// addon installed, and runs [`drive`] after bevy's input update.
pub struct WowPadPlugin;

impl Plugin for WowPadPlugin {
    fn build(&self, app: &mut App) {
        app.add_plugins(bevy::gilrs::GilrsPlugin)
            .insert_resource(Config::load())
            .init_resource::<Mapper>()
            .add_systems(Startup, addon::install_addon)
            .add_systems(PreUpdate, (log_pads, drive).chain().after(InputSystems))
            .add_systems(PostUpdate, hide_os_cursor);
    }
}

/// The eight face and D-pad buttons, in the addon's slot order (1-8), with their signals.
const FACE: [(u32, &str); 8] = [
    (pad::DPAD_UP, "DPAD_UP"),
    (pad::DPAD_DOWN, "DPAD_DOWN"),
    (pad::DPAD_LEFT, "DPAD_LEFT"),
    (pad::DPAD_RIGHT, "DPAD_RIGHT"),
    (pad::A, "A"),
    (pad::B, "B"),
    (pad::X, "X"),
    (pad::Y, "Y"),
];
const FACE_A: usize = 4;
const FACE_B: usize = 5;
const FACE_X: usize = 6;

/// The movement commands for stick up, down, left, right: WowPad moves with W/S and Q/E, which
/// are these on 1.12's default bindings.
const MOVES: [&str; 4] = ["MOVEFORWARD", "MOVEBACKWARD", "STRAFELEFT", "STRAFERIGHT"];

/// Kill switch: Back + Start held this long.
const TOGGLE_HOLD: f64 = 1.0;
/// Re-announce the mode on a press this long after the last time (a `/reload` loses it).
const MODE_RESEND: f64 = 10.0;
/// A bumper held this long alone turns the right stick's up/down into target flicks.
const CYCLE_HOLD: f64 = 0.15;
/// The stick must return to the middle first.
const FLICK_BLOCKED: i8 = 9;

/// What the addon answers each frame.
#[derive(Clone, Copy, Debug, Default)]
struct Frame {
    /// Camera look is on (`IsMouselooking`).
    looking: bool,
    /// A window is open or the pointer mode is on: the addon's menu context.
    menu: bool,
    /// A spell waits for its location (`SpellIsTargeting`).
    aiming: bool,
    /// The options panel's tuning.
    cam_scale: f32,
    ptr_scale: f32,
    zoom_scale: f32,
    /// -1 = the ini's, 0 = off, 1 = on.
    invert_y: i32,
    peek_delay_ms: f64,
    walk_run: bool,
    cam_smooth: bool,
    bumper_flick: bool,
    /// The utility ring's bar slot, `set * 10 + i`; 0 = none.
    ring_slot: i32,
    /// The D-pad navigates the open window and A / X click (the default set only).
    menu_nav: bool,
    /// Where navigation put the pointer: screen fractions from the bottom left, once.
    warp: Option<Vec2>,
}

/// The ground-target placement under way: camera look off, then a left click at the crosshair.
#[derive(Clone, Copy, Debug, Default, PartialEq, Eq)]
enum Place {
    #[default]
    Idle,
    /// Frames left before the click goes down.
    Wait(u8),
    /// The click is down; up next frame.
    Down,
}

/// The mapper's state (`mapper.cpp`'s globals).
#[derive(Resource)]
struct Mapper {
    session: Option<u64>,
    controller: bool,
    enabled: bool,
    focused: bool,
    pointer: bool,
    prev: u32,
    lt: bool,
    rt: bool,
    move_held: [bool; 4],
    walking: bool,
    walk_want_since: Option<f64>,
    click_held: [bool; 2],
    /// A or X held as a mouse click in a window (menu navigation), per face button.
    menu_click: [Option<MouseButton>; 8],
    held_sig: [Option<&'static str>; 8],
    interact_held: bool,
    zoom: bool,
    cycle: u8,
    cycle_want: u8,
    cycle_since: f64,
    flick_dir: i8,
    flick_next: f64,
    ring_held: Option<usize>,
    ring_dir: u8,
    ring_centre_at: f64,
    zoom_acc: f32,
    sm: Vec2,
    cam_active: bool,
    stick_idle_at: f64,
    last_mode_send: f64,
    back_down_at: f64,
    back_hold_sent: bool,
    chord_used: bool,
    chord_start: Option<f64>,
    chord_fired: bool,
    last_slot: Option<usize>,
    eaten: [bool; 8],
    real_travel: f32,
    place: Place,
    /// Keys we pressed (Back + A / B) to let go of next frame.
    keys_down: Vec<KeyCode>,
    /// The pad drives the pointer: the OS cursor stays hidden and the addon draws one.
    hide_os: bool,
    /// The window height last told to the addon (it sizes its drawn pointer by it).
    screen_h: u32,
    announced: bool,
    glue: Vec<(GamepadButton, glue::GlueInput)>,
}

impl Default for Mapper {
    fn default() -> Self {
        Self {
            session: None,
            controller: false,
            enabled: true,
            focused: true,
            pointer: false,
            prev: 0,
            lt: false,
            rt: false,
            move_held: [false; 4],
            walking: false,
            walk_want_since: None,
            click_held: [false; 2],
            menu_click: [None; 8],
            held_sig: [None; 8],
            interact_held: false,
            zoom: false,
            cycle: 0,
            cycle_want: 0,
            cycle_since: 0.0,
            flick_dir: 0,
            flick_next: 0.0,
            ring_held: None,
            ring_dir: 0,
            ring_centre_at: 0.0,
            zoom_acc: 0.0,
            sm: Vec2::ZERO,
            cam_active: false,
            stick_idle_at: 0.0,
            last_mode_send: f64::NEG_INFINITY,
            back_down_at: 0.0,
            back_hold_sent: false,
            chord_used: false,
            chord_start: None,
            chord_fired: false,
            last_slot: None,
            eaten: [false; 8],
            real_travel: 0.0,
            place: Place::Idle,
            keys_down: Vec::new(),
            hide_os: false,
            screen_h: 0,
            announced: false,
            glue: Vec::new(),
        }
    }
}

/// Everything the mapper writes to, borrowed for one frame.
struct Io<'a> {
    script: &'a UiScript,
    cfg: Config,
    now: f64,
    dt: f32,
    window: Option<Mut<'a, Window>>,
    motion: &'a mut AccumulatedMouseMotion,
    mouse: &'a mut ButtonInput<MouseButton>,
    /// Key edges to send after the tick (Back + A / B).
    key_out: Vec<(KeyCode, bool)>,
    /// An Interact to send after the tick.
    interact_out: bool,
    typing: bool,
    frame: Frame,
}

impl Io<'_> {
    /// A signal's key going down or up: the addon's `WOWPAD_<NAME>` binding command.
    fn signal(&self, name: &str, down: bool) {
        let command = format!("WOWPAD_{name}");
        match self.script.execute_binding(&command, down) {
            Ok(_) => {}
            Err(e) => warn!("wowpad: {command} failed: {e}"),
        }
    }

    fn tap(&self, name: &str) {
        self.signal(name, true);
        self.signal(name, false);
    }

    fn binding(&self, command: &str, down: bool) {
        if let Err(e) = self.script.execute_binding(command, down) {
            warn!("wowpad: {command} failed: {e}");
        }
    }

    fn run(&self, lua: &str) {
        if let Err(e) = self.script.run(lua) {
            warn!("wowpad: {lua} failed: {e}");
        }
    }

    /// Where the crosshair is: `CrosshairY` (pixels at 1080 high) above the window centre.
    fn crosshair(&self) -> Option<Vec2> {
        let w = self.window.as_deref()?;
        let up = self.cfg.crosshair_y * w.height() / 1080.0;
        Some(Vec2::new(w.width() / 2.0, w.height() / 2.0 - up))
    }

    /// Move benilla's pointer without a change on the window, so bevy_winit does not ask the OS
    /// to warp its own: Wayland refuses (an error each frame), and while the pad drives the OS
    /// cursor is hidden and the addon draws the pointer. [`hide_os_cursor`] warps the OS cursor
    /// once, when the mouse takes over again.
    fn put_cursor(&mut self, to: Vec2) {
        if let Some(w) = self.window.as_mut() {
            let max = Vec2::new(w.width() - 1.0, w.height() - 1.0);
            w.bypass_change_detection()
                .set_cursor_position(Some(to.clamp(Vec2::ZERO, max.max(Vec2::ZERO))));
        }
    }

    fn move_cursor_by(&mut self, d: Vec2) {
        let Some(at) = self.window.as_deref().map(|w| {
            w.cursor_position()
                .unwrap_or(Vec2::new(w.width() / 2.0, w.height() / 2.0))
        }) else {
            return;
        };
        self.put_cursor(at + d);
    }

    fn park_cursor(&mut self) {
        let Some(target) = self.crosshair() else {
            return;
        };
        let at = self.window.as_deref().and_then(Window::cursor_position);
        if at.is_none_or(|p| p.distance(target) > 1.0) {
            self.put_cursor(target);
        }
    }
}

/// The addon's frame answer; `None` when the addon is not loaded.
fn read_frame(script: &UiScript) -> Option<Frame> {
    #[allow(clippy::type_complexity)]
    let r: Result<
        (
            Option<bool>,
            bool,
            bool,
            f32,
            f32,
            f32,
            i32,
            f64,
            bool,
            bool,
            bool,
            i32,
            bool,
            Option<f32>,
            Option<f32>,
        ),
        _,
    > = script.eval("if WowPad_Frame then return WowPad_Frame() end");
    match r {
        Ok((
            Some(looking),
            menu,
            aiming,
            cs,
            ps,
            zs,
            inv,
            peek,
            walk,
            smooth,
            flick,
            ring,
            menu_nav,
            wx,
            wy,
        )) => Some(Frame {
            looking,
            menu,
            aiming,
            cam_scale: cs,
            ptr_scale: ps,
            zoom_scale: zs,
            invert_y: inv,
            peek_delay_ms: peek,
            walk_run: walk,
            cam_smooth: smooth,
            bumper_flick: flick,
            ring_slot: ring,
            menu_nav,
            warp: wx.zip(wy).map(|(x, y)| Vec2::new(x, y)),
        }),
        Ok(_) => None,
        Err(e) => {
            warn!("wowpad: WowPad_Frame failed: {e}");
            None
        }
    }
}

#[allow(clippy::too_many_arguments)]
fn drive(
    script: Option<NonSendMut<UiScript>>,
    pads: Query<(Entity, &Gamepad)>,
    mut layouts: Local<HashMap<Entity, Layout>>,
    cfg: Res<Config>,
    time: Res<Time>,
    mut motion: ResMut<AccumulatedMouseMotion>,
    mut m: ResMut<Mapper>,
    mut interact: MessageWriter<TargetInteract>,
    mut windows: Query<&mut Window, With<PrimaryWindow>>,
    mut mouse: ResMut<ButtonInput<MouseButton>>,
    mut keys: ResMut<ButtonInput<KeyCode>>,
    mut key_events: MessageWriter<KeyboardInput>,
) {
    let (gamepad, layout) = match pads.iter().next() {
        Some((e, pad)) => {
            let layout = layouts.entry(e).or_default();
            let was = *layout;
            layout.observe(pad, cfg.raw_layout, cfg.swap_xy);
            if (layout.raw, layout.swap) != (was.raw, was.swap) {
                info!(
                    "wowpad: pad layout: triggers on the {} axes, X / Y {}",
                    if layout.raw { "Z" } else { "trigger" },
                    if layout.swap { "swapped" } else { "in place" }
                );
            }
            (Some(pad), *layout)
        }
        None => (None, Layout::default()),
    };
    let in_world = script
        .as_ref()
        .is_some_and(|s| s.eval::<bool>("return UIParent ~= nil").unwrap_or(false));
    let frame = script
        .as_ref()
        .filter(|_| in_world)
        .and_then(|s| read_frame(s));
    let (Some(script), Some(frame)) = (script.filter(|_| in_world), frame) else {
        // Before the world, or without the addon: the glue screens' keys.
        let mut glue = std::mem::take(&mut m.glue);
        *m = Mapper::default();
        let mut window = windows.single_mut().ok();
        glue::drive(
            gamepad,
            cfg.cursor_speed,
            cfg.stick_deadzone,
            time.delta_secs(),
            window.as_deref_mut(),
            &mut mouse,
            &mut keys,
            &mut key_events,
            &mut glue,
            layout,
        );
        m.glue = glue;
        return;
    };
    // Entering the world with a glue key still held: let go of it.
    for (_, input) in std::mem::take(&mut m.glue) {
        glue::release(input, &mut mouse, &mut keys, &mut key_events);
    }
    let session = script.session();
    if m.session != Some(session) {
        *m = Mapper {
            session: Some(session),
            ..default()
        };
        // The crosshair dot sits where the peek parks the pointer.
        let frac = cfg.crosshair_y / 1080.0;
        if let Err(e) = script.run(&format!(
            "if WowPad_SetCrosshair then WowPad_SetCrosshair({frac}) end"
        )) {
            warn!("wowpad: WowPad_SetCrosshair failed: {e}");
        }
    }

    let mut cfg = cfg.clone();
    cfg.camera_speed *= frame.cam_scale;
    cfg.cursor_speed *= frame.ptr_scale;
    cfg.zoom_speed *= frame.zoom_scale;
    if frame.invert_y >= 0 {
        cfg.camera_invert_y = frame.invert_y != 0;
    }
    if frame.peek_delay_ms > 0.0 {
        cfg.peek_delay_ms = frame.peek_delay_ms.max(50.0);
    }

    let s = PadState::read(gamepad, layout, cfg.stick_deadzone, cfg.trigger_threshold);
    let window = windows.single_mut().ok();
    if let Some(h) = window.as_ref().map(|w| w.physical_height()) {
        if h != m.screen_h {
            m.screen_h = h;
            if let Err(e) = script.run(&format!(
                "if WowPad_SetScreen then WowPad_SetScreen({h}) end"
            )) {
                warn!("wowpad: WowPad_SetScreen failed: {e}");
            }
        }
    }
    let focused = window.as_ref().is_none_or(|w| w.focused);
    let real_motion = motion.delta.length();
    let real_press = keys.get_just_pressed().next().is_some()
        || (mouse.get_just_pressed().next().is_some()
            && m.click_held == [false; 2]
            && m.menu_click == [None; 8]);
    let typing = script.has_keyboard_focus();
    let mut io = Io {
        script: &script,
        cfg,
        now: time.elapsed_secs_f64(),
        dt: time.delta_secs(),
        window,
        motion: &mut motion,
        mouse: &mut mouse,
        key_out: Vec::new(),
        interact_out: false,
        typing,
        frame,
    };
    update(
        &mut m,
        &mut io,
        &s,
        gamepad,
        focused,
        real_press,
        real_motion,
    );
    let (key_out, interact_out) = (std::mem::take(&mut io.key_out), io.interact_out);
    drop(io);
    m.hide_os = m.controller && m.enabled && m.focused;
    for (k, down) in key_out {
        glue::key(k, down, &mut keys, &mut key_events);
    }
    if interact_out {
        interact.write(TargetInteract { loot_all: true });
    }
}

/// One mapper tick (`Mapper_Update`).
fn update(
    m: &mut Mapper,
    io: &mut Io<'_>,
    s: &PadState,
    gamepad: Option<&Gamepad>,
    focused: bool,
    real_press: bool,
    real_motion: f32,
) {
    // Keys pressed last frame (Back + A / B) go up now.
    for k in std::mem::take(&mut m.keys_down) {
        io.key_out.push((k, false));
    }
    // The connected pad, for the addon's glyphs.
    if s.connected != m.announced {
        m.announced = s.connected;
        if s.connected {
            let style = pad::style(gamepad.and_then(Gamepad::vendor_id));
            info!("wowpad: controller connected ({style})");
            io.run(&format!(
                "if WowPad_Connected then WowPad_Connected(\"{style}\") end"
            ));
        } else {
            info!("wowpad: controller disconnected");
        }
    }

    if focused != m.focused {
        m.focused = focused;
        if !focused {
            release_controller_state(m, io, m.controller);
        }
    }
    if !focused {
        m.prev = s.buttons;
        return;
    }
    if update_kill_switch(m, io, s) {
        m.prev = s.buttons;
        return;
    }
    if !m.enabled {
        m.prev = s.buttons;
        return;
    }

    // Mode detection: pad input is controller, real keyboard, mouse buttons or mouse travel
    // while the pad rests is desktop.
    let active = s.active();
    if active {
        m.real_travel = 0.0;
    } else {
        m.real_travel += real_motion;
    }
    let real_move = m.real_travel >= io.cfg.mouse_travel;
    if m.controller && (real_press || real_move) && !active {
        set_mode(
            m,
            io,
            false,
            if real_press {
                "keyboard/mouse button"
            } else {
                "mouse moved"
            },
        );
    } else if !m.controller && active {
        set_mode(m, io, true, "pad input");
    }
    if !m.controller {
        m.prev = s.buttons;
        return;
    }

    update_place(m, io);
    update_movement(m, io, s);
    update_triggers(m, io, s);
    update_buttons(m, io, s);
    update_pointer(m, io, s);
    update_cursor(m, io);
    m.prev = s.buttons;
}

fn send_mode(m: &mut Mapper, io: &Io) {
    io.tap(if m.controller {
        "MODE_CONTROLLER"
    } else {
        "MODE_DESKTOP"
    });
    io.tap(if m.pointer {
        "POINTER_ON"
    } else {
        "POINTER_OFF"
    });
    m.last_mode_send = io.now;
}

fn set_mode(m: &mut Mapper, io: &mut Io, controller: bool, why: &str) {
    if controller == m.controller {
        return;
    }
    if m.controller {
        release_controller_state(m, io, true);
    }
    m.controller = controller;
    if !controller {
        m.pointer = false;
    }
    info!(
        "wowpad: MODE {} ({why})",
        if controller { "controller" } else { "desktop" }
    );
    send_mode(m, io);
}

/// `ReleaseControllerState`: let go of everything held.
fn release_controller_state(m: &mut Mapper, io: &mut Io, tell_addon: bool) {
    for i in 0..8 {
        if let Some(sig) = m.held_sig[i].take() {
            io.signal(sig, false);
        }
    }
    m.interact_held = false;
    if tell_addon {
        if m.lt {
            io.tap("LT_OFF");
        }
        if m.rt {
            io.tap("RT_OFF");
        }
        if m.zoom {
            io.tap("ZOOM_OFF");
        }
        if m.walking {
            io.binding("TOGGLERUN", true);
            io.binding("TOGGLERUN", false);
        }
    }
    m.walking = false;
    m.walk_want_since = None;
    for (k, command) in MOVES.iter().enumerate() {
        if std::mem::take(&mut m.move_held[k]) {
            io.binding(command, false);
        }
    }
    if m.click_held[0] {
        io.mouse.release(MouseButton::Left);
    }
    if m.click_held[1] {
        io.mouse.release(MouseButton::Right);
    }
    if m.place == Place::Down {
        io.mouse.release(MouseButton::Left);
    }
    m.place = Place::Idle;
    m.click_held = [false; 2];
    for b in m.menu_click.iter_mut().filter_map(Option::take) {
        io.mouse.release(b);
    }
    m.lt = false;
    m.rt = false;
    m.zoom = false;
    m.zoom_acc = 0.0;
    m.cycle = 0;
    m.cycle_want = 0;
    m.ring_held = None;
    m.ring_dir = 0;
    m.flick_dir = 0;
    m.sm = Vec2::ZERO;
    m.cam_active = false;
    m.eaten = [false; 8];
}

fn update_kill_switch(m: &mut Mapper, io: &mut Io, s: &PadState) -> bool {
    let chord = s.connected && s.buttons & pad::BACK != 0 && s.buttons & pad::START != 0;
    if chord {
        m.chord_used = true;
    }
    if !chord {
        m.chord_start = None;
        m.chord_fired = false;
        return false;
    }
    let start = *m.chord_start.get_or_insert(io.now);
    if !m.chord_fired && io.now - start >= TOGGLE_HOLD {
        m.chord_fired = true;
        m.enabled = !m.enabled;
        info!(
            "wowpad: kill switch: controller input {} (Back+Start)",
            if m.enabled { "ENABLED" } else { "DISABLED" }
        );
        if !m.enabled {
            set_mode(m, io, false, "kill switch");
        }
        return true;
    }
    false
}

/// Walk/run option: slight tilt walks, full tilt runs, rest always goes back to run.
fn set_walking(m: &mut Mapper, io: &Io, walk: bool) {
    if walk == m.walking {
        return;
    }
    io.binding("TOGGLERUN", true);
    io.binding("TOGGLERUN", false);
    m.walking = walk;
}

fn update_movement(m: &mut Mapper, io: &mut Io, s: &PadState) {
    let v = [s.ly, -s.ly, -s.lx, s.lx];
    for (k, command) in MOVES.iter().enumerate() {
        let want = !io.typing
            && pad::hyst(
                m.move_held[k],
                v[k],
                io.cfg.move_press_at,
                io.cfg.move_release_at,
            );
        if want != m.move_held[k] {
            m.move_held[k] = want;
            io.binding(command, want);
        }
    }
    let moving = m.move_held.iter().any(|&h| h);
    if !io.frame.walk_run || !moving {
        m.walk_want_since = None;
        set_walking(m, io, false);
        return;
    }
    let mag = Vec2::new(s.lx, s.ly).length();
    if mag > io.cfg.run_above {
        m.walk_want_since = None;
        set_walking(m, io, false);
        return;
    }
    if m.walking || mag >= io.cfg.walk_below {
        m.walk_want_since = None;
        return;
    }
    let since = *m.walk_want_since.get_or_insert(io.now);
    if (io.now - since) * 1000.0 >= io.cfg.walk_delay_ms {
        set_walking(m, io, true);
    }
}

fn update_triggers(m: &mut Mapper, io: &mut Io, s: &PadState) {
    let (on, off) = (io.cfg.click_press_at, io.cfg.click_release_at);
    let lt = pad::hyst(m.lt || m.click_held[1], s.lt, on, off);
    let rt = pad::hyst(m.rt || m.click_held[0], s.rt, on, off);
    if m.pointer {
        // Pointer mode: RT = left click, LT = right click.
        if rt != m.click_held[0] {
            m.click_held[0] = rt;
            if rt {
                io.mouse.press(MouseButton::Left);
            } else {
                io.mouse.release(MouseButton::Left);
            }
        }
        if lt != m.click_held[1] {
            m.click_held[1] = lt;
            if lt {
                io.mouse.press(MouseButton::Right);
            } else {
                io.mouse.release(MouseButton::Right);
            }
        }
        return;
    }
    if lt != m.lt {
        m.lt = lt;
        io.tap(if lt { "LT_ON" } else { "LT_OFF" });
    }
    if rt != m.rt {
        m.rt = rt;
        io.tap(if rt { "RT_ON" } else { "RT_OFF" });
    }
}

fn update_buttons(m: &mut Mapper, io: &mut Io, s: &PadState) {
    let mut pressed = s.buttons & !m.prev;
    let released = m.prev & !s.buttons;
    let now = io.now;

    // Self-heal after a /reload: re-announce the mode now and then.
    if pressed != 0 && now - m.last_mode_send > MODE_RESEND {
        send_mode(m, io);
    }

    if pressed & pad::RSTICK != 0 {
        m.pointer = !m.pointer;
        if m.pointer {
            m.cam_active = false;
            if m.lt {
                io.tap("LT_OFF");
            }
            if m.rt {
                io.tap("RT_OFF");
            }
            m.lt = false;
            m.rt = false;
        } else {
            if m.click_held[0] {
                io.mouse.release(MouseButton::Left);
            }
            if m.click_held[1] {
                io.mouse.release(MouseButton::Right);
            }
            m.click_held = [false; 2];
        }
        io.tap(if m.pointer {
            "POINTER_ON"
        } else {
            "POINTER_OFF"
        });
        info!(
            "wowpad: pointer mode {}",
            if m.pointer { "on" } else { "off" }
        );
    }
    if pressed & pad::LSTICK != 0 {
        io.tap("L3");
    }
    if pressed & pad::LB != 0 {
        io.tap("LB");
    }
    if pressed & pad::RB != 0 {
        io.tap("RB");
    }
    let both = s.buttons & pad::LB != 0 && s.buttons & pad::RB != 0;
    if both != m.zoom {
        m.zoom = both;
        m.zoom_acc = 0.0;
        io.tap(if both { "ZOOM_ON" } else { "ZOOM_OFF" });
    }
    // One bumper held alone a moment: the right stick flicks through targets.
    let mut want = 0;
    if io.frame.bumper_flick && !both && !m.pointer {
        want = if s.buttons & pad::LB != 0 {
            1
        } else if s.buttons & pad::RB != 0 {
            2
        } else {
            0
        };
    }
    if want != m.cycle_want {
        m.cycle_want = want;
        m.cycle_since = now;
    }
    let cycle = if want != 0 && now - m.cycle_since >= CYCLE_HOLD {
        want
    } else {
        0
    };
    if cycle != m.cycle {
        m.cycle = cycle;
        m.flick_dir = if cycle != 0 && s.ry.abs() >= 0.3 {
            FLICK_BLOCKED
        } else {
            0
        };
    }

    // Back + A / Back + B: Enter / Escape (the chat box understands those while typing).
    if s.buttons & pad::BACK != 0 {
        let key = if pressed & pad::A != 0 {
            Some(KeyCode::Enter)
        } else if pressed & pad::B != 0 {
            Some(KeyCode::Escape)
        } else {
            None
        };
        if let Some(k) = key {
            m.chord_used = true;
            pressed &= !(pad::A | pad::B);
            io.key_out.push((k, true));
            m.keys_down.push(k);
        }
    }

    // Back: tap = map, hold = bags. Start: on release. Not after a chord.
    if pressed & pad::BACK != 0 {
        m.back_down_at = now;
        m.back_hold_sent = false;
    }
    if s.buttons & pad::BACK != 0
        && !m.chord_used
        && !m.back_hold_sent
        && (now - m.back_down_at) * 1000.0 >= io.cfg.back_hold_ms
    {
        io.tap("BACK_HOLD");
        m.back_hold_sent = true;
    }
    if released & pad::BACK != 0 && !m.chord_used && !m.back_hold_sent {
        io.tap("BACK_TAP");
    }
    if released & pad::START != 0 && !m.chord_used {
        io.tap("START");
    }
    if s.buttons & (pad::BACK | pad::START) == 0 {
        m.chord_used = false;
    }

    // Face buttons and D-pad: slot signals; the addon decides what they do.
    let cur_set = match (m.lt, m.rt) {
        (true, true) => 3,
        (true, false) => 1,
        (false, true) => 2,
        (false, false) => 0,
    };
    for (i, &(bit, sig)) in FACE.iter().enumerate() {
        if pressed & bit != 0 {
            // A spell waiting for its location: A or the same button places it at the
            // crosshair, B cancels. Not with a window open (A still navigates there).
            let slot_id = cur_set * 8 + i;
            let same = i == FACE_A || m.last_slot == Some(slot_id);
            let aiming = !m.pointer && io.frame.aiming && !io.frame.menu;
            if aiming && (same || i == FACE_B) {
                if same {
                    if m.place == Place::Idle {
                        // Camera look off first: in camera look a click is not a placement.
                        io.run("if WowPad_PlaceBegin then WowPad_PlaceBegin() end");
                        m.cam_active = false;
                        m.place = Place::Wait(2);
                    }
                } else {
                    io.run("SpellStopTargeting()");
                }
                m.eaten[i] = true;
                continue;
            }
            m.last_slot = Some(slot_id);
        }
        if m.eaten[i] {
            if released & bit != 0 {
                m.eaten[i] = false;
            }
            continue;
        }
        let ring_id = (cur_set * 10 + i + 1) as i32;
        if pressed & bit != 0 && io.frame.ring_slot == ring_id && !m.pointer {
            m.ring_held = Some(i);
            m.ring_dir = 0;
            m.ring_centre_at = now;
        }
        if released & bit != 0 && m.ring_held == Some(i) {
            m.ring_held = None;
        }
        if pressed & bit != 0 && !io.typing && io.frame.menu_nav && !m.pointer {
            // A window open: A clicks and X right-clicks where navigation put the pointer.
            let click = match i {
                FACE_A => Some(MouseButton::Left),
                FACE_X => Some(MouseButton::Right),
                _ => None,
            };
            if let Some(b) = click {
                io.mouse.press(b);
                m.menu_click[i] = Some(b);
            }
        }
        if released & bit != 0 {
            if let Some(b) = m.menu_click[i].take() {
                io.mouse.release(b);
            }
        }
        if pressed & bit != 0 && !io.typing {
            // X in the default set: interact first (it may change the target), then attack.
            if i == FACE_X && !m.lt && !m.rt && !io.frame.menu && !m.pointer {
                io.interact_out = true;
                m.interact_held = true;
            }
            io.signal(sig, true);
            m.held_sig[i] = Some(sig);
        }
        if released & bit != 0 && i == FACE_X {
            m.interact_held = false;
        }
        if released & bit != 0 {
            if let Some(held) = m.held_sig[i].take() {
                io.signal(held, false);
            }
        }
    }
}

/// The ground-target click, a frame apart from turning camera look off.
fn update_place(m: &mut Mapper, io: &mut Io) {
    match m.place {
        Place::Idle => {}
        Place::Wait(0) => {
            io.park_cursor();
            io.mouse.press(MouseButton::Left);
            m.place = Place::Down;
        }
        Place::Wait(n) => {
            io.park_cursor();
            m.place = Place::Wait(n - 1);
        }
        Place::Down => {
            io.mouse.release(MouseButton::Left);
            m.place = Place::Idle;
            if io.cfg.peek_delay_ms <= 0.0 {
                io.tap("CAM_ACTIVE");
            }
        }
    }
}

fn update_pointer(m: &mut Mapper, io: &mut Io, s: &PadState) {
    let now = io.now;
    let dt = io.dt;
    if m.ring_held.is_some() {
        // Ring held: the stick picks a wedge. 1 = up, clockwise. The centre counts after
        // 200 ms, so letting go of stick and button together keeps the pick.
        m.sm = Vec2::ZERO;
        let mag = Vec2::new(s.rx, s.ry).length();
        let mut dir = m.ring_dir;
        if mag >= 0.5 {
            let mut ang = s.rx.atan2(s.ry);
            if ang < 0.0 {
                ang += std::f32::consts::TAU;
            }
            dir =
                (((ang + std::f32::consts::FRAC_PI_8) / std::f32::consts::FRAC_PI_4) as u8) % 8 + 1;
            m.ring_centre_at = now;
        } else if mag < 0.25 && now - m.ring_centre_at >= 0.2 {
            dir = 0;
        } else if mag >= 0.25 {
            m.ring_centre_at = now;
        }
        if dir != m.ring_dir {
            m.ring_dir = dir;
            io.tap(&format!("RING_DIR_{dir}"));
        }
        return;
    }
    if m.cycle != 0 {
        // Flick: past 0.6 fires once, back under 0.3 re-arms; held, it repeats.
        let dir: i8 = if s.ry <= -0.6 {
            1
        } else if s.ry >= 0.6 {
            -1
        } else {
            0
        };
        if dir == 0 && s.ry.abs() < 0.3 {
            m.flick_dir = 0;
        }
        if dir != 0 && m.flick_dir != FLICK_BLOCKED && (dir != m.flick_dir || now >= m.flick_next) {
            let first = dir != m.flick_dir;
            m.flick_dir = dir;
            m.flick_next = now + if first { 0.45 } else { 0.3 };
            let sig = match (m.cycle, dir > 0) {
                (1, true) => "LB_FLICK_DOWN",
                (1, false) => "LB_FLICK_UP",
                (_, true) => "RB_FLICK_DOWN",
                (_, false) => "RB_FLICK_UP",
            };
            io.tap(sig);
        }
    }
    if m.zoom {
        // Zoom instead of turning: stick up zooms in.
        m.sm = Vec2::ZERO;
        m.zoom_acc += s.ry * io.cfg.zoom_speed * dt;
        let steps = m.zoom_acc.trunc();
        m.zoom_acc -= steps;
        if steps != 0.0 && !io.typing {
            let (verb, n) = if steps > 0.0 {
                ("CameraZoomIn", steps)
            } else {
                ("CameraZoomOut", -steps)
            };
            io.run(&format!("{verb}({n})"));
        }
        return;
    }
    let mut v = Vec2::new(s.rx, if m.cycle != 0 { 0.0 } else { s.ry });
    if io.frame.cam_smooth && !m.pointer {
        let a = 1.0 - (-dt * 1000.0 / io.cfg.smooth_ms).exp();
        m.sm += (v - m.sm) * a;
        if v == Vec2::ZERO && m.sm.x.abs() + m.sm.y.abs() < 0.02 {
            m.sm = Vec2::ZERO;
        }
        v = m.sm;
    } else {
        m.sm = v;
    }
    let mag = v.length();
    let peek = io.cfg.peek_delay_ms;
    if mag <= 0.0 {
        if m.cam_active && peek > 0.0 && (now - m.stick_idle_at) * 1000.0 >= peek {
            io.tap("CAM_IDLE");
            m.cam_active = false;
        }
        return;
    }
    m.stick_idle_at = now;
    if !m.cam_active && !m.pointer && peek > 0.0 {
        io.tap("CAM_ACTIVE");
        m.cam_active = true;
    }
    if io.typing {
        return;
    }
    if mag > 1.0 {
        v /= mag;
    }
    let mag = mag.min(1.0);
    let shaped = mag.powf(io.cfg.cursor_curve) / mag;
    let pointer = m.pointer;
    let mut speed = if pointer {
        io.cfg.cursor_speed
    } else {
        io.cfg.camera_speed
    };
    if pointer && io.cfg.precision_button != 0 && s.buttons & io.cfg.precision_button != 0 {
        speed *= io.cfg.precision_scale;
    }
    let y_dir = if !pointer && io.cfg.camera_invert_y {
        1.0
    } else {
        -1.0
    };
    let d = Vec2::new(v.x * shaped * speed * dt, v.y * y_dir * shaped * speed * dt);
    if io.frame.looking && !pointer {
        io.motion.delta += d;
    } else {
        io.move_cursor_by(d);
    }
}

/// The crosshair peek: camera look paused with no window open, the pointer parked under the
/// crosshair, so what is under it shows its tooltip and takes the clicks.
fn update_cursor(m: &mut Mapper, io: &mut Io) {
    // Menu navigation moved to a button: put the pointer on it.
    if let Some(f) = io.frame.warp {
        if let Some((w, h)) = io.window.as_deref().map(|w| (w.width(), w.height())) {
            io.put_cursor(Vec2::new(f.x * w, (1.0 - f.y) * h));
        }
    }
    if !m.pointer && !io.frame.menu && !io.frame.looking {
        io.park_cursor();
    }
}

/// PostUpdate, after the camera: keep the OS cursor hidden while the pad drives the pointer.
/// Ending camera look shows it (`release_cursor`); writing it back here in the same frame means
/// bevy_winit never sees it shown, so it does not flash. When the mouse takes over, the OS cursor
/// is warped to benilla's pointer (once) and shown, unless a camera look holds it.
fn hide_os_cursor(
    m: Res<Mapper>,
    mut was_hidden: Local<bool>,
    mut windows: Query<(&mut Window, &mut CursorOptions), With<PrimaryWindow>>,
) {
    let Ok((mut window, mut cursor)) = windows.single_mut() else {
        return;
    };
    if m.hide_os {
        if cursor.visible {
            cursor.visible = false;
        }
        *was_hidden = true;
    } else if std::mem::take(&mut *was_hidden) {
        window.set_changed();
        if cursor.grab_mode == CursorGrabMode::None && !cursor.visible {
            cursor.visible = true;
        }
    }
}

/// Name each pad as it connects, for reports.
fn log_pads(mut events: MessageReader<GamepadConnectionEvent>) {
    for ev in events.read() {
        match &ev.connection {
            GamepadConnection::Connected {
                name,
                vendor_id,
                product_id,
            } => info!(
                "wowpad: pad connected: {name} (vendor {:04x}, product {:04x})",
                vendor_id.unwrap_or(0),
                product_id.unwrap_or(0)
            ),
            GamepadConnection::Disconnected => info!("wowpad: pad disconnected"),
        }
    }
}
