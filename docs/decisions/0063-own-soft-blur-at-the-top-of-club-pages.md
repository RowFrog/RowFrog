# 0063. The soft blur at the top of the club pages is the app's own, with no bar per page

- Date: 2026-11-22
- Status: decided (owner, 22 Nov 2026, 18:55 CET (17:55 UTC): "Generally I like option 4", after the overview "Swipe crash fix options" with ways 1 to 4 and mock-ups per device)
- Where: `TopEdgeBlur` in `ios/RowFrog/TopEdgeBlur.swift`, `pages(_:chrome:insets:)` and `TopEdgeFade` in `ios/RowFrog/RootView.swift`, `PageTopEdge` in `ios/RowFrog/LocationPageView.swift`
- Replaces: the "How" and iOS 18 points of [0054](0054-soft-top-edge-on-club-pages.md); its look (no bar, cards blur away under the buttons only while scrolled, small name in a glass capsule, Low Power strip) stays

## Decision

- The club pages no longer sit in a `NavigationStack` each. The swiping pages are Apple's standard paged `TabView` again, as before #546.
- The blur at the top is the app's own: four UIKit blur layers stacked over each other, each faded out by a gradient a little higher than the one before, plus a light tint, the same method and proportions as the website's `.soft-edge` (#572). It is strongest under the clock and gone about 24 pt below the line of the top buttons and the small name, with no line where it ends.
- It lies over the page column only, never over the list beside it, and shows only while the page is scrolled.
- The same on iOS 18, 26 and 27, iPhone and iPad, upright and on its side, list shown or slid away.
- Low Power Mode keeps its plain strip.

## Why

- On 21 Nov 2026 the app quit on the owner's iPhone during quick swipes: UIKit's "top item belongs to a different navigation bar", because the paged `TabView` reuses pages and handed one page's bar item to its neighbour's bar. Repro on the Mac: 8 crashes in 583 swipes with a bar per page, 0 in 1,032 without.
- On the device, iOS's soft edge from that bar ended in a hard cut under the name capsule (owner's shots, 22 Nov 00:58 CET), not the soft fade-out picked in 0054.
- UIKit blur views are used rather than SwiftUI materials under a mask, because such a material did not blur on the owner's iPad (#439, 17 Nov 2026).

## Turned down

- 1: keep the bar per page with an own pager (PR #607): the hard cut stays, swipe questions open.
- 2: the same plus a short fade under the cut: a soft gap remains.
- 3: fade only, no blur: lighter, but less like Mail and the website.

## Open

- The Home Screen web app: how its solid strip behind the clock meets the blur (owner question, 22 Nov 18:55 CET).
- Checked on the owner's iPhone and iPad before merging.
