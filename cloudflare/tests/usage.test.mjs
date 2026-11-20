// The usage counter (cloudflare/usage): passes every request through, counts
// club and lake loads per day, and keeps the jobs' call totals behind a key.
import assert from "node:assert/strict";
import { afterEach, beforeEach, test } from "node:test";
import { fileURLToPath } from "node:url";
import worker from "../usage/src/index.js";
import { FakeD1, fakeCtx, fakeFetch } from "./fakes.mjs";

const SCHEMA = fileURLToPath(new URL("../usage/schema.sql", import.meta.url));
const KEY = "test-key";
const today = () => new Date().toISOString().slice(0, 10);
let env, upstream;

beforeEach(() => {
  env = { DB: new FakeD1(SCHEMA), USAGE_KEY: KEY };
  upstream = fakeFetch((request) =>
    new URL(request.url).pathname.includes("missing") ? new Response("no", { status: 404 }) : new Response("{}")
  );
});
afterEach(() => upstream.restore());

const APP_UA = "RowFrog/885 CFNetwork/3826.500.111 Darwin/25.1.0";

async function get(path, { method = "GET", key, body, headers: extra = { "user-agent": APP_UA } } = {}) {
  const ctx = fakeCtx();
  const headers = { ...extra, ...(key ? { authorization: `Bearer ${key}` } : {}) };
  const response = await worker.fetch(new Request(`https://api.rowfrog.com${path}`, { method, headers, body }), env, ctx);
  await ctx.done();
  return response;
}

test("a club forecast or lake view passes through and is counted per day", async () => {
  const response = await get("/v1/clubs/mrc-1880/forecast");
  assert.equal(response.status, 200);
  assert.equal(await response.text(), "{}");
  assert.equal(upstream.length, 1);
  await get("/v1/clubs/mrc-1880/forecast");
  await get("/v1/lakes/starnberger-see/view");
  assert.deepEqual(env.DB.rows("SELECT day, kind, id, n FROM hits ORDER BY kind"), [
    { day: today(), kind: "club", id: "mrc-1880", n: 2 },
    { day: today(), kind: "lake", id: "starnberger-see", n: 1 },
  ]);
});

test("other requests pass through without a count", async () => {
  for (const path of ["/v1/lakes.json", "/v1/clubs/missing/forecast", "/v1/clubs/MRC/forecast", "/v1/clubs/a/b/forecast", "/v1/clubs/mrc-1880/history"]) {
    const response = await get(path);
    assert.ok(response.status === 200 || response.status === 404, path);
  }
  await get("/v1/clubs/mrc-1880/forecast", { method: "POST", body: "x" });
  assert.equal(upstream.length, 6);
  assert.deepEqual(env.DB.rows("SELECT * FROM hits"), []);
});

test("only the real app, widget and website count; tests and scripts get the file uncounted", async () => {
  const counted = [
    { "user-agent": APP_UA },
    { "user-agent": "RowFrogWidget/885 CFNetwork/3826.500.111 Darwin/25.1.0" },
    { "user-agent": "Mozilla/5.0 (iPhone) Safari/604.1", origin: "https://rowfrog.com" },
    { "user-agent": "Mozilla/5.0 Safari/605.1.15", referer: "https://www.rowfrog.com/app/" },
  ];
  const ignored = [
    { "user-agent": "RowFrog/1 CFNetwork/3826.500.111 Darwin/25.1.0" },
    { "user-agent": "curl/8.5.0" },
    { "user-agent": "python-httpx/0.28.1" },
    {},
    { "user-agent": APP_UA, "x-rowfrog-test": "1" },
    { "user-agent": "Mozilla/5.0 Safari/605.1.15", origin: "https://rowfrog.com.example.net" },
    { "user-agent": "Mozilla/5.0 Safari/605.1.15", referer: "not a url" },
  ];
  for (const headers of [...counted, ...ignored]) {
    const response = await get("/v1/clubs/mrc-1880/forecast", { headers });
    assert.equal(response.status, 200);
  }
  assert.equal(upstream.length, counted.length + ignored.length);
  assert.deepEqual(env.DB.rows("SELECT id, n FROM hits"), [{ id: "mrc-1880", n: counted.length }]);
});

