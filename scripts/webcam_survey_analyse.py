"""Research only: match the webcams from webcam_survey_fetch.py to the club waters.

Writes CSV lists and summary.json to research/webcams/out/.

A webcam counts for a lake when it stands within AT_LAKE_M of the lake
outline ("at the lake"), or, when the provider gives a view direction, when
it stands up to VIEW_KM away and the lake lies inside its field of view
("lake in view"). For rivers and other waters without an outline, a webcam
counts when it is within AT_RIVER_M of a club's launch point on that water.
"""

from __future__ import annotations

import csv
import json
import math
import re
from pathlib import Path

from shapely.geometry import Point, Polygon, shape
from shapely.ops import transform  # noqa: F401 - kept simple for a one-off script

ROOT = Path(__file__).resolve().parent.parent
RAW = ROOT / "research" / "webcams" / "raw"
OUT = ROOT / "research" / "webcams" / "out"
AT_LAKE_M = 1000
AT_RIVER_M = 1500
VIEW_KM = 6
NEAR_KM = 5
# Lakes south of Munich (owner's priority region): rough box from Ammersee to Chiemsee.
SOUTH_MUNICH = (47.45, 10.75, 48.15, 12.65)

# Club websites with a webcam of their own or a link to one, checked by hand
# from club-sites.json. "own" = camera at the club; "linked" = the club page
# links to someone else's camera nearby.
CLUB_CAMS = {
    "mrsv-bayern": ("own", "https://mrsv.bayern/", "MRSV webcam, Starnberg"),
    "muenchener-ruder-und-segelverein-bayern-von-1910": ("own", "https://mrsv.bayern/", "MRSV webcam, Starnberg"),
    "gmundner-ruderverein": ("own", "http://webcam.gmundner-ruderverein.at/", "Webcam Ruderverein Gmunden"),
    "ruder-club-wolfgangsee": ("linked", "http://www.uyc-wolfgangsee.at/webcam/webcam1.php", "UYC Wolfgangsee webcam"),
    "ruderclub-wels": ("own", "https://ruderclub-wels.at/livecam-traun-wels/", "Livecam Traun Wels"),
    "ruderverein-wiking-bregenz": ("linked", "https://www.rv-wiking.at/wind_wetter_sicher/aktuellewerte", "Webcams on the club's weather page"),
    "wiener-ruder-club-pirat": ("own", "https://wrc-pirat.at/zusatzangebot/webcam-alte-donau/", "Webcam Alte Donau"),
    "nordiska-roddfoereningen-i-zuerich": ("linked", "https://rcz.ch/webcam", "RC Zürich webcam"),
    "nordiska-roddfoereningen-zuerich": ("linked", "https://rcz.ch/webcam", "RC Zürich webcam"),
    "ruderklub-kaufleuten": ("linked", "https://www.rcz.ch/webcam", "RC Zürich webcam"),
    "ruderclub-kaufleuten-zuerich": ("linked", "https://www.rcz.ch/webcam", "RC Zürich webcam"),
    "ruderclub-zuerich": ("own", "https://www.rcz.ch/webcam", "RCZ webcam"),
    "see-club-zug": ("own", "https://www.scz.ch/", "Seeclub Zug webcam"),
    "seeclub-zug": ("own", "https://www.scz.ch/", "Seeclub Zug webcam"),
    "societa-canottieri-ceresio": ("own", "https://www.scceresio.ch/webcam/", "SC Ceresio webcam"),
    "club-aviron-valais-leman": ("linked", "https://www.port-valais.ch/fr/webcam-2006.html", "Port-Valais webcam Bouveret"),
    "club-canottieri-lugano": ("own", "https://www.clubcanottierilugano.com/webcam-ccl", "CC Lugano webcam"),
    "damen-ruderclub-zuerich": ("linked", "https://www.drz-rudern.ch/live-cam", "Live cams page"),
    "rowing-club-lausanne": ("linked", "https://www.rclausanne.com/webcam-2/", "Webcam du lac (windspots.org)"),
    "ruderclub-erlenbach": ("own", "https://www.rudercluberlenbach.ch/webcam-wetter", "RC Erlenbach webcam"),
    "ruderclub-greifensee": ("linked", "http://www.greifenseewetter.ch/", "greifenseewetter.ch"),
    "ruderclub-sarnen": ("linked", "https://www.swisswebcams.ch/webcam/zoom/1384854763-Sarnersee-%280-Sachseln%29_Wetter", "Swisswebcams Sarnersee"),
    "ruderclub-uster": ("own", "https://www.rcuster.ch/rudern/wetter_und_webcam", "RC Uster webcam"),
    "ruderclub-aegeri": ("own", "https://www.rc-aegeri.ch/ruderbetrieb", "RC Ägeri webcam"),
    "seeclub-biel": ("linked", "https://bielersee.live/", "bielersee.live"),
    "societe-nautique-etoile-bienne": ("own", "https://www.sneb.ch/webcam/", "SNEB webcam"),
    "seeclub-sursee": ("own", "https://seeclub-sursee.ch/wetter-webcam/", "Seeclub Sursee webcam"),
    "crefelder-ruder-club-1883": ("own", "https://crc1883.de/e-see-livecam/", "E-See livecam"),
    "der-hamburger-und-germania-ruder-club": ("own", "https://www.mplg.info/dhugrc/webcam2/current.jpg", "DHuGRC webcam"),
    "essen-werdener-ruder-club-von-1896": ("own", "https://www.ewrc.de/webcam", "EWRC webcam"),
    "karlsruher-rheinklub-alemannia": ("own", "https://www.rheinklub-alemannia.de/webcam-im-karlsruher-hafen/", "Webcam Karlsruher Hafen"),
    "mindener-ruder-verein-von-1905": ("own", "https://www.mrv1905.de/", "Webcam from the balcony (members area)"),
    "passauer-ruderverein-von-1874": ("own", "https://passauer-ruderverein.de/webcam", "Passauer RV webcam"),
    "ratzeburger-ruderclub": ("own", "https://webcam.rrc-online.de:1984/stream.html?src=webcam", "RRC webcam"),
    "ruder-club-rastatt-1898": ("own", "https://ruder-club-rastatt.de/webcam/", "RC Rastatt webcam"),
    "rudergesellschaft-wiesbaden-biebrich-1888": ("own", "https://rgwb.de/infos/infos-wasserwetter/webcam-biebrich.php", "Webcam Biebrich"),
    "ruderklub-am-baldeneysee": ("own", "https://www.ruderklub-am-baldeneysee.de/de/verein/webcam/", "RaB webcam"),
    "ruderriege-etuf-essen": ("linked", "https://etuf-segeln.de/files/webcam-see/etuf-see.jpg", "ETUF sailing webcam"),
    "ruderverein-friedrichshafen": ("own", "https://webcam.rvfn.de", "RV Friedrichshafen webcam"),
    "ueberlinger-ruderclub-bodan": ("own", "https://ueberlinger-ruderclub.de/webcams.html", "Überlinger RC webcams"),
    "regattastrecke-oberschleissheim": ("own", "https://www.leistungszentrum-muenchen.de/die-anlage/webcam/", "Regattastrecke webcam"),
}


