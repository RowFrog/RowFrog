"""Looks at the official warning services for Austria and Switzerland.

Research only (thread "Add Austrian and Swiss weather warnings"): prints what
each service answers for a few club launch points, so we can tell which feed
covers what before building anything. Nothing is stored.

- GeoSphere Austria Warn API (warnungen.zamg.at / openapi.hub.geosphere.at),
- MeteoSwiss: the geo.admin.ch STAC catalogue (open data), the website's
  warning products and the app's API,
- MeteoAlarm feeds for Austria and Switzerland (CAP, EUMETNET),
- DWD's lake warning areas: does Bodensee cover the AT/CH shore clubs, and
  what does DWD answer for a point outside Germany.
"""

from __future__ import annotations

import json
import sys

import httpx

sys.path.insert(0, "backend")
from rowfrog.sources import dwd_warnings  # noqa: E402

UA = {"User-Agent": "RowFrog research probe (github.com/RowFrog/RowFrog)"}

AT_POINTS = {
    "Gmunden, Traunsee": (47.90762, 13.78344),
    "Seewalchen, Attersee": (47.95464, 13.58395),
    "St. Gilgen, Wolfgangsee": (47.76941, 13.3685),
    "Klagenfurt, Wörthersee": (46.62351, 14.24938),
    "Wien, Alte Donau": (48.23299, 16.43347),
    "Breitenbrunn, Neusiedler See": (47.94635, 16.73253),
    "Bregenz, Bodensee": (47.50719, 9.72955),
}
CH_POINTS = {
    "Zürich, Zürichsee": (47.35644, 8.53663, 8002),
    "Lausanne, Léman": (46.52183, 6.6327, 1007),
    "Kreuzlingen, Bodensee": (47.64761, 9.19825, 8280),
    "Arbon, Bodensee": (47.51844, 9.43764, 9320),
    "Locarno, Lago Maggiore": (46.14846, 8.77749, 6600),
    "Luzern, Vierwaldstättersee": (47.05, 8.31, 6006),
}


def head(title: str) -> None:
    print("\n" + "=" * 78 + f"\n{title}\n" + "=" * 78)


def show(resp: httpx.Response, limit: int = 1500) -> None:
    print(f"  HTTP {resp.status_code} {resp.headers.get('content-type', '')} {len(resp.content)} bytes")
    text = resp.text
    print("  " + text[:limit].replace("\n", "\n  "))


def get(client: httpx.Client, url: str, **params) -> httpx.Response | None:
    try:
        return client.get(url, params=params or None)
    except httpx.HTTPError as e:
        print(f"  {url}: {e!r}")
        return None


def keys_tree(obj, depth=0, maxdepth=3) -> None:
    pad = "    " * depth
    if isinstance(obj, dict):
        for k, v in list(obj.items())[:40]:
            kind = type(v).__name__
            sample = "" if isinstance(v, (dict, list)) else f" = {str(v)[:120]!r}"
            print(f"{pad}{k}: {kind}{sample}")
            if depth < maxdepth:
                keys_tree(v, depth + 1, maxdepth)
    elif isinstance(obj, list) and obj:
        print(f"{pad}[{len(obj)} items], first:")
        keys_tree(obj[0], depth + 1, maxdepth)


def geosphere(client: httpx.Client) -> None:
    head("GeoSphere Austria Warn API")
    for url in ("https://openapi.hub.geosphere.at/warnapi/v1/openapi.json",):
        r = get(client, url)
        if r is not None and r.status_code == 200:
            try:
                spec = r.json()
                print("  paths:", list(spec.get("paths", {}).keys()))
                print("  info:", json.dumps(spec.get("info", {}), ensure_ascii=False)[:800])
                for path in ("/getWarningsForCoords", "/getWarnstatus"):
                    print(f"  {path} responses:", json.dumps(spec["paths"][path]["get"].get("responses"), ensure_ascii=False)[:6000])
                print("  components:", json.dumps(spec.get("components", {}), ensure_ascii=False)[:9000])
                for p, ops in spec.get("paths", {}).items():
                    for m, op in ops.items():
                        if not isinstance(op, dict):
                            continue
                        params = [x.get("name") if isinstance(x, dict) else x for x in op.get("parameters", [])]
                        print(f"   {m.upper()} {p} params={params} :: {op.get('summary') or ''}")
            except ValueError:
                show(r)
        elif r is not None:
            show(r, 400)
    r = get(client, "https://warnungen.zamg.at/wsapp/api/getWarnstatus")
    if r is not None:
        print("\n getWarnstatus:")
        if r.status_code == 200:
            try:
                d = r.json()
                feats = d.get("features", [])
                print(f"  {len(feats)} warned areas now")
                if feats:
                    print("  first properties:", json.dumps(feats[0].get("properties"), ensure_ascii=False)[:800])
                types = {}
                for f in feats:
                    p = f.get("properties", {})
                    types[(p.get("wtype"), p.get("wlevel"))] = types.get((p.get("wtype"), p.get("wlevel")), 0) + 1
                print("  (wtype, wlevel) counts:", types)
            except ValueError:
                show(r, 600)
        else:
            show(r, 400)
    for name, (lat, lon) in AT_POINTS.items():
        for lang in ("de", "en"):
            r = get(client, "https://warnungen.zamg.at/wsapp/api/getWarningsForCoords", lon=lon, lat=lat, lang=lang)
            if r is None:
                continue
            print(f"\n getWarningsForCoords {name} lang={lang}: HTTP {r.status_code}")
            try:
                d = r.json()
            except ValueError:
                show(r, 400)
                continue
            props = d.get("properties", d)
            print("  location:", json.dumps(props.get("location", {}), ensure_ascii=False)[:300])
            warnings = props.get("warnings", [])
            print(f"  {len(warnings)} warnings")
            if name.startswith("Gmunden") and lang == "de":
                keys_tree({k: v for k, v in d.items() if k != "geometry"}, maxdepth=4)
            for w in warnings[:3]:
                print("  ", json.dumps(w, ensure_ascii=False)[:900])
    r = get(client, "https://warnungen.zamg.at/wsapp/api/getWarningsForCoords", lon=8.54, lat=47.36, lang="de")
    if r is not None:
        print("\n getWarningsForCoords for Zürich (outside AT):")
        show(r, 300)


