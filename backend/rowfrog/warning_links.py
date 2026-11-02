"""Where a warning can be read at the service that issued it.

None of the three services gives a single warning its own page, so each
warning links to the closest one (checked 2026-11-02 with a GitHub Actions
probe; thread "Open official warnings at their source"):

- DWD: the municipal warning page for the club's town (`?ort=`, as DWD's own
  "Homepagewetter" page documents), in German or English; lake warnings go to
  DWD's inland lake warning page. DWD's WarnWetter app has no web links of its
  own, so the app offers it through the App Store instead.
- GeoSphere Austria: the warning map opened at the launch point
  (/wsapp/<lang>/alle/gesamterzeitraum/oesterreich/<lon>,<lat>), which shows the
  warnings for that spot.
- MeteoSwiss: the hazards page. The MeteoSwiss app claims this address
  (apple-app-site-association), so on an iPhone with the app it opens there;
  without it the hazard map opens in the browser.
"""
from __future__ import annotations

from urllib.parse import quote

DWD_TOWN = {
    "de": "https://www.dwd.de/DE/wetter/warnungen_gemeinden/warnWetter_node.html?ort={town}",
    "en": "https://www.dwd.de/EN/weather/warnings/warnings_node.html?ort={town}",
}
DWD_LAKES = "https://www.wettergefahren.de/warnungen/binnenseewarnungen.html"
DWD_START = "https://www.wettergefahren.de/"
GEOSPHERE_POINT = "https://warnungen.zamg.at/wsapp/{lang}/alle/gesamterzeitraum/oesterreich/{lon:.4f},{lat:.4f}"
METEOSWISS = {
    "de": "https://www.meteoschweiz.admin.ch/service-und-publikationen/applikationen/gefahren.html#tab=natural-hazards-map",
    "en": "https://www.meteoswiss.admin.ch/services-and-publications/applications/hazards.html#tab=natural-hazards-map",
}


def town_of(address: str) -> str | None:
    """The town at the end of an address ("Seestraße 1, 82319 Starnberg" -> "Starnberg"),
    as the app's Club.town reads it."""
    last = address.split(",")[-1].split()
    while last and last[0].isdigit():
        last = last[1:]
    return " ".join(last) or None


def links(source: str | None, kind: str, address: str, lon: float, lat: float) -> dict[str, str] | None:
    """{"de": url, "en": url} for one warning, or None for a service without a page."""
    source = source or "dwd"
    if source == "dwd":
        if kind == "lake":
            return {"de": DWD_LAKES, "en": DWD_LAKES}
        town = town_of(address)
        if town is None:
            return {"de": DWD_START, "en": DWD_START}
        return {lang: url.format(town=quote(town)) for lang, url in DWD_TOWN.items()}
    if source == "geosphere":
        return {lang: GEOSPHERE_POINT.format(lang=lang, lon=lon, lat=lat) for lang in ("de", "en")}
    if source == "meteoswiss":
        return dict(METEOSWISS)
    return None
