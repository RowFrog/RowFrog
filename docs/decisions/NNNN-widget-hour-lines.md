# NNNN. Wind, waves and visibility under the hours in the large widgets

- Date: 2026-11-13
- Status: decided (owner, thread "Bug Fixes", 13 Nov 2026 09:56 and 10:40 CET: large "option B with legend", XL agreed, no "°" next to a °C legend)
- Where: `ios/RowFrog/WidgetLayouts.swift` (`hourRow`, `HourLine`, `largeLayout`, `extraLargeHours`), `Units.swift` (`Format.temperatureNumber`)

## Decision

The large and extra large widgets show three lines under each hour's
temperature: wind (mean–gust), waves and visibility, the trio the lake view
uses. A legend column on the left names each line's symbol and unit, so the
numbers go without units and the temperatures without "°" (as in the 48 h
table). Where the trio doesn't fit (smaller iPhones, the "values below" layout,
bigger text sizes), the widget falls back by itself to the temperature and
wind lines without a legend, so it never runs over. Medium and small stay as
they were. Mock-ups: artifact "Widgets: every size" (owner's pick B with
legend for large and extra large, 13 Nov 2026).

## Why

Wind, waves and visibility decide the light; showing them per hour explains
the dots. The legend saves repeating units in every column.

## Turned down

- The trio in the medium widget: about 55 pt too tall.
- Option A (lines without a legend, units in each cell): too wide in six columns.
