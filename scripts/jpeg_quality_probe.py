#!/usr/bin/env python3
"""Compare JPEG qualities for the satellite pictures against the lossless original.

Fetches each lake's clearest picture (and the middle 10 m tile for big lakes)
as PNG, saves it as JPEG at 100 down to 70, and prints size and loss: PSNR
and SSIM against the PNG (higher is closer; SSIM 1 = identical).

Usage: CDSE_CLIENT_ID=... CDSE_CLIENT_SECRET=... python3 scripts/jpeg_quality_probe.py [save-dir]

With a directory, the lossless originals are saved there as PNG too.
"""

from __future__ import annotations

import io
import math
import sys
from pathlib import Path
from datetime import datetime, timedelta, timezone

import numpy as np
from PIL import Image

from rowfrog import outlines
from rowfrog.sources import sentinel2

LAKES = ["starnberger-see", "ammersee", "regattastrecke-oberschleissheim", "aussenalster", "grosser-wannsee", "maschsee"]
QUALITIES = [100, 95, 90, 85, 80, 75, 70]


def _box_mean(a: np.ndarray, r: int = 3) -> np.ndarray:
    """Mean over a (2r+1)² window, by an integral image (edges cropped)."""
    c = np.pad(a, ((1, 0), (1, 0))).cumsum(0).cumsum(1)
    k = 2 * r + 1
    return (c[k:, k:] - c[:-k, k:] - c[k:, :-k] + c[:-k, :-k]) / (k * k)


def ssim(a: np.ndarray, b: np.ndarray) -> float:
    c1, c2 = (0.01 * 255) ** 2, (0.03 * 255) ** 2
    ma, mb = _box_mean(a), _box_mean(b)
    va, vb = _box_mean(a * a) - ma**2, _box_mean(b * b) - mb**2
    cov = _box_mean(a * b) - ma * mb
    return float((((2 * ma * mb + c1) * (2 * cov + c2)) / ((ma**2 + mb**2 + c1) * (va + vb + c2))).mean())


def grey(im: Image.Image) -> np.ndarray:
    return np.asarray(im.convert("L"), dtype=np.float64)


def main() -> int:
    client = sentinel2.client()
    if client is None:
        print("No Copernicus account in CDSE_CLIENT_ID / CDSE_CLIENT_SECRET, or sign-in failed.")
        return 0
    save = Path(sys.argv[1]) if len(sys.argv) > 1 else None
    if save:
        save.mkdir(parents=True, exist_ok=True)
    today = datetime.now(timezone.utc).date()
    totals = {q: [0, 0.0, 0.0, 0] for q in QUALITIES}  # bytes, squared error, ssim sum, pixels
    png_total = 0
    count = 0
    for lake_id in LAKES:
        rings = outlines.load(lake_id)
        if not rings:
            print(f"{lake_id}: no outline")
            continue
        ring = rings[0]
        bbox, width, height = sentinel2.frame(ring)
        passes = sentinel2.cloud_by_day(client, ring, today - timedelta(days=sentinel2.SEARCH_DAYS), today)
        _, _, clearest = sentinel2.choose(passes)
        chosen = clearest or (passes[-1] if passes else None)
        if not chosen:
            print(f"{lake_id}: no pass")
            continue
        shots = [("picture", bbox, width, height)]
        sharp = sentinel2.sharp_size(bbox)
        if sharp:
            grid = sentinel2.tiles(bbox, *sharp)
            _, _, box, w, h = grid[len(grid) // 2]
            shots.append(("10 m tile", box, w, h))
        for name, box, w, h in shots:
            png = sentinel2.png(client, box, w, h, chosen.day)
            if save:
                (save / f"{lake_id}-{'tile' if name != 'picture' else 'picture'}-{chosen.day}.png").write_bytes(png)
            original = Image.open(io.BytesIO(png)).convert("RGB")
            ref = np.asarray(original, dtype=np.float64)
            ref_grey = grey(original)
            png_total += len(png)
            count += 1
            row = [f"{lake_id} {name} {w}x{h} {chosen.day} cloud {chosen.lake_cloud:.0%}: PNG {len(png) // 1024} KB"]
            for q in QUALITIES:
                out = io.BytesIO()
                original.save(out, "JPEG", quality=q, optimize=True)
                data = out.getvalue()
                back = Image.open(io.BytesIO(data)).convert("RGB")
                err = ((ref - np.asarray(back, dtype=np.float64)) ** 2).sum()
                s = ssim(ref_grey, grey(back))
                t = totals[q]
                t[0] += len(data)
                t[1] += err
                t[2] += s
                t[3] += ref.size
                row.append(f"{q}: {len(data) // 1024} KB ssim {s:.4f}")
            print(" | ".join(row))
    print(f"\nRESULT {count} pictures, PNG total {png_total} bytes")
    print("RESULT quality,bytes,percent_of_png,psnr_db,ssim_mean")
    for q in QUALITIES:
        size, err, s, px = totals[q]
        psnr = 10 * math.log10(255**2 / (err / px)) if err else float("inf")
        print(f"RESULT {q},{size},{100 * size / png_total:.1f},{psnr:.2f},{s / count:.4f}")
    print(f"Requests: {sentinel2.requests_made}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
