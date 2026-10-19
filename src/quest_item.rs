//! The quick-use quest item: a few times a second [`scan`] lists the quest items in the bags
//! whose use spell can work here, through benilla's [`HeldItemFacts`] (an engine patch, as 1.12
//! has no call for it). The addon shows the first as a hint and LT + RT + L3 uses it.
//!
//! An item is *here* when its template binds it to the zone (or subzone) and map the player is
//! in, or its spell needs a focus object (an altar, a campfire) and one is within its radius. An
//! item with neither binding is listed as *target* with its spell's text: only the server knows
//! which creature it works on, so the addon shows it when the text names the player's target.
//! An unbound item whose text names a clickable object in reach (the well a waterskin is filled
//! at) is *here* too. One that is place-bound but not ready is listed as *no* with the reason, and
//! under `/wp debug` the other usable items as *skip* with their facts; `/wp debug` prints both.
//!
//! What the client cannot know, the server's database can: `tools/export-quest-spots.sh` writes
//! `benilla-config/wowpad-quest-spots.tsv` from the cMaNGOS world database, every spawn of the
//! creatures and objects each quest item's spell is meant for, and every spell focus object. An
//! item with spots there is *here* within one of them and *far* (with the distance) elsewhere,
//! whatever the client-side guesses say. The file is read again when it changes.

use benilla_app::{HeldItemFacts, ObjectType, Objects};
use benilla_ui::script::UiScript;
use benilla_world::terrain_stream::CurrentArea;
use benilla_world::world_map::CurrentMap;
use bevy::prelude::*;
use std::collections::HashMap;
use std::path::PathBuf;
use std::time::SystemTime;

/// How often the bags are looked through again, seconds.
const SCAN_EVERY: f32 = 0.25;
/// `ITEM_CLASS_QUEST`.
const CLASS_QUEST: u32 = 12;
/// `ITEM_BONDING_QUEST`: a quest item of another class (some are consumables).
const BONDING_QUEST: u32 = 4;
/// `ITEM_SPELLTRIGGER_ON_USE`.
const TRIGGER_ON_USE: u32 = 0;
/// `GAMEOBJECT_TYPE_SPELL_FOCUS`.
const GO_SPELL_FOCUS: i32 = 8;
/// Backpack slots, and where the four bags sit in the player's inventory.
const PACK_SLOTS: u8 = 16;
const BAG_SLOT_FIRST: u8 = 19;
const BAGS: u8 = 4;

/// The spots file in `benilla-config/`, and how often it is checked for a new export, seconds.
const SPOTS_FILE: &str = "wowpad-quest-spots.tsv";
const SPOTS_CHECK_EVERY: f32 = 5.0;

/// The last list the addon was told, the time since the last scan, and the server's spots.
#[derive(Resource, Default)]
pub struct QuestItems {
    since: f32,
    sent: Option<String>,
    spots: Spots,
    spots_checked: Option<f32>,
    spots_stamp: Option<SystemTime>,
}

/// One place an item's use works: a map and a WoW position, with how near counts, yards.
#[derive(Debug, Clone, Copy, PartialEq)]
struct Spot {
    map: u32,
    at: Vec3,
    radius: f32,
}

/// The exported spots, by item entry and by spell focus id.
#[derive(Default, Debug)]
struct Spots {
    items: HashMap<u32, Vec<Spot>>,
    focus: HashMap<u32, Vec<Spot>>,
}

impl Spots {
    /// The export's rows: `item|focus  id  map  x  y  z  radius`, tab separated; others skipped.
    fn parse(text: &str) -> Self {
        let mut spots = Self::default();
        for line in text.lines() {
            let f: Vec<&str> = line.split('\t').map(str::trim).collect();
            let [kind, id, map, x, y, z, radius] = f[..] else {
                continue;
            };
            let (Ok(id), Ok(map), Ok(x), Ok(y), Ok(z), Ok(radius)) = (
                id.parse::<u32>(),
                map.parse::<u32>(),
                x.parse::<f32>(),
                y.parse::<f32>(),
                z.parse::<f32>(),
                radius.parse::<f32>(),
            ) else {
                continue;
            };
            let spot = Spot {
                map,
                at: Vec3::new(x, y, z),
                radius,
            };
            match kind {
                "item" => spots.items.entry(id).or_default().push(spot),
                "focus" => spots.focus.entry(id).or_default().push(spot),
                _ => {}
            }
        }
        spots
    }

