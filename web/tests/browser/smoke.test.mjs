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
  assert.equal(await line.getAttribute("aria-expanded"), "true");
  assert.equal(await rows.isVisible(), true, "a tap shows the night's hours");
  const opened = await days();
  assert.equal(new Set(opened).size, opened.length, "no day header twice");
  assert.deepEqual([...new Set(opened)], [...new Set(folded)], "the same days either way");
  if (process.env.RF_NIGHT_SHOT) await page.locator(".hourly-card").screenshot({ path: `${process.env.RF_NIGHT_SHOT}-open.png` });
  await line.click();
  assert.equal(await rows.isHidden(), true, "a second tap folds it again");
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

test("the header's forecast time is the model run's arrival, and the update cycles open from the page's end", async () => {
  const { page, errors, context } = await open(visitor());
  // The run came out 40 minutes before the server built the file (weatherRun, app #403).
  const made = new Date(forecast.generatedAt);
  const run = { model: "ICON-D2", started: new Date(made - 3 * 3600e3).toISOString(), available: new Date(made - 40 * 60e3).toISOString() };
  await context.route((url) => url.pathname.endsWith("/v1/clubs/mrc-1880/forecast"),
    (route) => route.fulfill({ contentType: "application/json", body: JSON.stringify({ ...forecast, weatherRun: run }) }));
  await page.goto(`${base}/app/#/club/mrc-1880`);
  const clock = (d) => new Date(d).toLocaleTimeString("en-GB", { hour: "2-digit", minute: "2-digit", timeZone: "Europe/Berlin" });
  await page.waitForFunction((at) => document.querySelector("#updated-line")?.innerText.includes(`Forecast from ${at}`), clock(run.available), { timeout: 20000 });
  await page.locator("#updates").click();
  const sheet = page.locator("dialog.sheet");
  await sheet.waitFor();
  const text = await sheet.innerText();
  assert.ok(text.includes(`model run of ${clock(run.started)}, ready at ${clock(run.available)}`), text.slice(0, 300));
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
  assert.match(await tile.innerText(), /0\.3 km/);
  assert.ok(await tile.locator(".cause-red").count(), "the value takes the light's colour");
  assert.match(await page.locator(".card.now ul.reasons").innerText(), /Fog within 1 km of the launch point: visibility 0\.3 km\./);
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
  await page.locator("#refresh").waitFor({ state: "attached", timeout: 20000 });
  refused.add(path);
  // The header line can sit under the top bar on a phone-size page; the tap itself is what counts.
  await page.locator("#refresh").dispatchEvent("click");
  await shows("#failed", "Could not update: server refused the download (error 403)");
  assert.ok(await page.locator(".card.now").first().isVisible(), "the forecast stays");
  refused.clear();
  assert.deepEqual(errors, []);
  await context.close();
});

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
    await page.waitForTimeout(100);
    const now = await at();
    assert.ok(now.cog > 0, `in the window at ${y}`);
    assert.equal(now.cog, now.list, `cog level with the list at ${y}`);
    assert.equal(now.boat, now.list, `boat level with the list at ${y}`);
  }
  // The list slid away and back: the bar's buttons follow the page's column again.
  await page.evaluate(() => scrollTo(0, 0));
  await page.click("#hide-list");
  await page.locator("[data-show-list]").first().waitFor();
  await page.locator(".top-title [data-show-list]").click();
  await page.locator("#hide-list").waitFor();
  await page.waitForTimeout(600);
  let now = await at();
  assert.equal(now.cog, now.list);
  assert.equal(now.cogLeft, now.boatRight, "the buttons sit at the page's column edges");
  assert.ok(now.cogLeft >= 0 && now.cogLeft < 24);
  await page.setViewportSize({ width: 1100, height: 900 });
  await page.waitForTimeout(300);
  now = await at();
  assert.equal(now.cogLeft, now.boatRight, "and again after the window was resized");
  assert.ok(now.cogLeft >= 0 && now.cogLeft < 24);
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

test("the route editor: undo takes back the way back, Save marks the route saved, an edit changed and undo saved again", async () => {
  const { page, errors, context } = await open(visitor());
  const lake = squareLake();
  await context.route((url) => url.pathname.endsWith(`/v1/lakes/${club.lakeId}/view`),
    (route) => route.fulfill({ contentType: "application/json", body: JSON.stringify(lake) }));
  await page.goto(`${base}/app/#/lake/${club.lakeId}/${club.id}`);
  await page.locator("#route-mode").click({ timeout: 20000 });
  const map = page.locator("#lake-map");
  const box = await map.boundingBox();
  // Taps on the water above the panel add turning points.
  for (const [x, y] of [[0.3, 0.2], [0.7, 0.25]]) await map.click({ position: { x: box.width * x, y: box.height * y } });
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
  await map.click({ position: { x: box.width * 0.5, y: box.height * 0.35 } });
  const changedIcon = await page.locator("#routes").innerHTML();
  assert.notEqual(changedIcon, savedIcon, "changed after an edit");
  await undo.click();
  assert.equal(await page.locator("#routes").innerHTML(), savedIcon, "saved again after Undo");
  // Save as new route keeps the first one.
  await map.click({ position: { x: box.width * 0.5, y: box.height * 0.35 } });
  page.once("dialog", (d) => d.accept("Longer route"));
  await page.locator("#routes").click();
  await page.locator("#save-new-route").click();
  const both = await page.evaluate(() => JSON.parse(localStorage.getItem("rf.routes")));
  assert.deepEqual(both.map((r) => [r.name, r.points.length]), [["Test route", 3], ["Longer route", 4]]);

  assert.deepEqual(errors, []);
  await context.close();
});
