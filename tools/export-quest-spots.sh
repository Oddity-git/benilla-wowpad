#!/bin/bash
# export-quest-spots: where each quest item's use works, from a cMaNGOS Classic world database, for
# WowPad's quick-use quest item hint. The client never learns this; the server's database has it:
#   - a quest objective "cast this item's spell on creature / object X" (quest_template ReqSpellCast
#     with ReqCreatureOrGOId) and the spell's script targets (spell_script_target): every spawn of
#     those creatures and objects is a spot for the item;
#   - every spawned spell focus object (gameobject type 8: an altar, a campfire, a well), by focus id,
#     for items whose spell needs one.
# Writes one row per spot, tab separated: kind (item / focus), id, map, x, y, z, radius.
#
#   bash export-quest-spots.sh [output file]
# The database, user and password come from MANGOS_DB, MANGOS_USER, MANGOS_PASS (defaults: the
# classicmangos database, user mangos, password Admin, as the server's own config has them).

OUT="${1:-$HOME/Games/benilla-personal/benilla-config/wowpad-quest-spots.tsv}"
DB="${MANGOS_DB:-classicmangos}"
USER_="${MANGOS_USER:-mangos}"
PASS="${MANGOS_PASS:-Admin}"

command -v mysql >/dev/null || { echo "export-quest-spots: no mysql client here"; exit 1; }

# Each item's on-use spells, from its five spell slots.
ITEM_SPELLS="
  SELECT entry AS item, spellid_1 AS spell, class, bonding FROM item_template WHERE spellid_1 <> 0 AND spelltrigger_1 = 0
  UNION ALL SELECT entry, spellid_2, class, bonding FROM item_template WHERE spellid_2 <> 0 AND spelltrigger_2 = 0
  UNION ALL SELECT entry, spellid_3, class, bonding FROM item_template WHERE spellid_3 <> 0 AND spelltrigger_3 = 0
  UNION ALL SELECT entry, spellid_4, class, bonding FROM item_template WHERE spellid_4 <> 0 AND spelltrigger_4 = 0
  UNION ALL SELECT entry, spellid_5, class, bonding FROM item_template WHERE spellid_5 <> 0 AND spelltrigger_5 = 0"

# Quest objectives: the spell cast on a creature (positive id) or object (negative id).
OBJECTIVES="
  SELECT ReqSpellCast1 AS spell, ReqCreatureOrGOId1 AS target FROM quest_template WHERE ReqSpellCast1 <> 0
  UNION ALL SELECT ReqSpellCast2, ReqCreatureOrGOId2 FROM quest_template WHERE ReqSpellCast2 <> 0
  UNION ALL SELECT ReqSpellCast3, ReqCreatureOrGOId3 FROM quest_template WHERE ReqSpellCast3 <> 0
  UNION ALL SELECT ReqSpellCast4, ReqCreatureOrGOId4 FROM quest_template WHERE ReqSpellCast4 <> 0"

QUERY="
SELECT DISTINCT 'item', s.item, c.map, ROUND(c.position_x, 1), ROUND(c.position_y, 1), ROUND(c.position_z, 1), 30
  FROM ($ITEM_SPELLS) s JOIN ($OBJECTIVES) o ON o.spell = s.spell
  JOIN creature c ON o.target > 0 AND c.id = o.target
UNION
SELECT DISTINCT 'item', s.item, g.map, ROUND(g.position_x, 1), ROUND(g.position_y, 1), ROUND(g.position_z, 1), 15
  FROM ($ITEM_SPELLS) s JOIN ($OBJECTIVES) o ON o.spell = s.spell
  JOIN gameobject g ON o.target < 0 AND g.id = -o.target
UNION
SELECT DISTINCT 'item', s.item, c.map, ROUND(c.position_x, 1), ROUND(c.position_y, 1), ROUND(c.position_z, 1), 30
  FROM ($ITEM_SPELLS) s JOIN spell_script_target t ON t.entry = s.spell
  JOIN creature c ON t.type IN (1, 2) AND c.id = t.targetEntry
  WHERE s.class = 12 OR s.bonding = 4
UNION
SELECT DISTINCT 'item', s.item, c.map, ROUND(c.position_x, 1), ROUND(c.position_y, 1), ROUND(c.position_z, 1), 30
  FROM ($ITEM_SPELLS) s JOIN spell_script_target t ON t.entry = s.spell
  JOIN creature c ON t.type = 4 AND c.guid = t.targetEntry
  WHERE s.class = 12 OR s.bonding = 4
UNION
SELECT DISTINCT 'item', s.item, g.map, ROUND(g.position_x, 1), ROUND(g.position_y, 1), ROUND(g.position_z, 1), 15
  FROM ($ITEM_SPELLS) s JOIN spell_script_target t ON t.entry = s.spell
  JOIN gameobject g ON t.type = 0 AND g.id = t.targetEntry
  WHERE s.class = 12 OR s.bonding = 4
UNION
SELECT DISTINCT 'item', s.item, g.map, ROUND(g.position_x, 1), ROUND(g.position_y, 1), ROUND(g.position_z, 1), 15
  FROM ($ITEM_SPELLS) s JOIN spell_script_target t ON t.entry = s.spell
  JOIN gameobject g ON t.type = 3 AND g.guid = t.targetEntry
  WHERE s.class = 12 OR s.bonding = 4
UNION
SELECT DISTINCT 'focus', gt.data0, g.map, ROUND(g.position_x, 1), ROUND(g.position_y, 1), ROUND(g.position_z, 1), GREATEST(gt.data1, 5)
  FROM gameobject g JOIN gameobject_template gt ON gt.entry = g.id
  WHERE gt.type = 8 AND gt.data0 <> 0"

mkdir -p "$(dirname "$OUT")"
tmp="$OUT.tmp"
if ! MYSQL_PWD="$PASS" mysql -u "$USER_" -h 127.0.0.1 -N -B "$DB" -e "$QUERY" > "$tmp"; then
    rm -f "$tmp"
    echo "export-quest-spots: the database query failed (is the server's MySQL running?)"
    exit 1
fi
mv "$tmp" "$OUT"
echo "export-quest-spots: $(grep -c '^item' "$OUT") item spots, $(grep -c '^focus' "$OUT") spell focus spots -> $OUT"
