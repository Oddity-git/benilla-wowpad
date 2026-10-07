//! `benilla-config/wowpad.ini`: WowPad's tuning, the same file and keys the 3.3.5 DLL reads from
//! beside `Wow.exe`, less the ones that only made sense there (injection mode, movement keys,
//! pointer warping, logging). Written with the defaults on first start; every key is optional.

use std::path::Path;

use bevy::prelude::*;

/// The file written when there is none: the defaults, with the 3.3.5 file's comments.
const DEFAULT_INI: &str = include_str!("../wowpad.ini");

/// The tuning, as WowPad's DLL `Config` holds it.
#[derive(Resource, Clone, Debug)]
pub struct Config {
    /// [Input] radial stick deadzone, fraction of full deflection.
    pub stick_deadzone: f32,
    /// [Input] trigger threshold, fraction of full pull.
    pub trigger_threshold: f32,
    /// [Move] per-axis press and release points, after the deadzone.
    pub move_press_at: f32,
    pub move_release_at: f32,
    /// [Move] walk/run option: tilt below `walk_below` walks, above `run_above` runs.
    pub walk_below: f32,
    pub run_above: f32,
    pub walk_delay_ms: f64,
    /// [Cursor] pointer speed at full deflection, pixels a second, and the response curve.
    pub cursor_speed: f32,
    pub cursor_curve: f32,
    /// [Cursor] the pad button that slows the pointer (`None` = 0), and by how much.
    pub precision_button: u32,
    pub precision_scale: f32,
    /// [Camera] camera turn at full deflection, pixels a second of mouse motion.
    pub camera_speed: f32,
    pub camera_invert_y: bool,
    /// [Camera] LB+RB held: zoom steps a second at full deflection.
    pub zoom_speed: f32,
    /// [Camera] the crosshair's height above the window centre, pixels at 1080 high.
    pub crosshair_y: f32,
    /// [Camera] right stick resting this long pauses camera look (crosshair peek); 0 = off.
    pub peek_delay_ms: f64,
    /// [Camera] smooth camera option: easing time constant, milliseconds.
    pub smooth_ms: f32,
    /// [Click] trigger press and release points.
    pub click_press_at: f32,
    pub click_release_at: f32,
    /// [Mode] real mouse travel, pixels, that switches to desktop mode.
    pub mouse_travel: f32,
    /// [Mode] Back held this long is bags instead of the map.
    pub back_hold_ms: f64,
    /// [Input] the pad's raw Linux layout (triggers as Z axes, X and Y swapped): `None` = detect.
    pub raw_layout: Option<bool>,
}

impl Default for Config {
    fn default() -> Self {
        Self {
            stick_deadzone: 0.24,
            trigger_threshold: 0.12,
            move_press_at: 0.40,
            move_release_at: 0.30,
            walk_below: 0.60,
            run_above: 0.80,
            walk_delay_ms: 150.0,
            cursor_speed: 1200.0,
            cursor_curve: 2.0,
            precision_button: 0,
            precision_scale: 0.35,
            camera_speed: 1000.0,
            camera_invert_y: false,
            zoom_speed: 8.0,
            crosshair_y: 95.0,
            peek_delay_ms: 250.0,
            smooth_ms: 60.0,
            click_press_at: 0.50,
            click_release_at: 0.35,
            mouse_travel: 40.0,
            back_hold_ms: 400.0,
            raw_layout: None,
        }
    }
}

impl Config {
    /// `benilla-config/wowpad.ini`, written with the defaults when it is missing.
    pub fn load() -> Self {
        let Some(dir) = benilla_app::config_dir() else {
            return Self::default();
        };
        let path = dir.join("wowpad.ini");
        if !path.exists() {
            if let Err(e) =
                std::fs::create_dir_all(&dir).and_then(|()| std::fs::write(&path, DEFAULT_INI))
            {
                warn!("wowpad: could not write {}: {e}", path.display());
            }
        }
        Self::read(&path)
    }

    fn read(path: &Path) -> Self {
        match std::fs::read_to_string(path) {
            Ok(text) => {
                let c = Self::parse(&text);
                info!("wowpad: config {}", path.display());
                c
            }
            Err(_) => Self::default(),
        }
    }

