# Row Frog handbook

Everything that is not visible in the app or easy to find in the code:
hidden switches, how to test things, what runs on its own and what needs
you. Keep it current: every PR that adds a hidden feature, a workflow, a
secret or a manual step adds a line here.

## Hidden in the app

| What | How to reach it | What it does |
|---|---|---|
| Developer options | Settings > tap **Version** seven times | Shows the Developer section. Switching it off hides it again and puts every club back on the automatic weather model. Factory reset also turns it off. |
| Weather model picker (test) | Developer options on, then on a confirmed club (MRC 1880, MRSV Bayern, Tutzinger RV) tap the grey **Forecast** line at the bottom of the page | Pick Automatic (recommended), ICON-CH1, AROME or ECMWF IFS (not advised). The line then says "(your choice)". The widget always uses the automatic model. |
| Tour again | Settings > Help > Show the tour again | Replays the first-start tour; one-time tips come back on the next start. |
| Safety notice | First start, before the tour; later Settings > Legal > Safety notice | Has to be read to the end and agreed to. The device stores the agreed version and date (`RWSafetyAcceptedVersion`, `RWSafetyAcceptedAt`); factory reset keeps them. Raising `SafetyNotice.version` in `SafetyNotice.swift` makes everyone agree again. |
| What's new | Once after an update, to users who had already seen the tour | A sheet listing what changed (`WhatsNew` in `Tutorial.swift`). The device stores the version seen (`RWWhatsNewSeen`). For a new list: change `WhatsNew.points` and raise `WhatsNew.version`. New users finishing the tour do not get it. |
| Battery saving in Low Power Mode | Turn on Low Power Mode in iOS Settings > Battery (or Control Center) | Tiles over a picture are drawn solid whatever the tile style, the radar map waits for the play button, and the radar card refreshes every 15 minutes instead of 5. Turning it off brings everything back. |
| Legal notice (Impressum) | Settings > Legal | The placeholders in `LegalInfo` in `Legal.swift` must be filled in before release. |

### Testing the model picker

1. Settings > tap Version seven times > the Developer section appears.
2. Open MRC 1880, scroll to the bottom, tap the Forecast line.
3. Pick AROME. The sheet shows a spinner, then AROME first in the list; the
   line on the page says "Forecast: GeoSphere Austria AROME ... (your choice)".
4. Pick Automatic: back to "DWD ICON-D2".
5. Developer section > "All clubs back to the automatic model", or switch
   the option off: every club is automatic again.

If a picked model says "not published yet", wait for the next publishing
run: the other models are written every 3 hours, for the confirmed clubs
that someone opened in the last 7 days.

## Launch arguments (Simulator and screenshots)

Every setting can be set at launch, e.g. `-RWLanguage de`. The screenshot
workflow (`.github/workflows/screenshots.yml`) uses these; the most useful:

