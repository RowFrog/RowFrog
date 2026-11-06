// Natural neighbour blending between a lake's forecast points (app #392, LakeInterpolationTests).
import test from "node:test";
import assert from "node:assert/strict";
import { naturalNeighbours, blendWind, lakeInterpolation } from "../public/app/interpolate.js";

const POINTS = [[0, 0], [2200, 300], [500, 2100], [2600, 2500], [1300, 4400], [-400, 3600]];
const nn = naturalNeighbours(POINTS, { west: -3000, south: -3000, east: 5000, north: 7000 });
let seed = 1;
const random = (a, b) => {
  seed = (seed * 16807) % 2147483647;
  return a + ((seed - 1) / 2147483646) * (b - a);
};
const blend = (w, values) => w.reduce((s, [i, x]) => s + x * values[i], 0);

test("weights are never negative and add up to one", () => {
  for (let n = 0; n < 300; n++) {
    const w = nn.weights([random(-2500, 4500), random(-2500, 6500)]);
    assert.ok(w.every(([, x]) => x >= 0));
    assert.ok(Math.abs(w.reduce((s, [, x]) => s + x, 0) - 1) < 1e-9);
  }
});

test("a spot on a point gets that point only", () => {
  assert.deepEqual(nn.weights(POINTS[3]), [[3, 1]]);
  const near = nn.weights([POINTS[3][0] + 1, POINTS[3][1]]);
  assert.ok(near.find(([i]) => i === 3)[1] > 0.99);
});

test("an even slope is reproduced inside the points, and blends stay between the lowest and highest point", () => {
  const values = POINTS.map(([x, y]) => 3 + 0.001 * x - 0.0005 * y);
  for (const spot of [[1200, 1500], [1500, 3000], [800, 900]]) {
    assert.ok(Math.abs(blend(nn.weights(spot), values) - (3 + 0.001 * spot[0] - 0.0005 * spot[1])) < 1e-6);
  }
  const rough = [4, 9.5, 2, 7, 11, 3];
  for (let n = 0; n < 300; n++) {
    const v = blend(nn.weights([random(-2500, 4500), random(-2500, 6500)]), rough);
    assert.ok(v >= 2 - 1e-9 && v <= 11 + 1e-9);
  }
});

test("blended wind stays between the points, takes the arrows' direction and visibility on a log scale", () => {
  const a = { speedMs: 4, gustMs: 6, fromDeg: 350, other: "green", visM: 300, storm: "green", rainMm: 0, hail: false };
  const b = { speedMs: 8, gustMs: 11, fromDeg: 10, other: "green", visM: 15000, storm: "green", rainMm: 0, hail: false };
  const w = blendWind([[0, 0.5], [1, 0.5]], [a, b], a);
  assert.ok(Math.abs(w.speedMs - 6) < 1e-9);
  assert.ok(Math.abs(w.gustMs - 8.5) < 1e-9);
  assert.ok(Math.min(w.fromDeg, 360 - w.fromDeg) < 5);
  assert.ok(Math.abs(w.visM - Math.sqrt(300 * 15000)) < 1);
  assert.equal(w.other, "green");
  // Hail stays with the nearest point and makes it red; rain from 4 mm amber.
  assert.equal(blendWind([[0, 0.5], [1, 0.5]], [a, b], { ...b, hail: true }).other, "red");
  assert.equal(blendWind([[0, 0.5], [1, 0.5]], [{ ...a, visM: 15000, rainMm: 6 }, { ...b, rainMm: 2 }], b).other, "amber");
});

test("a lake with one point copies it; every cell gets weights", () => {
  const grid = { south: 47.9, west: 11.3, dLat: 0.01, dLon: 0.01, cols: 3, rows: 3, cells: [0, 1, 4, 8] };
  const coord = (g, i) => ({ lat: g.south + Math.floor(g.cells[i] / g.cols) * g.dLat, lon: g.west + (g.cells[i] % g.cols) * g.dLon });
  assert.deepEqual(lakeInterpolation(grid, [{ lat: 47.91, lon: 11.31 }], coord).cellWeights, [[[0, 1]], [[0, 1]], [[0, 1]], [[0, 1]]]);
  const two = lakeInterpolation(grid, [{ lat: 47.9, lon: 11.3 }, { lat: 47.92, lon: 11.32 }], coord);
  assert.deepEqual(two.cellWeights[0], [[0, 1]]);
  assert.ok(Math.abs(two.cellWeights[2].find(([i]) => i === 0)[1] - 0.5) < 1e-6);
});
