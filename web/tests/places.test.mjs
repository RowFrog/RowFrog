import { test } from "node:test";
import assert from "node:assert/strict";
import { ownForecast, sunDay, daylight, isOwn } from "../public/app/ownplace.js";
import { countryRows, rowMatches, inCountry } from "../public/app/countries.js";
import { nearestWater } from "../public/app/addplace.js";

test("sunrise and sunset as the backend works them out", () => {
  const s = sunDay(Date.UTC(2026, 9, 26), 47.99667, 11.34745);
  assert.equal(new Date(s.rise).toISOString().slice(0, 16), "2026-10-26T05:49");
  assert.equal(new Date(s.set).toISOString().slice(0, 16), "2026-10-26T16:07");
  assert.equal(sunDay(Date.UTC(2026, 5, 21), 80, 0), null);
});

test("daylight: green all hour, amber with sunrise inside, red in the dark", () => {
  const day = [{ rise: Date.UTC(2026, 9, 26, 5, 50), set: Date.UTC(2026, 9, 26, 16, 7) }];
  assert.deepEqual(daylight(Date.UTC(2026, 9, 26, 10), day, true).slice(0, 2), ["daylight", "green"]);
  assert.deepEqual(daylight(Date.UTC(2026, 9, 26, 5), day, true).slice(0, 2), ["twilight", "amber"]);
  assert.deepEqual(daylight(Date.UTC(2026, 9, 26, 20), day, false).slice(0, 2), ["daylight", "red"]);
});

test("an own place's hours get the backend's rowing light", () => {
  const club = { id: "own-x", launchPoint: { lat: 47.9, lon: 11.3 } };
  const hourly = {
    time: ["2026-10-26T10:00", "2026-10-26T11:00", "2026-10-26T12:00"],
    wind_speed_10m: [3, 6, 9], wind_gusts_10m: [5, 9, 13], visibility: [20000, 800, 20000], cape: [0, 0, 1200], precipitation: [0, 0, 2],
    is_day: [1, 1, 1],
  };
  const f = ownForecast(club, { hourly }, new Date("2026-10-26T09:30:00Z"));
  assert.equal(f.lakeId, null);
  assert.deepEqual(f.hours.map((x) => x.light), ["green", "amber", "red"]);
  assert.deepEqual(f.hours[1].reasons.map((r) => r.condition), ["wind", "gusts", "fog"]);
  assert.deepEqual(f.hours[2].reasons.map((r) => r.condition), ["wind", "gusts", "thunderstorm"]);
  assert.ok(isOwn(club.id) && !isOwn("mrc-1880"));
});

const lakes = [
  { id: "bodensee", name: "Bodensee", country: "de", center: { lat: 47.6, lon: 9.4 }, clubs: [
    { id: "a", name: "RV Lindau", address: "x, 88131 Lindau", country: "de" },
    { id: "b", name: "RC Bregenz", address: "x, 6900 Bregenz", country: "at", region: "Vorarlberg" }] },
  { id: "near-aken", name: "Water near Aken", country: "de", center: { lat: 51.85, lon: 12.05 }, clubs: [{ id: "c", name: "RV Aken", address: "x, 06385 Aken", country: "de" }] },
];

test("a border lake lists each country's own clubs", () => {
  assert.deepEqual(inCountry(lakes, "at").map((l) => l.clubs.map((c) => c.id)), [["b"]]);
  assert.equal(inCountry(lakes, "de").length, 2);
});

test("rows by water or by town, with a filter on clubs and towns", () => {
  const de = inCountry(lakes, "de");
  assert.deepEqual(countryRows(de, false).map((r) => [r.title, r.unknown]), [["Aken", true], ["Bodensee", false]]);
  assert.deepEqual(countryRows(de, true).map((r) => r.title), ["Aken", "Lindau"]);
  const [aken, boden] = countryRows(de, false);
  assert.ok(rowMatches(boden, "lindau") && !rowMatches(aken, "lindau"));
});

test("an own place is named after water within 2 km", () => {
  assert.equal(nearestWater(lakes, { lat: 47.605, lon: 9.41 })?.id, "bodensee");
  assert.equal(nearestWater(lakes, { lat: 48.5, lon: 9.4 }), null);
});
