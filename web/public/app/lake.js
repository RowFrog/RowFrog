// The lake view and route planning, worked out from /lakes/{id}/view as in the
// app (LakeView.swift, Route.swift). Kept free of the page so Node can test it.

import { key, limitsFor, coldWaterKit } from "./logic.js";

const RANK = { green: 0, amber: 1, red: 2 };
const LIGHTS = ["green", "amber", "red"];
const worse = (a, b) => (RANK[b] > RANK[a] ? b : a);

/** The view as the backend sends it, with each hour's lights as a list (one digit per cell). */
export function decodeView(raw) {
  return {
    ...raw,
    hours: raw.hours.map((hour) => ({
      ...hour,
      lights: typeof hour.lights === "string" ? [...hour.lights].map((c) => LIGHTS[Number(c)] ?? "green") : hour.lights,
      wind: hour.wind.map((w) => ({ ...w, other: w.other == null ? null : LIGHTS[Math.min(2, w.other)] })),
    })),
  };
}

/** The hour that is running at `at`, else the first one. */
export function hourIndex(view, at = new Date()) {
  let found = 0;
  view.hours.forEach((h, i) => {
    if (new Date(h.time) <= at) found = i;
  });
  return found;
}

/** Older than a club forecast may be: green turns grey. */
export const viewStale = (view, now = new Date()) => now - new Date(view.generatedAt) > 3 * 3600 * 1000;

function light(value, amber, red) {
  if (value == null) return "green";
  return value > red ? "red" : value >= amber ? "amber" : "green";
}

/**
 * The lake coloured for a boat's wind, gust and wave limits (LakeView.applying);
 * unchanged with the backend's own, or when the backend sends no fog per point.
 */
export function applyLakeLimits(view, limits, standard) {
  if (standard || !view.hours.every((h) => h.wind.every((w) => w.other != null))) return view;
  const { grid } = view;
  return {
    ...view,
    hours: view.hours.map((hour) => {
      // In cold water the app's wind limits drop, as on the backend.
      const cold = view.waterC != null ? view.waterC < 10 : hour.lakeWide.reasons.some((r) => r.condition === "cold_water");
      const forBoat = limitsFor(limits.boat, limits.custom, cold ? 0 : null);
      const reasons = hour.lakeWide.reasons
        .map((r) => (r.condition === "lake_strong_wind" ? { ...r, light: forBoat.strongWindLight } : r))
        .filter((r) => r.condition !== "single_cold" || forBoat.maybeSingle)
        .sort((a, b) => RANK[b.light] - RANK[a.light]);
      const zoneLights = hour.zones.map(() => "green");
      const lights = hour.lights.map((_, i) => {
        const wind = hour.wind[grid.cellPoint[i] ?? 0];
        let l = wind?.other ?? "green";
        l = worse(l, light(wind?.speedMs, forBoat.value("windAmber"), forBoat.value("windRed")));
        l = worse(l, light(wind?.gustMs, forBoat.value("gustAmber"), forBoat.value("gustRed")));
        l = worse(l, light(hour.wavesCm[i] / 100, forBoat.value("waveAmber"), forBoat.value("waveRed")));
        const z = grid.cellZone[i] ?? 0;
        if (z < zoneLights.length) zoneLights[z] = worse(zoneLights[z], l);
        return l;
      });
      return {
        ...hour,
        lakeWide: { light: reasons.reduce((w, r) => worse(w, r.light), "green"), reasons },
        lights,
        zones: hour.zones.map((z, i) => ({ ...z, light: zoneLights[i] })),
      };
    }),
  };
}

/** The stripes the maps draw over the water: red while the whole lake is red, amber for an amber lake-wide reason other than cold water. */
export function stripes(lakeWide) {
  if (lakeWide.light === "red") return "red";
  const cold = ["cold_water", "cool_water", "single_cold", "freezing_water"];
  return lakeWide.reasons.some((r) => r.light === "amber" && !cold.includes(r.condition)) ? "amber" : null;
}

/** The shore on the maps while the water is cold: "cool" from the life-jacket limit down, "cold" below 10 °C. */
export function coldShore(waterC, limits) {
  const kit = coldWaterKit(waterC, limits);
  return kit ? (kit === "lifeJacket" ? "cool" : "cold") : null;
}