    /// The nearest of `spots` on the player's map, and whether the player is within its radius.
    fn nearest(spots: &[Spot], here: &Here) -> Option<(f32, bool)> {
        let (map, at) = (here.map?, here.at?);
        spots
            .iter()
            .filter(|s| s.map == map)
            .map(|s| {
                let d = s.at.distance(at);
                (d, d <= s.radius)
            })
            .min_by(|a, b| {
                (!a.1, a.0)
                    .partial_cmp(&(!b.1, b.0))
                    .unwrap_or(std::cmp::Ordering::Equal)
            })
    }
}

fn spots_path() -> Option<PathBuf> {
    benilla_app::config_dir().map(|d| d.join(SPOTS_FILE))
}

/// Reads the spots file again when it is new or changed, a check every few seconds.
fn refresh_spots(state: &mut QuestItems, now: f32) {
    if state
        .spots_checked
        .is_some_and(|t| now - t < SPOTS_CHECK_EVERY)
    {
        return;
    }
    state.spots_checked = Some(now);
    let Some(path) = spots_path() else { return };
    let stamp = std::fs::metadata(&path).and_then(|m| m.modified()).ok();
    if stamp == state.spots_stamp {
        return;
    }
    state.spots_stamp = stamp;
    state.spots = match std::fs::read_to_string(&path) {
        Ok(text) => {
            let spots = Spots::parse(&text);
            info!(
                "wowpad: quest item spots for {} items and {} spell focuses from {}",
                spots.items.len(),
                spots.focus.len(),
                path.display()
            );
            spots
        }
        Err(_) => Spots::default(),
    };
}

/// What a held item is to the hint.
enum Verdict {
    /// Its use works here.
    Here,
    /// No place binding: usable while its spell text names the target.
    Target(String),
    /// Place-bound but not here, and why.
    No(String),
    /// The server's spots for it are all elsewhere, and how far the nearest is.
    Far(String),
    /// Not a quest item, with its facts for `/wp debug`.
    Skip(String),
    /// No template yet, or no use.
    Silent,
}

/// How near a clickable object must be for its name in the spell text to count, yards.
const NAMED_OBJECT_RANGE: f32 = 10.0;

/// Lists the usable quest items and tells the addon when the list changes.
#[allow(clippy::too_many_arguments)]
pub fn scan(
    script: Option<NonSend<UiScript>>,
    time: Res<Time>,
    objects: Objects,
    facts: HeldItemFacts,
    area: Option<Res<CurrentArea>>,
    map: Option<Res<CurrentMap>>,
    places: Query<&GlobalTransform>,
    mut state: ResMut<QuestItems>,
) {
    let Some(script) = script else { return };
    state.since += time.delta_secs();
    if state.since < SCAN_EVERY {
        return;
    }
    state.since = 0.0;
    refresh_spots(&mut state, time.elapsed_secs());
    let debug = script
        .eval::<bool>("return WowPadDB and WowPadDB.debug and true or false")
        .unwrap_or(false);
    let here = Here {
        area: area.and_then(|a| a.0),
        map: map.map(|m| m.0),
        // In WoW coordinates, as the objects' own positions are.
        at: objects.player().and_then(|p| places.get(p).ok()).map(|t| {
            let b = t.translation();
            Vec3::new(-b.z, -b.x, b.y)
        }),
    };
    let mut list = String::new();
    for (bag, slot, entry) in held(&objects) {
        let row = match ready(&facts, &objects, &state.spots, &here, entry) {
            Verdict::Here => ("here", String::new()),
            Verdict::Far(why) => ("far", why),
            Verdict::Target(text) => ("target", text),
            Verdict::No(why) => ("no", why),
            Verdict::Skip(why) if debug => ("skip", why),
            Verdict::Skip(_) | Verdict::Silent => continue,
        };
        // The item's name rides along for the hint's label, and its spell text for the addon's
        // place and target match (also on a "no" row: an unfound focus may still be named).
        let template = facts.template(entry);
        let name = template.map_or("", |t| t.name.as_str());
        let text = template
            .and_then(|t| t.spells.iter().find(|s| s.trigger == TRIGGER_ON_USE))
            .and_then(|s| facts.spell_description(s.spell_id))
            .unwrap_or_default();
        let row = format!(
            "{{{bag},{slot},\"{}\",{},{},{}}},",
            row.0,
            lua_string(&row.1),
            lua_string(name),
            lua_string(text)
        );
        list.push_str(&row);
    }
    if state.sent.as_deref() == Some(list.as_str()) {
        return;
    }
    if let Err(e) = script.run(&format!(
        "if WowPad_QuestItems then WowPad_QuestItems({{{list}}}) end"
    )) {
        warn!("wowpad: WowPad_QuestItems failed: {e}");
    }
    state.sent = Some(list);
}

