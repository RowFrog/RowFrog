import { test } from "node:test";
import assert from "node:assert/strict";
import { toggleLayer } from "../public/app/satellite.js";

test("waves and rowing light take turns colouring the water", () => {
  assert.deepEqual(toggleLayer([], "shore"), ["shore"]);
  assert.deepEqual(toggleLayer(["shore", "light"], "waves"), ["shore", "waves"]);
  assert.deepEqual(toggleLayer(["shore", "waves"], "wind"), ["shore", "waves", "wind"]);
  assert.deepEqual(toggleLayer(["shore", "waves"], "waves"), ["shore"]);
});

test("the frame key changes with the frame and matches the app's", async () => {
  const { frameKey } = await import("../public/app/satellite.js");
  const meta = { bbox: [11.26269, 47.8064, 11.36629, 48.01222], width: 435, height: 1280 };
  assert.equal(frameKey(meta), "44941545"); // FNV-1a of "11.26269,47.80640,11.36629,48.01222|435x1280", as the app works it out
  assert.equal(frameKey(meta), frameKey({ ...meta }));
  assert.notEqual(frameKey(meta), frameKey({ ...meta, width: 436 }));
  assert.equal(frameKey({}), null);
});