- `-RWDemoClubs YES` the three confirmed clubs with MRC 1880 as home base
- `-RWTutorialSeen YES -RWNoTips YES` skip the tour and tips
- `-RWOpenClub <id>` open a club page; `-RWScrollTo warnings|radar|conditions|lakeview|hourly|launchpoint|satellite|source|arrange|hourly-1` (`hourly-1` = second day of the 48-hour table)
- `-RWPageLayout "hourly,radar"` card order for all clubs (cards left out follow in the standard order); `-RWArrange YES` opens "Arrange this page"
- `-RWOpenRadarMap YES` open the rain radar map (`-RWRadarLoop NO` plays it once, otherwise it plays 3 times); `-RWOpenSatellite YES` open the satellite picture full screen, `-RWSatelliteLayers '(clubs, shore)'` the layers drawn over it; `-RWOpenHour n` open the n-th hour of the 48-hour table
- `-RWLiveLaunchMap YES` show the launch point card's live map instead of its still picture
- `-RWWidgetRadar YES` (with `-RWWidgetGallery YES`) light rain on the radar from 30 minutes on, to show the widget's radar line
- `-RWLegend lights` open the rowing light legend from the top tile
- `-RWOpenLakeView YES` open the lake view; `-RWLakeLegend YES` with its legend open; `-RWLakeImagery YES` Apple's satellite pictures under the lake (the switch in the lake view's top bar)
- `-RWChartSelect 5` a detail chart opens with the scrub line five hours from now
- `-AppleLanguages '(de)'` start as on a phone set to German (the app picks German from the phone's languages)
- `-RWOpenCondition <name>` open a detail view (swipe or the symbol menu moves to the others)
- `-RWTutorialPage n` open the first-start tour at page n (0 = welcome); `-RWShowTips YES` show every one-time tip; `-RWLaterTips YES` show the radar map and hour view tips, which otherwise wait until the rain radar and hourly tips are closed
- `-RWResetTips YES` show the one-time tips again, as after Settings › Help
- `-RWOpenForecastSource YES` open the forecast source sheet
- `-RWDeveloperOptions YES` and `-RWPickedModels '<dict><key>mrc-1880</key><string>ecmwf_ifs025</string></dict>'`
- `-RWShowSettings YES -RWScrollPage n` open the settings at section n
- `-RWLanguage de`, `-RWAppearance dark`, `-RWLandscape YES`
- `-RWSafetyAccepted YES` skip the first-start safety notice (the screenshot workflow passes it to every shot except 77 and 78)
- `-RWWhatsNewSeen 1000` keep the "What's new" sheet away (the screenshot workflow passes it to every shot except 114 and 115)
- `-RWStaleForecast YES` treat every forecast and lake view as more than 3 hours old (grey light and the out-of-date warning)
- `-RWSettingsPage safety|impressum|privacy|limits|boat:<id>|backgrounds` open those Settings pages

## What runs on its own (GitHub Actions)

| Workflow | When | Where you see it |
|---|---|---|
| Publish forecasts | every 30 min from main | api.rowfrog.com |
| Model check | 04:40 and 16:40 UTC | weekly report on the "Model check" issue (Mondays); its section "Once a day instead of twice?" shows whether the 04:40 run alone would rank the models the same (to decide later whether to drop the 16:40 run, about 700 Open-Meteo calls a day) |
| Usage limits | daily 06:10 UTC | comment on the "Usage limits" issue from 70 % of a limit, and on the 1st of the month. Covers Open-Meteo, Copernicus and, read with the Cloudflare token, Worker requests (100,000 a day) and D1 rows written (100,000) and read (5 million) on the free Workers plan |

## By hand

| Workflow | When to run it |
|---|---|
| Usage counter | once after setting it up, and whenever `cloudflare/usage/` changes on main (it runs itself then) |
| API check | to see whether api.rowfrog.com, the Cloudflare proxy and the usage counter answer |
| Model check with archive_days | once for a quick first score (60 days); otherwise leave it at 0 |
| Satellite water temperature check | after changing the satellite water temperature code (it runs itself on pushes that touch it): compares Copernicus LSWT, Landsat and the carried-forward estimate with GKD lake stations since 1 May; about 20 min |
| Water temperature stations | every few months, or when clubs are added: lists the GKD Bayern, PEGELONLINE and Swiss BAFU stations, shows how `data/water-stations.json` (the station each club reads, nearest on its own water) would change, and reads every station in it once. To take a changed list, run `python3 scripts/water_station_survey.py --write` locally and commit the file |
| App screenshots | only by hand: once a PR is ready for review, with `only` for the changed screens (e.g. `^8[1-7]-`); the full set only when the owner asks. Results land in docs/screenshots |

## Secrets (names only; the values live in GitHub > Settings > Secrets)

`CLOUDFLARE_API_TOKEN`, `CLOUDFLARE_ACCOUNT_ID`, `USAGE_KEY` (usage counter),
`CDSE_CLIENT_ID`, `CDSE_CLIENT_SECRET` (Copernicus satellite pictures, ice map and lake water temperature).
Landsat water temperatures come from Microsoft's Planetary Computer and need no secret.
