import json

from rowerweather import locations


def test_confirmed_clubs_have_short_names():
    locs = locations.load(catalog_path=None)
    assert locs.clubs["mrc-1880"].short_name == "MRC 1880"
    assert all(c.launch_point_verified for c in locs.clubs.values())


def test_catalog_adds_unconfirmed_clubs_but_never_overrides(tmp_path):
    catalog = {
        "lakes": [
            {"id": "ammersee", "name": "Ammersee", "center": {"lat": 48.0, "lon": 11.12}},
            {"id": "starnberger-see", "name": "Wrong", "center": {"lat": 0, "lon": 0}},
        ],
        "clubs": [
            {"id": "rc-ammersee", "name": "RC Ammersee", "lakeId": "ammersee",
             "launchPoint": {"lat": 48.0, "lon": 11.1, "verified": True}},
            {"id": "mrc-1880", "name": "Wrong", "lakeId": "ammersee",
             "launchPoint": {"lat": 0, "lon": 0}},
        ],
    }
    path = tmp_path / "catalog.json"
    path.write_text(json.dumps(catalog))
    locs = locations.load(catalog_path=path)
    assert locs.lakes["starnberger-see"].name == "Starnberger See"
    assert locs.clubs["mrc-1880"].name.startswith("Münchener Ruder-Club")
    added = locs.clubs["rc-ammersee"]
    assert added.launch_point_verified is False
    assert added.short_name == "RC Ammersee"
