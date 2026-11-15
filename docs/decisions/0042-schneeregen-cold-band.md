# 0042. Schneeregen from rain and snowfall, asked only in the cold band

- Date: 2026-11-15
- Status: decided (owner, thread "Check rain start time jumping", 15 Nov 2026 14:48 CET: "implement it with guardrails", with a log of the extra calls)
- Where: `backend/rowfrog/sleet.py`, `backend/rowfrog/sources/open_meteo.py` (`parse`, `fetch_outlook`), `scripts/publish_static.py` (`club_weather`, `club_outlooks`, `count_sleet`, `sleet_line`); app `ios/RowFrog/Sky.swift` (`.sleet`); website `web/public/app/logic.js` (`sky`, `SKY_TITLES`, `precipitationKind`, `skyIcon`)

## Decision

- Open-Meteo sends no weather code for a rain-snow mix (WMO 68/69): an hour comes as rain or as snow. The Pi asks for the hour's `rain` and `snowfall` too and marks an hour in which both fall (each at least 0.05) as 68 (light) or 69 (from 2.5 mm). Only drizzle, rain, snow and shower codes are replaced; freezing rain, thunderstorms and hail stay.
- Guardrail: the two values are asked only for clubs whose last forecast has a wet hour (from 0.1 mm or a drizzle to snow code) at −2 to +4 °C in the next 48 hours, or, for a club without a forecast yet, in October to April. Other clubs cost nothing extra.
- App and website show 68/69 as "Schneeregen" (sleet symbol, the same as freezing rain; "Schneeregen" as what falls). The widget follows the app's `Sky`. Older app versions show 68/69 as rain (their default).
- The cost is logged: each run prints `Schneeregen: N clubs in the cold band (-2 to 4 °C), +X Open-Meteo calls` and reports the extra calls to the usage counter as their own job `sleet` (the rest stays `publish`).
- Settings on the Pi (`~/.config/rowfrog.env`): `RW_SLEET=off` switches it off; `RW_SLEET_MIN_C`, `RW_SLEET_MAX_C` move the band.

## Why

Schneeregen matters on cold lakes in winter and was never shown. Open-Meteo counts a call per point per 10 variables, so 16 instead of 14 variables cost 0.2 calls more per club forecast (about +10 % for clubs in the band, nothing in summer). The owner asked for a way to read the cost later and switch it off or change it without a code change. Open-Meteo's documentation could not be reached from the build environment, so the variable names and the missing 68/69 are as known from it, not re-read.
