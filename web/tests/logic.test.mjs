import { test } from "node:test";
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import {
  isStale, shownLight, currentHour, nextHours, beaufort, windValue, compass, searchClubs, fold, town, overlayBox,
  sky, skyIcon, precipitationKind, lightFor, feelsLikeNote, pressureTrend, estimatedWater, iceOff, iceValue, sunState,
  applyBoat, applyBoatToHour, coldWaterKit, place, twilight, applyLimitsToHour, limitsFor, riverForBoat, GROUPS,
} from "../public/app/logic.js";

const forecast = JSON.parse(readFileSync(new URL("fixtures/forecast.json", import.meta.url)));
const lakes = JSON.parse(readFileSync(new URL("fixtures/lakes.json", import.meta.url)));
const generated = new Date(forecast.generatedAt);
const at = (ms) => new Date(generated.getTime() + ms);

test("a forecast more than 3 hours old is out of date, and only green turns grey", () => {
  assert.equal(isStale(forecast, at(2.9 * 3600e3)), false);
  assert.equal(isStale(forecast, at(3.1 * 3600e3)), true);
  assert.equal(shownLight("green", true), "grey");
  assert.equal(shownLight("amber", true), "amber");
  assert.equal(shownLight("red", true), "red");
  assert.equal(shownLight("green", false), "green");
});

test("the current hour is the one the time falls in", () => {
  const second = new Date(forecast.hours[1].time);
  assert.equal(currentHour(forecast.hours, new Date(second.getTime() + 30 * 60e3)), forecast.hours[1]);
  assert.equal(currentHour(forecast.hours, new Date("2000-01-01")), forecast.hours[0], "too early: the first hour");
  assert.equal(nextHours(forecast.hours, second, 48)[0], forecast.hours[1]);
  assert.ok(nextHours(forecast.hours, second, 48).length <= 48);
  // Without a count it keeps every later hour: the night tail past hour 48 (12 Nov 2026).
  const long = Array.from({ length: 58 }, (_, i) => ({ time: new Date(Date.parse(forecast.hours[0].time) + i * 3600e3).toISOString() }));
  assert.equal(nextHours(long, new Date(long[0].time)).length, 58);
});

test("wind units", () => {
  assert.equal(windValue(10, "kmh"), 36);
  assert.equal(windValue(10, "ms"), 10);
  assert.equal(windValue(10, "kn"), 19);
  assert.equal(beaufort(0.1), 0);
  assert.equal(beaufort(5.5), 4);
  assert.equal(beaufort(40), 12);
  assert.equal(compass(0), "N");
  assert.equal(compass(277), "W");
  assert.equal(compass(359), "N");
});

test("search finds clubs by short name, town or lake, without accents", () => {
  assert.equal(fold("Münchener Straße"), "munchener strasse");
  assert.equal(searchClubs(lakes, "mrc")[0].club.id, "mrc-1880");
  assert.ok(searchClubs(lakes, "starnberg").some((r) => r.club.id === "mrc-1880"));
  assert.ok(searchClubs(lakes, "munchener ruder").some((r) => r.club.id === "mrc-1880"));
  assert.deepEqual(searchClubs(lakes, "   "), []);
});

test("the sky as in the app: symbol, title and what falls", () => {
  assert.equal(sky(0), "clear");
  assert.equal(sky(65), "heavyRain");
  assert.equal(sky(96), "hail");
  assert.equal(sky(68), "sleet");
  assert.equal(sky(69), "sleet");
  assert.equal(precipitationKind("sleet"), "Sleet");
  assert.deepEqual(skyIcon("clear", true), ["moon-star", "moon"]);
  assert.equal(precipitationKind("showers"), "Rain");
  assert.equal(precipitationKind("partlyCloudy"), null);
});

test("a condition's light comes from its reasons", () => {
  const hour = { reasons: [{ condition: "gusts", light: "amber" }, { condition: "lake_warning", light: "red" }, { condition: "fog", light: "amber" }] };
  assert.equal(lightFor(hour, ["wind", "gusts", "lake_warning"]), "red");
  assert.equal(lightFor(hour, ["waves"]), null);
  assert.equal(feelsLikeNote({ temperatureC: 8, apparentTemperatureC: 4, windSpeedMs: 5 }), "Colder from wind chill");
  assert.equal(pressureTrend(-1.2), "Falling");
});

