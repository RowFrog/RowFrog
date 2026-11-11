"""Checks that every English text the iOS app shows also appears on the website
(web/public), so an app change cannot reach the app alone. A text that belongs
to the app only (widgets, app icons, Apple Health, iPhone settings) or that the
website says in its own words for browsers is listed in web/app-only-texts.txt,
under a comment saying why. Run from the repo root.

A text with placeholders counts as found when each piece between them is in the
website's code. When this check fails: carry the change over to the website, or
add the text to web/app-only-texts.txt with the reason."""

import re
import sys
from pathlib import Path

APP = Path("ios/RowFrog")
WEB = Path("web/public")
LIST = Path("web/app-only-texts.txt")
STRING = r'"((?:[^"\\]|\\.)*)"'
PLACEHOLDER = r"%(?:\d\$)?@|%d|%\.\d+f|%%"


def unescape(text: str) -> str:
    return text.replace('\\"', '"').replace("\\\\", "\\").replace("\\u{201C}", "“").replace("\\u{201D}", "”")


def app_texts() -> dict[str, str]:
    """English text -> the first app file that shows it."""
    texts: dict[str, str] = {}
    for path in sorted(APP.glob("*.swift")):
        if path.name == "Localization.swift":
            continue
        source = path.read_text()
        for pattern in (r"\btr\(" + STRING, r"englishTitle: " + STRING, r"\bSettingsSearch\(" + STRING):
            for text in re.findall(pattern, source):
                texts.setdefault(unescape(text), path.name)
    return texts


def web_source() -> str:
    parts = []
    for path in sorted(WEB.rglob("*")):
        if path.is_file() and path.suffix in (".js", ".html", ".json") and "vendor" not in path.parts:
            parts.append(path.read_text(errors="ignore"))
    return "\n".join(parts).replace('\\"', '"')


def found(text: str, web: str) -> bool:
    pieces = [p for p in re.split(PLACEHOLDER, text) if p.strip(" ·:,.")]
    return all(p in web for p in pieces)


def main() -> int:
    listed = {line for line in LIST.read_text().splitlines() if line.strip() and not line.startswith("#")}
    texts = app_texts()
    web = web_source()
    missing = sorted((f, t) for t, f in texts.items() if t not in listed and not found(t, web))
    stale = sorted(t for t in listed if t not in texts)
    for f, t in missing:
        print(f"only in the app ({f}): {t}")
    for t in stale:
        print(f"listed in {LIST} but no longer in the app: {t}")
    if missing:
        print(f"\n{len(missing)} app texts have no counterpart on the website: carry the change over to web/, "
              f"or list the text in {LIST} under the reason it stays app-only.")
    if not missing and not stale:
        print(f"All {len(texts)} app texts are on the website or listed as app-only ({len(listed)}).")
    return 1 if missing or stale else 0


if __name__ == "__main__":
    sys.exit(main())
