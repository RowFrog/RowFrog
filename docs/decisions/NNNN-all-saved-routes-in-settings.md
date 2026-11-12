# NNNN. All saved routes in Settings

- Date: 2026-11-12
- Status: decided (owner)
- Where: `ios/RowFrog/AllRoutesView.swift`, `ios/RowFrog/SettingsView.swift`, `web/public/app/lakeview.js` (`renderAllRoutes`)

## Decision

Settings has a Routes row under Boats and limits. It lists every saved route, grouped by water, with the tools of Manage routes, and a tap opens the route on its lake map. Manage routes on the lake map stays as it is, for that water's routes.

## Why

Saved routes could only be found from each lake's map; there was no list across waters.

## Turned down

An "All routes…" link inside Manage routes (opening another water's map from inside a lake map gets awkward).
