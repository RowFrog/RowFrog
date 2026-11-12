# 23. Screen controls: round X at the top left, cards close at their top right, tinted tips

- Date: 2026-11-12
- Status: decided (owner), parts still open (see below)
- Where: `ios/RowFrog/CloseButton.swift`, `ios/RowFrog/TintedTipView.swift`, `closeX` in `web/public/app/shared.js`, `.card-x` and `.tip` in `web/public/app/style.css`
- Audit and mock-ups: https://claude.ai/artifact/Ti3UG3YJxEN49Xy5zuYwhW, https://claude.ai/artifact/L5UeYpMwSonxmjmBcef35i

## Decision

1. Option A for every screen in the audit (boards 1 to 10): a screen or sheet that is only looked at closes with the round X at the top left, as iOS 26's close role (`CloseToolbarItem`, website `closeX`). Sheets that edit something keep Cancel at the left and Done at the right.
2. The value page's title is the menu to jump to another value (Apple's title menu). The launch point sheet's expand button moves to the right. The weather map's layer menu moves to the right.
3. Cards inside a screen (a tapped spot on the lake, a turning point) close with a grey round X at their own top right (`CardCloseButton`, website `.card-x`), as Maps' place cards. On the website the spot's X was blue and the turning point had a Done pill.
4. Tips are a box tinted with the tip blue (14 % light, 22 % dark) instead of a solid box, in the app (`TintedTipView`) and on the website (`.tip`). "For now", owner's words.
5. The same on the website, in every layout.

## Still open (owner to pick)

- How the value page goes to the next value (board 12: chevrons only, symbol + chevron, one bar with dots, or no buttons as Weather).
- Whether cards keep the X at the top right (recommended, as Apple Maps) or move it to the top left (board 13).
- Step 2 of option A: satellite picture and rain radar take the lake map's layout (X and name chip, layer buttons on the right, colour scale in the panel), the weather map's layer picker becomes a button above the panel, and the lake map's panel becomes a side card on wide screens (iPad landscape, iPhone on its side).

## Why

Close controls differed from screen to screen: an X at the top left on the lake map, Fertig at the top right elsewhere, a blue X on one card and Fertig on the next. iOS 26 puts the close button at the top leading edge.

## Turned down

Option B, Fertig at the top right everywhere: it would have needed a title bar over the full-screen maps, which costs map room, most of all on a phone turned sideways.