/** Share of the water that is green, amber and red; a lake-wide red closes the whole lake. */
export function shares(hour) {
  if (hour.lakeWide.light === "red") return { red: 1 };
  const out = {};
  for (const l of hour.lights) out[l] = (out[l] ?? 0) + 1;
  for (const l of Object.keys(out)) out[l] /= Math.max(hour.lights.length, 1);
  return out;
}

export const ZONE_TITLES = {
  north: key("North"), northeast: key("Northeast"), east: key("East"), southeast: key("Southeast"), south: key("South"),
  southwest: key("Southwest"), west: key("West"), northwest: key("Northwest"), middle: key("Middle"),
};
export const ZONE_PHRASES = {
  north: key("in the north"), northeast: key("in the northeast"), east: key("in the east"), southeast: key("in the southeast"),
  south: key("in the south"), southwest: key("in the southwest"), west: key("in the west"), northwest: key("in the northwest"),
  middle: key("in the middle"),
};
export const zoneTitle = (name, water = "lake") => ZONE_TITLES[name] ?? (water === "lake" ? key("Whole lake") : key("Whole stretch"));

/** "lake", "river" or "canal": a river section is a club's stretch of its river or canal (WaterKind). */
export const waterKind = (view) => (view?.kind !== "river" ? "lake" : view.section?.waterway === "canal" ? "canal" : "river");

/** The view's names by water (WaterKind.viewTitle, opensHint, aboutTitle). */
export const WATER_TEXTS = {
  lake: { view: key("Lake view"), opens: key("Opens the lake view"), about: key("About the lake view") },
  river: { view: key("River view"), opens: key("Opens the river view"), about: key("About the river view") },
  canal: { view: key("Canal view"), opens: key("Opens the canal view"), about: key("About the canal view") },
};

/** Where a river section ends, for the map's pins: [English text, ...arguments] (SectionEnd.title). */
export function sectionEndTitle(end) {
  const [first, ...rest] = (end.what ?? "").split(" ");
  const name = rest.length ? ` ${rest.join(" ")}` : "";
  switch (end.end) {
    case "weir/lock":
      return [{ lock: key("Lock"), lock_gate: key("Lock"), dam: key("Dam"), waterfall: key("Waterfall") }[first] ?? key("Weir"), name];
    case "river": return [key("%@ joins"), end.what.replace(" joins", "").replace(" branches off", "")];
    case "mouth": return [key("River mouth")];
    case "harbour": return [key("Harbour")];
    case "km sign": return [key("River km %@"), end.what.replace("river km ", "")];
    default: return [key("End of the stretch")];
  }
}

/** A river opens on the 10 km around the page's club, not on its whole stretch (LakeOverlay.openRect). */
export function openBounds(view, club) {
  const e = gridEdges(view.grid);
  if (!view.section || !club?.launchPoint) return e;
  const { lat, lon } = club.launchPoint;
  const dLat = 5000 / 111320;
  const dLon = 5000 / (111320 * Math.cos((lat * Math.PI) / 180));
  const box = { south: Math.max(e.south, lat - dLat), north: Math.min(e.north, lat + dLat), west: Math.max(e.west, lon - dLon), east: Math.min(e.east, lon + dLon) };
  return box.south < box.north && box.west < box.east ? box : e;
}
export const zonePhrase = (name) => ZONE_PHRASES[name] ?? key("on the whole lake");

/**
 * One line for the hour (LakeView.headline): [English text, ...arguments], such
 * as ["Calmest %@, roughest %@", "in the south", "in the north"].
 */
export function headline(view, hour) {
  const lake = waterKind(view) === "lake";
  const all = {
    green: lake ? key("Good to row on the whole lake") : key("Good to row on the whole stretch"),
    amber: lake ? key("Row with care on the whole lake") : key("Row with care on the whole stretch"),
    red: lake ? key("Stay ashore on the whole lake") : key("Stay ashore on the whole stretch"),
  };
  if (hour.lakeWide.light === "red") return [all.red];
  const ranked = view.zones.map((z, i) => [z, hour.zones[i]]).filter(([, z]) => z)
    .sort((a, b) => RANK[a[1].light] - RANK[b[1].light] || a[1].maxWaveM - b[1].maxWaveM);
  if (!ranked.length) return [""];
  const best = ranked[0];
  const worst = ranked[ranked.length - 1];
  if (best[1].light === worst[1].light || view.zones.length < 2) {
    return [all[worst[1].light]];
  }
  return [key("Calmest %@, roughest %@"), zonePhrase(best[0]), zonePhrase(worst[0])];
}

