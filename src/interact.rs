//! X's Interact, through benilla's own crate API: `benilla_app::Objects` lists what is streamed
//! and `benilla_app::Interact` runs an object's interact dispatcher, as a right-click on it would,
//! without selecting it (only an attack selects).
//!
//! A few times a second [`scan`] picks the soft target, the thing X would use: a corpse to loot or
//! skin, else the nearest NPC with a service or usable object ahead of the camera. The addon shows
//! it as an X icon over the thing. X acts on the soft target when there is one, else on the target.
//! In a fight with a target there is no soft target, so X stays on the target.

use benilla_app::{Interact, ObjectFields, ObjectType, Objects};
use benilla_ui::script::UiScript;
use benilla_world::view::WorldCamera;
use bevy::ecs::system::SystemParam;
use bevy::prelude::*;

/// How far a soft target may be, in yards: corpses, then NPCs and objects (whose use still needs
/// benilla's own reach).
const CORPSE_RANGE: f32 = 10.0;
const RANGE: f32 = 6.0;
/// `UNIT_FLAG_SKINNABLE`.
const UNIT_FLAG_SKINNABLE: u32 = 0x0400_0000;
/// `UNIT_FLAG_IN_COMBAT`.
const UNIT_FLAG_IN_COMBAT: u32 = 0x0008_0000;
/// `GAMEOBJECT_FLAGS` bit `0x10`: no interact.
const GO_FLAG_NO_INTERACT: u32 = 0x10;
/// How often the soft target is picked again, seconds.
const SCAN_EVERY: f32 = 0.1;

/// What X does to a soft target: the prompt's verb.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum Verb {
    Loot,
    Skin,
    Talk,
    Read,
    Mail,
    Use,
}

impl Verb {
    fn label(self) -> &'static str {
        match self {
            Verb::Loot => "Loot",
            Verb::Skin => "Skin",
            Verb::Talk => "Talk",
            Verb::Read => "Read",
            Verb::Mail => "Mail",
            Verb::Use => "Use",
        }
    }

    fn is_corpse(self) -> bool {
        matches!(self, Verb::Loot | Verb::Skin)
    }
}

/// What a streamed object is to X, if anything.
pub fn verb_of(fields: &ObjectFields) -> Option<Verb> {
    match fields.object_type()? {
        ObjectType::Unit | ObjectType::Player => {
            if fields.unit_is_dead() {
                if fields.unit_lootable() {
                    Some(Verb::Loot)
                } else if fields.unit_flags() & UNIT_FLAG_SKINNABLE != 0 {
                    Some(Verb::Skin)
                } else {
                    None
                }
            } else {
                (fields.unit_npc_flags() != 0).then_some(Verb::Talk)
            }
        }
        ObjectType::GameObject => {
            if fields.gameobject_flags() & GO_FLAG_NO_INTERACT != 0 {
                return None;
            }
            // Quest giver, chest (herbs and veins too), text, goober, mailbox.
            match fields.gameobject_type_id() {
                9 => Some(Verb::Read),
                19 => Some(Verb::Mail),
                2 | 3 | 10 => Some(Verb::Use),
                _ => None,
            }
        }
        _ => None,
    }
}

/// One candidate, reduced to what the ranking reads.
#[derive(Clone, Copy, Debug, PartialEq)]
pub struct Candidate {
    pub guid: u64,
    pub verb: Verb,
    /// Flat offset from the player, yards.
    pub offset: Vec2,
}

