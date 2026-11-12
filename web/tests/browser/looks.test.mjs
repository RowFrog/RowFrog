// Look checks with a background picture and the on-screen keyboard (owner, 12 Nov 2026: "how could that slip
// through?"). The other browser tests run on the plain background with no keyboard, so three bugs passed them:
// a dark bar over a frosted tile, a sign off the middle of its frame, and the picture riding up over the keyboard.
// This walks the pages with a picture, in both tile looks and both colour schemes, in every layout, and checks:
//  - inside a frosted tile nothing has its own solid colour, except what is meant to (the pinned table header);
//  - signs in thumbnails and round buttons sit in the middle of their frame;
//  - with the keyboard open (simulated: Chromium has none) the picture still covers the visible screen.
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

/** Elements inside frosted tiles that paint their own (nearly) solid colour and so show as a block on the glass. */
const solidInFrosted = (page) => page.evaluate(() => {
  if (!document.body.matches('.has-picture[data-tiles="frosted"]')) return ["the page has no frosted picture"];
  const alpha = (c) => {
    const m = c.match(/rgba?\(([^)]+)\)/);
    if (!m) return c.includes("color(") ? Number((c.match(/\/\s*([\d.]+)/) ?? [0, 1])[1]) : 0;
    const p = m[1].split(/[\s,/]+/).filter(Boolean);
    return p.length > 3 ? Number(p[3]) : 1;
  };
  // Meant to be solid: the pinned table header (its layer), tips (the app's TipView has its own box), coloured dots,
  // chips and pills with their own fill.
  const meant = ".hhead.stuck, .tip, .dot, .light, .pill, .chip, button, a, input, select, .switch, svg, img, canvas, .leaflet-container, .map, [class*='map'], .nightline, .bar, .fill, .swatch, .badge, mark";
  const out = [];
  for (const card of document.querySelectorAll(".card")) {
    for (const el of card.querySelectorAll("*")) {
      const box = el.getBoundingClientRect();
      if (box.width < 120 || box.height < 16 || el.closest(meant)) continue;
      const style = getComputedStyle(el);
      if (style.display === "none" || style.visibility === "hidden") continue;
      if (alpha(style.backgroundColor) >= 0.85) out.push(`${el.tagName.toLowerCase()}.${[...el.classList].join(".")} (${style.backgroundColor})`);
    }
  }
  return out;
});

for (const layout of LAYOUTS) for (const tiles of ["frosted", "solid"]) for (const scheme of ["light", "dark"]) {
  test(`looks: ${layout.name}, ${tiles} tiles, ${scheme}: club page and settings with a picture`, async () => {
    const { page, errors, context } = await openIn(layout, visitor({ "rf.tileStyle": tiles }), scheme);
    await page.goto(`${base}/app/#/club/mrc-1880`);
    await page.locator(".hhead").first().waitFor({ timeout: 20000 });
    await page.waitForTimeout(500);
    assert.equal(await page.evaluate(() => document.body.classList.contains("has-picture")), true, "the picture shows");
    if (tiles === "frosted") {
      assert.deepEqual(await solidInFrosted(page), [], "nothing in a frosted tile paints a solid block (loaded)");
      // The table header pinned at the top: its layer must hide the rows under it.
      await page.evaluate(() => { const h = document.querySelector(".hhead"); scrollBy(0, h.getBoundingClientRect().top + 300); });
      await page.waitForTimeout(300);
      const pinned = await page.evaluate(() => {
        const h = document.querySelector(".hhead");
        return h.classList.contains("stuck") ? getComputedStyle(h, "::before").backgroundColor : null;
      });
      if (pinned) assert.ok(!/rgba\(0, 0, 0, 0\)|transparent/.test(pinned), `the pinned header has a layer behind it (${pinned})`);
      assert.deepEqual(await solidInFrosted(page), [], "nothing in a frosted tile paints a solid block (scrolled)");
    }
    // Settings: the background pictures row's sign sits in the middle of its frame.
    await page.goto(`${base}/app/#/settings/appearance`);
    await page.locator("#bg-thumb").waitFor();
    await page.evaluate(() => localStorage.setItem("rf.background", JSON.stringify("none")));
    await page.reload();
    await page.locator("#bg-thumb svg").waitFor();
    const off = await page.evaluate(() => {
      const f = document.querySelector("#bg-thumb").getBoundingClientRect(), s = document.querySelector("#bg-thumb svg").getBoundingClientRect();
      return [Math.abs((f.left + f.right) / 2 - (s.left + s.right) / 2), Math.abs((f.top + f.bottom) / 2 - (s.top + s.bottom) / 2)];
    });
    assert.ok(off[0] <= 1 && off[1] <= 1, `the "no picture" sign is ${off.map(Math.round)} px off the middle of its frame`);
    assert.deepEqual(errors, []);
    await context.close();
  });
}

