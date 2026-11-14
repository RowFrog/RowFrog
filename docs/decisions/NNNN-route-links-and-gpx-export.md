# NNNN. Routes reach the browser by link first, GPX export second

- Date: 2026-11-14
- Status: decided (owner); the link is built, GPX export follows
- Where: `ios/RowFrog/RouteLink.swift`, `ios/RowFrog/AllRoutesView.swift`, `ios/RowFrog/ManageRoutesView.swift`, `web/public/app/routelink.js`, `web/public/app/lakeview.js` (`openSharedRoutes`, `shareRoutes`), `web/public/app/app.js` (`#/routes/add`)

## Decision

Routes saved in the app can be saved in a browser too, in two ways that do different jobs:

1. A share link: "Share link" in a route's menu and "Share all routes" at the top of Settings > Routes make a rowfrog.com link (`#/routes/add?r=<base64url JSON>`). Opened in a browser it saves the routes there (a route already saved is not saved again) and opens a single route on its lake map. The link carries name, water, way back and turning points at 5 decimals, not a rowed track. The website's Settings > Routes has the same share-all button.
2. A GPX export from the app, for other apps and devices (CrewNerd, Garmin, Strava) and as a backup. The website already imports GPX files.

## Why

The owner asked on 14 Nov 2026 whether routes can also be saved in the browser ("Is option A and B in combination possible and adviseable?", then "Go ahead.", Bug Fixes 2 thread, 13:58 CET). Routes live per device (app: UserDefaults `RWRoutes`; website: `rf.routes` in each browser), with no account or server copy.

## Turned down

Keeping routes on the server (needs accounts, no database for now). Only GPX (several steps for the plain phone-to-browser case).
