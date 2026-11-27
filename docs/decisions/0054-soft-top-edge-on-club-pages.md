# 0054. The top of a club page has no bar: the cards blur away under the buttons

- Date: 2026-11-19 (built 20 Nov)
- Status: decided, how it is built replaced by [0063](0063-own-soft-blur-at-the-top-of-club-pages.md) (owner's pick D on 19 Nov 2026, 16:29 CET (15:29 UTC): "Then lets go with option D for now. Keep the mock-ups, perhaps we change later on once again", after the mock-ups artifact "Top bar over a picture" and the owner's iPad screenshots of app, website and the Claude app; 16:31 CET: pages without a background picture get the same; 20 Nov 18:03 CET: "Yes, lets try 1", the empty bar that makes iOS blur as deep as in Mail, with the buttons and their places unchanged)
- Where: app `pages(_:chrome:insets:)` (a `NavigationStack` per club page), `TopEdgeFade` and `InlineClubTitle` in `ios/RowFrog/RootView.swift`, `PageTopEdge` in `ios/RowFrog/LocationPageView.swift`; website `.soft-edge` and `.top-pill` in `web/public/app/style.css`, `paintClockStrip` in `web/public/app/backgrounds.js`
- Replaces: item 3 of [0037](0037-app-web-detail-check-picks.md) (title fade A)

## Decision

- With or without a background picture, no bar is drawn behind the clock, the top buttons and the small club name, on iPhone and iPad, upright and on its side, with the list shown or slid away.
- On iOS 26 and later iOS's own soft scroll edge blurs and darkens the cards under the clock and the buttons, more the higher they are, and only while the page is scrolled, as in Mail, the Claude app and Apple's other apps. The list beside the page is not touched while it is at its top.
- How: iOS sizes that soft edge to a navigation bar. Each club page therefore sits in its own `NavigationStack` whose bar holds one invisible 44 pt item, so the edge reaches just below the button line. The real buttons, the small name and their places stay the app's own overlays, so they keep still while the pages swipe. Tried and dropped (20 Nov, iOS 27 Simulator): the soft edge alone or with an empty safe-area bar (covers only the clock), real toolbar items (buttons slid with the page, merged glass, page edges instead of the card column), one stack around all pages (no soft edge).
- On iOS 18 the same bar gives iOS's standard frosted bar once the page is scrolled. Not seen on iOS 18 yet (no Simulator for it on the Mac); the fade mask (option C) stays in the code for pages outside the stack.
- The small club name sits in its own glass capsule.
- Low Power Mode keeps its plain strip, as before.
- The website follows with the same look (21 Nov 2026): four stacked blur layers (1, 3, 6 and 12 px), each masked to a shorter band from the top, plus a fade into the page's colour, over the area beside the list, 10 px below the line of buttons, only while scrolled. On the Home Screen the solid strip behind the clock (theme-color) takes the page's colour, or over a picture the median colour of the picture's top 5 % under its veil, and the edge starts there at full strength, so the two run into each other. Without backdrop-filter or with reduced transparency the edge is the colour fade alone.

## Why

The owner's iPad (build 885) showed warning text readable through the top bar, and a straight line where the bar met the club list. The glass of PR #439 (15 Nov) drew as a thin grey tint without blur on the iPad; the reason stayed unclear without a build. All options replace that glass.

## Turned down

- A: back to thick glass as in 0037 (the dark slab the owner flagged on 15 Nov).
- B: the blurred picture as the bar's fill (a soft step at the list remains).
- C everywhere (recommended by Claude): no blur at all; kept as the iOS 18 look. The owner may switch later; the mock-ups stay.
