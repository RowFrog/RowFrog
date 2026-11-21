# 0056. Where a pass took no picture, the satellite picture is grey and the "i" is filled

- Date: 2026-11-21
- Status: decided (owner, thread "Fix black wedge in satellite image", 21 Nov 2026: option A "grey area" 19:29 CET (18:29 UTC), placement option 2 "filled i" 19:34 CET (18:34 UTC); mock-ups https://claude.ai/artifact/WwsCnqSqnh4T9gXaVxDyTb and https://claude.ai/artifact/LaTMP9ynSWwBY9GCEgMhYD)
- Where: `backend/rowfrog/sources/sentinel2.py` (`PICTURE_SCRIPT`, `picture_from_png`), `scripts/publish_static.py` (`_picture_meta`: `gap`), `ios/RowFrog/SatellitePicture.swift` (`Shot.gap`, `SatelliteCaption`), `web/public/app/satellite.js` (`caption`, `wireControls`).

## Why

The Außenalster's latest picture (17 Nov) had a black wedge in its bottom right corner. The pass saw the whole lake, but its strip ended inside the picture's frame, which is wider than the lake (at least 4 x 3 km). The picture script ignored the "no data" mask, so those pixels came out black, which looks like a broken picture. On 21 Nov 7 of 293 published pictures had such a wedge.

## Decision

- The picture asks Sentinel Hub for the data mask too. Parts the pass did not photograph are drawn in soft grey diagonal stripes, never black. The tiles of the full-screen view get the same grey.
- The satellite file names the share of the picture that is grey as `gap` on that picture (only from 0.5 %).
- On a picture with a gap the "i" after the caption is filled and blue (app `info.circle.fill`, accent colour). Its message is titled "Grey area" and explains the gap first, then the usual Sentinel-2 text. On a picture without a gap the "i" and its message stay as they were.
- The caption stays one line, so the picture keeps its size when switching pictures (SatelliteCaption, owner 14 Nov 2026).
- The cloud share already counted only the photographed part of the lake; no change.
- Pictures published before this change keep their black wedge until a newer pass replaces them (no extra Copernicus requests).

## Turned down

- A second caption line "Grau: nicht aufgenommen": the card's height would change between pictures.
- Same "i", longer text only (option 1): nothing tells that this picture has something to explain.
- A label inside the grey area (option 3): more work, a third text style on the picture.
- Filling the gap from an earlier pass (B): one picture would show two days.
- Only passes that cover the whole frame (C): the latest picture gets days older and loses the news that the lake was cloudy.
