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
  4. a few Lake Ice Extent 250 m and lake surface water temperature files
     from the public CDSE OData catalogue,
  5. the daily Lake Ice Extent 250 m (VIIRS, central Europe) over each lake
     last winter: the file is downloaded with the account and the pixel
     classes inside the lake's outline are counted.
Nothing is stored; the report goes to the log and the job summary.

Data: Copernicus Land Monitoring Service, free and open, credit "Copernicus".
"""

from __future__ import annotations

import io
import os
import re
import sys
import tempfile
import zipfile
from collections import Counter

import httpx

from rowerweather import locations, outlines

TOKEN_URL = "https://identity.dataspace.copernicus.eu/auth/realms/CDSE/protocol/openid-connect/token"
SH = "https://sh.dataspace.copernicus.eu"
ODATA = "https://catalogue.dataspace.copernicus.eu/odata/v1/Products"
DOWNLOAD = "https://download.dataspace.copernicus.eu/odata/v1/Products({id})/$value"
LAKES = ["starnberger-see", "ammersee", "regattastrecke-oberschleissheim"]
WINTER = ("2025-12-01T00:00:00Z", "2026-03-31T23:59:59Z")
# Ice products, and lake surface water temperature (LSWT) as a backup for lakes without a GKD station.
ICE_WORDS = re.compile(r"\b(ice|rlie|lie|lswt|surface water temperature)\b")
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
    for label, word in (
        ("Lake Ice Extent", "LIE"),
        ("River and Lake Ice Extent 20 m (Sentinel-1/-2)", "RLIE"),
        ("Lake surface water temperature", "LSWT"),
    ):
        say(f"## {label} files in the CDSE catalogue (public, no login)")
        flt = f"contains(Name,'{word}') and ContentDate/Start gt 2026-01-15T00:00:00.000Z and ContentDate/Start lt 2026-01-20T00:00:00.000Z"
        try:
            resp = client.get(ODATA, params={"$filter": flt, "$top": "10"}, timeout=60)
            resp.raise_for_status()
            for p in resp.json().get("value", []):
                say(f"  {p.get('Name')}  {p.get('ContentLength')} bytes")
            if not resp.json().get("value"):
                say("  none found with that name filter")
        except httpx.HTTPError as e:
            say(f"  OData search failed: {e!r}")


def inside(x: float, y: float, ring: list[tuple[float, float]]) -> bool:
    hit, j = False, len(ring) - 1
    for i, (xi, yi) in enumerate(ring):
        xj, yj = ring[j]
        if (yi > y) != (yj > y) and x < (xj - xi) * (y - yi) / (yj - yi) + xi:
            hit = not hit
        j = i
    return hit


def lie_products(client: httpx.Client) -> list[dict]:
    flt = (
        "contains(Name,'LIE250') and contains(Name,'CEURO') and endswith(Name,'_cog') "
        f"and ContentDate/Start ge {WINTER[0][:19]}.000Z and ContentDate/Start le {WINTER[1][:19]}.000Z"
    )
    found, params = [], {"$filter": flt, "$top": "100", "$orderby": "ContentDate/Start asc"}
    url: str | None = ODATA
    while url:
        resp = client.get(url, params=params, timeout=60)
        resp.raise_for_status()
        body = resp.json()
        found += body.get("value", [])
        url, params = body.get("@odata.nextLink"), None
    return found


def tif_from(content: bytes, folder: str) -> str:
    path = os.path.join(folder, "lie.tif")
    if content[:2] == b"PK":
        with zipfile.ZipFile(io.BytesIO(content)) as z:
            names = [n for n in z.namelist() if n.lower().endswith((".tif", ".tiff"))]
            with open(path, "wb") as f:
                f.write(z.read(names[0]))
    else:
        with open(path, "wb") as f:
            f.write(content)
    return path


def lie_winter(client: httpx.Client, locs) -> None:
    """Lake Ice Extent 250 m, class counts inside each lake's outline, day by day."""
    import rasterio
    from rasterio.warp import transform as reproject

    say()
    say("## Lake Ice Extent 250 m (VIIRS, central Europe), last winter")
    try:
        products = lie_products(client)
    except httpx.HTTPError as e:
        say(f"  catalogue search failed: {e!r}")
        return
    say(f"  {len(products)} daily files from {WINTER[0][:10]} to {WINTER[1][:10]}")
    rings = {lake_id: outlines.load(lake_id)[0] for lake_id in LAKES}
    rows: dict[str, list[str]] = {lake_id: [] for lake_id in LAKES}
    totals: dict[str, Counter] = {lake_id: Counter() for lake_id in LAKES}
    described = False
    with tempfile.TemporaryDirectory() as folder:
        for product in products:
            day = product["ContentDate"]["Start"][:10]
            try:
                resp = client.get(DOWNLOAD.format(id=product["Id"]), timeout=120, follow_redirects=True)
                resp.raise_for_status()
                path = tif_from(resp.content, folder)
            except (httpx.HTTPError, zipfile.BadZipFile, IndexError) as e:
                say(f"  {day}: download failed {e!r}")
                if not described:
                    return
                continue
            with rasterio.open(path) as ds:
                if not described:
                    described = True
                    say(f"  file: crs {ds.crs}, pixel {ds.res}, bands {ds.count}, nodata {ds.nodata}")
                    say(f"  tags: {dict(list(ds.tags().items())[:12])}")
                    say(f"  band tags: {dict(list(ds.tags(1).items())[:12])}")
                for lake_id, ring in rings.items():
                    xs, ys = zip(*ring)
                    if str(ds.crs) != "EPSG:4326":
                        xs, ys = reproject("EPSG:4326", ds.crs, list(xs), list(ys))
                    shore = list(zip(xs, ys))
                    window = rasterio.windows.from_bounds(min(xs), min(ys), max(xs), max(ys), ds.transform)
                    window = window.round_offsets().round_lengths()
                    data = ds.read(1, window=window, boundless=True)
                    t = ds.window_transform(window)
                    counts: Counter = Counter()
                    for r in range(data.shape[0]):
                        for c in range(data.shape[1]):
                            x, y = t * (c + 0.5, r + 0.5)
                            if inside(x, y, shore):
                                counts[int(data[r, c])] += 1
                    totals[lake_id].update(counts)
                    rows[lake_id].append(f"    {day}  " + "  ".join(f"{k}:{v}" for k, v in sorted(counts.items())))
    for lake_id in LAKES:
        lake = locs.lakes.get(lake_id)
        say()
        say(f"  {lake.name if lake else lake_id}: class totals over the winter {dict(sorted(totals[lake_id].items()))}")
        for line in rows[lake_id]:
            say(line)


def main() -> int:
    locs = locations.load()
    with httpx.Client() as client:
        odata_sample(client)
        if not os.environ.get("CDSE_CLIENT_ID") or not os.environ.get("CDSE_CLIENT_SECRET"):
            say("CDSE_CLIENT_ID / CDSE_CLIENT_SECRET are not set; add them as repository secrets for the rest of this check.")
            write_summary()
            return 0
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
        lie_winter(client, locs)
    write_summary()
    return 0


def write_summary() -> None:
    summary = os.environ.get("GITHUB_STEP_SUMMARY")
    if summary:
        with open(summary, "a", encoding="utf-8") as f:
            f.write("### Satellite ice data\n```\n" + "\n".join(report) + "\n```\n")


if __name__ == "__main__":
    sys.exit(main())
