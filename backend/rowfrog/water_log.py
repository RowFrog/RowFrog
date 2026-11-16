"""A long-running log of lake water temperatures from satellite and stations.

The publishing run keeps satellite readings only for the last 30 days and
station readings only for the last day, which is enough for the app but not for
judging the satellite later (per-lake Landsat offsets, how small a lake can be,
winter). This module appends what the run already has to monthly CSV files, so
nothing is asked of GKD or the satellites for it:

- satellite-water-YYYY-MM.csv: every LSWT reading and every Landsat pass that
  saw a lake, with how much of the lake was clear; passes too cloudy for a
  reading are kept too (empty celsius, usable 0).
- station-water-YYYY-MM.csv: the hourly readings of the stations on lakes that
  clubs read (GKD, PEGELONLINE, BAFU), each hour once.

What was written is remembered in `logged` (kept in the publish state), so a
reading seen again by a later run is not written twice. Keys older than
KEEP_DAYS are dropped from it; by then no run sees them again.
"""

from __future__ import annotations

import csv
from collections.abc import Iterable
from datetime import datetime, timedelta, timezone
from pathlib import Path

from .sources import lake_temperature_satellite as sat

KEEP_DAYS = 60

SATELLITE_FIELDS = ["logged", "lake", "source", "platform", "day", "time", "first", "last", "celsius", "pixels", "seen_share", "usable"]
STATION_FIELDS = ["logged", "station", "name", "lakes", "time", "celsius"]


def _append(path: Path, fields: list[str], rows: list[dict]) -> None:
    if not rows:
        return
    path.parent.mkdir(parents=True, exist_ok=True)
    new = not path.exists()
    with path.open("a", newline="", encoding="utf-8") as f:
        w = csv.DictWriter(f, fieldnames=fields)
        if new:
            w.writeheader()
        w.writerows(rows)


def _prune(logged: dict[str, str], now: datetime) -> None:
    cutoff = (now - timedelta(days=KEEP_DAYS)).date().isoformat()
    for key in [k for k, day in logged.items() if day < cutoff]:
        del logged[key]


def log_satellite(
    folder: Path,
    readings: dict[str, list[sat.Reading]],
    looks: Iterable[sat.LandsatLook],
    logged: dict[str, str],
    now: datetime,
) -> int:
    """Writes the readings and Landsat looks not written before; returns the number of rows."""
    rows = []
    stamp = now.isoformat(timespec="minutes")
    for lake_id, found in sorted(readings.items()):
        for r in found:
            if r.source != sat.LSWT:
                continue  # Landsat comes from the looks, which also hold the cloudy passes
            key = f"{lake_id}|{r.source}|{r.first}|{r.last}"
            if key in logged:
                continue
            logged[key] = r.day.isoformat()
            rows.append({
                "logged": stamp, "lake": lake_id, "source": r.source, "platform": r.platform or "", "day": r.day.isoformat(),
                "time": "", "first": r.first.isoformat() if r.first else "", "last": r.last.isoformat() if r.last else "",
                "celsius": r.celsius, "pixels": r.pixels, "seen_share": "", "usable": 1,
            })
    for look in sorted(looks, key=lambda x: (x.time, x.lake)):
        when = look.time.astimezone(timezone.utc)
        key = f"{look.lake}|{sat.LANDSAT}|{when.isoformat()}"
        if key in logged:
            continue
        logged[key] = when.date().isoformat()
        r = look.reading
        rows.append({
            "logged": stamp, "lake": look.lake, "source": sat.LANDSAT, "platform": look.platform or "", "day": when.date().isoformat(),
            "time": when.isoformat(timespec="minutes"), "first": "", "last": "",
            "celsius": r.celsius if r else "", "pixels": look.clear_pixels, "seen_share": round(look.seen_share, 3), "usable": 1 if r else 0,
        })
    _prune(logged, now)
    _append(folder / f"satellite-water-{now:%Y-%m}.csv", SATELLITE_FIELDS, rows)
    return len(rows)


def log_stations(
    folder: Path,
    history: dict[str, list],
    names: dict[str, str],
    lakes: dict[str, list[str]],
    logged: dict[str, str],
    now: datetime,
) -> int:
    """Writes each station's hourly readings newer than the last one written; returns the number of rows.

    `history` maps a station key ("gkd:starnberg-16663002") to readings with
    `.time` and `.celsius`; `logged` keeps, per station key, the time of the
    newest reading written.
    """
    rows = []
    stamp = now.isoformat(timespec="minutes")
    for key in sorted(history):
        last = logged.get(f"station|{key}", "")
        newest = last
        for h in sorted(history[key], key=lambda h: h.time):
            t = h.time.astimezone(timezone.utc).isoformat(timespec="minutes")
            if t <= last:
                continue
            rows.append({"logged": stamp, "station": key, "name": names.get(key, ""), "lakes": " ".join(lakes.get(key, [])), "time": t, "celsius": h.celsius})
            newest = max(newest, t)
        if newest:
            logged[f"station|{key}"] = newest
    _append(folder / f"station-water-{now:%Y-%m}.csv", STATION_FIELDS, rows)
    return len(rows)
