import { test } from "node:test";
import assert from "node:assert/strict";
import { windNumber, windRange, windPair } from "../public/app/shared.js";

// Decision 0060 (owner, 22 Nov 2026): mean and gust that round the same show once ("1", not
// "1–1"); hour tables keep both numbers. The app's UnitsTests.swift checks Format.windSpan the same way.
test("wind shows one number when mean and gust round the same", () => {
  assert.equal(windRange(0.8, 1.3), windNumber(1.3));
  assert.ok(!windRange(0.8, 1.3).includes("–"));
  assert.equal(windRange(2, 5), `${windNumber(2)}–${windNumber(5)}`);
  assert.equal(windRange(3, null), windNumber(3));
  assert.equal(windRange(null, 4), "–");
  for (let ms = 0; ms <= 20; ms += 0.1) {
    for (const extra of [0, 0.2, 0.4, 0.6, 1.5, 3]) {
      const same = windNumber(ms) === windNumber(ms + extra);
      assert.equal(windRange(ms, ms + extra).includes("–"), !same, `${ms} / ${ms + extra}`);
    }
  }
});

test("hour tables keep mean–gust", () => {
  assert.equal(windPair(0.8, 1.3), `${windNumber(0.8)}–${windNumber(1.3)}`);
  assert.equal(windPair(null, 1), "–");
});
