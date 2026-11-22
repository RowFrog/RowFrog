# 0060. Wind shows one number when mean and gust round the same; hour tables keep both

- Date: 2026-11-22
- Status: decided (owner, thread "Fix "1–1" wind speed display", 22 Nov 2026 17:16 CET (16:16 UTC): option B "Once, but keep tables").
- Where: app `Format.windRange` / `Format.windSpan` (`ios/RowFrog/Units.swift`), top tile `TopTileValues.swift`, widget hour line `WidgetLayouts.swift`; website `windRange` / `windPair` (`web/public/app/shared.js`).

## Why

The owner's iPad (22 Nov 2026 04:30 CET) showed wind "1–1 m/s" on the MRC 1880 list card and top tile: mean wind and strongest gust both rounded to 1 m/s, and the formatter always printed both numbers. It looked like a mistake.

## Decision

- Wherever wind is shown as mean–gust outside a table (club list card, top tile, widgets, "Alle Werte", lake and route summaries, map probes), it shows one number when both round the same in the chosen unit: "1 m/s" instead of "1–1 m/s". "2–5 m/s" stays as it is.
- Hour tables keep both numbers so the column always reads mean–gust: the club page's hour rows and night line, and the lake view's zone table ("1–1" there).
- The website follows the app with the same rule.

## Turned down

- A, one number everywhere including tables: one rule, but a table column would mix single numbers and pairs.
- C, keep "1–1": reads as an error.

Mock-ups: https://claude.ai/artifact/6Xzb4mu6M67Kj8wEPZ3NXV
