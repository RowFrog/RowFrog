# 0049. The tour fits the screen: Next always in sight, side by side when wider than tall

- Date: 2026-11-17
- Status: done (owner's pick on 17 Nov 2026, 16:26 CET (15:26 UTC): "Then lets go for now with A + C", from the mock-ups artifact "Tour Pages That Fit"; reported on the website pinned to an iPad's Home Screen)
- Where: app `ios/RowFrog/TourLayout.swift` (`TourColumns`, `TourSideColumn`, `TourDots`), `TutorialView` and `TourPageView` in `Tutorial.swift`, `ClubChoicePage` in `TourClubChoice.swift` (split off Tutorial.swift); website `renderTour` in `web/public/app/tour.js`, `.tour` rules in `web/public/app/style.css`

## Decision

- **A, upright:** a tour page fills the screen and never scrolls as a whole. Skip at the top, the page dots and Next/Weiter at the bottom, always in sight. On the club choices (home base, more clubs) the icon, title, intro and search stay and only the club list scrolls. On the other pages the middle scrolls.
- **Searching on a phone:** the icon and the intro step aside while the search has text, so the list keeps room above the keyboard. Text, not focus: a tap on a club that ends the typing must not move the list under the finger.
- **C, wider than tall** (iPad and iPhone on their side, a computer window at least 560 pt wide): two columns, centred. Left: icon, title, intro, search, then the dots and Next at the bottom. Right: the list or the page's content at full height. At most 400 + 48 + 560 pt. A club choice's head starts at the top, level with its list; the other pages' heads sit in the middle. Little height (an iPhone on its side) gives a smaller icon and title.
- **Live:** turning the device or resizing the window switches between A and C at once, on the same page, with the search text and the clubs picked kept.
- The page dots are the tour's own (app `TourDots`, as the website's), so they can sit under the left column; a tap on a dot goes to that page.
- App and website alike; the app leads.

## Turned down

- B, only a pinned Next over a scrolling page: the list would still scroll the title and the search away.
- Keeping one column on wide screens: half the screen empty on an iPad on its side or a computer, and the list cut short in landscape phones.
