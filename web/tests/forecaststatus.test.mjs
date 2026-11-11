import { test } from "node:test";
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { forecastStatus } from "../public/app/logic.js";

// testdata/states/forecast-status.json: the table the app's tests (ForecastStatusTests) read too.
const table = JSON.parse(readFileSync(new URL("../../testdata/states/forecast-status.json", import.meta.url), "utf8"));
const failure = ["no internet connection", "why"];

test("every combination gives the state in the shared table", () => {
  assert.equal(table.rows.length, 16);
  for (const row of table.rows) {
    const status = forecastStatus({ hasForecast: row.hasForecast, outOfDate: row.outOfDate, loading: row.loading, failure: row.failed ? failure : null });
    assert.equal(status.name, row.status, JSON.stringify(row));
    assert.ok(table.states[status.name], `${status.name} is described in the table`);
  }
});

test("out of date shows with a failed update, and the reason travels with it", () => {
  const status = forecastStatus({ hasForecast: true, outOfDate: true, failure });
  assert.deepEqual(status, { name: "outOfDateAndUpdateFailed", failure, outOfDate: true });
});
