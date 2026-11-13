// "Build 723 · 22a69ce" in the footer, as Settings > About in the app (BuildInfo.swift).
// scripts/build_web.py stamps the real numbers into the BUILD line; the source says 1 · dev.
import { test } from "node:test";
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { BUILD, footerLinks } from "../public/app/shared.js";

test("the footer names the build and the commit", () => {
  assert.deepEqual(BUILD, { build: "1", commit: "dev" });
  assert.match(footerLinks(), /<span class="build">Build 1 · dev<\/span>/);
});

test("the line build_web.py stamps is still there", () => {
  const shared = readFileSync(new URL("../public/app/shared.js", import.meta.url), "utf-8");
  assert.ok(shared.includes('export const BUILD = { build: "1", commit: "dev" };'));
  const index = readFileSync(new URL("../public/index.html", import.meta.url), "utf-8");
  assert.ok(index.includes("Build 1 · dev"));
});
