#!/usr/bin/env python3
"""Check which free sources could feed weather maps like the rain radar.

Usage: python3 scripts/weather_maps_probe.py   (from the repository root)

Looks for map layers and grids for wind, gusts, temperature, feels like,
humidity, air pressure, UV, lightning and fog/low cloud:

- DWD GeoServer (maps.dwd.de, the rain radar's server): WMS layers whose name
  or title matches, with their time steps, and one map picture of the region
  around Starnberg for each, to see that it answers and how big it is.
- EUMETSAT View (view.eumetsat.int): satellite fog/cloud and MTG lightning layers.
- DWD open data ICON-D2 (opendata.dwd.de): the model's regular-grid GRIB files
  per value, their size, and whether one decodes (to draw our own maps).
- DWD open data UV index forecasts.

Prints a report (also to the job summary). Nothing is stored.
"""

from __future__ import annotations

import bz2
import os
import re
import sys
import xml.etree.ElementTree as ET

import httpx

UA = {"User-Agent": "RowFrog/0.1 (+https://github.com/RowFrog/RowFrog)"}
# Starnberger See and about 50 km around it, lon/lat.
BBOX = (10.7, 47.6, 11.9, 48.3)
WANTED = {
    "wind": r"wind|böe|boee|gust|ff10|fx10|vmax|u_10|v_10",
    "temperature": r"temperat|t_2m|t2m|lufttemp",
    "feels like": r"gefühl|gefuehl|feels|apparent|wind.?chill|perceived",
    "humidity": r"feuchte|humid|relhum|dew|taupunkt",
    "pressure": r"druck|pressure|pmsl|mslp|bodendruck",
    "uv": r"\buv|uvi|ultraviol",
    "lightning": r"blitz|lightning|\bli_|_li\b|flash|gewitter|thunder",
    "fog": r"nebel|fog|low.?cloud|stratus|visib|sicht",
    "cloud": r"wolke|cloud|bewölk|satellit|seviri|rgb",
}
report: list[str] = []


def say(line: str = "") -> None:
    print(line, flush=True)
    report.append(line)


def strip(tag: str) -> str:
    return tag.rsplit("}", 1)[-1]


def wms_layers(client: httpx.Client, url: str) -> list[dict]:
    resp = client.get(url, params={"SERVICE": "WMS", "VERSION": "1.3.0", "REQUEST": "GetCapabilities"}, timeout=120)
    say(f"GetCapabilities {url}: HTTP {resp.status_code}, {len(resp.content) // 1024} KB")
    resp.raise_for_status()
    root = ET.fromstring(resp.content)
    layers = []
    for el in root.iter():
        if strip(el.tag) != "Layer":
            continue
        name = title = abstract = ""
        times = ""
        for child in el:
            t = strip(child.tag)
            if t == "Name":
                name = child.text or ""
            elif t == "Title":
                title = child.text or ""
            elif t == "Abstract":
                abstract = (child.text or "")[:160]
            elif t == "Dimension" and child.get("name", "").lower() == "time":
                times = (child.text or "").strip()
        if name:
            layers.append({"name": name, "title": title, "abstract": abstract, "times": times})
    say(f"  {len(layers)} layers")
    return layers


def describe_times(times: str) -> str:
    if not times:
        return "no time steps"
    parts = times.split(",")
    if len(parts) == 1 and "/" in parts[0]:
        return f"range {parts[0]}"
    return f"{len(parts)} steps, {parts[0]} … {parts[-1]}"


def try_map(client: httpx.Client, url: str, layer: str, crs84: bool = True) -> str:
    params = {
        "SERVICE": "WMS", "VERSION": "1.3.0", "REQUEST": "GetMap", "LAYERS": layer, "STYLES": "",
        "CRS": "EPSG:4326", "BBOX": f"{BBOX[1]},{BBOX[0]},{BBOX[3]},{BBOX[2]}",
        "WIDTH": "512", "HEIGHT": "512", "FORMAT": "image/png", "TRANSPARENT": "TRUE",
    }
    try:
        resp = client.get(url, params=params, timeout=60)
    except httpx.HTTPError as e:
        return f"map error {type(e).__name__}"
    kind = resp.headers.get("content-type", "")
    if "image" not in kind:
        return f"map HTTP {resp.status_code} {kind} {resp.text[:120]!r}"
    return f"map HTTP {resp.status_code} {len(resp.content) // 1024} KB"


