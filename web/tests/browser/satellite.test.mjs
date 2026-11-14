// The satellite picture keeps its size and place when switching between its pictures (owner, 12 Nov 2026:
// "the sat view, outlines and the safety vest hint seem to move when switched"). The caption under the picture
// wrapped to two lines for one picture ("100 % of the lake under cloud") and not for the other, and the picture
// is sized to leave room for the caption, so it shrank. The caption then took two lines; since 14 Nov 2026 its
// wording fits one line for every picture.
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
  "rf.clubs": [club], ...extra,
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


const PNG = Buffer.from("iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNkYAAAAAYAAjCB0C8AAAAASUVORK5CYII=", "base64");
const META = {
  width: 1000, height: 2000, bbox: [10.70, 47.55, 10.80, 47.65], attribution: "Contains modified Copernicus Sentinel data 2026",
  latest: { image: "latest.jpg", date: "2026-11-11", lakeCloud: 1 },
  clearest: { image: "clearest.jpg", date: "2026-10-27", lakeCloud: 0 },
};

for (const layout of LAYOUTS) {
  {
    test(`${layout.name}: the satellite picture stays put when switching pictures`, async () => {
      const { page, errors, context } = await openIn(layout, visitor());
      await context.route((url) => url.pathname.endsWith("/satellite"), (route) => route.fulfill({ contentType: "application/json", body: JSON.stringify(META) }));
      await context.route((url) => /\.jpg$/.test(url.pathname), (route) => route.fulfill({ contentType: "image/png", body: PNG }));
      await page.goto(`${base}/app/#/club/${club.id}`);
      const picture = page.locator("#satellite .picture");
      await picture.waitFor();
      // Read once the picture has settled: the same place in three readings 100 ms apart (up to 3 s),
      // so a slow machine (many tests at once) reads the end state, not a frame in between.
      const box = async () => {
        const read = () => page.evaluate(() => {
          const r = document.querySelector("#satellite .picture").getBoundingClientRect();
          return [r.x, r.width, r.height].map((v) => Math.round(v));
        });
        let last = await read(), same = 0;
        for (let i = 0; i < 30 && same < 2; i++) {
          await page.waitForTimeout(100);
          const now = await read();
          same = String(now) === String(last) ? same + 1 : 0;
          last = now;
        }
        return last;
      };
      // The picks come with the picture's details, which can arrive after the picture's box.
      const kinds = await page.waitForFunction(() => {
        const n = document.querySelectorAll("#satellite [data-kind]").length;
        return n === 2 ? n : false;
      }, null, { timeout: 10000 }).then((h) => h.jsonValue()).catch(() => page.locator("#satellite [data-kind]").count());
      assert.equal(kinds, 2, "two pictures to pick");
      await page.locator('#satellite [data-kind="latest"]').click();
      const latest = await box();
      await page.locator('#satellite [data-kind="clearest"]').click();
      const clearest = await box();
      await page.locator('#satellite [data-kind="latest"]').click();
      assert.deepEqual(clearest, latest, "the picture keeps its place and size (x, width, height)");
      assert.deepEqual(await box(), latest, "and again on switching back");
      assert.deepEqual(errors, []);
      await context.close();
    });
  }
}
