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

test("the satellite view stripes the lake while the whole lake is red or amber", async () => {
  const { stripeSvg } = await import("../public/app/satellite.js");
  assert.equal(stripeSvg(null, 300, 400, "c"), "");
  const red = stripeSvg("red", 300, 400, "c");
  assert.match(red, /rgba\(255,59,48/);
  assert.match(red, /clip-path="url\(#c\)"/);
  assert.match(stripeSvg("amber", 300, 400, "c"), /rgba\(255,149,0/);
});

test("a clearest picture from the latest day is not offered twice", async () => {
  const { pictureKinds } = await import("../public/app/satellite.js");
  const shot = (date) => ({ image: `${date}.jpg`, date });
  const kinds = (meta) => pictureKinds(meta).map(([k]) => k);
  assert.deepEqual(kinds({ latest: shot("2026-10-27"), clearest: shot("2026-10-27") }), ["latest"]);
  assert.deepEqual(kinds({ latest: shot("2026-10-27"), mostlyClear: shot("2026-10-22"), clearest: shot("2026-10-16") }), ["latest", "mostlyClear", "clearest"]);
  assert.deepEqual(kinds({ clearest: shot("2026-10-16") }), ["clearest"]);
});
