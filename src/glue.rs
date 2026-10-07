//! The pad before the world (login, realm list, character select), where neither the stock UI
//! nor WowPad is loaded: A is Enter, B is Escape, the D-pad is the arrow keys, Y is Tab, X clicks
//! and the right stick moves the cursor. Those are the keys the screens read. After benilla-pad's
//! `drive_glue` (lucasvallejodev/benilla-gamepad, MIT OR Apache-2.0).

use bevy::input::keyboard::{Key, KeyboardInput, NativeKey};
use bevy::input::ButtonState;
use bevy::prelude::*;

/// What a pad button holds down before the world.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum GlueInput {
    Key(KeyCode),
    Mouse(MouseButton),
}

fn glue_input(button: GamepadButton) -> Option<GlueInput> {
    Some(match button {
        GamepadButton::South => GlueInput::Key(KeyCode::Enter),
        GamepadButton::East => GlueInput::Key(KeyCode::Escape),
        GamepadButton::DPadUp => GlueInput::Key(KeyCode::ArrowUp),
        GamepadButton::DPadDown => GlueInput::Key(KeyCode::ArrowDown),
        GamepadButton::DPadLeft => GlueInput::Key(KeyCode::ArrowLeft),
        GamepadButton::DPadRight => GlueInput::Key(KeyCode::ArrowRight),
        GamepadButton::North => GlueInput::Key(KeyCode::Tab),
        GamepadButton::West => GlueInput::Mouse(MouseButton::Left),
        _ => return None,
    })
}

const GLUE_BUTTONS: [GamepadButton; 8] = [
    GamepadButton::South,
    GamepadButton::East,
    GamepadButton::West,
    GamepadButton::North,
    GamepadButton::DPadUp,
    GamepadButton::DPadDown,
    GamepadButton::DPadLeft,
    GamepadButton::DPadRight,
];

/// A key edge as the keyboard sends it: the button plane for `just_pressed` readers and the
/// message for the ones that read events (an EditBox, Tab on the login screen).
pub fn key(
    key: KeyCode,
    down: bool,
    keys: &mut ButtonInput<KeyCode>,
    events: &mut MessageWriter<KeyboardInput>,
) {
    if down {
        keys.press(key);
    } else {
        keys.release(key);
    }
    let logical = match key {
        KeyCode::Enter => Key::Enter,
        KeyCode::Escape => Key::Escape,
        KeyCode::Tab => Key::Tab,
        _ => Key::Unidentified(NativeKey::Unidentified),
    };
    events.write(KeyboardInput {
        key_code: key,
        logical_key: logical,
        state: if down {
            ButtonState::Pressed
        } else {
            ButtonState::Released
        },
        text: None,
        repeat: false,
        window: Entity::PLACEHOLDER,
    });
}

pub fn release(
    input: GlueInput,
    mouse: &mut ButtonInput<MouseButton>,
    keys: &mut ButtonInput<KeyCode>,
    events: &mut MessageWriter<KeyboardInput>,
) {
    match input {
        GlueInput::Key(k) => key(k, false, keys, events),
        GlueInput::Mouse(b) => mouse.release(b),
    }
}

/// One frame of the pad on the screens before the world.
#[allow(clippy::too_many_arguments)]
pub fn drive(
    pad: Option<&Gamepad>,
    cursor_speed: f32,
    deadzone: f32,
    dt: f32,
    window: Option<&mut Window>,
    mouse: &mut ButtonInput<MouseButton>,
    keys: &mut ButtonInput<KeyCode>,
    events: &mut MessageWriter<KeyboardInput>,
    held: &mut Vec<(GamepadButton, GlueInput)>,
    layout: crate::pad::Layout,
) {
    let mut i = 0;
    while i < held.len() {
        let (button, input) = held[i];
        if pad.is_none_or(|p| !p.pressed(layout.button(button))) {
            release(input, mouse, keys, events);
            held.swap_remove(i);
        } else {
            i += 1;
        }
    }
    let Some(pad) = pad else {
        return;
    };
    for button in GLUE_BUTTONS {
        if !pad.just_pressed(layout.button(button)) {
            continue;
        }
        if let Some(input) = glue_input(button) {
            match input {
                GlueInput::Key(k) => key(k, true, keys, events),
                GlueInput::Mouse(b) => mouse.press(b),
            }
            held.push((button, input));
        }
    }
    let right = crate::pad::radial(pad.right_stick(), deadzone);
    if let (Some(w), true) = (window, right != Vec2::ZERO) {
        let mag = right.length().min(1.0);
        let at = w
            .cursor_position()
            .unwrap_or(Vec2::new(w.width() / 2.0, w.height() / 2.0));
        let to =
            at + Vec2::new(right.x, -right.y) / right.length() * cursor_speed * mag.powf(2.0) * dt;
        w.set_cursor_position(Some(
            to.clamp(Vec2::ZERO, Vec2::new(w.width() - 1.0, w.height() - 1.0)),
        ));
    }
}
