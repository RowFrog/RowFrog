# Row Frog

Weather, conditions and forecasts for rowers at their rowing club, with
webcam pictures where they are available later on.

For each club's launch point the app shows an hourly green / amber / red
"can we row?" light for the next 48 hours, and the conditions behind it:
wind, gusts, computed wave height, fog, thunderstorm risk, air and water
temperature, rain radar, ice cover, official DWD warnings and daylight.
It starts with the lakes south of Munich (Starnberger See first) and can
show any club in the German Rowing Association's club list.

The app is free. It is an iPhone app (iOS 17 or later) written in SwiftUI;
Android may follow later.

> **Name.** The app is called **Row Frog** (working title until October 2026:
> RowerWeather). The app and widget use the bundle IDs `com.rowfrog.RowFrog`
> and `com.rowfrog.RowFrog.Widget`, the app group `group.com.rowfrog.RowFrog`
> and links starting with `rowfrog://`. The Xcode project, targets and folders
> and the Python package are still called `RowerWeather`.

## What the app does

**Locations.** On first start the list is empty: a short tour explains the
app, then the user picks a home base and more clubs. With location access
("While using") it suggests the 5 nearest clubs, otherwise 3 at random. The
search covers every club in the catalog (see [Club catalog](#club-catalog)).
Pages swipe left and right between saved locations, like the iOS Weather
app. The list shows each location's light and key numbers; swipe a row to
remove it or make it the home base. The saved list stays on the phone.

**Each location page** shows the rowing light and why it has that colour,
air and water temperature side by side, wave height, the hourly forecast for
48 hours, sunrise and sunset, and legends that explain every icon.

**DWD warnings.** Under the light the page shows the official DWD warnings:
the lake warning (strong wind or storm, as the shore lights show it) where
DWD runs its lake warning service (23 lakes, among them Starnberger See,
Ammersee and Chiemsee), and DWD's weather warnings for the municipality,
which cover rivers and canals too. When there is none the page says so and
when it was checked; when DWD cannot be reached it says that instead.
Warnings come from DWD's GeoServer (`backend/rowerweather/sources/dwd_warnings.py`)
and also set the hourly light. In English the app shows DWD's own English
text (from its English CAP files) with the German original below; where DWD
has no English version, only the event and headline are translated.

**Lake view and route planning.** A tile opens a map of the whole lake with
waves, wind and the light for each part of the lake, and a spot you can tap
for its details. "Plan a route" checks a route on the lake against the
forecast for the time you start, rowed once or out and back, and shows
where and when it gets rough. Routes are saved on the phone.

**Rain radar.** Each location page has a card with DWD's rain radar and
2-hour nowcast for the launch point, e.g. "Light rain from 21:30". The app
reads it from DWD directly (`ios/RowerWeather/RainRadar.swift`).

**Ice cover.** Every forecast carries an ice estimate per lake for today and
the coming week: no ice, shore ice possible, ice forming, ice cover likely,
or drift ice on rivers. Likely ice turns the hourly light red; possible shore
or drift ice turns it amber. The estimate is a frost model over the last
three months of air temperature plus the forecast week
(`backend/rowerweather/ice.py`); a measured water temperature above 3 °C
overrides it. On larger lakes the Copernicus Lake Ice Extent satellite map
checks it, and the ice tile shows the latest pass, e.g. "Satellite, Today:
open water".

**Satellite pictures.** Below the lake view a card shows the latest
Sentinel-2 picture of the lake, with a line such as "Sentinel-2 · 22 Oct ·
25 % of the lake under cloud" and an "i" that explains why a new picture
comes only every 2 to 5 days. A switch chooses between the latest pass
(clouds or not), the clearest one and, in cloudy weeks, a newer mostly clear
one; every picture shows the same area. Chips draw the shore, clubs, saved
routes, wind and, in winter, the satellite ice map over it. Tap for full
screen with zoom.

**Launch point map.** A map (Apple MapKit, no key needed) shows the launch
point the forecast is for, with its coordinates and a button to open it in
Maps.

**Widgets.** Home-screen and lock-screen widgets show the rowing light first,
with the temperature and the weather symbol beside each other.

**Settings** (cog on the location list):

- Appearance (light, dark or as the phone is set) and a Landscape switch (on by default; off
  keeps the app upright).
- Units with icons (wind in m/s, km/h, knots, mph or Beaufort; °C or °F; waves in m, cm or ft), language
  (English or German), date and time formats.
- Background pictures for all pages, single pages or single clubs: clear or
  blurred, frosted or solid tiles, or your own photo.
- App icon: the coxed double "rowing light" icon in light, dark and tinted,
  plus 10 alternates.
- Help: replay the tour. One-time tips point out features the first time they
  appear.
- Factory reset (keeps saved locations and the home base, resets the icon).

**Wide screens.** Phones on their side and the unfolded iPhone Duo get wide
layouts (two columns from 600 pt, a side list from 860 × 560 pt).

## Layout

| Path | What it is |
| --- | --- |
| `ios/` | SwiftUI iPhone app and widget. The Xcode project is generated from `project.yml` with XcodeGen. |
| `backend/` | Python (FastAPI) service that fetches the forecast, computes waves, the lake view and the traffic light, and serves the app. |
| `data/locations.json` | Lakes and clubs with confirmed launch points. Add a club or lake here; no code change is needed. |
| `data/catalog-drv.json` | Clubs from the German Rowing Association's club list (see [Club catalog](#club-catalog)). |
| `data/catalog.json` | More clubs found in OpenStreetMap. |
| `data/outlines/` | Lake outlines (GeoJSON) for the wave calculation and lake view, made with `scripts/fetch_lake_outline.py`. |
| `data/lake-depths.json` | Mean lake depths for the ice estimate. |
| `docs/screenshots/` | App screenshots from the "App screenshots" workflow. |
| `scripts/` | Catalog import, lake outlines, live data check, translation check and background drawing. |
| `CREDITS.md` | Data sources, licences and the credits the app must show. |

## Club catalog

The app's search offers about 470 clubs:

- `data/catalog-drv.json`: 469 clubs from the DRV club search
  (rudern.de/service/vereinssuche), written by `scripts/import_drv.py` via the
  **DRV club catalog** workflow (about 45 minutes). Each boathouse is geocoded
  (cached in `data/drv-geocode.json`) and matched to the lake or river it lies
  on: 158 on lakes, 253 on rivers (no wave calculation), the rest marked
  "Water near <town>". Only club facts are stored, no contact people, e-mail
  addresses or phone numbers. The DRV is credited; permission is still to be
  asked.
- `data/catalog.json`: clubs found in OpenStreetMap by
  `scripts/discover_clubs.py` via the **Club catalog** workflow.

Launch points from the catalogs are unconfirmed until a club is moved into
`data/locations.json`. When loading, `locations.json` wins over
`catalog-drv.json`, which wins over `catalog.json`; a catalog club within
300 m of a club from an earlier file is dropped.

## Run the backend

```sh
cd backend
pip install -e ".[dev]"
pytest
uvicorn rowerweather.api:app --reload
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
in); every 6 hours it refreshes all clubs. Weather is only loaded again after
a weather model has a new run, which keeps the job within Open-Meteo's free
limit; the last forecasts are kept between runs in the Actions cache.

Only `main` publishes to the live site. A branch can be published by running
the workflow by hand, which overwrites the live files until `main` publishes
again.

Release builds of the app read from there; Debug builds use a backend on the
Mac at localhost. To move to a server of our own, run
`uvicorn rowerweather.api:app` there and point the DNS record of
`api.rowfrog.com` at it; the app keeps its address.

## Run the app

On a Mac with Xcode 15 or later, install XcodeGen (`sudo port install
xcodegen` with MacPorts, or `brew install xcodegen`), then:

```sh
cd ios && xcodegen && open RowerWeather.xcodeproj
```

Run the backend first; the simulator reaches it at `http://localhost:8000`
(set in `project.yml` as `RWAPIBaseURL`).

## Workflows

| Workflow | What it does |
| --- | --- |
| **CI** (`ci.yml`) | Backend tests on every push to `main` and every pull request; the iOS build and tests run on pull requests only (on `macos-15-intel`, since Apple Silicon runners have not been assigned lately). |
| **App screenshots** (`screenshots.yml`) | Runs the backend with live data, starts the app in the iOS Simulator and saves screenshots of every screen to `docs/screenshots` on the same branch. Long pages are shot screen by screen (`-p1`, `-p2`, …). Tutzinger RV gets a made-up lake storm warning and the lake view a made-up south wind, both marked as samples in the app. Run it from the Actions tab; the `only` input limits it to matching screens. |
| **Publish forecasts** (`publish-backend.yml`) | Publishes the backend's answers to GitHub Pages, see [Hosting](#hosting). Needs the secrets `CDSE_CLIENT_ID` and `CDSE_CLIENT_SECRET` for satellite pictures and ice. |
| **Satellite ice check** (`satellite-ice.yml`) | Tries the Copernicus ice maps and Sentinel-2 pictures for our lakes with the same secrets. Runs by hand or when its scripts change. |
| **Live data check** (`live-check.yml`) | Downloads missing lake outlines from OpenStreetMap, checks club launch points against them and runs the forecast against live Open-Meteo and GKD data. Runs when the club list or data sources change; new outlines are committed back. |
| **DRV club catalog** (`drv-catalog.yml`) | Rebuilds `data/catalog-drv.json`. |
| **Club catalog** (`club-catalog.yml`) | Rebuilds `data/catalog.json` from OpenStreetMap. |

## Traffic light defaults

Proposed for small boats (1x, 2x) and to be tuned with rowers; see
`backend/rowerweather/score.py`.

| Condition | Amber from | Red above |
| --- | --- | --- |
| Mean wind | 5.5 m/s (Bft 4) | 8 m/s (Bft 5) |
| Gusts | 8 m/s | 12.8 m/s (46 km/h) |
| Wave height | 0.15 m | 0.30 m |
| Visibility | 1 km or less | under 500 m |
| Water temperature | under 15 °C (never red on its own) | – |
| DWD lake warning | strong wind | storm |
| DWD weather warning for the place | minor (yellow) | moderate (orange) or above, or any thunderstorm |
| Ice | shore ice possible, or drift ice on a river | ice cover likely |
| Daylight | sunrise or sunset within the hour | sun down for the whole hour |

## In progress

Not on `main` yet, each in an open pull request:

- A compact current-conditions card with detail sheets, and rowing limits you
  can set per boat.
- A per-region choice of weather model, with the forecast source shown in the
  app.

Not built yet: webcams.

## Licence

Proprietary, all rights reserved. See `LICENSE`.