/** Weakest and strongest mean wind over the lake, the strongest gust and the mean direction. */
export function windSummary(hour) {
  const speeds = hour.wind.map((w) => w.speedMs).filter((v) => v != null);
  if (!speeds.length) return null;
  let x = 0;
  let y = 0;
  for (const w of hour.wind) {
    if (w.fromDeg == null || w.speedMs == null) continue;
    const r = (w.fromDeg * Math.PI) / 180;
    x += Math.sin(r) * w.speedMs;
    y += Math.cos(r) * w.speedMs;
  }
  const gusts = hour.wind.map((w) => w.gustMs).filter((v) => v != null);
  return {
    min: Math.min(...speeds), max: Math.max(...speeds), gust: gusts.length ? Math.max(...gusts) : Math.max(...speeds),
    fromDeg: x || y ? ((Math.atan2(x, y) * 180) / Math.PI + 360) % 360 : null,
  };
}

export const maxWave = (hour) => (hour.wavesCm.length ? Math.max(...hour.wavesCm) / 100 : null);

// ---- The grid -------------------------------------------------------------------

export function gridEdges(grid) {
  return {
    north: grid.south + (grid.rows - 1) * grid.dLat + grid.dLat / 2,
    south: grid.south - grid.dLat / 2,
    west: grid.west - grid.dLon / 2,
    east: grid.west + (grid.cols - 1) * grid.dLon + grid.dLon / 2,
  };
}

/** The coordinate of a water cell's centre. */
export function cellCoordinate(grid, i) {
  const flat = grid.cells[i];
  return { lat: grid.south + Math.floor(flat / grid.cols) * grid.dLat, lon: grid.west + (flat % grid.cols) * grid.dLon };
}

const cellIndex = new WeakMap();
function byFlat(grid) {
  let map = cellIndex.get(grid);
  if (!map) {
    map = new Map(grid.cells.map((flat, i) => [flat, i]));
    cellIndex.set(grid, map);
  }
  return map;
}

/** The water cell at a coordinate, or null on land. */
export function cellAt(grid, { lat, lon }) {
  const col = Math.round((lon - grid.west) / grid.dLon);
  const row = Math.round((lat - grid.south) / grid.dLat);
  if (col < 0 || col >= grid.cols || row < 0 || row >= grid.rows) return null;
  return byFlat(grid).get(row * grid.cols + col) ?? null;
}

/** The water cell at the point, or the nearest one for a point on the shore. */
export function nearestCell(grid, c) {
  const found = cellAt(grid, c);
  if (found != null) return found;
  const k = Math.cos((c.lat * Math.PI) / 180);
  let best = 0;
  let bestD = Infinity;
  for (let i = 0; i < grid.cells.length; i++) {
    const p = cellCoordinate(grid, i);
    const d = ((p.lon - c.lon) * k) ** 2 + (p.lat - c.lat) ** 2;
    if (d < bestD) [best, bestD] = [i, d];
  }
  return best;
}

// ---- Colours (LakeRaster) -----------------------------------------------------------

export const RGB = { green: [52, 199, 89], amber: [255, 149, 0], red: [255, 59, 48] };
const CALM = [120, 205, 255];
const YELLOW = [255, 204, 0];
const PURPLE = [175, 82, 222];

/** When the whole lake is red the squares stay readable but faded to grey. */
export function greyed([r, g, b]) {
  const grey = 0.3 * r + 0.59 * g + 0.11 * b;
  return [grey + (r - grey) * 0.25, grey + (g - grey) * 0.25, grey + (b - grey) * 0.25];
}

/** Calm blue, yellow at the amber limit, red at the red limit, purple beyond. */
export function ramp(value, amber, red) {
  const stops = [[0, CALM], [amber, YELLOW], [red, RGB.red], [red * 1.6, PURPLE]];
  if (!(value > 0)) return CALM;
  for (let i = 1; i < stops.length; i++) {
    if (value <= stops[i][0]) {
      const [a, ca] = stops[i - 1];
      const [b, cb] = stops[i];
      const t = (value - a) / (b - a);
      return ca.map((v, j) => v + (cb[j] - v) * t);
    }
  }
  return PURPLE;
}

