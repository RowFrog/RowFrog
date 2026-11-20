"""Every reason the backend can give for a light needs a label in the app and a
tile on the website; a new reason without them shows its raw name ("lake_lowered")
to the rower. The names are listed once in testdata/reasons.json, which the app's
and the website's tests read too; here the backend may send nothing else."""

import json
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
BACKEND = ROOT / "backend" / "rowfrog"


def listed() -> dict:
    return json.loads((ROOT / "testdata" / "reasons.json").read_text())


def backend_reasons() -> set[str]:
    names: set[str] = set()
    # Every module, not only the scoring ones: "nearby_water" is made in api.py and was missed
    # while only score, forecast, river and lake_level were read (owner's screenshot, 12 Nov 2026).
    for path in sorted(BACKEND.rglob("*.py")):
        source = path.read_text()
        # ("wind", _rising(...)), checks.append(("fog", Light.RED)), return "twilight", Light.AMBER
        names |= set(re.findall(r'"([a-z_]+)",\s*(?:Light\.|_rising\(|c\.|t\.)', source))
        names |= set(re.findall(r'daylight_name: str = "([a-z_]+)"', source))
        # {"condition": "nearby_water", ...}
        names |= set(re.findall(r'"condition":\s*"([a-z_]+)"', source))
    return names


def sample_reasons() -> set[str]:
    """The reason names in the sample API files, as published."""
    names: set[str] = set()
    for path in (ROOT / "testdata" / "api").rglob("*"):
        if path.is_file():
            names |= set(re.findall(r'"condition":\s*"([a-z_]+)"', path.read_text(errors="ignore")))
    return names


def app_labels() -> set[str]:
    source = (ROOT / "ios" / "RowFrog" / "Models.swift").read_text()
    label = source.split("private var baseLabel: String {", 1)[1].split("private var baseExplanation", 1)[0]
    return set(re.findall(r'case "([a-z_]+)"', label))


def website_reasons() -> set[str]:
    source = (ROOT / "web" / "public" / "app" / "logic.js").read_text()
    block = source.split("export const REASONS = {", 1)[1].split("};", 1)[0]
    return set(re.findall(r'"([a-z_]+)"', block))


def test_the_backend_list_is_read():
    assert {"wind", "gusts", "waves", "fog", "twilight", "daylight", "lake_lowered", "current", "nearby_water"} <= backend_reasons()


def test_the_backend_sends_only_listed_reasons():
    assert backend_reasons() - set(listed()["reasons"]) == set()
    assert sample_reasons() - set(listed()["reasons"]) == set()


def test_every_listed_reason_is_still_sent():
    # A name taken out of the backend comes out of the list too.
    assert set(listed()["reasons"]) - backend_reasons() == set()


def test_every_backend_reason_has_an_app_label():
    # The app's own test (ReasonNamesTests.swift) also checks each listed name gets a real label.
    assert set(listed()["reasons"]) - app_labels() == set()


def test_every_backend_reason_has_a_website_tile():
    # The website files any "..._warning" under the warning icon, and "nearby_water" under its
    # topic's tile (reasonCondition in logic.js).
    missing = {n for n in backend_reasons() - website_reasons() if not n.endswith("_warning") and n != "nearby_water"}
    assert missing == set()


def test_reason_order_is_the_listed_one():
    """One order for the server, the app and the website (owner, 20 Nov 2026)."""
    from rowfrog.score import REASON_ORDER

    data = listed()
    assert list(REASON_ORDER) == data["order"]
    # Every reason the backend may send has its place; nearby_water ranks as its topic.
    assert set(data["reasons"]) - {"nearby_water"} <= set(data["order"])
    assert set(data["topics"]["nearby_water"]) <= set(data["order"])


def test_red_comes_first_then_the_more_dangerous():
    """The owner's screenshot of 20 Nov 2026 listed the amber sunset above red wind."""
    from rowfrog.score import Light, ordered

    got = ordered([
        ("twilight", Light.AMBER), ("wind", Light.RED), ("weather_warning", Light.AMBER),
        ("gusts", Light.RED), ("brand_new_reason", Light.AMBER),
    ])
    assert got == [
        ("gusts", Light.RED), ("wind", Light.RED), ("weather_warning", Light.AMBER),
        ("brand_new_reason", Light.AMBER), ("twilight", Light.AMBER),
    ]
