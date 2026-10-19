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

use benilla_app::{HeldItemFacts, ObjectType, Objects};
use benilla_ui::script::UiScript;
use benilla_world::terrain_stream::CurrentArea;
use benilla_world::world_map::CurrentMap;
use bevy::prelude::*;

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

/// The last list the addon was told, and the time since the last scan.
#[derive(Resource, Default)]
pub struct QuestItems {
    since: f32,
    sent: Option<String>,
}

/// What a held item is to the hint.
enum Verdict {
    /// Its use works here.
    Here,
    /// No place binding: usable while its spell text names the target.
    Target(String),
    /// Place-bound but not here, and why.
    No(String),
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
        let row = match ready(&facts, &objects, &here, entry) {
            Verdict::Here => format!("{{{bag},{slot},\"here\"}},"),
            Verdict::Target(text) => {
                format!("{{{bag},{slot},\"target\",{}}},", lua_string(&text))
            }
            Verdict::No(why) => format!("{{{bag},{slot},\"no\",{}}},", lua_string(&why)),
            Verdict::Skip(why) if debug => {
                format!("{{{bag},{slot},\"skip\",{}}},", lua_string(&why))
            }
            Verdict::Skip(_) | Verdict::Silent => continue,
        };
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
fn ready(facts: &HeldItemFacts, objects: &Objects, here: &Here, entry: u32) -> Verdict {
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
    let focus = facts.spell_focus(spell);
    // A place-bound use is a quest item's whatever its class; an unbound one only for a quest item.
    let bound = item.area != 0 || item.map != 0 || focus != 0;
    if !bound && item.class != CLASS_QUEST && item.bonding != BONDING_QUEST {
        return Verdict::Skip(format!(
            "{}: class {}, bonding {}, spell {spell}, no place binding",
            item.name, item.class, item.bonding
        ));
    }
    let name = &item.name;
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
        return Verdict::No(format!(
            "{name}: needs focus {focus}; {focus_objects} focus objects streamed, nearest match {}",
            // In 10 yd steps, so walking about does not rewrite the list each scan.
            nearest.map_or("none".to_string(), |d| format!(
                "about {} yd",
                (d / 10.0).round() * 10.0
            ))
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
    use super::lua_string;

    #[test]
    fn a_lua_string_escapes_quotes_and_lines() {
        assert_eq!(lua_string("a \"b\"\\\nc"), r#""a \"b\"\\\nc""#);
    }
}
