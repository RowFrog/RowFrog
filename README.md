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
| `data/locations.json` | Lakes and clubs. Add a club or lake here; no code change is needed. |
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

## Licence

Proprietary, all rights reserved. See `LICENSE`.