/** Each cell's colour for a layer ("light", "waves" or "wind"). */
export function cellColours(view, hour, layer, limits) {
  const { grid } = view;
  return grid.cells.map((_, i) => {
    if (layer === "waves") return ramp(hour.wavesCm[i] / 100, limits.value("waveAmber"), limits.value("waveRed"));
    if (layer === "wind") return ramp(hour.wind[grid.cellPoint[i]]?.speedMs ?? 0, limits.value("windAmber"), limits.value("windRed"));
    const c = RGB[hour.lights[i]] ?? RGB.green;
    return hour.lakeWide.light === "red" ? greyed(c) : c;
  });
}

/**
 * The cells as RGBA pixels, one per cell, north up, with the colours spread
 * two cells onto the land so the smoothing does not fade the water at the shore.
 */
export function rasterPixels(view, colours) {
  const { cols: w, rows: h, cells } = view.grid;
  const px = new Uint8ClampedArray(w * h * 4);
  const water = new Uint8Array(w * h);
  cells.forEach((flat, i) => {
    const p = (h - 1 - Math.floor(flat / w)) * w + (flat % w);
    water[p] = 1;
    px.set([colours[i][0], colours[i][1], colours[i][2], 255], p * 4);
  });
  for (let pass = 0; pass < 2; pass++) {
    const filled = water.slice();
    for (let y = 0; y < h; y++) {
      for (let x = 0; x < w; x++) {
        if (filled[y * w + x]) continue;
        let r = 0;
        let g = 0;
        let b = 0;
        let n = 0;
        for (const [dx, dy] of [[-1, 0], [1, 0], [0, -1], [0, 1]]) {
          const nx = x + dx;
          const ny = y + dy;
          if (nx < 0 || ny < 0 || nx >= w || ny >= h || !filled[ny * w + nx]) continue;
          const j = (ny * w + nx) * 4;
          r += px[j];
          g += px[j + 1];
          b += px[j + 2];
          n++;
        }
        if (!n) continue;
        px.set([r / n, g / n, b / n, 255], (y * w + x) * 4);
        water[y * w + x] = 1;
      }
    }
  }
  return { width: w, height: h, data: px };
}

// ---- Routes (Route.swift) ------------------------------------------------------------

/** Metres between two coordinates. */
export function distanceM(a, b) {
  const r = 6371000;
  const p1 = (a.lat * Math.PI) / 180;
  const p2 = (b.lat * Math.PI) / 180;
  const dp = p2 - p1;
  const dl = ((b.lon - a.lon) * Math.PI) / 180;
  const x = Math.sin(dp / 2) ** 2 + Math.cos(p1) * Math.cos(p2) * Math.sin(dl / 2) ** 2;
  return 2 * r * Math.asin(Math.sqrt(x));
}

/** Compass heading from a to b, degrees from north, clockwise. */
export function heading(a, b) {
  const dx = (b.lon - a.lon) * Math.cos((a.lat * Math.PI) / 180);
  const dy = b.lat - a.lat;
  return ((Math.atan2(dx, dy) * 180) / Math.PI + 360) % 360;
}

const lerp = (a, b, t) => ({ lat: a.lat + (b.lat - a.lat) * t, lon: a.lon + (b.lon - a.lon) * t });

/** How the wind (or the waves it makes) meets the boat: "head", "tail" or "cross". */
export function windRelation(headingDeg, windFromDeg) {
  const off = Math.abs((((windFromDeg - headingDeg + 540) % 360) + 360) % 360 - 180);
  return off < 45 ? "head" : off > 135 ? "tail" : "cross";
}
export const RELATION_WIND = { head: key("headwind"), tail: key("tailwind"), cross: key("crosswind") };
export const RELATION_WAVES = { head: key("head sea"), tail: key("following sea"), cross: key("waves from the side") };

