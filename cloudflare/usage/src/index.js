// Usage counter for the Row Frog backend.
//
// Sits in front of api.rowfrog.com (GitHub Pages today, a rented server
// later) and passes every request through unchanged. For a club forecast or
// a lake view it adds 1 to that club's or lake's count for the day, so the
// forecast job can refresh used places more often. Only the day, the club or
// lake id and the count are stored: no addresses, devices or other details.
//
// The forecast jobs also report how many calls they made to Open-Meteo and
// Copernicus, so a daily check can warn before the free limits are reached.
//
//   GET  /usage?days=7    clubs and lakes loaded in the last days    (key needed)
//   GET  /budget?days=35  calls per day and service                  (key needed)
//   POST /budget          {"service", "job", "calls"} adds calls     (key needed)
//
// The key is the Worker secret USAGE_KEY, sent as "Authorization: Bearer <key>".
//
// It also gives every file a tag made from its content (ETag). GitHub Pages
// tags a file anew on every publish, every 30 minutes, even when its bytes did
// not change, so the app downloaded satellite pictures, map tiles and lists
// again each time. Now an unchanged file answers "304 Not Modified" (owner, 6
// Nov 2026). Forecasts change on every run (warnings check time, radar).
//
// Forecasts from the Raspberry Pi (since Nov 2026): when the Worker has an R2
// bucket bound as FILES, the /v1/ files come from that bucket, which the Pi
// fills after every forecast run (scripts/local/pi/run-publish.sh). With no
// FILES binding everything passes through to GitHub Pages as before.
//
// Only real use counts (owner, 19 Nov 2026, decision 0051): the app and widget
// with a stamped build number (User-Agent "RowFrog/885 …", "RowFrogWidget/885
// …"), and the website (Origin or Referer rowfrog.com). Builds without a stamp
// (build 1: CI tap tests), curl and other scripts, and any request with the
// header "X-RowFrog-Test" still get the file but are not counted. On 17 Nov
// such requests made 37 clubs "used" instead of about 10.

const COUNTED = /^\/v1\/(clubs|lakes)\/([a-z0-9][a-z0-9-]{0,79})\/(forecast|view)$/;
const KEEP_DAYS = 120;

export default {
  async fetch(request, env, ctx) {
    const url = new URL(request.url);
    if (url.pathname === "/usage" || url.pathname === "/budget") {
      return api(request, env, url);
    }
    const response = await tagged(request, url, env);
    const match = url.pathname.match(COUNTED);
    if (match && request.method === "GET" && response.ok && realUse(request)) {
      const kind = match[1] === "clubs" ? "club" : "lake";
      ctx.waitUntil(count(env, kind, match[2]).catch(() => {}));
    }
    return response;
  },

  async scheduled(event, env) {
    const oldest = day(-KEEP_DAYS);
    await env.DB.batch([
      env.DB.prepare("DELETE FROM hits WHERE day < ?").bind(oldest),
      env.DB.prepare("DELETE FROM budget WHERE day < ?").bind(oldest),
    ]);
  },
};

// Files above this size pass through with GitHub's own tag (hashing them would take too long).
const TAG_MAX_BYTES = 2 * 1024 * 1024;

