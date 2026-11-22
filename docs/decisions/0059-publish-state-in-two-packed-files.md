# 0059. The publish state is kept in two packed files, written only when changed

- Date: 2026-11-22
- Status: decided (owner, thread "Review shared doc from Pi project", 22 Nov 2026 17:02 CET (16:02 UTC): go if all checks are green and the output stays the same). Asked for by the Pi project in its doc "rowfrog: fewer SD card writes from publish.pickle".
- Where: `scripts/publish_static.py` (`State.save`, `_write_whole`); files next to `--state`.

## Why

On the Pi the publisher rewrote its 25 MB state file `publish.pickle` twice in every 30-min run, about 1.2 to 2.4 GB of SD card writes a day, the largest single writer on the card. It wrote the file in place, so a power cut during a save left a broken file, and the next run then asked the weather APIs for everything again (about 2,700 Open-Meteo calls for an all-clubs run). About 97 % of the bytes are weather, which changes only in runs that load weather (4 of 14 runs on the Pi on the night of 22 Nov).

## Decision

- `--state FILE` keeps the small rest (warnings, water log marks, model runs, input prints …); `<stem>-weather<suffix>` next to it (Pi: `publish-weather.pickle`) keeps clubs, lakes, ice temperatures, outlooks, models and club runs. Both are gzip level 1.
- The weather file is written only when its fingerprint changed; the second save of a run (after the weather maps) never packs it.
- Every write goes to a temporary file, is flushed to the card and then renamed, so a power cut leaves the last whole file.
- The single file of before is read once, so the switch costs no API calls.
- `STATE_PACK=lzma0|none` exists for trials only; reading takes any of them.

Trial on 22 Nov 2026 with sample data and no network, 13 runs, today's code against the change: state written 545 MB against 13.6 MB; read 0.51 against 0.52 s; saves 1.09 against 0.62 s per run; every published file identical; the same API calls.

## Turned down

- Option B of the Pi project (state in RAM, copied to the card every 6 h): after a reboot the state could be up to 6 h old, which costs up to about 2,400 Open-Meteo calls and writes water log rows twice; it would also write more than this change.
- lzma preset 0: a third smaller, but a save that writes the weather takes 1.16 s instead of 0.69 s.
- Only comparing a hash of the whole file: the warnings' check time changes every run, so it would never skip.
