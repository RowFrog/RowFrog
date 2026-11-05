import { test } from "node:test";
import assert from "node:assert/strict";
import { backgroundFor, picturePlace } from "../public/app/backgrounds.js";

const b = { all: "sample:lake-waves", pages: { list: "none", clubPages: "satellite" }, clubs: { a: "custom:user-1.jpg", b: "bad" } };

test("a club's own picture, else its kind of page's, else the one for all pages", () => {
  assert.equal(backgroundFor("clubPages", "a", b), "custom:user-1.jpg");
  assert.equal(backgroundFor("clubPages", "c", b), "satellite");
  assert.equal(backgroundFor("clubPages", "b", b), "satellite");
  assert.equal(backgroundFor("list", "a", b), "none");
  assert.equal(backgroundFor("settings", null, b), "sample:lake-waves");
});

test("a satellite picture fills the window with the club as near the middle as its edges allow", () => {
  const picture = { width: 435, height: 1280 };
  const area = { width: 1000, height: 800 };
  // Scaled to cover: 1000 wide, 2943 tall.
  const centred = picturePlace(picture, area, null);
  assert.ok(Math.abs(centred.width - 1000) < 1e-9);
  assert.ok(Math.abs(centred.y - (800 - centred.height) / 2) < 1e-9);
  // A club near the north end: the picture's top edge stops it, no gap above.
  assert.equal(picturePlace(picture, area, { x: 0.8, y: 0.05 }).y, 0);
  // Halfway down: that point sits in the middle.
  const mid = picturePlace(picture, area, { x: 0.5, y: 0.5 });
  assert.ok(Math.abs(mid.y + mid.height / 2 - 400) < 1e-9);
  // Near the south end: the bottom edge stops it.
  const south = picturePlace(picture, area, { x: 0.5, y: 0.98 });
  assert.ok(Math.abs(south.y - (800 - south.height)) < 1e-9);
  // Never sideways off the window when it covers exactly.
  assert.ok(Math.abs(picturePlace(picture, area, { x: 1, y: 0.5 }).x) < 1e-9);
});