# Hosts of OpenStreetMap webcam links: road cameras are left out, a few
# networks get their own name so the licence review can group them.
TRAFFIC_HOSTS = ("asfinag", "tirol.gv.at", "verkehrsauskunft", "verkehrsinfo", "ras.bz.it", "land-oberoesterreich",
                 "autobahn", "strassen", "traffic", "verkehr", "inforoute", "svz-bw", "bayerninfo",
                 "pioupiou", "balisemeteo")
OSM_HOSTS = {"foto-webcam": "foto-webcam.eu", "feratel": "feratel (via OpenStreetMap)",
             "roundshot": "Roundshot (via OpenStreetMap)", "bergfex": "bergfex (via OpenStreetMap)",
             "windy": "Windy (via OpenStreetMap)", "panomax": "Panomax", "youtube": "YouTube stream (via OpenStreetMap)",
             "webcam-hd": "webcam-hd.com (via OpenStreetMap)",
             "terra-hd": "terra-hd.de (via OpenStreetMap)", "addicted-sports": "addicted-sports.com"}

# addicted-sports.com spots on the club waters. The site gives no coordinates,
# so the places are approximate (town shore, about 500 m).
ADDICTED = {
    "ammersee/herrsching": ("ammersee", 47.9985, 11.1720, "Ammersee Herrsching"),
    "starnbergersee/ammerland": ("starnberger-see", 47.8985, 11.3335, "Starnberger See Ammerland"),
    "brombachsee/allmannsdorf": ("grosser-brombachsee", 49.1235, 10.9405, "Brombachsee Allmannsdorf"),
    "wolfgangsee/lindenstrand": ("wolfgangsee", 47.7640, 13.3700, "Wolfgangsee Lindenstrand"),
}


