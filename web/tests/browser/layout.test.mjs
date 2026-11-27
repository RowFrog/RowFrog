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
  // Added to the Home Screen (owner, 14 Nov 2026): no Safari bars, so the page runs under the clock and the
  // home bar, and keeps its buttons clear of both (safe-area insets of an iPhone 17 and an iPad Air 11").
  { name: "phone Home Screen app", viewport: { width: 402, height: 874 }, touch: true, home: { top: 62, bottom: 34 } },
  { name: "tablet Home Screen app", viewport: { width: 820, height: 1180 }, touch: true, home: { top: 24, bottom: 20 } },
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
  if (layout.home) await homeScreen(context, page, layout.home);
  return { page, errors, context };
}

/**
 * The page as a Home Screen web app: the clock's and home bar's safe-area insets (Chromium's override), and
 * navigator.standalone with (display-mode: standalone) as Safari reports them there (web/public/start.js).
 */
async function homeScreen(context, page, insets) {
  const cdp = await context.newCDPSession(page);
  await cdp.send("Emulation.setSafeAreaInsetsOverride", { insets: { top: insets.top, bottom: insets.bottom, left: 0, right: 0 } });
  await page.addInitScript(() => {
    Object.defineProperty(navigator, "standalone", { value: true });
    const match = window.matchMedia.bind(window);
    window.matchMedia = (query) => /display-mode:\s*standalone/.test(query)
      ? Object.assign(match("all"), { media: query, matches: true }) : match(query);
  });
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
    width: innerWidth, height: innerHeight, scrollY, sideways: document.documentElement.scrollWidth - document.documentElement.clientWidth,
    bars: all(".top-title .head-side > .round, .top-title .head-side > .boat, nav.bottom a, nav.bottom button, .side-head > .round"),
    pageButtons: all(".top-title .head-side > .round, .top-title .head-side > .boat"),
    listButtons: all(".side-head > .round"),
    title: shown(title) ? rect(title.querySelector(".club-name, span") ?? title) : null,
    main: rect(document.querySelector("main")),
    bar: document.querySelector(".top-title") ? rect(document.querySelector(".top-title")) : null,
    sideRight: (() => { const side = document.querySelector("aside.side"); return side && side.getBoundingClientRect().width > 0 ? side.getBoundingClientRect().right : 0; })(),
    clientWidth: document.documentElement.clientWidth,
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
  // As a Home Screen app the buttons stay clear of the clock and the home bar.
  if (layout.home) for (const b of at.bars) {
    assert.ok(b.top >= layout.home.top - 0.5 && b.bottom <= at.height - layout.home.bottom + 0.5,
      `${where}: "${b.label}" runs under the ${b.top < layout.home.top ? "clock" : "home bar"} (${Math.round(b.top)} to ${Math.round(b.bottom)})`);
  }
  // The bar's glass spans the whole area beside the list, edge to edge, never just the page's column (owner, 12 Nov 2026).
  if (at.bar) {
    assert.ok(Math.abs(at.bar.left - at.sideRight) <= 1, `${where}: the top bar starts at ${Math.round(at.bar.left)}, not at the list's edge ${Math.round(at.sideRight)}`);
    assert.ok(Math.abs(at.bar.right - at.clientWidth) <= 1, `${where}: the top bar ends at ${Math.round(at.bar.right)}, not at the window's edge ${at.clientWidth}`);
  }
  // At rest the buttons never cover the name. Scrolling, it slides under them on its way out, as in the app, whose
  // name scrolls under its floating buttons; this held at 40 px only while the test bar above the page scrolled away
  // with it and took the list's buttons 23 px up (bar removed, owner 27 Nov 2026).
  if (at.title && at.scrollY === 0) for (const b of at.pageButtons) assert.ok(!overlaps(b, at.title), `${where}: "${b.label}" covers the club's name`);
  if (layout.wide) {
    assert.ok(at.pageButtons.length >= 2, `${where}: the page's cog and boat show`);
    for (const b of at.pageButtons) assert.ok(b.left >= at.main.left - 0.5 && b.right <= at.main.right + 0.5, `${where}: "${b.label}" sits outside the page's column`);
    if (at.listButtons.length) for (const b of at.pageButtons) {
      assert.ok(Math.abs(b.mid - at.listButtons[0].mid) <= 1, `${where}: "${b.label}" is ${Math.round(b.mid - at.listButtons[0].mid)} px off the list's buttons`);
    }
  }
}

