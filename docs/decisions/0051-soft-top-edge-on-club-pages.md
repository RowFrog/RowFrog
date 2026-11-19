# 0051. The top of a club page has no bar: the cards blur away under the buttons

- Date: 2026-11-19
- Status: decided (owner's pick D on 19 Nov 2026, 16:29 CET (15:29 UTC): "Then lets go with option D for now. Keep the mock-ups, perhaps we change later on once again", after the mock-ups artifact "Top bar over a picture" and the owner's iPad screenshots of app, website and the Claude app; 16:31 CET: pages without a background picture get the same)
- Where: app `TopEdgeFade` and `InlineClubTitle` in `ios/RowFrog/RootView.swift`, `PictureTopEdge` in `ios/RowFrog/LocationPageView.swift`; website to follow
- Replaces: item 3 of [0037](0037-app-web-detail-check-picks.md) (title fade A)

## Decision

- With or without a background picture, no bar is drawn behind the clock, the top buttons and the small club name, on iPhone and iPad, upright and on its side, with the list shown or slid away.
- On iOS 26 the page's own soft scroll edge blurs and darkens the cards under the clock and the buttons, more the higher they are, and only while the page is scrolled, as in the Claude app and Apple's apps. The list beside the page is not touched while it is at its top.
- On iOS 18 (or an app built with an older Xcode) the cards fade out instead, gone at the line below the buttons (or below the clock until the small name shows), back over 28 pt (option C).
- The small club name sits in its own glass capsule.
- Low Power Mode keeps its plain strip, as before.
- The website follows with the same look.

## Why

The owner's iPad (build 885) showed warning text readable through the top bar, and a straight line where the bar met the club list. The glass of PR #439 (15 Nov) drew as a thin grey tint without blur on the iPad; the reason stayed unclear without a build. All options replace that glass.

## Turned down

- A: back to thick glass as in 0037 (the dark slab the owner flagged on 15 Nov).
- B: the blurred picture as the bar's fill (a soft step at the list remains).
- C everywhere (recommended by Claude): no blur at all; kept as the iOS 18 look. The owner may switch later; the mock-ups stay.
