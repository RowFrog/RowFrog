import { test } from "node:test";
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { baseLabel, reasonExplanation } from "../public/app/shared.js";
import { REASONS, reasonCondition } from "../public/app/logic.js";

// testdata/reasons.json lists every reason the backend may send; the backend's and the app's
// tests read it too. The owner saw "nearby_water" as raw text on an old build (12 Nov 2026).
const list = JSON.parse(readFileSync(new URL("../../testdata/reasons.json", import.meta.url)));
const tiles = new Set(Object.values(REASONS).flat());

test("every listed reason has a label and a sentence of its own", () => {
  const fallback = baseLabel("not_a_reason");
  const fallbackSentence = reasonExplanation("not_a_reason", "amber");
  for (const name of list.reasons) {
    const topics = list.topics[name] ?? [null];
    for (const topic of topics) {
      const label = baseLabel(name, topic, 1);
      assert.ok(label && label !== name && label !== fallback, `${name}/${topic}: ${label}`);
      const sentence = reasonExplanation(name, "amber", topic, 1);
      assert.ok(sentence && sentence !== name && sentence !== fallbackSentence, `${name}/${topic}: ${sentence}`);
    }
  }
});

test("every listed reason has a tile", () => {
  for (const name of list.reasons) {
    const topics = list.topics[name] ?? [null];
    for (const topic of topics) {
      const tile = reasonCondition(name, topic);
      assert.ok(tile === "warning" || tile in REASONS || tiles.has(name), `${name}/${topic}: ${tile}`);
    }
  }
});

test("a reason newer than the page never shows its raw name", () => {
  assert.notEqual(baseLabel("brand_new_reason"), "brand_new_reason");
  assert.notEqual(reasonExplanation("brand_new_reason", "amber"), "brand_new_reason");
});
