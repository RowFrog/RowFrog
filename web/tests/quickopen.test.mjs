import { test } from "node:test";
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";

const kept = new Map();
globalThis.localStorage = {
  getItem: (k) => (kept.has(k) ? kept.get(k) : null),
  setItem: (k, v) => kept.set(k, String(v)),
  removeItem: (k) => kept.delete(k),
};
const { quickClub, quickLink, noteShown, lastShown } = await import("../public/app/quickopen.js");

// The installed website's Home Screen menu, as the app's (QuickActions.swift, decision 0048).
test("the menu links name no club; the page picks it", () => {
  assert.deepEqual(quickLink("/home"), { which: "home", part: null });
  assert.deepEqual(quickLink("/home/lake"), { which: "home", part: "lake" });
  assert.deepEqual(quickLink("/home/radar"), { which: "home", part: "radar" });
  assert.deepEqual(quickLink("/last"), { which: "last", part: null });
  assert.equal(quickLink("/club/home"), null);
  assert.equal(quickLink("/home/x"), null);
});

test("home is the first saved club; last the one shown last besides it, else the next", () => {
  const ids = ["mrc", "arc", "trv"];
  assert.equal(quickClub("home", ids, "trv"), "mrc");
  assert.equal(quickClub("last", ids, "trv"), "trv");
  assert.equal(quickClub("last", ids, "gone"), "arc");
  assert.equal(quickClub("last", ids, "mrc"), "arc");
  assert.equal(quickClub("last", ["mrc"], null), "mrc");
  assert.equal(quickClub("home", [], null), null);
});

test("only a saved club other than the first counts as last shown", () => {
  noteShown("mrc", ["mrc", "arc"]);
  assert.equal(lastShown(), null);
  noteShown("elsewhere", ["mrc", "arc"]);
  assert.equal(lastShown(), null);
  noteShown("arc", ["mrc", "arc"]);
  assert.equal(lastShown(), "arc");
});

test("both manifests carry the same four shortcuts", () => {
  const read = (name) => JSON.parse(readFileSync(new URL(`../public/app/${name}`, import.meta.url), "utf8"));
  const en = read("manifest.webmanifest");
  const de = read("manifest.de.webmanifest");
  const urls = ["/app/#/home", "/app/#/home/lake", "/app/#/home/radar", "/app/#/last"];
  assert.deepEqual(en.shortcuts.map((s) => s.url), urls);
  assert.deepEqual(de.shortcuts.map((s) => s.url), urls);
  assert.deepEqual(de.shortcuts.map((s) => s.name), ["Heimatverein", "Seeansicht", "Regenradar", "Zuletzt geöffnet"]);
  // Apart from the words, the two manifests are the same.
  const same = (m) => Object.fromEntries(Object.entries(m).filter(([k]) => !["shortcuts", "lang", "description"].includes(k)));
  assert.deepEqual(same(de), same(en));
});
