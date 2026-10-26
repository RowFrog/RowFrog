import { test } from "node:test";
import assert from "node:assert/strict";
import {
  GROUPS, limitsFor, standardLimit, matchesStandard, allowsMore, applyLimitsToHour, applyLimits, coldWaterKit, steadierBoat,
} from "../public/app/logic.js";

const gig = { id: "g1", name: "Anna", type: "gig", class: "4x" };
const single = { id: "s1", name: "", type: "training", class: "1x" };

test("the app's limits by boat type and size (RowingLimit.standard)", () => {
  assert.equal(standardLimit("windAmber", GROUPS[0]), 5.5);
  assert.equal(standardLimit("gustRed", GROUPS[1]), 12.8);
  assert.equal(standardLimit("waveRed", gig), 0.5);
  assert.equal(standardLimit("windAmber", single), 6.5);
  assert.equal(standardLimit("windRed", { type: "coastal", class: "1x" }), 12);
  assert.equal(standardLimit("lifeJacket", gig), 15);
});

test("small boats with the app's limits leave the backend's light alone", () => {
  assert.ok(matchesStandard(limitsFor(GROUPS[0])));
  assert.ok(!matchesStandard(limitsFor(GROUPS[0], { windAmber: 6 })));
  assert.ok(!matchesStandard(limitsFor(GROUPS[1])));
  const forecast = { hours: [], outlook: [] };
  assert.equal(applyLimits(forecast, limitsFor(GROUPS[0])), forecast);
  assert.ok(allowsMore(limitsFor(gig), limitsFor(GROUPS[0])));
  assert.ok(!allowsMore(limitsFor(GROUPS[0]), limitsFor(gig)));
});

test("cold water lowers the app's wind limits, not the user's own", () => {
  assert.equal(limitsFor(gig, {}, 8).value("windAmber"), 7);
  assert.equal(limitsFor(gig, { windAmber: 9 }, 8).value("windAmber"), 9);
  assert.equal(limitsFor(gig, {}, 8).value("waveAmber"), 0.3);
});

test("an own limit marks the reason and keeps a note when the app's would be stricter", () => {
  const hour = { time: "2026-10-26T12:00:00Z", light: "amber", windSpeedMs: 6, windGustMs: 7, waveHeightM: 0.1,
    reasons: [{ condition: "wind", light: "amber" }, { condition: "single_cold", light: "amber" }] };
  // Small boats with wind amber raised to 7 m/s: green, with a note that 6 m/s is above the app's 5.5.
  const loose = applyLimitsToHour(hour, limitsFor(GROUPS[0], { windAmber: 7 }), 16);
  // As in the app, the cold-water reasons give way to the life-jacket badge once the app works the light out.
  assert.equal(loose.light, "green");
  assert.ok(!loose.reasons.some((r) => r.condition === "wind"));
  assert.deepEqual(loose.notes, [{ condition: "wind", light: "amber" }]);
  // Wind amber lowered to 5 m/s: the reason is the user's.
  const strict = applyLimitsToHour(hour, limitsFor(gig, { windAmber: 5 }), 16);
  assert.deepEqual(strict.reasons, [{ condition: "wind", light: "amber", mine: true }]);
  // Own wind limits in cold water: a reminder that they don't drop.
  assert.ok(applyLimitsToHour(hour, limitsFor(gig, { windRed: 11 }), 8).notes.some((n) => n.condition === "cold_margin"));
});

test("the life-jacket limit and singles decide the cold-water badge", () => {
  assert.equal(coldWaterKit(16, limitsFor(gig, { lifeJacket: 18 })), "lifeJacket");
  assert.equal(coldWaterKit(12, limitsFor(gig, { lifeJacket: 11 })), null);
  assert.equal(coldWaterKit(8, limitsFor(single)), "partnerBoat");
  assert.equal(coldWaterKit(8, limitsFor(gig)), "nearShore");
});

test("a steadier own boat is suggested when it would get a better light", () => {
  const hour = { time: "2026-10-26T12:00:00Z", light: "red", windSpeedMs: 8.5, windGustMs: 9, waveHeightM: 0.2,
    reasons: [{ condition: "wind", light: "red" }, { condition: "waves", light: "amber" }] };
  const found = steadierBoat(hour, 16, [gig, single], "small", (b) => limitsFor(b));
  assert.equal(found.boat.id, "g1");
  assert.equal(found.light, "amber");
  assert.equal(steadierBoat({ ...hour, light: "green" }, 16, [gig], "small", (b) => limitsFor(b)), null);
});
