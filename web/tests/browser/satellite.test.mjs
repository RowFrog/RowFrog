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
  // The latest with a grey area (the pass's strip ended inside the frame): only its "i" is filled, and
  // the line keeps its height (owner 21 Nov 2026: "does this not mess up the height", decision 0056).
  latest: { image: "latest.jpg", date: "2026-11-11", lakeCloud: 1, gap: 0.09 },
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
      assert.ok(await page.locator("#satellite .sat-why.has-gap").count() > 0, "a filled i on the picture with a grey area");
      await page.locator('#satellite [data-kind="clearest"]').click();
      const clearest = await box();
      assert.equal(await page.locator("#satellite .sat-why.has-gap").count(), 0, "the plain i on the whole picture");
      await page.locator('#satellite [data-kind="latest"]').click();
      assert.deepEqual(clearest, latest, "the picture keeps its place and size (x, width, height)");
      assert.deepEqual(await box(), latest, "and again on switching back");
      assert.deepEqual(errors, []);
      await context.close();
    });
  }
}

// Three pictures: the picks read as the app's ("Fast klar", not the sky's "Überwiegend klar") and each stays on
// one line, the smallest phone included (owner's screenshots, 19 Nov 2026).
for (const [language, labels] of [["de", ["Neuestes", "Fast klar", "Klarstes"]], ["en", ["Latest", "Mostly clear", "Clearest"]]]) {
  for (const layout of [{ name: "small phone", viewport: { width: 320, height: 568 }, touch: true }, ...LAYOUTS]) {
    test(`${layout.name}, ${language}: three satellite picks, each on one line`, async () => {
      const { page, errors, context } = await openIn(layout, visitor({ "rf.language": language }), "light",
        language === "de" ? () => Object.defineProperty(navigator, "language", { get: () => "de-DE" }) : null);
      const meta = { ...META, mostlyClear: { image: "mostly.jpg", date: "2026-11-03", lakeCloud: 0.2 } };
      await context.route((url) => url.pathname.endsWith("/satellite"), (route) => route.fulfill({ contentType: "application/json", body: JSON.stringify(meta) }));
      await context.route((url) => /\.jpg$/.test(url.pathname), (route) => route.fulfill({ contentType: "image/png", body: PNG }));
      await page.goto(`${base}/app/#/club/${club.id}`);
      // The page may draw again once the language has loaded: the picks are read in one go, once in their language.
      const picks = await page.waitForFunction((want) => {
        const picks = [...document.querySelectorAll("#satellite [data-kind]")].map((b) => {
          const range = document.createRange();
          range.selectNodeContents(b);
          return { text: b.textContent, height: Math.round(b.getBoundingClientRect().height), cut: b.scrollWidth > b.clientWidth, lines: range.getClientRects().length };
        });
        return picks.map((p) => p.text).join() === want.join() && picks;
      }, labels, { timeout: 10000 }).then((h) => h.jsonValue())
        .catch(() => page.locator("#satellite [data-kind]").evaluateAll((buttons) => buttons.map((b) => ({ text: b.textContent }))));
      assert.deepEqual(picks.map((p) => p.text), labels);
      assert.equal(new Set(picks.map((p) => p.height)).size, 1, `one height: ${JSON.stringify(picks)}`);
      assert.ok(picks.every((p) => !p.cut && p.lines === 1), `each label whole, on one line: ${JSON.stringify(picks)}`);
      assert.deepEqual(errors, []);
      await context.close();
    });
  }
}

// The lake map opens on the street map, and in dark mode that is MapTiler's dark street map, not OpenStreetMap
// with turned-round colours, whose dark green forests read as satellite pictures on a phone (owner, 15 Nov 2026).
// The globe button switches to the satellite pictures and back; the street map follows a change of dark mode.
test("phone: the lake map opens on the street map, dark in dark mode, and the globe button switches back and forth", async () => {
  const { page, errors, context } = await openIn(LAYOUTS[0], visitor(), "dark");
  await context.route((url) => url.pathname.endsWith("/app/config.json"), (route) => route.fulfill({ contentType: "application/json", body: '{"maptilerKey":"k"}' }));
  // A small square lake (as smoke.test.mjs), as the sample data has no lake view.
  const cols = 12, rows = 12, n = cols * rows, start = new Date(forecast.generatedAt);
  const lake = {
    id: club.lakeId, name: "Square lake", generatedAt: forecast.generatedAt, waterC: 14,
    grid: { south: 47.985, west: 11.33, dLat: 0.002, dLon: 0.003, cols, rows, cells: [...Array(n).keys()], cellPoint: Array(n).fill(0), cellZone: Array(n).fill(0) },
    zones: ["west"], outline: [], clubs: [{ id: club.id, name: club.name, shortName: club.shortName, launchPoint: club.launchPoint }],
    points: [{ lat: 47.997, lon: 11.348 }],
    hours: [...Array(6).keys()].map((i) => ({
      time: new Date(start.getTime() + i * 3600e3).toISOString(), lakeWide: { light: "green", reasons: [] }, lights: "0".repeat(n), wavesCm: Array(n).fill(5),
      wind: [{ speedMs: 2, gustMs: 4, fromDeg: 270, other: 0 }], zones: [{ light: "green", maxWaveM: 0.05 }],
    })),
  };
  await context.route((url) => url.pathname.endsWith(`/v1/lakes/${club.lakeId}/view`), (route) => route.fulfill({ contentType: "application/json", body: JSON.stringify(lake) }));
  const tiles = () => page.evaluate(() => [...document.querySelectorAll("#lake-map img.leaflet-tile")].map((i) => i.src).filter((src) => src.startsWith("http")));
  const kinds = async () => [...new Set((await tiles()).map((s) => s.includes("hybrid") ? "satellite" : s.includes("streets-v2-dark") ? "dark street" : s.includes("openstreetmap") ? "street" : s))];
  await page.goto(`${base}/app/#/lake/${club.lakeId}/${club.id}`);
  const button = page.locator("#lake-map .sat-switch");
  await button.waitFor({ timeout: 20000 });
  await page.waitForFunction(() => document.querySelectorAll("#lake-map img.leaflet-tile").length > 0);
  assert.deepEqual(await kinds(), ["dark street"], "opens on the dark street map");
  assert.equal(await button.getAttribute("aria-label"), "Show satellite pictures");
  await button.tap();
  await page.waitForFunction(() => [...document.querySelectorAll("#lake-map img.leaflet-tile")].filter((i) => i.src.startsWith("http")).every((i) => i.src.includes("hybrid")));
  assert.equal(await button.getAttribute("aria-label"), "Show the map");
  await button.tap();
  await page.waitForFunction(() => [...document.querySelectorAll("#lake-map img.leaflet-tile")].filter((i) => i.src.startsWith("http")).every((i) => i.src.includes("streets-v2-dark")));
  assert.deepEqual(await kinds(), ["dark street"], "and back to the street map");
  await page.evaluate(() => { document.documentElement.dataset.theme = "light"; });
  await page.waitForFunction(() => [...document.querySelectorAll("#lake-map img.leaflet-tile")].filter((i) => i.src.startsWith("http")).every((i) => i.src.includes("openstreetmap")));
  assert.deepEqual(await kinds(), ["street"], "light mode: the OpenStreetMap street map");
  assert.deepEqual(errors, []);
  await context.close();
});
