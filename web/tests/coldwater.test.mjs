// testdata/rules/cold-water.json: the cold-water badge and the cold shore on the
// lake maps, which the app's tests (ColdWaterTableTests.swift) read too.
import { test } from "node:test";
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { coldWaterKit, limitsFor } from "../public/app/logic.js";
import { coldShore } from "../public/app/lake.js";

const table = JSON.parse(readFileSync(new URL("../../testdata/rules/cold-water.json", import.meta.url), "utf8"));

test("the cold-water badge and the shore are the table's", () => {
  for (const c of table.cases) {
    const limits = limitsFor(c.boat, c.ownLifeJacket == null ? {} : { lifeJacket: c.ownLifeJacket });
    const what = `${c.boat.id} ${c.boat.type} ${c.boat.class}, ${c.waterC} °C, own ${c.ownLifeJacket}`;
    assert.equal(coldWaterKit(c.waterC, limits), c.kit, what);
    assert.equal(coldShore(c.waterC, limits), c.shore, what);
  }
});
