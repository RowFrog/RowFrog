"""scripts/osm_club_places.py: which OpenStreetMap feature is a club's own place."""

import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[2] / "scripts"))

import osm_club_places as places  # noqa: E402

LAUNCH = (48.13, 11.55)


def feature(name, north_m=0.0, osm="way/1"):
    return {"name": name, "lat": LAUNCH[0] + north_m / 111_195, "lon": LAUNCH[1], "osm": osm}


def club(id, name, short=None):
    return {"id": id, "name": name, "shortName": short or name, "points": [LAUNCH]}


def test_names_keep_only_their_telling_words():
    assert places.words("Münchener Ruder-Club von 1880 e.V.") == {"muenchener", "1880"}
    assert places.words("Der Hamburger und Germania Ruder Club") == {"hamburger", "germania"}
    assert places.words("RuderClub Bayern") == {"bayern"}
    assert places.likeness("Münchener Ruder-Club von 1880 e.V.", "Münchener Ruderclub 1880") == 1.0
    assert places.likeness("Ruderclub", "Ruderverein") == 0.0


def test_the_club_takes_its_own_feature_not_the_neighbours():
    clubs = [club("mrc", "Münchener Ruder-Club von 1880 e.V."), club("bayern", "Münchener Ruderclub Bayern")]
    found = places.match(clubs, [feature("Münchener Ruder-Club 1880", 90, "way/1"), feature("Münchener RC Bayern", 40, "way/2")])
    assert found["mrc"]["osm"] == "way/1"
    assert found["bayern"]["osm"] == "way/2"


def test_a_club_without_its_own_feature_does_not_take_a_neighbours_it_shares_a_town_with():
    clubs = [club("mrc", "Münchener Ruder-Club von 1880 e.V."), club("bayern", "Münchener Ruderclub Bayern")]
    found = places.match(clubs, [feature("Münchener Ruderclub Bayern", 40, "way/2")])
    assert "mrc" not in found
    assert found["bayern"]["osm"] == "way/2"


def test_far_features_and_other_names_are_left_out():
    clubs = [club("hgrc", "Der Hamburger und Germania Ruder Club")]
    assert places.match(clubs, [feature("Der Hamburger und Germania Ruder Club", 900)]) == {}
    assert places.match(clubs, [feature("Segelclub Alster", 20)]) == {}
    assert places.match(clubs, [feature("Germania Ruder Club", 70)])["hgrc"]["name"] == "Germania Ruder Club"


def test_clubs_matching_one_feature_equally_share_it():
    clubs = [club("a", "Ruderverein Tutzing"), club("b", "Ruderriege Tutzing")]
    found = places.match(clubs, [feature("Bootshaus Tutzing", 30)])
    assert found["a"]["osm"] == found["b"]["osm"] == "way/1"


def test_rentals_and_unnamed_features_are_not_clubs():
    elements = [
        {"type": "node", "id": 1, "lat": 48.0, "lon": 11.0, "tags": {"name": "Ruderbootverleih am See", "leisure": "x"}},
        {"type": "node", "id": 2, "lat": 48.0, "lon": 11.0, "tags": {"sport": "rowing"}},
        {"type": "way", "id": 3, "center": {"lat": 48.1, "lon": 11.1}, "tags": {"name": "Ruderclub Tutzing", "sport": "rowing"}},
    ]
    assert places.features_from(elements) == [{"name": "Ruderclub Tutzing", "lat": 48.1, "lon": 11.1, "osm": "way/3"}]


def test_queries_look_only_around_the_clubs(monkeypatch):
    sent = []
    monkeypatch.setattr(places, "overpass", lambda q, timeout: sent.append(q) or {"elements": []})
    places.query([club("a", "Ruderverein Tutzing")])
    assert "(around:700,48.13000,11.55000)" in sent[0]
    assert "[timeout:90]" in sent[0]


def test_a_failed_query_is_tried_again_and_then_given_up(monkeypatch):
    calls = []

    def flaky(clubs):
        calls.append(1)
        if len(calls) < 3:
            raise OSError("all Overpass servers failed")
        return [{"type": "node", "id": 1}]

    monkeypatch.setattr(places, "query", flaky)
    assert places.query_with_retries([], tries=3, pause=0) == [{"type": "node", "id": 1}]
    calls.clear()
    assert places.query_with_retries([], tries=2, pause=0) is None


def test_clubs_whose_query_failed_keep_the_last_runs_place(monkeypatch, tmp_path):
    clubs = [club("a", "Ruderverein Tutzing"), club("b", "Ruderclub Starnberg")]
    clubs[1]["points"] = [(47.99, 11.34)]
    out = tmp_path / "osm-places.json"
    out.write_text('{"places": {"b": {"at": [47.99, 11.34], "name": "Ruderclub Starnberg", "osm": "way/9"}}}')
    monkeypatch.setattr(places, "OUT", out)
    monkeypatch.setattr(places, "CLUBS_PER_QUERY", 1)
    monkeypatch.setattr(places, "clubs_to_place", lambda: clubs)
    monkeypatch.setattr(places.time, "sleep", lambda s: None)
    tutzing = {"type": "way", "id": 1, "center": {"lat": 48.1301, "lon": 11.55}, "tags": {"name": "Ruderverein Tutzing"}}
    monkeypatch.setattr(places, "query_with_retries", lambda batch: [tutzing] if batch[0]["id"] == "a" else None)
    assert places.main() == 1  # written, but says not every club was looked up
    import json
    found = json.loads(out.read_text())["places"]
    assert found["a"]["osm"] == "way/1"
    assert found["b"]["osm"] == "way/9"
