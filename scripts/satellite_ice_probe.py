#!/usr/bin/env python3
"""Look at Copernicus satellite ice data for our lakes, before the app uses it.

Usage (from the repository root, after `pip install -e backend`):
    CDSE_CLIENT_ID=... CDSE_CLIENT_SECRET=... python3 scripts/satellite_ice_probe.py

Uses a free Copernicus Data Space Ecosystem (CDSE) account: an OAuth client
from the Sentinel Hub dashboard (https://shapps.dataspace.copernicus.eu/dashboard/).
On GitHub the two values are repository secrets. The script prints:
  1. the Sentinel Hub collections on CDSE that look like ice products
     (River and Lake Ice Extent from Sentinel-1/-2, Lake Ice Extent),
  2. for each of those and each lake, the passes over the lake last winter,
  3. per pass, the share of the lake seen as ice, open water and cloud,
  4. a few Lake Ice Extent 250 m files from the public CDSE OData catalogue.
Nothing is stored; the report goes to the log and the job summary.

Data: Copernicus Land Monitoring Service, free and open, credit "Copernicus".
"""

from __future__ import annotations

import os
import re
import sys

import httpx

from rowerweather import locations, outlines

TOKEN_URL = "https://identity.dataspace.copernicus.eu/auth/realms/CDSE/protocol/openid-connect/token"
SH = "https://sh.dataspace.copernicus.eu"
ODATA = "https://catalogue.dataspace.copernicus.eu/odata/v1/Products"
LAKES = ["starnberger-see", "ammersee", "regattastrecke-oberschleissheim"]
WINTER = ("2025-12-01T00:00:00Z", "2026-03-31T23:59:59Z")
ICE_WORDS = re.compile(r"\b(ice|rlie|lie)\b")
# River and Lake Ice Extent classes (CLMS HR-S&I): 1 open water, 100 ice, 205 cloud, 254 other, 255 no data.
EVALSCRIPT = """//VERSION=3
function setup() {
  return {input: [{bands: ["BAND", "dataMask"]}],
          output: [{id: "share", bands: 3, sampleType: "FLOAT32"}, {id: "dataMask", bands: 1}]};
}
function evaluatePixel(s) {
  return {share: [s.BAND == 100 ? 1 : 0, s.BAND == 1 ? 1 : 0, s.BAND == 205 ? 1 : 0],
          dataMask: [s.dataMask && s.BAND != 255 && s.BAND != 254 ? 1 : 0]};
}
"""

report: list[str] = []


def say(line: str = "") -> None:
    print(line, flush=True)
    report.append(line)


def token(client: httpx.Client) -> str:
    resp = client.post(
        TOKEN_URL,
        data={
            "grant_type": "client_credentials",
            "client_id": os.environ["CDSE_CLIENT_ID"],
            "client_secret": os.environ["CDSE_CLIENT_SECRET"],
        },
        timeout=30,
    )
    resp.raise_for_status()
    return resp.json()["access_token"]


def ice_collections(client: httpx.Client) -> list[dict]:
    found, url = [], f"{SH}/api/v1/catalog/1.0.0/collections"
    while url:
        resp = client.get(url, timeout=60)
        resp.raise_for_status()
        body = resp.json()
        for c in body.get("collections", []):
            text = f"{c.get('id', '')} {c.get('title', '')} {c.get('description', '')}".lower()
            if ICE_WORDS.search(text):
                found.append(c)
        url = next((l["href"] for l in body.get("links", []) if l.get("rel") == "next"), None)
    return found


def band_name(collection: dict) -> str:
    bands = (collection.get("summaries") or {}).get("eo:bands") or []
    names = [b.get("name") for b in bands if b.get("name") and b.get("name") != "dataMask"]
    return names[0] if names else "RLIE"


