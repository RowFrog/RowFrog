"""Checks that every English text the iOS app passes to tr() has a German
entry in Localization.swift, with the same placeholders. Run from the repo root."""

import re
import sys
from pathlib import Path

APP = Path("ios/RowerWeather")
STRING = r'"((?:[^"\\]|\\.)*)"'


def unescape(text: str) -> str:
    return text.replace('\\"', '"').replace("\\\\", "\\")


def main() -> int:
    table_source = (APP / "Localization.swift").read_text()
    table = {unescape(k): unescape(v) for k, v in re.findall(STRING + r": " + STRING + ",", table_source)}

    keys: set[str] = set()
    for path in APP.glob("*.swift"):
        source = path.read_text()
        keys |= {unescape(k) for k in re.findall(r"\btr\(" + STRING, source)}
        keys |= {unescape(k) for k in re.findall(r"englishTitle: " + STRING, source)}
    # Credits the backend sends, shown through tr().
    api = Path("backend/rowerweather/api.py").read_text()
    credits = re.search(r"ATTRIBUTION = \[(.*?)\]", api, re.S).group(1)
    keys |= set(re.findall(r'"([^"]+)"', credits))

    problems = []
    # A key twice in a Swift dictionary literal stops the app when the table is first read.
    all_keys = [unescape(k) for k, _ in re.findall(STRING + r": " + STRING + ",", table_source)]
    problems += [f"German text listed twice: {k}" for k in sorted({k for k in all_keys if all_keys.count(k) > 1})]
    for key in sorted(keys):
        if key not in table:
            problems.append(f"no German text for: {key}")
        elif re.findall(r"%[@%]|%\.\d+f", key) != re.findall(r"%[@%]|%\.\d+f", table[key]):
            problems.append(f"placeholders differ: {key!r} -> {table[key]!r}")
    for key in sorted(set(table) - keys):
        problems.append(f"unused German text: {key}")
    print("\n".join(problems) or f"All {len(keys)} texts have German translations.")
    return 1 if problems else 0


if __name__ == "__main__":
    sys.exit(main())