test("a counting error never breaks the response", async () => {
  env.DB = { prepare: () => ({ bind: () => ({ run: async () => { throw new Error("D1 down"); } }) }) };
  const response = await get("/v1/clubs/mrc-1880/forecast");
  assert.equal(response.status, 200);
});

test("/usage and /budget need the key and never reach the backend", async () => {
  for (const [path, method] of [["/usage", "GET"], ["/budget", "GET"], ["/budget", "POST"]]) {
    assert.equal((await get(path, { method })).status, 401);
    assert.equal((await get(path, { method, key: "wrong" })).status, 401);
  }
  env.USAGE_KEY = "";
  assert.equal((await get("/usage", { key: "" })).status, 401);
  assert.equal(upstream.length, 0);
});

test("/usage sums the counts of the last days", async () => {
  env.DB.db.exec(`INSERT INTO hits VALUES ('${today()}', 'club', 'mrc-1880', 3), ('2000-01-01', 'club', 'mrc-1880', 50),
                  ('${today()}', 'lake', 'starnberger-see', 2)`);
  const response = await get("/usage", { key: KEY });
  assert.equal(response.headers.get("cache-control"), "no-store");
  assert.deepEqual(await response.json(), { days: 7, clubs: { "mrc-1880": 3 }, lakes: { "starnberger-see": 2 } });
  assert.equal((await (await get("/usage?days=1000", { key: KEY })).json()).days, 120);
  assert.equal((await (await get("/usage?days=0", { key: KEY })).json()).days, 1);
  assert.equal((await (await get("/usage?days=abc", { key: KEY })).json()).days, 7);
});

test("/budget adds the jobs' calls per day, service and job", async () => {
  const post = (body) => get("/budget", { method: "POST", key: KEY, body: JSON.stringify(body) });
  assert.equal((await post({ service: "open-meteo", job: "publish", calls: 120 })).status, 200);
  assert.equal((await post({ service: "open-meteo", job: "publish", calls: 30.5 })).status, 200);
  assert.equal((await post({ service: "copernicus", job: "ice", calls: 4 })).status, 200);
  const { days, rows } = await (await get("/budget", { key: KEY })).json();
  assert.equal(days, 35);
  assert.deepEqual(rows.sort((a, b) => a.service.localeCompare(b.service)), [
    { day: today(), service: "copernicus", job: "ice", calls: 4 },
    { day: today(), service: "open-meteo", job: "publish", calls: 150.5 },
  ]);
});

test("/budget turns away bad reports", async () => {
  const bad = [
    "not json",
    JSON.stringify({ service: "Open Meteo", job: "publish", calls: 1 }),
    JSON.stringify({ service: "open-meteo", job: "", calls: 1 }),
    JSON.stringify({ service: "open-meteo", job: "publish", calls: -1 }),
    JSON.stringify({ service: "open-meteo", job: "publish", calls: "5" }),
    JSON.stringify({ service: "open-meteo", job: "publish", calls: 1e8 }),
    "null",
  ];
  for (const body of bad) {
    assert.equal((await get("/budget", { method: "POST", key: KEY, body })).status, 400, body);
  }
  assert.deepEqual(env.DB.rows("SELECT * FROM budget"), []);
  assert.equal((await get("/usage", { method: "POST", key: KEY })).status, 404);
});

test("the daily clean-up deletes counts older than 120 days", async () => {
  const old = new Date(Date.now() - 121 * 86400000).toISOString().slice(0, 10);
  const kept = new Date(Date.now() - 119 * 86400000).toISOString().slice(0, 10);
  env.DB.db.exec(`INSERT INTO hits VALUES ('${old}', 'club', 'a', 1), ('${kept}', 'club', 'b', 1);
                  INSERT INTO budget VALUES ('${old}', 'open-meteo', 'publish', 1), ('${kept}', 'open-meteo', 'publish', 2)`);
  await worker.scheduled({}, env);
  assert.deepEqual(env.DB.rows("SELECT id FROM hits"), [{ id: "b" }]);
  assert.deepEqual(env.DB.rows("SELECT calls FROM budget"), [{ calls: 2 }]);
});

