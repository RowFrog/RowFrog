import { test } from "node:test";
import assert from "node:assert/strict";
import { windArrows, windFrom, mix, shoreOf, shoreDistance, arrowLength } from "../public/app/windarrows.js";

// A square lake from 100 to 300 with one forecast point in the middle, blowing east at 5 m/s.
const rings = [[[100, 100], [300, 100], [300, 300], [100, 300]]];
const samples = [{ x: 200, y: 200, towardDeg: 90, speedMs: 5 }];
const north = () => ({ towardDeg: 0, speedMs: 10 });

test("arrows on a staggered grid over the water, none on land without the weather map", () => {
  const arrows = windArrows({ area: [0, 0, 400, 400], spacing: 60, rings, samples });
  assert.ok(arrows.length > 0);
  assert.ok(arrows.every((a) => !a.ashore && a.x > 100 && a.x < 300 && a.y > 100 && a.y < 300));
  const rows = [...new Set(arrows.map((a) => a.y))].sort((a, b) => a - b);
  const first = arrows.filter((a) => a.y === rows[0]).map((a) => a.x % 60);
  const second = arrows.filter((a) => a.y === rows[1]).map((a) => a.x % 60);
  assert.equal(Math.abs(first[0] - second[0]), 30);
  assert.ok(arrows.every((a) => Math.abs(a.towardDeg - 90) < 1e-9 && a.speedMs === 5));
});

test("on land the weather map's wind, faded in from the lake's near the shore", () => {
  const arrows = windArrows({ area: [0, 0, 400, 400], spacing: 20, rings, samples, land: north, blend: 50 });
  const ashore = arrows.filter((a) => a.ashore);
  assert.ok(ashore.length > 0);
  const far = ashore.filter((a) => a.x < 40 || a.y < 40);
  assert.ok(far.length && far.every((a) => a.towardDeg === 0 && a.speedMs === 10));
  const near = ashore.find((a) => a.x === 310 && a.y > 150 && a.y < 250);
  assert.ok(near.speedMs > 5 && near.speedMs < 10 && near.towardDeg > 0 && near.towardDeg < 90);
});

test("mixing, distance from the shore and the arrow length", () => {
  assert.deepEqual(mix({ towardDeg: 90, speedMs: 4 }, { towardDeg: 0, speedMs: 8 }, 0.5), { towardDeg: 45, speedMs: 6 });
  const shore = shoreOf(rings);
  assert.equal(shoreDistance(shore, [320, 200], 50), 20);
  assert.equal(shoreDistance(shore, [400, 200], 50), null);
  assert.equal(windFrom([], [0, 0]), null);
  assert.equal(arrowLength(30), arrowLength(15));
});
