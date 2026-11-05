import { test } from "node:test";
import assert from "node:assert/strict";
import { yTicks } from "../public/app/chart.js";

test("the value scale takes round steps, about three intervals, as Swift Charts", () => {
  assert.deepEqual(yTicks(0, 11), [0, 5, 10]);
  assert.deepEqual(yTicks(0, 2.6), [0, 1, 2]);
  assert.deepEqual(yTicks(-3, 12), [0, 5, 10]);
  assert.deepEqual(yTicks(0, 0.4), [0, 0.1, 0.2, 0.3, 0.4]);
  assert.deepEqual(yTicks(960, 1040), [960, 980, 1000, 1020, 1040]);
});

test("a log scale marks the powers of ten, and an empty range has no marks", () => {
  assert.deepEqual(yTicks(0.5, 200, true), [1, 10, 100]);
  assert.deepEqual(yTicks(3, 3), []);
});
