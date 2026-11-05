"""scripts/accept_launch_point.py: a launch point suggested from the app goes
into the hand-checked list and the club's catalog, on a copy of the data."""

import json
import shutil
import sys
from datetime import date
from pathlib import Path

import pytest

sys.path.insert(0, str(Path(__file__).resolve().parents[2] / "scripts"))

import accept_launch_point as accept  # noqa: E402

BODY = """Suggested from the app: where this club's boats go on the water.

- Club: `Ruderclub Musterstadt`
- Club id: `ruderclub-musterstadt`
- Launch point: 47.912346, 11.300000 ([map](https://www.openstreetmap.org/?mlat=47.912346&mlon=11.300000#map=18/47.912346/11.300000))

Answer `/accept` to put it into the hand-checked list (the workflow opens a pull request).
"""


@pytest.fixture
def root(tmp_path):
    (tmp_path / "data" / "catalogs").mkdir(parents=True)
    (tmp_path / "data" / "locations.json").write_text(json.dumps({"lakes": [], "clubs": [{"id": "mrc-1880"}]}))
    catalog = {"lakes": [{"id": "see"}], "clubs": [
        {"id": "ruderclub-musterstadt", "name": "Ruderclub Musterstadt", "lakeId": "see",
         "launchPoint": {"lat": 47.9, "lon": 11.29, "precision": "address", "verified": False}},
        {"id": "other", "name": "Other", "lakeId": "see", "launchPoint": {"lat": 1, "lon": 2}},
    ]}
    (tmp_path / "data" / "catalogs" / "de-drv.json").write_text(json.dumps(catalog))
    hand = {"comment": "x", "remove": ["gone"], "de": {
        "ruderclub-musterstadt": {"address": "Seeweg 1", "club": [47.91, 11.29], "launchPoint": [47.0, 11.0], "checked": "2026-10-01"},
        "school": {"sameAs": "ruderclub-musterstadt"},
    }}
    (tmp_path / "data" / "catalogs" / "hand-checked.json").write_text(json.dumps(hand))
    return tmp_path


def test_the_issue_text_gives_club_and_point():
    assert accept.parse(BODY) == ("ruderclub-musterstadt", 47.912346, 11.3)
    # An issue edited on GitHub comes back with Windows line ends.
    assert accept.parse(BODY.replace("\n", "\r\n")) == ("ruderclub-musterstadt", 47.912346, 11.3)


@pytest.mark.parametrize("body", [
    "",
    BODY.replace("- Club id:", "- Club:"),
    BODY.replace("`ruderclub-musterstadt`", "`../etc`"),
    BODY.replace("47.912346, 11.300000", "147.9, 11.3"),
])
def test_text_that_is_not_from_the_app_is_turned_down(body):
    with pytest.raises(ValueError):
        accept.parse(body)


def test_the_owner_can_give_another_point():
    assert accept.parse_override("") is None
    assert accept.parse_override(" 47.91234, 11.30012 ") == (47.91234, 11.30012)
    with pytest.raises(ValueError):
        accept.parse_override("please; rm -rf /")


def test_accepting_writes_the_hand_checked_list_and_moves_the_catalog_point(root):
    name = accept.accept("ruderclub-musterstadt", 47.912346, 11.3, 42, date(2026, 11, 6), root)
    assert name == "Ruderclub Musterstadt"
    hand = json.loads((root / "data" / "catalogs" / "hand-checked.json").read_text())
    assert hand["de"]["ruderclub-musterstadt"] == {
        "address": "Seeweg 1", "club": [47.91, 11.29], "launchPoint": [47.912346, 11.3],
        "checked": "2026-11-06", "suggestion": "#42"}
    assert hand["de"]["school"] == {"sameAs": "ruderclub-musterstadt"}
    clubs = json.loads((root / "data" / "catalogs" / "de-drv.json").read_text())["clubs"]
    assert clubs[0]["launchPoint"] == {"lat": 47.91235, "lon": 11.3, "verified": False,
                                       "precision": "launch point checked by hand on the satellite view (2026-11-06)"}
    assert clubs[1]["launchPoint"] == {"lat": 1, "lon": 2}


@pytest.mark.parametrize("club", ["mrc-1880", "nowhere", "school"])
def test_clubs_it_cannot_change(root, club):
    if club == "school":
        catalog = json.loads((root / "data" / "catalogs" / "de-drv.json").read_text())
        catalog["clubs"].append({"id": "school", "name": "School", "lakeId": "see", "launchPoint": {}})
        (root / "data" / "catalogs" / "de-drv.json").write_text(json.dumps(catalog))
    with pytest.raises(ValueError):
        accept.accept(club, 47.9, 11.3, 1, date(2026, 11, 6), root)


def test_the_real_files_keep_their_layout(tmp_path):
    """Writing the real files back unchanged keeps them byte for byte, so a
    pull request shows only the club's lines."""
    real = Path(accept.ROOT)
    shutil.copytree(real / "data", tmp_path / "data", ignore=shutil.ignore_patterns("outlines", "*.geojson"))
    hand = json.loads((real / "data" / "catalogs" / "hand-checked.json").read_text())
    club_id, entry = next((k, v) for k, v in hand["de"].items() if "launchPoint" in v)
    accept.accept(club_id, *entry["launchPoint"], 7, date.fromisoformat(entry["checked"]), tmp_path)
    after = json.loads((tmp_path / "data" / "catalogs" / "hand-checked.json").read_text())
    assert after["de"][club_id]["suggestion"] == "#7"
    del after["de"][club_id]["suggestion"]
    assert after == hand
