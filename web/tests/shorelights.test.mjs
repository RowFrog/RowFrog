import { test } from "node:test";
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { shoreLightsState } from "../public/app/logic.js";

// testdata/states/shore-lights-season.json: the table the app's tests (ShoreLightsSeasonTests) read too.
const table = JSON.parse(readFileSync(new URL("../../testdata/states/shore-lights-season.json", import.meta.url), "utf8"));

test("every row gives the state in the shared table", () => {
  assert.ok(table.rows.length > 0);
  for (const row of table.rows) {
    const state = shoreLightsState(row.season, new Date(row.at));
    assert.equal(state, row.state, JSON.stringify(row));
    assert.ok(table.states[state], `${state} is described in the table`);
  }
});
