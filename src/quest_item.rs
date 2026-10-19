//! The quick-use quest item: a few times a second [`scan`] lists the quest items in the bags
//! whose use spell can work here, through benilla's [`HeldItemFacts`] (an engine patch, as 1.12
//! has no call for it). The addon shows the first as a hint and LT + RT + L3 uses it.
//!
//! An item is *here* when its template binds it to the zone (or subzone) and map the player is
//! in, or its spell needs a focus object (an altar, a campfire) and one is within its radius. An
//! item with neither binding is listed as *target* with its spell's text: only the server knows
//! which creature it works on, so the addon shows it when the text names the player's target.

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
        at: objects
            .player()
            .and_then(|p| places.get(p).ok())
            .map(GlobalTransform::translation),
    };
    let mut list = String::new();
    for (bag, slot, entry) in held(&objects) {
        let Some(ready) = ready(&facts, &objects, &places, &here, entry) else {
            continue;
        };
        let row = match ready {
            Ready::Here => format!("{{{bag},{slot},\"here\"}},"),
            Ready::Target(text) => format!("{{{bag},{slot},\"target\",{}}},", lua_string(&text)),
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

/// Whether a held item is a quest item whose use works here, and how.
fn ready(
    facts: &HeldItemFacts,
    objects: &Objects,
    places: &Query<&GlobalTransform>,
    here: &Here,
    entry: u32,
) -> Option<Ready> {
    let item = facts.template(entry)?;
    if item.class != CLASS_QUEST && item.bonding != BONDING_QUEST {
        return None;
    }
    let spell = item
        .spells
        .iter()
        .find(|s| s.trigger == TRIGGER_ON_USE && s.spell_id != 0)?
        .spell_id;
    let focus = facts.spell_focus(spell);
    if item.map != 0 && here.map != Some(item.map) {
        return None;
    }
    if item.area != 0 {
        let area = here.area?;
        if area != item.area && facts.zone_of(area) != Some(item.area) {
            return None;
        }
    }
    if focus != 0 {
        let at = here.at?;
        let near = objects.iter().any(|(_, e, f)| {
            f.object_type() == Some(ObjectType::GameObject)
                && f.gameobject_type_id() == GO_SPELL_FOCUS
                && f.object_entry()
                    .and_then(|entry| facts.object_spell_focus(entry))
                    .is_some_and(|(id, radius)| {
                        id == focus
                            && places
                                .get(e)
                                .is_ok_and(|t| t.translation().distance(at) <= radius.max(5.0))
                    })
        });
        return near.then_some(Ready::Here);
    }
    if item.area != 0 || item.map != 0 {
        return Some(Ready::Here);
    }
    Some(Ready::Target(
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
