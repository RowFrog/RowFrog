# 0041. Widget: red night dot on a night band, day bars on one clock axis

- Date: 2026-11-15
- Status: decided (owner, thread "App icon ideas", 15 Nov 2026 15:36 CET: day bars option B "axis + now line"; 15:37 CET: night dot D "with the mark as well", built as E)
- Where: `ios/RowFrog/WidgetLayouts.swift` (`nightDot`, `nightBand`, `RowingSnapshot.days`, `goodStretch`, `WidgetDay`), `ios/RowFrog/WidgetDayBars.swift` (`dayBars`)
- Mock-ups: `/mnt/project-files/rowerweather/widgets/night-dot-day-bars/mockup.png` (project files)

## Decision

- The widget's folded night column has the dimmed red dot of the app's 48-hour table night hours, with the ✕ when the widget shows marks, on an indigo band like the app's folded night line. Out of date it is grey like every hour.
- The day bars of all days share one clock axis, from the earliest first daylight hour to the latest last one of the days shown; small hour labels every third hour sit above the bars. Today's hours that are gone before the forecast starts keep their place, faint, so today's bar no longer stretches as the day ends. A white tick marks now on today's bar.
- The texts right of the bars take the widest text's room, so all bars end in line.
- A running green hour counts whole for the good stretch: at 14:56 a green 14:00 hour reads "Jetzt–15:00", as the light at the top says "Gut, bis 15:00".

## Why

Screenshot 15 Nov 2026 14:56 CET: the night column's grey dot read like "Veraltet"; today's bar held only the 3 hours still forecast, each stretched over the full width, and said "Nicht gut" while the top said "Gut, bis 15:00" (the rule wanted a whole green hour from now on, only 4 minutes were left).