/// Where the player is.
struct Here {
    area: Option<u32>,
    map: Option<u32>,
    at: Option<Vec3>,
}

/// Every held item as `(bag, slot, entry)`, numbered as `GetContainerItemInfo` numbers them.
fn held(objects: &Objects) -> Vec<(u8, u8, u32)> {
    let mut out = Vec::new();
    let Some(me) = objects
        .player()
        .and_then(|p| objects.iter().find(|(_, e, _)| *e == p))
        .map(|(_, _, f)| f)
    else {
        return out;
    };
    let entry = |guid: u64| objects.object(guid).and_then(|f| f.object_entry());
    for i in 0..PACK_SLOTS {
        if let Some(e) = me.player_pack_slot(i).filter(|&g| g != 0).and_then(entry) {
            out.push((0, i + 1, e));
        }
    }
    for bag in 1..=BAGS {
        let Some(fields) = me
            .player_inv_slot(BAG_SLOT_FIRST + bag - 1)
            .filter(|&g| g != 0)
            .and_then(|g| objects.object(g))
        else {
            continue;
        };
        let slots = fields.container_num_slots().unwrap_or(0).min(36) as u8;
        for j in 0..slots {
            if let Some(e) = fields.container_slot(j).filter(|&g| g != 0).and_then(entry) {
                out.push((bag, j + 1, e));
            }
        }
    }
    out
}

/// Whether a held item's use works here, and how; the reasons are for `/wp debug`.
fn ready(
    facts: &HeldItemFacts,
    objects: &Objects,
    spots: &Spots,
    here: &Here,
    entry: u32,
) -> Verdict {
    let Some(item) = facts.template(entry) else {
        return Verdict::Silent;
    };
    let Some(spell) = item
        .spells
        .iter()
        .find(|s| s.trigger == TRIGGER_ON_USE && s.spell_id != 0)
        .map(|s| s.spell_id)
    else {
        return Verdict::Silent;
    };
    let name = &item.name;
    // The server's own word on where it works comes first.
    if let Some(list) = spots.items.get(&entry) {
        return match Spots::nearest(list, here) {
            Some((_, true)) => Verdict::Here,
            Some((d, false)) => Verdict::Far(format!("{name}: nearest spot {}", yards(d))),
            None => Verdict::Far(format!("{name}: no spot on this map")),
        };
    }
    let focus = facts.spell_focus(spell);
    // A place-bound use is a quest item's whatever its class; an unbound one only for a quest item.
    let bound = item.area != 0 || item.map != 0 || focus != 0;
    if !bound && item.class != CLASS_QUEST && item.bonding != BONDING_QUEST {
        return Verdict::Skip(format!(
            "{}: class {}, bonding {}, spell {spell}, no place binding",
            item.name, item.class, item.bonding
        ));
    }
    if item.map != 0 && here.map != Some(item.map) {
        return Verdict::No(format!("{name}: map {} (here {:?})", item.map, here.map));
    }
    if item.area != 0 {
        let area = here.area;
        let zone = area.and_then(|a| facts.zone_of(a));
        if area != Some(item.area) && zone != Some(item.area) {
            return Verdict::No(format!(
                "{name}: area {} (here {area:?}, zone {zone:?})",
                item.area
            ));
        }
    }
    if focus != 0 {
        let Some(at) = here.at else {
            return Verdict::No(format!("{name}: no position yet"));
        };
        let mut nearest: Option<f32> = None;
        let mut focus_objects = 0;
        for (_, _, f) in objects.iter() {
            if f.object_type() != Some(ObjectType::GameObject)
                || f.gameobject_type_id() != GO_SPELL_FOCUS
            {
                continue;
            }
            focus_objects += 1;
            let Some((id, radius)) = f.object_entry().and_then(|e| facts.object_spell_focus(e))
            else {
                continue;
            };
            let Some((pos, _)) = f.gameobject_position().filter(|_| f.gameobject_pos_sent()) else {
                continue;
            };
            if id != focus {
                continue;
            }
            let d = Vec3::new(pos.x, pos.y, pos.z).distance(at);
            if d <= radius.max(5.0) {
                return Verdict::Here;
            }
            nearest = Some(nearest.map_or(d, |n| n.min(d)));
        }
        // Out of streaming range the server's list of focus objects still knows.
        if let Some(list) = spots.focus.get(&focus) {
            return match Spots::nearest(list, here) {
                Some((_, true)) => Verdict::Here,
                Some((d, false)) => Verdict::Far(format!("{name}: nearest focus {}", yards(d))),
                None => Verdict::Far(format!("{name}: no focus {focus} on this map")),
            };
        }
        return Verdict::No(format!(
            "{name}: needs focus {focus}; {focus_objects} focus objects streamed, nearest match {}",
            nearest.map_or("none".to_string(), yards)
        ));
    }
    if bound {
        return Verdict::Here;
    }
    let text = facts.spell_description(spell).unwrap_or_default();
    if named_object_near(facts, objects, here, text) {
        return Verdict::Here;
    }
    Verdict::Target(text.to_string())
}

