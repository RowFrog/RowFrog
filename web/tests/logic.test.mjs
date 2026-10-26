import { test } from "node:test";
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import {
  isStale, shownLight, currentHour, nextHours, beaufort, windValue, compass, searchClubs, fold, town, overlayBox,
  sky, skyIcon, precipitationKind, lightFor, feelsLikeNote, pressureTrend, estimatedWater, iceOff, iceValue, sunState,
  applyBoat, applyBoatToHour, coldWaterKit, place, twilight,
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
