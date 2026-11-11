import { test } from "node:test";
import assert from "node:assert/strict";
import { loadable } from "../public/app/logic.js";

// The same moves as the app's Loadable (LoadableTests.swift), as the club page takes them.
const at = 1_800_000_000_000;

test("a first load waits, then shows or fails", () => {
  const start = loadable.started(undefined);
  assert.equal(start.loading, true);
  assert.equal(start.value, null);
  assert.equal(start.failure, null);
  const done = loadable.loaded("forecast", at);
  assert.deepEqual(done, { value: "forecast", loadedAt: at, loading: false, failure: null });
  const failed = loadable.failing(start, "offline");
  assert.equal(failed.value, null);
  assert.equal(failed.loading, false);
  assert.equal(failed.failure, "offline");
});

test("a retry keeps the reason until a load works", () => {
  const retry = loadable.started(loadable.failing(loadable.started(undefined), "timeout"));
  assert.equal(retry.loading, true);
  assert.equal(retry.failure, "timeout");
  assert.equal(loadable.loaded("forecast", at).failure, null);
});

test("a failed update keeps the forecast and its time", () => {
  const updating = loadable.started(loadable.loaded("forecast", at));
  assert.equal(updating.loading, true);
  assert.equal(updating.value, "forecast");
  const failed = loadable.failing(updating, "refused");
  assert.deepEqual(failed, { value: "forecast", loadedAt: at, loading: false, failure: "refused" });
});
