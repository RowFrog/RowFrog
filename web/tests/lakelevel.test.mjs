import { test } from "node:test";
import assert from "node:assert/strict";
import { isLowered, waterLevelTile, waterLevelBody, stateTitle, basinShape } from "../public/app/lakelevel.js";
import { reasonCondition } from "../public/app/logic.js";

const level = (state, levelM) => ({
  gauge: "Roßhaupten Seepegel", fullM: 781, loweredBelowM: 779.8, drainedBelowM: 777.5,
  now: state && { time: "2026-11-20T10:00:00Z", levelM, belowFullM: 781 - levelM, state, trend: "falling", light: state === "drained" ? "red" : state === "lowered" ? "amber" : "green",
    history: [{ time: "2026-11-13T10:00:00Z", levelM: levelM + 1 }, { time: "2026-11-20T10:00:00Z", levelM }] },
});

test("the Water level tile shows only while the lake is let down (app #187)", () => {
  assert.equal(isLowered(level("full", 781)), false);
  assert.equal(isLowered(level(null)), false);
  assert.equal(isLowered(undefined), false);
  assert.equal(isLowered(level("lowered", 779)), true);
  assert.equal(stateTitle("drained"), "Drained");
  const tile = waterLevelTile(level("lowered", 779));
  assert.match(tile, /data-water-level/);
  assert.match(tile, /Lowered/);
  assert.match(tile, /2\.0 m below full · falling/);
  const body = waterLevelBody(level("drained", 776));
  assert.match(body, /Too little water at the club to row\./);
  assert.match(body, /level-chart/);
  assert.equal(reasonCondition("lake_drained"), "waterLevel");
});

test("the basin's water stays inside its sloping sides and the marks are drawn in (owner, 12 Nov 2026)", () => {
  // Forggensee, 1.1 m below full: the water must sit below the amber lowered mark, not look nearly full and boxy.
  const lake = { fullM: 780.5, loweredBelowM: 779.8, drainedBelowM: 777.5 };
  const s = basinShape(779.4, lake);
  const inside = ([x, y]) => x >= 2 + 11.2 * (y - 4) / 36 && x <= 44 - (2 + 11.2 * (y - 4) / 36);
  for (const p of s.water) assert.ok(inside(p), `water point ${p} inside the sides`);
  const waterTop = s.water[2][1];
  assert.ok(waterTop > s.lowered[0][1], "the water is below the lowered mark");
  assert.ok(waterTop < s.drained[0][1], "and above the drained mark");
  assert.ok(s.full[0][1] < s.lowered[0][1], "full is above lowered");
  assert.ok(s.full[1][0] - s.full[0][0] > 20, "the full mark goes right across");
  const svg = waterLevelTile({ ...level("lowered", 779.4), ...lake });
  assert.match(svg, /<polygon /);
  assert.match(svg, /stroke-dasharray="2 2"/);
  assert.doesNotMatch(svg, /<rect /);
});
