// The sample API files in testdata/api/v1, written by the backend through the
// same code as the published files (backend/tests/test_sample_files.py) and read
// by the app's tests too. A field renamed on the backend fails here instead of
// leaving a blank tile on rowfrog.com.
import { test } from "node:test";
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import {
  currentHour, nextHours, searchClubs, lightFor, reasonCondition, REASONS, feelsLikeNote, pressureChange, iceValue, sunState,
} from "../public/app/logic.js";
import { ahead, radarSummary } from "../public/app/radar.js";

const read = (path) => JSON.parse(readFileSync(new URL(`../../testdata/api/v1/${path}`, import.meta.url)));
const forecast = read("clubs/mrc-1880/forecast");
const lakes = read("lakes/index");
const generated = new Date(forecast.generatedAt);

test("the sample club is found and its hours line up with now", () => {
  assert.equal(searchClubs(lakes, "mrc")[0].club.id, "mrc-1880");
  assert.equal(currentHour(forecast.hours, generated), forecast.hours[0]);
  assert.equal(nextHours(forecast.hours, generated, 48).length, 48);
  assert.ok(forecast.outlook.length > forecast.hours.length);
});

test("every reason in the sample belongs to a tile", () => {
  const known = new Set(Object.values(REASONS).flat());
  for (const hour of [...forecast.hours, ...forecast.outlook]) {
    for (const r of hour.reasons) {
      assert.ok(known.has(r.condition) || reasonCondition(r.condition) === "warning", r.condition);
    }
  }
  assert.equal(lightFor(forecast.hours[0], REASONS.wind), "red", "the sample storm warning");
});

test("the tiles' values come out of the sample", () => {
  const hour = forecast.hours[0];
  assert.ok(feelsLikeNote(hour));
  assert.equal(typeof pressureChange(forecast.hours, hour), "number");
  assert.equal(iceValue(forecast), null, "open water at 12.5 °C");
  assert.equal(sunState(forecast, generated).up, true);
  assert.equal(forecast.warnings.items.length, 2);
  assert.ok(forecast.warnings.items.every((w) => w.english?.headline));
  assert.ok(forecast.waterTemperature.history.length > 0);
});

test("the sample radar reads as rain ahead", () => {
  const r = { reference: Date.parse(forecast.radar.reference),
    steps: forecast.radar.steps.map((s) => ({ time: Date.parse(s.time), mm: s.mmPerHour })) };
  assert.ok(ahead(r, Date.parse(forecast.radar.reference)));
  assert.match(radarSummary(r), /from/);
});
