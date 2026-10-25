# Row Frog

Weather, conditions and forecasts for rowers at their rowing club, with
webcam pictures where they are available later on.

For each club's launch point the app shows an hourly green / amber / red
"can we row?" light for the next 48 hours, and the conditions behind it:
wind, gusts, computed wave height, fog, thunderstorm risk, air and water
temperature, rain radar, ice cover, official DWD warnings and daylight.
It started with the lakes south of Munich (Starnberger See first) and can
show rowing clubs across Germany, Austria and Switzerland, or a place of your
own.

The app is free. It is an iPhone app (iOS 17 or later) written in SwiftUI;
Android may follow later.

> **Name.** The app is called **Row Frog**, formerly "RowerWeather" (renamed
> in October 2026). The app and widget use the bundle IDs
> `com.rowfrog.RowFrog` and `com.rowfrog.RowFrog.Widget`, the app group
> `group.com.rowfrog.RowFrog` and links starting with `rowfrog://`. In the
> code the Xcode project is `RowFrog.xcodeproj` (targets `RowFrog`,
> `RowFrogWidget`, `RowFrogTests`) and the Python package is `rowfrog`.

Hidden switches, test steps, launch arguments, workflows and the secrets they
need are in the **[handbook](docs/handbook.md)**.

## What the app does

**Safety notice.** Before anything else, a first start shows a "Before you
row" safety notice that has to be accepted; it cannot be skipped, and a new
version of it is asked for again. It opens in the phone's language, with a
picker for English or German. Across the app, "Advice only, you decide"
lines remind rowers that the app only advises and they decide. A forecast
older than 3 hours shows a grey light instead of green.

