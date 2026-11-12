# 7. Forecasts as static files, free hosting first, one address

- Date: 2026-10-20
- Status: decided (owner)
- Where: `scripts/publish_static.py`, `ios/project.yml`

## Decision

The backend publishes its answers as static files (on free GitHub hosting to start). The app reads only `https://api.rowfrog.com/v1`, so moving to a rented server later means changing one DNS record at Cloudflare.

## Why

No running costs before launch, and no lock-in.

## Turned down

A small rented server from day one; it stays possible before the App Store launch.