def meteoswiss(client: httpx.Client) -> None:
    head("MeteoSwiss open data: STAC collections on data.geo.admin.ch")
    r = get(client, "https://data.geo.admin.ch/api/stac/v1/collections", limit=500)
    if r is not None and r.status_code == 200:
        cols = [c["id"] for c in r.json().get("collections", [])]
        ms = [c for c in cols if "meteoschweiz" in c]
        print(f"  {len(cols)} collections, {len(ms)} from MeteoSwiss:")
        for c in ms:
            print("   ", c)
        print("  any with warn/gefahr/alert:", [c for c in cols if any(k in c for k in ("warn", "gefahr", "alert", "danger"))])
    elif r is not None:
        show(r, 400)

    head("geo.admin.ch map layers mentioning warnings")
    for q in ("warnung", "gefahren", "sturm", "wind warning"):
        r = get(client, "https://api3.geo.admin.ch/rest/services/api/SearchServer", type="layers", searchText=q, lang="de")
        if r is not None and r.status_code == 200:
            for res in r.json().get("results", [])[:15]:
                a = res.get("attrs", {})
                print(f"  [{q}] {a.get('layer')} :: {a.get('label')}")

    head("MeteoSwiss website: product versions")
    for base in ("https://www.meteoschweiz.admin.ch", "https://www.meteoswiss.admin.ch"):
        r = get(client, base + "/product/output/versions.json")
        if r is not None and r.status_code == 200:
            try:
                v = r.json()
                print(f"  {base}: {len(v)} products")
                print("  all keys:", sorted(v))
                for k in v:
                    if any(s in k.lower() for s in ("warn", "lake", "see", "gefahr", "hazard")):
                        print(f"   {k}: {v[k]}")
                for key in [k for k in v if "warn" in k.lower()][:6]:
                    for path in (f"/product/output/{key}/version__{v[key]}/de/overview.json",
                                 f"/product/output/{key}/version__{v[key]}/de/",):
                        rr = get(client, base + path)
                        if rr is not None:
                            print(f"   GET {path}: HTTP {rr.status_code} {rr.text[:500]!r}")
            except ValueError:
                show(r, 300)
            break
        elif r is not None:
            print(f"  {base}: HTTP {r.status_code}")

    head("MeteoSwiss website: lake and airfield warning products")
    base = "https://www.meteoschweiz.admin.ch"
    r = get(client, base + "/product/output/versions.json")
    if r is not None and r.status_code == 200:
        v = r.json()
        for key in [k for k in v if any(s in k.lower() for s in ("lake", "airfield", "warn", "hazard", "gefahr", "see"))]:
            for path in (f"/product/output/{key}/version__{v[key]}/de/overview.json",
                         f"/product/output/{key}/version__{v[key]}/en/overview.json",
                         f"/product/output/{key}/version__{v[key]}/overview.json",
                         f"/product/output/{key}/version__{v[key]}/de/lakes.json",
                         f"/product/output/{key}/version__{v[key]}/de.json",
                         f"/product/output/{key}/version__{v[key]}/en.json"):
                rr = get(client, base + path)
                if rr is not None and rr.status_code == 200:
                    print(f"   GET {path}: {rr.text[:1500]!r}")

    head("MeteoSwiss app API (not open data, to see what exists)")
    for name, (lat, lon, plz) in CH_POINTS.items():
        r = get(client, "https://app-prod-ws.meteoswiss-app.ch/v1/plzDetail", plz=f"{plz}00")
        if r is None:
            continue
        print(f"\n plzDetail {name} ({plz}): HTTP {r.status_code}")
        if r.status_code == 200:
            try:
                d = r.json()
                print("  top keys:", list(d.keys()))
                for k in ("warnings", "warningsOverview"):
                    if k in d:
                        print(f"  {k}:", json.dumps(d[k], ensure_ascii=False)[:1200])
            except ValueError:
                show(r, 300)
    for path in ("/v1/warnings", "/v1/warningsOverview", "/v2/warnings", "/v1/lakeWarnings"):
        r = get(client, "https://app-prod-ws.meteoswiss-app.ch" + path)
        if r is not None:
            print(f"  {path}: HTTP {r.status_code} {r.text[:300]!r}")


