// Opens the built website (web/dist) in Chromium against the sample API files
// in testdata/api/v1, the same files the backend, app and unit tests share, and
// walks through it as a visitor: the safety notice, the club page, every tile's
// value page and the list. Fails on any JavaScript error. No internet: every
// request that does not go to the local server is cut off.
// Run: python scripts/build_web.py && node --test web/tests/browser/
import { test, before, after } from "node:test";
import assert from "node:assert/strict";
import { createServer } from "node:http";
import { readFile } from "node:fs/promises";
import { extname, join, normalize } from "node:path";
import { fileURLToPath } from "node:url";
import { chromium } from "playwright";

const ROOT = fileURLToPath(new URL("../../../", import.meta.url));
const DIST = join(ROOT, "web/dist");
const API = join(ROOT, "testdata/api/v1");
const TYPES = { ".html": "text/html", ".js": "text/javascript", ".css": "text/css", ".json": "application/json",
  ".png": "image/png", ".jpg": "image/jpeg", ".svg": "image/svg+xml", ".webmanifest": "application/manifest+json" };

const lakes = JSON.parse(await readFile(join(API, "lakes/index"), "utf8"));
const forecast = JSON.parse(await readFile(join(API, "clubs/mrc-1880/forecast"), "utf8"));
const club = lakes.flatMap((l) => l.clubs.map((c) => ({ ...c, lakeId: l.id }))).find((c) => c.id === "mrc-1880");

let server, base, browser;

before(async () => {
  server = createServer(async (req, res) => {
    const path = normalize(decodeURIComponent(new URL(req.url, "http://x").pathname));
    const api = path.startsWith("/v1/");
    let file = api ? join(API, path.slice(4)) : join(DIST, path);
    if (!api && path.endsWith("/")) file = join(file, "index.html");
    try {
      const body = await readFile(file);
      res.writeHead(200, { "Content-Type": api ? "application/json" : TYPES[extname(file)] ?? "application/octet-stream" });
      res.end(body);
    } catch {
      res.writeHead(404).end();
    }
  });
  await new Promise((done) => server.listen(0, "127.0.0.1", done));
  base = `http://127.0.0.1:${server.address().port}`;
  browser = await chromium.launch();
});

after(async () => {
  await browser?.close();
  server?.close();
});

/** A page with the sample API, the clock at the sample's time and JavaScript errors collected. */
async function open(storage = {}) {
  const context = await browser.newContext({ viewport: { width: 390, height: 844 }, locale: "en-GB", timezoneId: "Europe/Berlin" });
  await context.route((url) => !url.href.startsWith(base), (route) => route.abort());
  const page = await context.newPage();
  const errors = [];
  page.on("pageerror", (e) => errors.push(e.message));
  if (process.env.RF_DEBUG) page.on("pageerror", (e) => console.log("DEBUG", e.stack));
  if (process.env.RF_DEBUG) page.on("response", (r) => r.status() >= 400 && console.log("DEBUG", r.status(), r.url()));
  await page.clock.install({ time: new Date(forecast.generatedAt) });
  await page.addInitScript(([api, entries]) => {
    globalThis.RF_API = api;
    if (!sessionStorage.getItem("rf.test")) {
      sessionStorage.setItem("rf.test", "1");
      for (const [k, v] of Object.entries(entries)) localStorage.setItem(k, JSON.stringify(v));
    }
  }, [`${base}/v1`, storage]);
  return { page, errors, context };
}

const visitor = () => ({
  "rf.safety": { version: 1, at: forecast.generatedAt },
  "rf.tourSeen": true,
  "rf.tipsClosed": true,
  "rf.language": "en",
  "rf.clubs": [club],
});

test("a first visit starts with the safety notice, which needs a tick", async () => {
  const { page, errors, context } = await open({ "rf.language": "en" });
  await page.goto(`${base}/app/`);
  const button = page.locator("#continue");
  await button.waitFor();
  assert.equal(await button.isDisabled(), true, "the notice cannot be skipped");
  assert.deepEqual(errors, []);
  await context.close();
});

test("the club page shows the sample forecast and every tile opens its value page", async () => {
  const { page, errors, context } = await open(visitor());
  await page.goto(`${base}/app/#/club/mrc-1880`);
  // The page draws more than once while it loads; wait until the tiles are there.
  const found = await page.waitForFunction(() => {
    const tiles = [...document.querySelectorAll(".card:not(.now) [data-tile]")].map((e) => e.dataset.tile);
    return tiles.length >= 8 && tiles;
  }, null, { timeout: 20000 });
  const tiles = await found.jsonValue();
  for (const tile of new Set(tiles)) {
    await page.locator(`.card:not(.now) [data-tile="${tile}"]`).first().click();
    await page.waitForFunction((t) => location.hash.includes(`/value/${t}`), tile);
    await page.waitForTimeout(300);
    assert.deepEqual(errors, [], `after opening ${tile}`);
    // A value page that cannot load its forecast goes back to the club page by itself.
    assert.ok(await page.evaluate((t) => location.hash.includes(`/value/${t}`), tile), `${tile} went back`);
    await page.goBack();
    await page.waitForFunction(() => document.querySelectorAll(".card:not(.now) [data-tile]").length >= 8, null, { timeout: 20000 });
  }
  await context.close();
});

test("the list shows the saved club", async () => {
  const { page, errors, context } = await open(visitor());
  await page.goto(`${base}/app/#/list`);
  try {
    await page.waitForFunction((name) => document.body.innerText.includes(name), club.shortName ?? club.name, { timeout: 20000 });
  } catch (e) {
    throw new Error(`${e.message}\nThe page shows: ${(await page.locator("body").innerText()).slice(0, 500)}`);
  }
  assert.deepEqual(errors, []);
  await context.close();
});
