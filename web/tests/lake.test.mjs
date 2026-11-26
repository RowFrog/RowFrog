import { test } from "node:test";
import assert from "node:assert/strict";
import { GROUPS, limitsFor } from "../public/app/logic.js";
import {
  decodeView, applyLakeLimits, shares, headline, stripes, stripesFall, RouteEdit, routePlanner, planRoute, bestStart, plansBetter, windRelation, pace,
  lakeWideAt, withDaylightNow, fineLight, shoreDistance, zoneNotes, zoneNoteText, zoneValues, meanFrom, arrowGlyph,
} from "../public/app/lake.js";

// A 3×1 strip of water running east, one forecast point, two zones.
function sampleView({ speeds = [3, 3], lakeWide = { light: "green", reasons: [] } } = {}) {
  return decodeView({
    generatedAt: "2026-10-26T10:00:00Z", waterC: 14,
    grid: { south: 47.9, west: 11.3, dLat: 0.01, dLon: 0.01, cols: 3, rows: 1, cells: [0, 1, 2], cellPoint: [0, 0, 0], cellZone: [0, 0, 1] },
    zones: ["west", "east"], outline: [], clubs: [],
    points: [{ lat: 47.905, lon: 11.315 }],
    hours: speeds.map((s, i) => ({
      time: `2026-10-26T${String(10 + i).padStart(2, "0")}:00:00Z`, lakeWide, lights: "000", wavesMm: [50, 100, 200],
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

test("club pins move onto the club's place on the map, oars only for a set launch point", async () => {
  const { clubhouseOf, showsOars, shouldSplit } = await import("../public/app/lake.js");
  const launchPoint = { lat: 47.99667, lon: 11.34745 };
  const far = { lat: 47.99767, lon: 11.34745 }; // about 111 m north
  const near = { lat: 47.99677, lon: 11.34745 }; // about 11 m
  const place = { lat: 47.99807, lon: 11.34745, name: "Ruderclub" }; // about 44 m north of `far`
  const placeFar = { lat: 47.99907, lon: 11.34745, name: "Ruderclub" }; // about 155 m north of `far`
  assert.deepEqual(clubhouseOf({ launchPoint, launchPointSet: true, clubhouse: far }), far);
  assert.equal(clubhouseOf({ launchPoint, launchPointSet: true, clubhouse: near }), null);
  assert.equal(clubhouseOf({ launchPoint, launchPointSet: true, clubhouse: null }), null);
  assert.equal(clubhouseOf(undefined), null);
  // The map's place wins near the checked clubhouse; a checked clubhouse far from it keeps the pin.
  assert.deepEqual(clubhouseOf({ launchPoint, launchPointSet: true, clubhouse: far, mapPlace: place }), { lat: place.lat, lon: place.lon });
  assert.deepEqual(clubhouseOf({ launchPoint, launchPointSet: true, clubhouse: far, mapPlace: placeFar }), far);
  // Clubs with no launch point set move onto their place too, without oars.
  assert.deepEqual(clubhouseOf({ launchPoint, launchPointSet: false, mapPlace: place }), { lat: place.lat, lon: place.lon });
  assert.equal(clubhouseOf({ launchPoint, launchPointSet: false, mapPlace: { ...near, name: "x" } }), null);
  assert.equal(showsOars({ launchPointSet: false }), false);
  assert.equal(showsOars({ launchPointSet: true }), true);
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
  const hour = { wavesMm: [400], lakeWide: { reasons: [] }, wind: [{ speedMs: 3, gustMs: 9, visM: 800, storm: "green", rainMm: 0, hail: false }] };
  const p = spotProbe(view, hour, 0, { boat: { id: "small", name: "", type: "racing", class: "1x" }, custom: {} });
  assert.equal(p.waves.m, 0.4);
  assert.equal(p.visibility.light, "amber");
  assert.equal(p.extra, null);
});


// The lake view's "now" goes by this minute too (owner, 12 Nov 2026: "sun down" at 07:45 with
// sunrise at 07:15), and other whole-lake reasons stay (LakeWide.at, DaylightRuleTests).
test("the lake view's now goes by this minute's daylight", () => {
  const at = (hm) => Date.parse(`2026-11-12T${hm}:00+01:00`);
  const days = [{ sunrise: at("07:15"), sunset: at("16:41") }];
  const dark = { light: "red", reasons: [{ condition: "daylight", light: "red" }] };
  assert.deepEqual(lakeWideAt(dark, at("07:45"), days), { light: "green", reasons: [] });
  assert.equal(lakeWideAt(dark, at("07:10"), days).light, "red");
  const foggy = { light: "red", reasons: [{ condition: "daylight", light: "red" }, { condition: "weather_warning", light: "red" }] };
  assert.deepEqual(lakeWideAt(foggy, at("07:45"), days).reasons.map((r) => r.condition), ["weather_warning"]);
  assert.equal(lakeWideAt(foggy, at("07:45"), days).light, "red");
  assert.deepEqual(lakeWideAt(dark, at("16:10"), days), { light: "amber", reasons: [{ condition: "sunset_soon", light: "amber" }] });
  const calm = { light: "green", reasons: [] };
  assert.equal(lakeWideAt(calm, at("07:45"), days), calm);
  // Only the hour already begun changes, and only with the club's sun days.
  const view = { hours: [{ time: "2026-11-12T07:00:00+01:00", lakeWide: dark }, { time: "2026-11-12T08:00:00+01:00", lakeWide: dark }] };
  const now = new Date(at("07:45"));
  assert.deepEqual(withDaylightNow(view, days, now).hours.map((h) => h.lakeWide.light), ["green", "red"]);
  assert.equal(withDaylightNow(view, [], now), view);
});

// The rowing light drawn finer than the cells (LakeRaster.fineLight, owner's pick B, 12 Nov 2026): the edge
// between green and amber follows the waves blended between the cell centres, not the squares.
test("the fine rowing light follows the blended values", () => {
  const view = sampleView();
  view.hours[0].wavesMm = [50, 100, 300];
  const limits = limitsFor(GROUPS[0], { waveAmber: 0.15 });
  const fine = fineLight(view, view.hours[0], limits);
  assert.equal(fine.scale, 8);
  assert.equal(fine.width, 24);
  assert.equal(fine.height, 8);
  const at = (x, y = 4) => fine.data.slice((y * fine.width + x) * 4, (y * fine.width + x) * 4 + 3).join(",");
  const green = "52,199,89";
  const amber = "255,149,0";
  // The middle cell (pixels 8 to 15): green up to the blended 15 cm, amber after it.
  assert.equal(at(4), green);
  assert.equal(at(13), green);
  assert.equal(at(14), amber);
  assert.equal(at(20), "255,59,48"); // 30 cm is over the red limit of 25 cm
  // A thunderstorm stays with its cell.
  view.hours[0].wind[0] = { ...view.hours[0].wind[0], storm: "red", visM: 20000, rainMm: 0, hail: false };
  assert.equal(at(4), green);
  const stormy = fineLight(view, view.hours[0], limits);
  assert.equal(stormy.data.slice(16, 19).join(","), "255,59,48");
  // Older backends without the light per point: none.
  view.hours[0].wind[0] = { ...view.hours[0].wind[0], other: null };
  assert.equal(fineLight(view, view.hours[0], limits), null);
});

// Starnberger See, 12 Nov 2026, 23:00: 19 cells at "25 cm" were red from the server (25.4 cm over the 0.25 m limit)
// but amber by the rounded waves, so each stayed red as a hard square on the zoomed-in map (owner's shot).
test("a cell red only by the waves' rounding is not kept as a square", () => {
  const view = sampleView();
  const hour = view.hours[0];
  hour.wavesMm = [200, 250, 200];
  hour.lights = ["amber", "red", "amber"];
  const limits = limitsFor(GROUPS[0], { waveAmber: 0.15 });
  const fine = fineLight(view, hour, limits);
  const at = (x) => fine.data.slice((4 * fine.width + x) * 4, (4 * fine.width + x) * 4 + 3).join(",");
  for (const x of [8, 11, 12, 15]) assert.equal(at(x), "255,149,0", `pixel ${x} of the middle cell is amber, not a red square`);
  // A cell the server makes red for more than rounding still stays red.
  hour.wavesMm = [200, 249, 200];
  const kept = fineLight(view, hour, limits);
  assert.equal(kept.data.slice((4 * kept.width + 12) * 4, (4 * kept.width + 12) * 4 + 3).join(","), "255,59,48");
});

test("fog along both shores: each part says why and where, and the headline names the shore (app lake-notes)", () => {
  // 5 x 4 squares, all water: the outer ring red from fog, the six inner ones green (LakeViewTests).
  const lights = Array.from({ length: 20 }, (_, i) => ([6, 7, 8, 11, 12, 13].includes(i) ? "0" : "2")).join("");
  const view = decodeView({
    generatedAt: "2026-11-12T09:00:00Z", name: "Fog See",
    grid: { south: 47.8, west: 11.3, dLat: 0.01, dLon: 0.01, cols: 5, rows: 4, cells: [...Array(20).keys()], cellPoint: Array(20).fill(0),
      cellZone: [1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0] },
    zones: ["north", "south"], outline: [[[11.295, 47.795], [11.345, 47.795], [11.345, 47.835], [11.295, 47.835]]], clubs: [],
    points: [{ lat: 47.815, lon: 11.32 }],
    hours: [{ time: "2026-11-12T09:00:00Z", lakeWide: { light: "green", reasons: [] }, lights, wavesMm: Array(20).fill(10),
      wind: [{ speedMs: 1, gustMs: 2, fromDeg: 315, other: 2, visM: 300, storm: 0 }],
      zones: [{ light: "red", maxWaveM: 0.01 }, { light: "red", maxWaveM: 0.01 }] }],
  });
  const hour = view.hours[0];
  const limits = { boat: GROUPS[0], custom: {} };
  assert.deepEqual(shoreDistance(view.grid), [1, 1, 1, 1, 1, 1, 2, 2, 2, 1, 1, 2, 2, 2, 1, 1, 1, 1, 1, 1]);
  const notes = zoneNotes(view, hour, limits);
  assert.equal(notes.length, 3, "two parts and the whole lake");
  assert.deepEqual(notes[0], { light: "red", cause: "Fog", place: "shore", rest: "green" });
  assert.deepEqual(zoneNoteText(notes[0]), ["%@ near the shore, open water clear", "Fog"]);
  const values = zoneValues(view, hour, 0, limits);
  assert.deepEqual([values.waves.light, values.wind.light, values.visibility.light], ["green", "green", "red"]);
  assert.equal(values.waves.m, 0.01);
  assert.deepEqual(headline(view, hour, limits), ["%@ near the shore: stay ashore", "Fog"]);
  // Without the limits (older callers) the headline stays the whole-lake one.
  assert.deepEqual(headline(view, hour), ["Stay ashore on the whole lake"]);
});

test("a part's wind direction is the speed-weighted vector mean, and its arrow glyph (LakeZoneReading.meanFrom, arrowGlyph)", () => {
  assert.equal(meanFrom([]), null);
  assert.equal(meanFrom([{ fromDeg: 90, speedMs: 0 }, { fromDeg: null, speedMs: 3 }]), null, "calm or no direction counts for nothing");
  assert.ok(Math.abs(meanFrom([{ fromDeg: 350, speedMs: 2 }, { fromDeg: 10, speedMs: 2 }])) < 1e-9 || Math.abs(meanFrom([{ fromDeg: 350, speedMs: 2 }, { fromDeg: 10, speedMs: 2 }]) - 360) < 1e-9, "across north");
  assert.ok(Math.abs(meanFrom([{ fromDeg: 0, speedMs: 1 }, { fromDeg: 90, speedMs: 3 }]) - 71.565) < 0.01, "the stronger wind weighs more");
  assert.deepEqual([0, 45, 90, 180, 270, 337, 338, -45, 720].map(arrowGlyph), ["↑", "↗", "→", "↓", "←", "↖", "↑", "↖", "↑"]);
});

// Starnberger See, 26 Nov 2026, 12:00: cells of exactly "15 cm" next to each other blended to 0.1499999… at one
// pixel per cell, a green dot in the amber under the 0.15 m limit (owner's zoomed-in lake map).
test("cells exactly on a limit blend to it, without green dots", () => {
  const view = decodeView({
    generatedAt: "2026-11-26T11:00:00Z", waterC: 6,
    grid: { south: 47.9, west: 11.3, dLat: 0.01, dLon: 0.01, cols: 3, rows: 3, cells: [0, 1, 2, 3, 4, 5, 6, 7, 8],
            cellPoint: Array(9).fill(0), cellZone: Array(9).fill(0) },
    zones: ["all"], outline: [], clubs: [], points: [{ lat: 47.915, lon: 11.315 }],
    hours: [{
      time: "2026-11-26T11:00:00Z", lakeWide: { light: "green", reasons: [] }, lights: "111111111", wavesMm: Array(9).fill(150),
      wind: [{ speedMs: 2, gustMs: 4, fromDeg: 0, other: 0 }], zones: [{ light: "amber", maxWaveM: 0.15 }],
    }],
  });
  const limits = limitsFor(GROUPS[0], { waveAmber: 0.15 });
  const fine = fineLight(view, view.hours[0], limits);
  const green = [];
  for (let p = 0; p < fine.width * fine.height; p++) if (fine.data.slice(p * 4, p * 4 + 3).join(",") === "52,199,89") green.push(p);
  assert.deepEqual(green, []);
});
