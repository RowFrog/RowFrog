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

const COUNTED = /^\/v1\/(clubs|lakes)\/([a-z0-9][a-z0-9-]{0,79})\/(forecast|view)$/;
const KEEP_DAYS = 120;

export default {
  async fetch(request, env, ctx) {
    const url = new URL(request.url);
    if (url.pathname === "/usage" || url.pathname === "/budget") {
      return api(request, env, url);
    }
    const response = await tagged(request, url);
    const match = url.pathname.match(COUNTED);
    if (match && request.method === "GET" && response.ok) {
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

async function tagged(request, url) {
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

function day(offsetDays = 0) {
  return new Date(Date.now() + offsetDays * 86400000).toISOString().slice(0, 10);
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
