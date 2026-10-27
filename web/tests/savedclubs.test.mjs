import { test } from "node:test";
import assert from "node:assert/strict";

// A browser's storage, with a club saved on the pond it was once matched to
// and the catalog (kept for a day) that now has it on the Donau.
const kept = new Map();
globalThis.localStorage = {
  getItem: (k) => (kept.has(k) ? kept.get(k) : null),
  setItem: (k, v) => kept.set(k, String(v)),
  removeItem: (k) => kept.delete(k),
};
const club = { id: "ulmer-rc", name: "Ulmer Ruderclub Donau e.V.", shortName: "Ulmer RC", address: "x, 89073 Ulm", launchPoint: { lat: 48.39, lon: 10.0 }, launchPointVerified: false, source: "drv" };
kept.set("rf.clubs", JSON.stringify([
  { ...club, lakeId: "forellenbaechle", lakeName: "Forellenbächle", country: "de" },
  { id: "own-1", name: "Mein Steg", shortName: "Mein Steg", lakeId: "own-1", lakeName: "Mein Steg" },
]));
kept.set("rf.catalog", JSON.stringify({ at: Date.now(), lakes: [{ id: "donau-ulm", name: "Donau", country: "de", clubs: [club] }] }));

const { refreshSavedClubs, store } = await import("../public/app/shared.js");

test("a saved club moved to another water shows the new one; own places stay", async () => {
  assert.equal(await refreshSavedClubs(), true);
  assert.deepEqual(store.clubs.map((c) => [c.id, c.lakeId, c.lakeName]), [["ulmer-rc", "donau-ulm", "Donau"], ["own-1", "own-1", "Mein Steg"]]);
  assert.equal(await refreshSavedClubs(), false);
});
