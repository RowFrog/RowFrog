import { test } from "node:test";
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { warningGroups } from "../public/app/logic.js";

// testdata/states/warning-groups.json: the table the app's tests (WarningGroupTests) read too.
const table = JSON.parse(readFileSync(new URL("../../testdata/states/warning-groups.json", import.meta.url), "utf8"));

test("every case gives the blocks in the shared table", () => {
  assert.ok(table.cases.length > 0);
  for (const c of table.cases) {
    const blocks = warningGroups(c.warnings).map((g) => g.map((w) => w.event));
    assert.deepEqual(blocks, c.blocks, c.name);
  }
});
