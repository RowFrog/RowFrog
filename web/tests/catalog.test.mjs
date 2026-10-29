import { test } from "node:test";
import assert from "node:assert/strict";

// A browser's storage with a catalog copy older than a day (app #195).
const kept = new Map();
globalThis.localStorage = {
  getItem: (k) => (kept.has(k) ? kept.get(k) : null),
  setItem: (k, v) => kept.set(k, String(v)),
  removeItem: (k) => kept.delete(k),
};
const lakes = [{ id: "starnberger-see", name: "Starnberger See", country: "de", clubs: [] }];
const countries = [{ code: "de", clubs: 469 }];
kept.set("rf.catalog", JSON.stringify({ at: Date.now() - 3 * 24 * 3600e3, lakes, countries }));

let answer;
globalThis.fetch = async () => answer();
const { loadCatalog, loadCountryIndex } = await import("../public/app/shared.js");

test("an error status or an answer that is not JSON serves the last good catalog copy", async () => {
  answer = () => new Response("Bad gateway", { status: 502 });
  assert.deepEqual(await loadCatalog(), lakes);
  assert.deepEqual(await loadCountryIndex(), countries);
  answer = () => new Response("<html>publishing</html>", { status: 200 });
  assert.deepEqual(await loadCatalog(), lakes);
  answer = () => Promise.reject(new TypeError("offline"));
  assert.deepEqual(await loadCatalog(), lakes);
});

test("without a kept copy the error still shows", async () => {
  kept.delete("rf.catalog");
  answer = () => new Response("Bad gateway", { status: 502 });
  await assert.rejects(loadCatalog());
  await assert.rejects(loadCountryIndex());
});

test("map links follow the device until picked: Apple Maps on iPhone and iPad, Google Maps elsewhere", async () => {
  const { deviceMapsApp } = await import("../public/app/shared.js");
  assert.equal(deviceMapsApp("Mozilla/5.0 (iPhone; CPU iPhone OS 27_0 like Mac OS X)", 5), "apple");
  assert.equal(deviceMapsApp("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) Safari", 5), "apple");
  assert.equal(deviceMapsApp("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) Safari", 0), "google");
  assert.equal(deviceMapsApp("Mozilla/5.0 (Linux; Android 16; Pixel 9)", 5), "google");
  assert.equal(deviceMapsApp("Mozilla/5.0 (Windows NT 10.0; Win64; x64)", 0), "google");
});
