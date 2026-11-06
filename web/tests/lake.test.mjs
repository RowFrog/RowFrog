import { test } from "node:test";
import assert from "node:assert/strict";
import { GROUPS, limitsFor } from "../public/app/logic.js";
import {
  decodeView, applyLakeLimits, shares, headline, stripes, stripesFall, RouteEdit, routePlanner, planRoute, bestStart, plansBetter, windRelation, pace,
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
  // The way-back choice opens a loop again, and closes it (RouteEdit.open, app #204).
  const open = RouteEdit.open(points);
  assert.equal(open.length, 3);
  assert.ok(!RouteEdit.isLoop(open));
  assert.equal(RouteEdit.open(open), open);
  assert.ok(RouteEdit.isLoop(RouteEdit.close(open)));
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

test("on a river the times count with the current (RoutePlanner, app #179)", () => {
  const view = sampleView();
  // The river runs east along the strip.
  view.section = { waterway: "river", flow: [[[11.3, 47.905], [11.33, 47.905]]] };
  const down = routePlanner(view, [{ lat: 47.905, lon: 11.301 }, { lat: 47.905, lon: 11.329 }], false);
  const up = routePlanner(view, [{ lat: 47.905, lon: 11.329 }, { lat: 47.905, lon: 11.301 }], false);
  const start = new Date("2026-10-26T10:00:00Z");
  const still = planRoute(down, start, 150).end - start;
  const downstream = planRoute(down, start, 150, 1).end - start;
  const upstream = planRoute(up, start, 150, 1);
  assert.ok(downstream < still && upstream.end - start > still);
  assert.equal(upstream.currentMs, 1);
  assert.equal(upstream.noHeadway, false);
  // Faster than the boat: hardly any headway upstream.
  assert.equal(planRoute(up, start, 150, 4).noHeadway, true);
  // Without a section (a lake) the current is ignored.
  delete view.section;
  const lake = routePlanner(view, [{ lat: 47.905, lon: 11.301 }, { lat: 47.905, lon: 11.329 }], false);
  assert.equal(planRoute(lake, start, 150, 1).end - start, still);
  assert.equal(planRoute(lake, start, 150, 1).currentMs, null);
});

test("whole-lake stripes cross the lake's long side (LakeView.stripesFall)", () => {
  // A course 3 km long and 100 m wide near Oberschleißheim, turned `degrees` from east.
  const course = (degrees) => {
    const lat = 48.25, squeeze = Math.cos((lat * Math.PI) / 180), c = Math.cos((degrees * Math.PI) / 180), s = Math.sin((degrees * Math.PI) / 180);
    const corners = [[-0.0135, -0.00045], [0.0135, -0.00045], [0.0135, 0.00045], [-0.0135, 0.00045]];
    return [corners.map(([x, y]) => [11.5 + (x * c - y * s) / squeeze, lat + x * s + y * c])];
  };
  assert.equal(stripesFall(course(45)), true, "lies along the usual stripes");
  assert.equal(stripesFall(course(60)), true);
  assert.equal(stripesFall(course(135)), false, "already crosses them");
  assert.equal(stripesFall(course(90)), false, "north-south keeps the usual stripes");
  assert.equal(stripesFall(course(0)), false, "east-west keeps the usual stripes");
  assert.equal(stripesFall([[[11.49, 48.24], [11.51, 48.24], [11.51, 48.253], [11.49, 48.253]]]), false);
  assert.equal(stripesFall([]), false);
});

test("club pins split off the clubhouse only for a set launch point 30 m or more away", async () => {
  const { clubhouseOf, shouldSplit } = await import("../public/app/lake.js");
  const launchPoint = { lat: 47.99667, lon: 11.34745 };
  const far = { lat: 47.99767, lon: 11.34745 }; // about 111 m north
  const near = { lat: 47.99677, lon: 11.34745 }; // about 11 m
  assert.deepEqual(clubhouseOf({ launchPoint, launchPointSet: true, clubhouse: far }), far);
  assert.equal(clubhouseOf({ launchPoint, launchPointSet: true, clubhouse: near }), null);
  assert.equal(clubhouseOf({ launchPoint, launchPointSet: false, clubhouse: far }), null);
  assert.equal(clubhouseOf({ launchPoint, launchPointSet: true, clubhouse: null }), null);
  assert.equal(clubhouseOf(undefined), null);
  // Apart from 48 px, together again under 40 px.
  assert.equal(shouldSplit(47, false), false);
  assert.equal(shouldSplit(48, false), true);
  assert.equal(shouldSplit(41, true), true);
  assert.equal(shouldSplit(39, true), false);
});

test("a tapped spot names hail, a thunderstorm or heavy rain, the strongest only (app #388)", async () => {
  const { pointExtra, fogLight, spotProbe } = await import("../public/app/lake.js");
  assert.equal(fogLight(300), "red");
  assert.equal(fogLight(800), "amber");
  assert.equal(fogLight(20000), "green");
  assert.equal(pointExtra({ other: "green", storm: "green", rainMm: 0, hail: false, visM: 20000 }), null);
  assert.deepEqual(pointExtra({ hail: true, storm: "red", rainMm: 9 }), { kind: "hail", light: "red" });
  assert.deepEqual(pointExtra({ hail: false, storm: "amber", rainMm: 9 }), { kind: "thunderstorm", light: "amber" });
  assert.deepEqual(pointExtra({ hail: false, storm: "green", rainMm: 4 }), { kind: "rain", light: "amber", mm: 4 });
  assert.equal(pointExtra({ hail: false, storm: "green", rainMm: 3.9 }), null);
  // Older backends: fog explains the light, or else a thunderstorm did.
  assert.equal(pointExtra({ other: "red", visM: 300 }), null);
  assert.deepEqual(pointExtra({ other: "red", visM: 800 }), { kind: "thunderstorm", light: "red" });
  const view = { waterC: 15, grid: { cellPoint: [0] } };
  const hour = { wavesCm: [40], lakeWide: { reasons: [] }, wind: [{ speedMs: 3, gustMs: 9, visM: 800, storm: "green", rainMm: 0, hail: false }] };
  const p = spotProbe(view, hour, 0, { boat: { id: "small", name: "", type: "racing", class: "1x" }, custom: {} });
  assert.equal(p.waves.m, 0.4);
  assert.equal(p.visibility.light, "amber");
  assert.equal(p.extra, null);
});

