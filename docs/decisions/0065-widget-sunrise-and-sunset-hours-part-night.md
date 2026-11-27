# 0065. The widget's day bars show the sunrise and sunset hours, part night

- Date: 2026-11-27
- Status: decided (owner, thread "Show sunrise and sunset hours in widget", 27 Nov 2026: "Option C looks good, let's go with it for now." 13:55 CET (12:55 UTC); mock-ups https://claude.ai/artifact/RzHFpPtCnko6aebkAqnd7V)
- Where: `ios/RowFrog/WidgetLayouts.swift` (`RowingSnapshot.days`, `daylightHours`, `WidgetDay.nightBefore`/`nightAfter`), `ios/RowFrog/WidgetDayBars.swift` (`withNight`).

## Why

On 23 Nov the large widget's last day had one box more than today and tomorrow: only there the 16:00 hour (sunset 16:24) was counted. #655 made all days the same by leaving out the sunrise and sunset hours, but then the minutes of daylight in them (07:37–08:00, 16:00–16:24) did not show at all.

## Decision

- Every day's bar runs from the sunrise hour to the sunset hour, on one clock axis as before (0041).
- In the sunrise and sunset hours the minutes with the sun down are drawn in the night's indigo, and the daylight minutes in their light: the daylight half of the hour's half-and-half dot (`dotHalves`), so green after sunrise and amber before sunset (the last hour before sunset is amber, 6 Nov 2026), never better than the weather.
- The good-time text ("08:00–15:00") and "Bis 15:00" stay in whole hours.
- Widget only; the website has no widget.

## Turned down

- A: whole daylight hours only (the state after #655).
- B: short boxes as long as the daylight in them: too small to read at widget size.
- D: whole hours plus sunrise and sunset as a text line: one more line of height, and the reader has to work it out.