def metres(lat0: float):
    k = 111_320 * math.cos(math.radians(lat0))
    return lambda x, y, z=None: (x * k, y * 110_540)


def dist_m(a: tuple[float, float], b: tuple[float, float]) -> float:
    lat1, lon1, lat2, lon2 = map(math.radians, (*a, *b))
    h = math.sin((lat2 - lat1) / 2) ** 2 + math.cos(lat1) * math.cos(lat2) * math.sin((lon2 - lon1) / 2) ** 2
    return 12_742_000 * math.asin(math.sqrt(h))


def bearing(a, b) -> float:
    lat1, lon1, lat2, lon2 = map(math.radians, (*a, *b))
    y = math.sin(lon2 - lon1) * math.cos(lat2)
    x = math.cos(lat1) * math.sin(lat2) - math.sin(lat1) * math.cos(lat2) * math.cos(lon2 - lon1)
    return math.degrees(math.atan2(y, x)) % 360


ALL_CLUBS: dict[str, dict] = {}  # before the 300 m merge, for the club-website cameras


def load_waters():
    lakes, clubs, seen = {}, [], []
    files = [ROOT / "data" / "locations.json", *sorted((ROOT / "data" / "catalogs").glob("*.json"))]
    for f in files:
        data = json.loads(f.read_text())
        for lake in data.get("lakes", []):
            lakes.setdefault(lake["id"], lake)
        earlier = list(seen)
        for club in data.get("clubs", []):
            lp = club.get("launchPoint")
            if not lp:
                continue
            p = (lp["lat"], lp["lon"])
            club["_p"] = p
            ALL_CLUBS[club["id"]] = club
            if any(dist_m(p, q) < 300 for q in earlier):
                continue
            club["_p"] = p
            club["_file"] = f.stem
            clubs.append(club)
            seen.append(p)
    for lake in lakes.values():
        countries = sorted({c.get("country", "") for c in clubs if c.get("lakeId") == lake["id"]})
        if len(countries) > 1:
            lake["country"] = "/".join(countries)
        path = ROOT / "data" / "outlines" / f"{lake['id']}.geojson"
        lake["_kind"] = lake.get("kind", "lake")
        if path.exists():
            gj = json.loads(path.read_text())
            geom = shape(gj["features"][0]["geometry"] if gj.get("type") == "FeatureCollection" else gj.get("geometry", gj))
            lake["_geom"] = geom
            lake["_m"] = metres(lake["center"]["lat"])
            lake["_gm"] = transform(lake["_m"], geom)
    return lakes, clubs


def num(v):
    try:
        return float(v)
    except (TypeError, ValueError):
        return None


def fov_from_focal(f_mm: float | None) -> float:
    if not f_mm:
        return 60
    return math.degrees(2 * math.atan(36 / (2 * f_mm)))


