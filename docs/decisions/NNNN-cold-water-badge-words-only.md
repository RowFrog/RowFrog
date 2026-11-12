# NNNN. Cold-water badge: what to do, in words, no temperature

- Date: 2026-11-12
- Status: decided (owner)
- Where: `ios/RowFrog/Limits.swift` (`ColdWaterKit.title`), `ios/RowFrog/TrafficLightView.swift` (`ColdWaterBadge`), `web/public/app/shared.js` (`coldWaterText`, `coldWaterBadge`)

## Decision

The blue badge under the rowing light says what to do in full words, with no temperature and no ≈: "Weste tragen", "Weste tragen · nur mit Begleitboot" (boats that may be singles, below 10 °C) or "Weste tragen · ufernah rudern" (bigger boats, below 10 °C). In English: "Life jacket on", "Life jacket on · with partner boat", "Life jacket on · stay near shore" (owner's pick E5), which fit on one line on every screen at the default text size. Where it does not fit on one line (larger text sizes) it wraps onto a second line instead of shortening. The list row shows the same words on up to two lines.

The full advice for bigger boats below 10 °C now says "row with a second boat nearby" instead of "don't row alone".

## Why

"≈ Rettungsweste · in Ufernähe" read as a life jacket lying near the shore, and the ≈ (water estimated) looked as if it belonged to the life jacket. The water value sits just below the badge, blue when cold and marked ≈ when estimated, so the badge does not need to repeat it. "Don't row alone" made no sense in an eight.

## Turned down

The temperature on the badge in one line (A1: falls back to a terse short form on every screen in German), with extra symbols per part (A2: no standard symbols for a vest or a shore), or on two lines (A3). Mock-ups: rowerweather/cold-water-badge/badge-mockups.html in the project files.
