#!/usr/bin/env python3
"""Look at the club pages of Swiss Rowing and the Austrian rowing federation.

Usage (from the repository root):
    python3 scripts/probe_federations.py

Prints what the pages hold (raw markup around club entries, the scripts and
data endpoints behind the Austrian club list) so the import scripts can be
written against the real markup. Reads a handful of pages, one a second.
Imports nothing.
"""

from __future__ import annotations

import json
import re
import sys
import time

from import_drv import get, page_lines

SWISS = "https://www.swissrowing.ch/de/verband/ruderclubs"
AUSTRIA = "https://www.rudern.at/vereine/"


def fetch(url: str) -> str | None:
    time.sleep(1.0)
    try:
        page = get(url)
    except Exception as err:  # noqa: BLE001 - a probe reports every failure
        print(f"  FAILED {url}: {err}")
        return None
    print(f"  ok {url}: {len(page)} bytes")
    return page


def around(page: str, needle: str, before: int = 600, after: int = 900) -> None:
    i = page.find(needle)
    print(f"  --- around {needle!r} (at {i})")
    if i >= 0:
        print(page[max(0, i - before) : i + after])


def main() -> int:
    print("===== Swiss Rowing")
    page = fetch(SWISS)
    if page:
        around(page, "Basler Ruder-Club")
        hrefs = sorted(set(re.findall(r'href="([^"]*ruderclubs[^"]*)"', page)))
        print(f"  {len(hrefs)} hrefs with 'ruderclubs':", hrefs[:120])
        club = next((h for h in hrefs if h.rstrip("/").count("/") >= 4), None)
        if club:
            url = club if club.startswith("http") else "https://www.swissrowing.ch" + club
            p = fetch(url)
            if p:
                for l in page_lines(p)[:120]:
                    print("   ", l[:200])
                around(p, "Gründung", 300, 1500)
        p = fetch("https://www.swissrowing.ch/de/impressum")
        if p:
            for l in page_lines(p)[:80]:
                print("   ", l[:300])

    print("\n===== Austria")
    page = fetch(AUSTRIA)
    if page:
        around(page, "Bundesland ausw", 1500, 4000)
        for src in sorted(set(re.findall(r'<script[^>]+src="([^"]+)"', page))):
            print("  script:", src)
        for m in re.findall(r"(?i)[\"'](https?://[^\"']*(?:json|ajax|api)[^\"']*)[\"']", page)[:40]:
            print("  endpoint:", m)
        for s in re.findall(r"(?s)<script(?![^>]*src)[^>]*>(.*?)</script>", page):
            if re.search(r"(?i)verein|bundesland|\$\{u\}", s):
                print("  inline script:", s[:3000])
    for url in (
        "https://rudern.at/wp-json/wp/v2/types",
        "https://rudern.at/wp-json/",
    ):
        p = fetch(url)
        if p:
            try:
                d = json.loads(p)
                if "routes" in d:
                    print("  routes:", [r for r in d["routes"] if not r.startswith("/wp/v2/") or "verein" in r or "club" in r][:200])
                else:
                    print("  ", json.dumps({k: v.get("rest_base") for k, v in d.items()}, ensure_ascii=False))
            except (ValueError, AttributeError):
                print(p[:2000])
    p = fetch("https://rudern.at/wp-sitemap.xml")
    if p:
        print(p[:3000])
    return 0


if __name__ == "__main__":
    sys.exit(main())