def load_cams(clubs_by_id):
    cams = []
    for c in json.loads((RAW / "foto-webcam.json").read_text())["cams"]:
        if c.get("hidden"):
            continue
        # Partner cameras (terra-hd.com, foto-webcam.net, ...) are only listed on foto-webcam.eu and keep their own terms.
        cams.append({"provider": "foto-webcam.eu partner" if c.get("partner") else "foto-webcam.eu", "id": c["id"], "name": c.get("title") or c["name"],
                     "lat": num(c["latitude"]), "lon": num(c["longitude"]), "url": c["link"], "image": c.get("imgurl", ""),
                     "online": not c.get("offline"), "dir": num(c.get("direction")), "fov": fov_from_focal(num(c.get("focalLen"))),
                     "interval_min": round((num(c.get("captureInterval")) or 600) / 60)})
    for i in json.loads((RAW / "panomax.json").read_text())["instances"].values():
        cam = i["cam"]
        va = cam.get("viewAngle") or 360
        zero = cam.get("zeroDirection")
        cams.append({"provider": "Panomax", "id": str(i["id"]), "name": i["name"], "lat": cam["latitude"],
                     "lon": cam["longitude"], "url": f"https://www.panomax.com/ (instance {i['id']})", "image": "",
                     "online": True, "dir": None if va >= 360 or zero is None else (zero + va / 2) % 360,
                     "fov": va, "interval_min": 10})
    windy = RAW / "windy.json"
    if windy.exists():
        known = [(c["lat"], c["lon"]) for c in cams]
        for w in json.loads(windy.read_text()):
            loc = w.get("location", {})
            lat, lon = loc.get("latitude"), loc.get("longitude")
            if lat is None or w.get("status") != "active":
                continue
            # Windy also lists many foto-webcam.eu and Panomax cameras: keep those under their own provider.
            if any(abs(lat - a) < 0.001 and abs(lon - b) < 0.0015 and dist_m((lat, lon), (a, b)) < 75 for a, b in known):
                continue
            cams.append({"provider": "Windy", "id": str(w["webcamId"]), "name": w.get("title", "Webcam"), "lat": lat,
                         "lon": lon, "url": f"https://www.windy.com/webcams/{w['webcamId']}", "image": "",
                         "online": True, "dir": None, "fov": None, "interval_min": None,
                         "lake": any(c.get("id") == "lake" for c in w.get("categories", []))})
    osm = RAW / "osm.json"
    if osm.exists():
        for el in json.loads(osm.read_text()):
            t = el.get("tags", {})
            lat = el.get("lat") or el.get("center", {}).get("lat")
            lon = el.get("lon") or el.get("center", {}).get("lon")
            url = t.get("contact:webcam") or t.get("webcam") or t.get("url") or t.get("website") or ""
            if lat is None:
                continue
            d = t.get("camera:direction") or t.get("direction")
            try:
                d = float(d)
            except (TypeError, ValueError):
                d = None
            host = re.sub(r"^https?://(www\.)?", "", url).split("/")[0].lower()
            if any(t in host for t in TRAFFIC_HOSTS):
                continue
            label = next((name for key, name in OSM_HOSTS.items() if key in host), "Single operators (via OpenStreetMap)")
            cams.append({"provider": label, "id": f"{el['type']}/{el['id']}", "name": t.get("name") or t.get("operator") or "Webcam",
                         "lat": lat, "lon": lon, "url": url, "image": "", "online": None, "dir": d, "fov": 90 if d is not None else None,
                         "interval_min": None})
    for slug, (lake_id, lat, lon, name) in ADDICTED.items():
        cams.append({"provider": "addicted-sports.com", "id": slug, "name": name, "lat": lat, "lon": lon,
                     "url": f"https://www.addicted-sports.com/webcam/{slug}/", "image": "", "online": None,
                     "dir": None, "fov": None, "interval_min": 10, "approx": True})
    for cid, (kind, url, name) in CLUB_CAMS.items():
        club = clubs_by_id.get(cid) or ALL_CLUBS.get(cid)
        if not club or any(c["url"] == url for c in cams):
            continue
        cams.append({"provider": "Club website" if kind == "own" else "Linked on club website", "id": cid, "name": name,
                     "lat": club["_p"][0], "lon": club["_p"][1], "url": url, "image": "", "online": None, "dir": None,
                     "fov": None, "interval_min": None, "approx": True})
    # The same camera can be listed by OSM and a provider: drop OSM points within 50 m of another camera.
    keep = []
    for cam in cams:
        if cam["id"].startswith(("node/", "way/", "relation/")) and any(not o["id"].startswith(("node/", "way/", "relation/")) and dist_m((cam["lat"], cam["lon"]), (o["lat"], o["lon"])) < 50 for o in cams):
            continue
        keep.append(cam)
    return keep


def in_view(cam, lake) -> bool:
    if cam["dir"] is None and (cam["fov"] or 0) < 360:
        return False
    gm = lake["_gm"]
    m = lake["_m"]
    cx, cy = m(cam["lon"], cam["lat"])
    r = VIEW_KM * 1000
    if (cam["fov"] or 0) >= 360:
        return gm.distance(Point(cx, cy)) <= r
    half = cam["fov"] / 2
    pts = [(cx, cy)]
    for k in range(13):
        a = math.radians(cam["dir"] - half + cam["fov"] * k / 12)
        pts.append((cx + r * math.sin(a), cy + r * math.cos(a)))
    return Polygon(pts).intersects(gm)


