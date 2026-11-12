// The website reads the API's fields, never ones the app works out for itself
// (operatorName, satelliteName, when, summary): those it works out the same way.
import { test } from "node:test";
import assert from "node:assert/strict";
import { stationOperator, satelliteName, satelliteWhen } from "../public/app/values.js";
import { iceSatelliteSummary, iceDetail } from "../public/app/shared.js";

test("a water station names who runs it, from its network", () => {
  assert.equal(stationOperator({ network: "gkd" }), "Gewässerkundlicher Dienst Bayern (LfU)");
  assert.equal(stationOperator({ network: "pegelonline" }), "PEGELONLINE, the federal waterways and shipping administration (WSV)");
  assert.equal(stationOperator({ network: "bafu" }), "Swiss Federal Office for the Environment (BAFU)");
  assert.equal(stationOperator(undefined), "Gewässerkundlicher Dienst Bayern (LfU)");
});

test("a water temperature satellite is named and dated as in the app", () => {
  assert.equal(satelliteName({ source: "landsat", platform: "landsat-9" }), "Landsat 9");
  assert.equal(satelliteName({ source: "landsat" }), "Landsat");
  assert.equal(satelliteName({ source: "copernicus" }), "Copernicus (Sentinel-3)");
  assert.match(satelliteWhen({ date: "2026-10-05", from: "2026-10-01", to: "2026-10-10" }), / – /);
  assert.doesNotMatch(satelliteWhen({ date: "2026-10-05" }), / – /);
});

test("the satellite ice line says open water or the share of ice", () => {
  assert.match(iceSatelliteSummary({ date: "2026-01-20", seenShare: 0.8, iceShare: 0.05 }), /^Satellite, .+: open water$/);
  assert.match(iceSatelliteSummary({ date: "2026-01-20", seenShare: 0.8, iceShare: 0.6 }), /^Satellite, .+: 60 % ice$/);
  assert.match(iceDetail({ basis: "satellite", satellite: { date: "2026-01-20", seenShare: 1, iceShare: 0.6 } }), /60 % ice/);
  assert.equal(iceDetail({ basis: "season" }), "No ice this time of year");
});
