# 32. Website tour like the app's, river tip, OpenStreetMap place card

- Date: 2026-11-12
- Status: decided (owner, thread "First-Start Tutorial and One-Time-Tips")
- Where: `web/public/app/tour.js`, `web/public/app/osmplace.js`, `web/public/app/app.js`, `ios/RowFrog/TutorialTips.swift` (`RiverCurrentTip`), API `mapPlace.osm`

## Decision

1. The website tour gets the app's pages 2 and 3: on a first visit the visitor picks a home base and more clubs inside the tour, as in the app.
2. The tour's River page shows when a river club is among your clubs, now also on the website. Because a visitor can only pick a river club after the welcome page, the app and the website also get a one-time tip "Current on the river" on the Current tile, for anyone who never saw the River page.
3. The website's Location sheet gets a small place card of our own: the line "In OpenStreetMap as “…”" opens the club's OpenStreetMap place with its name, directions and its OpenStreetMap page. The API's `mapPlace` carries the place's OpenStreetMap id (`osm`) for it. No tip for it, as for the app's Apple Maps place card.

## Why

The website's first visit left out choosing clubs, and the River page could only show for clubs chosen before the tour. The app shows Apple's place card; the website has no Apple place, but it has the OpenStreetMap place the catalog matched each club to.

## Turned down

Leaving the website tour shorter than the app's; Apple's place card on the website (needs MapKit JS and an Apple key).