/**
 * Checks once the page has settled: measures again every 100 ms until the rules hold, for up to 5 s, so a busy
 * machine (screenshot runs on the Mac) cannot fail a check that only needed one more frame. A real fault still
 * fails, with the last measurement's message.
 */
async function checkSettled(page, layout, state) {
  const until = Date.now() + 5000;
  for (;;) {
    try {
      return check(await measure(page), layout, state);
    } catch (error) {
      if (Date.now() > until) throw error;
      await page.waitForTimeout(100);
    }
  }
}

/** Waits until fn() returns the expected value, for up to 5 s; then compares once more so a failure says what it got. */
async function eventually(fn, expected, message) {
  const until = Date.now() + 5000;
  let got = await fn();
  while (got !== expected && Date.now() < until) {
    await new Promise((done) => setTimeout(done, 100));
    got = await fn();
  }
  assert.equal(got, expected, message);
}

for (const layout of LAYOUTS) {
  test(`layout: ${layout.name} keeps its buttons in line through load, scroll, list, resize and a sheet`, async () => {
    const { page, errors, context } = await openIn(layout);
    await page.goto(`${base}/app/#/club/mrc-1880`);
    await page.locator(".title-row h1").waitFor();
    await page.waitForTimeout(300);
    await checkSettled(page, layout, "loaded");
    // For the screenshot matrix: RF_SHOTS=<folder> keeps a picture of each layout as loaded.
    if (process.env.RF_SHOTS) await page.screenshot({ path: join(process.env.RF_SHOTS, `layout-${layout.name.replaceAll(" ", "-")}.png`) });
    for (const y of [40, 400]) {
      await page.evaluate((top) => scrollTo(0, top), y);
      await page.waitForTimeout(150);
      await checkSettled(page, layout, `scrolled ${y} px`);
    }
    await page.evaluate(() => scrollTo(0, document.documentElement.scrollHeight));
    await page.waitForTimeout(150);
    await checkSettled(page, layout, "scrolled to the end");
    await page.evaluate(() => scrollTo(0, 0));
    if (layout.wide) {
      await page.click("#hide-list");
      await page.locator(".top-title [data-show-list]").waitFor();
      await page.waitForTimeout(150);
      await checkSettled(page, layout, "list slid away");
      await page.locator(".top-title [data-show-list]").click();
      await page.locator("#hide-list").waitFor();
      await page.waitForTimeout(600);
      await checkSettled(page, layout, "list back");
      await page.setViewportSize({ width: layout.viewport.width - 200, height: layout.viewport.height });
      await page.waitForTimeout(300);
      await checkSettled(page, { ...layout, name: `${layout.name} resized` }, "after resize");
    }
    await page.locator(".launch-open").first().click();
    await page.locator("dialog[open]").first().waitFor();
    await page.waitForTimeout(400);
    await checkSettled(page, layout, "Location sheet open");
    assert.deepEqual(errors, []);
    await context.close();
  });
}

