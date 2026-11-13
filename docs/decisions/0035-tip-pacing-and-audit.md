# 35. Tip pacing and the tips audit

- Date: 2026-11-12
- Status: decided (owner, thread "First-Start Tutorial and One-Time-Tips", 23:29 CET: "let's go with the proposal for now, and let's see how it comes out")
- Where: `ios/RowFrog/TipPacing.swift`, `ClubPageTips.swift`, `TutorialTips.swift`, `Tutorial.swift`; `web/public/app/tour.js` (`paceTips`, `pacedChoice`)

## Decision

1. **Pacing, app and website alike:** one tip on a screen; at most one new tip a day; no tips on the day of the tour; closing a tip never brings the next one at once; each tip has "Got it" and "No more tips" (Settings › Help › Show the tips again brings them back). Tips for a rare case or the moment of use skip the daily limit: water level in winter, water nearby, cold water, boats at other clubs, river current, and the route editor's tips while editing.
2. **Deleted tips:** What a reset does, Out on mobile data?, Pick your app icon (their screens already say it).
3. **Merged tips:** Rain on the way? + Rain radar map → one rain tip; Row a loop + One way or out and back → one "The way back" tip.
4. **Tour:** the boats page names the boat button on the club page; the locations page names ⋯ (browse by country, add a place); three lines off the full Conditions page (feels like, humidity, pressure: the More on the air tip covers them); iPad: hiding the list with the sidebar button.
5. **Added:** a tip in Settings › Widgets for the widgets' Layout and Marks options; What's new version 2 for people who finished the tour before.
6. **Placement (tip map section 6, rules R1-R7, owner 23:29 CET "we can go with the proposed rule set for now"):** a tip about a whole card sits under the card's title (app: `cardTip` environment in `TipPlacement.swift`; web: under the card's header); a tip about one control is a bubble on it (app: `popoverTip` via `bubbleAnchor`; web: `bubbleTip`, class `tip pop`). Club page: values, All values, the first hour row and the forecast line get bubbles; website also: Suggest the launch point, the map's chain button, Plan a route. A bubble never hands over to the next tip in its chain. Value page chart and map tips stay above the chart and map for now.
7. The lake map's "More or less panel" tip shows only with the full-width panel, not with the panel card on wide screens.

## Why

Right after the tour up to 8 tips showed at once and each closed one was replaced at once, so people would close them all unread. One at a time, spread over days, at the place they are about, gets them read.

## Turned down

Keeping all tips at once; dropping tips altogether. Rule 5 of the proposal (tips that wait for a second use) is left for later.