def simplified(lake_id: str, max_points: int = 400) -> dict:
    """The lake's outer shoreline from data/outlines, thinned for the request."""
    ring = outlines.load(lake_id)[0]
    step = max(1, len(ring) // max_points)
    pts = ring[::step]
    return {"type": "Polygon", "coordinates": [[list(p) for p in pts] + [list(pts[0])]]}


def bbox(geometry: dict) -> list[float]:
    xs = [p[0] for p in geometry["coordinates"][0]]
    ys = [p[1] for p in geometry["coordinates"][0]]
    return [min(xs), min(ys), max(xs), max(ys)]


def passes(client: httpx.Client, collection: dict, geometry: dict) -> list[str]:
    body = {"collections": [collection["id"]], "bbox": bbox(geometry), "datetime": "/".join(WINTER), "limit": 100}
    dates, nxt = [], None
    while True:
        if nxt is not None:
            body["next"] = nxt
        resp = client.post(f"{SH}/api/v1/catalog/1.0.0/search", json=body, timeout=60)
        resp.raise_for_status()
        data = resp.json()
        dates += [f["properties"].get("datetime", "?") for f in data.get("features", [])]
        nxt = (data.get("context") or {}).get("next")
        if not nxt:
            return sorted(dates)


def shares(client: httpx.Client, collection: dict, geometry: dict) -> list[str]:
    data_type = collection["id"] if collection["id"].startswith("byoc-") else f"byoc-{collection['id']}"
    request = {
        "input": {
            "bounds": {"geometry": geometry, "properties": {"crs": "http://www.opengis.net/def/crs/EPSG/0/4326"}},
            "data": [{"type": data_type, "dataFilter": {}}],
        },
        "aggregation": {
            "timeRange": {"from": WINTER[0], "to": WINTER[1]},
            "aggregationInterval": {"of": "P1D"},
            "evalscript": EVALSCRIPT.replace("BAND", band_name(collection)),
            "resx": 0.0003,
            "resy": 0.0002,
        },
    }
    resp = client.post(f"{SH}/api/v1/statistics", json=request, timeout=120)
    if resp.status_code != 200:
        return [f"    statistics: HTTP {resp.status_code} {resp.text[:300]}"]
    lines = []
    for entry in resp.json().get("data", []):
        stats = entry["outputs"]["share"]["bands"]
        seen = stats["B0"]["stats"].get("sampleCount", 0) - stats["B0"]["stats"].get("noDataCount", 0)
        if seen <= 0:
            continue
        ice, water, cloud = (stats[b]["stats"]["mean"] for b in ("B0", "B1", "B2"))
        lines.append(
            f"    {entry['interval']['from'][:10]}  ice {ice:4.0%}  open water {water:4.0%}  cloud {cloud:4.0%}  ({seen} pixels)"
        )
    return lines or ["    statistics: no pass saw the lake"]


def odata_sample(client: httpx.Client) -> None:
    say("## Lake Ice Extent 250 m files in the CDSE catalogue (public, no login)")
    flt = "contains(Name,'LIE') and ContentDate/Start gt 2026-01-15T00:00:00.000Z and ContentDate/Start lt 2026-01-20T00:00:00.000Z"
    try:
        resp = client.get(ODATA, params={"$filter": flt, "$top": "10"}, timeout=60)
        resp.raise_for_status()
        for p in resp.json().get("value", []):
            say(f"  {p.get('Name')}  {p.get('ContentLength')} bytes")
        if not resp.json().get("value"):
            say("  none found with that name filter")
    except httpx.HTTPError as e:
        say(f"  OData search failed: {e!r}")


def main() -> int:
    if not os.environ.get("CDSE_CLIENT_ID") or not os.environ.get("CDSE_CLIENT_SECRET"):
        say("CDSE_CLIENT_ID / CDSE_CLIENT_SECRET are not set; add them as repository secrets to run this check.")
        return 0
    locs = locations.load()
    with httpx.Client() as client:
        odata_sample(client)
        client.headers["Authorization"] = f"Bearer {token(client)}"
        collections = ice_collections(client)
        say()
        say(f"## Ice collections on CDSE Sentinel Hub: {len(collections)}")
        for c in collections:
            extent = (c.get("extent") or {}).get("temporal", {}).get("interval")
            say(f"- {c['id']}: {c.get('title')}  band {band_name(c)}  time {extent}")
        for c in collections:
            say()
            say(f"## {c.get('title')} ({c['id']})")
            for lake_id in LAKES:
                lake = locs.lakes.get(lake_id)
                geometry = simplified(lake_id)
                try:
                    dates = passes(client, c, geometry)
                    say(f"  {lake.name if lake else lake_id}: {len(dates)} passes {WINTER[0][:10]} to {WINTER[1][:10]}")
                    for line in shares(client, c, geometry):
                        say(line)
                except httpx.HTTPError as e:
                    say(f"  {lake_id}: failed {e!r}")
                except (KeyError, ValueError) as e:
                    say(f"  {lake_id}: unexpected answer {e!r}")
    summary = os.environ.get("GITHUB_STEP_SUMMARY")
    if summary:
        with open(summary, "a", encoding="utf-8") as f:
            f.write("### Satellite ice data\n```\n" + "\n".join(report) + "\n```\n")
    return 0


if __name__ == "__main__":
    sys.exit(main())