    /// The ini text over the defaults; unknown keys and bad values are skipped.
    pub fn parse(text: &str) -> Self {
        let mut c = Self::default();
        let mut section = String::new();
        for line in text.lines() {
            let line = line.split(';').next().unwrap_or("").trim();
            if line.is_empty() {
                continue;
            }
            if let Some(name) = line.strip_prefix('[').and_then(|l| l.strip_suffix(']')) {
                section = name.trim().to_ascii_lowercase();
                continue;
            }
            let Some((key, value)) = line.split_once('=') else {
                continue;
            };
            let key = key.trim().to_ascii_lowercase();
            let value = value.trim();
            let num = value.parse::<f32>().ok();
            let flag = matches!(value, "1" | "true" | "yes" | "on");
            match (section.as_str(), key.as_str()) {
                ("input", "stickdeadzone") => set(&mut c.stick_deadzone, num, 0.0, 0.9),
                ("input", "triggerthreshold") => set(&mut c.trigger_threshold, num, 0.0, 0.9),
                ("move", "pressat") => set(&mut c.move_press_at, num, 0.0, 1.0),
                ("move", "releaseat") => set(&mut c.move_release_at, num, 0.0, 1.0),
                ("move", "walkbelow") => set(&mut c.walk_below, num, 0.0, 1.0),
                ("move", "runabove") => set(&mut c.run_above, num, 0.0, 1.0),
                ("move", "walkdelayms") => set_ms(&mut c.walk_delay_ms, num, 2000.0),
                ("cursor", "speed") => set(&mut c.cursor_speed, num, 1.0, 20000.0),
                ("cursor", "curve") => set(&mut c.cursor_curve, num, 0.5, 4.0),
                ("cursor", "precisionbutton") => c.precision_button = button_bit(value),
                ("cursor", "precisionscale") => set(&mut c.precision_scale, num, 0.05, 1.0),
                ("camera", "speed") => set(&mut c.camera_speed, num, 1.0, 20000.0),
                ("camera", "inverty") => c.camera_invert_y = flag,
                ("camera", "zoomspeed") => set(&mut c.zoom_speed, num, 0.0, 100.0),
                ("camera", "crosshairy") => set(&mut c.crosshair_y, num, -1000.0, 1000.0),
                ("camera", "peekdelayms") => set_ms(&mut c.peek_delay_ms, num, 5000.0),
                ("camera", "smoothms") => set(&mut c.smooth_ms, num, 10.0, 300.0),
                ("click", "pressat") => set(&mut c.click_press_at, num, 0.0, 1.0),
                ("click", "releaseat") => set(&mut c.click_release_at, num, 0.0, 1.0),
                ("mode", "mousetravel") => set(&mut c.mouse_travel, num, 0.0, 10000.0),
                ("mode", "backholdms") => set_ms(&mut c.back_hold_ms, num, 5000.0),
                ("input", "rawlayout") => {
                    c.raw_layout = match value.to_ascii_lowercase().as_str() {
                        "on" | "1" | "true" | "yes" => Some(true),
                        "off" | "0" | "false" | "no" => Some(false),
                        _ => None,
                    }
                }
                _ => {}
            }
        }
        c
    }
}

fn set(field: &mut f32, value: Option<f32>, lo: f32, hi: f32) {
    if let Some(v) = value {
        *field = v.clamp(lo, hi);
    }
}

fn set_ms(field: &mut f64, value: Option<f32>, hi: f64) {
    if let Some(v) = value {
        *field = f64::from(v).clamp(0.0, hi);
    }
}

/// A pad button name as the ini spells it, as a [`crate::pad`] bit; 0 for `None` or unknown.
fn button_bit(name: &str) -> u32 {
    crate::pad::BUTTON_NAMES
        .iter()
        .find(|(_, n)| n.eq_ignore_ascii_case(name))
        .map_or(0, |(bit, _)| *bit)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn the_shipped_ini_parses_to_the_defaults() {
        let c = Config::parse(DEFAULT_INI);
        let d = Config::default();
        assert_eq!(c.stick_deadzone, d.stick_deadzone);
        assert_eq!(c.camera_speed, d.camera_speed);
        assert_eq!(c.cursor_speed, d.cursor_speed);
        assert_eq!(c.click_press_at, d.click_press_at);
        assert_eq!(c.move_press_at, d.move_press_at);
    }

    #[test]
    fn the_same_key_in_two_sections_stays_apart() {
        let c = Config::parse("[Move]\nPressAt=0.7\n[Click]\nPressAt=0.2\n");
        assert_eq!(c.move_press_at, 0.7);
        assert_eq!(c.click_press_at, 0.2);
    }
}
