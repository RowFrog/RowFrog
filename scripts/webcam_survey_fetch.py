"""Research only: download public webcam lists for the webcam survey.

Saves raw answers to research/webcams/raw/ so the analysis can run
anywhere. Nothing here is used by the app or the published forecasts.

Sources: foto-webcam.eu camera list, Panomax camera list, OpenStreetMap
webcams (Overpass), Windy Webcams API (only when WINDY_WEBCAMS_KEY is set),
addicted-sports.com webcam pages, and the clubs' own websites (front page
scanned for a webcam link).
"""

from __future__ import annotations

import concurrent.futures
import json
import os
import re
import sys
import time
from pathlib import Path
from urllib.parse import urljoin

import httpx

ROOT = Path(__file__).resolve().parent.parent
OUT = ROOT / "research" / "webcams" / "raw"
UA = "Mozilla/5.0 (compatible; RowFrogResearch/1.0; +https://rowfrog.com)"


def client() -> httpx.Client:
    return httpx.Client(headers={"User-Agent": UA}, timeout=30, follow_redirects=True)


def save(name: str, data) -> None:
    OUT.mkdir(parents=True, exist_ok=True)
    path = OUT / name
    if isinstance(data, (dict, list)):
        path.write_text(json.dumps(data, ensure_ascii=False, indent=1))
    else:
        path.write_text(data)
    print(f"saved {name} ({path.stat().st_size} bytes)")


def probe(c: httpx.Client, name: str, urls: list[str]) -> None:
    """Saves the first URL that answers with JSON; logs the rest."""
    log = []
    for url in urls:
        try:
            r = c.get(url)
            log.append({"url": url, "status": r.status_code, "type": r.headers.get("content-type"), "head": r.text[:400]})
            print(name, url, r.status_code, r.headers.get("content-type"), r.text[:200].replace("\n", " "))
            if r.status_code == 200:
                try:
                    save(f"{name}.json", r.json())
                    break
                except ValueError:
                    pass
        except httpx.HTTPError as e:
            log.append({"url": url, "error": str(e)})
            print(name, url, "error", e)
    save(f"{name}-probe.json", log)


OVERPASS = ["https://overpass-api.de/api/interpreter", "https://overpass.kumi.systems/api/interpreter",
            "https://maps.mail.ru/osm/tools/overpass/api/interpreter"]
# One query per country bounding box; whole-country area queries time out.
BOXES = {"de": (47.2, 5.8, 55.1, 15.1), "at": (46.3, 9.5, 49.1, 17.2), "ch": (45.8, 5.9, 47.9, 10.5)}
QUERY = """
[out:json][timeout:170];
(
 nwr["contact:webcam"]({s},{w},{n},{e});
 nwr["webcam"]({s},{w},{n},{e});
 nwr["surveillance:type"="webcam"]({s},{w},{n},{e});
 nwr["surveillance"="webcam"]({s},{w},{n},{e});
);
out center tags;
"""


def osm(c: httpx.Client) -> None:
    elements = {}
    for cc, (s, w, n, e) in BOXES.items():
        for url in OVERPASS:
            try:
                r = c.post(url, data={"data": QUERY.format(s=s, w=w, n=n, e=e)}, timeout=200,
                           headers={"User-Agent": "RowFrog/0.1"})
                print("overpass", cc, url, r.status_code, len(r.content), r.text[:150].replace("\n", " "))
                if r.status_code == 200:
                    for el in r.json().get("elements", []):
                        elements[f"{el['type']}/{el['id']}"] = el
                    break
            except (httpx.HTTPError, ValueError) as ex:
                print("overpass", cc, url, "error", ex)
            time.sleep(5)
    save("osm.json", list(elements.values()))


def windy(c: httpx.Client) -> None:
    key = os.environ.get("WINDY_WEBCAMS_KEY")
    if not key:
        print("windy: no WINDY_WEBCAMS_KEY, skipped")
        return
    cams = {}
    # Tiles of 0.5 x 0.5 degrees over the clubs' area keep each answer under the free offset cap.
    lat = 45.7
    while lat < 55.1:
        lon = 5.8
        while lon < 17.3:
            offset = 0
            while offset < 1000:
                r = c.get("https://api.windy.com/webcams/api/v3/webcams", headers={"x-windy-api-key": key},
                          params={"bbox": f"{lat + .5},{lon + .5},{lat},{lon}", "limit": 50, "offset": offset,
                                  "include": "location,categories,urls,player,images"})
                if r.status_code != 200:
                    print("windy", lat, lon, r.status_code, r.text[:300])
                    if r.status_code in (401, 403):
                        save("windy-error.json", {"status": r.status_code, "body": r.text[:2000]})
                        return
                    break
                if not cams and offset == 0:
                    print("windy first answer", r.text[:600])
                batch = r.json().get("webcams", [])
                for w in batch:
                    cams[w["webcamId"]] = w
                if len(batch) < 50:
                    break
                offset += 50
                time.sleep(0.2)
            lon += .5
        lat += .5
    save("windy.json", list(cams.values()))