/** Changes to a route's turning points; the first is the launch point and stays (RouteEdit). */
export const RouteEdit = {
  closeDistanceM: 50,
  isLoop(points) {
    return points.length >= 3 && distanceM(points[0], points[points.length - 1]) < 1;
  },
  /** Adds a point; one near the start, after at least two turning points, closes the loop. */
  add(point, points) {
    if (RouteEdit.isLoop(points)) return points;
    if (points.length >= 3 && distanceM(point, points[0]) <= RouteEdit.closeDistanceM) return [...points, points[0]];
    return [...points, point];
  },
  close(points) {
    return points.length >= 3 && !RouteEdit.isLoop(points) ? [...points, points[0]] : points;
  },
  /** Opens a loop again: the route ends at its last turning point. */
  open(points) {
    return RouteEdit.isLoop(points) ? points.slice(0, -1) : points;
  },
  /** Removes a turning point; a loop left with one turning point opens again. */
  remove(index, points) {
    if (index <= 0 || index >= points.length) return points;
    const loop = RouteEdit.isLoop(points);
    const out = points.filter((_, i) => i !== index);
    if (loop && out.length < 4) out.pop();
    return out;
  },
  insert(point, index, points) {
    if (index <= 0 || index >= points.length) return points;
    return [...points.slice(0, index), point, ...points.slice(index)];
  },
  move(index, point, points) {
    if (index <= 0 || index >= points.length) return points;
    return points.map((p, i) => (i === index ? point : p));
  },
};

/** The whole outing in metres, back to the start when rowed out and back. */
export function routeLength(points, outAndBack) {
  let m = 0;
  for (let i = 1; i < points.length; i++) m += distanceM(points[i - 1], points[i]);
  return outAndBack ? m * 2 : m;
}

export const STEP_M = 150;
/** Slowest speed over ground counted where the current is about as fast as the boat (RoutePlanner.minGroundMs). */
export const MIN_GROUND_MS = 0.2;
/** The river line farther than this from a point of the route says nothing about its current (RoutePlanner.flowNearM). */
const FLOW_NEAR_M = 300;

/** The river line (pointing downstream, [lon, lat] points) as pieces from one point to the next. */
function flowPieces(flow) {
  return (flow ?? []).flatMap((line) => {
    const points = line.filter((x) => x.length >= 2).map(([lon, lat]) => ({ lat, lon }));
    return points.slice(1).map((b, i) => [points[i], b]);
  });
}

/** The cosine between the route's heading and the river's flow at the nearest piece of the river line; 0 away from it. */
export function withCurrent(c, headingDeg, pieces) {
  let nearest = null;
  for (const piece of pieces) {
    const d = distanceM(c, lerp(piece[0], piece[1], 0.5));
    if (!nearest || d < nearest.d) nearest = { piece, d };
  }
  if (!nearest || nearest.d >= FLOW_NEAR_M + distanceM(nearest.piece[0], nearest.piece[1]) / 2) return 0;
  return Math.cos(((headingDeg - heading(nearest.piece[0], nearest.piece[1])) * Math.PI) / 180);
}

/** The route's geometry, worked out once; plans for other start times reuse it (RoutePlanner). */
export function routePlanner(view, waypoints, outAndBack) {
  if (waypoints.length < 2 || !view.grid.cells.length) return null;
  const path = outAndBack ? [...waypoints, ...waypoints.slice(0, -1).reverse()] : waypoints;
  const points = [];
  const pieces = [];
  let travelled = 0;
  const flow = flowPieces(view.section?.flow);
  for (let s = 1; s < path.length; s++) {
    const a = path[s - 1];
    const b = path[s];
    const length = distanceM(a, b);
    if (length <= 1) continue;
    const hd = heading(a, b);
    const steps = Math.max(1, Math.ceil(length / STEP_M));
    for (let k = 0; k < steps; k++) {
      const mid = lerp(a, b, (k + 0.5) / steps);
      points.push({
        coordinate: mid, distanceM: travelled + (length * (k + 0.5)) / steps, cell: nearestCell(view.grid, mid), headingDeg: hd,
        // The length this point stands for, and how much of the current runs along it: 1 downstream, -1 upstream.
        stepM: length / steps, withCurrent: withCurrent(mid, hd, flow),
      });
      pieces.push([lerp(a, b, k / steps), lerp(a, b, (k + 1) / steps)]);
    }
    travelled += length;
  }
  if (!points.length) return null;
  return { view, path, points, pieces, distanceM: travelled };
}

