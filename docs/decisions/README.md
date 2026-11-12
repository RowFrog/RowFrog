# Decisions

Why the app, the backend and the website are as they are: one short file per
decision, numbered in order. Read the relevant ones before changing something
they cover.

Records 1 to 18 were written on 2026-11-12 from the project's notes. Where a
reason or an alternative was not written down at the time, the record says
"Not recorded." rather than guess.

## Adding one

When the owner decides something that shapes the product or the code (a pick
from options, a rule for how work is done), add the next number:
`NNNN-short-title.md` with Date, Status, Where, and the sections Decision, Why
and Turned down. Keep it to a few lines. A later decision that replaces one
sets the old file's status to `replaced by NNNN` instead of deleting it.

Day-to-day details (test steps, switches, workflows) belong in
`docs/handbook.md`, not here.

| # | Date | Decision |
|---|---|---|
| 1 | 2026-10-18 | [iOS first, in SwiftUI, with a Python backend](0001-ios-first-in-swiftui-with-a-python-backend.md) |
| 2 | 2026-10-18 | [Southern Germany first, clubs at the Starnberger See first, an open list](0002-southern-germany-first-clubs-at-the-starnberger-see-first-an.md) |
| 3 | 2026-10-18 | [The app is free; free data sources; waves and ice are calculated](0003-the-app-is-free-free-data-sources-waves-and-ice-are-calculat.md) |
| 4 | 2026-10-18 | [Webcams only with permission](0004-webcams-only-with-permission.md) |
| 5 | 2026-10-18 | [Rowing is only advised while the sun is up](0005-rowing-is-only-advised-while-the-sun-is-up.md) |
| 6 | 2026-10-18 | [Proprietary licence, public repository](0006-proprietary-licence-public-repository.md) |
| 7 | 2026-10-20 | [Forecasts as static files, free hosting first, one address](0007-forecasts-as-static-files-free-hosting-first-one-address.md) |
| 8 | 2026-10-21 | [The app is called "Row Frog"](0008-the-app-is-called-row-frog.md) |
| 9 | 2026-10-24 | [Screenshots on demand](0009-screenshots-on-demand.md) |
| 10 | 2026-10-25 | [The website lives in this repository and follows the app](0010-the-website-lives-in-this-repository-and-follows-the-app.md) |
| 11 | 2026-10-30 | [The newest Xcode decides a merge](0011-the-newest-xcode-decides-a-merge.md) |
| 12 | 2026-11-04 | [Split very large Swift files as they are touched](0012-split-very-large-swift-files-as-they-are-touched.md) |
| 13 | 2026-11-06 | [The rowing light counts water within 1 km of the launch point](0013-the-rowing-light-counts-water-within-1-km-of-the-launch-poin.md) |
| 14 | 2026-11-06 | [Half-and-half dots in the hour of sunrise and sunset](0014-half-and-half-dots-in-the-hour-of-sunrise-and-sunset.md) |
| 15 | 2026-11-06 | [Publish schedule: all clubs four times a day](0015-publish-schedule-all-clubs-four-times-a-day.md) |
| 16 | 2026-11-11 | [One load state for everything the app loads](0016-one-load-state-for-everything-the-app-loads.md) |
| 17 | 2026-11-11 | ["No official warning" instead of naming the service](0017-no-official-warning-instead-of-naming-the-service.md) |
| 18 | 2026-11-12 | [Launch switches: one list, still on in Release](0018-launch-switches-one-list-still-on-in-release.md) |
| 19 | 2026-11-12 | [German texts in a String Catalog](0019-german-texts-in-a-string-catalog.md) |
| 20 | 2026-11-12 | [HSTS for one year right away](0020-hsts-for-one-year-right-away.md) |
| 21 | 2026-11-12 | [Statecharts as shared chart files (D-lite)](0021-statecharts-as-shared-chart-files-d-lite.md) |
| 22 | 2026-11-12 | [Route editor: every edit counts, Save as new, a real Undo](0022-route-editor-every-edit-changes-save-as-new-real-undo.md) |
| 23 | 2026-11-12 | [Club page columns: set by the window, kept when the list moves](0023-club-page-columns-set-by-the-window.md) |
| 24 | 2026-11-12 | [Satellite card opens on the clearest picture when the club is covered](0024-satellite-card-opens-on-clearest-when-club-is-covered.md) |
| 25 | 2026-11-12 | [The table finishes its last night with the coarser model](0025-night-after-48-hours-from-coarser-model.md) |
| 26 | 2026-11-12 | [The lake map's panel is a card at the bottom left on wide screens](0026-lake-map-panel-card-on-wide-screens.md) |
| 27 | 2026-11-12 | [Screen controls: round X at the top left, cards close at their top right, tinted tips](0027-screen-controls-close-x-top-left-tinted-tips.md) |
| 28 | 2026-11-12 | [All saved routes in Settings](0028-all-saved-routes-in-settings.md) |
| 29 | 2026-11-12 | [Cold-water badge: what to do, in words, no temperature](0029-cold-water-badge-words-only.md) |
| 30 | 2026-11-12 | [The lake tile shows its parts as a small table, wind with its direction](0030-lake-tile-parts-as-a-table-with-wind-direction.md) |
| 31 | 2026-11-12 | [iOS 18 or later](0031-ios-18-or-later.md) |
| 32 | 2026-11-12 | [Website tour like the app's, river tip, OpenStreetMap place card](0032-website-tour-river-place-card.md) |
| 33 | 2026-11-12 | [Screenshots cover every device, orientation, browser and scroll position](0033-screenshot-matrix-app-and-website.md) |