test("water and ice: the estimate only without a station, ice only when it matters", () => {
  assert.equal(estimatedWater(forecast), null);
  assert.equal(estimatedWater({ waterModelC: 7 }), 7);
  assert.equal(estimatedWater({ waterEstimate: { celsius: 9 }, waterModelC: 7 }), 9);
  assert.equal(iceOff({ status: "open", basis: "season" }), true);
  assert.equal(iceOff(null, new Date("2026-07-01")), true);
  assert.equal(iceOff(null, new Date("2026-01-10")), false);
  assert.equal(iceValue({ ice: { status: "edges" } }), "Shore ice possible");
  assert.equal(iceValue({ ice: { status: "open" }, waterTemperature: { celsius: 12 } }), null);
});

test("the sun is up between sunrise and sunset, else the next sunrise", () => {
  const f = { daylight: [{ date: "2026-10-26", sunrise: "2026-10-26T05:48:00Z", sunset: "2026-10-26T16:09:00Z" },
    { date: "2026-10-27", sunrise: "2026-10-27T05:49:00Z", sunset: "2026-10-27T16:07:00Z" }] };
  assert.equal(sunState(f, new Date("2026-10-26T12:00:00Z")).up, true);
  const night = sunState(f, new Date("2026-10-26T20:00:00Z"));
  assert.equal(night.up, false);
  assert.equal(night.sunrise.toISOString(), "2026-10-27T05:49:00.000Z");
});

test("big boats get the app's looser limits; small boats keep the backend's light", () => {
  assert.equal(applyBoat(forecast, "small"), forecast);
  const hour = { time: "2026-10-26T12:00:00Z", light: "red", windSpeedMs: 7, windGustMs: 11, waveHeightM: 0.1,
    reasons: [{ condition: "wind", light: "amber" }, { condition: "gusts", light: "red" }, { condition: "single_cold", light: "amber" },
      { condition: "lake_strong_wind", light: "red" }, { condition: "daylight", light: "red" }] };
  const warm = applyBoatToHour({ ...hour, reasons: hour.reasons.filter((r) => r.condition !== "daylight") }, "big", 16);
  // Gusts 11 m/s: amber from 10.8 for big boats; the lake's strong-wind light is amber for them.
  assert.deepEqual(warm.reasons, [{ condition: "lake_strong_wind", light: "amber" }, { condition: "gusts", light: "amber" }]);
  assert.equal(warm.light, "amber");
  // Very cold water: wind limits 1 m/s lower; cold water itself shows as the badge, not in the light.
  const cold = applyBoatToHour(hour, "big", 8);
  assert.equal(cold.light, "red", "the sun is still down");
  assert.ok(!cold.reasons.some((r) => ["cold_water", "cool_water", "single_cold"].includes(r.condition)));
  assert.equal(cold.reasons.find((r) => r.condition === "gusts").light, "amber");
  assert.ok(applyBoatToHour(hour, "big", 3).reasons.some((r) => r.condition === "freezing_water" && r.light === "amber"));
});

test("town from an address and the ice picture's place", () => {
  assert.equal(town("Dampfschiffstraße 6, 82319 Starnberg"), "Starnberg");
  assert.equal(town(null), null);
  const box = overlayBox([11, 47, 12, 48], [11.5, 47, 12, 47.5]);
  assert.deepEqual(box, { left: 50, top: 50, width: 50, height: 50 });
});

test("cold water: what to bring, as the app's badge", () => {
  assert.equal(coldWaterKit(16), null);
  assert.equal(coldWaterKit(null), null);
  assert.equal(coldWaterKit(12.7), "lifeJacket");
  assert.equal(coldWaterKit(8, "small"), "partnerBoat");
  assert.equal(coldWaterKit(8, "big"), "nearShore");
});

