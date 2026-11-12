# 25. The table finishes its last night with the coarser model

- Date: 2026-11-12
- Status: decided (owner, 14:35 CET)
- Where: backend `finish_night`, `FETCH_HOURS` in `backend/rowfrog/api.py` (`scripts/publish_static.py` uses the same); app `ClubForecast.coarserModel`, `NightRow`, `HourRow`; website `coarserModel` in `web/public/app/logic.js`, `nightLine` in `app.js`
- Mock-ups: https://claude.ai/artifact/6237JmLte55whpputgQV4o (options A–D)

## Decision

Option B. When the 48 hours end in the night, the table goes on to the hour the sun rises in, so the last night line reads "17–07" like every other night instead of stopping at the 48th hour. Those hours come from the next model in the chain (ICON-EU, 7 km). The owner wanted the hint inside the night line, not under the table: a second, small line in the night line says "≈ from 00:00 coarser model: ICON-EU, 7 km grid", and once the night is opened its coarser hours carry "≈" before their time. App and website show it the same way.

## Why

Every night line looks the same, and you can see the next morning. A: "17–" reads as if the night ended at midnight. C (stop at sunset) loses the evening hours. D (a grey partial line) draws the eye and still says nothing about the morning.

## Cost

No extra Open-Meteo calls: a forecast is now loaded for 78 hours instead of 60, and Open-Meteo counts a call by its values and places, not its length (up to two weeks). Forecast files grow by up to 18 hours.
