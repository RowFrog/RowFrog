// Local ops (Mac merge queue, 12 Nov 2026): serves a built web/dist for the iOS Simulator's Mobile Safari.
// /v1/* goes to the local backend on :8765. /seed?scheme=…&bg=…&tiles=… writes the rf.* keys on this
// origin and opens the club page; the page is then scrolled (by a small script added to /app/ only
// here, never in the repo) until the 48-hour header is pinned with rows under it.
// Usage: node scripts/local/safari-sim-server.mjs <dist dir> <port> [pin selector] [route hash]
// Never part of web/dist: the seed page and the scroll script exist only in this local server.
import { createServer } from "node:http";
import { readFile } from "node:fs/promises";
import { join, normalize, extname } from "node:path";

const [DIST, PORT, PIN = ".hourly-card", ROUTE = "#/club/mrc-1880"] = process.argv.slice(2);
const TYPES = { ".html": "text/html", ".js": "text/javascript", ".css": "text/css", ".json": "application/json",
  ".png": "image/png", ".jpg": "image/jpeg", ".svg": "image/svg+xml", ".webmanifest": "application/manifest+json" };

const seed = (q) => `<!doctype html><meta charset="utf-8"><script>
const s = ${JSON.stringify(q)};
const clubs = ${"%CLUBS%"};
const set = (k, v) => localStorage.setItem(k, JSON.stringify(v));
set("rf.safety", { version: 1, at: new Date().toISOString() });
set("rf.tourSeen", true); set("rf.language", "en"); set("rf.clubs", clubs);
set("rf.tipsClosed", ${"%TIPS%"});
set("rf.background", s.bg || "sample:alpine-lake"); set("rf.tileStyle", s.tiles || "frosted");
if (s.pin !== "none") sessionStorage.setItem("rf.pinHeader", "1"); else sessionStorage.removeItem("rf.pinHeader");
location.replace("/app/" + ${"%ROUTE%"});
</script>`;

const pinScript = `<script>
if (sessionStorage.getItem("rf.pinHeader")) {
  let n = 0;
  const t = setInterval(() => {
    const card = document.querySelector(${JSON.stringify(PIN)});
    if (card) { const y = card.getBoundingClientRect().top + scrollY; scrollTo(0, y + 420); }
    if (++n > 40) clearInterval(t);
  }, 400);
}
</script>`;

createServer(async (req, res) => {
  const url = new URL(req.url, "http://x");
  const path = normalize(decodeURIComponent(url.pathname));
  try {
    if (path.startsWith("/v1/")) {
      const r = await fetch(`http://localhost:8765/${path.slice(4)}`);
      res.writeHead(r.status, { "Content-Type": "application/json" });
      return res.end(Buffer.from(await r.arrayBuffer()));
    }
    if (path === "/seed") {
      const lakes = await (await fetch("http://localhost:8765/lakes/index")).json();
      const club = lakes.flatMap((l) => l.clubs.map((c) => ({ ...c, lakeId: l.id }))).find((c) => c.id === "mrc-1880");
      const tour = await readFile(join(DIST, "app/tour.js"), "utf8");
      const block = tour.match(/const TIPS = \{([\s\S]*?)\n\};/);
      const tips = block ? [...block[1].matchAll(/^\s{2}([A-Za-z0-9_]+|"[^"]+"):/gm)].map((m) => m[1].replace(/"/g, "")) : [];
      const page = seed(Object.fromEntries(url.searchParams)).replace("%CLUBS%", JSON.stringify([club])).replace("%TIPS%", JSON.stringify(tips)).replace("%ROUTE%", JSON.stringify(ROUTE));
      res.writeHead(200, { "Content-Type": "text/html" });
      return res.end(page);
    }
    let file = join(DIST, path);
    if (path.endsWith("/")) file = join(file, "index.html");
    let body = await readFile(file);
    if (path === "/app/" || path === "/app/index.html") {
      body = Buffer.from(body.toString("utf8").replace(/<\/body>/i, pinScript + "</body>"));
      // The API base for this server (the app reads RF_API before its own default).
      body = Buffer.from(body.toString("utf8").replace(/<head>/i, `<head><script>globalThis.RF_API = location.origin + "/v1";</script>`));
    }
    res.writeHead(200, { "Content-Type": TYPES[extname(file)] ?? "application/octet-stream", "Cache-Control": "no-store" });
    res.end(body);
  } catch (e) {
    res.writeHead(404).end(String(e));
  }
}).listen(Number(PORT), "127.0.0.1", () => console.log(`serving ${DIST} on ${PORT}`));