def main() -> None:
    OUT.mkdir(parents=True, exist_ok=True)
    lakes, clubs = load_waters()
    clubs_by_id = {c["id"]: c for c in clubs}
    cams = load_cams(clubs_by_id)
    waters_with_clubs = {c.get("lakeId") for c in clubs}
    per_lake = {lid: [] for lid in lakes if lid in waters_with_clubs}

    for lid in per_lake:
        lake = lakes[lid]
        lake_clubs = [c for c in clubs if c.get("lakeId") == lid]
        for cam in cams:
            p = (cam["lat"], cam["lon"])
            if "_gm" in lake:
                if dist_m(p, (lake["center"]["lat"], lake["center"]["lon"])) > 80_000:
                    continue
                d_shore = lake["_gm"].distance(Point(*lake["_m"](cam["lon"], cam["lat"])))
                if d_shore <= AT_LAKE_M:
                    how = "at the lake"
                elif d_shore <= VIEW_KM * 1000 and in_view(cam, lake):
                    how = "lake in view"
                else:
                    continue
            else:
                d_shore = min(dist_m(p, c["_p"]) for c in lake_clubs)
                if d_shore > AT_RIVER_M:
                    continue
                how = "near a club on this water"
            nearest = min(lake_clubs, key=lambda c: dist_m(p, c["_p"]))
            per_lake[lid].append({**cam, "how": how, "shore_m": round(d_shore),
                                  "nearest_club": nearest.get("shortName") or nearest["name"],
                                  "nearest_club_m": round(dist_m(p, nearest["_p"]))})

    def region(lake):
        la, lo = lake["center"]["lat"], lake["center"]["lon"]
        s, w, n, e = SOUTH_MUNICH
        if lake.get("country") == "de" and s <= la <= n and w <= lo <= e:
            return "Lakes south of Munich"
        return {"de": "Germany", "at": "Austria", "ch": "Switzerland"}.get(lake.get("country"), "Border lakes")

    lake_rows = []
    for lid, found in per_lake.items():
        lake = lakes[lid]
        at = [f for f in found if f["how"] != "lake in view"]
        view = [f for f in found if f["how"] == "lake in view"]
        lake_rows.append({"lake_id": lid, "lake": lake["name"], "kind": lake["_kind"], "country": lake.get("country", ""),
                          "region": region(lake), "clubs": sum(1 for c in clubs if c.get("lakeId") == lid),
                          "webcams_at_water": len(at), "webcams_lake_in_view": len(view), "webcams_total": len(found),
                          "providers": ", ".join(sorted({f["provider"] for f in found}))})
    lake_rows.sort(key=lambda r: (r["region"] != "Lakes south of Munich", r["country"], -r["webcams_total"], r["lake"]))

    with open(OUT / "webcams-per-lake.csv", "w", newline="") as fh:
        w = csv.writer(fh)
        w.writerow(["lake_id", "lake", "kind", "country", "region", "provider", "webcam", "how", "distance_to_shore_m",
                    "nearest_club", "distance_to_nearest_club_m", "latitude", "longitude", "view_direction_deg",
                    "field_of_view_deg", "update_every_min", "online", "page"])
        for row in lake_rows:
            for f in sorted(per_lake[row["lake_id"]], key=lambda f: (f["how"] == "lake in view", f["nearest_club_m"])):
                w.writerow([row["lake_id"], row["lake"], row["kind"], row["country"], row["region"], f["provider"], f["name"],
                            f["how"], f["shore_m"], f["nearest_club"], f["nearest_club_m"], f["lat"], f["lon"],
                            "" if f["dir"] is None else round(f["dir"]), "" if f["fov"] is None else round(f["fov"]),
                            f["interval_min"] or "", "" if f["online"] is None else ("yes" if f["online"] else "no"), f["url"]])
    with open(OUT / "lakes-summary.csv", "w", newline="") as fh:
        w = csv.DictWriter(fh, fieldnames=list(lake_rows[0]))
        w.writeheader()
        w.writerows(lake_rows)

    club_rows = []
    for c in clubs:
        p = c["_p"]
        ranked = sorted(cams, key=lambda cam: dist_m(p, (cam["lat"], cam["lon"])))
        near = [cam for cam in ranked if dist_m(p, (cam["lat"], cam["lon"])) <= NEAR_KM * 1000]
        lake_cams = sorted(per_lake.get(c.get("lakeId"), []), key=lambda f: dist_m(p, (f["lat"], f["lon"])))
        best = ranked[0]
        lk = lake_cams[0] if lake_cams else None
        lake = lakes.get(c.get("lakeId"), {})
        club_rows.append({
            "club_id": c["id"], "club": c.get("shortName") or c["name"], "country": c.get("country", ""),
            "water": lake.get("name", ""), "kind": lake.get("_kind", ""), "region": region(lake) if lake else "",
            "nearest_webcam": best["name"], "nearest_provider": best["provider"],
            "nearest_distance_km": round(dist_m(p, (best["lat"], best["lon"])) / 1000, 2),
            "nearest_direction": compass(bearing(p, (best["lat"], best["lon"]))),
            "nearest_page": best["url"],
            "webcams_within_5km": len(near),
            "nearest_webcam_for_this_water": lk["name"] if lk else "",
            "provider_for_this_water": lk["provider"] if lk else "",
            "distance_km_for_this_water": round(dist_m(p, (lk["lat"], lk["lon"])) / 1000, 2) if lk else "",
            "how": lk["how"] if lk else "",
        })
    club_rows.sort(key=lambda r: (r["region"] != "Lakes south of Munich", r["country"], r["water"], r["club"]))
    with open(OUT / "nearest-webcam-per-club.csv", "w", newline="") as fh:
        w = csv.DictWriter(fh, fieldnames=list(club_rows[0]))
        w.writeheader()
        w.writerows(club_rows)

    with open(OUT / "all-webcams.csv", "w", newline="") as fh:
        w = csv.writer(fh)
        w.writerow(["provider", "id", "webcam", "latitude", "longitude", "view_direction_deg", "field_of_view_deg", "online", "page", "image"])
        for cam in cams:
            w.writerow([cam["provider"], cam["id"], cam["name"], cam["lat"], cam["lon"],
                        "" if cam["dir"] is None else round(cam["dir"]), "" if cam["fov"] is None else round(cam["fov"]),
                        "" if cam["online"] is None else cam["online"], cam["url"], cam["image"]])

    def counts(rows):
        return {"waters": len(rows), "none": sum(r["webcams_total"] == 0 for r in rows),
                "one": sum(r["webcams_total"] == 1 for r in rows), "several": sum(r["webcams_total"] > 1 for r in rows),
                "at_water_none": sum(r["webcams_at_water"] == 0 for r in rows),
                "at_water_one": sum(r["webcams_at_water"] == 1 for r in rows),
                "at_water_several": sum(r["webcams_at_water"] > 1 for r in rows)}

    summary = {
        "cams_by_provider": {p: sum(c["provider"] == p for c in cams) for p in sorted({c["provider"] for c in cams})},
        "clubs": len(clubs),
        "lakes": counts([r for r in lake_rows if r["kind"] == "lake"]),
        "lakes_south_of_munich": counts([r for r in lake_rows if r["region"] == "Lakes south of Munich"]),
        "rivers": counts([r for r in lake_rows if r["kind"] == "river"]),
        "other_waters": counts([r for r in lake_rows if r["kind"] not in ("lake", "river")]),
        "clubs_with_cam_within_1km": sum(r["nearest_distance_km"] <= 1 for r in club_rows),
        "clubs_with_cam_within_5km": sum(r["nearest_distance_km"] <= 5 for r in club_rows),
        "clubs_with_cam_for_their_water": sum(bool(r["nearest_webcam_for_this_water"]) for r in club_rows),
        "lake_rows": lake_rows,
    }
    (OUT / "summary.json").write_text(json.dumps(summary, ensure_ascii=False, indent=1))
    print(json.dumps({k: v for k, v in summary.items() if k != "lake_rows"}, indent=1, ensure_ascii=False))


def compass(deg: float) -> str:
    return ["N", "NE", "E", "SE", "S", "SW", "W", "NW"][round(deg / 45) % 8]


if __name__ == "__main__":
    main()
