import json

from rowerweather import locations


def test_confirmed_clubs_have_short_names():
    locs = locations.load(catalog_paths=())
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
    locs = locations.load(catalog_paths=[path])
    assert locs.lakes["starnberger-see"].name == "Starnberger See"
    assert locs.clubs["mrc-1880"].name.startswith("Münchener Ruder-Club")
    added = locs.clubs["rc-ammersee"]
    assert added.launch_point_verified is False
    assert added.short_name == "RC Ammersee"


def test_later_catalogs_skip_clubs_already_listed_nearby(tmp_path):
    drv = {
        "lakes": [{"id": "ammersee", "name": "Ammersee", "center": {"lat": 48.0, "lon": 11.12}}],
        "clubs": [{"id": "rc-ammersee", "name": "Ruder-Club Ammersee e.V.", "lakeId": "ammersee", "source": "drv",
                   "launchPoint": {"lat": 48.0, "lon": 11.1}}],
    }
    osm = {
        "lakes": [{"id": "ammersee-osm", "name": "Ammersee", "center": {"lat": 48.0, "lon": 11.12}}],
        "clubs": [{"id": "ruderclub-ammersee", "name": "Ruderclub Ammersee", "lakeId": "ammersee-osm",
                   "launchPoint": {"lat": 48.0005, "lon": 11.1005}}],
    }
    paths = []
    for name, data in [("drv.json", drv), ("osm.json", osm)]:
        (tmp_path / name).write_text(json.dumps(data))
        paths.append(tmp_path / name)
    locs = locations.load(catalog_paths=paths)
    assert locs.clubs["rc-ammersee"].source == "drv"
    assert "ruderclub-ammersee" not in locs.clubs
    assert "ammersee-osm" not in locs.lakes  # no clubs left on it
    assert locs.clubs["mrc-1880"].source is None
