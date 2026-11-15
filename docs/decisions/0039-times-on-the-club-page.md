# 0039. One update time, the model run by its name, "Now" for the running hour

- Date: 2026-11-15
- Status: decided (owner, thread "Make the app's times consistent", 15 Nov 2026 11:23 and 11:27 CET: header wording "Modelllauf 06 UTC · aktualisiert 10:01", lake view 2A, table 3A, widget and website follow)
- Where: `ios/RowFrog/LocationPageView.swift` (`updatedLine`, `runHour`, `isRunning`, warnings line), `ClubPageHeader.swift`, `LocationListView.swift`, `LakeViewCard.swift`, `HourRows.swift` (`isNow`), `UpdateCycles.swift`; website `web/public/app/app.js` (`updatedLine`, `runHour`, `isRunning`, `hourlyCard`, `updateCyclesBody`), `lakeview.js`
- Mock-ups: artifact "Times on the club page" (https://claude.ai/artifact/DvZ6muJUGoq8eAPbVoy3CL)

## Decision

- The club page header says "Modelllauf 06 UTC · aktualisiert 10:01": the ICON-D2 run by the hour it started in UTC (the name forecasters use: 00, 03, 06 … UTC) and when the server last built the club's file (`generatedAt`, the Pi's :00/:30 run). Without a known run: "Aktualisiert 10:01".
- The club list footer and the widget's clock show only that update time (the list's clubs can come from different runs).
- The warnings line says "geprüft" without its own time: the header has it.
- When the run was ready and when this device loaded the file are in the "How often data is updated" sheet, no longer in the header.
- The lake view card says "Jetzt" instead of "Jetzt, 10:00". The 48-hour table's first row says "Jetzt" instead of the running hour's start time, as the widget already did; VoiceOver reads "Jetzt, 10:00 bis 11:00".

## Why

The screenshot of 15 Nov 2026 10:13 CET showed "Vorhersage von 08:26" (the run's arrival on Open-Meteo, `weatherRun.available`), "geladen 10:11", "geprüft 10:01", "Jetzt, 10:00" and a table starting at 10:00, while the club list and the widget showed 10:01 under the same words. The arrival time changes only every 3 hours and never matches the :00/:30 rhythm; the hour slots' start times read like a wrong clock.
