import { test } from "node:test";
import assert from "node:assert/strict";
import { conditionData, dataAt, conditionDetail } from "../public/app/values.js";
import { cover, tileFor, frameIndex, frames, gridValue, pixel, LAYERS, layerFor } from "../public/app/weathermap.js";
import { detailTime } from "../public/app/chart.js";

const at = (h) => `2026-10-26T${String(h).padStart(2, "0")}:00:00Z`;
const hourAt = (h, extra = {}) => ({ time: at(h), temperatureC: 10 + h / 2, windSpeedMs: 3, windGustMs: 5, windFromDeg: 270, pressureHpa: 1010, ...extra });

function sampleForecast() {
  const hours = [10, 11, 12, 13].map((h) => hourAt(h));
  const outlook = [13, 12, 11, 10, 9].map((h) => hourAt(h, { uvIndex: h / 4 }));
  return { hours, outlook };
}

test("the timeline is sorted and the shown hour borrows the outlook's UV index", () => {
  const f = sampleForecast();
  const d = conditionData(f, f.hours[1]);
  assert.deepEqual(d.timeline.map((x) => x.time), [9, 10, 11, 12, 13].map(at));
  assert.equal(d.now.uvIndex, 11 / 4);
  assert.equal(d.x(at(13)), 2);
  assert.deepEqual(d.points((x) => x.temperatureC).map((p) => p.x), [-2, -1, 0, 1, 2]);
});

test("the big value follows the chart's line to the nearest hour", () => {
  const f = sampleForecast();
  const d = conditionData(f, f.hours[0]);
  assert.equal(dataAt(d, 0.3), d);
  assert.equal(dataAt(d, 1.6).now.time, at(12));
  assert.equal(dataAt(d, -1).now.time, at(9));
});

test("every value builds a page", () => {
  const f = sampleForecast();
  const d = conditionData(f, f.hours[0]);
  for (const c of ["temperature", "wind", "pressure", "visibility", "precipitation"]) {
    const page = conditionDetail(c, d);
    assert.ok(page.value != null, c);
  }
});

const index = {
  columns: 150, rows: 130, arrowStep: 5,
  tiles: [
    { id: "a", west: 6, east: 12, south: 46, north: 50 },
    { id: "b", west: 9, east: 15, south: 46, north: 50 },
    { id: "c", west: 9, east: 15, south: 48, north: 52 },
  ],
};

test("each patch of the screen is drawn by one tile only", () => {
  const drawn = cover(index, { west: 10, east: 13, south: 47, north: 49 });
  const patches = drawn.flatMap((x) => x.patches.map((p) => `${p.west},${p.south}`));
  assert.equal(new Set(patches).size, patches.length);
  assert.ok(patches.includes("10.5,47"));
  assert.equal(tileFor(index, { lat: 47.9, lon: 7.5 }).id, "a");
  assert.equal(tileFor(index, { lat: 47.9, lon: 13 }).id, "b");
  assert.equal(tileFor(index, { lat: 40, lon: 11 }), null);
});

test("grid pixels and values, with 255 as no data", () => {
  const p = pixel(index.tiles[0], { lat: 49.99, lon: 6.01 }, 150, 130);
  assert.deepEqual(p, { row: 0, column: 0 });
  const grid = { columns: 2, rows: 1, encoding: { offset: -10, scale: 0.5 }, bytes: new Uint8Array([20, 255, 40, 0]) };
  assert.equal(gridValue(grid, 0, 0, 0), 0);
  assert.equal(gridValue(grid, 0, 0, 1), null);
  assert.equal(gridValue(grid, 1, 0, 0), 10);
});

test("model frames start at the hour now, and UV links by day", () => {
  const now = new Date(at(11).replace(":00:00Z", ":30:00Z"));
  const list = frames(LAYERS[layerFor("wind")], { hours: [9, 10, 11, 12].map(at) }, now);
  assert.deepEqual(list.map((x) => x.toISOString().slice(11, 13)), ["11", "12"]);
  assert.equal(frameIndex(LAYERS.wind, list, new Date(at(12))), 1);
  const days = [new Date("2026-10-26T00:00:00Z"), new Date("2026-10-27T00:00:00Z")];
  assert.equal(frameIndex(LAYERS.uv, days, new Date("2026-10-26T23:00:00Z")), 0);
});

test("the map follows the chart when linked and keeps its own time when not", () => {
  const time = detailTime(true);
  time.mapHours = [0, 1, 2, 3];
  time.setChart(2.2);
  assert.equal(time.mapFrameHour, 2);
  time.setLinked(false);
  time.setMap(3);
  assert.equal(time.hour, 2);
  assert.equal(time.mapFrameHour, 3);
  time.setLinked(true);
  time.setChart(9);
  assert.equal(time.mapOutOfRange, true);
});
