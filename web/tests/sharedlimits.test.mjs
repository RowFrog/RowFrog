import { test } from "node:test";
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { standardLimit, limitsFor, COLD } from "../public/app/logic.js";

// testdata/limits.json: the table the backend's and the app's tests read too.
const table = JSON.parse(readFileSync(new URL("../../testdata/limits.json", import.meta.url), "utf8"));
const BOAT_LIMITS = ["windAmber", "windRed", "gustAmber", "gustRed", "waveAmber", "waveRed"];

test("the website's limits by boat match the shared table", () => {
  for (const row of table.boats) {
    const boat = { id: "own", type: row.type, class: row.class };
    for (const limit of BOAT_LIMITS) assert.equal(standardLimit(limit, boat), row[limit], `${row.type} ${row.class} ${limit}`);
    for (const [limit, value] of Object.entries(table.everyBoat)) assert.equal(standardLimit(limit, boat), value, `${row.type} ${limit}`);
  }
});

test("cold water and the strong-wind light match the shared table", () => {
  assert.equal(COLD.waterC, table.coldWater.belowC);
  assert.equal(COLD.marginMs, table.coldWater.windMarginMs);
  const boat = { id: "own", type: "racing", class: "1x" };
  assert.equal(limitsFor(boat, {}, table.coldWater.belowC - 0.1).value("windAmber"), table.boats[0].windAmber - table.coldWater.windMarginMs);
  for (const row of table.strongWindLight) {
    assert.equal(limitsFor({ id: "own", type: row.type, class: row.class }).strongWindLight, row.light, `${row.type} ${row.class}`);
  }
});
