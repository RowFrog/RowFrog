"""Official DWD warnings: lake warnings and weather warnings for the place.

DWD runs a warning service for 23 inland lakes (Binnenseen), among them
Starnberger See, Ammersee, Chiemsee and Bodensee: strong-wind and storm
warnings shown by the flashing lights on the shore. Every other water (rivers,
canals, smaller lakes) is covered by DWD's ordinary weather warnings for the
municipality, which also apply on the lakes.

Both come from DWD's GeoServer as WFS layers:

- dwd:Warngebiete_Binnenseen: the lake warning areas (polygons, static),
- dwd:Warnungen_Binnenseen: active lake warnings, by WARNCELLID,
- dwd:Warnungen_Gemeinden: active weather warnings per municipality.

Warnings are CAP messages: EVENT (e.g. "STURMBÖEN"), SEVERITY (Minor,
Moderate, Severe, Extreme), HEADLINE, DESCRIPTION, INSTRUCTION, ONSET and
EXPIRES. Coordinate order in the answers depends on the requested CRS, so
geometry is normalised by value: in Germany latitude is 47-55 and longitude
6-15, so the order can be told apart safely.

Data: Deutscher Wetterdienst, CC BY 4.0 (credit "Deutscher Wetterdienst").
"""

from __future__ import annotations

import math
from dataclasses import dataclass
from datetime import datetime
from typing import Iterable

import httpx

WFS_URL = "https://maps.dwd.de/geoserver/dwd/ows"
# A launch point on the shore can sit just outside DWD's lake polygon.
LAKE_AREA_TOLERANCE_M = 1000.0
EARTH_RADIUS_M = 6_371_000.0

SEVERITIES = ["Minor", "Moderate", "Severe", "Extreme"]


@dataclass(frozen=True)
class LakeArea:
    warncell_id: int
    name: str
    rings: list[list[tuple[float, float]]]  # (lon, lat)


@dataclass(frozen=True)
class Warning:
    kind: str  # "lake" or "local"
    area: str
    event: str
    severity: str
    headline: str
    description: str
    instruction: str | None
    onset: datetime | None
    expires: datetime | None

    @property
    def level(self) -> int:
        """0 (Minor) to 3 (Extreme)."""
        return SEVERITIES.index(self.severity) if self.severity in SEVERITIES else 0

    def active_during(self, start: datetime, end: datetime) -> bool:
        return (self.onset is None or self.onset < end) and (self.expires is None or start < self.expires)


def _query(**params: str) -> dict[str, str]:
    q = {"service": "WFS", "version": "2.0.0", "request": "GetFeature", "outputFormat": "application/json"}
    q.update(params)
    return q


def _lonlat(pair: Iterable[float]) -> tuple[float, float]:
    a, b = list(pair)[:2]
    return (float(b), float(a)) if a > 30 else (float(a), float(b))


def _rings(geometry: dict | None) -> list[list[tuple[float, float]]]:
    if not geometry:
        return []
    if geometry["type"] == "Polygon":
        polygons = [geometry["coordinates"]]
    elif geometry["type"] == "MultiPolygon":
        polygons = geometry["coordinates"]
    else:
        return []
    return [[_lonlat(p) for p in ring] for polygon in polygons for ring in polygon]


def _time(value: str | None) -> datetime | None:
    if not value:
        return None
    return datetime.fromisoformat(value.replace("Z", "+00:00"))


def parse_lake_areas(geojson: dict) -> list[LakeArea]:
    return [
        LakeArea(int(f["properties"]["WARNCELLID"]), f["properties"]["NAME"], _rings(f.get("geometry")))
        for f in geojson.get("features", [])
    ]


