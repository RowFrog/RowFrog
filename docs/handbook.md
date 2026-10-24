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
- `-RWOpenClub <id>` open a club page; `-RWScrollTo hourly|launchpoint|lakeview|source`
- `-RWOpenForecastSource YES` open the forecast source sheet
- `-RWDeveloperOptions YES` and `-RWPickedModels '<dict><key>mrc-1880</key><string>ecmwf_ifs025</string></dict>'`
- `-RWShowSettings YES -RWScrollPage n` open the settings at section n
- `-RWLanguage de`, `-RWAppearance dark`, `-RWLandscape YES`

## What runs on its own (GitHub Actions)

| Workflow | When | Where you see it |
|---|---|---|
| Publish forecasts | every 30 min from main | api.rowfrog.com |
| Model check | 04:40 and 16:40 UTC | weekly report on the "Model check" issue (Mondays) |
| Usage limits | daily 06:10 UTC | comment on the "Usage limits" issue from 70 % of a limit, and on the 1st of the month |
| App screenshots | when its workflow file changes, or by hand | docs/screenshots |

## By hand

| Workflow | When to run it |
|---|---|
| Usage counter | once after setting it up, and whenever `cloudflare/usage/` changes on main (it runs itself then) |
| API check | to see whether api.rowfrog.com, the Cloudflare proxy and the usage counter answer |
| Model check with archive_days | once for a quick first score (60 days); otherwise leave it at 0 |
| App screenshots with `only` | to re-shoot some screens, e.g. `^8[1-7]-` |

## Secrets (names only; the values live in GitHub > Settings > Secrets)

`CLOUDFLARE_API_TOKEN`, `CLOUDFLARE_ACCOUNT_ID`, `USAGE_KEY` (usage counter),
`CDSE_CLIENT_ID`, `CDSE_CLIENT_SECRET` (Copernicus satellite pictures).
