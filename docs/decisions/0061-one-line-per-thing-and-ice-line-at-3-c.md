# 0061. One reason line per thing near the launch point; the ice line only at 3 °C or colder

- Date: 2026-11-22
- Status: decided (owner, thread "Review fog warnings and ice line", 22 Nov 2026 17:19 CET (16:19 UTC): fog option A and ice option A on the options page "Fog lines and ice row").
- Where: app `ForecastHour.shownReasons`, `ForecastHour.nearbyWithLaunchPoint`, `ClubForecast.iceValue`, `IceSeason.openWaterC` (`ios/RowFrog/Models.swift`); website `shownReasons`, `iceValue`, `OPEN_WATER_C` (`web/public/app/logic.js`) and `nearbyWithLaunchPoint` (`web/public/app/shared.js`).

## Why

An iPhone screenshot of MRC 1880 on 22 Nov 2026 showed two fog lines: a red "Nebel im Umkreis von 1 km um den Steg: Sicht 0,3 km." (the water within 1 km, below 500 m) and an orange "Nebel: Die Sicht ist schlecht." (the launch point itself, 500 to 1000 m). They read as two opinions on one thing. The card printed every reason as its own line; nothing joined two reasons on the same topic.

The same screenshot showed "Eisdecke · Kein Eis · Wasser 7,9 °C, zu warm für Eis" under the daylight row. The line showed whenever the water was below 8 °C, but the backend calls measured water above 3 °C open water (`OPEN_WATER_C`, `backend/rowfrog/ice.py`), so between 3 and 8 °C the line said it was too warm for ice.

## Decision

- Where the water within 1 km (`nearby_water`) sets the light for the same thing as one of the launch point's own reasons (fog, wind, gusts, waves, heavy rain, thunderstorm, hail), the card, the VoiceOver "Why" and the club list's "Why" show one line in the worse colour, with both values: "Nebel: Sicht am Steg 0,7 km, im Umkreis von 1 km nur 0,3 km." Without a launch point value the nearby sentence stays as before. The hour's reasons and light are not changed.
- The ice line under the daylight row (and the ice value in widgets) shows when the estimate reports more than open water, or when the water is at or below 3 °C. The ice detail page without an estimate says "too warm for ice" only above 3 °C.

## Turned down

- Fog B: two lines, "Am Steg" and "Im Umkreis von 1 km", each with its value. Still two lines for one thing.
- Fog C: only the worse line. Loses that the launch point itself is better.
- Ice B: only when ice is reported. Loses "Kein Eis" in deep winter, which tells the rower the app did check.
- Ice C: keep 8 °C, hide only measured "too warm". Lakes without a station would still show "Kein Eis" from 8 °C down.
