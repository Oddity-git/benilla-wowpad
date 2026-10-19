//! The quick-use quest item: a few times a second [`scan`] lists the quest items in the bags
//! whose use spell can work here, through benilla's [`HeldItemFacts`] (an engine patch, as 1.12
//! has no call for it). The addon shows the first as a hint and LT + RT + L3 uses it.
//!
//! An item is *here* when its template binds it to the zone (or subzone) and map the player is
//! in, or its spell needs a focus object (an altar, a campfire) and one is within its radius. An
//! item with neither binding is listed as *target* with its spell's text: only the server knows
//! which creature it works on, so the addon shows it when the text names the player's target.
//! One that is place-bound but not ready is listed as *no* with the reason, which `/wp debug`
//! prints.

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

/// Why an item may be used now.
enum Ready {
    Here,
    Target(String),
}

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
            Ok(Ready::Here) => format!("{{{bag},{slot},\"here\"}},"),
            Ok(Ready::Target(text)) => {
                format!("{{{bag},{slot},\"target\",{}}},", lua_string(&text))
            }
            Err(Some(why)) => format!("{{{bag},{slot},\"no\",{}}},", lua_string(&why)),
            Err(None) => continue,
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

/// Whether a held item's use works here, and how. `Err(None)` for an item this is not about,
/// `Err(Some(why))` for one that is but is not ready, for `/wp debug`.
fn ready(
    facts: &HeldItemFacts,
    objects: &Objects,
    here: &Here,
    entry: u32,
) -> Result<Ready, Option<String>> {
    let item = facts.template(entry).ok_or(None)?;
    let spell = item
        .spells
        .iter()
        .find(|s| s.trigger == TRIGGER_ON_USE && s.spell_id != 0)
        .ok_or(None)?
        .spell_id;
    let focus = facts.spell_focus(spell);
    // A place-bound use is a quest item's whatever its class; an unbound one only for a quest item.
    let bound = item.area != 0 || item.map != 0 || focus != 0;
    if !bound && item.class != CLASS_QUEST && item.bonding != BONDING_QUEST {
        return Err(None);
    }
    let name = &item.name;
    if item.map != 0 && here.map != Some(item.map) {
        return Err(Some(format!(
            "{name}: map {} (here {:?})",
            item.map, here.map
        )));
    }
    if item.area != 0 {
        let area = here.area;
        let zone = area.and_then(|a| facts.zone_of(a));
        if area != Some(item.area) && zone != Some(item.area) {
            return Err(Some(format!(
                "{name}: area {} (here {area:?}, zone {zone:?})",
                item.area
            )));
        }
    }
    if focus != 0 {
        let at = here
            .at
            .ok_or_else(|| Some(format!("{name}: no position yet")))?;
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
                return Ok(Ready::Here);
            }
            nearest = Some(nearest.map_or(d, |n| n.min(d)));
        }
        return Err(Some(format!(
            "{name}: needs focus {focus}; {focus_objects} focus objects streamed, nearest match {}",
            // In 10 yd steps, so walking about does not rewrite the list each scan.
            nearest.map_or("none".to_string(), |d| format!(
                "about {} yd",
                (d / 10.0).round() * 10.0
            ))
        )));
    }
    if bound {
        return Ok(Ready::Here);
    }
    Ok(Ready::Target(
        facts
            .spell_description(spell)
            .unwrap_or_default()
            .to_string(),
    ))
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
