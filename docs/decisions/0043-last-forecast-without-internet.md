# 0043. Without internet the last forecast shows, and downloads give up sooner

- Date: 2026-11-16
- Status: done from the owner's bug report (three iPhone screenshots, build 885, 16 Nov 2026: flight mode, and a plane's Wi-Fi that lets only messaging through); no open choice
- Where: `ios/RowFrog/APIClient.swift` (`APIClient.session`, `keptForecast`), `ios/RowFrog/LocationStore.swift` (`ForecastStore.showKept`); website `web/public/app/shared.js` (`loadForecast`, `keepForecast`, `keptForecast`, `READ_TIMEOUT`), `web/public/app/app.js` (`renderClub`, `drawClubPage`, `fillRow`, `paintRow`, `forecastLines`)

## Decision

- The app keeps the last download of each club's forecast on the phone (it did already, for the 304 check, in Caches/API). When a club has nothing shown yet, as after a fresh start, that kept forecast shows at once with "Updating…" while the new one loads. If the download fails, it stays with the same line as after a return to the app: "Could not update: no internet connection. Showing data from 12:02." An old one also gets the out-of-date line. A kept forecast whose hours are all past is not shown; then "No forecast" stays.
- Own places (forecast straight from Open-Meteo) are not kept; they behave as before.
- App downloads give up after 15 seconds without a byte from the server and after 60 seconds in all (the system default waited 60 seconds per byte). The website's downloads give up after 20 seconds in all (was 30).
- The website does the same (owner, 16 Nov 2026 13:31 CET: "so the behavior of app and website are the same"): it keeps each club's last forecast in the browser's Cache Storage (`rf-forecasts`, about 100 KB per club, too big for localStorage). With nothing loaded in this visit, the club page and the list show it at once, the page with "Updating…" under the update line; the page is drawn again when the download answers, or keeps it with "Could not update: …" when it fails.

## Why

On 16 Nov 2026 the owner's iPhone, started fresh in flight mode at 12:30, said "Keine Vorhersage" although the app had loaded MRC 1880's forecast at 12:02; the same phone, back from the background, showed that forecast with "Aktualisieren fehlgeschlagen: keine Internetverbindung. Daten von 12:02." The kept file was only used for the ETag, never shown. On a plane's Wi-Fi that passes only messaging apps, the page showed "Vorhersage wird geladen …" with empty cards; with nothing kept shown and the system's 60-second wait per byte, the failure line could not come for at least a minute (assumption: the phone's own log was not read).
