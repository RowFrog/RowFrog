# 0043. Every hourly rain value is shown under the hour it fell

- Date: 2026-11-16
- Status: decided (owner, thread "Check rain start time jumping", 16 Nov 2026 13:26 CET: option 2, "Tile, list, charts, widget")
- Where: `backend/rowfrog/sources/open_meteo.py` (`rain_to_hour_start`, called by `parse`), `scripts/publish_static.py` (saved forecasts moved once, mark `rain_at_hour_start`); app `ios/RowFrog/ConditionsCard.swift` (`forecastRain`), `ios/RowFrog/RainRadar.swift` ("Until about"); website `web/public/app/radar.js` (`forecastRain`, `rainOutlook`)

## Decision

- Open-Meteo's precipitation at a time stamp is the sum of the hour before it. The backend moves each value one row earlier when it reads a forecast, so the 12:00 row holds the rain from 12:00 to 13:00. That is how the app, widget and website read every row ("Now, 12:00 to 13:00", the 48 hours, the detail chart, the widget's day bars, the rowing light's rain), so they all become right at once.
- A weather code that names something falling (drizzle to hail, 51-99) moves with the rain, so the symbol and the amount stay together. Cloud and fog codes stay where they are. Whether Open-Meteo's code describes the hour before or the moment is not clearly documented (unclear; its documentation could not be reached from the build environment), so the code follows the amount.
- The last row of a forecast has no next hour, so it has no amount (beyond the 48 hours and the night after them).
- Schneeregen (decision 0042) is worked out per Open-Meteo row first and then moves with its rain.
- The app and website no longer subtract an hour themselves (decision 0040's "row time minus 1 h"). "Rain from" is the wet hour's start, never before the radar's end. "Until about" is the first dry hour's start.
- Forecasts the Pi saved before this change are moved once when it reads its state, so no saved forecast is moved twice and none stays an hour late.

## Why

On 16 Nov 2026 the Website thread found that without a radar reading the rain tile's "now" showed the previous hour's rain (the 12:00 row at 12:24), and the 48 hours and charts had the same one-hour shift. The owner picked the full fix over the rain tile alone. The installed app builds (885) predate decision 0040, so they pick up the corrected rows as they are.

## Not done

- The detail chart draws each rain bar centred on its hour's time stamp, not in the middle of the hour. Moving the bars half an hour would change how scrubbing picks a value, so it waits for Simulator screenshots on the Mac.
- Gusts are also a maximum over the hour before (Open-Meteo); they are not moved.
