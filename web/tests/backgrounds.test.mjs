import { test } from "node:test";
import assert from "node:assert/strict";
import { backgroundFor, keyboardShift, picturePlace } from "../public/app/backgrounds.js";

const b = { all: "sample:lake-waves", pages: { list: "none", clubPages: "satellite" }, clubs: { a: "custom:user-1.jpg", b: "bad" } };

test("a club's own picture, else its kind of page's, else the one for all pages", () => {
  assert.equal(backgroundFor("clubPages", "a", b), "custom:user-1.jpg");
  assert.equal(backgroundFor("clubPages", "c", b), "satellite");
  assert.equal(backgroundFor("clubPages", "b", b), "satellite");
  assert.equal(backgroundFor("list", "a", b), "none");
});

test("the settings keep their plain background unless the developer options are on (#355)", () => {
  const saved = globalThis.localStorage;
  const items = new Map();
  globalThis.localStorage = { getItem: (k) => items.get(k) ?? null, setItem: (k, v) => items.set(k, String(v)), removeItem: (k) => items.delete(k) };
  try {
    assert.equal(backgroundFor("settings", null, b), "none");
    items.set("rf.developerOptions", "true");
    assert.equal(backgroundFor("settings", null, b), "sample:lake-waves");
  } finally {
    globalThis.localStorage = saved;
  }
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

test("the picture stays on the screen while the keyboard is open, not while zoomed or for the browser's own bars", () => {
  // iPhone, keyboard open, Safari slid the visible part 270 points down to show the search at the bottom.
  assert.equal(keyboardShift({ layoutHeight: 852, height: 470, offsetTop: 270.4, scale: 1 }), 270);
  // Keyboard open but nothing slid: the list is long enough and the page scrolled instead.
  assert.equal(keyboardShift({ layoutHeight: 852, height: 470, offsetTop: 0, scale: 1 }), 0);
  // The address bar coming and going.
  assert.equal(keyboardShift({ layoutHeight: 852, height: 800, offsetTop: 40, scale: 1 }), 0);
  // Pinch zoom moves the visible part too; the picture zooms with the page then.
  assert.equal(keyboardShift({ layoutHeight: 852, height: 400, offsetTop: 200, scale: 2 }), 0);
});

test("the clock strip takes the colour seen at the picture's top (decision 0054)", async () => {
  const { stripColour, medianColour } = await import("../public/app/backgrounds.js");
  // Median per channel, so a few bright pixels (a cloud's rim) don't move it.
  const pixels = [10, 20, 30, 255, 12, 22, 32, 255, 250, 250, 250, 255, 11, 21, 31, 255, 13, 23, 33, 255];
  assert.deepEqual(medianColour(pixels), [12, 22, 32]);
  // Under the page-coloured veil (60 % at the top), and 30 % darker in dark mode.
  assert.deepEqual(stripColour([100, 150, 200], [242, 242, 247], false), [185, 205, 228]);
  assert.deepEqual(stripColour([100, 150, 200], [0, 0, 0], true), [28, 42, 56]);
});
