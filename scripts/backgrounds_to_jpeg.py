"""Turns the PNGs from draw_backgrounds.mjs into the app's JPEG backgrounds.
    python3 scripts/backgrounds_to_jpeg.py <png-dir>"""

import sys
from pathlib import Path

from PIL import Image

src = Path(sys.argv[1])
dest = Path("ios/RowFrog/Backgrounds")
dest.mkdir(parents=True, exist_ok=True)
for png in sorted(src.glob("*.png")):
    if png.stem in {"sheet", "crop"}:
        continue
    out = dest / f"bg-{png.stem}.jpg"
    Image.open(png).convert("RGB").save(out, quality=86, optimize=True, progressive=True)
    print(out, out.stat().st_size // 1024, "KB")
