import json

from fastapi.testclient import TestClient

from rowfrog import api, locations


def test_catalog_file_name_gives_the_country(tmp_path):
    at = {
        "lakes": [{"id": "river-donau", "name": "Donau", "center": {"lat": 48.2, "lon": 16.4}, "kind": "river"}],
        "clubs": [{"id": "wrk-argonauten", "name": "Wiener Ruderklub Argonauten", "lakeId": "river-donau",
                   "region": "Wien", "launchPoint": {"lat": 48.24, "lon": 16.43}}],
    }
    (tmp_path / "at-oerv.json").write_text(json.dumps(at))
    locs = locations.load(catalog_paths=[tmp_path / "at-oerv.json"])
    club = locs.clubs["wrk-argonauten"]
    assert (club.country, club.source, club.region) == ("at", "oerv", "Wien")
    assert locs.lakes["river-donau"].country == "at"
    assert locs.clubs["mrc-1880"].country == "de"
    assert locs.countries() == ["de", "at"]


def test_a_border_lake_lists_each_countrys_clubs_in_its_own_file(tmp_path, monkeypatch):
    lake = {"id": "bodensee", "name": "Bodensee", "center": {"lat": 47.6, "lon": 9.4}}
    de = {"lakes": [lake], "clubs": [{"id": "rv-konstanz", "name": "RV Konstanz", "lakeId": "bodensee",
                                      "launchPoint": {"lat": 47.66, "lon": 9.18}}]}
    ch = {"lakes": [lake], "clubs": [{"id": "rc-kreuzlingen", "name": "RC Kreuzlingen", "lakeId": "bodensee",
                                      "launchPoint": {"lat": 47.65, "lon": 9.20}}]}
    (tmp_path / "de-drv.json").write_text(json.dumps(de))
    (tmp_path / "ch-osm.json").write_text(json.dumps(ch))
    monkeypatch.setattr(api, "_locations", locations.load(catalog_paths=[tmp_path / "de-drv.json", tmp_path / "ch-osm.json"]))
    client = TestClient(api.app)

    countries = {c["code"]: c for c in client.get("/countries/index").json()}
    assert set(countries) == {"de", "ch"}
    assert countries["ch"]["clubs"] == 1 and countries["ch"]["nameDe"] == "Schweiz"
    assert countries["ch"]["bounds"]["north"] == 47.65

    ch_lakes = client.get("/countries/ch/lakes").json()
    assert [(l["id"], [c["id"] for c in l["clubs"]]) for l in ch_lakes] == [("bodensee", ["rc-kreuzlingen"])]
    de_ids = {c["id"] for l in client.get("/countries/de/lakes").json() for c in l["clubs"]}
    assert "rv-konstanz" in de_ids and "rc-kreuzlingen" not in de_ids
    assert client.get("/countries/fr/lakes").status_code == 404
    everything = {c["id"] for l in client.get("/lakes/index").json() for c in l["clubs"]}
    assert {"rv-konstanz", "rc-kreuzlingen", "mrc-1880"} <= everything
