import json

from rowfrog import locations


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


def test_clubs_sharing_a_boathouse_in_one_catalog_are_all_kept(tmp_path):
    drv = {
        "lakes": [{"id": "river-main", "name": "Main", "center": {"lat": 49.9, "lon": 10.9}}],
        "clubs": [{"id": f"club-{i}", "name": f"Club {i}", "lakeId": "river-main",
                   "launchPoint": {"lat": 49.9, "lon": 10.9}} for i in range(2)],
    }
    (tmp_path / "drv.json").write_text(json.dumps(drv))
    locs = locations.load(catalog_paths=[tmp_path / "drv.json"])
    assert {"club-0", "club-1"} <= set(locs.clubs)


def test_river_clubs_move_onto_their_sections(tmp_path):
    catalog = {
        "lakes": [{"id": "river-main", "name": "Main", "kind": "river", "center": {"lat": 50.1, "lon": 8.7}}],
        "clubs": [
            {"id": "rc-offenbach", "name": "RC Offenbach", "lakeId": "river-main", "launchPoint": {"lat": 50.10, "lon": 8.76}},
            {"id": "rc-frankfurt", "name": "RC Frankfurt", "lakeId": "river-main", "launchPoint": {"lat": 50.10, "lon": 8.68}},
            {"id": "rc-wuerzburg", "name": "RC Würzburg", "lakeId": "river-main", "launchPoint": {"lat": 49.79, "lon": 9.93}},
        ],
    }
    end = {"km": 7.3, "end": "weir/lock", "what": "lock Offenbach", "at": [50.1, 8.8]}
    sections = {"sections": [
        {"id": "river-main-offenbach", "water": "river-main", "name": "Main", "river": "Main", "waterway": "river",
         "country": "de", "place": "Offenbach", "center": {"lat": 50.1, "lon": 8.72}, "clubs": ["rc-offenbach", "rc-frankfurt"],
         "lengthKm": 14.5, "up": end, "down": None, "pictureBox": [8.65, 50.06, 8.79, 50.15]},
        {"id": "river-main-gone", "water": "river-main", "name": "Main", "river": "Main", "waterway": "river",
         "country": "de", "place": "Gone", "center": {"lat": 50.0, "lon": 9.0}, "clubs": ["rc-moved-away"],
         "lengthKm": 10, "up": None, "down": None, "pictureBox": [8.9, 49.9, 9.1, 50.1]},
    ]}
    (tmp_path / "de-drv.json").write_text(json.dumps(catalog))
    (tmp_path / "sections.json").write_text(json.dumps(sections))
    locs = locations.load(catalog_paths=[tmp_path / "de-drv.json"], sections_path=tmp_path / "sections.json")
    assert locs.clubs["rc-offenbach"].lake_id == locs.clubs["rc-frankfurt"].lake_id == "river-main-offenbach"
    section = locs.lakes["river-main-offenbach"]
    assert (section.kind, section.name, section.section.place) == ("river", "Main", "Offenbach")
    assert section.section.up.what == "lock Offenbach" and section.section.down is None
    # A club without a section stays on the whole river, and sections without clubs are left out.
    assert locs.clubs["rc-wuerzburg"].lake_id == "river-main"
    assert "river-main-gone" not in locs.lakes
