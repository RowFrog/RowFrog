# 24. Satellite card opens on the clearest picture when the club is covered

- Date: 2026-11-12
- Status: decided (owner, 12:49 CET)
- Where: backend `scripts/publish_static.py` (`club_areas`, `_club_cloud`), `backend/rowfrog/sources/sentinel2.py` (`cloud_on`); app `SatellitePicture.startKind`; website `startKind` in `web/public/app/satellite.js`

## Decision

The satellite card on a club page opens on "Clearest" instead of "Latest" when the latest picture is covered over the club and around it, from 90 % cloud. The club's area is the square of about 2 x 2 km around its launch point. The backend measures cloud there (Copernicus scene classes, the same as for the whole lake) once per new pass for each club in use, and publishes it as `clubCloud` on the latest picture. Where no number exists for the club yet, or for water without an outline, the share over the whole lake (or the club's own picture area) decides. Nothing changes when the clearest picture is the same pass, or when there is none. "Latest" stays one tap away, and a picked picture stays picked.

## Why

A fully white picture (for example Starnberger See on 8 Nov) shows nothing useful. The whole-lake share can hide that the club's own end is clear, or covered, on a long lake.

## Cost

One Copernicus statistics request per club in use, only when a lake gets a new latest pass.
