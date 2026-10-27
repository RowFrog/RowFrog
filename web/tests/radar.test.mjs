import { test } from "node:test";
import assert from "node:assert/strict";
import { ahead, rainOutlook, rainLines, radarSummary, radarFrames, radarRegion, nearestFrame, radarCovers } from "../public/app/radar.js";
import { conditionData } from "../public/app/values.js";

const MIN = 60000;
const now = Math.floor(Date.now() / (5 * MIN)) * 5 * MIN;
const radar = (values) => ({ reference: now, steps: values.map((mm, i) => ({ time: now + i * 15 * MIN, mm })) });
const hour = (offset, mm = 0, code = 0) => ({ time: new Date(Math.floor(now / 3600000) * 3600000 + offset * 3600000).toISOString(), precipitationMm: mm, weatherCode: code });

test("the radar ahead of a moment keeps at least half an hour", () => {
  const r = radar([0, 0, 0, 0, 0, 0, 0, 0, 0]);
  assert.equal(ahead(r, now).steps.length, 9);
  assert.equal(ahead(r, now + 90 * MIN).steps.length, 3);
  assert.equal(ahead(r, now + 105 * MIN), null);
  assert.equal(ahead(null, now), null);
});

test("dry radar: rain from the radar, else nothing coming", () => {
  const hours = [hour(0), hour(1), hour(2), hour(3)];
  const wet = rainOutlook(radar([0, 0, 0.6, 1.8, 0, 0, 0, 0, 0]), hours);
  assert.equal(wet.now, null);
  assert.equal(wet.next.fromRadar, true);
  assert.match(wet.next.text, /^Rain from /);
  assert.equal(rainOutlook(radar([0, 0, 0, 0, 0, 0, 0, 0, 0]), hours).summary, "No rain in the next 2 hours");
});

test("raining: dry again or heavier, whichever comes first; snow named from the forecast", () => {
  const hours = [hour(-1), hour(0), hour(1), hour(2), hour(3)];
  const ends = rainOutlook(radar([1, 1, 0, 0, 0, 0, 0, 0, 0]), hours);
  assert.equal(ends.now, "Light rain");
  assert.match(ends.next.text, /^Dry from /);
  const heavier = rainOutlook(radar([1, 3, 3, 0, 0, 0, 0, 0, 0]), hours);
  assert.match(heavier.next.text, /^Heavier from /);
  const snow = rainOutlook(radar([1, 1, 1, 1, 1, 1, 1, 1, 1]), hours.map((x) => ({ ...x, precipitationMm: 1, weatherCode: 73 })));
  assert.equal(snow.now, "Snow");
  assert.equal(snow.next.text, "No end in sight");
  assert.equal(snow.next.fromRadar, false);
});

test("the tile's lines: the radar for two hours, the forecast after them", () => {
  const forecast = { hours: [hour(0), hour(1), hour(2), hour(3, 1.2, 61), hour(4)] };
  const dry = rainLines(conditionData(forecast, forecast.hours[0], radar([0, 0, 0, 0, 0, 0, 0, 0, 0])));
  assert.equal(dry.value, "Dry");
  assert.equal(dry.fromRadar, false);
  assert.match(dry.detail, /^Rain from /);
  const wet = rainLines(conditionData(forecast, forecast.hours[0], radar([2, 2, 0, 0, 0, 0, 0, 0, 0])));
  assert.equal(wet.value, "Light rain");
  assert.equal(wet.fromRadar, true);
  // Without the radar, the forecast as before.
  assert.equal(rainLines(conditionData(forecast, forecast.hours[0])).value, "Dry");
});

test("the radar card's line names the heaviest rain", () => {
  assert.match(radarSummary(radar([0, 0, 12, 1, 0, 0, 0, 0, 0])), /^Heavy rain from /);
  assert.equal(radarSummary(radar([0, 0, 0, 0, 0, 0, 0, 0, 0])), "No rain in the next 2 hours");
});

test("the radar map: frames from an hour ago to two ahead, and its square around the club", () => {
  const frames = radarFrames(now, 15);
  assert.equal(frames.length, 13);
  assert.equal(frames[4], now);
  assert.equal(radarFrames(now, 30).length, 7);
  assert.equal(nearestFrame(now + 8 * MIN, frames), now + 15 * MIN);
  assert.equal(nearestFrame(now + 3 * 3600000, frames), null);
  assert.ok(radarCovers(now - 50 * MIN) && !radarCovers(now - 70 * MIN, Date.now()));
  const region = radarRegion({ lat: 47.95, lon: 11.35 });
  const [[south, west], [north, east]] = region.bounds;
  assert.ok(south < 47.95 && north > 47.95 && west < 11.35 && east > 11.35);
  // 600 km of web-mercator map: about 400 km of real ground at 48° N.
  assert.ok(Math.abs((east - west) * 111.32 * Math.cos((47.95 * Math.PI) / 180) - 402) < 10);
});
