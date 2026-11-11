import { test } from "node:test";
import assert from "node:assert/strict";

// The reason under "Could not update" names the true cause (owner, 11 Nov 2026), as RefreshFailure in the app.
const kept = new Map();
globalThis.localStorage = {
  getItem: (k) => (kept.has(k) ? kept.get(k) : null),
  setItem: (k, v) => kept.set(k, String(v)),
  removeItem: (k) => kept.delete(k),
};

const { refreshFailure } = await import("../public/app/shared.js");
const status = (code) => Object.assign(new Error(`HTTP ${code}`), { status: code });
const online = (on) => Object.defineProperty(globalThis, "navigator", { value: { onLine: on }, configurable: true });

test("a refused download is not called a server error that fixes itself", () => {
  const [short, why] = refreshFailure(status(403));
  assert.match(short, /refused/);
  assert.match(why, /403/);
  assert.doesNotMatch(why, /fixes itself/);
  assert.match(refreshFailure(status(503))[1], /fixes itself/);
});

test("a missing club file names the 6-hour run, not 30 minutes", () => {
  const [, why] = refreshFailure(status(404));
  assert.match(why, /6 hours/);
  assert.doesNotMatch(why, /30 minutes/);
});

test("a failed fetch is only 'no internet connection' when the browser is offline", () => {
  online(false);
  assert.equal(refreshFailure(new TypeError("Failed to fetch"))[0], "no internet connection");
  online(true);
  assert.equal(refreshFailure(new TypeError("Failed to fetch"))[0], "the server could not be reached");
});

test("own places still blame the weather service", () => {
  assert.equal(refreshFailure(status(403), true)[0], "the weather service did not answer");
});

test("no text promises a forecast that may not be shown", () => {
  for (const error of [new Error("odd"), status(500), status(404)]) assert.doesNotMatch(refreshFailure(error)[1], /forecast shown stays/);
});
