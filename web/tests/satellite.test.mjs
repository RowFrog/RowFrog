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

test("two pictures name their day, three do not (SatelliteKindPicker)", async () => {
  const { pictureKinds, kindLabel } = await import("../public/app/satellite.js");
  const shot = (date) => ({ image: `${date}.jpg`, date });
  const lake = (meta) => ({ meta, kinds: pictureKinds(meta) });
  const two = lake({ latest: shot("2026-11-03"), clearest: shot("2026-10-27") });
  assert.match(kindLabel(two, "latest", "Latest"), /^Latest, .*3/);
  assert.match(kindLabel(two, "clearest", "Clearest"), /^Clearest, .*27/);
  const three = lake({ latest: shot("2026-11-03"), mostlyClear: shot("2026-10-30"), clearest: shot("2026-10-27") });
  assert.equal(kindLabel(three, "latest", "Latest"), "Latest");
});

test("the life-jacket badge moves to a corner clear of the lake", async () => {
  const { badgeCorner } = await import("../public/app/satellite.js");
  const ring = (x0, y0, x1, y1) => [[[x0, y0], [x1, y0], [x1, y1], [x0, y1]]];
  const place = (shore) => badgeCorner(shore, 300, 300, [150, 34], [34, 34]);
  assert.deepEqual(place(ring(100, 100, 200, 200)), { corner: "top-left", compact: false });
  assert.deepEqual(place(ring(10, 10, 120, 120)), { corner: "top-right", compact: false });
  assert.equal(place(ring(30, 30, 270, 270)).compact, true);
  assert.equal(place(ring(-10, -10, 310, 310)).compact, true);
});

test("a card opens on the clearest picture when the latest is covered over the club (decision 0024)", async () => {
  const { pictureKinds, startKind } = await import("../public/app/satellite.js");
  const shot = (date, lakeCloud, more = {}) => ({ date, lakeCloud, image: `${date}.jpg`, ...more });
  const open = (meta, club = "mrc") => startKind(meta, pictureKinds(meta), club);
  // Covered over the club, though not over the whole lake: the clearest.
  assert.equal(open({ latest: shot("2026-11-08", 0.6, { clubCloud: { mrc: 0.95 } }), clearest: shot("2026-10-27", 0) }), "clearest");
  // Clear over the club, though the lake is mostly covered: the latest.
  assert.equal(open({ latest: shot("2026-11-08", 0.95, { clubCloud: { mrc: 0.3 } }), clearest: shot("2026-10-27", 0) }), "latest");
  // No measure for this club: the whole lake decides, from 90 %.
  assert.equal(open({ latest: shot("2026-11-08", 0.9), clearest: shot("2026-10-27", 0) }), "clearest");
  assert.equal(open({ latest: shot("2026-11-08", 0.89), clearest: shot("2026-10-27", 0) }), "latest");
  // The clearest is the same pass, or there is none: the latest.
  assert.equal(open({ latest: shot("2026-11-08", 1), clearest: shot("2026-11-08", 1) }), "latest");
  assert.equal(open({ latest: shot("2026-11-08", 1) }), "latest");
});