def addicted(c: httpx.Client) -> None:
    pages = {}
    for url in ["https://www.addicted-sports.com/webcam/", "https://www.addicted-sports.com/sitemap.xml",
                "https://www.addicted-sports.com/sitemap_index.xml"]:
        try:
            r = c.get(url)
            print("addicted", url, r.status_code, len(r.text))
            pages[url] = {"status": r.status_code, "links": sorted(set(re.findall(r"https?://www\.addicted-sports\.com/webcam/[^\"'<> ]+|/webcam/[a-z0-9\-]+/[a-z0-9\-]+/?", r.text))),
                          "coords": re.findall(r"(?:lat|latitude)[\"']?\s*[:=]\s*[\"']?(-?\d+\.\d+)[\"']?\s*,\s*[\"']?(?:lng|lon|longitude)[\"']?\s*[:=]\s*[\"']?(-?\d+\.\d+)", r.text)[:2000]}
        except httpx.HTTPError as e:
            pages[url] = {"error": str(e)}
    save("addicted-sports.json", pages)
    spots = {}
    links = sorted({l for v in pages.values() for l in v.get("links", []) if not l.rstrip("/").endswith("current")})
    for link in links:
        url = urljoin("https://www.addicted-sports.com", link)
        try:
            r = c.get(url)
            text = r.text
            spots[link] = {
                "status": r.status_code,
                "title": (re.search(r"<title>(.*?)</title>", text, re.S) or [None, ""])[1].strip(),
                "coords": re.findall(r"(-?\d{1,2}\.\d{3,})\s*,\s*(-?\d{1,3}\.\d{3,})", text)[:20],
                "geo": re.findall(r"(?:lat|latitude)[\"']?\s*[:=]\s*[\"']?(-?\d+\.\d+)[^0-9\-]{1,40}?(?:lng|lon|longitude)[\"']?\s*[:=]\s*[\"']?(-?\d+\.\d+)", text)[:5],
                "meta": re.findall(r"<meta[^>]+(?:geo\.position|ICBM|place:location)[^>]+>", text)[:5],
            }
        except httpx.HTTPError as e:
            spots[link] = {"error": str(e)}
        time.sleep(1)
    save("addicted-sports-spots.json", spots)


def clubs() -> list[dict]:
    out = []
    files = [ROOT / "data" / "locations.json", *sorted((ROOT / "data" / "catalogs").glob("*.json"))]
    for f in files:
        for club in json.loads(f.read_text()).get("clubs", []):
            if club.get("website"):
                out.append({"id": club["id"], "website": club["website"]})
    return out


LINK = re.compile(r"<a\b[^>]*href=[\"']([^\"']+)[\"'][^>]*>(.*?)</a>", re.I | re.S)


def scan(club: dict) -> dict:
    result = {"id": club["id"], "website": club["website"]}
    try:
        with client() as c:
            r = c.get(club["website"], timeout=15)
        result["status"] = r.status_code
        text = r.text
        links = []
        for href, label in LINK.findall(text):
            plain = re.sub(r"<[^>]+>", " ", label)
            if re.search(r"web-?cam|live-?cam|seecam|panorama-?cam", href + " " + plain, re.I):
                links.append({"href": urljoin(str(r.url), href), "label": " ".join(plain.split())[:80]})
        text = re.sub(r"data:image/[^\"']+", "data:", text)
        imgs = re.findall(r"<img\b[^>]*src=[\"']([^\"']*(?:webcam|livecam|cam\d|current\.jpe?g)[^\"']*)[\"']", text, re.I)
        frames = re.findall(r"<iframe\b[^>]*src=[\"']([^\"']+)[\"']", text, re.I)
        result["webcamLinks"] = links[:10]
        result["webcamImages"] = [urljoin(str(r.url), i) for i in imgs][:10]
        result["camFrames"] = [f for f in frames if re.search(r"cam|panomax|roundshot|foto-webcam|windy|feratel", f, re.I)][:10]
        result["mentionsWebcam"] = bool(re.search(r"web-?cam", text, re.I))
    except Exception as e:  # noqa: BLE001 - research scan, any failure is just recorded
        result["error"] = f"{type(e).__name__}: {e}"[:200]
    return result


def club_sites() -> None:
    todo = clubs()
    with concurrent.futures.ThreadPoolExecutor(8) as pool:
        results = list(pool.map(scan, todo))
    print("club sites scanned", len(results), "with webcam hints",
          sum(1 for r in results if r.get("webcamLinks") or r.get("webcamImages") or r.get("camFrames")))
    save("club-sites.json", results)


def main() -> None:
    steps = sys.argv[1:] or ["foto", "panomax", "osm", "windy", "addicted", "clubs"]
    with client() as c:
        if "foto" in steps:
            probe(c, "foto-webcam", ["https://www.foto-webcam.eu/webcam/include/metadata.php",
                                     "https://www.foto-webcam.eu/webcam/include/list.php",
                                     "https://www.foto-webcam.eu/webcam/include/camlist.php"])
        if "panomax" in steps:
            probe(c, "panomax", ["https://api.panomax.com/1.0/maps/panomaxweb",
                                 "https://api.panomax.com/1.0/instances/lists/public",
                                 "https://api.panomax.com/1.0/cams",
                                 "https://api.panomax.com/1.0/instances"])
        if "osm" in steps:
            osm(c)
        if "windy" in steps:
            windy(c)
        if "addicted" in steps:
            addicted(c)
    if "clubs" in steps:
        club_sites()


if __name__ == "__main__":
    main()