/// The soft target among `candidates`: a corpse within [`CORPSE_RANGE`] (`last`, the corpse X
/// last used, first, else the nearest), else the thing within [`RANGE`] nearest and most ahead of
/// the camera (`ahead`, flat and unit, or zero for no preference); nothing behind the camera.
pub fn pick(
    candidates: impl Iterator<Item = Candidate>,
    ahead: Vec2,
    last: Option<u64>,
) -> Option<Candidate> {
    let mut corpse: Option<(f32, Candidate)> = None;
    let mut other: Option<(f32, Candidate)> = None;
    for c in candidates {
        let d = c.offset.length();
        if c.verb.is_corpse() {
            if d > CORPSE_RANGE {
                continue;
            }
            let rank = if last == Some(c.guid) { -1.0 } else { d };
            if corpse.is_none_or(|(r, _)| rank < r) {
                corpse = Some((rank, c));
            }
        } else {
            if d > RANGE {
                continue;
            }
            let facing = if ahead == Vec2::ZERO || d < 0.5 {
                1.0
            } else {
                c.offset.normalize().dot(ahead)
            };
            if facing <= 0.0 {
                continue;
            }
            let rank = d * (2.0 - facing);
            if other.is_none_or(|(r, _)| rank < r) {
                other = Some((rank, c));
            }
        }
    }
    corpse.or(other).map(|(_, c)| c)
}

/// The soft target X would use now, and the prompt the addon was last told.
#[derive(Resource, Default)]
pub struct Soft {
    pub pick: Option<(Entity, u64, Verb)>,
    shown: Option<Verb>,
    /// Where the addon was last told the prompt goes.
    at: Option<Vec2>,
    since: f32,
    /// The corpse X last used, ranked first while it stays lootable.
    last: Option<u64>,
}

/// What [`scan`] and X's press read.
#[derive(SystemParam)]
pub struct World<'w, 's> {
    objects: Objects<'w, 's>,
    transforms: Query<'w, 's, &'static Transform>,
    camera: Query<'w, 's, (&'static Camera, &'static Transform), With<WorldCamera>>,
}

impl World<'_, '_> {
    /// The camera the world renders through (the active one: off-screen booths have their own).
    fn view(&self) -> Option<(&Camera, GlobalTransform)> {
        self.camera
            .iter()
            .find(|(c, _)| c.is_active)
            .map(|(c, pose)| (c, GlobalTransform::from(*pose)))
    }

    /// Where the prompt goes for `entity`: over it on screen, as fractions of the
    /// viewport from its top-left corner. `None` behind the camera or off screen.
    fn prompt_at(&self, entity: Entity, verb: Verb) -> Option<Vec2> {
        // Projected as benilla seats its own world-anchored overlays (the chat bubble): the camera's
        // and the object's own `Transform`.
        let (camera, cam) = self.view()?;
        let tf = self.transforms.get(entity).ok()?;
        // Where the icon's middle goes: just over a standing NPC's head (where its quest mark
        // sits), a little over a corpse, over the middle of an object; scaled with the model.
        let up = match verb {
            Verb::Talk => 2.6,
            Verb::Loot | Verb::Skin => 0.9,
            _ => 0.8,
        } * tf.scale.y.max(0.1);
        let size = camera.logical_viewport_size()?;
        let p = camera.world_to_viewport(&cam, tf.translation + Vec3::Y * up).ok()?;
        if p.x < 0.0 || p.y < 0.0 || p.x > size.x || p.y > size.y {
            return None;
        }
        Some(p / size)
    }

    fn soft(&self, last: Option<u64>) -> Option<(Entity, u64, Verb)> {
        let me = self.objects.player()?;
        // In a fight with a target, X stays on the target: a guard or vendor in reach must not
        // take the press.
        let mine = self.objects.iter().find(|(_, e, _)| *e == me)?.2;
        if mine.unit_flags() & UNIT_FLAG_IN_COMBAT != 0 && mine.unit_target().is_some() {
            return None;
        }
        let at = self.transforms.get(me).ok()?.translation;
        let ahead = self
            .view()
            .map(|(_, c)| {
                let f = c.forward().as_vec3();
                Vec2::new(f.x, f.z).normalize_or_zero()
            })
            .unwrap_or(Vec2::ZERO);
        let candidates = self.objects.iter().filter_map(|(guid, entity, fields)| {
            if entity == me {
                return None;
            }
            let verb = verb_of(fields)?;
            let p = self.transforms.get(entity).ok()?.translation;
            Some(Candidate {
                guid,
                verb,
                offset: Vec2::new(p.x - at.x, p.z - at.z),
            })
        });
        let c = pick(candidates, ahead, last)?;
        Some((self.objects.entity(c.guid)?, c.guid, c.verb))
    }

