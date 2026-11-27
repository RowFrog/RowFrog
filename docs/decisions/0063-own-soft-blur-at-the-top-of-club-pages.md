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
- Home Screen web app (owner's pick B, 22 Nov 2026, 18:59 CET (17:59 UTC), card "Pick how the Home Screen clock strip meets the blur"): no solid strip behind the clock any more. The page runs on under the clock (`apple-mobile-web-app-status-bar-style` black-translucent) as in the app, so the soft edge covers the clock too and there is no step. iOS then always draws the clock in white, so a light dark veil sits behind it (`html::after` in standalone mode, lighter in dark mode). Turned down: A, keep the strip with a longer solid tint below it.

## Why

- On 21 Nov 2026 the app quit on the owner's iPhone during quick swipes: UIKit's "top item belongs to a different navigation bar", because the paged `TabView` reuses pages and handed one page's bar item to its neighbour's bar. Repro on the Mac: 8 crashes in 583 swipes with a bar per page, 0 in 1,032 without.
- On the device, iOS's soft edge from that bar ended in a hard cut under the name capsule (owner's shots, 22 Nov 00:58 CET), not the soft fade-out picked in 0054.
- UIKit blur views are used rather than SwiftUI materials under a mask, because such a material did not blur on the owner's iPad (#439, 17 Nov 2026).

## Added 25 Nov 2026 (owner, after the real-device shots of 23 Nov)

- The pinned 48-hour header stops on the table's last line and leaves together with it (pick B), in the app and on the website. Before, it rode to the tile's end and stood there alone with square corners over the tile's rounded end.
- The soft edge runs out 34 pt below the clock, or below the small name and the buttons, 10 pt deeper than at first, as deep as the website's looked.
- The website behaves as the app, in light and dark mode: the same depth and tint for the soft edge (system background, 45 % to clear), and glass buttons as clear as the app's in dark mode (28 % tint, nothing behind darkened, where it was 55 % and darker).

## Turned down

- 1: keep the bar per page with an own pager (PR #607): the hard cut stays, swipe questions open.
- 2: the same plus a short fade under the cut: a soft gap remains.
- 3: fade only, no blur: lighter, but less like Mail and the website.

## Open

- On a real Home Screen: whether the white clock stays readable over light pictures, and whether existing Home Screen icons pick up the new status bar style without being added again.
- Checked on the owner's iPhone and iPad before merging.
