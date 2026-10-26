import { test } from "node:test";
import assert from "node:assert/strict";
import { GROUPS, limitsFor } from "../public/app/logic.js";
import {
  decodeView, applyLakeLimits, shares, headline, stripes, RouteEdit, routePlanner, planRoute, bestStart, plansBetter, windRelation, pace,
} from "../public/app/lake.js";

// A 3×1 strip of water running east, one forecast point, two zones.
function sampleView({ speeds = [3, 3], lakeWide = { light: "green", reasons: [] } } = {}) {
  return decodeView({
    generatedAt: "2026-10-26T10:00:00Z", waterC: 14,
    grid: { south: 47.9, west: 11.3, dLat: 0.01, dLon: 0.01, cols: 3, rows: 1, cells: [0, 1, 2], cellPoint: [0, 0, 0], cellZone: [0, 0, 1] },
    zones: ["west", "east"], outline: [], clubs: [],
    points: [{ lat: 47.905, lon: 11.315 }],
    hours: speeds.map((s, i) => ({
      time: `2026-10-26T${String(10 + i).padStart(2, "0")}:00:00Z`, lakeWide, lights: "000", wavesCm: [5, 10, 20],
      wind: [{ speedMs: s, gustMs: s + 2, fromDeg: 270, other: 0 }],
      zones: [{ light: "green", maxWaveM: 0.1 }, { light: "green", maxWaveM: 0.2 }],
    })),
  });
}

test("decodes the lights and the per-point light", () => {
  const view = sampleView();
  assert.deepEqual(view.hours[0].lights, ["green", "green", "green"]);
  assert.equal(view.hours[0].wind[0].other, "green");
});

test("colours the lake for a boat's own wind limit", () => {
  const view = sampleView({ speeds: [5, 5] });
  const own = limitsFor(GROUPS[0], { windAmber: 4 });
  const coloured = applyLakeLimits(view, own, false);
  assert.deepEqual(coloured.hours[0].lights, ["amber", "amber", "amber"]);
  assert.equal(coloured.hours[0].zones[1].light, "amber");
  assert.equal(applyLakeLimits(view, own, true), view);
});

test("shares, headline and stripes", () => {
  const view = sampleView();
  view.hours[0].lights = ["green", "green", "red"];
  view.hours[0].zones[1].light = "red";
  assert.deepEqual(shares(view.hours[0]), { green: 2 / 3, red: 1 / 3 });
  assert.deepEqual(headline(view, view.hours[0]), ["Calmest %@, roughest %@", "in the west", "in the east"]);
  assert.equal(stripes({ light: "red", reasons: [] }), "red");
  assert.equal(stripes({ light: "amber", reasons: [{ condition: "cold_water", light: "amber" }] }), null);
  assert.equal(stripes({ light: "amber", reasons: [{ condition: "daylight", light: "amber" }] }), "amber");
});

test("route edits keep the start and close loops", () => {
  const a = { lat: 47.9, lon: 11.3 };
  let points = [a];
  points = RouteEdit.add({ lat: 47.91, lon: 11.3 }, points);
  points = RouteEdit.add({ lat: 47.91, lon: 11.31 }, points);
  points = RouteEdit.add({ lat: 47.9001, lon: 11.3001 }, points);
  assert.ok(RouteEdit.isLoop(points));
  assert.equal(RouteEdit.remove(0, points), points);
  assert.equal(RouteEdit.remove(1, points).length, 2);
});

test("plans a route through the hours and finds a better start", () => {
  const view = sampleView({ speeds: [9, 2] });
  view.hours[0].lights = ["red", "red", "red"];
  const planner = routePlanner(view, [{ lat: 47.905, lon: 11.301 }, { lat: 47.905, lon: 11.329 }], true);
  assert.ok(planner.distanceM > 4000);
  const first = planRoute(planner, new Date("2026-10-26T10:00:00Z"), 135);
  assert.equal(first.worstLight, "red");
  assert.equal(first.stops[0].relation, "tail");
  const best = bestStart(planner, 135, new Date("2026-10-26T10:00:00Z"));
  assert.equal(best.start.toISOString(), "2026-10-26T11:00:00.000Z");
  assert.ok(plansBetter(best, first));
  assert.equal(windRelation(90, 90), "head");
  assert.equal(pace(135), "2:15");
});
