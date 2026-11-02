"""Every reason the backend can give for a light needs a label in the app and a
tile on the website; a new reason without them shows its raw name ("lake_lowered")
to the rower."""

import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
BACKEND = ROOT / "backend" / "rowfrog"


def backend_reasons() -> set[str]:
    names: set[str] = set()
    for module in ("score", "forecast", "river", "lake_level"):
        source = (BACKEND / f"{module}.py").read_text()
        # ("wind", _rising(...)), checks.append(("fog", Light.RED)), return "twilight", Light.AMBER
        names |= set(re.findall(r'"([a-z_]+)",\s*(?:Light\.|_rising\(|c\.|t\.)', source))
        names |= set(re.findall(r'daylight_name: str = "([a-z_]+)"', source))
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
    assert {"wind", "gusts", "waves", "fog", "twilight", "daylight", "lake_lowered", "current"} <= backend_reasons()


def test_every_backend_reason_has_an_app_label():
    assert backend_reasons() - app_labels() == set()


def test_every_backend_reason_has_a_website_tile():
    # The website files any "..._warning" under the warning icon (reasonCondition in logic.js).
    missing = {n for n in backend_reasons() - website_reasons() if not n.endswith("_warning")}
    assert missing == set()