def meteoalarm(client: httpx.Client) -> None:
    for country in ("austria", "switzerland"):
        head(f"MeteoAlarm feed: {country}")
        r = get(client, f"https://feeds.meteoalarm.org/api/v1/warnings/feeds-{country}")
        if r is None:
            continue
        if r.status_code != 200:
            show(r, 400)
            continue
        try:
            d = r.json()
        except ValueError:
            show(r, 600)
            continue
        ws = d.get("warnings", [])
        from datetime import datetime, timezone
        now = datetime.now(timezone.utc)
        def live(w):
            exp = [i.get("expires") for i in w.get("alert", {}).get("info", []) if i.get("expires")]
            return any(datetime.fromisoformat(e) > now for e in exp)
        print(f"  {len(ws)} warnings in feed, {sum(map(live, ws))} not yet expired")
        lakeish = set()
        for w in ws:
            for i in w.get("alert", {}).get("info", []):
                for a in i.get("area", []):
                    d_ = a.get("areaDesc") or ""
                    if any(k in d_.lower() for k in ("see", "lac", "lago", "lake", "leman")):
                        lakeish.add(d_)
                for ec in i.get("eventCode", []) or []:
                    events[("code", ec.get("valueName"), ec.get("value"))] = 0
        print("  lake-like area names:", sorted(lakeish))
        events = {}
        areas = set()
        for w in ws:
            info = (w.get("alert", {}).get("info") or [{}])
            for i in info:
                events[(i.get("language"), i.get("event"))] = events.get((i.get("language"), i.get("event")), 0) + 1
                for a in i.get("area", []):
                    areas.add(a.get("areaDesc"))
        print("  (language, event):", dict(list(events.items())[:30]))
        print("  sample areas:", sorted(a for a in areas if a)[:60])
        if ws:
            keys_tree(ws[0], maxdepth=4)
    r = get(client, "https://feeds.meteoalarm.org/feeds/meteoalarm-legacy-atom-switzerland")
    if r is not None:
        print("\n legacy atom switzerland:", r.status_code, r.text[:400].replace("\n", " "))


def dwd(client: httpx.Client) -> None:
    head("DWD lake warning areas vs AT/CH clubs")
    try:
        areas = dwd_warnings.fetch_lake_areas_sync(client) if hasattr(dwd_warnings, "fetch_lake_areas_sync") else None
    except Exception as e:  # noqa: BLE001
        areas = None
        print("  ", e)
    if areas is None:
        r = client.get(
            dwd_warnings.WFS_URL,
            params={"service": "WFS", "version": "2.0.0", "request": "GetFeature", "outputFormat": "application/json",
                    "typeName": "dwd:Warngebiete_Binnenseen", "srsName": "EPSG:4326", "propertyName": "WARNCELLID,NAME,SHAPE"},
            timeout=180,
        )
        areas = dwd_warnings.parse_lake_areas(r.json())
    print("  areas:", [(a.warncell_id, a.name) for a in areas])
    pts = {k: (v[0], v[1]) for k, v in {**AT_POINTS, **{k: v[:2] for k, v in CH_POINTS.items()}}.items()}
    for name, (lat, lon) in pts.items():
        a = dwd_warnings.lake_area_for(lon, lat, areas)
        print(f"  {name}: {None if a is None else (a.warncell_id, a.name)}")
    r = client.get(
        dwd_warnings.WFS_URL,
        params={"service": "WFS", "version": "2.0.0", "request": "GetFeature", "outputFormat": "application/json",
                "typeName": "dwd:Warnungen_Binnenseen"},
        timeout=60,
    )
    feats = r.json().get("features", [])
    print(f"  active lake warnings now: {len(feats)}", [(f['properties'].get('NAME'), f['properties'].get('EVENT')) for f in feats][:20])


def main() -> None:
    with httpx.Client(headers=UA, timeout=40, follow_redirects=True) as client:
        for step in (geosphere, meteoswiss, meteoalarm, dwd):
            try:
                step(client)
            except Exception as e:  # noqa: BLE001
                print(f"  {step.__name__} failed: {e!r}")


if __name__ == "__main__":
    main()