/// Whether a clickable object in reach is named in a spell's text: a well, a brazier, a corpse
/// pile the use is meant for, which the server checks by entry and the client cannot.
fn named_object_near(facts: &HeldItemFacts, objects: &Objects, here: &Here, text: &str) -> bool {
    let Some(at) = here.at else { return false };
    let text = text.to_lowercase();
    if text.is_empty() {
        return false;
    }
    objects.iter().any(|(_, _, f)| {
        f.object_type() == Some(ObjectType::GameObject)
            && f.gameobject_pos_sent()
            && f.gameobject_position()
                .is_some_and(|(p, _)| Vec3::new(p.x, p.y, p.z).distance(at) <= NAMED_OBJECT_RANGE)
            && f.object_entry()
                .and_then(|e| facts.object_name(e))
                .is_some_and(|n| n.len() >= 4 && text.contains(&n.to_lowercase()))
    })
}

/// A distance for the reasons, coarse so walking about does not rewrite the list each scan.
fn yards(d: f32) -> String {
    let step = if d < 100.0 { 10.0 } else { 100.0 };
    format!("about {} yd", (d / step).round() * step)
}

/// `s` as a Lua string literal.
fn lua_string(s: &str) -> String {
    let mut out = String::with_capacity(s.len() + 2);
    out.push('"');
    for c in s.chars() {
        match c {
            '\\' => out.push_str("\\\\"),
            '"' => out.push_str("\\\""),
            '\n' => out.push_str("\\n"),
            '\r' => {}
            c if (c as u32) < 0x20 => {}
            c => out.push(c),
        }
    }
    out.push('"');
    out
}

#[cfg(test)]
mod tests {
    use super::{Here, Spots, lua_string};
    use bevy::math::Vec3;

    #[test]
    fn spots_parse_and_the_nearest_counts_its_radius() {
        let spots = Spots::parse(
            "item\t5000\t1\t10.0\t20.0\t30.0\t15\nfocus\t42\t1\t0\t0\t0\t10\nbad line\n\
             item\t5000\t0\t10.0\t20.0\t30.0\t15\n",
        );
        assert_eq!(spots.items[&5000].len(), 2);
        assert_eq!(spots.focus[&42].len(), 1);
        let here = |x: f32| Here {
            area: None,
            map: Some(1),
            at: Some(Vec3::new(x, 20.0, 30.0)),
        };
        assert_eq!(
            Spots::nearest(&spots.items[&5000], &here(20.0)),
            Some((10.0, true))
        );
        assert_eq!(
            Spots::nearest(&spots.items[&5000], &here(40.0)),
            Some((30.0, false))
        );
        let elsewhere = Here {
            area: None,
            map: Some(530),
            at: Some(Vec3::ZERO),
        };
        assert_eq!(Spots::nearest(&spots.items[&5000], &elsewhere), None);
    }

    #[test]
    fn a_lua_string_escapes_quotes_and_lines() {
        assert_eq!(lua_string("a \"b\"\\\nc"), r#""a \"b\"\\\nc""#);
    }
}