test("a file is tagged by its content, and an unchanged one answers 304", async () => {
  upstream.restore();
  let body = "same bytes";
  const seen = [];
  upstream = fakeFetch((request) => {
    seen.push(request.headers.get("if-none-match"));
    return new Response(body, { headers: { etag: `W/"${Math.random()}"`, "last-modified": "Fri, 06 Nov 2026 13:00:00 GMT" } });
  });
  const first = await get("/v1/lakes/starnberger-see/satellite-latest.jpg");
  const tag = first.headers.get("etag");
  assert.match(tag, /^W\/"rf-[0-9a-f]{24}"$/);
  assert.equal(first.headers.get("last-modified"), null);
  assert.equal(await first.text(), "same bytes");

  const ctx = fakeCtx();
  const again = await worker.fetch(
    new Request("https://api.rowfrog.com/v1/lakes/starnberger-see/satellite-latest.jpg", { headers: { "if-none-match": tag } }),
    env,
    ctx
  );
  await ctx.done();
  assert.equal(again.status, 304);
  assert.equal(await again.text(), "");
  assert.equal(seen[1], null, "GitHub is asked for the whole file, not with the app's tag");

  body = "new bytes";
  const ctx2 = fakeCtx();
  const changed = await worker.fetch(
    new Request("https://api.rowfrog.com/v1/lakes/starnberger-see/satellite-latest.jpg", { headers: { "if-none-match": tag } }),
    env,
    ctx2
  );
  await ctx2.done();
  assert.equal(changed.status, 200);
  assert.notEqual(changed.headers.get("etag"), tag);
  assert.equal(await changed.text(), "new bytes");
});

test("missing files and the key-protected pages are not tagged", async () => {
  const missing = await get("/v1/clubs/missing/forecast");
  assert.equal(missing.status, 404);
  assert.equal(missing.headers.get("etag"), null);
});

// Forecasts from the Pi (scripts/local/pi/run-publish.sh): with an R2 bucket bound as FILES the files come from the bucket.
class FakeBucket {
  constructor(files) {
    this.files = files;
  }
  async get(key) {
    const text = this.files[key];
    return text === undefined ? null : { arrayBuffer: async () => new TextEncoder().encode(text).buffer };
  }
}

test("with a FILES bucket the files come from it, open to the website, and are still counted", async () => {
  env.FILES = new FakeBucket({ "v1/clubs/mrc-1880/forecast": '{"club":"mrc-1880"}', "v1/lakes/starnberger-see/ice.png": "png" });
  const response = await get("/v1/clubs/mrc-1880/forecast");
  assert.equal(response.status, 200);
  assert.equal(await response.text(), '{"club":"mrc-1880"}');
  assert.equal(response.headers.get("access-control-allow-origin"), "*");
  assert.match(response.headers.get("content-type"), /^application\/json/);
  assert.match(response.headers.get("etag"), /^W\/"rf-[0-9a-f]{24}"$/);
  assert.equal(upstream.length, 0, "GitHub is never asked");
  assert.deepEqual(env.DB.rows("SELECT kind, id, n FROM hits"), [{ kind: "club", id: "mrc-1880", n: 1 }]);

  const ctx = fakeCtx();
  const again = await worker.fetch(
    new Request("https://api.rowfrog.com/v1/clubs/mrc-1880/forecast", { headers: { "if-none-match": response.headers.get("etag") } }),
    env,
    ctx
  );
  await ctx.done();
  assert.equal(again.status, 304);

  assert.equal((await get("/v1/lakes/starnberger-see/ice.png")).headers.get("content-type"), "image/png");
  const missing = await get("/v1/clubs/missing/forecast");
  assert.equal(missing.status, 404);
  assert.equal(missing.headers.get("access-control-allow-origin"), "*");
  assert.equal(env.DB.rows("SELECT n FROM hits WHERE id = 'missing'").length, 0);
  assert.equal((await get("/v1/clubs/")).status, 404);
});
