// The coloured bars with a dot (ScaleBar) are all the same length, the dot included (owner, 13 Nov 2026: the
// bars for waves and UV looked longer than air temperature's). The dot sat centred on the bar's end and stuck
// out half a dot when the value was at either end; in the app it stays inside the bar.
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

/** Every layout the website has (as layout.test.mjs). */
const LAYOUTS = [
  { name: "phone portrait", viewport: { width: 390, height: 844 }, touch: true },
  { name: "phone landscape", viewport: { width: 844, height: 390 }, touch: true },
  { name: "tablet portrait", viewport: { width: 820, height: 1180 }, touch: true },
  { name: "tablet landscape", viewport: { width: 1180, height: 820 }, touch: true },
  { name: "computer wide", viewport: { width: 1400, height: 1000 } },
];

const visitor = (extra = {}) => ({
  "rf.safety": { version: 1, at: forecast.generatedAt }, "rf.tourSeen": true, "rf.tipsClosed": true, "rf.language": "en",
  "rf.clubs": [club], "rf.background": "sample:lake-waves", ...extra,
});

async function openIn(layout, storage, scheme = "light", init = null) {
  const context = await browser.newContext({ viewport: layout.viewport, isMobile: Boolean(layout.touch), hasTouch: Boolean(layout.touch),
    locale: "en-GB", timezoneId: "Europe/Berlin", colorScheme: scheme });
  await context.route((url) => !url.href.startsWith(base), (route) => route.abort());
  const page = await context.newPage();
  const errors = [];
  page.on("pageerror", (e) => errors.push(e.message));
  await page.clock.install({ time: new Date(forecast.generatedAt) });
  if (init) await page.addInitScript(init);
  await page.addInitScript(([api, entries]) => {
    globalThis.RF_API = api;
    if (!sessionStorage.getItem("rf.test")) {
      sessionStorage.setItem("rf.test", "1");
      for (const [k, v] of Object.entries(entries)) localStorage.setItem(k, JSON.stringify(v));
    }
  }, [`${base}/v1`, storage]);
  return { page, errors, context };
}


for (const layout of LAYOUTS) {
  test(`${layout.name}: every value bar's dot stays inside its bar`, async () => {
    const { page, errors, context } = await openIn(layout, visitor({ "rf.topTileOpenAll": true }));
    await page.goto(`${base}/app/#/club/${club.id}`);
    // The page draws again when the forecast is in, so the bars are read once at least three are there.
    const bars = await (await page.waitForFunction(() => {
      const all = [...document.querySelectorAll(".scale")];
      return all.length >= 3 && all.map((bar) => {
        const b = bar.getBoundingClientRect(), k = bar.querySelector(".knob").getBoundingClientRect();
        return { width: Math.round(b.width), out: Math.max(b.left - k.left, k.right - b.right) };
      });
    })).jsonValue();
    assert.ok(bars.length >= 3, `value bars on the page (${bars.length})`);
    for (const bar of bars) {
      assert.equal(bar.width, 46);
      assert.ok(bar.out <= 0.5, `the dot sticks out ${bar.out} px`);
    }
    assert.deepEqual(errors, []);
    await context.close();
  });
}