def parse_warnings(geojson: dict, kind: str) -> list[tuple[int, Warning]]:
    """(WARNCELLID, warning) pairs. Only actual messages; tests and updates' cancels are dropped."""
    out = []
    for f in geojson.get("features", []):
        p = f["properties"]
        if p.get("STATUS", "Actual") != "Actual" or p.get("MSGTYPE") == "Cancel":
            continue
        out.append(
            (
                int(p.get("WARNCELLID") or 0),
                Warning(
                    kind=kind,
                    area=p.get("NAME") or p.get("AREADESC") or "",
                    event=p.get("EVENT") or "",
                    severity=p.get("SEVERITY") or "Minor",
                    headline=p.get("HEADLINE") or "",
                    description=p.get("DESCRIPTION") or "",
                    instruction=p.get("INSTRUCTION") or None,
                    onset=_time(p.get("ONSET") or p.get("EFFECTIVE")),
                    expires=_time(p.get("EXPIRES")),
                ),
            )
        )
    return out


def _to_m(lon: float, lat: float, olon: float, olat: float) -> tuple[float, float]:
    return (
        math.radians(lon - olon) * EARTH_RADIUS_M * math.cos(math.radians(olat)),
        math.radians(lat - olat) * EARTH_RADIUS_M,
    )


def distance_to_area_m(lon: float, lat: float, rings: list[list[tuple[float, float]]]) -> float:
    """0 inside the area (even-odd rule), else the distance to its nearest edge."""
    inside = False
    best = math.inf
    for ring in rings:
        pts = [_to_m(x, y, lon, lat) for x, y in ring]
        for (x1, y1), (x2, y2) in zip(pts, pts[1:] + pts[:1]):
            if (y1 > 0) != (y2 > 0) and 0 < x1 + (0 - y1) * (x2 - x1) / (y2 - y1):
                inside = not inside
            ex, ey = x2 - x1, y2 - y1
            length2 = ex * ex + ey * ey
            t = 0.0 if length2 == 0 else max(0.0, min(1.0, -(x1 * ex + y1 * ey) / length2))
            best = min(best, math.hypot(x1 + t * ex, y1 + t * ey))
    return 0.0 if inside else best


def lake_area_for(lon: float, lat: float, areas: list[LakeArea], tolerance_m: float = LAKE_AREA_TOLERANCE_M) -> LakeArea | None:
    """The DWD lake warning area the launch point lies in or next to, if any."""
    scored = [(distance_to_area_m(lon, lat, a.rings), a) for a in areas if a.rings]
    scored = [s for s in scored if s[0] <= tolerance_m]
    return min(scored, key=lambda s: s[0])[1] if scored else None


async def fetch_lake_areas(client: httpx.AsyncClient) -> list[LakeArea]:
    # The polygons are detailed and DWD's server can take a minute; they rarely change and are cached.
    resp = await client.get(
        WFS_URL,
        params=_query(typeName="dwd:Warngebiete_Binnenseen", srsName="EPSG:4326", propertyName="WARNCELLID,NAME,THE_GEOM"),
        timeout=120,
    )
    resp.raise_for_status()
    return parse_lake_areas(resp.json())


async def fetch_lake_warnings(client: httpx.AsyncClient) -> list[tuple[int, Warning]]:
    """All active lake warnings in Germany; there are only ever a few."""
    resp = await client.get(
        WFS_URL,
        params=_query(typeName="dwd:Warnungen_Binnenseen", propertyName=_PROPERTIES),
        timeout=30,
    )
    resp.raise_for_status()
    return parse_warnings(resp.json(), "lake")


async def fetch_local_warnings(client: httpx.AsyncClient, lon: float, lat: float) -> list[Warning]:
    """Weather warnings for the municipality the point lies in."""
    # GeoServer reads EPSG:4326 points in latitude-longitude order in WFS 2.0.
    resp = await client.get(
        WFS_URL,
        params=_query(
            typeName="dwd:Warnungen_Gemeinden",
            propertyName=_PROPERTIES.replace("AREADESC", "NAME"),
            CQL_FILTER=f"INTERSECTS(THE_GEOM,POINT({lat} {lon}))",
        ),
        timeout=30,
    )
    resp.raise_for_status()
    return [w for _, w in parse_warnings(resp.json(), "local")]


_PROPERTIES = "AREADESC,WARNCELLID,STATUS,MSGTYPE,EVENT,SEVERITY,HEADLINE,DESCRIPTION,INSTRUCTION,EFFECTIVE,ONSET,EXPIRES"
