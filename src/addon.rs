//! The WowPad addon ships inside the binary and is kept installed in
//! `benilla-config/AddOns/WowPad`, where benilla loads addons from. A file is written only
//! when its bytes differ, so an unchanged install is left alone, and a file the addon no longer
//! ships is removed (the folder is ours). `BENILLA_WOWPAD_NO_INSTALL=1` skips the sync, for editing
//! the installed copy by hand.

use std::path::Path;

use bevy::prelude::*;
use include_dir::{include_dir, Dir};

static ADDON: Dir<'_> = include_dir!("$CARGO_MANIFEST_DIR/addon/WowPad");

/// Startup: write the embedded addon into the AddOns folder.
pub fn install_addon() {
    if std::env::var("BENILLA_WOWPAD_NO_INSTALL").is_ok_and(|v| v == "1") {
        info!("wowpad: addon sync skipped (BENILLA_WOWPAD_NO_INSTALL=1)");
        return;
    }
    let Some(config) = benilla_app::config_dir() else {
        warn!("wowpad: no benilla-config folder, the WowPad addon is not installed");
        return;
    };
    let root = config.join("AddOns").join("WowPad");
    if let Err(e) = prune(&ADDON, &root) {
        warn!("wowpad: could not tidy the WowPad addon folder: {e}");
    }
    match sync(&ADDON, &root) {
        Ok(0) => info!("wowpad: WowPad addon up to date at {}", root.display()),
        Ok(n) => info!(
            "wowpad: WowPad addon installed ({n} files) at {}",
            root.display()
        ),
        Err(e) => warn!("wowpad: could not install the WowPad addon: {e}"),
    }
}

/// Write every file of `dir` under `root` whose bytes differ; the count written.
fn sync(dir: &Dir<'_>, root: &Path) -> std::io::Result<usize> {
    let mut written = 0;
    for file in dir.files() {
        let path = root.join(file.path());
        if std::fs::read(&path).is_ok_and(|have| have == file.contents()) {
            continue;
        }
        if let Some(parent) = path.parent() {
            std::fs::create_dir_all(parent)?;
        }
        std::fs::write(&path, file.contents())?;
        written += 1;
    }
    for sub in dir.dirs() {
        written += sync(sub, root)?;
    }
    Ok(written)
}

/// Remove every file under `root` that `dir` does not ship; the count removed.
fn prune(dir: &Dir<'_>, root: &Path) -> std::io::Result<usize> {
    fn walk(dir: &Dir<'_>, root: &Path, here: &Path, removed: &mut usize) -> std::io::Result<()> {
        let Ok(entries) = std::fs::read_dir(here) else {
            return Ok(());
        };
        for entry in entries {
            let path = entry?.path();
            if path.is_dir() {
                walk(dir, root, &path, removed)?;
                continue;
            }
            let Ok(rel) = path.strip_prefix(root) else {
                continue;
            };
            if dir.get_file(rel).is_none() {
                std::fs::remove_file(&path)?;
                *removed += 1;
            }
        }
        Ok(())
    }
    let mut removed = 0;
    walk(dir, root, root, &mut removed)?;
    Ok(removed)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn every_addon_file_compiles_under_the_1_12_grammar() {
        let lua = mlua::Lua::new();
        let mut n = 0;
        for file in ADDON.files() {
            if file.path().extension().is_some_and(|e| e == "lua") {
                let src = file.contents_utf8().expect("utf-8");
                let name = file.path().display().to_string();
                if let Err(e) = lua.load(src).set_name(name.as_str()).into_function() {
                    panic!("{name}: {e}");
                }
                n += 1;
            }
        }
        assert!(n >= 9, "only {n} Lua files");
    }

    #[test]
    fn the_toc_names_only_files_the_addon_ships() {
        let toc = ADDON
            .get_file("WowPad.toc")
            .and_then(|f| f.contents_utf8())
            .expect("toc");
        for line in toc.lines().map(str::trim) {
            if line.is_empty() || line.starts_with('#') {
                continue;
            }
            assert!(
                ADDON.get_file(line).is_some(),
                "{line} is listed but not shipped"
            );
        }
    }
}
