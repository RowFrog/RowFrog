# 22. Route editor: every edit counts, Save as new, a real Undo

- Date: 2026-11-12
- Status: decided (owner)
- Where: `ios/RowFrog/Charts/route-editor.json`, `ios/RowFrog/RouteDraft.swift`, `web/public/app/routedraft.js`

## Decision

1. Every edit (add, insert, drag, delete, Clear, way back) makes an open saved route "changed"; undoing back to the saved shape makes it "saved" again. It is compared, not a flag.
2. Save updates the open saved route; "Save as new route" keeps it and saves a copy.
3. Undo is a real history in the app and on the website, and it includes the way back. Opening a route starts a new history.

## Why

Before, the app and the website treated drags, Undo and the way back differently, and Save sometimes made a new route and sometimes overwrote the old one.

## Turned down

Keeping the old behaviour, where some edits left the route marked as saved.
