# 21. Statecharts as shared chart files (D-lite)

- Date: 2026-11-12
- Status: decided (owner); full D to be reviewed later
- Where: `ios/RowFrog/Charts/`, `ios/RowFrog/Statechart.swift`, `web/public/app/statechart.js`

## Decision

Screens with real states (first: the route editor) get one chart file per state machine, in a format close to SCXML and XState. A small reader in Swift and one in JavaScript run the same file; the guards and actions stay in code and shared tables in `testdata/states/` check that both behave alike. Screens only send events and read the state.

## Why

One description for the app, the website and a later Apple Watch app (Swift, so it shares the app's reader), and a way into full D without rewriting the screens.

## Turned down

A: hand-written enums per platform (simpler, but drifts between app and website). Full D, code generated from the charts (more tooling than the few machines need today; review it when Android work starts or there are about 8 to 10 machines).
