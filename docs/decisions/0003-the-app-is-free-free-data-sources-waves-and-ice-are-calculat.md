# 3. The app is free; free data sources; waves and ice are calculated

- Date: 2026-10-18
- Status: decided (owner)
- Where: `backend/rowfrog/sources/`, `backend/rowfrog/lake_view.py`

## Decision

The app is free for now. All conditions come from free sources (DWD via Open-Meteo, GKD Bayern, DWD radar, Copernicus). Waves (fetch-limited, from the lake outline) and ice cover are calculated, since no free source gives them.

## Why

No income yet, so no paid API. The free tiers cover the needs while the app is free.

## Turned down

WeatherKit as the main source (kept as a fallback idea).
