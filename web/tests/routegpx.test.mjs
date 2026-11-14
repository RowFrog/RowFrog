// The GPX export; ios/RowFrogTests/RouteGPXTests.swift expects the same text from the app.
import { test } from "node:test";
import assert from "node:assert/strict";
import { gpxText, gpxFileName } from "../public/app/routegpx.js";
import { readTrack } from "../public/app/rowimport.js";

test("an out-and-back route writes the way back too", () => {
  const route = { name: "Ufer & <Insel>", lakeId: "starnberger-see", outAndBack: true,
    points: [{ lat: 47.9312345, lon: 11.3123456 }, { lat: 47.94, lon: 11.32 }, { lat: 47.95, lon: 11.31 }] };
  assert.equal(gpxText(route), `<?xml version="1.0" encoding="UTF-8"?>
<gpx version="1.1" creator="Row Frog" xmlns="http://www.topografix.com/GPX/1/1">
  <metadata><name>Ufer &amp; &lt;Insel&gt;</name></metadata>
  <trk>
    <name>Ufer &amp; &lt;Insel&gt;</name>
    <type>rowing</type>
    <trkseg>
      <trkpt lat="47.93123" lon="11.31235"/>
      <trkpt lat="47.94000" lon="11.32000"/>
      <trkpt lat="47.95000" lon="11.31000"/>
      <trkpt lat="47.94000" lon="11.32000"/>
      <trkpt lat="47.93123" lon="11.31235"/>
    </trkseg>
  </trk>
</gpx>
`);
});

test("the file name drops characters file systems refuse", () => {
  assert.equal(gpxFileName({ name: "A/B: C?" }), "A B  C.gpx");
  assert.equal(gpxFileName({ name: "  " }), "Route.gpx");
});

test("the export reads back as a track", () => {
  const text = gpxText({ name: "Kurz", outAndBack: false, points: [{ lat: 48, lon: 11.1 }, { lat: 48.01, lon: 11.12 }] });
  assert.equal(readTrack(new TextEncoder().encode(text).buffer).length, 2);
});
