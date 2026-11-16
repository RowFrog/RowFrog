#!/usr/bin/env python3
"""How often Landsat 8/9 gives a usable water temperature for small lakes.

Usage (from the repository root, after `pip install -e "backend[satellite]"`):
    python3 scripts/small_lake_passes.py [first day, default 1 Jan] [lake ids ...]

For each lake (outline from data/outlines) it counts, over the period, the
Landsat passes that saw the lake whole, and how many of them would have given
a reading with the app's own rules (lake_temperature_satellite: 120 m shore
strip left out, at least 30 % of the rest clear and at least 50 clear pixels).
It also prints how many 30 m pixels are left after the shore strip, so a lake
that can never pass is visible at once. Only scenes with at most MAX_CLOUD %
cloud over the whole scene are read, to keep the run short. Results go to the
log, the job summary and small-lake-passes.csv. Nothing else is stored.

Data: Landsat courtesy of the U.S. Geological Survey, via Microsoft Planetary Computer.
"""

from __future__ import annotations

import csv
import math
import os
import statistics
import sys
import time
from collections import defaultdict
from itertools import pairwise
from datetime import date, datetime, timezone

import httpx
from rowfrog import outlines
from rowfrog.sources import lake_temperature_satellite as sat

LAKES = [
    "westbad-weiher",
    "stadtsee",
    "kleiner-wannsee",
    "stoessensee",
    "regattastrecke-oberschleissheim",
    "grosser-dutzendteich",
    "bugasee",
    "rotsee",
    "altwarmbuechener-see",
    "maschsee",
    "titisee",
    "alte-donau",
]
MAX_CLOUD = 70
SECONDS = 50 * 60

out: list[str] = []


def say(line: str = "") -> None:
    print(line, flush=True)
    out.append(line)


def area_km2(ring: list[tuple[float, float]]) -> float:
    lat0 = statistics.mean(y for _, y in ring)
    kx, ky = 111_320 * math.cos(math.radians(lat0)), 110_540
    return (
        abs(
            sum(
                x1 * kx * y2 * ky - x2 * kx * y1 * ky
                for (x1, y1), (x2, y2) in zip(ring, ring[1:] + ring[:1])
            )
        )
        / 2e6
    )


def read(
    client: httpx.Client, scene: dict, shores: dict[str, list[tuple[float, float]]]
) -> dict[str, tuple[int, int, float | None]]:
    """Per lake fully in the scene: (pixels after the shore strip, clear pixels, median °C or None)."""
    import rasterio
    from rasterio.features import rasterize
    from rasterio.warp import transform as warp
    from rasterio.windows import from_bounds

    token = sat._sas.get(client)
    found = {}
    with (
        rasterio.open(scene["assets"]["lwir11"]["href"] + "?" + token) as st,
        rasterio.open(scene["assets"]["qa_pixel"]["href"] + "?" + token) as qa,
    ):
        b = st.bounds
        for lake_id, ring in shores.items():
            xs, ys = warp(
                "EPSG:4326", st.crs, [p[0] for p in ring], [p[1] for p in ring]
            )
            if (
                min(xs) < b.left
                or max(xs) > b.right
                or min(ys) < b.bottom
                or max(ys) > b.top
            ):
                continue
            window = (
                from_bounds(min(xs), min(ys), max(xs), max(ys), st.transform)
                .round_offsets()
                .round_lengths()
            )
            temp = st.read(1, window=window, boundless=True, fill_value=0)
            bits = qa.read(1, window=window, boundless=True, fill_value=1)
            lake = rasterize(
                [{"type": "Polygon", "coordinates": [list(zip(xs, ys))]}],
                out_shape=temp.shape,
                transform=st.window_transform(window),
            ).astype(bool)
            for _ in range(sat.LANDSAT_SHORE_PIXELS):
                lake[1:, :] &= lake[:-1, :].copy()
                lake[:-1, :] &= lake[1:, :].copy()
                lake[:, 1:] &= lake[:, :-1].copy()
                lake[:, :-1] &= lake[:, 1:].copy()
            total = int(lake.sum())
            good = (
                lake
                & ((bits & sat.LANDSAT_BAD_BITS) == 0)
                & ((bits & sat.LANDSAT_WATER_BIT) != 0)
                & (temp != 0)
            )
            values = [
                c
                for c in (temp[good] * 0.00341802 + 149.0 - 273.15).tolist()
                if sat.plausible(c)
            ]
            ok = (
                total
                and len(values) / total >= sat.LANDSAT_SEEN_SHARE
                and len(values) >= sat.LANDSAT_MIN_PIXELS
            )
            found[lake_id] = (
                total,
                len(values),
                round(statistics.median(values), 1) if ok else None,
            )
    return found


