#!/usr/bin/env python3
"""Look at the club pages of Swiss Rowing and the Austrian rowing federation.

Usage (from the repository root):
    python3 scripts/probe_federations.py

Prints what the pages hold (links to club pages, field labels, legal pages,
robots.txt) so the import scripts can be written against the real markup.
Reads a handful of pages, one a second. Imports nothing.
"""

from __future__ import annotations

import re
import sys
import time
import urllib.parse

from import_drv import get, page_lines

START = {
    "swissrowing": "https://www.swissrowing.ch/de/verband/ruderclubs",
    "oerv": "https://www.rudern.at/",
}
EXTRA = [
    "https://www.rudern.at/vereine",
    "https://www.rudern.at/verband/vereine",
    "https://www.rudern-ooe.at/verband/vereine/",
]
LEGAL = re.compile(r"(?i)impressum|rechtlich|datenschutz|nutzung|agb|disclaimer|copyright|legal")


def links(base: str, page: str) -> list[tuple[str, str]]:
    out = []
    for href, text in re.findall(r'(?s)<a\b[^>]*href="([^"#]+)"[^>]*>(.*?)</a>', page):
        text = " ".join(re.sub(r"<[^>]+>", " ", text).split())
        out.append((urllib.parse.urljoin(base, href), text))
    return list(dict.fromkeys(out))


def fetch(url: str) -> str | None:
    time.sleep(1.0)
    try:
        page = get(url)
    except Exception as err:  # noqa: BLE001 - a probe reports every failure
        print(f"  FAILED {url}: {err}")
        return None
    print(f"  ok {url}: {len(page)} bytes")
    return page


def show(url: str, page: str, pattern: str | None = None, lines: int = 60) -> list[tuple[str, str]]:
    found = links(url, page)
    print(f"--- {url}")
    print("  title:", re.search(r"(?s)<title>(.*?)</title>", page).group(1).strip() if "<title>" in page else "-")
    if pattern:
        hits = [(u, t) for u, t in found if re.search(pattern, u)]
        print(f"  {len(hits)} links matching {pattern}:")
        for u, t in hits[:400]:
            print(f"    {u} | {t}")
    for u, t in found:
        if LEGAL.search(u) or LEGAL.search(t):
            print(f"  legal: {u} | {t}")
    print("  text:")
    for l in page_lines(page)[:lines]:
        print("   ", l[:200])
    return found


def main() -> int:
    for host in ("https://www.swissrowing.ch", "https://www.rudern.at"):
        page = fetch(host + "/robots.txt")
        if page:
            print(page[:1500])

    print("\n===== Swiss Rowing")
    page = fetch(START["swissrowing"])
    if page:
        found = show(START["swissrowing"], page, r"/verband/ruderclubs/[^/]+", lines=40)
        clubs = [u for u, _ in found if re.search(r"/verband/ruderclubs/[^/?]+/?$", u)]
        for u in clubs[:3]:
            p = fetch(u)
            if p:
                show(u, p, lines=80)
                for m in re.findall(r"(?s)<script[^>]*ld\+json[^>]*>(.*?)</script>", p):
                    print("  ld+json:", m.strip()[:800])
                for m in re.findall(r'data-(?:lat|lng|lon|latitude|longitude)="[^"]+"', p)[:5]:
                    print("  coords attr:", m)
        for u, _ in found:
            if LEGAL.search(u):
                p = fetch(u)
                if p:
                    show(u, p, lines=120)
                break

    print("\n===== Austria")
    page = fetch(START["oerv"])
    if page:
        found = show(START["oerv"], page, r"(?i)verein|club|landesverb|verband", lines=30)
        for u, _ in found:
            if LEGAL.search(u):
                p = fetch(u)
                if p:
                    show(u, p, lines=120)
                break
    for u in EXTRA:
        p = fetch(u)
        if p:
            show(u, p, r"(?i)verein|club|ruder|rv|rc", lines=80)
    return 0


if __name__ == "__main__":
    sys.exit(main())
