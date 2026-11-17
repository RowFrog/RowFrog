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
import { routeLink } from "../../public/app/routelink.js";
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
async function open(storage = {}, viewport = { width: 390, height: 844 }, locale = "en-GB") {
  const context = await browser.newContext({ viewport, locale, timezoneId: "Europe/Berlin" });
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

test("a first visit starts with the safety notice, which needs a tick", async () => {
  const { page, errors, context } = await open({ "rf.language": "en" });
  await page.goto(`${base}/app/`);
  const button = page.locator("#continue");
  await button.waitFor();
  assert.equal(await button.isDisabled(), true, "the notice cannot be skipped");
  assert.deepEqual(errors, []);
  await context.close();
});

test("a first visit's tour asks for the home base and more clubs, as the app's", async () => {
  const { page, errors, context } = await open({ "rf.language": "en", "rf.safety": { version: 1, at: forecast.generatedAt } });
  await page.goto(`${base}/app/`);
  await page.locator(".tour #next").click();
  await page.locator(".tour-choice").waitFor();
  assert.equal(await page.locator(".tour #skip").count(), 0, "no skipping the home base choice");
  assert.equal(await page.locator(".tour #next").isDisabled(), true, "Next waits for a home base");
  await page.locator("#tour-search").fill(club.shortName ?? club.name);
  await page.locator(`.tour-clubs .result[data-club="${club.id}"]`).click();
  assert.equal(await page.locator(".tour #next").isDisabled(), false, "a home base lets the tour go on");
  assert.equal(await page.evaluate(() => JSON.parse(localStorage.getItem("rf.clubs"))[0].id), club.id);
  await page.locator(".tour #next").click();
  await page.waitForFunction(() => document.querySelector(".tour h1")?.textContent === "Add more clubs");
  // The home base is in the list and stays when tapped there.
  await page.locator(`.tour-clubs .result[data-club="${club.id}"]`).click();
  assert.equal(await page.evaluate(() => JSON.parse(localStorage.getItem("rf.clubs")).length), 1);
  assert.deepEqual(errors, []);
  await context.close();
});

test("the tour's pages: the club choice on a first visit, the river page with a river club (TourPage.order)", async () => {
  const { page, errors, context } = await open(visitor());
  await page.goto(`${base}/app/#/list`);
  const ids = await page.evaluate(async () => {
    const { tourPages } = await import("./tour.js");
    return [tourPages(false, false), tourPages(true, true)].map((list) => list.map((p) => p.id));
  });
  assert.deepEqual(ids[0], ["welcome", "rowingLight", "conditions", "warnings", "boats", "lake", "locations", "wideScreen", "settings"]);
  assert.deepEqual(ids[1], ["welcome", "homeBase", "moreClubs", "rowingLight", "conditions", "warnings", "boats", "lake", "river", "locations", "wideScreen", "settings"]);
  assert.deepEqual(errors, []);
  await context.close();
});

test("the tour from Help skips the club choice once there is a home base", async () => {
  const { page, errors, context } = await open({ ...visitor(), "rf.tourSeen": false });
  await page.goto(`${base}/app/`);
  await page.locator(".tour #next").click();
  await page.waitForFunction(() => document.querySelector(".tour h1")?.textContent === "The rowing light");
  assert.deepEqual(errors, []);
  await context.close();
});

test("the club page shows the sample forecast and every tile opens its value page", async () => {
  const { page, errors, context } = await open(visitor());
  await page.goto(`${base}/app/#/club/mrc-1880`);
  // Current conditions sits in the top tile: "All values" opens its tiles, and stays open (app #315).
  const sel = ".card.now .tt-open [data-tile]";
  await page.locator(".card.now .all-values").first().click({ timeout: 20000 });
  // The page draws more than once while it loads; wait until the tiles are there.
  const found = await page.waitForFunction((sel) => {
    const tiles = [...document.querySelectorAll(sel)].filter((e) => e.offsetParent).map((e) => e.dataset.tile);
    return tiles.length >= 8 && tiles;
  }, sel, { timeout: 20000 });
  const tiles = await found.jsonValue();
  for (const tile of new Set(tiles)) {
    await page.locator(`${sel}[data-tile="${tile}"]`).first().click();
    await page.waitForFunction((t) => location.hash.includes(`/value/${t}`), tile);
    await page.waitForTimeout(300);
    assert.deepEqual(errors, [], `after opening ${tile}`);
    // A value page that cannot load its forecast goes back to the club page by itself.
    assert.ok(await page.evaluate((t) => location.hash.includes(`/value/${t}`), tile), `${tile} went back`);
    await page.goBack();
    await page.waitForFunction((sel) => [...document.querySelectorAll(sel)].filter((e) => e.offsetParent).length >= 8, sel, { timeout: 20000 });
  }
  await context.close();
});

test("the Location sheet names the club's OpenStreetMap place and opens its card", async () => {
  const { page, errors, context } = await open(visitor());
  await page.goto(`${base}/app/#/club/mrc-1880`);
  await page.locator(".club-head .launch-open").first().click({ timeout: 20000 });
  const line = page.locator("dialog.sheet .osm-place > summary");
  await line.waitFor({ timeout: 20000 });
  assert.match(await line.textContent(), /In OpenStreetMap as “Münchener Ruder-Club v\. 1880 e\.V\.”/);
  await line.click();
  const link = page.locator("dialog.sheet .osm-place .place-card a[href$='/way/42123014']");
  assert.ok(await link.isVisible());
  assert.deepEqual(errors, []);
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

test("each warning links to the service that issued it", async () => {
  const { page, errors, context } = await open(visitor());
  await page.goto(`${base}/app/#/club/mrc-1880`);
  const expected = forecast.warnings.items.map((w) => w.links.en);
  // The page draws more than once while it loads; wait until every warning's link is there.
  try {
    await page.waitForFunction((urls) => {
      const hrefs = [...document.querySelectorAll(".warning .source-links a")].map((a) => a.href);
      return urls.every((u) => hrefs.includes(u)) && hrefs.some((h) => h.startsWith("https://apps.apple.com/"));
    }, expected, { timeout: 20000 });
  } catch (e) {
    const hrefs = await page.locator(".warning .source-links a").evaluateAll((links) => links.map((a) => a.href));
    throw new Error(`${e.message}\nExpected ${expected.join(", ")} and the WarnWetter app; the page links ${hrefs.join(", ")}`);
  }
  if (process.env.RF_SHOT) await page.locator(".warning").first().screenshot({ path: process.env.RF_SHOT });
  assert.deepEqual(errors, []);
  await context.close();
});

test("each night of the 48 hours is one line that opens on a tap", async () => {
  const { page, errors, context } = await open(visitor());
  await page.goto(`${base}/app/#/club/mrc-1880`);
  const line = page.locator(".hourly-card .nightline").first();
  await line.waitFor({ timeout: 20000 });
  const rows = line.locator("xpath=following-sibling::div[1]");
  assert.equal(await rows.isHidden(), true, "the night starts folded");
  const days = () => page.locator(".hourly-card .dayhead:visible").evaluateAll((els) => els.map((e) => e.dataset.day));
  // The day headers come with the rows; read them only once one shows (CI read none once, #309).
  await page.locator(".hourly-card .dayhead:visible").first().waitFor({ timeout: 20000 });
  const folded = await days();
  if (process.env.RF_NIGHT_SHOT) await page.locator(".hourly-card").screenshot({ path: `${process.env.RF_NIGHT_SHOT}-folded.png` });
  await line.click();
  // Read the state once it has settled (a busy machine can be a frame behind).
  await settles(async () => {
    assert.equal(await line.getAttribute("aria-expanded"), "true");
    assert.equal(await rows.isVisible(), true, "a tap shows the night's hours");
    const opened = await days();
    assert.equal(new Set(opened).size, opened.length, "no day header twice");
    assert.deepEqual([...new Set(opened)], [...new Set(folded)], "the same days either way");
  });
  if (process.env.RF_NIGHT_SHOT) await page.locator(".hourly-card").screenshot({ path: `${process.env.RF_NIGHT_SHOT}-open.png` });
  await line.click();
  await settles(async () => assert.equal(await rows.isHidden(), true, "a second tap folds it again"));
  assert.deepEqual(errors, []);
  await context.close();
});

test("a night from the coarser model says so inside its line, and its hours carry ≈", async () => {
  // Owner's option B (12 Nov 2026): after the 48 hours the night goes on with ICON-EU. The sample
  // ends by day, so here its first night turns coarser from its fourth hour (22:00).
  const { page, errors, context } = await open(visitor());
  const parts = [
    { model: "ICON-D2", provider: "Deutscher Wetterdienst (DWD)", resolutionKm: 2.2, fromHour: 0, toHour: 14 },
    { model: "ICON-EU", provider: "Deutscher Wetterdienst (DWD)", resolutionKm: 7, fromHour: 14, toHour: 48 },
  ];
  await context.route(/\/v1\/clubs\/mrc-1880\/forecast/, (route) => route.fulfill({
    contentType: "application/json", body: JSON.stringify({ ...forecast, forecastSource: { region: "germany", parts } }),
  }));
  await page.goto(`${base}/app/#/club/mrc-1880`);
  const line = page.locator(".hourly-card .nightline").first();
  await line.waitFor({ timeout: 20000 });
  assert.equal(await line.locator(".coarser").innerText(), "≈ from 22:00 coarser model: ICON-EU, 7 km grid");
  assert.match(await line.getAttribute("aria-label"), /from 22:00 coarser model: ICON-EU/);
  if (process.env.RF_NIGHT_SHOT) await page.locator(".hourly-card").screenshot({ path: `${process.env.RF_NIGHT_SHOT}-coarser.png` });
  await line.click();
  const times = await line.locator("xpath=following-sibling::div[1]").locator(".hrow > span:first-child").allInnerTexts();
  assert.ok(times.includes("21:00") && times.includes("≈22:00"), times.join(" "));
  assert.deepEqual(errors, []);
  await context.close();
});

test("the top tile's values never break a word or get cut, at any width or text size", async () => {
  // Owner's rule: every size. German has the longest words ("Niederschlag", "Gefühlt"); the
  // large-text case scales the tile's type up as iOS's largest sizes do (12 Nov 2026).
  for (const width of [320, 390, 844, 1024]) {
    for (const big of [false, true]) {
      // The website speaks the browser's language.
      const { page, errors, context } = await open(visitor(), { width, height: 900 }, "de-DE");
      await page.goto(`${base}/app/#/club/mrc-1880`);
      const grid = page.locator(".now-grid").first();
      await grid.waitFor({ timeout: 20000 });
      if (big) await page.addStyleTag({ content: ".now-grid small { font-size: 22px !important } .now-grid .v28 { font-size: 46px !important } .now-grid .v17 { font-size: 30px !important }" });
      await settles(async () => {
        const bad = await grid.evaluate((g) => {
          const out = [];
          // Three columns: the tracks (titles and values) fit side by side.
          const style = getComputedStyle(g);
          const tracks = style.gridTemplateColumns.split(" ").map(parseFloat);
          if (tracks.reduce((a, b) => a + b, 0) + (tracks.length - 1) * parseFloat(style.columnGap) > g.clientWidth + 1) out.push(`tracks ${style.gridTemplateColumns}`);
          // Titles and values (the wind's arrow pokes out a few pixels at every size); the grey
          // lines reach past their column on purpose (fitGreyLines).
          for (const e of g.querySelectorAll(".label, .v28, .v17")) {
            if (e.scrollWidth > e.clientWidth + 6) out.push(`${e.closest("[data-top]")?.dataset.top} ${e.textContent.trim()} ${e.scrollWidth}/${e.clientWidth} ${g.className}`);
          }
          const right = g.getBoundingClientRect().right;
          for (const e of g.querySelectorAll(".grey")) if (e.getBoundingClientRect().right > right + 1) out.push(`grey ${e.textContent.trim()}`);
          return out;
        });
        assert.deepEqual(bad, [], `${width}${big ? " big" : ""}`);
      });
      if (process.env.RF_TILE_SHOT) await page.locator(".card.now").first().screenshot({ path: `${process.env.RF_TILE_SHOT}-${width}${big ? "-big" : ""}.png` });
      assert.deepEqual(errors, []);
      await context.close();
    }
  }
});

test("a night that ends the table up to sunrise reads as a whole night, a night cut off in the dark as open", async () => {
  // The 12 Nov evening shot read "17–" though the backend had finished the night to sunrise.
  for (const [last, range] of [["2026-10-19T04:00:00+00:00", "19–07"], ["2026-10-19T01:00:00+00:00", "19–"]]) {
    const { page, errors, context } = await open(visitor());
    const hours = forecast.hours.filter((x) => Date.parse(x.time) <= Date.parse(last));
    await context.route(/\/v1\/clubs\/mrc-1880\/forecast/, (route) => route.fulfill({
      contentType: "application/json", body: JSON.stringify({ ...forecast, hours }),
    }));
    await page.goto(`${base}/app/#/club/mrc-1880`);
    const line = page.locator(".hourly-card .nightline").last();
    await line.waitFor({ timeout: 20000 });
    assert.equal(await line.locator(".range").innerText(), range);
    assert.deepEqual(errors, []);
    await context.close();
  }
});

test("real data past hour 48 reaches the table: the last night ends at sunrise and names the coarser model", async () => {
  // The 12 Nov real-data shot still read "17–" with no "≈" line: the table cut the server's
  // night tail at 48 hours. Here the clock stands at 22:00, so hour 48 falls in the night.
  const { page, errors, context } = await open(visitor());
  const now = "2026-10-18T20:00:00+00:00";
  const shifted = forecast.hours.filter((x) => Date.parse(x.time) >= Date.parse("2026-10-19T06:00:00+00:00"))
    .map((x) => ({ ...x, time: new Date(Date.parse(x.time) + 24 * 3600e3).toISOString().replace(".000Z", "+00:00") }));
  const hours = [...forecast.hours, ...shifted].filter((x) => Date.parse(x.time) >= Date.parse(now));
  const parts = [
    { model: "ICON-D2", provider: "Deutscher Wetterdienst (DWD)", resolutionKm: 2.2, fromHour: 0, toHour: 48 },
    { model: "ICON-EU", provider: "Deutscher Wetterdienst (DWD)", resolutionKm: 7, fromHour: 48, toHour: 58 },
  ];
  assert.equal(hours.length, 58);
  await page.clock.setSystemTime(new Date(now));
  await context.route(/\/v1\/clubs\/mrc-1880\/forecast/, (route) => route.fulfill({
    contentType: "application/json", body: JSON.stringify({ ...forecast, generatedAt: now, hours, forecastSource: { region: "germany", parts } }),
  }));
  await page.goto(`${base}/app/#/club/mrc-1880`);
  const line = page.locator(".hourly-card .nightline").last();
  await line.waitFor({ timeout: 20000 });
  assert.equal(await line.locator(".range").innerText(), "19–07");
  assert.equal(await line.locator(".coarser").innerText(), "≈ from 22:00 coarser model: ICON-EU, 7 km grid");
  // Counted once the page has settled: it can draw the table again (refresh) between the reads above and here.
  const hints = await page.waitForFunction(() => {
    const n = document.querySelectorAll(".hourly-card .nightline .coarser").length;
    return n === 1 ? n : false;
  }, null, { timeout: 5000 }).then((h) => h.jsonValue()).catch(() => page.locator(".hourly-card .nightline .coarser").count());
  assert.equal(hints, 1, "only the last night has the hint");
  if (process.env.RF_NIGHT_SHOT) await page.locator(".hourly-card").screenshot({ path: `${process.env.RF_NIGHT_SHOT}-tail.png` });
  assert.deepEqual(errors, []);
  await context.close();
});

test("browsing by country lists the countries, a country's waters and a water's clubs", async () => {
  const { page, errors, context } = await open(visitor());
  await page.goto(`${base}/app/#/countries`);
  const country = page.locator('a.result[href="#/countries/de"]');
  await country.waitFor();
  assert.match(await country.innerText(), /Germany/);
  await country.click();
  const water = page.locator("#waters a.result").first();
  await water.waitFor();
  await water.click();
  const clubs = page.locator("#clubs .result");
  await clubs.first().waitFor();
  assert.ok(await clubs.count() > 0);
  assert.doesNotMatch(await page.locator("main").innerHTML(), /\[object Object\]|&lt;svg/, "markup is not escaped twice");
  assert.deepEqual(errors, []);
  await context.close();
});

test("the header names the model run and the update time, and the update cycles open from the page's end", async () => {
  const { page, errors, context } = await open(visitor());
  // The run came out 40 minutes before the server built the file (weatherRun, app #403).
  const made = new Date(forecast.generatedAt);
  const run = { model: "ICON-D2", started: new Date(made - 3 * 3600e3).toISOString(), available: new Date(made - 40 * 60e3).toISOString() };
  await context.route((url) => url.pathname.endsWith("/v1/clubs/mrc-1880/forecast"),
    (route) => route.fulfill({ contentType: "application/json", body: JSON.stringify({ ...forecast, weatherRun: run }) }));
  await page.goto(`${base}/app/#/club/mrc-1880`);
  const clock = (d) => new Date(d).toLocaleTimeString("en-GB", { hour: "2-digit", minute: "2-digit", timeZone: "Europe/Berlin" });
  const utcHour = String(new Date(run.started).getUTCHours()).padStart(2, "0");
  await page.waitForFunction((want) => document.querySelector("#updated-line")?.innerText.includes(want),
    `Model run ${utcHour} UTC · updated ${clock(made)}`, { timeout: 20000 });
  await page.locator("#updates").click();
  const sheet = page.locator("dialog.sheet");
  await sheet.waitFor();
  const text = await sheet.innerText();
  assert.ok(text.includes(`model run ${utcHour} UTC (started ${clock(run.started)}), ready at ${clock(run.available)}`), text.slice(0, 300));
  assert.equal(await sheet.locator(".legend.cycles li").count(), 11);
  if (process.env.RF_SHOT) await sheet.screenshot({ path: process.env.RF_SHOT });
  if (process.env.RF_SHOT_END) { await page.keyboard.press("Escape"); await page.locator(".page-end").screenshot({ path: process.env.RF_SHOT_END }); }
  assert.deepEqual(errors, []);
  await context.close();
});

test("fog within 1 km shows on the top tile and in the Why line (app #409)", async () => {
  const { page, errors, context } = await open(visitor());
  const near = { light: "red", windMs: 1, gustMs: 2, waveM: 0, visM: 300, rainMm: 0, other: "red", otherCause: "fog" };
  const hours = forecast.hours.map((x, i) => i < 48 ? { ...x, nearby: near, light: "red",
    reasons: [{ condition: "nearby_water", light: "red", topic: "fog", value: 300 }, ...(x.reasons ?? [])] } : x);
  await context.route((url) => url.pathname.endsWith("/v1/clubs/mrc-1880/forecast"),
    (route) => route.fulfill({ contentType: "application/json", body: JSON.stringify({ ...forecast, hours }) }));
  await page.goto(`${base}/app/#/club/mrc-1880`);
  const tile = page.locator('.card.now .now-grid [data-top="visibility"]');
  await page.waitForFunction(() => document.querySelector('.card.now .now-grid [data-top="visibility"]')?.innerText.includes("Nearby"), null, { timeout: 20000 });
  // The page may draw once more with the stored forecast; wait for the state rather than reading it once.
  await settles(async () => {
    assert.match(await tile.innerText(), /0\.3 km/);
    assert.ok(await tile.locator(".cause-red").count(), "the value takes the light's colour");
    assert.match(await page.locator(".card.now ul.reasons").innerText(), /Fog within 1 km of the launch point: visibility 0\.3 km\./);
  });
  if (process.env.RF_SHOT_NEAR) await page.locator(".card.now").screenshot({ path: process.env.RF_SHOT_NEAR });
  assert.deepEqual(errors, []);
  await context.close();
});

test("a refused forecast shows No forecast, and a failed update keeps the forecast with the reason", async () => {
  const { page, errors, context } = await open(visitor());
  const path = "/v1/clubs/mrc-1880/forecast";
  refused.add(path);
  await page.goto(`${base}/app/#/club/mrc-1880`);
  // The page may draw more than once while it loads; wait for the text rather than the first element.
  const shows = (sel, text) => page.waitForFunction(([sel, text]) => document.querySelector(sel)?.innerText.includes(text), [sel, text], { timeout: 20000 });
  // The page draws twice on opening (both tries are refused); wait until it has settled.
  await page.waitForLoadState("networkidle");
  await shows(".loading", "No forecast: server refused the download (error 403)");
  // Try again works once the server answers, then a failed update keeps what is shown (loadable in logic.js).
  refused.delete(path);
  await page.locator(".loading #retry").click();
  await page.locator(".card.now").first().waitFor({ timeout: 20000 });
  await page.locator("#updated-line").waitFor({ state: "attached", timeout: 20000 });
  refused.add(path);
  // No Refresh button (owner, 15 Nov 2026): the page loads again on return to the tab once
  // its forecast is over ten minutes old (refreshOnReturn).
  await page.clock.install();
  await page.clock.fastForward("11:00");
  await page.evaluate(() => document.dispatchEvent(new Event("visibilitychange")));
  await shows("#failed", "Could not update: server refused the download (error 403)");
  assert.ok(await page.locator(".card.now").first().isVisible(), "the forecast stays");
  refused.clear();
  assert.deepEqual(errors, []);
  await context.close();
});

/** Runs the assertions again every 100 ms until they hold, for up to 5 s, so a busy machine needs no fixed waits. */
async function settles(assertions) {
  const until = Date.now() + 5000;
  for (;;) {
    try {
      return await assertions();
    } catch (error) {
      if (Date.now() > until) throw error;
      await new Promise((done) => setTimeout(done, 100));
    }
  }
}

test("on wide windows the page's buttons stay level with the list's buttons and follow its column", async () => {
  // Owner, 12 Nov 2026: compare every layout, the wide one with the list beside the page included.
  const { page, errors } = await open(visitor(), { width: 1400, height: 1000 });
  await page.goto(`${base}/app/#/club/mrc-1880`);
  await page.locator(".title-row h1").waitFor();
  const at = () => page.evaluate(() => {
    const box = (q) => document.querySelector(q)?.getBoundingClientRect();
    const mid = (b) => Math.round(b.top + b.height / 2);
    const main = box("main"), cog = box(".top-title .head-side a"), boat = box(".top-title .head-side.end > *"), list = box("#hide-list");
    return { list: list ? mid(list) : null, cog: mid(cog), boat: mid(boat), cogLeft: Math.round(cog.left - main.left), boatRight: Math.round(main.right - boat.right) };
  });
  for (const y of [0, 40, 400]) {
    await page.evaluate((y) => scrollTo(0, y), y);
    await settles(async () => {
      const now = await at();
      assert.ok(now.cog > 0, `in the window at ${y}`);
      assert.equal(now.cog, now.list, `cog level with the list at ${y}`);
      assert.equal(now.boat, now.list, `boat level with the list at ${y}`);
    });
  }
  // The list slid away and back: the bar's buttons follow the page's column again.
  await page.evaluate(() => scrollTo(0, 0));
  await page.click("#hide-list");
  await page.locator("[data-show-list]").first().waitFor();
  await page.locator(".top-title [data-show-list]").click();
  await page.locator("#hide-list").waitFor();
  await settles(async () => {
    const now = await at();
    assert.equal(now.cog, now.list);
    assert.equal(now.cogLeft, now.boatRight, "the buttons sit at the page's column edges");
    assert.ok(now.cogLeft >= 0 && now.cogLeft < 24);
  });
  await page.setViewportSize({ width: 1100, height: 900 });
  await settles(async () => {
    const now = await at();
    assert.equal(now.cogLeft, now.boatRight, "and again after the window was resized");
    assert.ok(now.cogLeft >= 0 && now.cogLeft < 24);
  });
  assert.deepEqual(errors, []);
});

/** A made-up lake view: a square of water round the club's launch point, six calm hours (there is no sample file of one). */
function squareLake() {
  const cols = 12, rows = 12, n = cols * rows;
  const start = new Date(forecast.generatedAt);
  return {
    id: club.lakeId, name: "Square lake", generatedAt: forecast.generatedAt, waterC: 14,
    grid: { south: 47.985, west: 11.33, dLat: 0.002, dLon: 0.003, cols, rows, cells: [...Array(n).keys()], cellPoint: Array(n).fill(0), cellZone: Array(n).fill(0) },
    zones: ["west"], outline: [], clubs: [{ id: club.id, name: club.name, shortName: club.shortName, launchPoint: club.launchPoint }],
    points: [{ lat: 47.997, lon: 11.348 }],
    hours: [...Array(6).keys()].map((i) => ({
      time: new Date(start.getTime() + i * 3600e3).toISOString(), lakeWide: { light: "green", reasons: [] }, lights: "0".repeat(n), wavesCm: Array(n).fill(5),
      wind: [{ speedMs: 2, gustMs: 4, fromDeg: 270, other: 0 }], zones: [{ light: "green", maxWaveM: 0.05 }],
    })),
  };
}

test("wide windows: the page starts 10 px below the line of top buttons, level with the list's search field, the big name full width (PageTopButtons.gapBelow)", async () => {
  const { page, errors, context } = await open(visitor(), { width: 1194, height: 834 });
  await page.goto(`${base}/app/#/club/${club.id}`);
  await page.locator(".club-head h1").waitFor({ timeout: 20000 });
  await page.waitForTimeout(500);
  const at = () => page.evaluate(() => {
    const r = (s) => document.querySelector(s)?.getBoundingClientRect();
    const btn = [...document.querySelectorAll(".top-title .head-side .round")].find((b) => b.getBoundingClientRect().width).getBoundingClientRect();
    return { search: r("aside.side .search")?.top, head: r(".club-head").top, h1: r(".club-head h1").width, row: r(".club-head .title-row").width, btnBottom: btn.bottom };
  });
  let m = await at();
  assert.ok(Math.abs(m.head - m.search) <= 1, `header top ${m.head} level with the search field ${m.search}`);
  assert.ok(Math.abs(m.head - m.btnBottom - 10) <= 1, "10 px below the buttons");
  assert.ok(Math.abs(m.h1 - m.row) <= 1, "no room kept beside the big name");
  await page.locator("#hide-list").click();
  await page.waitForTimeout(800);
  m = await at();
  assert.ok(Math.abs(m.head - m.btnBottom - 10) <= 1, "also with the list slid away");
  assert.deepEqual(errors, []);
  await context.close();
});

test("the lake tile shows its parts as a small table with the wind's arrow, and lines where it does not fit (LakeZoneTable)", async () => {
  const { page, errors, context } = await open(visitor());
  const lake = squareLake();
  await context.route((url) => url.pathname.endsWith(`/v1/lakes/${club.lakeId}/view`),
    (route) => route.fulfill({ contentType: "application/json", body: JSON.stringify(lake) }));
  await page.goto(`${base}/app/#/club/${club.id}`);
  const box = page.locator(".zone-box");
  await box.waitFor({ timeout: 20000 });
  assert.equal(await box.getAttribute("data-fit"), "table");
  // The table never makes the page wider than the phone (the app's did, 4ee242a05).
  assert.ok(await page.evaluate(() => document.documentElement.scrollWidth <= innerWidth), "no sideways overflow");
  const row = page.locator(".zone-table tbody tr").first();
  assert.equal(await row.locator(".zt-name strong").innerText(), "West");
  // From the west: the arrow points east, where the wind blows to.
  assert.match(await row.locator(".zt-arrow .arrow").getAttribute("style"), /rotate\(90deg\)/);
  // A narrow window falls back to the parts' names over their values, the arrow as a character.
  await page.setViewportSize({ width: 250, height: 800 });
  await page.waitForFunction(() => document.querySelector(".zone-box")?.dataset.fit === "lines");
  assert.match(await page.locator(".zone-box .zones .zone-values").first().innerText(), /→/);
  assert.deepEqual(errors, []);
  await context.close();
});

test("value pages keep the chart and the map at the same height: 40 px between them, the waves page with the lake's waves (owner, 13 Nov 2026)", async () => {
  const { page, errors, context } = await open(visitor());
  const lake = squareLake();
  await context.route((url) => url.pathname.endsWith(`/v1/lakes/${club.lakeId}/view`),
    (route) => route.fulfill({ contentType: "application/json", body: JSON.stringify(lake) }));
  const seen = [];
  for (const value of ["visibility", "temperature", "wind", "waves", "cloudCover", "pressure"]) {
    await page.goto(`${base}/app/#/club/${club.id}/value/${value}`);
    const m = await page.waitForFunction(() => {
      const chart = document.querySelector(".vchart-wrap")?.getBoundingClientRect();
      const map = document.querySelector("#map-card")?.getBoundingClientRect();
      return chart && map?.height > 100 ? { chart: chart.top, gap: map.top - chart.bottom } : null;
    }, null, { timeout: 20000 }).then((h) => h.jsonValue());
    seen.push(m.chart);
    assert.ok(Math.abs(m.gap - 40) <= 1, `${value}: ${m.gap} px from the chart to the map`);
  }
  assert.ok(Math.max(...seen) - Math.min(...seen) <= 1, `the chart starts at the same height on every page: ${seen}`);
  // The waves page's map is the lake's, and opens the lake view on its waves.
  await page.goto(`${base}/app/#/club/${club.id}/value/waves`);
  await page.locator("#map-card canvas.wm-lake").waitFor({ timeout: 20000 });
  assert.match(await page.locator("#map-card a").getAttribute("href"), /layer=waves/);
  await page.locator("#map-card canvas").click();
  await page.waitForFunction(() => document.querySelector('.lake-layers [data-layer="waves"]')?.classList.contains("on"), null, { timeout: 20000 });
  assert.deepEqual(errors, []);
  await context.close();
});

test("the lake view's layers read rowing light, wind, waves and visibility; visibility only when the view has it (LakeLayer.available)", async () => {
  const { page, errors, context } = await open(visitor());
  const lake = squareLake();
  await context.route((url) => url.pathname.endsWith(`/v1/lakes/${club.lakeId}/view`),
    (route) => route.fulfill({ contentType: "application/json", body: JSON.stringify(lake) }));
  const layers = () => page.locator(".lake-layers [data-layer]").evaluateAll((bs) => bs.map((b) => b.dataset.layer));
  await page.goto(`${base}/app/#/lake/${club.lakeId}/${club.id}`);
  await page.locator(".lake-layers").waitFor({ timeout: 20000 });
  assert.deepEqual(await layers(), ["light", "wind", "waves"]);
  await context.close();
  // With visibility per point (wind[].visM), the fourth layer, coloured by fogginess.
  const second = await open(visitor());
  await second.context.route((url) => url.pathname.endsWith(`/v1/lakes/${club.lakeId}/view`),
    (route) => route.fulfill({ contentType: "application/json", body: JSON.stringify({ ...lake, hours: lake.hours.map((x) => ({ ...x, wind: x.wind.map((w) => ({ ...w, visM: 800 })) })) }) }));
  await second.page.goto(`${base}/app/#/lake/${club.lakeId}/${club.id}`);
  await second.page.locator(".lake-layers").waitFor({ timeout: 20000 });
  assert.deepEqual(await second.page.locator(".lake-layers [data-layer]").evaluateAll((bs) => bs.map((b) => b.dataset.layer)), ["light", "wind", "waves", "visibility"]);
  await second.page.locator('[data-layer="visibility"]').click();
  await second.page.locator(".lake-scale .bar").waitFor();
  assert.deepEqual([...errors, ...second.errors], []);
  await second.context.close();
});

test("the lake view opened twice while the map library loads builds one map (no \"Map container is already initialized\")", async () => {
  // A second route() while Leaflet still loads, as refreshSavedClubs() or a hash change can cause on a slow start.
  const { page, errors, context } = await open(visitor());
  const lake = squareLake();
  await context.route((url) => url.pathname.endsWith(`/v1/lakes/${club.lakeId}/view`),
    (route) => route.fulfill({ contentType: "application/json", body: JSON.stringify(lake) }));
  await context.route((url) => url.pathname.endsWith("/vendor/leaflet/leaflet.js"), async (route) => {
    await new Promise((resolve) => setTimeout(resolve, 1500));
    await route.continue();
  });
  await page.goto(`${base}/app/#/lake/${club.lakeId}/${club.id}`);
  await page.locator("#lake-map").waitFor();
  await page.waitForTimeout(300);
  await page.evaluate(() => window.dispatchEvent(new HashChangeEvent("hashchange")));
  await page.locator(".lake-layers").waitFor({ timeout: 20000 });
  await page.waitForTimeout(500);
  assert.equal(await page.locator(".leaflet-container").count(), 1);
  assert.deepEqual(errors, []);
  await context.close();
});

test("on a phone, planning a route brings the pulled-up sheet back to its smaller height (owner's pick B)", async () => {
  const { page, errors, context } = await open(visitor());
  const lake = squareLake();
  await context.route((url) => url.pathname.endsWith(`/v1/lakes/${club.lakeId}/view`),
    (route) => route.fulfill({ contentType: "application/json", body: JSON.stringify(lake) }));
  await page.goto(`${base}/app/#/lake/${club.lakeId}/${club.id}`);
  await page.locator("#panel-grip").click({ timeout: 20000 });
  assert.equal(await page.locator("#panel-grip").getAttribute("aria-expanded"), "true");
  await page.locator("#route-mode").click();
  await page.waitForFunction(() => document.querySelector("#panel-grip")?.getAttribute("aria-expanded") === "false");
  // Pulled up again while planning, it stays up.
  await page.locator("#panel-grip").click();
  assert.equal(await page.locator("#panel-grip").getAttribute("aria-expanded"), "true");
  assert.deepEqual(errors, []);
  await context.close();
});

test("the route editor: undo takes back the way back, Save marks the route saved, an edit changed and undo saved again", async () => {
  const { page, errors, context } = await open(visitor());
  const lake = squareLake();
  await context.route((url) => url.pathname.endsWith(`/v1/lakes/${club.lakeId}/view`),
    (route) => route.fulfill({ contentType: "application/json", body: JSON.stringify(lake) }));
  await page.goto(`${base}/app/#/lake/${club.lakeId}/${club.id}`);
  await page.locator("#route-mode").click({ timeout: 20000 });
  const map = page.locator("#lake-map");
  const box = await map.boundingBox();
  // Taps on the water above the panel add turning points (the lake sits below the top buttons, as the app fits it).
  for (const [x, y] of [[0.3, 0.35], [0.7, 0.4]]) await map.click({ position: { x: box.width * x, y: box.height * y } });
  await page.locator(".route-line .sub").waitFor();
  const undo = page.locator("#undo");

  await page.locator('[data-way-back="outAndBack"]').click();
  assert.ok(await page.locator('[data-way-back="outAndBack"].on').count());
  await undo.click();
  assert.ok(await page.locator('[data-way-back="oneWay"].on').count(), "Undo takes back the way back");
  // Save, named in the browser's prompt.
  page.once("dialog", (d) => d.accept("Test route"));
  await page.locator("#routes").click();
  await page.locator("#save-route").click();
  const saved = await page.evaluate(() => JSON.parse(localStorage.getItem("rf.routes")));
  assert.equal(saved.length, 1);
  assert.equal(saved[0].name, "Test route");
  const savedIcon = await page.locator("#routes").innerHTML();
  // An edit makes it changed (an empty bookmark), undoing it makes it saved again.
  await map.click({ position: { x: box.width * 0.55, y: box.height * 0.6 } });
  const changedIcon = await page.locator("#routes").innerHTML();
  assert.notEqual(changedIcon, savedIcon, "changed after an edit");
  await undo.click();
  assert.equal(await page.locator("#routes").innerHTML(), savedIcon, "saved again after Undo");
  // Save as new route keeps the first one.
  await map.click({ position: { x: box.width * 0.55, y: box.height * 0.6 } });
  page.once("dialog", (d) => d.accept("Longer route"));
  await page.locator("#routes").click();
  await page.locator("#save-new-route").click();
  const both = await page.evaluate(() => JSON.parse(localStorage.getItem("rf.routes")));
  assert.deepEqual(both.map((r) => [r.name, r.points.length]), [["Test route", 3], ["Longer route", 4]]);

  assert.deepEqual(errors, []);
  await context.close();
});

test("Settings › Routes lists every saved route by water and opens one on its lake map", async () => {
  const lake = squareLake();
  const lp = club.launchPoint;
  const routes = [
    { id: "r1", name: "Square loop", lakeId: club.lakeId, outAndBack: false, points: [lp, { lat: lp.lat + 0.006, lon: lp.lon }, { lat: lp.lat + 0.006, lon: lp.lon + 0.009 }] },
    { id: "r2", name: "Elsewhere", lakeId: "nowhere-lake", outAndBack: true, points: [{ lat: 48, lon: 11 }, { lat: 48.01, lon: 11 }] },
  ];
  const { page, errors, context } = await open({ ...visitor(), "rf.routes": routes });
  await context.route((url) => url.pathname.endsWith(`/v1/lakes/${club.lakeId}/view`),
    (route) => route.fulfill({ contentType: "application/json", body: JSON.stringify(lake) }));
  await page.goto(`${base}/app/#/settings`);
  const row = page.locator('a[href="#/settings/routes"]');
  await row.waitFor({ timeout: 20000 });
  assert.match(await row.innerText(), /2 routes/);
  await row.click();
  await page.locator(".all-routes .manage-routes").first().waitFor();
  const headings = await page.locator(".all-routes h3.section").allInnerTexts();
  assert.equal(headings.length, 2, "one group per water");
  assert.ok(headings.some((x) => /nowhere-lake/i.test(x)), `a water missing from the catalogue keeps its id: ${headings}`);
  // Per route: Share link and Export GPX in place of the row's tools (AllRoutesView), Close brings them back.
  await page.locator('.all-routes [data-share-one="r2"]').click();
  assert.ok(await page.locator('.all-routes [data-gpx="r2"]').isVisible());
  const [one] = await Promise.all([page.waitForEvent("download"), page.locator('.all-routes [data-gpx="r2"]').click()]);
  assert.equal(one.suggestedFilename(), "Elsewhere.gpx");
  assert.ok(await page.locator('.all-routes [data-share-one="r2"]').isVisible(), "the tools are back");
  await page.locator('.all-routes [data-share-one="r2"]').click();
  await page.locator('.all-routes [data-share-done]').locator("visible=true").click();
  assert.ok(await page.locator('.all-routes [data-delete="r2"]').isVisible());
  await page.locator('.all-routes [data-open="r1"]').click();
  await page.waitForFunction(() => location.hash.includes("route=r1"));
  await page.locator("#routes").waitFor({ timeout: 20000 });
  assert.ok(await page.locator("#undo").isDisabled(), "a freshly opened route has nothing to undo");
  assert.match(await page.locator(".route-line").innerText(), /km/);
  assert.equal(await page.locator(".lake-top a.round").getAttribute("href"), "#/settings/routes", "Close goes back to the list");
  // Routes › Export GPX downloads the open route as a GPX track (RouteGPX).
  await page.locator("#routes").click();
  const [download] = await Promise.all([page.waitForEvent("download"), page.locator("#export-gpx").click()]);
  assert.equal(download.suggestedFilename(), "Square loop.gpx");
  const gpx = await readFile(await download.path(), "utf8");
  assert.equal((gpx.match(/<trkpt /g) ?? []).length, 3);
  assert.deepEqual(errors, []);
  await context.close();
});

test("a route link from the app saves its route in this browser once and opens it on its lake map", async () => {
  const lake = squareLake();
  const lp = club.launchPoint;
  const shared = { name: "Shared loop", lakeId: club.lakeId, outAndBack: false, points: [lp, { lat: lp.lat + 0.006, lon: lp.lon }, { lat: lp.lat + 0.006, lon: lp.lon + 0.009 }] };
  const link = routeLink([shared], "#/routes/add?r=");
  const { page, errors, context } = await open(visitor());
  await context.route((url) => url.pathname.endsWith(`/v1/lakes/${club.lakeId}/view`),
    (route) => route.fulfill({ contentType: "application/json", body: JSON.stringify(lake) }));
  await page.goto(`${base}/app/${link}`);
  await page.waitForFunction(() => location.hash.startsWith("#/lake/") && location.hash.includes("route="), null, { timeout: 20000 });
  await page.locator("#routes").waitFor({ timeout: 20000 });
  const saved = await page.evaluate(() => JSON.parse(localStorage.getItem("rf.routes")));
  assert.deepEqual(saved.map((r) => [r.name, r.lakeId, r.points.length]), [["Shared loop", club.lakeId, 3]]);
  // The same link again does not save it twice; Settings › Routes offers a link with every route.
  await page.goto(`${base}/app/${link}`);
  await page.waitForFunction(() => location.hash.startsWith("#/lake/"), null, { timeout: 20000 });
  assert.equal(await page.evaluate(() => JSON.parse(localStorage.getItem("rf.routes")).length), 1);
  await page.goto(`${base}/app/#/settings/routes`);
  await page.locator("[data-share-routes]").waitFor();
  assert.deepEqual(errors, []);
  await context.close();
});

test("the Home Screen web app opens straight on the forecasts, a browser tab keeps the welcome page (owner, 15 Nov 2026)", async () => {
  const tab = await open(visitor());
  await tab.page.goto(`${base}/`);
  await tab.page.locator("a[href='/app/'] button").waitFor();
  assert.equal(new URL(tab.page.url()).pathname, "/", "a browser tab stays on the welcome page");
  await tab.context.close();
  const { page, errors, context } = await open(visitor());
  await page.addInitScript(() => Object.defineProperty(navigator, "standalone", { value: true }));
  await page.goto(`${base}/`);
  await page.waitForURL((url) => url.pathname === "/app/", { timeout: 10000 });
  await page.locator(".club-head h1").waitFor({ timeout: 20000 });
  assert.deepEqual(errors, []);
  await context.close();
});

test("the top tile's \"For small boats\" and weather word are 12 px, the app's caption size (owner's iPhone comparison, 16 Nov 2026)", async () => {
  const { page, errors, context } = await open(visitor());
  await page.goto(`${base}/app/#/club/${club.id}`);
  // Each read waits for its element: the page may draw the top tile again (radar, refresh) in between.
  const sizes = await page.waitForFunction(() => {
    const read = [".now-title .boat-for", ".now-sky small"].map((s) => document.querySelector(s)).map((el) => (el?.isConnected ? getComputedStyle(el).fontSize : ""));
    return read.every(Boolean) ? read : false;
  }, null, { timeout: 20000 }).then((x) => x.jsonValue());
  assert.deepEqual(sizes, ["12px", "12px"]);
  assert.deepEqual(errors, []);
  await context.close();
});

test("a visit without internet shows the last visit's forecast at once with Updating…, then the reason (decision 0044)", async () => {
  const { page, errors, context } = await open(visitor());
  await page.goto(`${base}/app/#/club/${club.id}`);
  await page.locator(".card.now").waitFor({ timeout: 20000 });
  // Kept in the background once it came.
  await page.waitForFunction(async () => (await (await caches.open("rf-forecasts")).keys()).length > 0, null, { timeout: 10000 });
  // The next visit: the forecast download hangs, then the connection is gone.
  let release;
  const held = new Promise((resolve) => (release = resolve));
  await context.route((url) => url.pathname.endsWith(`/clubs/${club.id}/forecast`), async (route) => {
    await held;
    await route.abort("internetdisconnected");
  });
  await page.reload();
  await page.locator(".club-head .updating").waitFor({ timeout: 20000 });
  assert.equal(await page.locator(".card.now").count(), 1, "the kept forecast shows while loading");
  release();
  await page.locator(".club-head #failed").waitFor({ timeout: 20000 });
  assert.equal(await page.locator(".club-head .updating").count(), 0);
  assert.equal(await page.locator(".card.now").count(), 1, "and stays with the reason");
  // The list shows it too.
  await page.goto(`${base}/app/#/list`);
  await page.locator("#saved .row.tinted").waitFor({ timeout: 20000 });
  assert.deepEqual(errors, []);
  await context.close();
});

test("a browser without the iPhone's text size setting keeps the text at 100 % (textsize.js)", async () => {
  const { page, errors, context } = await open(visitor());
  await page.goto(`${base}/app/#/club/${club.id}`);
  await page.locator(".club-head h1").waitFor({ timeout: 20000 });
  assert.equal(await page.evaluate(() => document.documentElement.dataset.textScale), "100");
  assert.deepEqual(errors, []);
  await context.close();
});

test("a cold start with a kept forecast never shows the stand-in cards; a first visit shows them without dashes (decision 0046)", async () => {
  const { page, errors, context } = await open(visitor());
  // Notes every time stand-in cards are put on the page, before any paint.
  await page.addInitScript(() => {
    globalThis.RF_STANDINS = 0;
    new MutationObserver((changes) => {
      for (const change of changes) {
        for (const node of change.addedNodes) {
          if (node.nodeType === 1 && (node.matches(".shimmer") || node.querySelector(".shimmer"))) globalThis.RF_STANDINS++;
        }
      }
    }).observe(document, { childList: true, subtree: true });
  });
  // First visit, forecast held back: stand-in cards with a light sweep, no "–" values, and the line in the header.
  await page.goto(`${base}/app/?stayLoading#/club/${club.id}`);
  await page.locator(".loading.shimmer").waitFor({ timeout: 20000 });
  assert.equal(await page.locator(".club-head .loading-line").count(), 1);
  assert.equal(await page.locator(".loading.shimmer .sh-value").count(), 3);
  assert.doesNotMatch(await page.locator(".loading.shimmer").innerText(), /–/);
  // A normal visit keeps the forecast in the browser.
  await page.goto(`${base}/app/#/club/${club.id}`);
  await page.locator(".card.now").waitFor({ timeout: 20000 });
  await page.waitForFunction(async () => (await (await caches.open("rf-forecasts")).keys()).length > 0, null, { timeout: 10000 });
  // The next start, its download held: the kept forecast is on the page from the start, never the stand-ins.
  let release;
  const held = new Promise((resolve) => (release = resolve));
  await context.route((url) => url.pathname.endsWith(`/clubs/${club.id}/forecast`), async (route) => {
    await held;
    await route.continue();
  });
  await page.reload();
  await page.locator(".club-head .updating").waitFor({ timeout: 20000 });
  assert.equal(await page.evaluate(() => globalThis.RF_STANDINS), 0, "no stand-in cards before the kept forecast");
  release();
  await page.locator(".club-head #updated-line").waitFor({ timeout: 20000 });
  assert.deepEqual(errors, []);
  await context.close();
});
