# 0053. The sunset count sits at the sun, reasons go red first, a unit takes its value's colour

- Date: 2026-11-20
- Status: done (owner, thread "Decide where sunset time appears", 20 Nov 2026: red-first order agreed 18:30 CET (17:30 UTC); option E with "Bis Sonnenuntergang zurück an Land sein." 18:41 CET; the minutes amber like the time 18:45 CET; units in their value's colour 18:47 CET; "go ahead" 18:49 CET; mock-ups https://claude.ai/artifact/KfjKqRj9QZ3HiU7SSAGPne)
- Where: `Reason.order` and `[Reason].ordered()` in `ios/RowFrog/ReasonOrder.swift`, used by `ClubForecast.current`, `LakeWide.at`, `ForecastHour.applying` (Limits.swift), the lake view's boat reasons and own places; `explanation` in `Models.swift`; `daylightLine`/`sunTinted` in `LocationPageView.swift`; `sunTile` in `ConditionTileViews.swift`; `WindView` in `TopTileValues.swift`. Backend `REASON_ORDER`/`ordered` in `backend/rowfrog/score.py`. Website `REASON_ORDER`/`orderReasons` in `web/public/app/logic.js` (also `lake.js`, `ownplace.js`), `hourExplanation` in `shared.js`, top tile and Sunset tile in `app.js`. The list itself in `testdata/reasons.json` ("order").

## Why

The owner's screenshot (iPhone, 20 Nov 2026 15:37 CET) showed the sunset twice in the top tile, a few lines apart: "Sonnenuntergang um 16:32: noch 56 min Tageslicht." as a reason and "Rudern bis 16:32 · noch 55 min" as the sun line. (The 56 against 55 came from build 885, from before #509; build 982 counts both the same.) The amber sunset line also stood above two red wind lines: the server sorted red before amber, but the app and the website then put the daylight reason first.

## Decision

- **Order of reasons**: red before amber; within one colour one fixed list, the more dangerous first: lake storm or strong-wind warning, thunderstorm, hail, ice, near-freezing and cold water, fog, gusts, wind, waves, shipping stopped, high water, current, official weather warning, heavy rain, lake drained or lowered, then daylight last (it only says when to be back). Unknown names sit just before daylight; the water within 1 km ranks as what it is about. The same list on the server, in the app and on the website.
- **Reason line in the last hour before sunset**: one line, no number: "Bis Sonnenuntergang zurück an Land sein." / "Be back ashore by sunset.", the same with the top tile open or closed.
- **Closed top tile**: the sun line keeps counting all day, as before ("Rudern bis 16:32 · noch 2 h 10 min"). In the last hour the minutes take the light's colour like the time ("16:32 · noch 55 min" amber; "Rudern bis" stays as it is). This widens the owner's pick S1 (5 Nov 2026), which coloured only the time.
- **Open top tile**: in the last hour the Sunset tile shows "noch 55 min" in the light's colour where it otherwise shows the sunrise; its time takes the light's colour like every other tile's value.
- **Units**: a value's unit takes the value's colour. Everywhere the unit already sits next to the number ("8,3°", "0,03 m", "40 km"); the wind's "m/s" sits on the grey line under the number, so there only "m/s" takes the colour and the direction ("· aus SW") stays grey.

## Turned down

- A: keep both counts (repeats itself).
- B: the count only in the reason line (the sun line loses it in the hour it matters most; the line wraps).
- C: the count only in the sun line, no reason line (an amber light from the sunset alone would have no reason; the open tile no count).
- D: one count, its place changing with the tile (the reason line's wording would change when the tile opens).
- Sorting within a colour by how far a value is over its limit (wind in m/s and fog in metres cannot be compared, and the order would change from hour to hour).
- Counting on the sun line only in the last hour (the owner wants the count all day).