/**
 * What the route meets when started at `start` at a pace in seconds per 500 m (RoutePlanner.plan).
 * On rivers `currentMs` (the club's gauge, mid-river) speeds the boat up downstream and slows it
 * down upstream: over ground, still-water speed ± current.
 */
export function planRoute(planner, start, pace, currentMs = null) {
  const speed = 500 / Math.max(pace, 60);
  const { view } = planner;
  const current = view.section ? currentMs ?? 0 : 0;
  const hours = view.hours;
  const last = new Date(hours[hours.length - 1].time).getTime();
  let beyond = false;
  let noHeadway = false;
  let elapsed = 0;
  const stops = planner.points.map((p) => {
    let ground = speed + current * p.withCurrent;
    if (ground < MIN_GROUND_MS) {
      noHeadway = true;
      ground = MIN_GROUND_MS;
    }
    const time = new Date(start.getTime() + (elapsed + p.stepM / 2 / ground) * 1000);
    elapsed += p.stepM / ground;
    let h = 0;
    hours.forEach((x, i) => {
      if (new Date(x.time) <= time) h = i;
    });
    if (time.getTime() >= last + 3600 * 1000) beyond = true;
    const hour = hours[h];
    const wind = hour.wind[view.grid.cellPoint[p.cell]];
    return {
      coordinate: p.coordinate, distanceM: p.distanceM, time, cell: p.cell,
      light: worse(hour.lights[p.cell], hour.lakeWide.light), waveM: hour.wavesCm[p.cell] / 100,
      windMs: wind?.speedMs ?? null, gustMs: wind?.gustMs ?? null,
      relation: wind?.fromDeg == null ? null : windRelation(p.headingDeg, wind.fromDeg),
    };
  });
  const end = new Date(start.getTime() + elapsed * 1000);
  const worst = stops.reduce((w, s) => worse(w, s.light), "green");
  const maxWaveM = Math.max(0, ...stops.map((s) => s.waveM));
  return { start, end, distanceM: planner.distanceM, stops, segments: segments(stops, planner.pieces), beyondForecast: beyond, worstLight: worst, maxWaveM,
    currentMs: view.section ? currentMs : null, noHeadway };
}

function segments(stops, pieces) {
  const out = [];
  let current = [];
  let l = null;
  stops.forEach((stop, i) => {
    if (stop.light !== l && l && current.length) {
      out.push({ points: current, light: l });
      current = [current[current.length - 1]];
    }
    if (!current.length) current = [pieces[i][0]];
    current.push(pieces[i][1]);
    l = stop.light;
  });
  if (l && current.length > 1) out.push({ points: current, light: l });
  return out;
}

/** The stop with the worst light and, among those, the highest waves. */
export function roughest(plan) {
  return plan.stops.reduce((best, s) => (!best || RANK[s.light] > RANK[best.light] || (s.light === best.light && s.waveM > best.waveM) ? s : best), null);
}

/** The start within the forecast that meets the best conditions: best worst light, lowest waves, earliest. */
export function bestStart(planner, pace, from = new Date(), currentMs = null) {
  let best = null;
  for (const hour of planner.view.hours) {
    const t = new Date(hour.time);
    if (t.getTime() + 3600 * 1000 <= from.getTime()) continue;
    const plan = planRoute(planner, t < from ? from : t, pace, currentMs);
    if (plan.beyondForecast) continue;
    const score = [RANK[plan.worstLight], Math.round(plan.maxWaveM * 100), plan.start.getTime()];
    if (!best || compare(score, best.score) < 0) best = { plan, score };
  }
  return best?.plan ?? null;
}

function compare(a, b) {
  for (let i = 0; i < a.length; i++) if (a[i] !== b[i]) return a[i] - b[i];
  return 0;
}

/** Whether plan `a` meets better conditions than `b`: the worst light, then the waves in cm. */
export const plansBetter = (a, b) => compare([RANK[a.worstLight], Math.round(a.maxWaveM * 100)], [RANK[b.worstLight], Math.round(b.maxWaveM * 100)]) < 0;

/** "2:15" per 500 m. */
export function pace(seconds) {
  const s = Math.round(seconds);
  return `${Math.floor(s / 60)}:${String(s % 60).padStart(2, "0")}`;
}
