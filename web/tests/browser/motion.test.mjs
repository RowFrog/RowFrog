// How the website moves between club pages, against the table every app and website change shares
// (testdata/motion.json; owner, 12 Nov 2026: "exactly as the Weather app", after the website had no slide at all).
// Records the motion each page change asks for (document.startViewTransition with data-motion), so it runs in
// Chromium without judging the animation by eye.
// Run: python scripts/build_web.py && node --test web/tests/browser/
import { test, before, after } from "node:test";
import assert from "node:assert/strict";
import { createServer } from "node:http";
import { readFile } from "node:fs/promises";
import { extname, join, normalize } from "node:path";
import { fileURLToPath } from "node:url";
import { chromium } from "playwright";
import { CSP } from "../../functions/_middleware.js";

const ROOT = fileURLToPath(new URL("../../../", import.meta.url));
const DIST = join(ROOT, "web/dist");
const API = join(ROOT, "testdata/api/v1");
const TYPES = { ".html": "text/html", ".js": "text/javascript", ".css": "text/css", ".json": "application/json",
  ".png": "image/png", ".jpg": "image/jpeg", ".svg": "image/svg+xml", ".webmanifest": "application/manifest+json" };

const lakes = JSON.parse(await readFile(join(API, "lakes/index"), "utf8"));
const forecast = JSON.parse(await readFile(join(API, "clubs/mrc-1880/forecast"), "utf8"));

let server, base, browser;

before(async () => {
  server = createServer(async (req, res) => {
    const path = normalize(decodeURIComponent(new URL(req.url, "http://x").pathname));
    const api = path.startsWith("/v1/");
    let file = api ? join(API, path.slice(4)) : join(DIST, path);
    if (!api && path.endsWith("/")) file = join(file, "index.html");
    try {
      const body = await readFile(file);
      // The site's Content Security Policy, enforced here (the live site only reports it
      // for now), so a page that needs a source it doesn't list fails this test.
      res.writeHead(200, { "Content-Type": api ? "application/json" : TYPES[extname(file)] ?? "application/octet-stream",
        ...(api ? {} : { "Content-Security-Policy": CSP }) });
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

const table = Object.fromEntries(JSON.parse(await readFile(join(ROOT, "testdata/motion.json"), "utf8")).changes.map((c) => [c.id, c.web]));
const clubs = lakes.flatMap((l) => l.clubs.map((c) => ({ ...c, lakeId: l.id })));

async function openPhone() {
  const context = await browser.newContext({ viewport: { width: 390, height: 844 }, isMobile: true, hasTouch: true, locale: "en-GB", timezoneId: "Europe/Berlin" });
  await context.route((url) => !url.href.startsWith(base), (route) => route.abort());
  const page = await context.newPage();
  const errors = [];
  page.on("pageerror", (e) => errors.push(e.message));
  await page.clock.install({ time: new Date(forecast.generatedAt) });
  await page.addInitScript(([api, entries]) => {
    globalThis.RF_API = api;
    // Every motion asked for, in order; "none" for a change without one.
    window.__motions = [];
    const start = document.startViewTransition?.bind(document);
    if (start) document.startViewTransition = (update) => { window.__motions.push(document.documentElement.dataset.motion ?? "none"); return start(update); };
    if (!sessionStorage.getItem("rf.test")) {
      sessionStorage.setItem("rf.test", "1");
      for (const [k, v] of Object.entries(entries)) localStorage.setItem(k, JSON.stringify(v));
    }
  }, [`${base}/v1`, { "rf.safety": { version: 1, at: forecast.generatedAt }, "rf.tourSeen": true, "rf.tipsClosed": true, "rf.language": "en", "rf.clubs": clubs }]);
  return { page, errors, context };
}

/** The motions asked for so far; the hashchange that asks runs just after the address changes. */
const motions = async (page) => {
  await page.waitForTimeout(150);
  return page.evaluate(() => window.__motions.splice(0));
};
const shownClub = (page) => page.evaluate(() => decodeURIComponent(location.hash.replace("#/club/", "")));
const wantFor = (id, dir) => (table[id] === "next/prev" ? [dir] : table[id] ? [table[id]] : []);

test("motion: the arrow keys (as a swipe) slide one club", async () => {
  const { page, errors, context } = await openPhone();
  await page.goto(`${base}/app/#/club/${clubs[0].id}`);
  await page.locator(".bottom .dots").waitFor();
  await motions(page);
  await page.keyboard.press("ArrowRight");
  await page.waitForFunction((id) => location.hash.endsWith(id), clubs[1].id);
  assert.deepEqual(await motions(page), wantFor("swipe", "next"));
  // The new page wires its own keys once drawn.
  await page.waitForFunction(() => [...document.querySelectorAll(".bottom .dots a")].findIndex((a) => a.classList.contains("on")) === 1);
  await page.waitForTimeout(300);
  await page.keyboard.press("ArrowLeft");
  await page.waitForFunction((id) => location.hash.endsWith(id), clubs[0].id);
  assert.deepEqual(await motions(page), wantFor("swipe", "prev"));
  assert.deepEqual(errors, []);
  await context.close();
});

test("motion: a tap on a far dot moves one club towards it, sliding, as Weather's page dots", async () => {
  const { page, errors, context } = await openPhone();
  await page.goto(`${base}/app/#/club/${clubs[0].id}`);
  await page.locator(".bottom .dots a").nth(2).waitFor();
  await motions(page);
  await page.locator(".bottom .dots a").nth(2).click();
  await page.waitForFunction((id) => location.hash.endsWith(id), clubs[1].id);
  assert.equal(await shownClub(page), clubs[1].id, "one club on, not straight to the tapped one");
  assert.deepEqual(await motions(page), wantFor("dotTap", "next"));
  assert.deepEqual(errors, []);
  await context.close();
});

test("motion: a finger along the dots jumps without a slide", async () => {
  const { page, errors, context } = await openPhone();
  await page.goto(`${base}/app/#/club/${clubs[0].id}`);
  const dots = page.locator(".bottom .dots a");
  await dots.nth(2).waitFor();
  await motions(page);
  await page.waitForTimeout(300);
  const [a, c] = await page.evaluate(() => [0, 2].map((i) => {
    const r = document.querySelectorAll(".bottom .dots a")[i].getBoundingClientRect();
    return { x: r.x, y: r.y, width: r.width, height: r.height };
  }));
  await page.mouse.move(a.x + a.width / 2, a.y + a.height / 2);
  await page.mouse.down();
  await page.mouse.move(c.x + c.width / 2, c.y + c.height / 2, { steps: 8 });
  await page.mouse.up();
  await page.waitForFunction((id) => location.hash.endsWith(id), clubs[2].id);
  await page.waitForTimeout(200);
  assert.equal(await shownClub(page), clubs[2].id);
  assert.deepEqual(await motions(page), wantFor("dotDrag"));
  assert.deepEqual(errors, []);
  await context.close();
});

test("motion: a club picked in the list zooms open from its row", async () => {
  const { page, errors, context } = await openPhone();
  await page.goto(`${base}/app/#/list`);
  const row = page.locator(`main.list-page a.row[data-id="${clubs[2].id}"]`);
  await row.waitFor();
  await motions(page);
  await row.click();
  await page.waitForFunction((id) => location.hash.endsWith(id), clubs[2].id);
  assert.deepEqual(await motions(page), wantFor("listPick"));
  assert.deepEqual(errors, []);
  await context.close();
});
