# 0066. The night reason and the info-only warning line each fit on one line

- Date: 2026-11-27
- Status: decided (owner, thread "Shorten night and Ampel note lines", 27 Nov 2026: picked "N1 + A5" on the decision card 16:28 CET (15:28 UTC); mock-ups https://claude.ai/artifact/Qw3WuaUvczmArv8dtUnVW9)
- Where: `ios/RowFrog/Models.swift` (`Reason.baseExplanation`, "daylight"), `ios/RowFrog/LocationPageView.swift` (`warningsLine`), `ios/RowFrog/Localization.swift`, `web/public/app/shared.js` (`reasonExplanation`), `web/public/app/app.js` (`laterWarningLine`), `web/public/app/style.css` (`.no-warning`).

## Why

Every night the top tile's red reason "Die Sonne ist untergegangen. Rudern wird nur bei Tageslicht empfohlen." took two lines, even on the widest iPhone. The grey line for a warning that does not count for the rowing light, "DWD-Warnung: Frost ab 17:00 · zählt nicht für die Ampel", wrapped on every iPhone at standard text size. The sun line at the tile's end already gives the sunrise time, and the ⓘ in front of the grey line already marks it as information.

## Decision

- Night (N1): "Nur bei Tageslicht rudern." / "Row in daylight only." The same text shows for night hours wherever a reason is explained (48 hours, website).
- Info-only warning (A5): "DWD-Warnung: Frost ab 17:00 · nur Info" / "DWD warning: Frost from 17:00 · info only" where it fits on one line, else the event and its start only, "Frost ab 17:00 · nur Info" (ViewThatFits in the app, `fit-line` on the website, as for "Alles innerhalb der Grenzwerte"). The full sentence ("Zählt nicht für die Ruderampel …") stays in the warnings card.
- On the website the ⓘ stays beside the text and the text wraps beside it, never under it.
- App first, the website the same.

## Turned down

- N2 "Dunkel bis Sonnenaufgang.", N3 "Dunkel: nur bei Tageslicht rudern." (two lines at XXXL on the smallest iPhone), N4 "Nachts nicht rudern." (reads like a ban, while the app only advises).
- A1 the full form only, A2 "DWD: … · nur Info", A3 "… · nicht für die Ampel", A4 the event only.