def scan_wms(client: httpx.Client, url: str, label: str, max_maps: int = 40) -> None:
    say()
    say(f"## {label}")
    try:
        layers = wms_layers(client, url)
    except Exception as e:  # noqa: BLE001
        say(f"  FAILED: {type(e).__name__}: {e}")
        return
    maps = 0
    for topic, pattern in WANTED.items():
        rx = re.compile(pattern, re.I)
        hits = [l for l in layers if rx.search(l["name"]) or rx.search(l["title"])]
        say(f"### {topic}: {len(hits)} layers")
        for l in hits[:25]:
            line = f"- {l['name']} — {l['title']} — {describe_times(l['times'])}"
            if maps < max_maps:
                line += f" — {try_map(client, url, l['name'])}"
                maps += 1
            say(line)
            if l["abstract"]:
                say(f"    {l['abstract']!r}")


def listing(client: httpx.Client, url: str) -> list[str]:
    resp = client.get(url, timeout=60)
    if resp.status_code != 200:
        say(f"  {url}: HTTP {resp.status_code}")
        return []
    return re.findall(r'href="([^"?/][^"]*)"', resp.text)


def icon_d2(client: httpx.Client) -> None:
    say()
    say("## DWD open data ICON-D2 (regular lat-lon grid)")
    base = "https://opendata.dwd.de/weather/nwp/icon-d2/grib/"
    runs = [r.strip("/") for r in listing(client, base) if re.fullmatch(r"\d\d/", r)]
    say(f"runs: {runs}")
    if not runs:
        return
    run = runs[-1]
    variables = [v.strip("/") for v in listing(client, base + run + "/")]
    say(f"{len(variables)} values in run {run}: {', '.join(sorted(variables))}")
    for var in ["u_10m", "v_10m", "vmax_10m", "t_2m", "relhum_2m", "td_2m", "pmsl", "ps", "clct", "clcl", "vis", "lpi", "lpi_con_max", "ceiling", "tot_prec"]:
        files = [f for f in listing(client, f"{base}{run}/{var}/") if "regular-lat-lon" in f] if var in variables else []
        if not files:
            say(f"- {var}: {'not in run' if var not in variables else 'no regular-lat-lon files'}")
            continue
        size = ""
        head = client.head(f"{base}{run}/{var}/{files[0]}", timeout=30)
        size = f"{int(head.headers.get('content-length', 0)) // 1024} KB each"
        say(f"- {var}: {len(files)} files ({files[0]} …), {size}")
    # One file decoded, to see that the backend could draw maps from it.
    if "t_2m" in variables:
        files = sorted(f for f in listing(client, f"{base}{run}/t_2m/") if "regular-lat-lon" in f)
        if files:
            data = bz2.decompress(client.get(f"{base}{run}/t_2m/{files[1]}", timeout=120).content)
            try:
                import eccodes  # type: ignore

                gid = eccodes.codes_new_from_message(data)
                ni, nj = eccodes.codes_get(gid, "Ni"), eccodes.codes_get(gid, "Nj")
                values = eccodes.codes_get_values(gid)
                say(f"decoded {files[1]}: grid {ni}×{nj}, {len(values)} values, {values.min() - 273.15:.1f}…{values.max() - 273.15:.1f} °C, "
                    f"lat {eccodes.codes_get(gid, 'latitudeOfFirstGridPointInDegrees')}…{eccodes.codes_get(gid, 'latitudeOfLastGridPointInDegrees')}, "
                    f"lon {eccodes.codes_get(gid, 'longitudeOfFirstGridPointInDegrees')}…{eccodes.codes_get(gid, 'longitudeOfLastGridPointInDegrees')}")
            except Exception as e:  # noqa: BLE001
                say(f"decode failed: {type(e).__name__}: {e}")


def uv(client: httpx.Client) -> None:
    say()
    say("## DWD open data UV index")
    for url in ["https://opendata.dwd.de/climate_environment/health/forecasts/",
                "https://opendata.dwd.de/climate_environment/health/alerts/"]:
        say(f"{url}: {listing(client, url)[:40]}")


def main() -> None:
    with httpx.Client(headers=UA, follow_redirects=True) as client:
        scan_wms(client, "https://maps.dwd.de/geoserver/dwd/wms", "DWD GeoServer (maps.dwd.de)")
        scan_wms(client, "https://view.eumetsat.int/geoserver/ows", "EUMETSAT View", max_maps=30)
        icon_d2(client)
        uv(client)
    summary = os.environ.get("GITHUB_STEP_SUMMARY")
    if summary:
        with open(summary, "a") as f:
            f.write("\n".join(report) + "\n")


if __name__ == "__main__":
    sys.exit(main())
