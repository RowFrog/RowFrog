// The warning line ("Sunset at 16:36: 6 min of daylight left") and the sun line
// ("Rowing until 16:36 · 5 min left") once counted the same moment differently:
// the warning rounded up, the sun line down, and the sunset carries seconds
// (16:36:40). Both now count clock minutes, as the reader does (owner, 17 Nov 2026).
// The app's twin is FormatTests.testMinutesLeftCountsClockMinutes.
import { test } from "node:test";
import assert from "node:assert/strict";
import { minutesLeft, timeLeft, hourExplanation } from "../public/app/shared.js";

const sunset = Date.parse("2026-11-16T15:36:40Z"); // 16:36 in Munich, with seconds

test("minutes left count the clock minutes shown", () => {
  assert.equal(minutesLeft(Date.parse("2026-11-16T15:31:00Z"), sunset), 5);
  assert.equal(minutesLeft(Date.parse("2026-11-16T15:31:59Z"), sunset), 5);
  assert.equal(minutesLeft(Date.parse("2026-11-16T14:55:30Z"), sunset), 41);
  assert.equal(minutesLeft(Date.parse("2026-11-16T14:32:10Z"), sunset), 64);
  assert.equal(timeLeft(Date.parse("2026-11-16T14:32:10Z"), sunset), "1 h 4 min");
});

test("the last minute before sunset still says 1 min, after it 0", () => {
  assert.equal(minutesLeft(Date.parse("2026-11-16T15:36:10Z"), sunset), 1);
  assert.equal(minutesLeft(sunset + 1000, sunset), 0);
});

test("the warning line and the sun line give the same number", () => {
  const forecast = { daylight: [{ date: "2026-11-16", sunrise: "2026-11-16T06:23:00Z", sunset: "2026-11-16T15:36:40Z" }] };
  for (const at of ["15:31:00", "15:31:59", "14:55:30", "15:00:01", "15:36:10"]) {
    const now = new Date(`2026-11-16T${at}Z`);
    const warning = hourExplanation(forecast, { condition: "sunset_soon", light: "amber" }, { time: "2026-11-16T15:00:00Z" }, now);
    const minutes = warning.match(/(\d+) min/)[1];
    assert.equal(`${minutes} min`, timeLeft(now, sunset), `at ${at}: ${warning}`);
  }
});
