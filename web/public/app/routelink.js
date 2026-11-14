// Saved routes as a link, so routes planned in the app (or another browser) can be saved in this browser
// (owner, 14 Nov 2026). The app's RouteLink.swift makes the same links:
//   https://rowfrog.com/app/#/routes/add?r=<base64url of {"v":1,"routes":[{"name","lake","back","p":[[lat,lon],…]}]}>
// Points are rounded to 5 decimals (about 1 m); an imported row's track and date stay on the device.

export const LINK_BASE = "https://rowfrog.com/app/#/routes/add?r=";
/** Most turning points one shared route may bring, and most routes in one link. */
export const MAX_POINTS = 500;
export const MAX_ROUTES = 200;

const round = (x) => Math.round(x * 1e5) / 1e5;

function toBase64url(text) {
  let bin = "";
  for (const b of new TextEncoder().encode(text)) bin += String.fromCharCode(b);
  return btoa(bin).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
}

function fromBase64url(text) {
  const bin = atob(text.replace(/-/g, "+").replace(/_/g, "/"));
  return new TextDecoder().decode(Uint8Array.from(bin, (c) => c.charCodeAt(0)));
}

/** The link for these saved routes. */
export function routeLink(routes, base = LINK_BASE) {
  const payload = { v: 1, routes: routes.map((r) => ({ name: r.name, lake: r.lakeId, back: !!r.outAndBack, p: r.points.map((p) => [round(p.lat), round(p.lon)]) })) };
  return base + toBase64url(JSON.stringify(payload));
}

/**
 * The routes in a link's `r` value, as new routes ready to save (fresh ids), or null when it is not a route link.
 * Routes that are malformed are left out.
 */
export function readRouteLink(value, newId = () => crypto.randomUUID?.() ?? `r${Date.now()}${Math.random()}`) {
  let payload;
  try {
    payload = JSON.parse(fromBase64url(value));
  } catch {
    return null;
  }
  if (payload?.v !== 1 || !Array.isArray(payload.routes)) return null;
  const ok = (p) => Array.isArray(p) && p.length === 2 && Number.isFinite(p[0]) && Number.isFinite(p[1]) && Math.abs(p[0]) <= 90 && Math.abs(p[1]) <= 180;
  return payload.routes.slice(0, MAX_ROUTES)
    .filter((r) => typeof r?.lake === "string" && r.lake && Array.isArray(r.p) && r.p.length >= 2 && r.p.length <= MAX_POINTS && r.p.every(ok))
    .map((r) => ({ id: newId(), name: String(r.name ?? "").trim().slice(0, 100) || "Route", lakeId: r.lake, points: r.p.map(([lat, lon]) => ({ lat, lon })), outAndBack: r.back === true }));
}

const same = (a, b) => a.lakeId === b.lakeId && a.outAndBack === b.outAndBack && a.points.length === b.points.length
  && a.points.every((p, i) => round(p.lat) === round(b.points[i].lat) && round(p.lon) === round(b.points[i].lon));

/**
 * Adds the shared routes to the saved ones, skipping any already saved (same water, points and way back), so
 * opening a link twice does not save it twice. Returns the saved list and, per shared route, the saved one.
 */
export function addSharedRoutes(saved, shared) {
  const list = [...saved];
  const result = shared.map((r) => {
    const have = list.find((x) => same(x, r));
    if (have) return have;
    list.push(r);
    return r;
  });
  return { list, routes: result };
}
