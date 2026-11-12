# 16. One load state for everything the app loads

- Date: 2026-11-11
- Status: decided (owner)
- Where: `ios/RowFrog/Loadable.swift`, `web/public/app/logic.js`, `testdata/states/`

## Decision

Option B: forecasts, lake views, radar, satellite pictures and weather maps share one generic load state (`Loadable`: loading, failed, shown with an optional update in flight and the last failure). The website mirrors it (`loadable` in `logic.js`). A failed update keeps the old forecast, and the header says "out of date" with a reason that can be tapped.

## Why

Each store had its own flags that could contradict each other; one shape is testable and the same on both sides.

## Turned down

The other options in the state machine review; full statecharts are a later look, especially for the route editor.
