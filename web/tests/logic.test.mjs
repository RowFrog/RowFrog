import { test } from "node:test";
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import {
  isStale, shownLight, currentHour, nextHours, days, beaufort, windValue, compass, searchClubs, fold,
  waterTemperature, town, overlayBox, localDay,
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

test("days start today and show only daylight hours", () => {
  const list = days(forecast, generated);
  assert.equal(list[0].day, localDay(generated));
  for (const d of list) {
    assert.ok(d.minC <= d.maxC);
    assert.ok(d.lights.length <= 17, "no night hours");
  }
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

test("water temperature: measured first", () => {
  assert.equal(waterTemperature(forecast).basis, "measured");
  assert.equal(waterTemperature({ waterModelC: 7 }).basis, "air");
  assert.equal(waterTemperature({}), null);
});

test("town from an address and the ice picture's place", () => {
  assert.equal(town("Dampfschiffstraße 6, 82319 Starnberg"), "Starnberg");
  assert.equal(town(null), null);
  const box = overlayBox([11, 47, 12, 48], [11.5, 47, 12, 47.5]);
  assert.deepEqual(box, { left: 50, top: 50, width: 50, height: 50 });
});
