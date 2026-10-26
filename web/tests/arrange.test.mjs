import { test } from "node:test";
import assert from "node:assert/strict";
import { normalized, moved, visibleCards, STANDARD } from "../public/app/arrange.js";

test("an order keeps every card once and drops unknown ones", () => {
  const layout = normalized({ order: ["hourly", "future", "hourly", "radar"], hidden: ["future", "satellite"] });
  assert.deepEqual(layout.order, ["hourly", "radar", "conditions", "lakeView", "launchPoint", "satellite"]);
  assert.deepEqual(layout.hidden, ["satellite"]);
  assert.deepEqual(normalized(null), STANDARD);
});

test("the rain radar card starts switched off", () => {
  assert.deepEqual(visibleCards(normalized(STANDARD)), ["conditions", "lakeView", "hourly", "launchPoint", "satellite"]);
});

test("switched-off cards are left out, the rest keep their order", () => {
  const layout = normalized({ order: ["satellite", "hourly"], hidden: ["lakeView"] });
  assert.deepEqual(visibleCards(layout), ["satellite", "hourly", "conditions", "launchPoint"]);
});

test("moving a card puts it at the new place", () => {
  assert.deepEqual(moved(["a", "b", "c", "d"], "a", 2), ["b", "c", "a", "d"]);
  assert.deepEqual(moved(["a", "b", "c", "d"], "d", 0), ["d", "a", "b", "c"]);
  assert.deepEqual(moved(["a", "b", "c"], "b", 9), ["a", "c", "b"]);
});
