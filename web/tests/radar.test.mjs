import { test } from "node:test";
import assert from "node:assert/strict";
import { ahead, rainOutlook, rainLines, skyNow, radarSummary, radarFrames, radarRegion, nearestFrame, radarCovers, radarTitleMark, radarStatus } from "../public/app/radar.js";
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

test("drizzle under 0.1 mm is named, never called dry beside its symbol", () => {
  const forecast = { hours: [hour(0, 0.04, 51), hour(1), hour(2), hour(3), hour(4)] };
  const lines = rainLines(conditionData(forecast, forecast.hours[0]));
  assert.equal(lines.value, "Drizzle");
  assert.match(lines.detail, /^Under 0\.1 mm$/);
  // The radar sees no drizzle, so its dry does not hide the forecast's.
  assert.equal(rainLines(conditionData(forecast, forecast.hours[0], radar([0, 0, 0, 0, 0, 0, 0, 0, 0]))).value, "Drizzle");
  // Drizzle later on counts as something coming, not "Dry next 24 h".
  const later = { hours: [hour(0), hour(1), hour(2), hour(3, 0.02, 53), hour(4)] };
  assert.match(rainLines(conditionData(later, later.hours[0])).detail, /^Drizzle from /);
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

test("the sky follows the radar while it covers the moment (ConditionData.sky)", () => {
  const at = (h, r) => skyNow(conditionData({ hours: [h] }, h, r));
  const rainy = { ...hour(0, 1.2, 61), cloudCoverPct: 90, temperatureC: 8 };
  // The model says rain, the radar is dry: the sky from the cloud cover alone.
  assert.equal(at(rainy, radar([0, 0, 0, 0, 0, 0, 0, 0, 0])), "cloudy");
  assert.equal(at({ ...rainy, cloudCoverPct: 50 }, radar([0, 0, 0, 0, 0, 0, 0, 0, 0])), "partlyCloudy");
  // The model is dry, the radar wet: rain, heavy rain from 10 mm/h, snow at 0 °C or below.
  const dry = { ...hour(0, 0, 2), cloudCoverPct: 50, temperatureC: 8 };
  assert.equal(at(dry, radar([2, 2, 0, 0, 0, 0, 0, 0, 0])), "rain");
  assert.equal(at(dry, radar([12, 2, 0, 0, 0, 0, 0, 0, 0])), "heavyRain");
  assert.equal(at({ ...dry, temperatureC: -1 }, radar([2, 2, 0, 0, 0, 0, 0, 0, 0])), "snow");
  // Both agree, or no radar: the model's sky.
  assert.equal(at(rainy, radar([2, 2, 0, 0, 0, 0, 0, 0, 0])), "rain");
  assert.equal(at(rainy), "rain");
  assert.equal(at(dry), "partlyCloudy");
});

test("the rain tile's radar symbol: plain, faint while read, struck through when missing (RadarMark)", () => {
  assert.match(radarTitleMark(), /class="radar-mark head"/);
  assert.match(radarTitleMark("loading"), /class="radar-mark head loading"/);
  assert.match(radarTitleMark("missing"), /class="radar-mark head missing"/);
  assert.equal(radarStatus(null), null);
  assert.equal(radarStatus({ lat: 47.95, lon: 11.35 }), null, "never asked");
});
