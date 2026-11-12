# 30. The lake tile shows its parts as a small table, wind with its direction

- Date: 2026-11-12
- Status: decided (owner, 15:18 CET)
- Where: app `LakeZoneTable` (`ios/RowFrog/LakeZoneTable.swift`), `LakeView.zoneReading` (`LakeZoneNotes.swift`), `LakeViewCard`; website follows (app leads)
- Mock-ups: https://claude.ai/artifact/YNAbsMPXKRbYt3DpVPHpZ5 (options A–H)

## Decision

Option H1. The parts of the lake (Norden, Mitte, Süden …) are a small table styled like the 48-hour table: each column's icon over its unit, one line under the header. A map symbol stands over the parts' names, on the left like the clock over the times. One wind symbol stands over two columns: an arrow for where the wind blows (under a compass) and the speed, wind to gusts (under the unit). Values that set amber or red keep their colour. When the table does not fit (narrow phones, larger text), each part falls back to its name over its values, the direction as an arrow after the speed ("2–4 m/s ↙"). The wind line under the parts is gone.

## Why

The three values wrapped next to the map, and the wind line repeated the lake's wind with a range that meant something else (lowest to highest wind across the lake, while a part's range is wind to gusts). Its only new facts were the direction, now per part, and the lake's highest gust.

## Turned down

A (tighter line): wraps again with letters or longer values. C (narrower map): smaller lake, wraps with longer values. D (direction once above the table), E (arrow and letters column), G1/G3 (compass or "N↑" as a separate column), H2 (the word "Bereich"), H3 (map symbol centred: it floats between names and numbers).
