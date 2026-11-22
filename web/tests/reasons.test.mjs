import { test } from "node:test";
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { baseLabel, reasonExplanation, nearbyWithLaunchPoint } from "../public/app/shared.js";
import { REASONS, reasonCondition, REASON_ORDER, orderReasons } from "../public/app/logic.js";

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

test("one order for the server, the app and the website (owner, 20 Nov 2026)", () => {
  assert.deepEqual(REASON_ORDER, list.order);
  for (const name of list.reasons) if (name !== "nearby_water") assert.ok(REASON_ORDER.includes(name), name);
});

test("red first, then the more dangerous, daylight last (owner's screenshot, 20 Nov 2026)", () => {
  const got = orderReasons([
    { condition: "sunset_soon", light: "amber" }, { condition: "wind", light: "red" },
    { condition: "weather_warning", light: "amber", topic: "wind" }, { condition: "gusts", light: "red" },
    { condition: "brand_new_reason", light: "amber" }, { condition: "nearby_water", light: "red", topic: "fog" },
  ]).map((r) => r.condition);
  assert.deepEqual(got, ["nearby_water", "gusts", "wind", "weather_warning", "brand_new_reason", "sunset_soon"]);
});

test("a nearby reason with the same thing at the launch point names both places (owner's pick A, 22 Nov 2026)", () => {
  const near = { condition: "nearby_water", light: "red", topic: "fog", value: 300 };
  const both = { reasons: [near, { condition: "fog", light: "amber" }], visibilityM: 700 };
  assert.match(nearbyWithLaunchPoint(near, both), /^Fog: visibility 0\.7 km at the launch point, only 0\.3 km within 1 km\.$/);
  assert.equal(nearbyWithLaunchPoint(near, { reasons: [near], visibilityM: 700 }), null, "no launch point reason: the old sentence");
  assert.equal(nearbyWithLaunchPoint(near, { reasons: both.reasons }), null, "no launch point value: the old sentence");
  const wind = { condition: "nearby_water", light: "red", topic: "wind", value: 9 };
  assert.ok(nearbyWithLaunchPoint(wind, { reasons: [wind, { condition: "wind", light: "amber", mine: true }], windSpeedMs: 6 }).endsWith("You set this limit yourself."));
  const storm = { condition: "nearby_water", light: "red", topic: "thunderstorm" };
  assert.equal(nearbyWithLaunchPoint(storm, { reasons: [storm, { condition: "thunderstorm", light: "amber" }] }), "Thunderstorms are possible at the launch point and within 1 km of it.");
  assert.equal(nearbyWithLaunchPoint({ condition: "fog", light: "amber" }, both), null);
});
