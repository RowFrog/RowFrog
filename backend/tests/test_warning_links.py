from rowfrog import warning_links


def test_dwd_town_page_in_both_languages():
    links = warning_links.links("dwd", "local", "Seestraße 1, 82319 Starnberg", 11.34, 48.0)
    assert links == {
        "de": "https://www.dwd.de/DE/wetter/warnungen_gemeinden/warnWetter_node.html?ort=Starnberg",
        "en": "https://www.dwd.de/EN/weather/warnings/warnings_node.html?ort=Starnberg",
    }


def test_dwd_town_with_umlaut_and_space_is_encoded():
    links = warning_links.links(None, "local", "Am See 2, 82211 Herrsching am Ammersee", 11.17, 48.0)
    assert links["de"].endswith("?ort=Herrsching%20am%20Ammersee")


def test_dwd_lake_warning_goes_to_inland_lakes_page():
    links = warning_links.links("dwd", "lake", "Seestraße 1, 82319 Starnberg", 11.34, 48.0)
    assert links["de"] == "https://www.wettergefahren.de/warnungen/binnenseewarnungen.html"


def test_dwd_without_town_falls_back_to_start_page():
    assert warning_links.links("dwd", "local", "", 11.34, 48.0)["de"] == "https://www.wettergefahren.de/"


def test_geosphere_opens_the_map_at_the_launch_point():
    links = warning_links.links("geosphere", "local", "Uferweg 1, 9020 Klagenfurt", 14.24561, 46.61789)
    assert links["de"] == "https://warnungen.zamg.at/wsapp/de/alle/gesamterzeitraum/oesterreich/14.2456,46.6179"
    assert links["en"].startswith("https://warnungen.zamg.at/wsapp/en/alle/")


def test_meteoswiss_uses_the_address_its_app_claims():
    links = warning_links.links("meteoswiss", "local", "Bellerivestrasse 1, 8008 Zürich", 8.55, 47.36)
    assert "/applikationen/gefahren.html" in links["de"]
    assert "/applications/hazards.html" in links["en"]


def test_unknown_service_has_no_link():
    assert warning_links.links("other", "local", "x", 0, 0) is None
