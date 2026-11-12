import { test } from "node:test";
import assert from "node:assert/strict";
import { pacedChoice, dayKey } from "../public/app/tour.js";

const today = "2026-11-13";
const base = { today, tourDay: "2026-11-12", off: false, state: null };

test("one paced tip on a screen: the first in the page order takes the day", () => {
  const { show, state } = pacedChoice(["satellite", "hourly", "topTile"], base);
  assert.deepEqual(show, ["topTile"]);
  assert.deepEqual(state, { day: today, id: "topTile" });
});

test("once a tip took the day, no other paced tip shows that day, also after it was closed", () => {
  const state = { day: today, id: "topTile" };
  assert.deepEqual(pacedChoice(["hourly", "satellite"], { ...base, state }).show, []);
  assert.deepEqual(pacedChoice(["hourly", "topTile"], { ...base, state }).show, ["topTile"]);
});

test("the next day the next tip may show", () => {
  const state = { day: "2026-11-12", id: "topTile" };
  assert.deepEqual(pacedChoice(["hourly", "satellite"], { ...base, state }).show, ["hourly"]);
});

test("no paced tips on the day of the tour, but a tip for a rare case shows", () => {
  assert.deepEqual(pacedChoice(["topTile"], { ...base, tourDay: today }).show, []);
  assert.deepEqual(pacedChoice(["topTile", "waterLevel"], { ...base, tourDay: today }).show, ["waterLevel"]);
});

test("a tip for a rare case goes first and keeps the screen to one tip", () => {
  const { show, state } = pacedChoice(["topTile", "nearbyWater", "coldWater"], base);
  assert.deepEqual(show, ["nearbyWater"]);
  assert.equal(state, null);
});

test("No more tips stops every tip", () => {
  assert.deepEqual(pacedChoice(["topTile", "waterLevel"], { ...base, off: true }).show, []);
});

test("a day is the browser's calendar day", () => {
  assert.equal(dayKey(new Date(2026, 10, 3, 23, 59)), "2026-11-03");
});
