# 13. The rowing light counts water within 1 km of the launch point

- Date: 2026-11-06
- Status: decided (owner)
- Where: `backend/rowfrog/lake_view.py` (`NEARBY_M`), `ios/RowFrog/Models.swift`

## Decision

Option C: besides the launch point itself, the light counts the lake squares within 1 km of it (on rivers 1 km up and downstream), one constant for all. Worse water nearby gives its own reason line.

## Why

Rowers are off the launch point within minutes, so the water just off the shore counts too.

## Turned down

The other options offered in the thread (A and B).
