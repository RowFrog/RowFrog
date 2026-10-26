"""Builds the website (web/public) into web/dist for Cloudflare Pages.

Copies the pages, makes app/de.json from the iPhone app's German table
(ios/RowFrog/Localization.swift) plus web/strings-de.json for the texts only
the website has, and draws the home-screen icons from the app icon. Run from
the repo root: python scripts/build_web.py
"""

import json
import re
import shutil
import sys
from pathlib import Path

WEB = Path("web")
OUT = WEB / "dist"
APP_ICON = Path("ios/RowFrog/Assets.xcassets/AppIcon.appiconset/light.png")
STRING = r'"((?:[^"\\]|\\.)*)"'


def unescape(text: str) -> str:
    return text.replace('\\"', '"').replace("\\\\", "\\")


def german_table() -> dict[str, str]:
    source = Path("ios/RowFrog/Localization.swift").read_text(encoding="utf-8")
    table = {unescape(k): unescape(v) for k, v in re.findall(STRING + r": " + STRING + ",", source)}
    extras = json.loads((WEB / "strings-de.json").read_text(encoding="utf-8"))
    return table | extras


def web_keys() -> set[str]:
    """Every English text the web app passes to t(), plus the backend credits it shows through t()."""
    keys: set[str] = set()
    for path in (WEB / "public" / "app").glob("*.js"):
        keys |= {unescape(k) for k in re.findall(r"\b(?:t|key)\(" + STRING, path.read_text(encoding="utf-8"))}
    api = Path("backend/rowfrog/api.py").read_text(encoding="utf-8")
    credits = re.search(r"ATTRIBUTION = \[(.*?)\]", api, re.S).group(1)
    return keys | set(re.findall(r'"([^"]+)"', credits))


def missing_german() -> list[str]:
    table = german_table()
    return sorted(k for k in web_keys() if k not in table or table[k].count("%@") != k.count("%@"))


def main() -> int:
    missing = missing_german()
    if missing:
        print("No German for:", *missing, sep="\n  ")
        return 1
    if OUT.exists():
        shutil.rmtree(OUT)
    shutil.copytree(WEB / "public", OUT)
    # The app's sample background pictures, so they are kept in one place.
    shutil.copytree(Path("ios/RowFrog/Backgrounds"), OUT / "app" / "backgrounds")
    table = german_table()
    # Only the texts the website uses, so the file stays small.
    used = {k: table[k] for k in sorted(web_keys())}
    (OUT / "app" / "de.json").write_text(json.dumps(used, ensure_ascii=False, indent=0), encoding="utf-8")
    from PIL import Image

    with Image.open(APP_ICON) as icon:
        for size in (192, 512):
            icon.convert("RGB").resize((size, size), Image.LANCZOS).save(OUT / f"icon-{size}.png", optimize=True)
    print(f"Built {sum(1 for p in OUT.rglob('*') if p.is_file())} files into {OUT}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
