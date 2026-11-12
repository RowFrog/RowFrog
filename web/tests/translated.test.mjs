// Every text the website shows through t() gets its German version from the build, also
// texts picked inside t(), e.g. t(mm < 2.5 ? "Light rain" : "Rain"), which the build once
// missed, so German pages showed "Light rain" (owner, 12 Nov 2026).
import { test } from "node:test";
import assert from "node:assert/strict";
import { execFileSync } from "node:child_process";
import { readFileSync, readdirSync } from "node:fs";
import { fileURLToPath } from "node:url";

const ROOT = fileURLToPath(new URL("../../", import.meta.url));
const APP = `${ROOT}web/public/app/`;

test("texts chosen inside t() are collected by the build and have German", () => {
  const out = execFileSync("python3", ["-c",
    "import json, sys; sys.path.insert(0, 'scripts'); import build_web as b; t = b.german_table(); print(json.dumps({k: t.get(k) for k in b.web_keys()}))"],
  { cwd: ROOT, encoding: "utf8" });
  const de = JSON.parse(out);
  const missing = [];
  for (const file of readdirSync(APP).filter((f) => f.endsWith(".js"))) {
    const source = readFileSync(APP + file, "utf8");
    for (const [, choice] of source.matchAll(/\bt\(([^()`"]*\?[^()`]*)\)/g)) {
      for (const [, text] of choice.matchAll(/"((?:[^"\\]|\\.)*)"/g)) if (!de[text]) missing.push(`${file}: ${text}`);
    }
  }
  assert.equal(de["Light rain"], "Leichter Regen");
  assert.deepEqual(missing, []);
});
