# 0047. Small lake maps stand on the street map, as the lake view

- Date: 2026-11-17
- Status: decided (owner, thread "Match the wave map to the wind map", 17 Nov 2026 12:46 CET: option B of the mock-ups; 13:02 CET: the lake view tile follows)
- Where: app `ios/RowFrog/LakeMiniMap.swift` (`LakeMiniMap`, `LakeMiniFrame`), `ios/RowFrog/DetailLakeCard.swift`, `ios/RowFrog/MapTimeControls.swift` (`MapLinkButton`, `MapTimeControls`, shared with `DetailMapCard`); website `web/public/app/lakeview.js` (`drawMiniMap`, `miniFrame`, `miniBase`), `web/public/app/valuepage.js` (`wavesMap`, `wireControls`)

## Decision

- The small lake map of the lake view tile and of the waves page shows the lake on the street map, as the lake view a tap opens: Apple's muted map in the app (a still picture, taken once per lake, size and appearance), OpenStreetMap on the website (MapTiler's dark street map in dark mode).
- The land is not dimmed. Faint arrows on land show the weather map's wind, faded in from the lake's near the shore; the lake keeps its own arrows and colours.
- The page's club has its blue mark (house or rower) as on the other maps; other clubs keep their small dots.
- The waves page's map card is shaped as the weather map cards: the hour in the header, the chain button ("Linked" / "Own time"), and play, slider and repeat through the lake view's hours.
- Without the map picture (no connection, or dark mode on the website without a MapTiler key) the lake stands on the plain box as before.

## Why

The owner compared the wind and waves detail views: the wind card had a map and the time controls, the waves card the lake alone on grey. A card opens the lake view, so it should look like what it opens; the lake view shows the land with the wind's arrows. The tile uses the same small map, so it follows. A still picture keeps scrolling as light as the plain lake (the reason the tile had no map, 12 Nov 2026). Mock-ups: https://claude.ai/artifact/TRuBHqsCd3RgK4Kj9kgBUu

## Turned down

- A: the same map with the land dimmed and no arrows on land: cleaner, but unlike the lake view it opens.
- C: the weather map's own 50 km frame: the lake too small to read its waves.
- Dimming the land in the lake view too: the arrows on land show where the wind comes onto the lake on every layer.
