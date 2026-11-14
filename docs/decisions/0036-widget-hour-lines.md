# 0036. Wind, waves and visibility under the hours in the large widgets

- Date: 2026-11-13
- Status: decided (owner, thread "Bug Fixes", 13 Nov 2026 09:56 and 10:40 CET: large "option B with legend", XL agreed, no "°" next to a °C legend; 14 Nov 2026 via the Mac thread: temperature row in the same style, medium without values, gallery per phone)
- Where: `ios/RowFrog/WidgetLayouts.swift` (`hourRow`, `HourLine`, `largeLayout`, `extraLargeHours`), `Units.swift` (`Format.temperatureNumber`), `WidgetBridge.swift` (`WidgetGalleryView`, `WidgetSizes`)

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

Added 14 Nov 2026: with the lines, the temperature row has the same small
style as wind, waves and visibility (no bigger or bolder font; the legend
keeps °C). The medium widget drops the values under the dots altogether:
time, symbol and light only. The widget gallery (`-RWWidgetGallery YES`)
draws each phone's own widget sizes from Apple's table and a dark home
screen in dark mode, so the iPhone 13 mini and SE shots show the fit.

## Why

Wind, waves and visibility decide the light; showing them per hour explains
the dots. The legend saves repeating units in every column.

## Small phones keep all values (owner, 14 Nov 2026, 14:34 CET)

"Wouldn't it be better that the fallback also features all the values below the dots and the legend to its side?"
On the iPhone SE and 13 mini the large widget fell back to temperature and wind. It now makes room in steps first, in one
ViewThatFits for the large and the extra large widget:

1. As designed: gaps 10 pt, 5 pt between the value lines, three days.
2. Tighter: gaps 6 pt, 3 pt between the value lines, symbol row 22 pt instead of 26, 6 pt between the day bars.
3. Tighter and two days instead of three.
4. Last, for very large text sizes only: temperature and wind without the legend.

The widget gallery (`-RWWidgetGallery YES`) marks each large widget with the step it landed on.

## Turned down

- The trio in the medium widget: about 55 pt too tall.
- Option A (lines without a legend, units in each cell): too wide in six columns.
