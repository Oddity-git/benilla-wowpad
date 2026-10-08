//! The controller as WowPad's DLL sees it: a button bitmask, two sticks with a radial deadzone
//! and two triggers past their threshold (`controller.h`, `controller_filter.cpp`).

use bevy::prelude::*;

pub const DPAD_UP: u32 = 1 << 0;
pub const DPAD_DOWN: u32 = 1 << 1;
pub const DPAD_LEFT: u32 = 1 << 2;
pub const DPAD_RIGHT: u32 = 1 << 3;
pub const START: u32 = 1 << 4;
pub const BACK: u32 = 1 << 5;
pub const LSTICK: u32 = 1 << 6;
pub const RSTICK: u32 = 1 << 7;
pub const LB: u32 = 1 << 8;
pub const RB: u32 = 1 << 9;
pub const A: u32 = 1 << 12;
pub const B: u32 = 1 << 13;
pub const X: u32 = 1 << 14;
pub const Y: u32 = 1 << 15;

/// Each bit with its name in `wowpad.ini` and the log.
pub const BUTTON_NAMES: [(u32, &str); 14] = [
    (DPAD_UP, "DPadUp"),
    (DPAD_DOWN, "DPadDown"),
    (DPAD_LEFT, "DPadLeft"),
    (DPAD_RIGHT, "DPadRight"),
    (START, "Start"),
    (BACK, "Back"),
    (LSTICK, "LStick"),
    (RSTICK, "RStick"),
    (LB, "LB"),
    (RB, "RB"),
    (A, "A"),
    (B, "B"),
    (X, "X"),
    (Y, "Y"),
];

const BUTTONS: [(GamepadButton, u32); 14] = [
    (GamepadButton::DPadUp, DPAD_UP),
    (GamepadButton::DPadDown, DPAD_DOWN),
    (GamepadButton::DPadLeft, DPAD_LEFT),
    (GamepadButton::DPadRight, DPAD_RIGHT),
    (GamepadButton::Start, START),
    (GamepadButton::Select, BACK),
    (GamepadButton::LeftThumb, LSTICK),
    (GamepadButton::RightThumb, RSTICK),
    (GamepadButton::LeftTrigger, LB),
    (GamepadButton::RightTrigger, RB),
    (GamepadButton::South, A),
    (GamepadButton::East, B),
    (GamepadButton::West, X),
    (GamepadButton::North, Y),
];

/// Valve's USB vendor id: Steam's virtual pad.
const VALVE: u16 = 0x28de;

/// How a pad reports itself. A pad the input library has no mapping for comes through in the raw
/// Linux layout: Xbox-style X / Y arrive as `North` / `West` (evdev's `BTN_X` is `BTN_NORTH`),
/// and the triggers as the `LeftZ` / `RightZ` axes instead of `LeftTrigger2` / `RightTrigger2`.
#[derive(Clone, Copy, Debug, Default, PartialEq, Eq)]
pub struct Layout {
    /// The triggers are the Z axes.
    pub raw: bool,
    /// X and Y arrive swapped.
    pub swap: bool,
    /// The Z axes run -1 (released) to 1 (pulled), rather than 0 to 1.
    pub bipolar: bool,
}

impl Layout {
    /// Learn from this poll: a Z axis that reports at all marks the raw layout, and a negative
    /// reading a -1..1 range. X and Y swap with the raw layout, except on Steam's virtual pad
    /// (Valve's vendor id), whose face buttons arrive in place. `raw` and `swap` are the ini's
    /// `RawLayout` and `SwapXY` (`None` = detect).
    pub fn observe(&mut self, pad: &Gamepad, raw: Option<bool>, swap: Option<bool>) {
        let z = [GamepadAxis::LeftZ, GamepadAxis::RightZ].map(|a| pad.get(a));
        if z.iter().flatten().any(|v| *v < -0.05) {
            self.bipolar = true;
        }
        self.raw = raw.unwrap_or(self.raw || z.iter().any(Option::is_some));
        self.swap = swap.unwrap_or(self.raw && pad.vendor_id() != Some(VALVE));
    }

    /// The button that is physically `button` on this pad.
    pub fn button(self, button: GamepadButton) -> GamepadButton {
        match (self.swap, button) {
            (true, GamepadButton::West) => GamepadButton::North,
            (true, GamepadButton::North) => GamepadButton::West,
            _ => button,
        }
    }

    /// A Z axis as a 0..1 trigger pull.
    fn z(self, v: Option<f32>) -> f32 {
        let v = v.unwrap_or(if self.bipolar { -1.0 } else { 0.0 });
        if self.bipolar {
            ((v + 1.0) / 2.0).clamp(0.0, 1.0)
        } else {
            v.clamp(0.0, 1.0)
        }
    }
}