def main(first: date, lake_ids: list[str]) -> int:
    last = datetime.now(timezone.utc).date()
    shores = {}
    for lake_id in lake_ids:
        rings = outlines.load(lake_id)
        if rings:
            shores[lake_id] = sat.thin(rings[0])
        else:
            say(f"- {lake_id}: no outline, left out")
    say(f"# Usable Landsat passes on small lakes, {first} to {last}")
    say(
        f"Scenes with at most {MAX_CLOUD} % cloud over the whole scene; app rules for a reading."
    )
    passes: dict[str, list[tuple[str, int, int, float | None, float]]] = defaultdict(
        list
    )
    started = time.monotonic()
    stopped = False
    with httpx.Client() as client:
        scenes = {}
        for lake_id, ring in shores.items():
            xs, ys = [x for x, _ in ring], [y for _, y in ring]
            for s in sat.landsat_scenes(
                client, [min(xs), min(ys), max(xs), max(ys)], first, last
            ):
                if s["properties"].get("eo:cloud_cover", 100) <= MAX_CLOUD and s[
                    "properties"
                ].get("platform") in ("landsat-8", "landsat-9"):
                    scenes[s["id"]] = s
        say(f"- {len(scenes)} scenes to read")
        for n, scene in enumerate(
            sorted(scenes.values(), key=lambda s: s["properties"]["datetime"])
        ):
            if time.monotonic() - started > SECONDS:
                say(f"- time limit reached after {n} scenes; later scenes not read")
                stopped = True
                break
            lon0, lat0, lon1, lat1 = scene["bbox"]
            here = {
                k: r
                for k, r in shores.items()
                if lon0 <= min(x for x, _ in r)
                and max(x for x, _ in r) <= lon1
                and lat0 <= min(y for _, y in r)
                and max(y for _, y in r) <= lat1
            }
            if not here:
                continue
            try:
                for lake_id, (total, clear, c) in read(client, scene, here).items():
                    passes[lake_id].append(
                        (
                            scene["properties"]["datetime"][:10],
                            total,
                            clear,
                            c,
                            scene["properties"].get("eo:cloud_cover", 0),
                        )
                    )
            except Exception as e:  # noqa: BLE001
                say(f"  {scene['id']}: {e!r}")

    say()
    say(
        "| Lake | Area (km²) | Pixels after shore strip | Passes read | Usable | Usable Apr–Oct | Usable Nov–Mar | Longest gap Apr–Oct (days) |"
    )
    say("| --- | --- | --- | --- | --- | --- | --- | --- |")
    rows = []
    for lake_id in sorted(shores, key=lambda k: area_km2(shores[k])):
        p = passes[lake_id]
        usable = sorted({d for d, _, _, c, _ in p if c is not None})
        summer = [d for d in usable if 4 <= int(d[5:7]) <= 10]
        winter = [d for d in usable if not 4 <= int(d[5:7]) <= 10]
        days = [date.fromisoformat(d) for d in summer]
        gap = max(((b - a).days for a, b in pairwise(days)), default=None)
        inner = max((t for _, t, _, _, _ in p), default=0)
        say(
            f"| {lake_id} | {area_km2(shores[lake_id]):.2f} | {inner} | {len(p)} | {len(usable)} | {len(summer)} | {len(winter)} | {gap if gap is not None else '–'} |"
        )
        rows += [(lake_id, d, t, cl, c, cc) for d, t, cl, c, cc in p]
    with open("small-lake-passes.csv", "w", newline="", encoding="utf-8") as f:
        w = csv.writer(f)
        w.writerow(
            [
                "lake",
                "day",
                "pixels_after_shore_strip",
                "clear_pixels",
                "median_c",
                "scene_cloud_pct",
            ]
        )
        w.writerows(rows)
    if stopped:
        say("Stopped at the time limit: later months are missing.")
    summary = os.environ.get("GITHUB_STEP_SUMMARY")
    if summary:
        with open(summary, "a", encoding="utf-8") as f:
            f.write("\n".join(out) + "\n")
    return 0


if __name__ == "__main__":
    args = sys.argv[1:]
    start = (
        date.fromisoformat(args.pop(0))
        if args and args[0][:2] == "20"
        else date(datetime.now(timezone.utc).year, 1, 1)
    )
    sys.exit(main(start, args or LAKES))
