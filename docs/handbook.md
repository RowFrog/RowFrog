# Row Frog handbook

Everything that is not visible in the app or easy to find in the code:
hidden switches, how to test things, what runs on its own and what needs
you. Keep it current: every PR that adds a hidden feature, a workflow, a
secret or a manual step adds a line here.

## Hidden in the app

| What | How to reach it | What it does |
|---|---|---|
| Developer options | Settings > About > tap **Version** seven times | Shows the Developer row on the first Settings page. Switching it off hides it again and puts every club back on the automatic weather model. Factory reset also turns it off. |
| Weather model picker (test) | Developer options on, then on a confirmed club (MRC 1880, MRSV Bayern, Tutzinger RV) tap the grey **Forecast** line at the bottom of the page | Pick Automatic (recommended), ICON-CH1, AROME or ECMWF IFS (not advised). The line then says "(your choice)". The widget always uses the automatic model. |
| Tour again | Settings > Help > Show the tour again | Replays the first-start tour; one-time tips come back on the next start. |
| Safety notice | First start, before the tour; later Settings > About > Safety notice | Has to be read to the end and agreed to. The device stores the agreed version and date (`RWSafetyAcceptedVersion`, `RWSafetyAcceptedAt`); factory reset keeps them. Raising `SafetyNotice.version` in `SafetyNotice.swift` makes everyone agree again. |
| What's new | Once after an update, to users who had already seen the tour | A sheet listing what changed (`WhatsNew` in `Tutorial.swift`). The device stores the version seen (`RWWhatsNewSeen`). For a new list: change `WhatsNew.points` and raise `WhatsNew.version`. New users finishing the tour do not get it. |
| Widget updates | Settings > Widgets > Updates | Every 30 minutes (default), every hour, every 2 hours, or only after using the app (`RWWidgetUpdates`: `halfHour`, `hour`, `twoHours`, `appOpen`; also a launch argument). With `appOpen` the widget timeline never reloads by itself; the app asks for one as the user leaves it, at most every 15 minutes. |
| Map zoom | Settings > Club pages > Weather maps > Maps start | Close, Normal (default) or Wide: how much map the weather maps in the detail views (card and full screen) open with around the club. Normal is 50 km across, rain and lightning 120 km; Close halves it, Wide doubles it. Zooming out loads more tiles; zooming by hand works as before (`RWMapStartZoom`: `close`, `normal`, `wide`; also a launch argument). |
| Battery saving in Low Power Mode | Turn on Low Power Mode in iOS Settings > Battery (or Control Center) | Tiles over a picture, the page bar's buttons and the strip behind the clock are drawn solid instead of blurred or glass (same layout), the radar map waits for the play button, and the radar (rain tile, top tile, radar card) refreshes every 15 minutes instead of 5. Turning it off brings everything back. |
| Saving data | Turn on Low Data Mode in iOS Settings > Mobile Data (or Wi-Fi > the network's (i) button), or switch on Settings > Battery and data > Save mobile data and use mobile data | Satellite pictures load only after a tap on the card (or opening it full screen), the radar map and the rain map's radar pictures take half-hour steps (7 pictures instead of 13) and the radar refreshes every 15 minutes. Forecasts, warnings and the lake view always load. Launch argument `-RWSaveData YES` acts as if Low Data Mode were on. |
| Chart and map linked | Any detail view with a map (wind, temperature, feels like, humidity, pressure, visibility, cloud, rain, UV; lightning is live and never linked): the chain button on the map card | Linked (default), the map shows the hour of the chart's blue line and playing the map moves the line. Unlinked ("Own time"), each keeps its own hour, and "Back to <hour>" moves only the chart. The choice is remembered (`RWMapTimeLinked`). A one-time tip (`MapLinkTip`) points at the chain the first time. |
| Refresh on return | Leave the app, come back after more than 10 minutes | The club page in front (or the list, top to bottom) loads first, then every other saved club; the page in front also renews its lake view and satellite passes. Clubs loaded in the last 10 minutes are skipped (`ForecastStore.reloadAfter`). A pull on a club page refreshes that club, then the others. The header says when the server made the forecast and when the phone loaded it ("Forecast from 14:51 · loaded 15:39"). No refresh runs while the app is in the background. |
| Legal notice (Impressum) | Settings > About > Legal notice | The placeholders in `LegalInfo` in `Legal.swift` must be filled in before release. |

### Testing the model picker

1. Settings > About > tap Version seven times > the Developer row appears on the first Settings page.
2. Open MRC 1880, scroll to the bottom, tap the Forecast line.
3. Pick AROME. The sheet shows a spinner, then AROME first in the list; the
   line on the page says "Forecast: GeoSphere Austria AROME ... (your choice)".
4. Pick Automatic: back to "DWD ICON-D2".
5. Settings > Developer > "All clubs back to the automatic model", or switch
   the option off: every club is automatic again.

If a picked model says "not published yet", wait for the next publishing
run: the other models are written every 3 hours, for the confirmed clubs
that someone opened in the last 7 days.

### Testing chart and map together

1. Open MRC 1880 > Current conditions > Wind. The map card sits under the
   chart (beside it with the phone on its side, when landscape is on).
2. Hold, then slide on the chart: the blue line moves, the big number shows
   that hour, and the map follows. The green marker at the bottom of the
   chart is the map's hour; the thin green band shows the hours with maps.
3. Play the map: the blue line moves with it and the chart scrolls along.
4. Drag the chart past the green band (about two days on): the map stays
   on its last hour, greyed, with "The maps end ...".
5. Tap the chain ("Own time"): the map's badge at the bottom of the chart
   loses its chain and turns outlined, a dashed green line runs the full
   height above it, and the map and the chart move separately. Tap again: the chart jumps to the map's hour.
6. Tap the map: full screen, with the chart as a slim time bar above the
   slider. Swipe to Temperature: the hour stays.
7. Pick an hour in the 48 hours and open a value: chart and map start
   there, and "Back to <that hour>" returns both.

### Testing the rain tile with the radar

The club page has no rain radar card any more (it can be switched on under
Arrange this page); the rain tile in Current conditions reads DWD's radar for
the next two hours and the forecast after that.

1. Open a club on a day with showers nearby. The rain tile shows what the radar
   sees now ("Dry", "Light rain") with a line such as "Rain from 12:45"
   after a small radar symbol (from the radar), or "Rain from 18:00" without
   it (from the forecast), and small bars: thin ones for the
   radar's quarter hours, a line, then paler ones for the next forecast hours.
   The top tile's "Rain, hail" cell shows the same two lines: the value, and
   the grey line under it with the same symbol. The top tile's small values
   (waves, rain, visibility) start under Air, Water and Wind (left column at the left edge, right column ending at the right edge, middle column with equal gaps; grey lines don't set the widths); their grey lines
   use shorter words than the tiles ("1.0 km open water", "Dry for 24 h").
   When ice matters it gets its own line under them (`-RWSampleIce YES`).
   Snow, hail and drizzle are named from the forecast's weather code (the
   radar only measures how much falls). While it rains, the line says what
   comes next: "Dry from 14:15", "Heavier from 14:30" (radar) or "Until about
   17:00" (forecast, no symbol), in the tile and the top tile alike.
2. Tap the tile: the chart starts with thin purple radar bars for two hours,
   then the blue forecast hours; the legend turns either off. The map card
   says "Radar 12:45" and shows the radar picture; a tap opens the radar map.
   Slide the chart past two hours: the big number, the chart and the map
   turn to the forecast, and the map's header to "Forecast <hour>".
   The repeat button beside the map's slider (every detail map) plays it
   3 times, as the full-screen maps do.
3. Pick an hour in the 48 hours less than two hours ahead: its tiles use the
   radar too. Later hours use the forecast only.
4. Arrange this page: "Rain radar" is switched off; switched on, the old card
   comes back under Current conditions.

### Testing "Import a row"

The Simulator has no real rows, so this needs the iPhone (Apple Health) or a
real export file.

1. Lake view > Plan a route > bookmark menu > **Import a row**. The first time,
   iOS asks to let Row Frog read workouts and workout routes (read only).
2. Apple Health lists rowing workouts of the last year that have a GPS route
   (Apple Watch outdoor rowing, or apps that save rows with their route to
   Health). Tap one: it becomes a saved route on this lake, the pace setting
   takes the row's pace, and the bookmark menu offers **Show rowed track**.
3. **Choose a file** takes a GPX, TCX or FIT file (CrewNerd, Garmin Connect,
   Strava export). Sharing such a file from another app or from Files to Row
   Frog saves it on the lake whose clubs are within 3 km of the row.
4. A row not on this lake, or shorter than 200 m, is refused with a note.

Health access can be changed later in the Health app > Sharing > Apps >
Row Frog. Nothing read from Health or a file leaves the phone.

### Testing on an iPad

The app runs natively on the iPad (iPhone and iPad in `TARGETED_DEVICE_FAMILY`).
Install it like on the iPhone: cable, Trust, Developer Mode on the iPad
(Settings > Privacy & Security), Personal Team, Run scheme on Release, pick the
iPad in Xcode, then trust the developer under Settings > General > VPN & Device
Management.

1. In landscape, and in portrait on the larger iPads, the location list stays
   on the left and the club page sits on the right with the cards in two columns.
2. Turn the iPad every way, including upside down; resize the window (Stage
   Manager, or the window handle on iPadOS 26): narrow windows fall back to the
   iPhone layout.
3. Settings > Appearance has no Landscape switch on the iPad: iPadOS ignores an
   orientation lock for apps in windows.
4. The widget offers every size, including extra large.
5. A value's view (tap a tile) opens full screen on the iPad: chart and map
   one under the other in portrait, side by side in landscape.

## Launch arguments (Simulator and screenshots)

Every setting can be set at launch, e.g. `-RWLanguage de`. The screenshot
workflow (`.github/workflows/screenshots.yml`) uses these; the most useful:

- `-RWDemoClubs YES` the three confirmed clubs with MRC 1880 as home base
- `-RWTutorialSeen YES -RWNoTips YES` skip the tour and tips
- `-RWOpenClub <id>` open a club page; `-RWScrollTo warnings|radar|conditions|lakeview|hourly|launchpoint|satellite|source|arrange|hourly-1` (`hourly-1` = second day of the 48-hour table)
- `-RWPageLayout "hourly,radar"` card order for all clubs (cards left out follow in the standard order; the rain radar card is off unless named, since the rain tile shows the radar); `-RWArrange YES` opens "Arrange this page"
- `-RWOpenRadarMap YES` open the rain radar map from the radar card, so name `radar` in `-RWPageLayout` too (`-RWRadarLoop NO` plays it once, otherwise it plays 3 times); `-RWOpenSatellite YES` open the satellite picture full screen, `-RWSatelliteLayers '(clubs, shore)'` the layers drawn over it; `-RWOpenHour n` open the n-th hour of the 48-hour table
- `-RWOpenWeatherMap <layer>` open the weather map from the detail view opened with `-RWOpenCondition` (layers: `wind`, `gust`, `temperature`, `feelsLike`, `humidity`, `pressure`, `visibility`, `rain`, `uv`, `lightning`, `fog`)
- `-RWMapTimeLinked NO` detail views open with the map on its own time (chain off)
- `-RWSatelliteZoom n` opens the full satellite picture n times closer than usual (with `-RWOpenSatellite YES`)
- `-RWLakeWide twilight|cold|dark` sets the whole-lake light of every lake hour (twilight with cold water: amber stripes; cold water alone: no stripes; dark: grey with red stripes)
- `-RWLiveLaunchMap YES` show the launch point card's live map instead of its still picture
- `-RWSampleRadar YES` made-up rain on the radar from 30 minutes on (light, then rain, dry again after an hour), to show the rain tile, the top tile's rain value and the rain chart while DWD's radar is dry
- `-RWSampleIce YES` the top tile shows a made-up "Shore ice possible" line, to check the winter layout outside the ice season
- `-RWWidgetRadar YES` (with `-RWWidgetGallery YES`) light rain on the radar from 30 minutes on, to show the widget's radar line
- `-RWLegend lights` open the rowing light legend from the top tile
- `-RWOpenLakeView YES` open the lake view; `-RWLakeLegend YES` with its legend open; `-RWLakeImagery YES` Apple's satellite pictures under the lake (the switch in the lake view's top bar)
- `-RWRoute "lat,lon;lat,lon;…"` open route mode with these points (a new route goes one way); `-RWOutAndBack YES` rows it out and back
- `-RWImportRows YES` open "Import a row" in the lake view with made-up Apple Health rows (Health is not asked); `-RWImportedRoute YES` with `-RWRoute` imports a made-up row along those points (2:20 per 500 m, a week ago); `-RWShowTrack YES` shows the rowed track (the switch in the bookmark menu)
- `-RWChartSelect 5` a detail chart opens with the blue line (and the big number) five hours on, and its label shown
- `-AppleLanguages '(de)'` start as on a phone set to German (the app picks German from the phone's languages)
- `-RWOpenCondition <name>` open a detail view (swipe or the symbol menu moves to the others)
- `-RWTutorialPage n` open the first-start tour at page n (0 = welcome); `-RWShowTips YES` show every one-time tip; `-RWLaterTips YES` show the radar map, hour view, water estimate, route stretch and weather map tips, which otherwise wait until the rain radar, hourly, conditions, close loop and chart scrub tips are closed; `-RWTourAutoHome YES` on the home base page (`-RWTutorialPage 1`) picks the first suggested club, to check the tour stays on that page
- `-RWResetTips YES` show the one-time tips again, as after Settings › Help
- `-RWOpenForecastSource YES` open the forecast source sheet
- `-RWDeveloperOptions YES` and `-RWPickedModels '<dict><key>mrc-1880</key><string>ecmwf_ifs025</string></dict>'`
- `-RWShowSettings YES -RWScrollPage n` open the settings; on a long Settings page, scroll to its section n
- `-RWSaveData YES` saving data as in Low Data Mode (satellite pictures wait for a tap, half-hour radar steps)
- `-RWLowPower YES` draws the app as in Low Power Mode (solid tiles, bar buttons and clock strip)
- `-UIPreferredContentSizeCategoryName UICTContentSizeCategoryXXXL` (or `…AccessibilityL`) opens the app at a larger text size, as Settings › Display › Text Size
- `-RWLanguage de`, `-RWAppearance dark`, `-RWLandscape YES`
- `-RWSafetyAccepted YES` skip the first-start safety notice (the screenshot workflow passes it to every shot except 77 and 78)
- `-RWWhatsNewSeen 1000` keep the "What's new" sheet away (the screenshot workflow passes it to every shot except 114 and 115)
- `-RWStaleForecast YES` treat every forecast and lake view as more than 3 hours old (grey light and the out-of-date warning)
- `-RWSlowRefresh YES` show the "updates less often" tip of clubs nobody opened lately on every club
- `-RWSettingsPage appearance|clubpages|language|data|help|about|developer|limits|boat:<id>|backgrounds|widgets|safety|impressum|privacy` open those Settings pages, with the pages on the way (backgrounds = Settings > Club pages > Background pictures, widgets = Settings > Widgets)
- `-RWSettingsSearch <text>` open the settings with the search field filled in
- Backend `RW_SAMPLE_WARNING_CLUBS=<club ids>` gives those clubs a made-up warning, marked as a sample: a lake storm warning where DWD has a lake area, else a thunderstorm warning from the place's own service (GeoSphere Austria or MeteoSwiss). The screenshot workflow sets it for Tutzinger RV, Seeclub Zürich and RV Albatros Klagenfurt
- Backend `RW_SAMPLE_LAKE_WIND=from,speed,gusts` (degrees, m/s) replaces the wind in the lake view with a made-up one, marked as a sample, so screenshots show waves building across the lake on a calm day (the screenshot workflow sets `192,5.2,7.9`, a south wind)
- Backend `RW_SAMPLE_SATELLITE_WATER=<lake ids>` gives those lakes a made-up Landsat reading from five days ago, so the water detail shows the satellite estimate (the screenshot workflow sets it for the Simssee, shots 152-153)

## What runs on its own (GitHub Actions)

| Workflow | When | Where you see it |
|---|---|---|
| Publish forecasts | every 30 min from main, started on the minute by the Cloudflare Worker `rowfrog-timer` (`cloudflare/timer/`); GitHub's own `*/30` timer is the backup and stops at the `due` job while the files are younger than 40 minutes; all catalog clubs every 6 hours on GitHub's timer | api.rowfrog.com; the weather maps in `maps/` (index + one file per tile and value) are rebuilt only when DWD has a newer ICON-D2 run, every 3 hours, from DWD open data without Open-Meteo calls |
| Model check | 04:40 and 16:40 UTC | weekly report on the "Model check" issue (Mondays); its section "Once a day instead of twice?" shows whether the 04:40 run alone would rank the models the same (to decide later whether to drop the 16:40 run, about 700 Open-Meteo calls a day) |
| Usage limits | daily 06:10 UTC | comment on the "Usage limits" issue from 70 % of a limit, and on the 1st of the month. Covers Open-Meteo, Copernicus and, read with the Cloudflare token, Worker requests (100,000 a day) and D1 rows written (100,000) and read (5 million) on the free Workers plan |
| Website | when `web/`, `scripts/build_web.py` or the app's German table change on main (tests only on PRs) | Cloudflare Pages project `rowfrog-web` (rowfrog.com once the domain is attached, else rowfrog-web.pages.dev). The run checks that the site refuses visitors without the password |
| App size | when iOS code lands on main, or by hand | job summary of the run: installed size, expected App Store download, and the largest files (Release archive, unsigned, about 15 macOS minutes) |

## By hand

| Workflow | When to run it |
|---|---|
| Usage counter | once after setting it up, and whenever `cloudflare/usage/` changes on main (it runs itself then) |
| API check | to see whether api.rowfrog.com, the Cloudflare proxy and the usage counter answer |
| Model check with archive_days | once for a quick first score (60 days); otherwise leave it at 0 |
| Satellite water temperature check | after changing the satellite water temperature code (it runs itself on pushes that touch it): compares Copernicus LSWT, Landsat and the carried-forward estimate with GKD lake stations since 1 May; about 20 min |
| Water temperature stations | every few months, or when clubs are added: lists the GKD Bayern, PEGELONLINE and Swiss BAFU stations, shows how `data/water-stations.json` (the station each club reads, nearest on its own water) would change, and reads every station in it once. To take a changed list, run `python3 scripts/water_station_survey.py --write` locally and commit the file |
| Fix unknown waters | on main, after `data/catalogs/water-fixes.json` changes: puts clubs the import left under "Water near <town>" on the water checked by hand for them and moves their town-level launch points to that water's nearest shore (OpenStreetMap, within 6 km). The importers apply the same list on every run, so a re-import keeps the waters; locally `python3 scripts/fix_unknown_waters.py` (without `--snap`) only moves the clubs. A fix with `"replace": true` (and the water's `"id"`) also moves a club the import put on a wrong water, such as a pond, a harbour basin or a piece of river. A run stops after 45 minutes and saves what it has; run it again until the report no longer says "run the workflow again". It also finds a water whose map name is longer ("Untere Alte Donau", "Murtensee / Lac de Morat") when none has the exact name nearby, and bays such as the Flensburger Förde; a fix with `"near": {"lat", "lon", "place"}` searches from there, for a club the import geocoded to the wrong town. A club that rows at a second site gets its own entry from `data/catalogs/extra-sites.json` (a copy of the club with the site's name, address, water and launch point; e.g. Pro Sport Berlin 24 (Gatow)), with a `"near"` fix of the same id so the run snaps it too |
| River sections | by hand, after river clubs or `data/river-section-overrides.json` change (about 40 minutes): cuts each river and canal club's stretch out of OpenStreetMap (Geofabrik extracts of DE/AT/CH) with `scripts/build_river_sections.py` and commits `data/river-sections.json` and the outlines `data/outlines/<section-id>.geojson` to the branch it runs on. Clubs within 3 km on the same water share a section. Rule: to the next weir or lock up to 25 km each way; open sides end at a river mouth, a big river joining or a big harbour 3 to 15 km away, else 12 km upstream and 8 km downstream (canals 10 and 10), moved to a river km sign within 1 km. The overrides add waters that belong to a stretch (`include`) and the side a club rows on where a weir sits at its boathouse (`direction`). The "only" input rebuilds just the sections of the given club ids. The backend moves the clubs onto their sections (`locations.py`), so they get the River view and satellite pictures of about 10 km around them |
| DRV club catalog | to refresh `data/catalogs/de-drv.json` from the DRV club search (about 45 minutes); it runs itself when `scripts/import_drv.py` changes on main |
| Club catalog | to refresh `data/catalogs/de-osm.json` from OpenStreetMap; it runs itself when `scripts/discover_clubs.py` changes on main |
| Austria and Switzerland club catalogs | to refresh the `at-*` and `ch-*` catalogs; tick `swissrowing` only once Swiss Rowing has agreed. It runs itself when its import scripts change on main |
| Live data check | after adding clubs or lakes: downloads missing lake outlines, checks launch points against them and runs the forecast with live data; new outlines are committed back. It runs itself when `data/locations.json`, `scripts/` or the data sources change on main |
| Satellite ice check | to see whether the Copernicus ice maps and Sentinel-2 pictures answer for our lakes; it runs itself when its scripts change |
| Place suggestions | with `deploy` ticked, to deploy the Worker in `cloudflare/suggestions/` that turns place suggestions into GitHub issues; unticked it only checks the GitHub token and the label. It runs itself when `cloudflare/suggestions/` changes (deploying only from main) |
| Forecast timer | with `deploy` ticked, to deploy the Worker in `cloudflare/timer/` that starts Publish forecasts at :00 and :30; unticked it only checks the GitHub token. It runs itself when `cloudflare/timer/` changes (deploying only from main). Its logs: Cloudflare > Workers > rowfrog-timer |
| Weather maps data check | to see what DWD (ICON-D2, GeoServer) and EUMETSAT offer for the weather maps; it runs itself when `scripts/weather_maps_probe.py` changes |
| River section survey | research only: for every river club, how far the next weir or lock is up- and downstream (`scripts/river_section_survey.py`, on the Geofabrik extracts filtered with osmium, so no Overpass). Nothing is stored |
| River gauge check | research only: which river gauges (PEGELONLINE, BAFU) and flow forecasts (Open-Meteo Flood API) could tell river clubs about current and high water (`scripts/river_gauge_probe.py`). Nothing is stored |
| Austrian and Swiss warnings check | to see what GeoSphere Austria, MeteoSwiss, MeteoAlarm and DWD's lake areas answer for a few Austrian and Swiss clubs (research for warnings outside Germany); it runs itself when `scripts/alpine_warnings_probe.py` changes. Nothing is stored |
| App screenshots | only by hand: once a PR is ready for review, with `only` for the changed screens (e.g. `^8[1-7]-`); the full set only when the owner asks. Results go to `refs/screenshots/<branch>` (not in any branch's history; the run starts from that branch's last set, else main's) and to the run's "screenshots" download. Get them: `git fetch origin refs/screenshots/<branch> && mkdir -p shots && git archive FETCH_HEAD | tar -x -C shots`. Sets of deleted branches are removed by the next run. Input `device` = `iPad` shoots on an 11-inch iPad Pro Simulator instead; those shots go to an `ipad/` folder in the same set |

## Secrets (names only; the values live in GitHub > Settings > Secrets)

`CLOUDFLARE_API_TOKEN` (also needs "Cloudflare Pages: Edit" for the website), `CLOUDFLARE_ACCOUNT_ID`, `USAGE_KEY` (usage counter),
`SITE_USER`, `SITE_PASSWORD` (the website's password while it is in testing; change them and re-run the Website workflow to change the password),
`CDSE_CLIENT_ID`, `CDSE_CLIENT_SECRET` (Copernicus satellite pictures, ice map and lake water temperature).
`SUGGESTIONS_GITHUB_TOKEN` (fine-grained token with Issues read and write on this repo, for the place-suggestions Worker).
`PUBLISH_TIMER_TOKEN` (fine-grained token with Actions read and write on this repo, for the forecast timer Worker).
Landsat water temperatures come from Microsoft's Planetary Computer and need no secret.

## Website (rowfrog.com, in testing)

- Source in `web/`: `public/` (start page, `app/` = forecasts in the browser, legal pages), `functions/_middleware.js` (password on every page, `noindex` and no-AI headers on every answer; only `robots.txt` is open), `strings-de.json` (German for texts only the website has; everything else comes from the app's table in `ios/RowFrog/Localization.swift`).
- Build: `python scripts/build_web.py` writes `web/dist` and stops on any text without German. Tests: `node --test web/tests/*.test.mjs`.
- Try it locally against sample files: put a published `v1/` folder (e.g. `git archive origin/gh-pages v1/clubs/mrc-1880 v1/countries v1/lakes/starnberger-see | tar -x`) next to the contents of `web/dist`, serve that folder (`python3 -m http.server 8765`) and set `globalThis.RF_API = "http://localhost:8765/v1"` before the page loads (the browser tests do this with Playwright's addInitScript). Without it the page reads https://api.rowfrog.com/v1.
- Laid out like the app: the home base's page opens first, with the top tile, official warnings (only while a warning is out), current conditions tiles, next 48 hours, launch point map and satellite picture; the list and search are at `#/list`. On wide screens it behaves like the app on iPad: the page grows to 1000 px, its cards go into two balanced columns from 600 px, and from 860 × 560 px the list sits beside the page. Icons are Lucide (`web/public/app/icons.js`, made once from `lucide-static`; add a name there for a new icon). The launch point map is Leaflet 1.9.4 in `web/public/app/vendor/leaflet/` with OpenStreetMap tiles.
- Boats: small boats with the app's limits show the backend's light; big boats, own boats (Settings › Boats and limits) and own limits are worked out again in the browser (`applyLimits` in `logic.js`, the same table and rules as `Limits.swift`; change both together).
- Lake view: a tile after Current conditions on clubs whose lake has `lakes/{id}/view`, and the full map at `#/lake/<lake>/<club>` with the hours, the Rowing light/Waves/Wind layers, a tapped spot and route planning (out and back, pace, start time, better start, lake at the boat's time, saved routes). The logic is in `web/public/app/lake.js` (same rules as `LakeView.swift`, `Route.swift` and `RouteSummary.swift`; change both together), the page in `lakeview.js`. The boat the lake is coloured for is under Settings › Boats and limits › Lake map colours.
- Value pages: each current conditions tile opens `#/club/<id>/value/<condition>` (optionally `/<time>` from the hour sheet) with the big value, the 24 h-wide scrollable chart (drag to scrub, the big value follows the line), limits, facts, rowing advice and source, as `ConditionDetailView.swift`. The texts are built in `web/public/app/values.js` (same rules as the app's detail builders; change both together), the chart in `chart.js`, the page in `valuepage.js`. The weather map under the chart (`weathermap.js`) reads the ICON-D2 tiles from `maps/index` and `maps/<tile>/<value>` (raw deflate, 255 = no data) and shows lightning, UV and fog live from DWD's and EUMETSAT's WMS; the chain button links its time to the chart, the full-screen view has a layer picker, play and loop. Start zoom is under Settings › Weather maps. In Beaufort the wind chart draws the forces without their steps (`beaufortScale` in `logic.js`: each force from half below to half above), so the lines and the limits keep the same order as in m/s, km/h, kn or mph.
- Satellite picture: the card under the club page (`web/public/app/satellite.js`, as `SatellitePicture.swift`) offers latest / mostly clear / clearest, switches for shore, clubs, routes, rowing light or waves, wind and (in winter) the ice map, drawn from the lake view in the picture's lon/lat box, and a legend. A tap opens it full screen: wheel or pinch to zoom (up to 6×), drag to move, double click or tap to zoom in or back; it opens on the saved routes when the Routes switch is on, else (in a portrait window) filling the width around the club, in a landscape window as a whole.
- Browse and add places: the list links to `#/countries` (every country, then its waters or towns grouped by state or first letter, with a filter, then the clubs; `web/public/app/countries.js`, as `ClubSearch.swift`), and the search has country chips. A club only counts for its own country, so a border lake such as the Bodensee shows each country's clubs. `#/add-place` (`addplace.js`) puts an own place on the map; it is saved with the clubs (id `own-…`) and its forecast is worked out in the browser from Open-Meteo with the backend's rules (`ownplace.js`, as `OwnPlaces.swift`; change both together). "Suggest it for everyone's list" posts to `https://api.rowfrog.com/v1/suggestions` as a plain-text form post (`no-cors`), because the suggestions Worker sends no CORS headers; the website cannot see whether it arrived. There is no satellite map switch on the website.
- Arrange the club page: "Arrange this page" at the end of each club page and Settings › Club pages open the same sheet as the app (`web/public/app/arrange.js`, as `ArrangePageSheet` and `PageLayout`; change both together). Cards move by their handle or the up and down arrows and can be switched off, for all clubs (`rf.pageLayout`) or only one (`rf.clubPageLayouts`). The rain radar card starts switched off, as in the app; orders saved before the rain tile read the radar switch it off once (`radarInTile`), and switched on again it stays on.
- Units, time, date and appearance (Settings on the website): the same choices as the app's Settings › Language and units and Appearance (`UNITS` in `web/public/app/logic.js` as `Units.swift`, `time`/`dateText` in `shared.js` as `TimeFormat`/`DateFormat`; change both together). Values arrive metric and are converted only for display, also in the charts and their limit lines. Device follows the browser's language for times and its light or dark setting; Light or Dark sets `data-theme` on the page.
- Background pictures and data use (Settings on the website): `#/settings/backgrounds` (`web/public/app/backgrounds.js`, as `Backgrounds.swift` and `BackgroundSettingsView`; change both together) sets a picture for all pages, for club pages, the list or the settings, or for one club; the samples are copied from `ios/RowFrog/Backgrounds/` by `scripts/build_web.py`, the visitor's own pictures stay in the browser's IndexedDB (`rowfrog` › `pictures`). Tiles over a picture: frosted or solid, as in the app (a stored "glass" choice reads as frosted). Save mobile data: satellite pictures (card and background) wait for a tap while the browser reports mobile data (`navigator.connection.type`, Chrome on Android) or asks to save data (`saveData`); other browsers do not tell.
- Rain radar: the club page reads DWD's radar at the launch point straight from DWD (`maps.dwd.de`, which allows browsers to ask) every 5 minutes while the page is open, 15 when saving data (`web/public/app/radar.js`, as `RainRadar.swift`, `RainOutlook` and `ConditionData.rainLines`; change both together). The rain tile, the top tile's rain value and the rain view use it for the next two hours and the forecast after that, with the radar symbol before a line read from the radar; hours picked less than two hours ahead use it too. The rain view's chart has thin purple radar bars for the two hours, and its map shows the radar picture while the time is within an hour back to two ahead ("Radar 0:15"), the forecast after that ("Forecast …"); tapped, it opens the radar map (also from the rain radar card when switched on): every picture loaded first, then played 3 times with repeat on. `localStorage["rf.sampleRadar"] = "true"` puts made-up rain on the radar from 30 minutes on, to test while DWD's radar is dry (as `-RWSampleRadar`).
- Import a row: Import a row on the lake view's route tools reads a GPX, TCX or FIT file (CrewNerd, Garmin Connect, Strava) in the browser only (`web/public/app/rowimport.js`, as `RowTrack.swift` and `RowImport.swift`; change both together). The row must lie mostly on the lake and be at least 200 m long; it becomes a saved route (`rf.routes`, with the rowed track and date) that starts at the launch point when the row did, is out and back or a loop as rowed, and sets the planning pace to the pace rowed. Show rowed track draws the track under the route. There is no Apple Health import on the website.
- Tour and tips: the tour (`web/public/app/tour.js`, as `TutorialView` and `TourPage` without the club choice pages, since the website picks clubs in the list) shows once after the safety notice and again from Settings › Help › Show the tour again (`#/tour`). The one-time tips (as the app's TipKit tips) sit at the top of their card and stay closed once closed; a follow-up tip (hour view after the hourly table, chart and map link after the weather map, the rain radar's two after More on the air) shows once the one before is closed, also on later visits. Show the tips again brings them all back. Texts that name iPhone gestures say what the website does instead.
- Everything the visitor picks stays in the browser (localStorage keys `rf.clubs`, `rf.wind`, `rf.boat`, `rf.boats`, `rf.limits`, `rf.mapBoat`, `rf.routes`, `rf.mapLinked`, `rf.mapZoom`, `rf.mapLoop`, `rf.limitInfo`, `rf.satLayers`, `rf.countryByTown`, `rf.pageLayout`, `rf.clubPageLayouts`, `rf.temperature`, `rf.waves`, `rf.rain`, `rf.distance`, `rf.pressure`, `rf.timeFormat`, `rf.dateFormat`, `rf.appearance`, `rf.background`, `rf.pageBackgrounds`, `rf.clubBackgrounds`, `rf.blurBackground`, `rf.tileStyle`, `rf.userPictures`, `rf.saveData`, `rf.sampleRadar` (test switch), `rf.tourSeen`, `rf.tourPage`, `rf.tipsClosed`, `rf.language`, `rf.safety`, `rf.catalog`). The safety notice has the app's text and version (1); raise `SAFETY_VERSION` in `web/public/app/app.js` together with the app's.
- Before opening the site to others: fill in the Impressum (`web/public/impressum/`), the full privacy policy, and remove the password check and the testing banner.