test("place reads like the app's, and twilight says sunrise or sunset", () => {
  assert.equal(place("Starnberger See", "Starnberg"), "Starnberger See · Starnberg");
  assert.equal(place("Water near Aken", "Aken"), "Aken");
  assert.equal(place("Water near Aken", null), "Water near Aken");
  const f = { daylight: [{ date: "2026-10-26", sunrise: "2026-10-26T05:49:00Z", sunset: "2026-10-26T16:07:00Z" }] };
  assert.equal(twilight(f, { time: "2026-10-26T16:00:00Z" }).kind, "sunset");
  assert.equal(twilight(f, { time: "2026-10-26T05:00:00Z" }).time.toISOString(), "2026-10-26T05:49:00.000Z");
  assert.equal(twilight(f, { time: "2026-10-26T12:00:00Z" }), null);
});

test("the river current counts with the boat's own limits (app #182)", () => {
  const hour = { time: "2026-10-26T10:00:00Z", windSpeedMs: 2, windGustMs: 3, waveHeightM: 0.05, reasons: [{ condition: "current", light: "amber" }], light: "amber" };
  const small = GROUPS[0];
  // The app's limits: amber from 1.5 m/s.
  assert.equal(applyLimitsToHour(hour, limitsFor(small), 15, 1.8).light, "amber");
  // A crew that allows 2 m/s gets green, with a note that the app would say amber.
  const looser = applyLimitsToHour(hour, limitsFor(small, { currentAmber: 2 }), 15, 1.8);
  assert.equal(looser.light, "green");
  assert.deepEqual(looser.notes.map((n) => n.condition), ["current"]);
  // A stricter crew: red above 1.2 m/s.
  assert.equal(applyLimitsToHour(hour, limitsFor(small, { currentAmber: 0.8, currentRed: 1.2 }), 15, 1.3).light, "red");
  // Past the gauge's hours the backend's reason stays as it is.
  assert.equal(applyLimitsToHour(hour, limitsFor(small, { currentAmber: 2 }), 15).light, "amber");
  // The Current tile follows the boat's limits.
  const river = { now: { speedMs: 1.8, state: "normal", light: "amber" }, limits: { currentAmberMs: 1.5, currentRedMs: 2.5 } };
  const mine = riverForBoat(river, limitsFor(small, { currentAmber: 2 }));
  assert.equal(mine.now.light, "green");
  assert.equal(mine.limits.currentAmberMs, 2);
  assert.equal(riverForBoat({ ...river, now: { ...river.now, state: "high" } }, limitsFor(small, { currentAmber: 2 })).now.light, "amber");
});

test("the night's dark hours fold into one line with the worst of each column", async () => {
  const { nightParts, nightSummary } = await import("../public/app/logic.js");
  const base = Date.UTC(2026, 9, 30, 15);
  const hours = [true, true, false, false, false, true].map((up, i) => ({
    time: new Date(base + i * 3600e3).toISOString(), sunUp: up, light: up ? "green" : "red", reasons: [],
    temperatureC: [5, 3, 1, -0.6, 2, 4][i], apparentTemperatureC: [3, 1, -1, -3, 0, 2][i],
    windSpeedMs: i, windGustMs: i * 2, waveHeightM: 0.1, precipitationMm: 0.2, visibilityM: 20000 - i,
  }));
  const parts = nightParts(hours);
  assert.equal(parts.length, 4, "two day hours, one night, one day hour");
  assert.equal(parts[2].night.length, 3);
  const n = nightSummary(parts[2].night);
  assert.equal(n.lowestC, -0.6);
  assert.equal(n.frost, true);
  assert.equal(n.lowestFeelsLikeC, -3);
  assert.equal(n.gustMs, 8);
  assert.ok(Math.abs(n.rainMm - 0.6) < 1e-9);
  assert.equal(n.end, new Date(base + 5 * 3600e3).toISOString());
  const startsAtNight = nightParts(hours.slice(2));
  assert.ok(startsAtNight[0].hour, "the first hour keeps its row at night");
  assert.equal(startsAtNight[1].night.length, 2);
  assert.ok(nightParts([hours[0], hours[2], hours[5]]).every((p) => p.hour), "one dark hour stays a row");
  const dusk = { ...hours[2], light: "amber", reasons: [{ condition: "twilight", light: "amber" }] };
  assert.ok(nightParts([hours[0], dusk, hours[3], hours[4]])[1].hour, "the hour the sun sets in keeps its row");
});

