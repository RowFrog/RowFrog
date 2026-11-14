# 0037. App and website detail check: the owner's picks

- Date: 2026-11-14
- Status: decided (owner, thread "Bug Fixes", 13:10, 13:39, 13:42 and 13:43 CET; mock-ups artifact TiYN4fb4NLEY9Gy4fvjA1c)
- Where: app `RootView.swift` (TopEdgeFade), `ConditionsCard.swift` (CloudColours, chart axis, map strip), `RoutePinImage.swift`, `LakeMapScreen.swift`, `ClubPageLayout.swift`, `AppSettings.swift`, `AllRoutesView.swift`; website `style.css`, `chart.js`, `values.js`, `arrange.js`, `lakeview.js`, `shared.js`

## Decision

1. **The website follows the app everywhere:** colours, top bar, spacing, symbols (the nearest symbol where there is no exact one), chart look, iPad layouts by window width.
2. **Warning wording C:** "Amtliche Gewitterwarnung · Keine", "Amtliche Regenwarnung · Keine" instead of "Kein Niederschlag".
3. **Title fade A:** solid page colour behind the floating club name down to just below it, then an 8 pt fade (over a background picture thick glass instead of the page grey).
4. **Cloud chart A (for now):** "Alle" a grey area behind; high, middle and low cloud one blue from light to dark. The colour thread may change the palette later.
5. **Route waypoints:** numbered on both. The disc follows the mode: white in light mode and on satellite pictures, dark grey in dark mode, blue ring and number. A later point that would overlap an earlier one is hidden.
6. **Route panel B (iPhone):** route planning opens the panel at half height with the planning controls; the map zooms the route into the room above it.
7. **Chart map strip:** the strip of hours with maps, its marker line and badge are teal (green read as the rowing light, grey as "no forecast"); the strip ends where the plot ends.
8. **Chart axis:** "Jetzt" under the start of a forecast on both; no label is cut at an edge.
9. **Page order:** Aktuelle Bedingungen comes before Warnungen in the arrange sheet. Reordering on the web uses drag handles on touch screens, arrow buttons otherwise.
10. **Alle Werte:** closed by default, remembered per club until the app restarts.
11. **Route tempo:** 2:30 /500 m by default, plus a Standard-Tempo setting in Settings › Routes.
12. **Routen chip:** shown in the app too (it already was, when the lake has routes).

## Why

The side-by-side check of 31 screens found the app and the website drifting apart in many small ways. One reference (the app) keeps them together. Each pick came from a mock-up with options.

## Turned down

- Title fade B (headings pinned under the bar): more work and 20 pt of screen.
- Cloud colours B (three hues) and C (line styles).
- A grey strip for the map hours: it reads as "no forecast" or "stale forecast".
- Route panel A alone (zoom only, panel still tall).
