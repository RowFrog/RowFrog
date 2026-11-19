# 0050. The club list's cards: tight numbers, the text beside them gets the room

- Date: 2026-11-19
- Status: done (owner's pick on 19 Nov 2026, 15:35 CET (14:35 UTC): "Ok, lets go with it for now", after the mock-ups artifact "Club list cards: app and website" and the owner's iPad screenshots of app and website)
- Where: app `ListMetrics` and `ListLineLabelStyle` in `ios/RowFrog/LocationListView.swift`; website `.metrics` and `.row-why .lead` in `web/public/app/style.css` (unchanged, the model)

## Decision

- In each card of the club list, a symbol and its text stand as on the website: the symbol in a 20 pt column, 8 pt before the text; the two number columns 12 pt apart. Both grow with the text size.
- The same for the vest line and the warning line on the left, so their symbols line up with the numbers' rows.
- The width this frees goes to the text on the left: the status, "Why", the vest and the warning line wrap less and are cut less ("Weste tragen · n…" and "DWD-War…" before).
- No font size changes: Apple's text styles stay (name 20 pt, place and status 15, the small lines and numbers 12), and text that does not fit still wraps or ends in "…", never shrinks.
- Same day, website only (PR #542): the "Updated HH:MM" line under the list is centred without a plate, and the light's tint over a picture is as strong as the app's (22 %).

## Turned down

- The website copying the app's wider number columns: taller cards and more of the safety lines cut.
- Leaving app and website different.
