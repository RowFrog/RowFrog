import { test } from "node:test";
import assert from "node:assert/strict";
import { backgroundFor } from "../public/app/backgrounds.js";

const b = { all: "sample:lake-waves", pages: { list: "none", clubPages: "satellite" }, clubs: { a: "custom:user-1.jpg", b: "bad" } };

test("a club's own picture, else its kind of page's, else the one for all pages", () => {
  assert.equal(backgroundFor("clubPages", "a", b), "custom:user-1.jpg");
  assert.equal(backgroundFor("clubPages", "c", b), "satellite");
  assert.equal(backgroundFor("clubPages", "b", b), "satellite");
  assert.equal(backgroundFor("list", "a", b), "none");
  assert.equal(backgroundFor("settings", null, b), "sample:lake-waves");
});