    /// Our player's target, as the server last recorded it (`UNIT_FIELD_TARGET`).
    fn target(&self) -> Option<Entity> {
        let me = self.objects.player()?;
        let fields = self.objects.iter().find(|(_, e, _)| *e == me)?.2;
        self.objects.entity(fields.unit_target()?)
    }
}

/// Pick the soft target a few times a second and tell the addon when its prompt changes.
pub fn scan(
    script: Option<NonSend<UiScript>>,
    time: Res<Time>,
    world: World,
    mut soft: ResMut<Soft>,
) {
    let Some(script) = script else { return };
    soft.since += time.delta_secs();
    if soft.since >= SCAN_EVERY {
        soft.since = 0.0;
        let in_world = script
            .eval::<bool>("return UIParent ~= nil")
            .unwrap_or(false);
        soft.pick = if in_world { world.soft(soft.last) } else { None };
    }
    // Every frame, so the icon rides the object as the camera turns.
    let at = soft
        .pick
        .and_then(|(entity, _, verb)| world.prompt_at(entity, verb));
    let moved = match (at, soft.at) {
        (Some(a), Some(b)) => a.distance(b) > 0.0005,
        (a, b) => a.is_some() != b.is_some(),
    };
    if moved {
        soft.at = at;
        let args = at.map_or("nil".to_string(), |p| format!("{}, {}", p.x, p.y));
        if let Err(e) = script.run(&format!(
            "if WowPad_InteractPromptAt then WowPad_InteractPromptAt({args}) end"
        )) {
            warn!("wowpad: WowPad_InteractPromptAt failed: {e}");
        }
    }
    let verb = soft.pick.map(|(_, _, v)| v);
    if verb != soft.shown {
        soft.shown = verb;
        let arg = verb.map_or("nil".to_string(), |v| format!("\"{}\"", v.label()));
        if let Err(e) = script.run(&format!(
            "if WowPad_InteractPrompt then WowPad_InteractPrompt({arg}) end"
        )) {
            warn!("wowpad: WowPad_InteractPrompt failed: {e}");
        }
    }
}

/// X: the soft target when there is one (your target stays), else your target. Returns whether a
/// corpse is being looted, so the addon can take every row.
pub fn press(world: &World, soft: &mut Soft, out: &mut MessageWriter<Interact>) -> bool {
    // Fresh, not the last scan's, so a corpse looted a moment ago is not asked again.
    let pick = world.soft(soft.last);
    if let Some((entity, guid, verb)) = pick {
        if verb.is_corpse() {
            soft.last = Some(guid);
        }
        out.write(Interact(entity));
        return verb == Verb::Loot;
    }
    if let Some(entity) = world.target() {
        out.write(Interact(entity));
    }
    false
}

#[cfg(test)]
mod tests {
    use super::*;

    fn c(guid: u64, verb: Verb, x: f32, z: f32) -> Candidate {
        Candidate {
            guid,
            verb,
            offset: Vec2::new(x, z),
        }
    }

    #[test]
    fn a_corpse_outranks_a_service_and_the_last_corpse_outranks_distance() {
        let all = [
            c(1, Verb::Talk, 1.0, 0.0),
            c(2, Verb::Loot, 8.0, 0.0),
            c(3, Verb::Loot, 4.0, 0.0),
        ];
        let ahead = Vec2::X;
        assert_eq!(pick(all.into_iter(), ahead, None).map(|c| c.guid), Some(3));
        assert_eq!(pick(all.into_iter(), ahead, Some(2)).map(|c| c.guid), Some(2));
    }

    #[test]
    fn a_service_must_be_near_and_not_behind_the_camera() {
        let ahead = Vec2::X;
        assert_eq!(pick([c(1, Verb::Talk, 7.0, 0.0)].into_iter(), ahead, None), None);
        assert_eq!(pick([c(1, Verb::Mail, -3.0, 0.0)].into_iter(), ahead, None), None);
        let near = pick([c(1, Verb::Read, 3.0, 1.0)].into_iter(), ahead, None);
        assert_eq!(near.map(|c| c.verb), Some(Verb::Read));
    }
}
