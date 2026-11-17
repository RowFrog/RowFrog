# 0048. The Row Frog icon's long-press menu: home base, lake view, rain radar, last opened club

- Date: 2026-11-17
- Status: done (owner's picks on 17 Nov 2026, 14:54 CET: "A for now", no weather in the menu, website shortcuts yes, no tutorial tip; from the mock-ups artifact "Row Frog Quick Actions")
- Where: `ios/RowFrog/QuickActions.swift` (list, scene delegate, `QuickLakeScreen`), `RootView.open(_:)`, the scene delegate named in `AppDelegate` (RowFrogApp.swift), `DefaultsKey.lastOpenedClub`; website `web/public/app/quickopen.js`, `openQuick` in app.js, `manifest.webmanifest` and `manifest.de.webmanifest` (chosen in `setLanguage`, i18n.js)

## Decision

- **Four items under iOS's own ones (option A):** the home base (name, "Heimatverein · <lake>"), its lake view, its rain radar ("Rund um <club>") and the club shown last other than the home base ("Zuletzt geöffnet"; the next saved club until there is one). iOS shows at most four app items. A water without a lake view leaves that item out. With no club saved the menu has one item, "Verein hinzufügen", which opens the club list.
- **No weather in the menu:** iOS keeps the items until the app runs again, so a rowing light there could be hours old. The menu is rewritten each time the app goes to the background, with the widget's data.
- **Links:** `rowfrog://club/<id>` (as the widget), new `rowfrog://lake/<id>`, `rowfrog://radar/<id>` (the club's id) and `rowfrog://add`. A link that comes on a cold start waits until the club list has loaded, so it is no longer replaced by the home base (this also helps the widget's tap).
- **Website:** the manifest's `shortcuts` with the same four items, English and German manifests by the page's language. A manifest's list is fixed, so the links name no club: `#/home`, `#/home/lake`, `#/home/radar` and `#/last` pick it in the browser. Chrome and Edge show them on Android and desktop; Safari on iPhone and iPad showed no sign of reading them when checked on 17 Nov 2026 (not confirmed on a device).
- **No tutorial tip:** iOS users know the long-press.

## Turned down

- Option B, the rowing light with its time in each line: goes stale until the app is opened again.
- Option C, up to four saved clubs only: loses the lake view and radar, the two screens that take most taps to reach.
