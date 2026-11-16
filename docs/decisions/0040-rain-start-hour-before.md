# 0040. Forecast rain starts an hour before its row, never before the radar's end

- Date: 2026-11-15
- Status: decided, the "hour before" part now done once in the backend (decision 0043); decided by the owner, thread "Check rain start time jumping", 15 Nov 2026 12:12 CET: option 1)
- Where: `ios/RowFrog/ConditionsCard.swift` (`forecastRain`, `rainLines`, the precipitation detail's "Expected from"), `ios/RowFrog/RainRadar.swift` (`RainOutlook.next`, "Until about"); website `web/public/app/radar.js` (`forecastRain`, `rainLines`, `rainOutlook`), `values.js`

## Decision

- Open-Meteo's precipitation at a row's time stamp is the sum of the hour before it, so the forecast's rain of the 14:00 row starts at 13:00. The "Rain from …" line, "Expected from …" in the detail view and "Until about …" (the first dry row while it rains past the radar) use that hour's start.
- While the radar covers the next two hours, forecast rain never starts before the radar's end: a dry radar to 13:55 and a wet 14:00 row read "Rain from 13:55". Rows that end inside the radar's window are left to the radar.
- A start that has already passed (without the radar, the forecast's rain hour has begun) names no time: "Regen in dieser Stunde", in the detail view "Erwartet in dieser Stunde" (owner's card, 15 Nov 2026, recommended option taken while the answer is open).
- The widget is unchanged: it names rain only from the radar.

## Why

On 15 Nov 2026 two loads a minute apart (11:55 and 11:57 CET, same file, run 09 UTC) showed "Regen ab 13:00" and "Regen ab 14:00". The first had no radar yet and took the 13:00 row (light-rain code, 0.0 mm); the second had the radar to 13:55, skipped the 13:00 row and took the 14:00 row (0.1 mm), whose rain falls from 13:00. Both times were an hour late for their own source. With this rule the two loads read "ab 12:00" (forecast only; "in dieser Stunde" once 12:00 has passed) and "ab 13:55" (radar dry to 13:55, then the forecast); the gap stays, but each time is right for its source. Which hour Open-Meteo's weather code describes is not checked (its documentation could not be reached from the build environment); the code-only rows follow the same rule.
