import { test } from "node:test";
import assert from "node:assert/strict";
import { toggleLayer } from "../public/app/satellite.js";

test("waves and rowing light take turns colouring the water", () => {
  assert.deepEqual(toggleLayer([], "shore"), ["shore"]);
  assert.deepEqual(toggleLayer(["shore", "light"], "waves"), ["shore", "waves"]);
  assert.deepEqual(toggleLayer(["shore", "waves"], "wind"), ["shore", "waves", "wind"]);
  assert.deepEqual(toggleLayer(["shore", "waves"], "waves"), ["shore"]);
});
