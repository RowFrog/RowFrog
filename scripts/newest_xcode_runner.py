"""Picks the GitHub macOS runner label whose default Xcode is the newest released
one, so the deciding CI job moves to Xcode 28 and later by itself (owner,
2026-10-30). Reads the runner-images README and each image's readme; an image
counts only when its default Xcode is a final release (not beta or RC), and
deprecated images are skipped. Prints `runner=<label>` and `xcode=<version>`
for $GITHUB_OUTPUT. Falls back to FALLBACK when GitHub's pages can't be read.

Run: python3 scripts/newest_xcode_runner.py [README.md image-readme-dir]
(with no arguments it fetches the pages from GitHub)."""

import re
import sys
import urllib.request
from pathlib import Path

FALLBACK = ("xcode-27", "27")
RAW = "https://raw.githubusercontent.com/actions/runner-images/main/"


def fetch(path: str, local: Path | None) -> str:
    if local:
        return (local / Path(path).name).read_text()
    with urllib.request.urlopen(RAW + path, timeout=30) as response:
        return response.read().decode()


def default_xcode(image_readme: str) -> tuple[int, ...] | None:
    """The default Xcode's version, or None when it is a beta or RC."""
    for line in image_readme.split("### Xcode", 1)[-1].splitlines():
        cells = [c.strip() for c in line.strip().strip("|").split("|")]
        if cells and cells[0].endswith("(default)"):
            if re.search(r"beta|release.candidate|\brc\b", line, re.I):
                return None
            return tuple(int(n) for n in re.findall(r"\d+", cells[0]))
    return None


def candidates(readme: str, local: Path | None):
    links = dict(re.findall(r"^\[([^\]]+)\]: \S+/(images/macos/\S+\.md)$", readme, re.M))
    for row in readme.splitlines():
        if not row.startswith("|") or "deprecated" in row.lower():
            continue
        ref = re.search(r"\[([^\]]+)\] \|\s*$", row)
        if not ref or ref.group(1) not in links:
            continue
        # A standard runner label: not the paid -large/-xlarge ones, not the moving -latest.
        labels = [l for l in re.findall(r"`([^`]+)`", row) if not re.search(r"large|latest", l)]
        if not labels:
            continue
        version = default_xcode(fetch(links[ref.group(1)], local))
        if version:
            yield version, "preview" not in row.lower(), labels[0]


def main() -> int:
    local = Path(sys.argv[2]) if len(sys.argv) > 2 else None
    try:
        readme = Path(sys.argv[1]).read_text() if local else fetch("README.md", None)
        # Newest default Xcode first; on a tie a regular image beats a preview.
        version, _, label = max(candidates(readme, local))
        xcode = ".".join(map(str, version))
    except Exception as error:  # noqa: BLE001 - any failure keeps CI on the known runner
        print(f"Could not read the runner list ({error}); using {FALLBACK[0]}", file=sys.stderr)
        label, xcode = FALLBACK
    print(f"runner={label}")
    print(f"xcode={xcode}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