test("looks: signs sit in the middle of the picture choices and round buttons", async () => {
  const { page, errors, context } = await openIn(LAYOUTS[0], visitor());
  await page.goto(`${base}/app/#/settings/backgrounds`);
  await page.locator("[data-target=all]").click();
  await page.locator(".bg-option .thumb svg").first().waitFor();
  const off = await page.evaluate(() => [...document.querySelectorAll(".bg-option .thumb, .round, .g")].flatMap((frame) => {
    const svgs = [...frame.children].filter((c) => c.matches("svg.i"));
    if (svgs.length !== 1 || frame.children.length !== 1) return [];
    const f = frame.getBoundingClientRect(), s = svgs[0].getBoundingClientRect();
    if (!f.width || !s.width) return [];
    const dx = (f.left + f.right) / 2 - (s.left + s.right) / 2, dy = (f.top + f.bottom) / 2 - (s.top + s.bottom) / 2;
    return Math.abs(dx) > 1.5 || Math.abs(dy) > 1.5 ? [`${frame.className}: ${Math.round(dx)},${Math.round(dy)}`] : [];
  }));
  assert.deepEqual(off, [], "signs off the middle of their frame");
  assert.deepEqual(errors, []);
  await context.close();
});

for (const layout of LAYOUTS.filter((l) => l.touch)) {
  test(`looks: ${layout.name}: the picture stays on the screen while the keyboard is open`, async () => {
    // Safari slides the visible part down to the search; Chromium has no on-screen keyboard, so visualViewport is faked.
    const fakeKeyboard = () => {
      const fake = new EventTarget();
      Object.assign(fake, { height: innerHeight, width: innerWidth, offsetTop: 0, offsetLeft: 0, scale: 1 });
      Object.defineProperty(window, "visualViewport", { get: () => fake });
      window.__keyboard = (height, top) => { fake.height = height; fake.offsetTop = top; fake.dispatchEvent(new Event("resize")); };
    };
    const { page, errors, context } = await openIn(layout, visitor({ "rf.clubs": [] }), "dark", fakeKeyboard);
    await page.goto(`${base}/app/#/`);
    await page.locator("#page-picture").waitFor({ state: "attached" });
    await page.waitForTimeout(300);
    const h = layout.viewport.height, keyboard = Math.round(h * 0.4), slid = Math.round(h * 0.3);
    await page.evaluate(([v, top]) => window.__keyboard(v, top), [h - keyboard, slid]);
    await page.waitForTimeout(200);
    const top = await page.evaluate(() => document.querySelector("#page-picture").getBoundingClientRect().top);
    assert.ok(Math.abs(top - slid) <= 1, `the picture's top is ${Math.round(top)} px down the page; it must follow the visible part (${slid} px)`);
    await page.evaluate(([v]) => window.__keyboard(v, 0), [h]);
    await page.waitForTimeout(200);
    assert.ok(Math.abs(await page.evaluate(() => document.querySelector("#page-picture").getBoundingClientRect().top)) <= 1, "back in place once the keyboard closes");
    assert.deepEqual(errors, []);
    await context.close();
  });
}
