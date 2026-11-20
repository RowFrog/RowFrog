# 0051. Only the real app and the website count as use

- Date: 2026-11-19
- Status: done (owner's pick on 19 Nov 2026, 21:54 CET (20:54 UTC): option B "Count only the real app" for now, the minimum-use rule later)
- Where: `realUse()` in `cloudflare/usage/src/index.js`; tests in `cloudflare/tests/usage.test.mjs`; `APIClient.get` in `ios/RowFrog/APIClient.swift` (Simulator header); handbook row "Usage counter"

## Why

On 19 Nov the half-hourly forecast runs built 37 "used" clubs instead of about 10, and Open-Meteo reached 69 % of its free daily limit. Cloudflare's traffic for 17 Nov (path `/v1/clubs/`, 520 requests) showed why: about 289 loads came from the CI tap tests on GitHub's Mac runners (User-Agent `RowFrog/1`), and 73 from `curl/8.5.0` in a cloud session of this project, which loaded 27 catalog clubs a to z once each. One load in 7 days makes a club used, at about 25 Open-Meteo calls a day. The owner deleted the 27 rows on 19 Nov at 20:26 CET; the 20:30 run built 10 clubs.

## Decision

- The usage counter counts a club forecast or lake view only for the app and widget with a stamped build number (User-Agent `RowFrog/<build>` or `RowFrogWidget/<build>`, build above 1) and for the website (Origin or Referer `rowfrog.com` or `www.rowfrog.com`).
- Not counted, but still served: builds without a stamp (build 1, CI), curl, Python and other scripts, requests without a User-Agent, and any request with the header `X-RowFrog-Test`.
- The app in the Simulator (Xcode runs, Mac screenshots) sends `X-RowFrog-Test: 1`, as those builds carry a real build number (`APIClient.get`). Real iPhones and iPads count as before; the website is unchanged.

## Later (option A)

- A club counts as used only after loads on 2 or more days, or 3 or more loads in 7 days (`used()` in `scripts/publish_static.py`). Then one look by a visitor no longer keeps a club on the half-hourly runs for a week. Wanted once many people browse clubs they don't follow.

## Turned down

- Only the minimum-use rule: the CI tests would keep counting.
- Waiting for the 27 clubs to drop out on 24 Nov: the next script would add them back.
