import { test } from "node:test";
import assert from "node:assert/strict";
import { UNITS, unitStep } from "../public/app/logic.js";

const close = (a, b, eps = 1e-3) => assert.ok(Math.abs(a - b) < eps, `${a} ≠ ${b}`);

test("units convert as the app's Units.swift", () => {
  close(UNITS.temperature.options.fahrenheit.from(10), 50);
  close(UNITS.wind.options.mph.from(10), 22.369);
  close(UNITS.wind.options.kn.from(10), 19.438);
  assert.equal(UNITS.wind.options.bft.from(5.5), 4);
  close(UNITS.waves.options.cm.from(0.15), 15);
  close(UNITS.waves.options.ft.from(0.3048), 1);
  close(UNITS.rain.options.in.from(25.4), 1);
  close(UNITS.distance.options.mi.from(1609.344), 1);
  close(UNITS.distance.options.nm.from(1852), 1);
  close(UNITS.pressure.options.inhg.from(1013.25), 29.921);
  close(UNITS.pressure.options.mmhg.from(1013.25), 760.0, 0.01);
  close(UNITS.pressure.options.bar.from(1013), 1.013);
});

test("a difference converts without the offset", () => {
  close(unitStep(UNITS.temperature.options.fahrenheit, 5), 9);
  close(unitStep(UNITS.temperature.options.celsius, 5), 5);
});

test("every kind has its standard unit among its options", () => {
  for (const kind of Object.values(UNITS)) assert.ok(kind.options[kind.standard]);
});

test("the Beaufort chart scale keeps the order of line and limits and rounds to the force", async () => {
  const { beaufort, beaufortScale } = await import("../public/app/logic.js");
  let last = -1;
  for (let ms = 0; ms <= 40; ms += 0.05) {
    const b = beaufortScale(ms);
    assert.ok(b >= last, `not rising at ${ms}`);
    last = b;
    if (Math.abs(b - Math.round(b) - 0.5) > 1e-6) assert.equal(Math.round(b), beaufort(ms), `at ${ms} m/s`);
  }
  close(beaufortScale(5.5), 3.5);
  assert.ok(beaufortScale(5.9) > beaufortScale(5.5));
});
