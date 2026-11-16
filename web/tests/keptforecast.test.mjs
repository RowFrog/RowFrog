import { test } from "node:test";
import assert from "node:assert/strict";

// Opened without internet, a club shows the forecast kept from the last visit with
// the reason, as the app does (ForecastStore.showKept), instead of "No forecast".
globalThis.localStorage = { getItem: () => null, setItem: () => {}, removeItem: () => {} };
// Cache Storage as the browser has it, one box per name.
const boxes = new Map();
globalThis.caches = {
  open: async (name) => {
    if (!boxes.has(name)) {
      const kept = new Map();
      boxes.set(name, {
        put: async (key, response) => kept.set(key, await response.text()),
        match: async (key) => (kept.has(key) ? new Response(kept.get(key)) : undefined),
      });
    }
    return boxes.get(name);
  },
};

let answer;
globalThis.fetch = async () => answer();
const { loadForecast, forecasts, keepForecast, keptForecast } = await import("../public/app/shared.js");

const hourFromNow = (h) => new Date(Date.now() + h * 3600e3).toISOString();
const forecast = (clubId, h) => ({ clubId, generatedAt: new Date().toISOString(), hours: [{ time: hourFromNow(h), light: "green", reasons: [] }] });

test("a forecast that came is kept, and serves with the reason when the next visit is offline", async () => {
  answer = () => new Response(JSON.stringify(forecast("mrc-1880", 1)), { status: 200 });
  await loadForecast("mrc-1880", true);
  // Kept in the background, without holding up the page.
  await new Promise((resolve) => setTimeout(resolve, 20));
  forecasts.clear();
  answer = () => Promise.reject(new TypeError("Failed to fetch"));
  const shown = await loadForecast("mrc-1880", true);
  assert.equal(shown.clubId, "mrc-1880");
  const state = forecasts.get("mrc-1880");
  assert.ok(state.failure instanceof TypeError);
  assert.equal(state.loading, false);
  assert.ok(state.loadedAt <= Date.now());
});

test("without a kept forecast the error still shows", async () => {
  answer = () => Promise.reject(new TypeError("Failed to fetch"));
  await assert.rejects(loadForecast("nowhere", true));
  assert.equal(forecasts.get("nowhere").value, null);
});

test("a kept forecast whose hours are all past is not shown", async () => {
  await keepForecast("old-club", forecast("old-club", -2), Date.now() - 3 * 86400e3);
  assert.equal(await keptForecast("old-club"), null);
  await keepForecast("new-club", forecast("new-club", 2));
  assert.equal((await keptForecast("new-club")).forecast.clubId, "new-club");
});
