"""Asks DWD's GeoServer the same questions the forecast run asks, a few times,
and prints status, time and size of each answer. Research only (warnings
"could not be loaded" for some clubs, 17 Nov 2026)."""
import time
import httpx

WFS = "https://maps.dwd.de/geoserver/dwd/ows"
BASE = {"service": "WFS", "version": "2.0.0", "request": "GetFeature", "outputFormat": "application/json"}
PROPS = "NAME,IDENTIFIER,WARNCELLID,STATUS,MSGTYPE,EVENT,SEVERITY,HEADLINE,EFFECTIVE,ONSET,EXPIRES"
POINTS = {"mrc-1880": (11.34745, 47.99667), "mrsv": (11.33901, 47.99156), "tutzing": (11.27525, 47.89578), "ammersee": (11.09902, 47.98155)}
QUERIES = {
    "lake-warnings": {"typeName": "dwd:Warnungen_Binnenseen", "propertyName": PROPS.replace("NAME", "AREADESC")},
    **{f"local-{k}": {"typeName": "dwd:Warnungen_Gemeinden", "propertyName": PROPS,
                      "CQL_FILTER": f"INTERSECTS(THE_GEOM,POINT({lat} {lon}))"} for k, (lon, lat) in POINTS.items()},
    "cell-mrc": {"typeName": "dwd:Warngebiete_Gemeinden", "propertyName": "WARNCELLID",
                 "CQL_FILTER": f"INTERSECTS(SHAPE,POINT({POINTS['mrc-1880'][1]} {POINTS['mrc-1880'][0]}))"},
}
with httpx.Client(timeout=60) as c:
    for round_ in range(4):
        for name, q in QUERIES.items():
            t = time.monotonic()
            try:
                r = c.get(WFS, params={**BASE, **q})
                body = r.text
                try:
                    n = len(r.json().get("features", []))
                except Exception:
                    n = f"not JSON: {body[:200]!r}"
                print(f"{round_} {name}: {r.status_code} {time.monotonic()-t:.1f}s {len(body)}B features={n}")
                if r.status_code == 200 and name.startswith("local") and isinstance(n, int):
                    for f in r.json()["features"]:
                        p = f["properties"]
                        print("     ", p.get("EVENT"), p.get("SEVERITY"), p.get("ONSET"), p.get("EXPIRES"))
            except Exception as e:
                print(f"{round_} {name}: ERROR {time.monotonic()-t:.1f}s {e!r}")
        time.sleep(20)
