# 0046. A cold start shows the last page at once; a first start shows sweeping stand-in cards

- Date: 2026-11-17
- Status: done (owner's pick on 17 Nov 2026, 12:20 CET: "Build all three now", from the mock-ups artifact "Row Frog cold start")
- Where: `ios/RowFrog/ColdStart.swift`, `ForecastStore.primeKept` and `LocationStore.primeCatalog` (LocationStore.swift), `LakeViewStore.primeKept` (LakeView.swift), `SatellitePictureStore.primeKept` (SatellitePicture.swift), `APIClient.keptNow` / `keptForecastNow`, `LoadingCards` and `LoadingSweep` (LocationPageView.swift), the "Loading the forecast…" line in ClubPageHeader.swift, `UILaunchScreen` in `ios/project.yml` with the colour `LaunchBackground`; website `renderClub`, `loadingCards`, `forecastLines` in `web/public/app/app.js`, `.shimmer` in style.css

## Decision

- **Start with data kept from the last visit (almost every start):** before its first frame the app reads the kept club list, the first club's forecast, its lake view and satellite picture list (with the picture the card opens with), and the page's background picture. The page opens complete with "Updating…" in the header while the new data loads, as decision 0044 already did a moment later. Each of them still downloads once the page asks. A kept lake view older than a day is left out. The website reads the kept forecast from Cache Storage before it draws the club page.
- **Nothing kept (first start, a club never opened):** the stand-in cards stay, with a soft band of light sweeping over shapes instead of "–°" dashes, and "Loading the forecast…" moves into the header's update line. With Reduce Motion (app) or `prefers-reduced-motion` (website) the shapes stand still.
- **Launch screen:** iOS's grouped background colour, light and dark (`LaunchBackground`), the colour of a page without a picture (the default). The owner picked a lake-blue launch screen; on checking, pages have no picture unless one is chosen, so blue would have flashed before a white or black page. With a picture chosen, the picture is now in the first frame instead of fading in.


## Why

The owner's screen recording (16 Nov 2026, build 885) showed empty cards and "Vorhersage wird geladen …" for a moment after every cold start. On main after #492 the order was still: white launch screen, a spinner while the club list was read, stand-in cards, then the kept forecast, with the lake view and satellite picture last (checked in the code, not measured on a phone).

## Turned down

- A launch screen with the frog held until the data is there (option C): makes the user wait on purpose, and Apple's guidelines advise against it.
- One frog card instead of the stand-in cards (option D): the page jumps from one card to five when the data comes.
