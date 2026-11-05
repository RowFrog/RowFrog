import { test } from "node:test";
import assert from "node:assert/strict";
import { suggestOffered, suggestRow } from "../public/app/suggest.js";

const club = { id: "mrc-1880", name: "Münchener Ruder-Club von 1880 e.V.", launchPoint: { lat: 47.99667, lon: 11.34745 } };

test("a launch point can be suggested only for a club from the lists that has not confirmed its own", () => {
  assert.equal(suggestOffered({ ...club, launchPointVerified: false }), true);
  assert.equal(suggestOffered({ ...club, launchPointVerified: true }), false);
  assert.equal(suggestOffered({ ...club, id: "own-123", launchPointVerified: false }), false);
});

test("the button asks for a better point once one was checked by hand", () => {
  assert.match(suggestRow({ ...club, launchPointVerified: false }), /Suggest the launch point/);
  assert.match(suggestRow({ ...club, launchPointVerified: false, launchPointSet: true }), /Suggest a better launch point/);
  assert.equal(suggestRow({ ...club, launchPointVerified: true }), "");
});
