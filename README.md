# RowerWeather

Weather and conditions for rowers at different rowing locations, incl. weather and conditions forecast and web-cam footage if available.

The app shows, for each club's launch point, an hourly green / amber / red
"can we row?" light for the next 48 hours, with the conditions behind it:
wind, gusts, computed wave height, fog, thunderstorm risk and daylight.
The first lake is Starnberger See.

## Layout

| Path | What it is |
| --- | --- |
| `ios/` | SwiftUI iPhone app (iOS 17+). The Xcode project is generated from `project.yml` with XcodeGen. |
| `backend/` | Python (FastAPI) service that fetches the forecast, computes waves and the traffic light, and serves the app. |
| `data/locations.json` | Lakes and clubs with confirmed launch points. Add a club or lake here; no code change is needed. |
| `data/catalog-drv.json` | All clubs from the German Rowing Association's club list (rudern.de), written by `scripts/import_drv.py` (the "DRV club catalog" workflow). Each boathouse is geocoded and matched to the lake or river it lies on; launch points are unconfirmed. Geocoding results are cached in `data/drv-geocode.json`. |
| `data/catalog.json` | More clubs from OpenStreetMap that the app's search offers, written by `scripts/discover_clubs.py` (the "Club catalog" workflow). Launch points are unconfirmed until a club is moved into `locations.json`. |
| `data/outlines/` | Lake outlines (GeoJSON) for the wave calculation, made with `scripts/fetch_lake_outline.py`. |
| `CREDITS.md` | Data sources, licences and the credits the app must show. |

## Run the backend

```sh
cd backend
pip install -e ".[dev]"
pytest
uvicorn rowerweather.api:app --reload
```

Then open http://localhost:8000/lakes or http://localhost:8000/clubs/mrc-1880/forecast.

Waves are only computed for lakes that have an outline. To add Starnberger See:

```sh
python3 scripts/fetch_lake_outline.py starnberger-see "Starnberger See"
```

## Hosting

There is no server yet. The "Publish forecasts" workflow runs the backend on
GitHub every 30 minutes (confirmed clubs) and every 6 hours (all clubs) and
publishes its answers as files on GitHub Pages, at
https://rowerweatherfrog.github.io/RowerWeather/v1/ (same paths as the API:
`lakes`, `clubs/<id>/forecast`). Release builds of the app read from there;
Debug builds use a backend on the Mac at localhost. To move to a server of our
own, run `uvicorn rowerweather.api:app` there and change `RW_API_BASE_URL` for
Release in `ios/project.yml`.

## Run the app

On a Mac with Xcode 15 or later:

```sh
brew install xcodegen
cd ios && xcodegen && open RowerWeather.xcodeproj
```

Run the backend first; the simulator reaches it at `http://localhost:8000`
(set in `project.yml` as `RWAPIBaseURL`).

## Traffic light defaults

Proposed for small boats (1x, 2x) and to be tuned with rowers; see
`backend/rowerweather/score.py`.

| Condition | Amber from | Red above |
| --- | --- | --- |
| Mean wind | 5.5 m/s (Bft 4) | 8 m/s (Bft 5) |
| Gusts | 8 m/s | 12.8 m/s (46 km/h) |
| Wave height | 0.15 m | 0.30 m |
| Visibility | 1 km or less | under 500 m |
| DWD lake warning | strong wind | storm |
| DWD weather warning for the place | minor (yellow) | moderate (orange) or above, or any thunderstorm |
| Daylight | sunrise or sunset within the hour | sun down for the whole hour |

## The app

The app opens on the home base (MRC 1880 by default) and pages left and
right between saved locations, like the iOS Weather app. The list button
shows all saved locations with their light and key numbers; swipe a row to
remove it or make it the home base, and use the search to add clubs from
the catalog. The saved list is stored on the phone.

Each page shows, under the rowing light, the official DWD warnings: the lake warning (strong
wind or storm, as the shore lights show it) where DWD runs its lake warning
service (23 lakes, among them Starnberger See, Ammersee and Chiemsee), and
DWD's weather warnings for the municipality, which cover rivers and canals
too. When there is none the page says so and when it was checked; when DWD
cannot be reached it says that instead. Warnings come from DWD's GeoServer
(`backend/rowerweather/sources/dwd_warnings.py`) and also set the hourly light.
When the app is in English, warnings show DWD's own English text (from its
English CAP files on opendata.dwd.de) with the German original below; where DWD
has no English version, only the event and headline are translated.

Below the forecast a map (Apple MapKit, no key needed) shows the launch point
the forecast is for, with its coordinates and a button to open it in Maps.

## Licence

Proprietary, all rights reserved. See `LICENSE`.
