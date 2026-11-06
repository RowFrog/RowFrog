// Every combination of the weather before, in and after an hour with every sunrise and sunset
// minute (owner, 6 Nov 2026: "check it with all possible combinations"). The same loops run in
// the app (DaylightRuleTests.testEveryCombination).
import { test } from "node:test";
import assert from "node:assert/strict";
import { hourHalves, nowHour, daylightAt, daylightParts, sunDaysOf } from "../public/app/logic.js";

const RANK = { green: 0, amber: 1, red: 2 };
const LIGHTS = ["green", "amber", "red"];
const worst = (...l) => l.reduce((w, x) => (RANK[x] > RANK[w] ? x : w), "green");
const iso = (ms) => new Date(ms).toISOString();
const DAY = Date.UTC(2026, 10, 7);
const HOUR = 3600e3;

/** A forecast as the backend writes it: each hour the strictest of its weather and its daylight minutes. */
function forecast(sunrise, sunset, weather) {
  const daylight = [{ date: "2026-11-07", sunrise: iso(sunrise), sunset: iso(sunset) }];
  const days = sunDaysOf({ daylight });
  const hours = Object.entries(weather).map(([start, wx]) => {
    const t = Number(start);
    const sun = daylightParts(t, days).reduce((w, p) => worst(w, p.light), "green");
    const reasons = [];
    if (wx !== "green") reasons.push({ condition: "wind", light: wx });
    reasons.push(sun === "amber" ? { condition: "twilight", light: "amber" } : { condition: "daylight", light: sun });
    return { time: iso(t), light: worst(wx, sun), reasons: sun === "green" ? reasons.filter((r) => r.condition === "wind") : reasons, sunUp: sun !== "red" };
  });
  return { daylight, hours, days };
}

function check(f, label) {
  let splits = 0;
  f.hours.forEach((hour, i) => {
    const halves = hourHalves(f, hour);
    const t = Date.parse(hour.time);
    const own = f.hours[i].reasons.filter((r) => r.condition === "wind").map((r) => r.light)[0] ?? "green";
    const before = i > 0 ? (f.hours[i - 1].reasons.find((r) => r.condition === "wind")?.light ?? "green") : "green";
    const after = i + 1 < f.hours.length ? (f.hours[i + 1].reasons.find((r) => r.condition === "wind")?.light ?? "green") : "green";
    const at = `${label} ${hour.time}`;
    // The row is never more relaxed than any minute of "now" in it.
    for (let m = 0; m < 60; m += 1) {
      const now = nowHour(f, new Date(t + m * 60e3));
      assert.ok(RANK[hour.light] >= RANK[now.light], `${at}+${m}: row ${hour.light}, now ${now.light}`);
    }
    if (!halves) return;
    splits += 1;
    assert.notEqual(halves.start, halves.end, at);
    // The stricter half is the hour's own light; neither half is below the hour's weather.
    assert.equal(worst(halves.start, halves.end), hour.light, at);
    assert.ok(RANK[halves.start] >= RANK[own] && RANK[halves.end] >= RANK[own], at);
    // The better half is never better than the weather of the hour it touches.
    if (RANK[halves.start] < RANK[halves.end]) assert.ok(RANK[halves.start] >= RANK[before], `${at}: ${halves.start} after ${before}`);
    else assert.ok(RANK[halves.end] >= RANK[after], `${at}: ${halves.end} before ${after}`);
    // Each half is the daylight at that end of the hour (or the weather when stricter).
    assert.ok(RANK[halves.start] >= RANK[daylightAt(t, f.days)], at);
    assert.ok(RANK[halves.end] >= RANK[daylightAt(t + HOUR - 60e3, f.days)], at);
  });
  return splits;
}

test("every sunset minute with every weather before, in and after its hours", () => {
  let cases = 0;
  let splits = 0;
  const sunrise = DAY + 6 * HOUR + 9 * 60e3;
  for (let m = 0; m < 60; m += 1) {
    const sunset = DAY + 15 * HOUR + m * 60e3;
    for (const a of LIGHTS) for (const b of LIGHTS) for (const c of LIGHTS) for (const d of LIGHTS) {
      // 13:00 to 16:00 UTC: the hour the window starts in, the sunset hour and one either side.
      const weather = { [DAY + 13 * HOUR]: a, [DAY + 14 * HOUR]: b, [DAY + 15 * HOUR]: c, [DAY + 16 * HOUR]: d };
      splits += check(forecast(sunrise, sunset, weather), `sunset :${m} ${a}/${b}/${c}/${d}`);
      cases += 1;
    }
  }
  assert.equal(cases, 60 * 81);
  assert.ok(splits > 0);
});

test("every sunrise minute with every weather before, in and after its hour", () => {
  const sunset = DAY + 15 * HOUR + 49 * 60e3;
  for (let m = 0; m < 60; m += 1) {
    const sunrise = DAY + 6 * HOUR + m * 60e3;
    for (const a of LIGHTS) for (const b of LIGHTS) for (const c of LIGHTS) {
      const weather = { [DAY + 5 * HOUR]: a, [DAY + 6 * HOUR]: b, [DAY + 7 * HOUR]: c };
      check(forecast(sunrise, sunset, weather), `sunrise :${m} ${a}/${b}/${c}`);
    }
  }
});

test("the owner's situations come out as on the options page (pick B)", () => {
  const sunrise = DAY + 6 * HOUR + 9 * 60e3;
  const sunset = DAY + 15 * HOUR + 49 * 60e3;
  const dots = (hours, w) => {
    const f = forecast(sunrise, sunset, Object.fromEntries(hours.map((h, i) => [DAY + h * HOUR, w[i]])));
    return f.hours.map((x) => { const s = hourHalves(f, x); return s ? `${s.start[0]}/${s.end[0]}` : x.light[0]; }).join(" ");
  };
  const G = "green", A = "amber", R = "red";
  // Sunset at 15:49 UTC: amber from 14:49. 1 clear, 2 red day, 3 amber day, 4 storm in the sunset hour,
  // 5 red only before, 6 amber only at sunset.
  assert.equal(dots([13, 14, 15, 16], [G, G, G, G]), "g g/a a/r r");
  assert.equal(dots([13, 14, 15, 16], [R, R, G, G]), "r r r r");
  assert.equal(dots([13, 14, 15, 16], [A, A, A, A]), "a a a/r r");
  assert.equal(dots([13, 14, 15, 16], [G, G, R, R]), "g g/a r r");
  assert.equal(dots([13, 14, 15, 16], [G, R, G, G]), "g r r r");
  assert.equal(dots([13, 14, 15, 16], [G, G, A, A]), "g g/a a/r r");
  // Sunrise at 06:09 UTC. 7 clear, 8 red day after, 9 amber fog after, 10 fog in the sunrise hour.
  assert.equal(dots([4, 5, 6, 7], [G, G, G, G]), "r r r/g g");
  assert.equal(dots([4, 5, 6, 7, 8], [G, G, G, R, R]), "r r r r r");
  assert.equal(dots([4, 5, 6, 7, 8], [G, G, G, A, A]), "r r r/a a a");
  assert.equal(dots([4, 5, 6, 7], [G, G, R, G]), "r r r g");
});