test("columns (owner's pick B): the window sets 2 or 3, kept when the list slides away, with a buffer on resize", async () => {
  const layout = { name: "computer", viewport: { width: 1512, height: 945 } };
  const { page, errors, context } = await openIn(layout);
  // What the window allows; the sample page may have fewer cards than columns.
  const count = () => page.evaluate(() => Number(document.querySelector(".cards").dataset.columns));
  await page.goto(`${base}/app/#/club/mrc-1880`);
  await page.locator(".title-row h1").waitFor();
  await page.waitForTimeout(300);
  await eventually(count, 2, "1512 px with the list: 2");
  await page.click("#hide-list");
  await page.locator(".top-title [data-show-list]").waitFor();
  await page.waitForTimeout(300);
  await eventually(count, 2, "and still 2 with the list slid away");
  await page.locator(".top-title [data-show-list]").click();
  await page.locator("#hide-list").waitFor();
  await page.setViewportSize({ width: 1728, height: 945 });
  await page.waitForTimeout(500);
  await eventually(count, 3, "1728 px: 3");
  const widths = await page.evaluate(() => [...document.querySelectorAll(".cards .col")].map((c) => c.getBoundingClientRect().width));
  assert.ok(widths.every((w) => w >= 380 && w <= 560.5), `card widths ${widths}`);
  await page.setViewportSize({ width: 1610, height: 945 });
  await page.waitForTimeout(500);
  await eventually(count, 3, "1610 px after 3: kept by the buffer (room 1178)");
  await page.setViewportSize({ width: 1590, height: 945 });
  await page.waitForTimeout(500);
  await eventually(count, 2, "1590 px: back to 2 (room 1158)");
  await checkSettled(page, { name: "computer 1590", wide: true }, "after the columns changed");
  await page.setViewportSize({ width: 2000, height: 1125 });
  await page.waitForTimeout(500);
  await page.click("#hide-list");
  await page.locator(".top-title [data-show-list]").waitFor();
  await page.waitForTimeout(300);
  await eventually(count, 3, "2000 px without the list: 3, cards no wider than 560");
  const wide = await page.evaluate(() => [...document.querySelectorAll(".cards .col")].map((c) => c.getBoundingClientRect().width));
  assert.ok(wide.every((w) => w <= 560.5), `card widths ${wide}`);
  assert.deepEqual(errors, []);
  await context.close();
});

test("tablet from the Home Screen icon (no #/club/ address): a turn lays the page out again, list and sidebar button included", async () => {
  // Owner's iPad shots, 23 Nov 2026: turned, the list stayed beside a portrait page, or a landscape page kept the
  // phone layout with neither list nor sidebar button, as only "#/club/…" addresses were laid out again.
  const { page, errors, context } = await openIn({ name: "tablet", viewport: { width: 1180, height: 820 }, touch: true });
  await page.goto(`${base}/app/`);
  await page.locator("aside.side").waitFor();
  await page.setViewportSize({ width: 820, height: 1180 });
  await eventually(() => page.locator("aside.side").count(), 0, "portrait: no list beside the page");
  await page.setViewportSize({ width: 1180, height: 820 });
  await eventually(() => page.locator("aside.side").count(), 1, "landscape again: the list is back");
  await page.click("#hide-list");
  await page.locator(".top-title [data-show-list]").waitFor();
  await page.setViewportSize({ width: 820, height: 1180 });
  await page.setViewportSize({ width: 1180, height: 820 });
  await eventually(() => page.locator(".top-title [data-show-list]").count(), 1, "slid away and turned twice: the sidebar button is there");
  assert.deepEqual(errors, []);
  await context.close();
});

test("Home Screen app: the club page starts below the clock as in the app, with no test bar (owner's iPhone shots, 27 Nov 2026)", async () => {
  // black-translucent (decision 0063) runs the page on under the clock: without the safe-area inset the
  // club's name sat behind the clock and the small name showed at once, with the yellow test bar above it.
  const { page, errors, context } = await openIn(LAYOUTS.find((l) => l.name === "phone Home Screen app"));
  await page.goto(`${base}/app/`);
  await page.locator(".club-head h1").waitFor();
  await page.locator("main.page.club .card:not(.loading)").first().waitFor();
  const at = await page.evaluate(() => ({ head: document.querySelector(".club-head").getBoundingClientRect().top,
    gone: document.body.classList.contains("title-gone"), bars: document.querySelectorAll(".testing").length }));
  assert.ok(at.head >= 62 + 8 && at.head <= 62 + 30, `the header starts ${at.head} px down, below the 62 px clock as the app's`);
  assert.equal(at.gone, false, "the big name shows, not the small one");
  assert.equal(at.bars, 0, "no test bar");
  for (const hash of ["#/settings", "#/list"]) {
    await page.goto(`${base}/app/${hash}`);
    await page.waitForTimeout(300);
    assert.equal(await page.locator(".testing").count(), 0, `no test bar on ${hash}`);
  }
  assert.deepEqual(errors, []);
  await context.close();
});