**Locations.** On first start the list is empty: a short tour explains the
app (11 pages, including your boats and rowing limits), then the user picks a
home base and more clubs. With location access
("While using") it suggests the 5 nearest clubs, otherwise 3 at random. The
search covers the clubs in Germany, Austria and Switzerland (see
[Club catalog](#club-catalog)) in one box, with country chips to narrow it,
and the clubs can also be browsed country by country.
Pages swipe left and right between saved locations, like the iOS Weather
app. The list shows each location's light and key numbers, with feels like under the temperature; swipe a row to
remove it or make it the home base. The saved list stays on the phone.

**Add a place.** A club, boathouse or spot on the water that no list has can
be put on the map. It stays on the phone, and its forecast is worked out on
the phone straight from Open-Meteo, since the published forecasts only cover
listed clubs (`ios/RowFrog/OwnPlaces.swift`). Only if the user turns it
on, the place is suggested for everyone's list: the Row Frog suggestions
service (a Cloudflare Worker in `cloudflare/suggestions/`) files it as a
GitHub issue, so no GitHub account is needed.

**Each location page** is a column of cards, in this order by default:

1. A top tile with the rowing light, which boat it is for and why it has that
   colour; air, water and wind; waves, rain and visibility (and ice when it
   matters); a DWD warning status line and a daylight line. Tapping a value
   opens its chart.
2. The DWD warnings card, only while a warning is issued (or the check failed).
3. Current conditions.
4. Rain radar.
5. Lake view.
6. Next 48 hours, with a feels-like column and a day header that stays in
   place while scrolling; tapping an hour opens that hour's view.
7. Launch point map.
8. Satellite picture.
9. Forecast source and credits.

"Arrange this page" at the end of the page reorders or hides cards, for all
clubs or only this one. Every card has an ⓘ button that explains its symbols;
the full legend is in Settings › Help. When a steadier boat of your own would
get a better light, the page suggests it.

**Current conditions.** A compact card of tiles in two columns, each with a
small graphic: wind, gusts, waves, temperatures, rain, cloud, visibility,
pressure, humidity, UV index, sun and ice, among others. Tapping a tile opens
a detail view with a chart you can drag from yesterday to 7 days ahead, with
a line that shows the values at any time and dots for now ("Back to now",
or "Back to" the hour it was opened from, returns there), a unit switch at the
bottom (air pressure in hPa, mbar, bar, inHg or mmHg), the limit lines (named on the side away from now), wind arrows
every 3 hours, an "About the limits" note, advice for rowing and the data
source (`ios/RowFrog/ConditionsCard.swift`). Swipe between detail views
or jump to another from the symbol at the top; tapping an entry in a chart's
legend switches its line on or off.

**Rowing limits.** Settings › Rowing limits chooses the limits the light
uses: *Small boats* (the default) or *Big boats*, or *My boats*, where each
boat has a name, a type (racing, training, gig or coastal) and a size and
rigging from 1x to 8+. Limits can be fine-tuned per group and per boat. A
separate choice sets which boat the lake map is coloured for, with a warning
when the map looks calmer than your boat. The phone works the light out
again for the chosen boat on the club page, the lake map and the widget
(`ios/RowFrog/Limits.swift`).

**Cold water.** Below 15 °C water the app advises a life jacket against
cold-water shock. Below 10 °C it warns of very cold water (stay near the shore,
don't row alone), suggests a coach or partner boat for singles and lowers its
own wind and gust limits by 1 m/s (your own limits stay as set, with a note).
Below 4 °C it warns of near-freezing water.

**Water temperature.** Each club reads the nearest measuring station on its
own water, from GKD Bayern, the German federal PEGELONLINE network or the
Swiss federal stations (BAFU, via api.existenz.ch); 85 clubs so far, listed
in `data/water-stations.json`. The water temperature view names the
station's operator and shows the station on a still map with its address. For lakes without a station the
backend works out a satellite estimate from Copernicus lake surface
temperatures and Landsat (through Microsoft's Planetary Computer, no extra
account), carried forward with the air temperatures; the top tile shows it
in grey as "Estimated", and the detail view names the satellite and the date
of the reading.

**DWD warnings.** The page shows the official DWD warnings:
the lake warning (strong wind or storm, as the shore lights show it) where
DWD runs its lake warning service (23 lakes, among them Starnberger See,
Ammersee and Chiemsee), and DWD's weather warnings for the municipality,
which cover rivers and canals too. While one is issued it gets its own card
under the top tile; otherwise the top tile's status line says there is none
and when it was checked, or that DWD could not be reached.
Warnings come from DWD's GeoServer (`backend/rowfrog/sources/dwd_warnings.py`)
and also set the hourly light. In English the app shows DWD's own English
text (from its English CAP files) with the German original below; where DWD
has no English version, only the event and headline are translated.
At lakes with shore warning lights the card explains both lights (40 and 90
flashes a minute) and the season they run in.

**Lake view and route planning.** A tile opens a map of the whole lake with
waves, wind and the light for each part of the lake, and a spot you can tap
for its details. A legend lists what is on the map, a switch puts Apple's
satellite pictures under the lake, and wind arrows get denser as you zoom in.
"Plan a route" checks a route on the lake against the
forecast for the time you start, rowed once or out and back, and shows
where and when it gets rough. The way out and the way back are drawn side
by side, and "Lake at the boat's time" adds a slider that shows the lake as
it will be where the boat is at each moment. Turning points can be dragged or
deleted, and a loop closes when it ends within 50 m of the start or with a
button. While planning, a compact panel shows only the route's result,
start time, pace and out and back, so the map keeps the screen. Routes are
saved on the phone; "Manage routes" lists them with their length and whether
they are a loop, to rename, duplicate, delete or reorder. "Import a row" turns a row you already did into a
route: a rowing workout from Apple Health or a GPX, TCX or FIT file from
another app, with the real pace as the starting pace and the rowed track as
an optional line on the map. Health access is asked for only for this, and
everything stays on the phone (`ios/RowFrog/RowTrack.swift`).

**Rain radar.** Each location page has a card with DWD's rain radar and
2-hour nowcast for the launch point, e.g. "Light rain from 21:30"; tapping it
opens the radar map, with DWD's colour legend and a switch to play the radar
as a loop. The app reads it from DWD directly (`ios/RowFrog/RainRadar.swift`).

**Battery.** The app keeps its battery use low: the radar only updates on the
page in front, readings and map pictures are reused, widgets redraw only when
something changed, and the launch point map stays a still picture until it is
tapped. A blurred background picture is blurred once, not on every frame, and
Add a place looks up the water only once the map stops moving. In Low Power
Mode the tiles are drawn solid and the radar updates less often. The app does
nothing in the background; only the widgets load forecasts on their own.

**Ice cover.** Every forecast carries an ice estimate per lake for today and
the coming week: no ice, shore ice possible, ice forming, ice cover likely,
or drift ice on rivers. Likely ice turns the hourly light red; possible shore
or drift ice turns it amber. The estimate is a frost model over the last
three months of air temperature plus the forecast week
(`backend/rowfrog/ice.py`); a measured water temperature above 3 °C
overrides it. On larger lakes the Copernicus Lake Ice Extent satellite map
checks it, and the ice tile shows the latest pass, e.g. "Satellite, Today:
open water".

**Satellite pictures.** A card near the end of the page shows the latest
Sentinel-2 picture of the lake, with a line such as "Sentinel-2 · 22 Oct ·
25 % of the lake under cloud" and an "i" that explains why a new picture
comes only every 2 to 5 days. A switch chooses between the latest pass
(clouds or not), the clearest one and, in cloudy weeks, a newer mostly clear
one; every picture shows the same area. Chips draw the shore, clubs, saved
routes, wind and, in winter, the satellite ice map over it. Two more layers
colour the water with the lake view's wave heights or rowing light for the
chosen hour, one at a time; a legend explains them. Tap for full screen with
zoom, opening around the club or all saved routes. Pictures are kept on the
phone, so each pass loads only once.

**Forecast source.** A small line at the end of each club page names the
weather model the forecast comes from (today DWD's ICON models for every club,
`backend/rowfrog/weather_models.py`); tapping it explains the chain of
models from the first hours to the end of the forecast. When a model is
picked in the hidden developer options, the credits line names its provider
(MeteoSwiss, GeoSphere Austria or ECMWF) as well as DWD.

**Launch point map.** A map (Apple MapKit, no key needed) shows the launch
point the forecast is for, with its coordinates. It is a still picture until
tapped; then it can be panned and zoomed, and it resets on each visit. "Open
in Maps" also offers directions, and when Apple Maps knows the club as a
place (with photos and opening hours), it opens that.

**Maps** all mark clubs the same way: this page's club in blue, other clubs in
grey, with a house for the home base and a rower for any other club.

**When an update fails,** the page keeps the last forecast and says why under
the club's name (no internet, server did not answer, no forecast for this
club); a tap explains whose side it is on and offers "Try again".

**Widgets.** Home-screen and lock-screen widgets show the rowing light first,
then the values in the top tile's order, each with its symbol: temperature
and feels like beside the weather symbol, water, wind, waves, rain,
visibility and daylight. When the light is green but the rain radar sees rain
coming within 2 hours, the widget adds a line such as "Light rain from 14:30".
Behind them goes a sky in the weather's colours (the default), the rowing
light's colour, the club's app picture or another picture, the satellite
picture of the lake, or plain white or black.

**Settings** (cog in the page bar of the club pages and on the location
list; the list goes back to the club page with a button named after the club):

- Appearance (light, dark or as the phone is set; a note says dark saves
  battery on OLED iPhones) and a Landscape switch (on by default; off keeps
  the app upright).
- Units with icons (wind in m/s, km/h, knots, mph or Beaufort; °C or °F; waves in m, cm or ft), language
  (English or German), date and time formats.
- Background pictures for all pages, single pages or single clubs: clear or
  blurred, frosted, solid or Liquid Glass tiles (iOS 26), or your own photo.
  The satellite picture of the club's lake can be a background too. On club
  pages the picture fills the screen behind the status and page bars and
  fades between clubs while swiping.
- Widgets: the background for all widgets or per club (each widget can also
  pick its own when you edit it), and how often they update: every 30 minutes
  (default), every hour, every 2 hours, or only after using the app. Less often saves battery and data, but a new DWD
  warning reaches the widgets later.
- App icon: the coxed double "rowing light" icon in light, dark and tinted,
  plus 10 alternates.
- Help: the full legend of symbols, and replay the tour. One-time tips point
  out features the first time they appear (among them the rain radar,
  satellite picture, forecast source, rowing limits and cold water), and after an update a "What's new"
  sheet shows once.
- Rowing limits (see above).
- Legal: the safety notice, a privacy summary and the legal notice
  (Impressum, still with placeholders).
- Factory reset (keeps saved locations, the home base and My boats; resets
  the icon and the limits).

**Wide screens.** Phones on their side and the unfolded iPhone Duo get wide
layouts (two columns from 600 pt, a side list from 860 × 560 pt).

## Layout

| Path | What it is |
| --- | --- |
| `ios/` | SwiftUI iPhone app and widget. The Xcode project is generated from `project.yml` with XcodeGen. |
| `backend/` | Python (FastAPI) service that fetches the forecast, computes waves, the lake view and the traffic light, and serves the app. |
| `data/locations.json` | Lakes and clubs with confirmed launch points. Add a club or lake here; no code change is needed. |
| `data/catalogs/` | Clubs the app's search offers, one file per country and source (see [Club catalog](#club-catalog)). |
| `data/geocode.json` | Cached geocoding results for the catalog imports. |
| `data/outlines/` | Lake outlines (GeoJSON) for the wave calculation and lake view, made with `scripts/fetch_lake_outline.py`. |
| `data/water-stations.json` | The water temperature station each club reads (nearest on its own water). |
| `data/lake-depths.json` | Mean lake depths for the ice estimate. |
| `cloudflare/` | Cloudflare Workers: `usage/` counts loads on `api.rowfrog.com`, `suggestions/` turns place suggestions into GitHub issues. |
| `docs/handbook.md` | The handbook: hidden features, how to test them, launch arguments, workflows and secrets. |
| `docs/screenshots/` | App screenshots from the "App screenshots" workflow. |
| `scripts/` | Catalog imports, lake outlines, publishing, checks and background drawing. |
| `CREDITS.md` | Data sources, licences and the credits the app must show. |

## Club catalog

The app's search offers clubs in Germany, Austria and Switzerland, about 670
in all, from one file per country and source in `data/catalogs/`
(`<country>-<source>.json`):

| File | Clubs | Source | Made by |
| --- | --- | --- | --- |
| `de-drv` | 469 | German Rowing Association (DRV) club search, rudern.de | `scripts/import_drv.py`, **DRV club catalog** workflow (about 45 minutes) |
| `de-osm` | 3 | OpenStreetMap around the Bavarian lakes | `scripts/discover_clubs.py`, **Club catalog** workflow |
| `at-oerv` | 44 | Austrian Rowing Federation (ÖRV) club list, rudern.at | `scripts/import_oerv.py` |
| `at-osm` | 33 | OpenStreetMap, clubs the ÖRV list does not have | `scripts/import_osm_clubs.py` |
| `ch-swissrowing` | 76 | Swiss Rowing's club directory | `scripts/import_swissrowing.py`, only when started by hand with "Import Swiss Rowing" ticked |
| `ch-osm` | 45 | OpenStreetMap | `scripts/import_osm_clubs.py` |

The last four run in the **Austria and Switzerland club catalogs** workflow.
Each boathouse is geocoded (cached in `data/geocode.json`) and matched to the
lake or river it lies on; clubs on rivers get no wave calculation. Only club
facts are stored, no contact people, e-mail addresses or phone numbers. The
federations are credited in `CREDITS.md`, which also notes where permission
is still to be asked.

Launch points from the catalogs are unconfirmed until a club is moved into
`data/locations.json`. When loading, `locations.json` always wins, then the
catalogs in the order above (a federation's list before OpenStreetMap); a
catalog club with the same id as an earlier club, or within 300 m of a club
from an earlier file, is left out as the same club. The app loads the clubs of
one country at a time.

## Run the backend

```sh
cd backend
pip install -e ".[dev]"
pytest
uvicorn rowfrog.api:app --reload
```

Then open http://localhost:8000/lakes,
http://localhost:8000/clubs/mrc-1880/forecast or
http://localhost:8000/lakes/starnberger-see/view.

Waves are only computed for lakes that have an outline. To add one:

```sh
python3 scripts/fetch_lake_outline.py starnberger-see "Starnberger See"
```

## Hosting

There is no server yet. The "Publish forecasts" workflow runs the backend on
GitHub and publishes its answers as files on GitHub Pages, at
https://api.rowfrog.com/v1/ (same paths as the API: `lakes/index`,
`clubs/<id>/forecast`, `lakes/<id>/view`, and the satellite pictures).
Every 30 minutes it refreshes the clubs people actually load (until the
usage counter is set up, the confirmed clubs in `data/locations.json` stand
in); every 6 hours it refreshes all clubs. A club nobody opened lately is
refreshed less often and its page says so; once opened, it is back to every
half hour from the next run. DWD's local warnings for all clubs come in a couple of
bulk queries per run. Weather is only loaded again after
a weather model has a new run, which keeps the job within Open-Meteo's free
limit. When a station's water temperature fails to load, the last good reading
stands in for up to 6 hours. For clubs people use it also loads the 8-day outlook after each model
run (every 3 hours) for the charts in the condition details. The last
forecasts are kept between runs in the Actions cache.

Only `main` publishes to the live site. A branch can be published by running
the workflow by hand, which overwrites the live files until `main` publishes
again.

Release builds of the app read from there; Debug builds use a backend on the
Mac at localhost, except for the satellite pictures, which only the publishing
job makes and every build loads from `api.rowfrog.com`. To move to a server of our own, run
`uvicorn rowfrog.api:app` there and point the DNS record of
`api.rowfrog.com` at it; the app keeps its address.

## Run the app

On a Mac with Xcode 15 or later, install XcodeGen (`sudo port install
xcodegen` with MacPorts, or `brew install xcodegen`), then:

```sh
cd ios && xcodegen && open RowFrog.xcodeproj
```

Run the backend first; the simulator reaches it at `http://localhost:8000`
(set in `project.yml` as `RWAPIBaseURL`).

A checkout from before the October 2026 rename needs `xcodegen` run again
(the old `RowerWeather.xcodeproj` can be deleted) and the backend installed
again with `pip install -e ".[dev]"`, since the package is now `rowfrog`.

## Workflows

More detail, including the secrets each one needs, is in the
[handbook](docs/handbook.md).

| Workflow | What it does |
| --- | --- |
| **CI** (`ci.yml`) | Backend tests on every push to `main` and every pull request; the iOS build and tests run on pull requests that change `ios/` (on `macos-15-intel`, since Apple Silicon runners have not been assigned lately). |
| **App screenshots** (`screenshots.yml`) | Runs the backend with live data, starts the app in the iOS Simulator and saves screenshots to `docs/screenshots` on the same branch. Long pages are shot screen by screen (`-p1`, `-p2`, …). Tutzinger RV gets a made-up lake storm warning and the lake view a made-up south wind, both marked as samples in the app. Runs only by hand from the Actions tab, since it holds a Mac runner for a long time: once per pull request when it is ready for review, for the screens that changed (the `only` input), and a full set only when asked. |
| **Publish forecasts** (`publish-backend.yml`) | Publishes the backend's answers to GitHub Pages, see [Hosting](#hosting). Needs the secrets `CDSE_CLIENT_ID` and `CDSE_CLIENT_SECRET` for satellite pictures and ice. |
| **Satellite ice check** (`satellite-ice.yml`) | Tries the Copernicus ice maps and Sentinel-2 pictures for our lakes with the same secrets. Runs by hand or when its scripts change. |
| **Model check** (`model-check.yml`) | Twice a day stores every candidate weather model's forecast for the test points in `data/model-check/points.json` on the `model-check` branch and compares them with DWD station measurements. On Mondays the report is posted on the "Model check" issue, with a section on whether one run a day would be enough. Changes to its scripts start it only on `main`. |
| **Usage counter** (`usage-worker.yml`) | Deploys the Cloudflare Worker in `cloudflare/usage/` that counts club and lake loads on `api.rowfrog.com` (no IP addresses) and keeps the jobs' call totals. Needs `CLOUDFLARE_API_TOKEN`, `CLOUDFLARE_ACCOUNT_ID` and `USAGE_KEY`. |
| **Usage limits** (`budget-check.yml`) | Once a day compares the calls with Open-Meteo's and Copernicus' free limits and Cloudflare's free Worker and database limits and comments on the "Usage limits" issue at 70 % (warning) and 85 % (alert), plus a monthly summary. |
| **Austria and Switzerland club catalogs** (`alpine-catalogs.yml`) | Rebuilds the `at-*` and `ch-*` catalogs (Swiss Rowing only when ticked by hand). By hand, or when its scripts change on `main`. |
| **Place suggestions** (`suggestions-worker.yml`) | Deploys the Cloudflare Worker that turns place suggestions into GitHub issues. Needs `SUGGESTIONS_GITHUB_TOKEN`, `CLOUDFLARE_API_TOKEN` and `CLOUDFLARE_ACCOUNT_ID`. |
| **API check** (`api-check.yml`) | Shows how `api.rowfrog.com` answers (Cloudflare proxy, SSL mode, usage counter). Runs by hand. |
| **Live data check** (`live-check.yml`) | Downloads missing lake outlines from OpenStreetMap, checks club launch points against them and runs the forecast against live Open-Meteo and GKD data. Runs by hand, or when the club list or data sources change on `main`; new outlines are committed back. |
| **Water temperature stations** (`water-stations.yml`) | Lists the GKD Bayern, PEGELONLINE and Swiss BAFU stations, shows how `data/water-stations.json` would change and reads every station in it once. Nothing is stored; a changed list is committed by hand (see the handbook). By hand, or when its files change. |
| **Satellite water temperature check** (`water-temperature-probe.yml`) | Compares Copernicus, Landsat and the carried-forward estimate with GKD lake stations. By hand, or when the satellite water temperature code changes. |
| **DRV club catalog** (`drv-catalog.yml`) | Rebuilds `data/catalogs/de-drv.json`. By hand, or when its script changes on `main`. |
| **Club catalog** (`club-catalog.yml`) | Rebuilds `data/catalogs/de-osm.json` from OpenStreetMap. By hand, or when its script changes on `main`. |

## Traffic light defaults

For small racing boats (1x, 2x, 2-), the app's starting boat; see
`backend/rowfrog/score.py`. Other boats and limits the user changed are
worked out on the phone (`ios/RowFrog/Limits.swift`).

| Condition | Amber from | Red above |
| --- | --- | --- |
| Mean wind | 5.5 m/s (Bft 4) | 8 m/s (Bft 5) |
| Gusts | 8 m/s | 10.3 m/s (20 kn) |
| Wave height | 0.15 m | 0.25 m |
| Visibility | 1 km or less | under 500 m |
| Rain and hail | heavy rain, 4 mm per hour or more | hail |
| Water temperature | under 15 °C with a life jacket hint; under 10 °C also "Very cold", a hint for singles and wind and gust limits 1 m/s lower; under 4 °C near-freezing water (never red on its own) | – |
| Shore warning lights (DWD lake warning) | strong wind (40 flashes a minute) for all other boats | strong wind for small racing boats and training boats; storm (90 flashes a minute) for all |
| DWD weather warning for the place | minor (yellow) | moderate (orange) or above, or any thunderstorm |
| Ice | shore ice possible, or drift ice on a river | ice cover likely |
| Daylight | sunrise or sunset within the hour | sun down for the whole hour |

## In progress

Not on `main` yet:

- Weather models chosen per region from the model check results, and a
  model choice in Settings for everyone. A test version of the picker is
  hidden behind the developer options (see the handbook).

Not built yet: webcams.

## Licence

Proprietary, all rights reserved. See `LICENSE`.
