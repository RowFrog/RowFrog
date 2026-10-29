import { test } from "node:test";
import assert from "node:assert/strict";
import { isLowered, waterLevelTile, waterLevelBody, stateTitle } from "../public/app/lakelevel.js";
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
