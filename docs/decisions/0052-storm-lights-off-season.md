# 0052. Out of season the warnings card says the storm lights are off, in one fixed order

- Date: 2026-11-20
- Status: done (owner's pick on 20 Nov 2026, 12:15 CET (11:15 UTC): option A, order 1, with the transitions; mock-ups https://claude.ai/artifact/SzqcwixPXWgaCoLKgFBeEq)
- Where: `ShoreLightsGuide` and `ShoreLightsSeason` in `ios/RowFrog/ShoreLights.swift`, order in `WarningsCard.card`; website `shoreLights()`/`warningsBody()` in `web/public/app/app.js`, `shoreLightsState()` in `web/public/app/logic.js`; season per lake in `data/shore-lights.json`, sent as `warnings.shoreLightsSeason`; shared rule `testdata/states/shore-lights-season.json`

## Why

The row "Was die Sturmwarnleuchten bedeuten" stood the same all year. From November to March the lights on the Bavarian lakes do not run, and the thing a rower needs to know then is that nothing will flash, not what the flashes mean. The owner also noticed the row moved: under the lake warning when a warning was out, under the "Umfasst …" line when none was.

## Decision

- On a lake with season `apr-oct`, the row reads "Sturmwarnleuchten aus bis 1. April" from 1 November to 14 March and "Sturmwarnleuchten ab 1. April wieder an" from 15 to 31 March (German time), with a muted beacon. Tapping it still opens the explanation, led by "Von November bis März blinkt am Ufer nichts, auch bei Sturm. …"; the two flash rows are dimmed.
- From 1 April to 31 October the row is as before.
- Lake Constance (`all-year`) keeps the row all year, and its footnote says the lights run all year, for shorter hours in winter. Forggensee, Walchensee and Steinhuder Meer have no season in the list (their dates were not confirmed) and keep the summer wording.
- One order in every state of the card: warnings (or "Derzeit keine Warnung"), then the shore lights row, then what was checked. The lake warning's own text already says how often the lights flash.

## Sources and gaps

- Bavarian season 1 April to 31 October: the app's existing text and the Bavarian notice (AllMBl. 2010 S. 170) as listed in data/shore-lights.json.
- Lake Constance all year (winter 7 to 20 h, summer 6 to 22 h since 1 April 2024): DWD RWB Stuttgart via wetterdienst.de "Thema des Tages" 5755, seen in a web search on 20 Nov 2026; the page could not be opened from the cloud session.
- Forggensee and Walchensee have their own start dates in the notice (web search, 20 Nov 2026); the dates themselves are still to be read.
- Unclear: whether DWD issues lake warnings for inland lakes outside the season.

## Turned down

- B: keep the link with a grey "aus bis 1.4." label (wraps on small iPhones, easy to miss).
- C: one sentence in the footer (smallest, greyest text; not tappable).
- D: hide the row in winter (leaves the dangerous assumption that the lights would warn).
- Order 2 (lights first) and 3 (lights last, under the footer).
