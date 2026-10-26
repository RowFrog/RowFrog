"""Temporary: wider Sentinel-2 frames around a few small waters, for the owner's mock-ups."""

import json
import math
import pathlib
from datetime import date

from rowfrog.sources import sentinel2

LAKES = {
    "kleiner-see": ((9.33358, 48.72413, 9.33379, 48.72429), "2026-10-12"),
    "neckar": ((9.33175, 48.62586, 9.33283, 48.62692), "2026-10-12"),
    "tegeler-hafen": ((13.2769, 52.59039, 13.28138, 52.5917), "2026-10-19"),
    "regattastrecke": ((9.49934, 51.29229, 9.50225, 51.29813), "2026-10-22"),
    "bertasee": ((6.78112, 51.40634, 6.7886, 51.41082), "2026-10-15"),
}
W_M, H_M = 4000, 3000  # 400 x 300 px at 10 m

out = pathlib.Path("mockups/tiny")
out.mkdir(parents=True, exist_ok=True)
client = sentinel2.client()
meta = {}
for lake, (b, day) in LAKES.items():
    lon, lat = (b[0] + b[2]) / 2, (b[1] + b[3]) / 2
    dlon = W_M / 2 / (111_320 * math.cos(math.radians(lat)))
    dlat = H_M / 2 / 110_540
    box = (lon - dlon, lat - dlat, lon + dlon, lat + dlat)
    (out / f"{lake}.jpg").write_bytes(sentinel2.jpeg(client, box, W_M // 10, H_M // 10, date.fromisoformat(day)))
    meta[lake] = {"bbox": box, "date": day}
(out / "meta.json").write_text(json.dumps(meta, indent=1))
print(meta)