test("now takes the daylight light of this minute (Forecast.current)", async () => {
  const { nowHour } = await import("../public/app/logic.js");
  const forecast = {
    daylight: [{ sunrise: "2026-11-05T06:02:00Z", sunset: "2026-11-05T15:51:00Z" }, { sunrise: "2026-11-06T06:04:00Z", sunset: "2026-11-06T15:49:00Z" }],
    hours: [{ time: "2026-11-05T14:00:00Z", light: "amber", reasons: [{ condition: "twilight", light: "amber" }], sunUp: true },
      { time: "2026-11-05T15:00:00Z", light: "red", reasons: [{ condition: "daylight", light: "red" }], sunUp: true }],
  };
  const green = nowHour(forecast, new Date("2026-11-05T14:40:00Z"));
  assert.equal(green.light, "green");
  assert.deepEqual(green.reasons, []);
  const soon = nowHour(forecast, new Date("2026-11-05T14:51:00Z"));
  assert.equal(soon.light, "amber");
  assert.equal(soon.reasons[0].condition, "sunset_soon");
  const after = nowHour(forecast, new Date("2026-11-05T15:55:00Z"));
  assert.equal(after.light, "red");
  assert.equal(after.reasons[0].condition, "daylight");
  assert.equal(after.sunUp, false);
  // Another amber reason stays amber.
  forecast.hours[0].reasons.push({ condition: "wind", light: "amber" });
  assert.equal(nowHour(forecast, new Date("2026-11-05T14:30:00Z")).light, "amber");
  // The hour itself, as the 48 hours show it, keeps its own light.
  assert.equal(forecast.hours[1].light, "red");
});

test("an hour in which the daylight changes shows half and half (DaylightRule.halves)", async () => {
  const { hourHalves, daylightHalves, daylightAt, nightParts, sunDaysOf } = await import("../public/app/logic.js");
  const forecast = { daylight: [{ sunrise: "2026-11-06T06:04:00Z", sunset: "2026-11-06T15:49:00Z" }] };
  const days = sunDaysOf(forecast);
  assert.equal(daylightAt(Date.parse("2026-11-06T14:48:00Z"), days), "green");
  assert.equal(daylightAt(Date.parse("2026-11-06T14:49:00Z"), days), "amber");
  assert.equal(daylightAt(Date.parse("2026-11-06T15:49:00Z"), days), "red");
  const hour = (time, light, condition) => ({ time, light, reasons: [{ condition, light }], sunUp: true });
  assert.deepEqual(hourHalves(forecast, hour("2026-11-06T14:00:00Z", "amber", "twilight")), { start: "green", end: "amber" });
  assert.deepEqual(hourHalves(forecast, hour("2026-11-06T15:00:00Z", "red", "daylight")), { start: "amber", end: "red" });
  assert.deepEqual(hourHalves(forecast, hour("2026-11-06T06:00:00Z", "red", "daylight")), { start: "red", end: "green" });
  assert.equal(hourHalves(forecast, hour("2026-11-06T14:00:00Z", "amber", "twilight"), true), null, "no halves on an old forecast");
  // Another reason sets a floor: amber wind leaves green-to-amber one colour.
  const windy = hour("2026-11-06T14:00:00Z", "amber", "twilight");
  windy.reasons.push({ condition: "wind", light: "amber" });
  assert.equal(hourHalves(forecast, windy), null);
  // A relaxed part under 10 minutes is dropped; a stricter one always shows.
  const late = [{ sunrise: Date.parse("2026-11-06T06:04:00Z"), sunset: Date.parse("2026-11-06T15:05:00Z") }];
  assert.equal(daylightHalves(Date.parse("2026-11-06T14:00:00Z"), late), null, "5 green minutes before 14:05 are dropped");
  const late6 = [{ sunrise: Date.parse("2026-11-06T06:55:00Z"), sunset: Date.parse("2026-11-06T15:49:00Z") }];
  assert.equal(daylightHalves(Date.parse("2026-11-06T06:00:00Z"), late6), null, "5 green minutes after a 06:55 sunrise are dropped");
  const tiny = [{ sunrise: Date.parse("2026-11-06T06:04:00Z"), sunset: Date.parse("2026-11-06T15:55:00Z") }];
  assert.deepEqual(daylightHalves(Date.parse("2026-11-06T14:00:00Z"), tiny), { start: "green", end: "amber" }, "5 amber minutes are stricter, so they show");
  // The sunset hour keeps its row even with the sun down at half past.
  const dusk = { time: "2026-11-06T15:00:00Z", light: "red", reasons: [{ condition: "daylight", light: "red" }], sunUp: false };
  const night = (t) => ({ time: t, light: "red", reasons: [{ condition: "daylight", light: "red" }], sunUp: false });
  const parts = nightParts([night("2026-11-06T14:00:00Z"), dusk, night("2026-11-06T16:00:00Z"), night("2026-11-06T17:00:00Z")], days);
  assert.ok(parts[1].hour, "the hour the sun sets in keeps its row");
});