async function tagged(request, url, env) {
  if (env.FILES && url.pathname.startsWith("/v1/")) {
    return fromBucket(request, url, env.FILES);
  }
  if (request.method !== "GET" || !url.pathname.startsWith("/v1/")) {
    return fetch(request);
  }
  // Ask GitHub for the whole file: its own tag changes with every publish anyway.
  const headers = new Headers(request.headers);
  headers.delete("if-none-match");
  headers.delete("if-modified-since");
  const upstream = await fetch(new Request(request, { headers }));
  const size = Number(upstream.headers.get("content-length") || 0);
  if (upstream.status !== 200 || size > TAG_MAX_BYTES) {
    return upstream;
  }
  const body = await upstream.arrayBuffer();
  const digest = new Uint8Array(await crypto.subtle.digest("SHA-256", body));
  const etag = `W/"rf-${[...digest.slice(0, 12)].map((b) => b.toString(16).padStart(2, "0")).join("")}"`;
  const out = new Headers(upstream.headers);
  out.set("etag", etag);
  out.delete("last-modified");
  out.delete("content-length");
  const asked = (request.headers.get("if-none-match") || "").split(",").map((t) => t.trim().replace(/^W\//, ""));
  if (asked.includes(etag.replace(/^W\//, ""))) {
    out.delete("content-type");
    out.delete("content-encoding");
    return new Response(null, { status: 304, headers: out });
  }
  return new Response(body, { status: 200, headers: out });
}

// The headers GitHub Pages gave the files, which the app and the website
// (another origin, rowfrog.com) rely on: open to every origin, 10 minutes.
const BUCKET_HEADERS = { "access-control-allow-origin": "*", "cache-control": "max-age=600" };

function contentType(path) {
  if (path.endsWith(".jpg")) return "image/jpeg";
  if (path.endsWith(".png")) return "image/png";
  // The weather map tiles (maps/<tile>/<value>) are raw deflate bytes.
  if (path.startsWith("/v1/maps/") && path !== "/v1/maps/index") return "application/octet-stream";
  return "application/json; charset=utf-8";
}

async function fromBucket(request, url, bucket) {
  if (request.method === "OPTIONS") {
    return new Response(null, { status: 204, headers: { ...BUCKET_HEADERS, "access-control-allow-methods": "GET, HEAD" } });
  }
  if (request.method !== "GET" && request.method !== "HEAD") {
    return new Response("method not allowed", { status: 405, headers: BUCKET_HEADERS });
  }
  const key = decodeURIComponent(url.pathname.slice(1));
  if (key.includes("..") || key.endsWith("/")) {
    return new Response("not found", { status: 404, headers: BUCKET_HEADERS });
  }
  const object = await bucket.get(key);
  if (!object) {
    return new Response("not found", { status: 404, headers: { ...BUCKET_HEADERS, "content-type": "text/plain" } });
  }
  const body = await object.arrayBuffer();
  const digest = new Uint8Array(await crypto.subtle.digest("SHA-256", body));
  const etag = `W/"rf-${[...digest.slice(0, 12)].map((b) => b.toString(16).padStart(2, "0")).join("")}"`;
  const headers = new Headers({ ...BUCKET_HEADERS, etag, "content-type": contentType(url.pathname) });
  const asked = (request.headers.get("if-none-match") || "").split(",").map((t) => t.trim().replace(/^W\//, ""));
  if (asked.includes(etag.replace(/^W\//, ""))) {
    headers.delete("content-type");
    return new Response(null, { status: 304, headers });
  }
  return new Response(request.method === "HEAD" ? null : body, { status: 200, headers });
}

function day(offsetDays = 0) {
  return new Date(Date.now() + offsetDays * 86400000).toISOString().slice(0, 10);
}

const APP = /^RowFrog(?:Widget)?\/(\d+)\b/;
const WEBSITE = new Set(["rowfrog.com", "www.rowfrog.com"]);

function realUse(request) {
  if (request.headers.has("x-rowfrog-test")) return false;
  const app = (request.headers.get("user-agent") || "").match(APP);
  if (app) return Number(app[1]) > 1;
  for (const name of ["origin", "referer"]) {
    try {
      if (WEBSITE.has(new URL(request.headers.get(name)).hostname)) return true;
    } catch {
      // missing or not a URL
    }
  }
  return false;
}

async function count(env, kind, id) {
  await env.DB.prepare(
    "INSERT INTO hits (day, kind, id, n) VALUES (?, ?, ?, 1) ON CONFLICT (day, kind, id) DO UPDATE SET n = n + 1"
  )
    .bind(day(), kind, id)
    .run();
}

function json(body, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "content-type": "application/json", "cache-control": "no-store" },
  });
}

function days(url, fallback) {
  const n = parseInt(url.searchParams.get("days") || "", 10);
  return Number.isFinite(n) ? Math.min(Math.max(n, 1), KEEP_DAYS) : fallback;
}

async function api(request, env, url) {
  const auth = request.headers.get("authorization") || "";
  if (!env.USAGE_KEY || auth !== `Bearer ${env.USAGE_KEY}`) {
    return json({ error: "key needed" }, 401);
  }

  if (url.pathname === "/usage" && request.method === "GET") {
    const n = days(url, 7);
    const { results } = await env.DB.prepare(
      "SELECT kind, id, SUM(n) AS n FROM hits WHERE day >= ? GROUP BY kind, id"
    )
      .bind(day(-(n - 1)))
      .all();
    const out = { days: n, clubs: {}, lakes: {} };
    for (const r of results) out[r.kind === "club" ? "clubs" : "lakes"][r.id] = r.n;
    return json(out);
  }

  if (url.pathname === "/budget" && request.method === "GET") {
    const n = days(url, 35);
    const { results } = await env.DB.prepare(
      "SELECT day, service, job, calls FROM budget WHERE day >= ? ORDER BY day"
    )
      .bind(day(-(n - 1)))
      .all();
    return json({ days: n, rows: results });
  }

  if (url.pathname === "/budget" && request.method === "POST") {
    let body;
    try {
      body = await request.json();
    } catch {
      return json({ error: "JSON body needed" }, 400);
    }
    const { service, job, calls } = body || {};
    const name = /^[a-z0-9-]{1,40}$/;
    if (!name.test(service || "") || !name.test(job || "") || !(typeof calls === "number" && calls >= 0 && calls < 1e7)) {
      return json({ error: "service, job and calls needed" }, 400);
    }
    await env.DB.prepare(
      "INSERT INTO budget (day, service, job, calls) VALUES (?, ?, ?, ?) ON CONFLICT (day, service, job) DO UPDATE SET calls = calls + excluded.calls"
    )
      .bind(day(), service, job, calls)
      .run();
    return json({ ok: true });
  }

  return json({ error: "not found" }, 404);
}
