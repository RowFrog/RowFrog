# 0061. In columns the warnings card spans the page, and warnings for the same place and time are one block

- Date: 2026-11-22
- Status: decided (owner, thread "Lay out warnings tile in wide views", 22 Nov 2026: "I like C" 17:13 CET (16:13 UTC) after checking the links, "Go ahead" 17:15 CET (16:15 UTC); mock-ups https://claude.ai/artifact/UH6J5zf4aA9Kmz9H2oLdU2)
- Where: `ios/RowFrog/WarningsCard.swift` (`WarningGroup`, `WarningBlocks`, `WarningBlock`), `ios/RowFrog/LocationPageView.swift` (`columns:`), `web/public/app/logic.js` (`warningGroups`), `web/public/app/app.js` (`warningBlocks`, `warningBlock`, `data-cols` in `balanceCards`), `web/public/app/style.css` (`.warn-blocks`), shared rule `testdata/states/warning-groups.json`.

## Why

On the iPad (owner's screenshot, 22 Nov 2026 04:30 CET) the warnings card spanned the whole page with Frost and Glätte stacked: the same time, note and both DWD links twice, and lines running across the full width. The DWD link depends only on the club's town (and on lake or weather warning), and the WarnWetter link is one App Store link, so warnings for the same place and time lead to the same pages.

## Decision

- The warnings card keeps spanning all columns in every multi-column view (iPad, iPhone on its side, website), under the top tile.
- Warnings of the same service, kind, place, start, end and page are one block: the time once, each warning's headline, text and advice, one note about the rowing light (each its own note when they differ), one set of links. The bar has the colour of the worst level in the block. Lake warnings are never merged. This holds on the iPhone too.
- In columns the blocks sit side by side, at most one per page column, sharing the width; more go to a new row. "Now" and "Later" keep their own rows. A block alone puts its parts side by side: a single warning its text left and advice, note and links right; merged warnings their texts.
- App first, the website the same.

## Turned down

- A: the card as one column card, top left: taller than before, and a lake storm warning would no longer be the band under the light.
- B: blocks side by side without merging: the repeats stay.
- D: one line per warning, details on tap: the official texts would no longer be visible at a glance.
