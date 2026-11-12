// Layout checks (owner, 12 Nov 2026: "compare" means every layout). Measures where things sit, in numbers,
// in every layout the website has and after each change of state: loaded, scrolled, the list beside the page
// slid away and back, the window resized and a sheet open. It does not judge looks; it catches buttons out of
// line, out of the window or on top of the title, and pages that scroll sideways.
//
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
/** Forecast paths the server answers with 403 (the test for a refused forecast). */
const refused = new Set();

before(async () => {
  server = createServer(async (req, res) => {
    const path = normalize(decodeURIComponent(new URL(req.url, "http://x").pathname));
    const api = path.startsWith("/v1/");
    if (refused.has(path)) return res.writeHead(403).end();
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

/** A page with the sample API, the clock at the sample's time and JavaScript errors collected. */
async function open(storage = {}, viewport = { width: 390, height: 844 }) {
  const context = await browser.newContext({ viewport, locale: "en-GB", timezoneId: "Europe/Berlin" });
  await context.route((url) => !url.href.startsWith(base), (route) => route.abort());
  const page = await context.newPage();
  const errors = [];
  page.on("pageerror", (e) => errors.push(e.message));
  page.on("console", (m) => /Content Security Policy/i.test(m.text()) && errors.push(m.text()));
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


/** Every layout the website has: phones and tablets by touch, computers by mouse; wide ones get the list beside the page. */
const LAYOUTS = [
  { name: "phone portrait", viewport: { width: 390, height: 844 }, touch: true },
  { name: "phone landscape", viewport: { width: 844, height: 390 }, touch: true },
  { name: "tablet portrait", viewport: { width: 820, height: 1180 }, touch: true },
  { name: "tablet landscape", viewport: { width: 1180, height: 820 }, touch: true, wide: true },
  { name: "computer small", viewport: { width: 700, height: 800 } },
  { name: "computer wide", viewport: { width: 1400, height: 1000 }, wide: true },
  { name: "computer very wide", viewport: { width: 2000, height: 1125 }, wide: true },
];

async function openIn(layout) {
  const context = await browser.newContext({ viewport: layout.viewport, isMobile: Boolean(layout.touch), hasTouch: Boolean(layout.touch), locale: "en-GB", timezoneId: "Europe/Berlin" });
  await context.route((url) => !url.href.startsWith(base), (route) => route.abort());
  const page = await context.newPage();
  const errors = [];
  page.on("pageerror", (e) => errors.push(e.message));
  await page.clock.install({ time: new Date(forecast.generatedAt) });
  await page.addInitScript(([api, entries]) => {
    globalThis.RF_API = api;
    if (!sessionStorage.getItem("rf.test")) {
      sessionStorage.setItem("rf.test", "1");
      for (const [k, v] of Object.entries(entries)) localStorage.setItem(k, JSON.stringify(v));
    }
  }, [`${base}/v1`, visitor()]);
  return { page, errors, context };
}

/** Where the bars' buttons, the big name and the list's buttons are, read in the page. */
const measure = (page) => page.evaluate(() => {
  const shown = (el) => {
    if (!el) return false;
    const style = getComputedStyle(el);
    const box = el.getBoundingClientRect();
    return box.width > 0 && box.height > 0 && style.visibility !== "hidden" && style.display !== "none" && Number(style.opacity) > 0.05
      && !el.closest("[hidden], dialog:not([open])") && Number(getComputedStyle(el.closest(".top-title") ?? el).opacity) > 0.05;
  };
  const rect = (el) => { const b = el.getBoundingClientRect(); return { top: b.top, bottom: b.bottom, left: b.left, right: b.right, mid: (b.top + b.bottom) / 2, label: el.getAttribute("aria-label") || el.textContent.trim().slice(0, 20) || el.className }; };
  const all = (q) => [...document.querySelectorAll(q)].filter(shown).map(rect);
  const title = document.querySelector(".title-row h1");
  return {
    width: innerWidth, height: innerHeight, sideways: document.documentElement.scrollWidth - document.documentElement.clientWidth,
    bars: all(".top-title .head-side > .round, .top-title .head-side > .boat, nav.bottom a, nav.bottom button, .side-head > .round"),
    pageButtons: all(".top-title .head-side > .round, .top-title .head-side > .boat"),
    listButtons: all(".side-head > .round"),
    title: shown(title) ? rect(title.querySelector(".club-name, span") ?? title) : null,
    main: rect(document.querySelector("main")),
    dialogs: all("dialog[open]"),
  };
});

const overlaps = (a, b) => a.left < b.right - 1 && b.left < a.right - 1 && a.top < b.bottom - 1 && b.top < a.bottom - 1;

/** The rules every layout keeps, in every state. */
function check(at, layout, state) {
  const where = `${layout.name}, ${state}`;
  assert.ok(at.sideways <= 0, `${where}: the page scrolls sideways by ${at.sideways} px`);
  for (const b of [...at.bars, ...at.dialogs]) {
    assert.ok(b.top >= -0.5 && b.bottom <= at.height + 0.5 && b.left >= -0.5 && b.right <= at.width + 0.5,
      `${where}: "${b.label}" leaves the window (${Math.round(b.left)},${Math.round(b.top)} to ${Math.round(b.right)},${Math.round(b.bottom)})`);
  }
  if (at.title) for (const b of at.pageButtons) assert.ok(!overlaps(b, at.title), `${where}: "${b.label}" covers the club's name`);
  if (layout.wide) {
    assert.ok(at.pageButtons.length >= 2, `${where}: the page's cog and boat show`);
    for (const b of at.pageButtons) assert.ok(b.left >= at.main.left - 0.5 && b.right <= at.main.right + 0.5, `${where}: "${b.label}" sits outside the page's column`);
    if (at.listButtons.length) for (const b of at.pageButtons) {
      assert.ok(Math.abs(b.mid - at.listButtons[0].mid) <= 1, `${where}: "${b.label}" is ${Math.round(b.mid - at.listButtons[0].mid)} px off the list's buttons`);
    }
  }
}

for (const layout of LAYOUTS) {
  test(`layout: ${layout.name} keeps its buttons in line through load, scroll, list, resize and a sheet`, async () => {
    const { page, errors, context } = await openIn(layout);
    await page.goto(`${base}/app/#/club/mrc-1880`);
    await page.locator(".title-row h1").waitFor();
    await page.waitForTimeout(300);
    check(await measure(page), layout, "loaded");
    for (const y of [40, 400]) {
      await page.evaluate((y) => scrollTo(0, y), y);
      await page.waitForTimeout(150);
      check(await measure(page), layout, `scrolled ${y} px`);
    }
    await page.evaluate(() => scrollTo(0, document.documentElement.scrollHeight));
    await page.waitForTimeout(150);
    check(await measure(page), layout, "scrolled to the end");
    await page.evaluate(() => scrollTo(0, 0));
    if (layout.wide) {
      await page.click("#hide-list");
      await page.locator(".top-title [data-show-list]").waitFor();
      await page.waitForTimeout(150);
      check(await measure(page), layout, "list slid away");
      await page.locator(".top-title [data-show-list]").click();
      await page.locator("#hide-list").waitFor();
      await page.waitForTimeout(600);
      check(await measure(page), layout, "list back");
      await page.setViewportSize({ width: layout.viewport.width - 200, height: layout.viewport.height });
      await page.waitForTimeout(300);
      check(await measure(page), { ...layout, name: `${layout.name} resized` }, "after resize");
    }
    await page.locator(".launch-open").first().click();
    await page.locator("dialog[open]").first().waitFor();
    await page.waitForTimeout(400);
    check(await measure(page), layout, "Location sheet open");
    assert.deepEqual(errors, []);
    await context.close();
  });
}