/// One poll of the pad, deadzones applied.
#[derive(Clone, Copy, Debug, Default, PartialEq)]
pub struct PadState {
    pub connected: bool,
    pub buttons: u32,
    pub lx: f32,
    pub ly: f32,
    pub rx: f32,
    pub ry: f32,
    pub lt: f32,
    pub rt: f32,
}

impl PadState {
    pub fn read(pad: Option<&Gamepad>, layout: Layout, stick_dz: f32, trigger_th: f32) -> Self {
        let Some(pad) = pad else {
            return Self::default();
        };
        let mut buttons = 0;
        for (button, bit) in BUTTONS {
            if pad.pressed(layout.button(button)) {
                buttons |= bit;
            }
        }
        let l = radial(pad.left_stick(), stick_dz);
        let r = radial(pad.right_stick(), stick_dz);
        let trigger = |b: GamepadButton, z: GamepadAxis| {
            let mut v = pad.get(b).unwrap_or(if pad.pressed(b) { 1.0 } else { 0.0 });
            if layout.raw {
                v = v.max(layout.z(pad.get(z)));
            }
            threshold(v, trigger_th)
        };
        Self {
            connected: true,
            buttons,
            lx: l.x,
            ly: l.y,
            rx: r.x,
            ry: r.y,
            lt: trigger(GamepadButton::LeftTrigger2, GamepadAxis::LeftZ),
            rt: trigger(GamepadButton::RightTrigger2, GamepadAxis::RightZ),
        }
    }

    /// Any input at all (`PadActive`).
    pub fn active(&self) -> bool {
        self.connected
            && (self.buttons != 0
                || self.lx != 0.0
                || self.ly != 0.0
                || self.rx != 0.0
                || self.ry != 0.0
                || self.lt > 0.0
                || self.rt > 0.0)
    }
}

/// `RadialDeadzone`: nothing inside `dz`, then rescaled so motion starts from zero at its edge.
pub fn radial(v: Vec2, dz: f32) -> Vec2 {
    let mag = v.length();
    if mag <= dz || mag <= 0.0 {
        return Vec2::ZERO;
    }
    let clamped = mag.min(1.0);
    v * (((clamped - dz) / (1.0 - dz)) / mag)
}

/// `TriggerDeadzone`.
pub fn threshold(v: f32, th: f32) -> f32 {
    if v <= th {
        return 0.0;
    }
    ((v - th) / (1.0 - th)).min(1.0)
}

/// `Hyst`: a press point and a lower release point.
pub fn hyst(held: bool, v: f32, on: f32, off: f32) -> bool {
    if held {
        v > off
    } else {
        v >= on
    }
}

/// The face style a pad's USB vendor implies, for the addon's glyphs.
pub fn style(vendor: Option<u16>) -> &'static str {
    match vendor {
        Some(0x054c) => "playstation",
        _ => "xbox",
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn the_deadzone_starts_motion_from_zero_at_its_edge() {
        assert_eq!(radial(Vec2::new(0.2, 0.0), 0.24), Vec2::ZERO);
        let v = radial(Vec2::new(1.0, 0.0), 0.24);
        assert!((v.x - 1.0).abs() < 1e-6);
        let mid = radial(Vec2::new(0.62, 0.0), 0.24);
        assert!((mid.x - 0.5).abs() < 1e-6);
    }

    #[test]
    fn the_raw_layout_swaps_x_and_y_and_reads_bipolar_z() {
        let raw = Layout {
            raw: true,
            swap: true,
            bipolar: true,
        };
        assert_eq!(raw.button(GamepadButton::West), GamepadButton::North);
        assert_eq!(raw.button(GamepadButton::South), GamepadButton::South);
        assert_eq!(
            Layout::default().button(GamepadButton::West),
            GamepadButton::West
        );
        assert_eq!(raw.z(Some(-1.0)), 0.0);
        assert_eq!(raw.z(Some(1.0)), 1.0);
        assert_eq!(raw.z(None), 0.0);
        let unipolar = Layout {
            raw: true,
            swap: true,
            bipolar: false,
        };
        assert_eq!(unipolar.z(Some(0.5)), 0.5);
    }

    #[test]
    fn hysteresis_holds_between_its_points() {
        assert!(!hyst(false, 0.35, 0.4, 0.3));
        assert!(hyst(false, 0.4, 0.4, 0.3));
        assert!(hyst(true, 0.35, 0.4, 0.3));
        assert!(!hyst(true, 0.3, 0.4, 0.3));
    }
}
