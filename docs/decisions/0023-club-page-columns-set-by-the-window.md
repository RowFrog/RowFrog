# 23. Club page columns: set by the window, kept when the list moves

- Date: 2026-11-12
- Status: decided (owner, 12:03 CET, option B)
- Where: the app leads (`ClubPageColumns` in `ios/RowFrog/ClubPageLayout.swift`, owner: the app is the reference, the website follows); website `web/public/app/app.js` (`balanceCards`, `COLUMNS`)
- Mock-ups: https://claude.ai/artifact/6Zrnnmuwtq2fZFMTUGj875

## Decision

On wide windows the club page's cards go into up to three columns, each card 380 to 560 px wide. The window sets the count, worked out as if the list beside the page were shown. Sliding the list away or back only widens or narrows the same columns, and no card moves to another one. Three columns start when the room (the page without its 16 px padding) reaches 1,200 px, and it only goes back to two below 1,172 px (3 × 380 + 2 gaps). The count is worked out again 300 ms after a resize stops, and the card at the top of the window stays at the top. The top tile always spans the full width.

## Why

Big screens left wide empty bands beside a 1,000 px page. Cards that jump between columns when the list moves make you lose your place.

## Turned down

- A: recount on every list toggle (cards jump between 2 and 3 columns at 1280–1512 px).
- Keep 2 columns.
- Four or more columns: the 48-hour table gets too narrow and the cards spread too far to scan.
