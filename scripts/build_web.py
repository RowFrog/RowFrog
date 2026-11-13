"""Builds the website (web/public) into web/dist for Cloudflare Pages.

Copies the pages, makes app/de.json from the iPhone app's German table
(ios/RowFrog/Localization.swift) plus web/strings-de.json for the texts only
the website has, and draws the home-screen icons from the app icon. Run from
the repo root: python scripts/build_web.py
"""

import json
import os
import re
import shutil
import subprocess
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
        source = path.read_text(encoding="utf-8")
        keys |= {unescape(k) for k in re.findall(r"\b(?:t|key)\(" + STRING, source)}
        # tk("All", "Cloud line: All"): German comes from the key.
        keys |= {unescape(m[1]) for m in re.findall(r"\btk\(" + STRING + r",\s*" + STRING, source)}
        # A choice inside t(), e.g. t(mm < 2.5 ? "Light rain" : "Rain"): every text in it.
        for choice in re.findall(r"\bt\(([^()`\"]*\?[^()`]*)\)", source):
            keys |= {unescape(k) for k in re.findall(STRING, choice)}
    api = Path("backend/rowfrog/api.py").read_text(encoding="utf-8")
    credits = re.search(r"ATTRIBUTION = \[(.*?)\]", api, re.S).group(1)
    return keys | set(re.findall(r'"([^"]+)"', credits))


def missing_german() -> list[str]:
    table = german_table()
    return sorted(k for k in web_keys() if k not in table or table[k].count("%@") != k.count("%@"))


def build_and_commit() -> tuple[str, str]:
    """The build number and sha7, as the app's Settings > About shows them (BuildInfo.swift,
    decision 0034): ROWFROG_BUILD/ROWFROG_COMMIT (deploy-web.sh sets them for
    the deployed commit), else git here, else "1" and "dev"."""
    build, commit = os.environ.get("ROWFROG_BUILD", ""), os.environ.get("ROWFROG_COMMIT", "")
    if not (build and commit):
        try:
            git = lambda *a: subprocess.run(["git", *a], capture_output=True, text=True, check=True).stdout.strip()
            build, commit = git("rev-list", "--count", "HEAD"), git("rev-parse", "--short=7", "HEAD")
        except (OSError, subprocess.CalledProcessError):
            build, commit = "1", "dev"
    return build, commit[:7]


def stamp(path: Path, old: str, new: str) -> None:
    text = path.read_text(encoding="utf-8")
    if old not in text:
        raise SystemExit(f"{path}: {old!r} not found, cannot stamp the build")
    path.write_text(text.replace(old, new, 1), encoding="utf-8")


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
    # The app's statecharts (the route editor), read by both (owner decision 12 Nov 2026, D-lite).
    shutil.copytree(Path("ios/RowFrog/Charts"), OUT / "app" / "charts")
    table = german_table()
    # Only the texts the website uses, so the file stays small.
    used = {k: table[k] for k in sorted(web_keys())}
    (OUT / "app" / "de.json").write_text(json.dumps(used, ensure_ascii=False, indent=0), encoding="utf-8")
    # Settings > About > Version shows the app's version (MARKETING_VERSION in ios/project.yml),
    # build number and commit as the app does: "0.1.0 (723) · 22a69ce" (BuildInfo.swift).
    found = re.search(r'MARKETING_VERSION:\s*"?([^"\n]+)"?', Path("ios/project.yml").read_text(encoding="utf-8"))
    version = found.group(1).strip() if found else "–"
    build, commit = build_and_commit()
    (OUT / "app" / "version.json").write_text(json.dumps({
        "version": version, "build": build, "commit": commit, "summary": f"{version} ({build}) · {commit}",
    }), encoding="utf-8")
    # "Build 723 · 22a69ce" in the footers (the source says "Build 1 · dev").
    stamp(OUT / "app" / "shared.js", 'export const BUILD = { build: "1", commit: "dev" };',
          f"export const BUILD = {json.dumps({'build': build, 'commit': commit})};")
    stamp(OUT / "index.html", "Build 1 · dev", f"Build {build} · {commit}")
    from PIL import Image

    with Image.open(APP_ICON) as icon:
        for size in (180, 192, 512):
            icon.convert("RGB").resize((size, size), Image.LANCZOS).save(OUT / f"icon-{size}.png", optimize=True)
        # Safari also asks for these two by name, whatever the page links.
        shutil.copy(OUT / "icon-180.png", OUT / "apple-touch-icon.png")
        icon.convert("RGB").save(OUT / "favicon.ico", sizes=[(32, 32), (48, 48)])
    print(f"Build {build} · {commit}")
    print(f"Built {sum(1 for p in OUT.rglob('*') if p.is_file())} files into {OUT}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