test("the top tile shows the worst nearby value that sets the light (app #409)", async () => {
  const { nearbyCondition, shownWind, shownWaveHeightM, shownVisibilityM, reasonCondition } = await import("../public/app/logic.js");
  // Owner, 6 Nov 2026: no 15 km visibility at the launch point when there is fog 300 m out.
  const foggy = {
    windSpeedMs: 2, windGustMs: 3, waveHeightM: 0.05, visibilityM: 15000,
    nearby: { light: "red", windMs: 1, gustMs: 2, waveM: 0, visM: 300, other: "red", otherCause: "fog" },
    reasons: [{ condition: "nearby_water", light: "red", topic: "fog", value: 300 }],
  };
  assert.equal(nearbyCondition(foggy), "visibility");
  assert.equal(shownVisibilityM(foggy), 300);
  assert.deepEqual(shownWind(foggy), { speed: 2, gust: 3 }, "wind does not set the light, so it stays the launch point's");
  assert.equal(shownWaveHeightM(foggy), 0.05);
  assert.equal(reasonCondition("nearby_water", "fog"), "visibility", "the reason takes the icon of its cause");
  const windy = { ...foggy, nearby: { ...foggy.nearby, windMs: 9, gustMs: 12 }, reasons: [{ condition: "nearby_water", light: "red", topic: "gusts", value: 12 }] };
  assert.deepEqual(shownWind(windy), { speed: 9, gust: 12 });
  assert.equal(shownVisibilityM(windy), 15000);
  const plain = { ...foggy, reasons: [] };
  assert.equal(nearbyCondition(plain), null, "without the nearby reason the tile shows the launch point's own values");
  assert.equal(shownVisibilityM(plain), 15000);
});

test("satellite tiles ask for the double-size version on sharp screens", async () => {
  const { satelliteUrl } = await import("../public/app/basemap.js");
  assert.match(satelliteUrl("k"), /\{y\}\{r\}\.jpg\?key=k$/);
});

test("the night after the 48 hours is marked as coming from the coarser model", async () => {
  const { coarserModel } = await import("../public/app/logic.js");
  const part = (model, resolutionKm, fromHour, toHour) => ({ model, provider: "DWD", resolutionKm, fromHour, toHour });
  const f = { generatedAt: "2026-10-18T17:20:00+00:00", forecastSource: { parts: [part("ICON-D2", 2.2, 0, 48), part("ICON-EU", 7, 48, 60)] } };
  const at = (i) => ({ time: new Date(Date.parse("2026-10-18T17:00:00Z") + i * 3600e3).toISOString() });
  assert.equal(coarserModel(f, at(0)), null);
  assert.equal(coarserModel(f, at(47)), null);
  assert.equal(coarserModel(f, at(48)).model, "ICON-EU");
  assert.equal(coarserModel({ ...f, forecastSource: { parts: [part("ICON-D2", 2.2, 0, 48)] } }, at(50)), null);
  assert.equal(coarserModel({}, at(50)), null);
});

test("a night that ends the table is whole when the sun rises in the next hour", async () => {
  const { endsAtSunrise } = await import("../public/app/logic.js");
  const days = [{ sunrise: Date.parse("2026-11-15T06:21:00Z"), sunset: Date.parse("2026-11-15T15:35:00Z") }];
  assert.equal(endsAtSunrise(Date.parse("2026-11-15T06:00:00Z"), days), true, "17–07: finished up to sunrise");
  assert.equal(endsAtSunrise(Date.parse("2026-11-15T03:00:00Z"), days), false, "cut off in the dark: 17–");
  assert.equal(endsAtSunrise(Date.parse("2026-11-15T06:00:00Z"), []), false);
});
