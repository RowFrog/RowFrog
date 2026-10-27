import { test } from "node:test";
import assert from "node:assert/strict";
import { clubNameHtml } from "../public/app/shared.js";

test("club titles offer the long name with the short one in brackets, and the short name", () => {
  const html = clubNameHtml({ name: "Münchener Ruder-Club von 1880 e.V.", shortName: "MRC 1880" });
  assert.match(html, /class="fit-long">Münchener Ruder-Club von 1880 e\.V\. \(MRC 1880\)</);
  assert.match(html, /class="fit-short">MRC 1880</);
});

test("a club without a separate short name has one title", () => {
  assert.equal(clubNameHtml({ name: "Seeclub", shortName: "Seeclub" }), '<span class="fit-one">Seeclub</span>');
  assert.equal(clubNameHtml({ name: "Seeclub" }), '<span class="fit-one">Seeclub</span>');
  assert.equal(clubNameHtml(null, "mrc-1880"), '<span class="fit-one">mrc-1880</span>');
});