test("48 hours: the table's last line stops the pinned header, and the two leave together (owner's pick B, 25 Nov 2026)", async () => {
  const { page, errors, context } = await openIn({ name: "short phone", viewport: { width: 390, height: 330 }, touch: true });
  await page.goto(`${base}/app/#/club/mrc-1880`);
  await page.locator(".hhead").waitFor();
  const at = () => page.evaluate(() => {
    const head = document.querySelector(".hhead");
    const last = [...head.nextElementSibling.children].filter((x) => x.offsetParent).at(-1).getBoundingClientRect();
    const box = head.getBoundingClientRect();
    return { stuck: head.classList.contains("stuck"), bottom: box.bottom, lastTop: last.top };
  });
  const end = await page.evaluate(() => document.querySelector(".hourly").getBoundingClientRect().bottom + scrollY);
  let met = 0;
  for (let y = end - 330; y <= end - 40; y += 10) {
    await page.evaluate((to) => scrollTo(0, to), y);
    await page.waitForTimeout(60);
    const now = await at();
    if (!now.stuck) continue;
    assert.ok(now.bottom <= now.lastTop + 0.5, `at ${y}: the header (bottom ${now.bottom}) lies over the last line (top ${now.lastTop})`);
    if (Math.abs(now.bottom - now.lastTop) < 0.5) met++;
  }
  assert.ok(met >= 2, "the header rode on the last line for a while");
  assert.deepEqual(errors, []);
  await context.close();
});

test("tablet: a swipe on a short club list never scrolls the club page beside it (owner's iPad shots, 23 Nov 2026)", async () => {
  const { page, errors, context } = await openIn({ name: "tablet", viewport: { width: 1180, height: 820 } });
  await page.goto(`${base}/app/#/club/mrc-1880`);
  await page.locator("aside.side").waitFor();
  await page.mouse.move(150, 500);
  for (let i = 0; i < 6; i++) await page.mouse.wheel(0, 400);
  await page.waitForTimeout(400);
  assert.equal(await page.evaluate(() => document.scrollingElement.scrollTop), 0, "the club page stayed at the top");
  assert.deepEqual(errors, []);
  await context.close();
});

test("club page: one 16 px gap between the cards and each item at the page's end, as the app (VStack spacing 16)", async () => {
  for (const layout of [LAYOUTS[0], LAYOUTS[5]]) {
    const { page, errors, context } = await openIn(layout);
    await page.goto(`${base}/app/#/club/mrc-1880`);
    await page.locator(".title-row h1").waitFor();
    await page.waitForTimeout(300);
    const gaps = await page.evaluate(() => {
      const shown = (e) => e.getBoundingClientRect().height > 0;
      // The column the page's end sits in (in two or three columns), its cards, then the page's end.
      const col = document.querySelector(".page-end").closest(".col") ?? document.querySelector(".cards");
      const items = [...col.querySelectorAll(":scope > .card"), ...document.querySelectorAll(".page-end > *")].filter(shown);
      const boxes = items.map((e) => ({ label: e.id || e.className, box: e.getBoundingClientRect() }));
      return boxes.slice(1).map((b, i) => ({ label: b.label, gap: Math.round(b.box.top - boxes[i].box.bottom) }));
    });
    assert.ok(gaps.length >= 4, `${layout.name}: too few items measured (${gaps.length})`);
    for (const g of gaps) assert.equal(g.gap, 16, `${layout.name}: ${g.gap} px above "${g.label}", not 16`);
    assert.deepEqual(errors, []);
    await context.close();
  }
});
