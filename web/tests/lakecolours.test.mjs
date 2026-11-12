// testdata/rules/lake-colours.json: the lake view's colours, which the app's
// tests (LakeColourTableTests.swift) read too, so both colour the lake alike.
import { test } from "node:test";
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { RGB, greyed, ramp } from "../public/app/lake.js";

const table = JSON.parse(readFileSync(new URL("../../testdata/rules/lake-colours.json", import.meta.url), "utf8"));
const close = (actual, expected, what) =>
  assert.ok(actual.every((v, i) => Math.abs(v - expected[i]) <= 0.01), `${what}: ${actual} instead of ${expected}`);

test("the light colours are the table's", () => {
  for (const [light, rgb] of Object.entries(table.lights)) assert.deepEqual(RGB[light], rgb, light);
});

test("waves and wind are coloured as in the table", () => {
  for (const c of table.ramp) close(ramp(c.value, c.amber, c.red), c.rgb, `${c.layer} ${c.value} (${c.amber}/${c.red})`);
});

test("a lake-wide red fades the light colours as in the table", () => {
  for (const c of table.greyed) close(greyed(RGB[c.light]), c.rgb, c.light);
});
