# 0064. The small print at a club page's end sits on the cards' plate over a picture

- Date: 2026-11-22
- Status: decided (owner, thread "Bug reports and small fixes", 22 Nov 2026: "Then lets go with B" 19:54 CET (18:54 UTC); mock-ups https://claude.ai/artifact/EYxqLL24fyWHNCtz4L1G7e)
- Where: `ios/RowFrog/Backgrounds.swift` (`plateBackground`), `ios/RowFrog/LocationPageView.swift` (credits), `ios/RowFrog/ForecastSourceView.swift`, `web/public/app/style.css` (`.page-end > .source`, `.credits`, `footer.links`).

## Why

Over a background picture the forecast source line, the credits and the website's footer links sat on a thin 25 % veil. Their secondary grey was hard to read in light mode, while the same grey on the cards reads fine.

## Decision

- Over a picture the small print at the page's end gets the cards' own plate: frosted like the cards with "Picture blurred", the solid card colour with "No picture". Over the plain background nothing changes.
- The text keeps the standard secondary grey (iOS `.secondary`, web `--sub`), the same as the cards' own small text.
- The buttons at the page's end stay as they are.
- App first, the website the same.

## Turned down

- A: keep the thin veil.
- C: B with darker text: a grey of its own that no other text uses.
- D and E: C with more frosted or solid buttons: the buttons were not the problem.
